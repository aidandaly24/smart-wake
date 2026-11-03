import Combine
import Foundation

@MainActor
final class WatchModel: ObservableObject {
    @Published private(set) var bedtimeAt: Date?
    @Published private(set) var recordingWindow: RecordingWindow?
    @Published private(set) var sleep = WatchSleepSummary.notRequested
    @Published private(set) var motion = WatchMotionSummary(status: .unknown)
    @Published private(set) var isBusy = false
    @Published private(set) var healthRequestAttempted: Bool

    private let health = WatchHealthReader()
    private let recorder = WatchMotionRecorder()
    private let defaults: UserDefaults
    private static let bedtimeKey = "watch.bedtimeAt"
    private static let windowKey = "watch.motionRecordingWindow"
    private static let healthAttemptKey = "watch.healthRequestAttempted"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        bedtimeAt = defaults.object(forKey: Self.bedtimeKey) as? Date
        healthRequestAttempted = defaults.bool(forKey: Self.healthAttemptKey)
        if let data = defaults.data(forKey: Self.windowKey) {
            recordingWindow = try? JSONDecoder().decode(RecordingWindow.self, from: data)
        }
    }

    var recordingRequestedForFuture: Bool {
        guard let recordingWindow else { return false }
        // No stop API exists. Avoid repeatedly extending an already requested overnight capture.
        return recordingWindow.end > .now
            && motion.status != .denied && motion.status != .restricted
            && motion.status != .unsupported
    }

    var canRequestRecording: Bool {
        !isBusy && !recordingRequestedForFuture
            && motion.status != .denied && motion.status != .restricted
            && motion.status != .unsupported && motion.status != .unknown
    }

    func markBedtime(now: Date = .now) {
        bedtimeAt = now
        defaults.set(now, forKey: Self.bedtimeKey)
    }

    func clearBedtime() {
        bedtimeAt = nil
        defaults.removeObject(forKey: Self.bedtimeKey)
    }

    func refreshCapability() async {
        guard !isBusy else { return }
        let result = await recorder.availability()
        guard !isBusy else { return }
        if result.status == .denied || result.status == .restricted {
            // A denied first consent prompt must not lock the Record button for the next 8 hours
            // after the user later enables permission. This forgets metadata, not system samples.
            if let recordingWindow, recordingWindow.end > .now {
                self.recordingWindow = nil
                defaults.removeObject(forKey: Self.windowKey)
            }
        }
        // Returning from the permission prompt must reflect denial instead of asserting recording.
        if result.status != .ready || motion.sampleCount == 0 {
            if result.status == .ready, recordingRequestedForFuture {
                motion = WatchMotionSummary(status: .recordingRequested, window: recordingWindow)
            } else {
                motion = result
            }
        }
    }

    func requestSleepAccess() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        healthRequestAttempted = true
        defaults.set(true, forKey: Self.healthAttemptKey)
        guard await health.requestAccess() else {
            sleep = WatchSleepSummary(
                status: .error, intervals: [],
                message: "The Health request did not complete. Health may be unavailable; try again on the watch."
            )
            return
        }
        sleep = await health.readLastFourteenDays()
    }

    func recordMotion(hours: Int) async {
        guard canRequestRecording else { return }
        isBusy = true
        defer { isBusy = false }
        let result = await recorder.requestRecording(duration: Double(hours) * 60 * 60)
        motion = result.summary
        if let window = result.requestedWindow {
            recordingWindow = window
            if let data = try? JSONEncoder().encode(window) {
                defaults.set(data, forKey: Self.windowKey)
            }
        }
    }

    func refreshSummary() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        await readCurrentSummary()
    }

    func sendSummary(using connection: WatchPhoneConnection) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        // Refresh before packaging so generatedAt isn't a misleading time for an old in-memory read.
        await readCurrentSummary()
        connection.send(WatchSummary(
            generatedAt: .now, bedtimeAt: bedtimeAt, sleep: sleep, motion: motion
        ))
    }

    private func readCurrentSummary() async {
        if healthRequestAttempted {
            sleep = await health.readLastFourteenDays()
        }
        motion = await recorder.summarize(window: recordingWindow)
    }
}
