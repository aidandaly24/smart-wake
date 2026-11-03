import Foundation

public enum WakePlanningError: Error, Equatable, Sendable {
    case invalidClockTime
    case invalidRetryLimit
    case invalidPreferredDuration
    case invalidDate
    case alarmPermissionRequired
    case calendarCouldNotResolveDate
}

/// A local clock selection. An armed plan stores absolute dates, not this recurring time.
public struct ClockTime: Codable, Equatable, Hashable, Sendable {
    public let hour: Int
    public let minute: Int

    public init(hour: Int, minute: Int) throws {
        guard (0...23).contains(hour), (0...59).contains(minute) else {
            throw WakePlanningError.invalidClockTime
        }
        self.hour = hour
        self.minute = minute
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            hour: container.decode(Int.self, forKey: .hour),
            minute: container.decode(Int.self, forKey: .minute)
        )
    }
}

public enum WakeMode: Codable, Hashable, Sendable {
    case manual(ClockTime)
    case smart
}

public enum AlarmAuthorization: String, Codable, Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

/// Optional historical sleep interval. This is not a medical assessment.
/// Adapters should merge overlapping stage samples before creating an entry.
public struct SleepHistoryEntry: Codable, Equatable, Sendable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

public enum AlarmKind: String, Codable, Equatable, Sendable {
    case primary
    case retry
    case fallback
}

public struct PlannedAlarm: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let fireDate: Date
    public let kind: AlarmKind
    public let retryIndex: Int?

    init(fireDate: Date, kind: AlarmKind, retryIndex: Int? = nil) {
        self.id = UUID()
        self.fireDate = fireDate
        self.kind = kind
        self.retryIndex = retryIndex
    }
}

public enum PlanningBasis: String, Codable, Equatable, Sendable {
    case manualSelection
    case bedtimeAndRecentHistory
    case bedtimeAndPreferredDuration
    case fallbackWithoutRecentBedtime
}

public struct WakePlan: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let mode: WakeMode
    public let createdAt: Date
    public let timeZoneIdentifier: String
    public let targetDate: Date
    public let latestWakeDate: Date?
    public let events: [PlannedAlarm]
    public let basis: PlanningBasis
    /// A planning preference informed by historical durations, not "enough sleep."
    public let sleepDurationUsed: TimeInterval?

    public var eventIDs: [UUID] { events.map(\.id) }

    init(
        mode: WakeMode,
        createdAt: Date,
        timeZoneIdentifier: String,
        targetDate: Date,
        latestWakeDate: Date?,
        events: [PlannedAlarm],
        basis: PlanningBasis,
        sleepDurationUsed: TimeInterval?
    ) {
        self.id = UUID()
        self.mode = mode
        self.createdAt = createdAt
        self.timeZoneIdentifier = timeZoneIdentifier
        self.targetDate = targetDate
        self.latestWakeDate = latestWakeDate
        self.events = events
        self.basis = basis
        self.sleepDurationUsed = sleepDurationUsed
    }
}
