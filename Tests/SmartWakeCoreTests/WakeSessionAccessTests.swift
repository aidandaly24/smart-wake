import Foundation
import XCTest
@testable import SmartWakeCore

final class WakeSessionAccessTests: XCTestCase {
    private func sessions() throws -> [WakeSession] {
        let now = ISO8601DateFormatter().date(from: "2026-11-02T23:00:00Z")!
        let plan = try WakePlanner().makePlan(
            mode: .manual(ClockTime(hour: 7, minute: 0)), now: now,
            timeZone: TimeZone(secondsFromGMT: 0)!, authorization: .authorized)
        let memory = WakeSession(plan: plan,
            challenge: try MemoryChallenge(sequence: [.sun, .leaf, .moon]))
        return [memory] + WakeGameKind.allCases.map { WakeSession(plan: plan, gameKind: $0) }
    }

    private var invalidDates: [Date] {
        [Double.nan, .infinity, -.infinity].map { Date(timeIntervalSinceReferenceDate: $0) }
    }

    private func beginAnswering(_ wake: inout WakeSession, now: Date) {
        XCTAssertTrue(wake.beginChallenge(now: now))
        if wake.game == nil {
            XCTAssertEqual(wake.state, .memorizing)
            XCTAssertTrue(wake.hideSequence())
        }
        XCTAssertEqual(wake.state, .answering)
    }

    @discardableResult
    private func submitSolution(_ wake: inout WakeSession, now: Date) -> PuzzleSubmission {
        var result = PuzzleSubmission.ignored
        guard let game = wake.game else {
            for token in wake.challenge.sequence.dropFirst(wake.correctTapCount) {
                result = wake.submit(token, now: now)
            }
            return result
        }
        switch game.kind {
        case .word:
            result = wake.submit(.guess(game.wordAnswer), now: now)
        case .groups:
            for group in game.groups where !game.solvedGroupIDs.contains(group.id) {
                result = wake.submit(.group(group.words), now: now)
            }
        case .crossword:
            for entry in game.crossword where game.crosswordAnswers[entry.id] == nil {
                result = wake.submit(.crossword(entryID: entry.id, answer: entry.answer), now: now)
            }
        }
        return result
    }

    private func makeProgress(_ wake: inout WakeSession, now: Date) {
        guard let game = wake.game else {
            for token in wake.challenge.sequence.dropLast() { wake.submit(token, now: now) }
            return
        }
        switch game.kind {
        case .word:
            wake.submit(.hint, now: now)
        case .groups:
            for group in game.groups.dropLast() { wake.submit(.group(group.words), now: now) }
        case .crossword:
            for entry in game.crossword.dropLast() {
                wake.submit(.crossword(entryID: entry.id, answer: entry.answer), now: now)
            }
        }
    }

    private func restored(_ wake: WakeSession) throws -> WakeSession {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(wake)) as? [String: Any])
        // A missing game key is the original memory-session persistence format.
        if wake.game == nil { object.removeValue(forKey: "game") }
        return try JSONDecoder().decode(WakeSession.self,
            from: JSONSerialization.data(withJSONObject: object))
    }

    func testCanPlayRequiresFiniteReachedTargetAndNonterminalState() throws {
        for var wake in try sessions() {
            let target = wake.plan.targetDate
            XCTAssertFalse(wake.canPlay(at: target.addingTimeInterval(-0.001)))
            for invalid in invalidDates { XCTAssertFalse(wake.canPlay(at: invalid)) }
            XCTAssertTrue(wake.canPlay(at: target))
            XCTAssertTrue(wake.canPlay(at: target.addingTimeInterval(3600)))
            XCTAssertTrue(wake.beginChallenge(now: target))
            XCTAssertTrue(wake.canPlay(at: target))
            if wake.game == nil {
                XCTAssertEqual(wake.state, .memorizing)
                XCTAssertTrue(wake.hideSequence())
            }
            XCTAssertEqual(wake.state, .answering)
            XCTAssertTrue(wake.canPlay(at: target))
            wake.emergencyExit()
            XCTAssertFalse(wake.canPlay(at: target))
            XCTAssertFalse(wake.canPlay(at: target.addingTimeInterval(3600)))
        }
    }

    func testAllPuzzleFamiliesCannotStartOrSubmitBeforeTarget() throws {
        for var wake in try sessions() {
            let before = wake.plan.targetDate.addingTimeInterval(-0.001)
            let snapshot = wake
            XCTAssertFalse(wake.beginChallenge(now: before))
            XCTAssertFalse(wake.hideSequence())
            XCTAssertEqual(submitSolution(&wake, now: before), .ignored)
            XCTAssertEqual(wake.submit(.hint, now: before), .ignored)
            XCTAssertEqual(wake.submit(MemoryToken.wave, now: before), .ignored)
            XCTAssertEqual(wake, snapshot)
            XCTAssertEqual(wake.alarmIDsToCancel, [])
        }
    }

    func testAllPuzzleFamiliesCanCompleteAtExactTarget() throws {
        for var wake in try sessions() {
            let target = wake.plan.targetDate
            beginAnswering(&wake, now: target)
            XCTAssertEqual(submitSolution(&wake, now: target),
                .completed(cancelAlarmIDs: wake.plan.eventIDs))
            XCTAssertEqual(wake.state, .completed)
            XCTAssertEqual(wake.alarmIDsToCancel, wake.plan.eventIDs)
            XCTAssertFalse(wake.canPlay(at: target))
        }
    }

    func testAllPuzzleFamiliesCanCompleteAfterTarget() throws {
        for var wake in try sessions() {
            let later = wake.plan.targetDate.addingTimeInterval(3600)
            beginAnswering(&wake, now: later)
            XCTAssertEqual(submitSolution(&wake, now: later),
                .completed(cancelAlarmIDs: wake.plan.eventIDs))
        }
    }

    func testInvalidDatesCannotStartAnyPuzzleFamily() throws {
        for var wake in try sessions() {
            let snapshot = wake
            for invalid in invalidDates {
                XCTAssertFalse(wake.beginChallenge(now: invalid))
                XCTAssertEqual(submitSolution(&wake, now: invalid), .ignored)
                XCTAssertEqual(wake, snapshot)
            }
            XCTAssertEqual(wake.alarmIDsToCancel, [])
        }
    }

    func testInvalidDatesCannotChangeOrFinishAnsweringSessions() throws {
        for var wake in try sessions() {
            let target = wake.plan.targetDate
            beginAnswering(&wake, now: target)
            makeProgress(&wake, now: target)
            let snapshot = wake
            for invalid in invalidDates {
                XCTAssertFalse(wake.canPlay(at: invalid))
                XCTAssertEqual(submitSolution(&wake, now: invalid), .ignored)
                XCTAssertEqual(wake.submit(.hint, now: invalid), .ignored)
                XCTAssertEqual(wake.submit(MemoryToken.wave, now: invalid), .ignored)
                XCTAssertEqual(wake, snapshot)
            }
            XCTAssertEqual(wake.alarmIDsToCancel, [])
            XCTAssertEqual(submitSolution(&wake, now: target),
                .completed(cancelAlarmIDs: wake.plan.eventIDs))
        }
    }

    func testClockMovingBeforeTargetFreezesExistingProgressUntilTarget() throws {
        for var wake in try sessions() {
            let target = wake.plan.targetDate
            let before = target.addingTimeInterval(-60)
            beginAnswering(&wake, now: target)
            makeProgress(&wake, now: target)
            let snapshot = wake
            XCTAssertEqual(wake.state, .answering)
            XCTAssertFalse(wake.canPlay(at: before))
            XCTAssertFalse(wake.beginChallenge(now: before))
            XCTAssertEqual(submitSolution(&wake, now: before), .ignored)
            XCTAssertEqual(wake.submit(.hint, now: before), .ignored)
            XCTAssertEqual(wake.submit(MemoryToken.wave, now: before), .ignored)
            XCTAssertEqual(wake, snapshot)
            XCTAssertEqual(wake.alarmIDsToCancel, [])
            XCTAssertTrue(wake.canPlay(at: target))
            XCTAssertEqual(submitSolution(&wake, now: target),
                .completed(cancelAlarmIDs: wake.plan.eventIDs))
        }
    }

    func testOldAnsweringSessionsRestoreButCannotFinishBeforeTarget() throws {
        for var wake in try sessions() {
            let target = wake.plan.targetDate
            beginAnswering(&wake, now: target)
            makeProgress(&wake, now: target)
            var copy = try restored(wake)
            XCTAssertEqual(copy, wake)
            XCTAssertEqual(copy.state, .answering)
            let before = target.addingTimeInterval(-60)
            XCTAssertFalse(copy.canPlay(at: before))
            XCTAssertEqual(submitSolution(&copy, now: before), .ignored)
            XCTAssertEqual(copy, wake)
            XCTAssertEqual(copy.alarmIDsToCancel, [])
            XCTAssertEqual(submitSolution(&copy, now: target),
                .completed(cancelAlarmIDs: wake.plan.eventIDs))
        }
    }

    func testOldCompletedSessionsWithFutureTargetsRemainTerminalOnDecode() throws {
        for var wake in try sessions() {
            let target = wake.plan.targetDate
            beginAnswering(&wake, now: target)
            submitSolution(&wake, now: target)
            // This is also the saved shape written by old builds that allowed
            // early completion. Loading it must not resurrect or rearm alarms.
            var copy = try restored(wake)
            XCTAssertEqual(copy, wake)
            XCTAssertEqual(copy.state, .completed)
            XCTAssertTrue(copy.isTerminal)
            XCTAssertEqual(copy.alarmIDsToCancel, wake.plan.eventIDs)
            for now in [target.addingTimeInterval(-60), target, target.addingTimeInterval(60)] {
                XCTAssertFalse(copy.canPlay(at: now))
                XCTAssertFalse(copy.beginChallenge(now: now))
                XCTAssertEqual(copy.submit(MemoryToken.sun, now: now), .ignored)
                XCTAssertEqual(copy.submit(.hint, now: now), .ignored)
                XCTAssertEqual(copy, wake)
            }
            XCTAssertEqual(copy.cancel(), [])
            XCTAssertEqual(copy.emergencyExit(), [])
            XCTAssertEqual(copy, wake)
        }
    }

    func testCancellationAndEmergencyExitRemainAvailableWhenPlayIsBlocked() throws {
        for original in try sessions() {
            let target = original.plan.targetDate
            for blockedTime in [target.addingTimeInterval(-60)] + invalidDates {
                for hasBegun in [false, true] {
                    var wake = original
                    if hasBegun {
                        beginAnswering(&wake, now: target)
                        makeProgress(&wake, now: target)
                    }
                    XCTAssertFalse(wake.canPlay(at: blockedTime))
                    XCTAssertFalse(wake.beginChallenge(now: blockedTime))
                    var emergency = wake
                    XCTAssertEqual(wake.cancel(), original.plan.eventIDs)
                    XCTAssertEqual(wake.state, .cancelled)
                    XCTAssertEqual(emergency.emergencyExit(), original.plan.eventIDs)
                    XCTAssertEqual(emergency.state, .emergencyExited)
                    for terminal in [wake, emergency] {
                        XCTAssertFalse(terminal.canPlay(at: target))
                        XCTAssertEqual(try restored(terminal), terminal)
                        XCTAssertEqual(terminal.alarmIDsToCancel, original.plan.eventIDs)
                    }
                }
            }
        }
    }
}
