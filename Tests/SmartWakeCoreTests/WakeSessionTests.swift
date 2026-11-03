import Foundation
import XCTest
@testable import SmartWakeCore

final class WakeSessionTests: XCTestCase {
    private func session() throws -> WakeSession {
        let now = ISO8601DateFormatter().date(from: "2026-11-02T23:00:00Z")!
        let plan = try WakePlanner().makePlan(
            mode: .manual(ClockTime(hour: 7, minute: 0)),
            now: now,
            timeZone: TimeZone(secondsFromGMT: 0)!,
            authorization: .authorized
        )
        return WakeSession(plan: plan, challenge: try MemoryChallenge(sequence: [.sun, .leaf, .moon]))
    }

    func testCannotAnswerBeforeSequenceIsHidden() throws {
        var wake = try session()
        XCTAssertEqual(wake.submit(.sun, now: wake.plan.targetDate), .ignored)
        XCTAssertTrue(wake.beginChallenge(now: wake.plan.targetDate))
        XCTAssertEqual(wake.submit(.sun, now: wake.plan.targetDate), .ignored)
        XCTAssertEqual(wake.correctTapCount, 0)
        XCTAssertTrue(wake.hideSequence())
        XCTAssertEqual(wake.submit(.sun, now: wake.plan.targetDate), .progress(remaining: 2))
    }

    func testCorrectSequenceCompletesAndReturnsEveryCancellationID() throws {
        var wake = try session()
        wake.beginChallenge(now: wake.plan.targetDate)
        wake.hideSequence()
        XCTAssertEqual(wake.submit(.sun, now: wake.plan.targetDate), .progress(remaining: 2))
        XCTAssertEqual(wake.submit(.leaf, now: wake.plan.targetDate), .progress(remaining: 1))
        XCTAssertEqual(wake.submit(.moon, now: wake.plan.targetDate), .completed(cancelAlarmIDs: wake.plan.eventIDs))
        XCTAssertEqual(wake.state, .completed)
        XCTAssertTrue(wake.isTerminal)
        XCTAssertEqual(wake.alarmIDsToCancel, wake.plan.eventIDs)
    }

    func testWrongTapResetsForAnotherLookWithoutEscalation() throws {
        var wake = try session()
        wake.beginChallenge(now: wake.plan.targetDate)
        wake.hideSequence()
        wake.submit(.sun, now: wake.plan.targetDate)
        XCTAssertEqual(wake.submit(.wave, now: wake.plan.targetDate), .incorrect)
        XCTAssertEqual(wake.state, .memorizing)
        XCTAssertEqual(wake.correctTapCount, 0)
        XCTAssertFalse(wake.isTerminal)
        XCTAssertTrue(wake.hideSequence())
        XCTAssertEqual(wake.submit(.sun, now: wake.plan.targetDate), .progress(remaining: 2))
    }

    func testCancelBeforeChallengeReturnsIDsAndCannotRearm() throws {
        var wake = try session()
        XCTAssertEqual(wake.cancel(), wake.plan.eventIDs)
        XCTAssertEqual(wake.state, .cancelled)
        XCTAssertFalse(wake.beginChallenge(now: wake.plan.targetDate))
        XCTAssertFalse(wake.hideSequence())
        XCTAssertEqual(wake.submit(.sun, now: wake.plan.targetDate), .ignored)
        XCTAssertEqual(wake.cancel(), [])
        XCTAssertEqual(wake.emergencyExit(), [])
        XCTAssertEqual(wake.state, .cancelled)
    }

    func testEmergencyExitAvailableBeforeOrDuringPuzzle() throws {
        for stage in 0...2 {
            var wake = try session()
            if stage >= 1 { wake.beginChallenge(now: wake.plan.targetDate) }
            if stage >= 2 { wake.hideSequence(); wake.submit(.sun, now: wake.plan.targetDate) }
            XCTAssertEqual(wake.emergencyExit(), wake.plan.eventIDs)
            XCTAssertEqual(wake.state, .emergencyExited)
            XCTAssertTrue(wake.isTerminal)
            XCTAssertEqual(wake.submit(.leaf, now: wake.plan.targetDate), .ignored)
            XCTAssertFalse(wake.beginChallenge(now: wake.plan.targetDate))
        }
    }

    func testCompleteSessionCannotBeRepeatedOrRearmed() throws {
        var wake = try session()
        wake.beginChallenge(now: wake.plan.targetDate)
        wake.hideSequence()
        wake.submit(.sun, now: wake.plan.targetDate)
        wake.submit(.leaf, now: wake.plan.targetDate)
        wake.submit(.moon, now: wake.plan.targetDate)
        XCTAssertFalse(wake.beginChallenge(now: wake.plan.targetDate))
        XCTAssertFalse(wake.hideSequence())
        XCTAssertEqual(wake.submit(.moon, now: wake.plan.targetDate), .ignored)
        XCTAssertEqual(wake.cancel(), [])
        XCTAssertEqual(wake.state, .completed)
    }

    func testProgressAndCancellationIntentSurviveRelaunch() throws {
        var wake = try session()
        wake.beginChallenge(now: wake.plan.targetDate)
        wake.hideSequence()
        wake.submit(.sun, now: wake.plan.targetDate)
        var restored = try JSONDecoder().decode(
            WakeSession.self, from: JSONEncoder().encode(wake)
        )
        XCTAssertEqual(restored, wake)
        XCTAssertEqual(restored.correctTapCount, 1)
        XCTAssertEqual(restored.submit(.leaf, now: restored.plan.targetDate), .progress(remaining: 1))
        restored.emergencyExit()
        let terminal = try JSONDecoder().decode(
            WakeSession.self, from: JSONEncoder().encode(restored)
        )
        XCTAssertEqual(terminal.alarmIDsToCancel, wake.plan.eventIDs)
        XCTAssertEqual(terminal.state, .emergencyExited)
    }

    func testCannotDecodeCorruptProgress() throws {
        let wake = try session()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(wake)) as? [String: Any])
        object["correctTapCount"] = 999
        let corrupt = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try JSONDecoder().decode(WakeSession.self, from: corrupt))
    }

    func testChallengeRejectsInvalidLengthIncludingOnDecode() throws {
        for count in [0, 1, 2, 7] {
            XCTAssertThrowsError(try MemoryChallenge(sequence: Array(repeating: .sun, count: count)))
        }
        XCTAssertThrowsError(try JSONDecoder().decode(
            MemoryChallenge.self, from: Data(#"{"sequence":[]}"#.utf8)
        ))
        XCTAssertEqual(MemoryChallenge.random(length: -1).sequence.count, 3)
        XCTAssertEqual(MemoryChallenge.random(length: 100).sequence.count, 6)
    }
}
