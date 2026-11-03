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
        XCTAssertEqual(wake.submit(.sun), .ignored)
        XCTAssertTrue(wake.beginChallenge())
        XCTAssertEqual(wake.submit(.sun), .ignored)
        XCTAssertEqual(wake.correctTapCount, 0)
        XCTAssertTrue(wake.hideSequence())
        XCTAssertEqual(wake.submit(.sun), .progress(remaining: 2))
    }

    func testCorrectSequenceCompletesAndReturnsEveryCancellationID() throws {
        var wake = try session()
        wake.beginChallenge()
        wake.hideSequence()
        XCTAssertEqual(wake.submit(.sun), .progress(remaining: 2))
        XCTAssertEqual(wake.submit(.leaf), .progress(remaining: 1))
        XCTAssertEqual(wake.submit(.moon), .completed(cancelAlarmIDs: wake.plan.eventIDs))
        XCTAssertEqual(wake.state, .completed)
        XCTAssertTrue(wake.isTerminal)
        XCTAssertEqual(wake.alarmIDsToCancel, wake.plan.eventIDs)
    }

    func testWrongTapResetsForAnotherLookWithoutEscalation() throws {
        var wake = try session()
        wake.beginChallenge()
        wake.hideSequence()
        wake.submit(.sun)
        XCTAssertEqual(wake.submit(.wave), .incorrect)
        XCTAssertEqual(wake.state, .memorizing)
        XCTAssertEqual(wake.correctTapCount, 0)
        XCTAssertFalse(wake.isTerminal)
        XCTAssertTrue(wake.hideSequence())
        XCTAssertEqual(wake.submit(.sun), .progress(remaining: 2))
    }

    func testCancelBeforeChallengeReturnsIDsAndCannotRearm() throws {
        var wake = try session()
        XCTAssertEqual(wake.cancel(), wake.plan.eventIDs)
        XCTAssertEqual(wake.state, .cancelled)
        XCTAssertFalse(wake.beginChallenge())
        XCTAssertFalse(wake.hideSequence())
        XCTAssertEqual(wake.submit(.sun), .ignored)
        XCTAssertEqual(wake.cancel(), [])
        XCTAssertEqual(wake.emergencyExit(), [])
        XCTAssertEqual(wake.state, .cancelled)
    }

    func testEmergencyExitAvailableBeforeOrDuringPuzzle() throws {
        for stage in 0...2 {
            var wake = try session()
            if stage >= 1 { wake.beginChallenge() }
            if stage >= 2 { wake.hideSequence(); wake.submit(.sun) }
            XCTAssertEqual(wake.emergencyExit(), wake.plan.eventIDs)
            XCTAssertEqual(wake.state, .emergencyExited)
            XCTAssertTrue(wake.isTerminal)
            XCTAssertEqual(wake.submit(.leaf), .ignored)
            XCTAssertFalse(wake.beginChallenge())
        }
    }

    func testCompleteSessionCannotBeRepeatedOrRearmed() throws {
        var wake = try session()
        wake.beginChallenge()
        wake.hideSequence()
        wake.submit(.sun)
        wake.submit(.leaf)
        wake.submit(.moon)
        XCTAssertFalse(wake.beginChallenge())
        XCTAssertFalse(wake.hideSequence())
        XCTAssertEqual(wake.submit(.moon), .ignored)
        XCTAssertEqual(wake.cancel(), [])
        XCTAssertEqual(wake.state, .completed)
    }

    func testProgressAndCancellationIntentSurviveRelaunch() throws {
        var wake = try session()
        wake.beginChallenge()
        wake.hideSequence()
        wake.submit(.sun)
        var restored = try JSONDecoder().decode(
            WakeSession.self, from: JSONEncoder().encode(wake)
        )
        XCTAssertEqual(restored, wake)
        XCTAssertEqual(restored.correctTapCount, 1)
        XCTAssertEqual(restored.submit(.leaf), .progress(remaining: 1))
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
