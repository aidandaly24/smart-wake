import Foundation

/// Creates a finite batch of one-shot alarms. It does not schedule OS notifications.
///
/// The caller must recheck OS permission and arm the complete batch transactionally.
/// A stored plan retains its original dates across travel or daylight saving changes.
public struct WakePlanner: Sendable {
    public static let maximumRetryLimit = 10
    public static let retryInterval: TimeInterval = 60
    public static let minimumSchedulingLeadTime: TimeInterval = 60

    public let retryLimit: Int
    public let preferredSleepDuration: TimeInterval

    public init(
        retryLimit: Int = 10,
        preferredSleepDuration: TimeInterval = 8 * 60 * 60
    ) throws {
        guard (0...Self.maximumRetryLimit).contains(retryLimit) else {
            throw WakePlanningError.invalidRetryLimit
        }
        guard preferredSleepDuration.isFinite,
              (3 * 60 * 60...12 * 60 * 60).contains(preferredSleepDuration) else {
            throw WakePlanningError.invalidPreferredDuration
        }
        self.retryLimit = retryLimit
        self.preferredSleepDuration = preferredSleepDuration
    }

    public func makePlan(
        mode: WakeMode,
        now: Date,
        timeZone: TimeZone,
        bedtime: Date? = nil,
        history: [SleepHistoryEntry] = [],
        authorization: AlarmAuthorization
    ) throws -> WakePlan {
        guard authorization == .authorized else {
            throw WakePlanningError.alarmPermissionRequired
        }
        guard now.timeIntervalSinceReferenceDate.isFinite else {
            throw WakePlanningError.invalidDate
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        switch mode {
        case .manual(let clockTime):
            let target = try nextOccurrence(of: clockTime, after: now, calendar: calendar)
            return WakePlan(
                mode: mode,
                createdAt: now,
                timeZoneIdentifier: timeZone.identifier,
                targetDate: target,
                latestWakeDate: nil,
                events: makeEvents(target: target, deadline: nil),
                basis: .manualSelection,
                sleepDurationUsed: nil
            )

        case .smart:
            let latestTime = try ClockTime(hour: 8, minute: 15)
            let earliestTime = try ClockTime(hour: 6, minute: 30)
            let deadline = try nextOccurrence(of: latestTime, after: now, calendar: calendar)
            let earliest = try occurrence(
                of: earliestTime,
                onDayContaining: deadline,
                calendar: calendar
            )

            let target: Date
            let basis: PlanningBasis
            let duration: TimeInterval?
            if let bedtime,
               bedtime.timeIntervalSinceReferenceDate.isFinite,
               bedtime <= now,
               now.timeIntervalSince(bedtime) <= 18 * 60 * 60 {
                let historicDuration = recentMedianDuration(history: history, now: now)
                let chosenDuration = historicDuration ?? preferredSleepDuration
                let proposed = bedtime.addingTimeInterval(chosenDuration)
                // Leave time for platform scheduling if the target is imminent or
                // elapsed. The deadline still wins over this preferred lead time.
                // At the boundary, the single deadline alarm is also the primary wake.
                let leadDate = now.addingTimeInterval(Self.minimumSchedulingLeadTime)
                target = min(deadline, max(earliest, max(proposed, leadDate)))
                basis = historicDuration == nil
                    ? .bedtimeAndPreferredDuration : .bedtimeAndRecentHistory
                duration = chosenDuration
            } else {
                // No current bedtime or missing/stale Watch context: never invent a
                // sleep-stage signal. Start with the mandatory 08:15 fallback.
                target = deadline
                basis = .fallbackWithoutRecentBedtime
                duration = nil
            }

            return WakePlan(
                mode: mode,
                createdAt: now,
                timeZoneIdentifier: timeZone.identifier,
                targetDate: target,
                latestWakeDate: deadline,
                events: makeEvents(target: target, deadline: deadline),
                basis: basis,
                sleepDurationUsed: duration
            )
        }
    }

    private func makeEvents(target: Date, deadline: Date?) -> [PlannedAlarm] {
        var events: [PlannedAlarm] = []
        if let deadline {
            // The deadline is the latest *initial* wake, not a cutoff for
            // follow-ups. Use one event when the target and fallback coincide.
            if target < deadline {
                events.append(PlannedAlarm(fireDate: target, kind: .primary))
                if retryLimit > 0 {
                    for attempt in 1...retryLimit {
                        let date = target.addingTimeInterval(Double(attempt) * Self.retryInterval)
                        if date >= deadline { break }
                        events.append(PlannedAlarm(fireDate: date, kind: .retry, retryIndex: attempt))
                    }
                }
            }
            events.append(PlannedAlarm(fireDate: deadline, kind: .fallback))
            if retryLimit > 0 {
                for attempt in 1...retryLimit {
                    events.append(PlannedAlarm(
                        fireDate: deadline.addingTimeInterval(Double(attempt) * Self.retryInterval),
                        kind: .retry, retryIndex: attempt
                    ))
                }
            }
        } else {
            events.append(PlannedAlarm(fireDate: target, kind: .primary))
            if retryLimit > 0 {
                for attempt in 1...retryLimit {
                    events.append(PlannedAlarm(
                        fireDate: target.addingTimeInterval(Double(attempt) * Self.retryInterval),
                        kind: .retry, retryIndex: attempt
                    ))
                }
            }
        }
        return events
    }

    private func nextOccurrence(
        of time: ClockTime,
        after now: Date,
        calendar: Calendar
    ) throws -> Date {
        let today = try occurrence(of: time, onDayContaining: now, calendar: calendar)
        if today > now { return today }

        // Add a calendar day rather than 86,400 seconds. Resolving from local
        // midnight also prevents accidentally selecting the second DST occurrence.
        guard let tomorrow = calendar.date(
            byAdding: .day, value: 1, to: calendar.startOfDay(for: now)
        ) else { throw WakePlanningError.calendarCouldNotResolveDate }
        return try occurrence(of: time, onDayContaining: tomorrow, calendar: calendar)
    }

    private func occurrence(
        of time: ClockTime,
        onDayContaining day: Date,
        calendar: Calendar
    ) throws -> Date {
        var components = DateComponents()
        components.hour = time.hour
        components.minute = time.minute
        components.second = 0
        guard let result = calendar.nextDate(
            after: calendar.startOfDay(for: day).addingTimeInterval(-1),
            matching: components,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        ) else { throw WakePlanningError.calendarCouldNotResolveDate }
        return result
    }

    private func recentMedianDuration(history: [SleepHistoryEntry], now: Date) -> TimeInterval? {
        let cutoff = now.addingTimeInterval(-14 * 24 * 60 * 60)
        // The range is a data-quality filter, not a recommended sleep range.
        // Ignore duplicate intervals and overlaps rather than weighting one night
        // several times when a HealthKit adapter accidentally repeats samples.
        let candidates = history.filter {
            $0.start.timeIntervalSinceReferenceDate.isFinite &&
            $0.end.timeIntervalSinceReferenceDate.isFinite &&
            $0.end <= now && $0.end >= cutoff &&
            (3 * 60 * 60...12 * 60 * 60).contains($0.duration)
        }.sorted { $0.start < $1.start }
        var accepted: [SleepHistoryEntry] = []
        for entry in candidates {
            if let previous = accepted.last, entry.start < previous.end { continue }
            accepted.append(entry)
        }
        let durations = accepted.map(\.duration).sorted()
        guard durations.count >= 3 else { return nil }
        let middle = durations.count / 2
        return durations.count.isMultiple(of: 2)
            ? (durations[middle - 1] + durations[middle]) / 2
            : durations[middle]
    }
}
