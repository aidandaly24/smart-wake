import Foundation

/// Only these value types cross actor boundaries. Framework objects and raw motion stay local.
struct WatchSleepInterval: Sendable {
    let start: Date
    let end: Date

    var propertyList: [String: Any] {
        ["start": start.timeIntervalSince1970, "end": end.timeIntervalSince1970]
    }

    /// Union overlapping records (including duplicate Health sources), without filling awake gaps.
    static func merging(_ intervals: [WatchSleepInterval]) -> [WatchSleepInterval] {
        let ordered = intervals.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        var merged: [WatchSleepInterval] = []
        for interval in ordered {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = WatchSleepInterval(
                    start: last.start, end: max(last.end, interval.end)
                )
            } else {
                merged.append(interval)
            }
        }
        return merged
    }
}

enum WatchSleepStatus: String, Sendable {
    case notRequested, available, noDataOrNotAuthorized, unavailable, error
}

struct WatchSleepSummary: Sendable {
    let status: WatchSleepStatus
    let intervals: [WatchSleepInterval]
    let message: String

    static let notRequested = WatchSleepSummary(
        status: .notRequested, intervals: [],
        message: "Choose Read sleep history to request read-only access to the last 14 days."
    )
}

struct RecordingWindow: Codable, Sendable {
    let start: Date
    let end: Date
}

enum WatchMotionStatus: String, Sendable {
    case unsupported, notDetermined, denied, restricted, ready, recordingRequested
    case noSamples, available, expired, invalidDuration, unknown
}

struct WatchMotionSummary: Sendable {
    let status: WatchMotionStatus
    let sampleCount: Int
    let window: RecordingWindow?
    let meanAccelerationMagnitudeG: Double?
    let magnitudeStandardDeviationG: Double?

    init(
        status: WatchMotionStatus,
        sampleCount: Int = 0,
        window: RecordingWindow? = nil,
        meanAccelerationMagnitudeG: Double? = nil,
        magnitudeStandardDeviationG: Double? = nil
    ) {
        self.status = status
        self.sampleCount = sampleCount
        self.window = window
        self.meanAccelerationMagnitudeG = meanAccelerationMagnitudeG
        self.magnitudeStandardDeviationG = magnitudeStandardDeviationG
    }

    /// "available" describes retrieved samples, not authorization or hardware support.
    var propertyList: [String: Any] {
        var result: [String: Any] = [
            "available": sampleCount > 0,
            "status": status.rawValue,
            "sampleCount": sampleCount
        ]
        if let window {
            result["windowStart"] = window.start.timeIntervalSince1970
            result["windowEnd"] = window.end.timeIntervalSince1970
        }
        if let meanAccelerationMagnitudeG {
            result["meanAccelerationMagnitudeG"] = meanAccelerationMagnitudeG
        }
        if let magnitudeStandardDeviationG {
            result["magnitudeStandardDeviationG"] = magnitudeStandardDeviationG
        }
        return result
    }

    var message: String {
        switch status {
        case .unsupported: return "Motion recording is not supported on this device."
        case .notDetermined: return "Motion permission has not been decided. Tap Record motion to request it."
        case .denied: return "Motion access is off. You can change Motion & Fitness permissions in Settings."
        case .restricted: return "Motion access is restricted on this device."
        case .ready: return "Motion is available. Recording starts only when you tap Record motion."
        case .recordingRequested: return "Recording requested. Reopen after sleeping to retrieve available samples."
        case .noSamples: return "No motion samples returned yet. Data may be delayed, missing, or unavailable."
        case .available: return "Motion samples summarized on this watch. These are not sleep stages."
        case .expired: return "This recording window is too old. Apple keeps samples for up to three days."
        case .invalidDuration: return "Choose a recording duration between 1 minute and 12 hours."
        case .unknown: return "Motion authorization could not be determined."
        }
    }
}

struct WatchSummary: Sendable {
    let generatedAt: Date
    let bedtimeAt: Date?
    let sleep: WatchSleepSummary
    let motion: WatchMotionSummary

    var propertyList: [String: Any] {
        var result: [String: Any] = [
            "kind": "watchSummary",
            "schemaVersion": 1,
            "generatedAt": generatedAt.timeIntervalSince1970,
            "sleepStatus": sleep.status.rawValue,
            "sleepIntervals": sleep.intervals.map(\.propertyList),
            "motion": motion.propertyList
        ]
        if let bedtimeAt {
            result["bedtimeAt"] = bedtimeAt.timeIntervalSince1970
        }
        return result
    }
}
