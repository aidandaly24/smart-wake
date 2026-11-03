import Foundation
import Combine
import SmartWakeCore
import WatchConnectivity

/// Paired-device transport only. No web service, analytics, or cloud persistence.
@MainActor
final class WatchBridge: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var status = "No Watch summary yet. Manual alarms still work."
    @Published private(set) var history: [SleepHistoryEntry] = []
    @Published private(set) var bedtime: Date?
    @Published private(set) var lastUpdated: Date?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        // Serialize on the callback queue to cross the actor boundary with Sendable Data.
        guard let data = try? PropertyListSerialization.data(fromPropertyList: context, format: .binary, options: 0) else { return }
        Task { @MainActor [weak self] in self?.receive(data) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: applicationContext, format: .binary, options: 0) else { return }
        Task { @MainActor [weak self] in self?.receive(data) }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    private func receive(_ data: Data) {
        guard let payload = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              payload["kind"] as? String == "watchSummary",
              payload["schemaVersion"] as? Int == 1,
              let generatedAt = payload["generatedAt"] as? Double,
              generatedAt.isFinite else { return }
        let generated = Date(timeIntervalSince1970: generatedAt)
        let now = Date()
        guard generated <= now.addingTimeInterval(300), generated > now.addingTimeInterval(-86_400),
              lastUpdated.map({ generated > $0 }) ?? true else { return }
        let intervals = payload["sleepIntervals"] as? [[String: Double]] ?? []
        // HealthKit may return stages, overlaps, multiple sources and awake gaps.
        // Merge overlaps, then sum actual asleep time by noon-to-noon sleep day.
        var spans: [(Date, Date)] = intervals.compactMap { item in
            guard let start = item["start"], let end = item["end"], start.isFinite, end.isFinite,
                  start < end, end <= now.timeIntervalSince1970,
                  start > now.addingTimeInterval(-15 * 86_400).timeIntervalSince1970 else { return nil }
            return (Date(timeIntervalSince1970: start), Date(timeIntervalSince1970: end))
        }.sorted { $0.0 < $1.0 }
        var merged: [(Date, Date)] = []
        for span in spans {
            if let last = merged.last, span.0 <= last.1 {
                merged[merged.count - 1].1 = max(last.1, span.1)
            } else { merged.append(span) }
        }
        spans.removeAll()
        var nights: [Date: (start: Date, seconds: Double)] = [:]
        let calendar = Calendar.current
        for span in merged {
            let night = calendar.startOfDay(for: span.0.addingTimeInterval(-12 * 3600))
            let old = nights[night]
            nights[night] = (min(old?.start ?? span.0, span.0), (old?.seconds ?? 0) + span.1.timeIntervalSince(span.0))
        }
        history = nights.values.map { SleepHistoryEntry(start: $0.start, end: $0.start.addingTimeInterval($0.seconds)) }
        bedtime = nil
        if let stamp = payload["bedtimeAt"] as? Double, stamp.isFinite {
            let candidate = Date(timeIntervalSince1970: stamp)
            if candidate <= now, candidate > now.addingTimeInterval(-18 * 3600) { bedtime = candidate }
        }
        lastUpdated = generated
        let motion = payload["motion"] as? [String: Any]
        let motionAvailable = motion?["available"] as? Bool ?? false
        status = history.isEmpty
            ? "Watch connected; no readable sleep history. Health access may be off or records may not exist yet."
            : "Received \(history.count) nights. Motion samples \(motionAvailable ? "available" : "unavailable"). History informs tomorrow's target, not live sleep stage."
    }
}
