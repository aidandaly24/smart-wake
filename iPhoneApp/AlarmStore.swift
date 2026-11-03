import AlarmKit
import Combine
import Foundation
import SmartWakeCore
import SwiftUI

@MainActor
final class AlarmStore: ObservableObject {
    static let shared = AlarmStore()
    @Published private(set) var wakeSession: WakeSession?
    var plan: WakePlan? { wakeSession?.plan }
    @Published private(set) var busy = false
    @Published private(set) var status = "Set a time, then arm your alarm."
    @Published private(set) var scheduledCount = 0
    @Published var showPuzzle = false
    @Published var bedtime: Date?
    let watch = WatchBridge()
    private let manager = AlarmManager.shared
    private var observation: Task<Void, Never>?
    private var watchObservation: AnyCancellable?
    private var cancellationRequested = false

    var effectiveBedtime: Date? {
        let now = Date()
        return [bedtime, watch.bedtime].compactMap { $0 }
            .filter { $0 <= now && now.timeIntervalSince($0) <= 18 * 3600 }.max()
    }
    private let persistenceURL: URL

    private init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        persistenceURL = directory.appendingPathComponent("wake-plan.json")
        if let data = try? Data(contentsOf: persistenceURL) {
            do { wakeSession = try JSONDecoder().decode(WakeSession.self, from: data) }
            catch { status = "Saved plan could not be read. Use emergency stop to clear this app's alarms before arming again." }
        }
        watchObservation = watch.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        observation = Task { [weak self] in
            for await alarms in AlarmManager.shared.alarmUpdates {
                guard let self else { return }
                self.scheduledCount = alarms.count
            }
        }
        refresh()
    }

    func markBedtime() { bedtime = Date() }

    func arm(manualTime: Date?, smart: Bool, gameKind: WakeGameKind? = nil,
             replacingSessionID: UUID? = nil) async {
        guard !busy else { return }
        if let replacingSessionID {
            guard plan?.id == replacingSessionID else {
                status = "The saved alarm changed. Review it before updating."
                return
            }
        } else if plan != nil {
            status = "Choose Update wake-up to replace the saved alarm."
            return
        }
        busy = true
        cancellationRequested = false
        defer {
            busy = false
            if cancellationRequested {
                cancellationRequested = false
                cancelAll()
            }
        }
        var replacementStarted = false
        var oldAlarmRemoved = false
        do {
            // A confirmed update may replace the saved session. Unowned/orphaned
            // alarms still require the explicit emergency-stop recovery flow.
            let existingAlarms = try manager.alarms
            guard replacingSessionID != nil || existingAlarms.isEmpty else {
                status = "Existing alarms remain. Use emergency stop before replacing them."
                return
            }
            let mode: WakeMode
            if smart { mode = .smart }
            else {
                let parts = Calendar.current.dateComponents([.hour, .minute], from: manualTime ?? Date())
                mode = .manual(try ClockTime(hour: parts.hour ?? 7, minute: parts.minute ?? 0))
            }
            let planningTimeZone = TimeZone.current
            let authorization = try await manager.requestAuthorization()
            guard authorization == .authorized else {
                status = replacingSessionID == nil
                    ? "Alarm permission is off. Nothing was armed. Enable Smart Wake alarms in Settings."
                    : "Alarm permission is off. The existing session was not replaced, but its alarms may not work. Enable permission and keep a separate backup."
                return
            }
            guard !cancellationRequested else { throw ArmError.cancelled }
            let planner = try WakePlanner(retryLimit: 10)
            let proposed = try planner.makePlan(mode: mode, now: Date(), timeZone: planningTimeZone,
                                                bedtime: effectiveBedtime,
                                                history: watch.history, authorization: .authorized)
            if let replacingSessionID {
                guard !cancellationRequested else { throw ArmError.cancelled }
                guard var oldSession = wakeSession, oldSession.plan.id == replacingSessionID else {
                    throw ArmError.sessionChanged
                }
                guard proposed.events.allSatisfy({ $0.fireDate > Date() }) else { throw ArmError.timePassed }
                // One operation owns busy/cancellationRequested throughout. Do not
                // call cancelAll() here: while busy it only requests deferred stop.
                _ = oldSession.cancel()
                try persist(oldSession)
                wakeSession = oldSession
                replacementStarted = true
                for alarm in try manager.alarms { try manager.cancel(id: alarm.id) }
                let remaining = try manager.alarms
                scheduledCount = remaining.count
                guard remaining.isEmpty else { throw ArmError.cancellationIncomplete }
                try clearPersistence()
                wakeSession = nil
                showPuzzle = false
                oldAlarmRemoved = true
            }
            guard !cancellationRequested else { throw ArmError.cancelled }
            // Write the complete ID ledger BEFORE making any external schedule call.
            // A crash mid-arm can then recover/cancel every possibly scheduled alarm.
            let session = WakeSession(plan: proposed, gameKind: gameKind)
            try persist(session)
            wakeSession = session
            var armedIDs: Set<UUID> = []
            // Reserve the deadline and its follow-ups before less critical
            // earlier reminders if AlarmKit runs into its scheduling limit.
            func schedulingPriority(_ event: PlannedAlarm) -> Int {
                if event.kind == .fallback { return 0 }
                if event.kind == .primary { return 1 }
                if let deadline = proposed.latestWakeDate, event.fireDate > deadline { return 2 }
                return 3
            }
            let events = proposed.events.sorted { left, right in
                let leftPriority = schedulingPriority(left)
                let rightPriority = schedulingPriority(right)
                return leftPriority == rightPriority
                    ? left.fireDate < right.fireDate : leftPriority < rightPriority
            }
            do {
                for event in events {
                    guard !cancellationRequested else { throw ArmError.cancelled }
                    guard event.fireDate > Date() else { throw ArmError.timePassed }
                    let alert = AlarmPresentation.Alert(
                        title: event.kind == .fallback ? "Smart Wake · latest wake time" : "Smart Wake · rise & play",
                        stopButton: AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.circle"),
                        secondaryButton: AlarmButton(text: "Play", textColor: .black, systemImageName: "square.grid.2x2.fill"),
                        secondaryButtonBehavior: .custom)
                    let attributes = AlarmAttributes<WakeMetadata>(
                        presentation: AlarmPresentation(alert: alert),
                        metadata: WakeMetadata(sessionID: proposed.id.uuidString), tintColor: .mint)
                    let configuration = AlarmManager.AlarmConfiguration<WakeMetadata>.alarm(
                        schedule: .fixed(event.fireDate), attributes: attributes,
                        secondaryIntent: OpenPuzzleIntent(sessionID: proposed.id.uuidString))
                    _ = try await manager.schedule(id: event.id, configuration: configuration)
                    armedIDs.insert(event.id)
                    guard !cancellationRequested else { throw ArmError.cancelled }
                }
                let registered = Set(try manager.alarms.map(\.id))
                scheduledCount = registered.count
                if armedIDs.isSubset(of: registered) {
                    status = "Registered \(armedIDs.count) alarms. Finish the game to cancel remaining reminders."
                } else {
                    status = "Some alarms could not be verified. Do not rely on this session; use emergency stop, re-arm, and keep a separate backup."
                }
            } catch {
                let updateWarning = oldAlarmRemoved ? "The previous alarm was removed. " : ""
                if let alarms = try? manager.alarms {
                    let registered = Set(alarms.map(\.id))
                    scheduledCount = alarms.count
                    let fallbackPresent = proposed.events.contains {
                        $0.kind == .fallback && registered.contains($0.id)
                    }
                    status = updateWarning + "Only \(alarms.count) alarms are registered; the full plan did not arm. "
                        + (fallbackPresent ? "The fallback is registered. " : "Fallback is not confirmed. ")
                        + "Do not rely on this session. Use emergency stop and keep a separate backup. \(error.localizedDescription)"
                } else {
                    status = updateWarning + "Could not verify which alarms are registered. Do not rely on this session. Use emergency stop and keep a separate backup. \(error.localizedDescription)"
                }
            }
        } catch {
            if oldAlarmRemoved {
                status = "The previous alarm was removed, but its replacement was not armed. Set a backup alarm now. \(error.localizedDescription)"
            } else if replacementStarted {
                status = "Could not finish replacing the alarm. Some previous alarms may remain; no replacement was scheduled. Use emergency stop and keep a separate backup. \(error.localizedDescription)"
            } else {
                status = "Could not arm: \(error.localizedDescription)"
                if replacingSessionID != nil { status += " The existing session was not replaced." }
            }
        }
    }

    func refresh() {
        guard !busy else { return }
        do {
            let alarms = try manager.alarms
            scheduledCount = alarms.count
            if manager.authorizationState == .denied {
                status = "Alarm permission is off. Scheduled alarms are not reliable; enable permission and re-arm."
                return
            }
            if let plan {
                let registered = Set(alarms.map(\.id))
                let expected = Set(plan.events.filter { $0.fireDate > Date() }.map(\.id))
                if wakeSession?.isTerminal == true {
                    status = "Cancellation needs confirmation. Use emergency stop to clear the remaining session."
                } else if !expected.isSubset(of: registered) {
                    let fallbackPresent = plan.events.contains { $0.kind == .fallback && registered.contains($0.id) }
                    status = "Some planned alarms are missing. \(fallbackPresent ? "The fallback is registered. " : "")Do not rely on this session; use emergency stop, re-arm, and keep a separate backup."
                } else if case .smart = plan.mode,
                          let deadline = plan.latestWakeDate, deadline > Date(),
                          plan.events.filter({ $0.kind == .retry && $0.fireDate > deadline }).count < WakePlanner.maximumRetryLimit {
                    status = "This saved plan has fewer than ten follow-ups after the fallback. Use emergency stop and re-arm to update it; keep a separate backup."
                } else {
                    status = "\(alarms.count) alarms remain registered. Complete the puzzle or use emergency stop to clear the session."
                }
                if plan.timeZoneIdentifier != TimeZone.current.identifier {
                    status += " Time zone changed: these alarms keep their original absolute times in \(plan.timeZoneIdentifier)."
                }
                if Date() >= plan.targetDate { beginPuzzle() }
            } else if !alarms.isEmpty {
                status = "System alarms remain without a readable session. Use emergency stop before arming again."
            }
        } catch { status = "Could not verify scheduled alarms. Keep a separate backup alarm." }
    }

    func openPuzzle(sessionID: String) {
        guard plan?.id.uuidString == sessionID else { return }
        beginPuzzle()
    }

    func beginPuzzle() {
        guard !busy else { return }
        guard var session = wakeSession else { return }
        let now = Date()
        guard now >= session.plan.targetDate else {
            status = "The wake-up game unlocks at \(session.plan.targetDate.formatted(date: .omitted, time: .shortened)). Your alarms remain armed."
            showPuzzle = false
            return
        }
        _ = session.beginChallenge(now: now)
        guard saveProgress(session) else { return }
        showPuzzle = true
    }

    func hideSequence() {
        guard var session = wakeSession else { return }
        _ = session.hideSequence()
        saveProgress(session)
    }

    func submit(_ token: MemoryToken) {
        guard !busy else { return }
        guard var session = wakeSession else { return }
        let result = session.submit(token)
        guard saveProgress(session) else { return }
        if case .completed = result { finishPuzzle() }
    }

    func submitGame(_ action: WakeGameAction) {
        guard !busy, var session = wakeSession else { return }
        let result = session.submit(action)
        // Never cancel from transient UI state. Commit solved state and the
        // cancellation ledger first, just as for legacy memory sessions.
        guard saveProgress(session) else { return }
        if case .completed = result { finishPuzzle() }
    }

    @discardableResult
    private func saveProgress(_ session: WakeSession) -> Bool {
        do {
            try persist(session)
            wakeSession = session
            return true
        } catch {
            status = "Could not save puzzle progress. Emergency stop is still available."
            return false
        }
    }

    func finishPuzzle() {
        guard let session = wakeSession, session.state == .completed,
              Date() >= session.plan.targetDate else {
            status = "A future alarm cannot be cleared by playing early. Use Update wake-up or emergency stop if you want to change it."
            return
        }
        cancelAll(completed: true)
    }

    func cancelAll(completed: Bool = false) {
        if busy {
            cancellationRequested = true
            status = "Stopping after the current system scheduling call finishes…"
            if var session = wakeSession {
                _ = session.emergencyExit()
                _ = saveProgress(session)
            }
            return
        }
        busy = true
        defer { busy = false }
        // Persist the user's stop intent before touching the daemon, so an interrupted
        // cancellation never returns to an unfinished puzzle on the next launch.
        if !completed, var session = wakeSession {
            _ = session.emergencyExit()
            _ = saveProgress(session)
        }
        do {
            // The manager returns only this app's alarms. This also clears orphaned IDs.
            let alarms = try manager.alarms
            var failures = 0
            for alarm in alarms {
                do { try manager.cancel(id: alarm.id) }
                catch { failures += 1 }
            }
            let remaining = try manager.alarms
            scheduledCount = remaining.count
            guard remaining.isEmpty else {
                status = "\(remaining.count) alarms remain after \(failures) cancellation errors. Try emergency stop again or stop them in the system alarm UI."
                return
            }
            try clearPersistence()
            wakeSession = nil
            showPuzzle = false
            status = completed ? "Nice work. You're up! All remaining alarms are cancelled." : "Stopped. All this app's alarms are cancelled."
        } catch {
            status = "Could not confirm cancellation: \(error.localizedDescription). Use the system Stop control if an alarm sounds, then retry emergency stop."
        }
    }

    private func persist(_ session: WakeSession) throws {
        let folder = persistenceURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var excluded = URLResourceValues()
        excluded.isExcludedFromBackup = true
        var mutableFolder = folder
        try mutableFolder.setResourceValues(excluded)
        try JSONEncoder().encode(session).write(to: persistenceURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func clearPersistence() throws {
        if FileManager.default.fileExists(atPath: persistenceURL.path) {
            try FileManager.default.removeItem(at: persistenceURL)
        }
    }

    private enum ArmError: LocalizedError {
        case timePassed
        case cancelled
        case sessionChanged
        case cancellationIncomplete
        var errorDescription: String? {
            switch self {
            case .timePassed: return "The selected time passed during scheduling."
            case .cancelled: return "Arming was cancelled."
            case .sessionChanged: return "The saved alarm changed during the update."
            case .cancellationIncomplete: return "The previous alarms could not all be cancelled."
            }
        }
    }
}
