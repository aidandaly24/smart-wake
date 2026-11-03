import Foundation
import XCTest
@testable import SmartWakeCore

final class WakePlannerTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func manual(
        _ hour: Int,
        _ minute: Int,
        now: String,
        timeZone: TimeZone? = nil,
        retries: Int = 10
    ) throws -> WakePlan {
        try WakePlanner(retryLimit: retries).makePlan(
            mode: .manual(ClockTime(hour: hour, minute: minute)),
            now: date(now),
            timeZone: timeZone ?? utc,
            authorization: .authorized
        )
    }

    private func smart(
        now: String = "2026-11-02T23:00:00Z",
        bedtime: String? = nil,
        history: [SleepHistoryEntry] = [],
        retries: Int = 10
    ) throws -> WakePlan {
        try WakePlanner(retryLimit: retries).makePlan(
            mode: .smart,
            now: date(now),
            timeZone: utc,
            bedtime: bedtime.map(date),
            history: history,
            authorization: .authorized
        )
    }

    func testInvalidClockValuesAreRejected() {
        for (hour, minute) in [(-1, 0), (24, 0), (7, -1), (7, 60)] {
            XCTAssertThrowsError(try ClockTime(hour: hour, minute: minute)) {
                XCTAssertEqual($0 as? WakePlanningError, .invalidClockTime)
            }
        }
    }

    func testDecodingCannotBypassClockValidation() {
        let data = Data(#"{"hour":99,"minute":0}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ClockTime.self, from: data))
    }

    func testManualChoosesTodayWhenClockTimeIsAhead() throws {
        let plan = try manual(7, 15, now: "2026-11-02T01:00:00Z")
        XCTAssertEqual(plan.targetDate, date("2026-11-02T07:15:00Z"))
        XCTAssertEqual(plan.basis, .manualSelection)
        XCTAssertNil(plan.latestWakeDate)
        XCTAssertNil(plan.sleepDurationUsed)
    }

    func testManualChoosesTomorrowWhenClockTimeHasPassed() throws {
        let plan = try manual(7, 15, now: "2026-11-02T09:00:00Z")
        XCTAssertEqual(plan.targetDate, date("2026-11-03T07:15:00Z"))
    }

    func testManualExactCurrentTimeChoosesNextDay() throws {
        let plan = try manual(7, 15, now: "2026-11-02T07:15:00Z")
        XCTAssertEqual(plan.targetDate, date("2026-11-03T07:15:00Z"))
    }

    func testManualMidnightSelectionUsesNextLocalDate() throws {
        let plan = try manual(0, 5, now: "2026-11-02T23:55:00Z")
        XCTAssertEqual(plan.targetDate, date("2026-11-03T00:05:00Z"))
    }

    func testManualRetriesCrossMidnightUsingAbsoluteMinutes() throws {
        let plan = try manual(23, 58, now: "2026-11-02T20:00:00Z", retries: 3)
        XCTAssertEqual(plan.events.map(\.fireDate), [
            date("2026-11-02T23:58:00Z"), date("2026-11-02T23:59:00Z"),
            date("2026-11-03T00:00:00Z"), date("2026-11-03T00:01:00Z")
        ])
        XCTAssertEqual(plan.events.map(\.kind), [.primary, .retry, .retry, .retry])
    }

    func testSpringGapResolvesToNextExistingTime() throws {
        let zone = TimeZone(identifier: "America/New_York")!
        let plan = try manual(2, 30, now: "2026-03-08T05:00:00Z", timeZone: zone)
        // 02:30 does not exist. Calendar .nextTime selects 03:00 EDT.
        XCTAssertEqual(plan.targetDate, date("2026-03-08T07:00:00Z"))
    }

    func testAutumnRepeatedTimeUsesFirstOccurrence() throws {
        let zone = TimeZone(identifier: "America/New_York")!
        let plan = try manual(1, 30, now: "2026-11-01T04:00:00Z", timeZone: zone)
        XCTAssertEqual(plan.targetDate, date("2026-11-01T05:30:00Z"))
    }

    func testAfterFirstRepeatedTimeDoesNotChooseSecondOccurrence() throws {
        let zone = TimeZone(identifier: "America/New_York")!
        let plan = try manual(1, 30, now: "2026-11-01T05:45:00Z", timeZone: zone)
        XCTAssertEqual(plan.targetDate, date("2026-11-02T06:30:00Z"))
    }

    func testSpringDayRolloverAddsCalendarDayNotTwentyFourHours() throws {
        let zone = TimeZone(identifier: "America/New_York")!
        let plan = try manual(7, 0, now: "2026-03-07T13:00:00Z", timeZone: zone)
        XCTAssertEqual(plan.targetDate, date("2026-03-08T11:00:00Z"))
    }

    func testNonWholeHourTimeZoneIsCaptured() throws {
        let zone = TimeZone(identifier: "Asia/Kolkata")!
        let plan = try manual(7, 0, now: "2026-11-02T18:00:00Z", timeZone: zone)
        XCTAssertEqual(plan.targetDate, date("2026-11-03T01:30:00Z"))
        XCTAssertEqual(plan.timeZoneIdentifier, "Asia/Kolkata")
    }

    func testSmartSpringTransitionUsesElapsedSleepAndLocalDeadline() throws {
        let zone = TimeZone(identifier: "America/New_York")!
        let plan = try WakePlanner().makePlan(
            mode: .smart,
            now: date("2026-03-08T04:00:00Z"),
            timeZone: zone,
            bedtime: date("2026-03-08T03:30:00Z"),
            authorization: .authorized
        )
        XCTAssertEqual(plan.targetDate, date("2026-03-08T11:30:00Z"))
        XCTAssertEqual(plan.latestWakeDate, date("2026-03-08T12:15:00Z"))
        XCTAssertEqual(plan.events.first(where: { $0.kind == .fallback })?.fireDate, plan.latestWakeDate)
    }

    func testSmartAutumnTransitionKeepsEightFifteenLocalDeadline() throws {
        let zone = TimeZone(identifier: "America/New_York")!
        let plan = try WakePlanner().makePlan(
            mode: .smart,
            now: date("2026-11-01T04:00:00Z"),
            timeZone: zone,
            bedtime: date("2026-11-01T03:30:00Z"),
            authorization: .authorized
        )
        XCTAssertEqual(plan.targetDate, date("2026-11-01T11:30:00Z"))
        XCTAssertEqual(plan.latestWakeDate, date("2026-11-01T13:15:00Z"))
    }

    func testSmartEarlyProposalClampsToSixThirty() throws {
        let plan = try smart(now: "2026-11-02T22:00:00Z", bedtime: "2026-11-02T21:00:00Z")
        XCTAssertEqual(plan.targetDate, date("2026-11-03T06:30:00Z"))
        XCTAssertEqual(plan.latestWakeDate, date("2026-11-03T08:15:00Z"))
        XCTAssertEqual(plan.events.filter { $0.kind == .fallback }.count, 1)
    }

    func testSmartLateProposalUsesFallbackAndMinuteFollowups() throws {
        let plan = try smart(now: "2026-11-03T02:00:00Z", bedtime: "2026-11-03T01:00:00Z")
        XCTAssertEqual(plan.targetDate, date("2026-11-03T08:15:00Z"))
        XCTAssertEqual(plan.events.count, 11)
        XCTAssertEqual(plan.events.first?.kind, .fallback)
        XCTAssertEqual(plan.events.last?.fireDate, date("2026-11-03T08:25:00Z"))
        XCTAssertEqual(plan.events.compactMap(\.retryIndex), Array(1...10))
    }

    func testScreenshotBedtimeHasFallbackAndTenMinuteFollowups() throws {
        let plan = try smart(now: "2026-11-03T01:12:00Z", bedtime: "2026-11-03T01:11:00Z")
        XCTAssertEqual(plan.targetDate, date("2026-11-03T08:15:00Z"))
        XCTAssertEqual(plan.events.map(\.fireDate), (0...10).map {
            date("2026-11-03T08:15:00Z").addingTimeInterval(Double($0) * 60)
        })
        XCTAssertEqual(plan.events.filter { $0.kind == .fallback }.count, 1)
        XCTAssertEqual(Set(plan.eventIDs).count, 11)
    }

    func testMissingWatchAndBedtimeDataUsesMandatoryFallback() throws {
        let plan = try smart()
        XCTAssertEqual(plan.basis, .fallbackWithoutRecentBedtime)
        XCTAssertEqual(plan.targetDate, date("2026-11-03T08:15:00Z"))
        XCTAssertEqual(plan.events.count, 11)
        XCTAssertEqual(plan.events.last?.fireDate, date("2026-11-03T08:25:00Z"))
        XCTAssertNil(plan.sleepDurationUsed)
    }

    func testBedtimeWithoutWatchHistoryUsesExplicitPreference() throws {
        let plan = try smart(bedtime: "2026-11-02T23:00:00Z")
        XCTAssertEqual(plan.basis, .bedtimeAndPreferredDuration)
        XCTAssertEqual(plan.sleepDurationUsed, 8 * 3600)
        XCTAssertEqual(plan.targetDate, date("2026-11-03T07:00:00Z"))
    }

    func testRecentHistoryUsesMedianAndNotAnOutlier() throws {
        let history = [
            SleepHistoryEntry(start: date("2026-10-28T23:00:00Z"), end: date("2026-10-29T06:30:00Z")),
            SleepHistoryEntry(start: date("2026-10-29T23:00:00Z"), end: date("2026-10-30T07:00:00Z")),
            SleepHistoryEntry(start: date("2026-10-30T21:00:00Z"), end: date("2026-10-31T09:00:00Z"))
        ]
        let plan = try smart(bedtime: "2026-11-02T23:00:00Z", history: history)
        XCTAssertEqual(plan.basis, .bedtimeAndRecentHistory)
        XCTAssertEqual(plan.sleepDurationUsed, 8 * 3600)
        XCTAssertEqual(plan.targetDate, date("2026-11-03T07:00:00Z"))
    }

    func testInsufficientDuplicateStaleAndInvalidHistoryDoesNotDriveTarget() throws {
        let entry = SleepHistoryEntry(start: date("2026-10-30T23:00:00Z"), end: date("2026-10-31T06:00:00Z"))
        let history = [
            entry, entry, entry,
            SleepHistoryEntry(start: date("2026-09-01T23:00:00Z"), end: date("2026-09-02T06:00:00Z")),
            SleepHistoryEntry(start: date("2026-11-02T23:00:00Z"), end: date("2026-11-03T06:00:00Z")),
            SleepHistoryEntry(start: date("2026-10-29T23:00:00Z"), end: date("2026-10-29T22:00:00Z")),
            SleepHistoryEntry(start: date("2026-10-28T23:00:00Z"), end: date("2026-10-29T00:00:00Z"))
        ]
        let plan = try smart(bedtime: "2026-11-02T23:00:00Z", history: history)
        XCTAssertEqual(plan.basis, .bedtimeAndPreferredDuration)
        XCTAssertEqual(plan.sleepDurationUsed, 8 * 3600)
    }

    func testStaleOrFutureBedtimeUsesFallback() throws {
        for bedtime in ["2026-11-01T23:00:00Z", "2026-11-03T23:00:00Z"] {
            let plan = try smart(bedtime: bedtime)
            XCTAssertEqual(plan.basis, .fallbackWithoutRecentBedtime)
            XCTAssertEqual(plan.events.count, 11)
        }
    }

    func testElapsedSmartTargetMovesAheadInsideCurrentWindow() throws {
        let plan = try smart(now: "2026-11-03T07:10:00Z", bedtime: "2026-11-02T23:00:00Z")
        XCTAssertEqual(plan.targetDate, date("2026-11-03T07:11:00Z"))
        XCTAssertEqual(plan.latestWakeDate, date("2026-11-03T08:15:00Z"))
        XCTAssertTrue(plan.events.allSatisfy { $0.fireDate > plan.createdAt })
    }

    func testJustBeforeDeadlineDoesNotMoveAlarmPastDeadline() throws {
        let plan = try smart(now: "2026-11-03T08:14:59Z", bedtime: "2026-11-02T23:00:00Z")
        XCTAssertEqual(plan.targetDate, date("2026-11-03T08:15:00Z"))
        XCTAssertEqual(plan.events.count, 11)
        XCTAssertEqual(plan.events.first?.kind, .fallback)
        XCTAssertEqual(plan.events.last?.fireDate, date("2026-11-03T08:25:00Z"))
    }

    func testExactDeadlineSelectsNextWindow() throws {
        let plan = try smart(now: "2026-11-03T08:15:00Z")
        XCTAssertEqual(plan.targetDate, date("2026-11-04T08:15:00Z"))
    }

    func testDeadlineSeparatesEarlyRetriesAndFallbackFollowupsWithoutDuplicates() throws {
        let plan = try smart(now: "2026-11-03T00:12:00Z", bedtime: "2026-11-03T00:12:00Z")
        XCTAssertEqual(Array(plan.events.prefix(4)).map(\.fireDate), [
            date("2026-11-03T08:12:00Z"), date("2026-11-03T08:13:00Z"),
            date("2026-11-03T08:14:00Z"), date("2026-11-03T08:15:00Z")
        ])
        XCTAssertEqual(plan.events.filter { $0.kind == .fallback }.count, 1)
        XCTAssertEqual(plan.events.count, 14)
        XCTAssertEqual(plan.events.last?.fireDate, date("2026-11-03T08:25:00Z"))
        XCTAssertEqual(Set(plan.events.map(\.fireDate)).count, plan.events.count)
        XCTAssertEqual(Set(plan.eventIDs).count, plan.events.count)
    }

    func testSmartFallbackWithZeroRetriesHasOneAlarm() throws {
        let plan = try smart(retries: 0)
        XCTAssertEqual(plan.events.count, 1)
        XCTAssertEqual(plan.events.first?.kind, .fallback)
    }

    func testZeroRetriesStillKeepsSmartFallback() throws {
        let plan = try smart(bedtime: "2026-11-02T23:00:00Z", retries: 0)
        XCTAssertEqual(plan.events.map(\.kind), [.primary, .fallback])
    }

    func testRetryBatchIsFiniteAndEveryRetryIsSixtySecondsApart() throws {
        let plan = try manual(7, 0, now: "2026-11-02T23:00:00Z")
        XCTAssertEqual(plan.events.count, 11)
        XCTAssertEqual(plan.events.compactMap(\.retryIndex), Array(1...10))
        XCTAssertEqual(Set(plan.eventIDs).count, plan.events.count)
        for pair in zip(plan.events, plan.events.dropFirst()) {
            XCTAssertEqual(pair.1.fireDate.timeIntervalSince(pair.0.fireDate), 60)
        }
    }

    func testInvalidConfigurationRejected() {
        for limit in [-1, 11, 1000] {
            XCTAssertThrowsError(try WakePlanner(retryLimit: limit)) {
                XCTAssertEqual($0 as? WakePlanningError, .invalidRetryLimit)
            }
        }
        let invalidDurations: [TimeInterval] = [0, 24 * 3600, .nan, .infinity]
        for duration in invalidDurations {
            XCTAssertThrowsError(try WakePlanner(preferredSleepDuration: duration)) {
                XCTAssertEqual($0 as? WakePlanningError, .invalidPreferredDuration)
            }
        }
    }

    func testEveryUnapprovedPermissionStateBlocksPlanning() throws {
        let planner = try WakePlanner()
        for authorization in [AlarmAuthorization.denied, .notDetermined, .restricted] {
            for mode in [WakeMode.smart, .manual(try ClockTime(hour: 7, minute: 0))] {
                XCTAssertThrowsError(try planner.makePlan(
                    mode: mode,
                    now: date("2026-11-02T23:00:00Z"),
                    timeZone: utc,
                    authorization: authorization
                )) { XCTAssertEqual($0 as? WakePlanningError, .alarmPermissionRequired) }
            }
        }
    }

    func testPersistedPlanKeepsExactDatesAndTimeZone() throws {
        let original = try manual(
            7, 0, now: "2026-11-02T22:00:00Z",
            timeZone: TimeZone(identifier: "America/Los_Angeles")!
        )
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(WakePlan.self, from: data)
        XCTAssertEqual(restored, original)
        XCTAssertEqual(restored.timeZoneIdentifier, "America/Los_Angeles")
        XCTAssertEqual(restored.targetDate, date("2026-11-03T15:00:00Z"))
    }
}
