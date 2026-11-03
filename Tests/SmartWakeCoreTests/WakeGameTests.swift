import Foundation
import XCTest
@testable import SmartWakeCore

final class WakeGameTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func plan(timeZone: TimeZone? = nil) throws -> WakePlan {
        try WakePlanner().makePlan(mode: .manual(ClockTime(hour: 7, minute: 0)),
            now: date("2026-11-02T23:00:00Z"), timeZone: timeZone ?? utc,
            authorization: .authorized)
    }

    private func session(_ kind: WakeGameKind) throws -> WakeSession {
        WakeSession(plan: try plan(), gameKind: kind)
    }

    private func restored<T: Codable>(_ value: T) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }

    private func editedJSON<T: Encodable>(_ value: T,
                                         edit: (inout [String: Any]) -> Void) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        edit(&object)
        return try JSONSerialization.data(withJSONObject: object)
    }

    @discardableResult
    private func solve(_ wake: inout WakeSession) throws -> PuzzleSubmission {
        let game = try XCTUnwrap(wake.game)
        switch game.kind {
        case .word: return wake.submit(.guess(game.wordAnswer), now: wake.plan.targetDate)
        case .groups:
            var result = PuzzleSubmission.ignored
            for group in game.groups where !game.solvedGroupIDs.contains(group.id) {
                result = wake.submit(.group(group.words), now: wake.plan.targetDate)
            }
            return result
        case .crossword:
            var result = PuzzleSubmission.ignored
            for entry in game.crossword where game.crosswordAnswers[entry.id] == nil {
                result = wake.submit(.crossword(entryID: entry.id, answer: entry.answer), now: wake.plan.targetDate)
            }
            return result
        }
    }

    func testLetterFeedbackConsumesDuplicatesAndReservesExactMatches() {
        XCTAssertEqual(WakeGame.letterFeedback(guess: "ALLEE", answer: "APPLE"),
            [.exact, .present, .absent, .absent, .exact])
        XCTAssertEqual(WakeGame.letterFeedback(guess: "LLAMA", answer: "SMALL"),
            [.present, .present, .exact, .present, .absent])
        XCTAssertEqual(WakeGame.letterFeedback(guess: "PAPAL", answer: "APPLE"),
            [.present, .present, .exact, .absent, .present])
        XCTAssertEqual(WakeGame.letterFeedback(guess: "APPLE", answer: "APPLE"),
            Array(repeating: .exact, count: 5))
    }

    func testLetterFeedbackNormalizesCaseAccentsWidthAndEdgeWhitespace() {
        for spelling in [" apple\n", "Ápple", "ａｐｐｌｅ"] {
            XCTAssertEqual(WakeGame.letterFeedback(guess: spelling, answer: "APPLE"),
                Array(repeating: .exact, count: 5))
        }
        for invalid in ["", "APPL", "APPLE!", "AP PLE", "12345", "🌞🌞🌞🌞🌞"] {
            XCTAssertEqual(WakeGame.letterFeedback(guess: invalid, answer: "APPLE"), [])
        }
    }

    func testNewSessionsUseTargetDateAndSavedTimeZone() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "Pacific/Auckland"))
        let armedPlan = try plan(timeZone: zone)
        let wake = WakeSession(plan: armedPlan)
        XCTAssertEqual(wake.game, WakeGame.make(for: armedPlan.targetDate, timeZone: zone))
        XCTAssertEqual(wake.state, .armed)
        XCTAssertEqual(wake.correctTapCount, 0)
        XCTAssertEqual(wake.plan, armedPlan)
        for kind in WakeGameKind.allCases {
            XCTAssertEqual(WakeSession(plan: armedPlan, gameKind: kind).game?.kind, kind)
        }
    }

    func testDailyRotationIsDeterministicAcrossThreeLocalDays() throws {
        let start = date("2026-11-01T12:00:00Z")
        let games = (0..<9).map { WakeGame.make(for: start.addingTimeInterval(Double($0) * 86400), timeZone: utc) }
        XCTAssertEqual(Set(games.prefix(3).map(\.kind)), Set(WakeGameKind.allCases))
        for index in 0..<6 {
            XCTAssertEqual(games[index].kind, games[index + 3].kind)
            XCTAssertNotEqual(games[index], games[index + 3])
        }
        for index in games.indices {
            XCTAssertEqual(games[index], WakeGame.make(for: start.addingTimeInterval(Double(index) * 86400), timeZone: utc))
            XCTAssertEqual(try restored(games[index]), games[index])
        }
    }

    func testLocalDateNotUTCDateOrElapsedHoursControlsRotation() throws {
        let losAngeles = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        // Same local Nov 1, including both occurrences of 01:30 at the DST fall-back.
        let early = WakeGame.make(for: date("2026-11-01T08:30:00Z"), timeZone: losAngeles)
        let repeatedHour = WakeGame.make(for: date("2026-11-01T09:30:00Z"), timeZone: losAngeles)
        let late = WakeGame.make(for: date("2026-11-02T07:59:00Z"), timeZone: losAngeles)
        XCTAssertEqual(early, repeatedHour)
        XCTAssertEqual(early, late)
        let nextDay = WakeGame.make(for: date("2026-11-02T08:00:00Z"), timeZone: losAngeles)
        XCTAssertNotEqual(early.kind, nextDay.kind)
        // Equal wall dates in different zones choose the same content and tile order.
        XCTAssertEqual(early, WakeGame.make(for: date("2026-11-01T12:00:00Z"), timeZone: utc))
        XCTAssertNotEqual(late.kind, WakeGame.make(for: date("2026-11-02T07:59:00Z"), timeZone: utc).kind)
        // The spring transition also has one daily change, despite a 23-hour day.
        XCTAssertEqual(
            WakeGame.make(for: date("2026-03-08T08:00:00Z"), timeZone: losAngeles),
            WakeGame.make(for: date("2026-03-09T06:59:00Z"), timeZone: losAngeles))
    }

    func testCatalogCyclesContainVariedValidPersistablePuzzles() throws {
        let epoch = date("2000-01-01T12:00:00Z")
        for kind in WakeGameKind.allCases {
            var signatures = Set<String>()
            // Includes dates before the fixed epoch, exercising negative modulo.
            for offset in -5..<95 {
                let game = WakeGame.make(for: epoch.addingTimeInterval(Double(offset) * 86400), timeZone: utc, kind: kind)
                XCTAssertEqual(game.kind, kind)
                XCTAssertEqual(try restored(game), game)
                XCTAssertFalse(game.isSolved)
                switch kind {
                case .word: signatures.insert(game.wordAnswer)
                case .groups: signatures.insert(game.groups.map(\.title).joined(separator: "|"))
                case .crossword: signatures.insert(game.crossword.map(\.answer).joined(separator: "|"))
                }
            }
            XCTAssertEqual(signatures.count, kind == .word ? 30 : 12)
        }
    }

    func testGamesRequireBeginAndCannotUseLegacyMemoryBypass() throws {
        for kind in WakeGameKind.allCases {
            var wake = try session(kind)
            XCTAssertEqual(wake.submit(.hint, now: wake.plan.targetDate), .ignored)
            XCTAssertTrue(wake.beginChallenge(now: wake.plan.targetDate))
            XCTAssertEqual(wake.state, .answering)
            XCTAssertFalse(wake.beginChallenge(now: wake.plan.targetDate))
            XCTAssertFalse(wake.hideSequence())
            XCTAssertEqual(wake.submit(MemoryToken.sun, now: wake.plan.targetDate), .ignored)
            XCTAssertEqual(wake.correctTapCount, 0)
            XCTAssertFalse(wake.isTerminal)
        }
    }

    func testWordRejectsInvalidInputsWithoutConsumingAGuess() throws {
        var wake = try session(.word)
        wake.beginChallenge(now: wake.plan.targetDate)
        for input in ["", " ", "FOUR", "SIXLET", "12345", "A BCD", "AB-CD", "ABCD🌞", String(repeating: "A", count: 200)] {
            XCTAssertEqual(wake.submit(.guess(input), now: wake.plan.targetDate), .incorrect)
            XCTAssertEqual(wake.game?.guesses, [])
            XCTAssertFalse(wake.game?.feedback.isEmpty ?? true)
        }
        XCTAssertEqual(wake.state, .answering)
    }

    func testWordAllowsUnlimitedWrongGuessesThenCaseInsensitiveCompletion() throws {
        var wake = try session(.word)
        wake.beginChallenge(now: wake.plan.targetDate)
        for _ in 0..<25 { XCTAssertEqual(wake.submit(.guess("CRANE"), now: wake.plan.targetDate), .incorrect) }
        XCTAssertEqual(wake.game?.guesses.count, 25)
        XCTAssertEqual(wake.state, .answering)
        XCTAssertEqual(wake.alarmIDsToCancel, [])
        let answer = try XCTUnwrap(wake.game?.wordAnswer)
        XCTAssertEqual(wake.submit(.guess(" \(answer.lowercased())\n"), now: wake.plan.targetDate), .completed(cancelAlarmIDs: wake.plan.eventIDs))
        XCTAssertTrue(wake.game?.isSolved == true)
    }

    func testGroupsRejectDuplicatesUnknownTilesAndPartialOverlap() throws {
        var wake = try session(.groups)
        wake.beginChallenge(now: wake.plan.targetDate)
        let game = try XCTUnwrap(wake.game)
        let first = game.groups[0]
        let second = game.groups[1]
        XCTAssertEqual(Set(game.tileWords), Set(game.groups.flatMap(\.words)))
        XCTAssertEqual(wake.submit(.group(Array(repeating: first.words[0], count: 4)), now: wake.plan.targetDate), .incorrect)
        XCTAssertEqual(wake.submit(.group([first.words[0], first.words[0].lowercased(), first.words[1], first.words[2]]), now: wake.plan.targetDate), .incorrect)
        XCTAssertEqual(wake.submit(.group(Array(first.words.prefix(3))), now: wake.plan.targetDate), .incorrect)
        XCTAssertEqual(wake.submit(.group([first.words[0], first.words[1], first.words[2], "UNKNOWN"]), now: wake.plan.targetDate), .incorrect)
        XCTAssertEqual(wake.submit(.group([first.words[0], first.words[1], first.words[2], second.words[0]]), now: wake.plan.targetDate), .incorrect)
        XCTAssertEqual(wake.game?.solvedGroupIDs, [])
        XCTAssertEqual(wake.submit(.group(first.words.reversed().map { " \($0.lowercased()) " }), now: wake.plan.targetDate), .progress(remaining: 1))
        XCTAssertEqual(wake.game?.solvedGroupIDs, [first.id])
        XCTAssertEqual(wake.submit(.group(first.words), now: wake.plan.targetDate), .incorrect)
        XCTAssertEqual(wake.submit(.group([first.words[0], second.words[0], second.words[1], second.words[2]]), now: wake.plan.targetDate), .incorrect)
        XCTAssertEqual(wake.submit(.group(second.words), now: wake.plan.targetDate), .completed(cancelAlarmIDs: wake.plan.eventIDs))
    }

    func testEveryMiniHasConnectedMatchingIntersections() {
        let start = date("2026-11-01T12:00:00Z")
        for offset in 0..<12 {
            let game = WakeGame.make(for: start.addingTimeInterval(Double(offset) * 86400), timeZone: utc, kind: .crossword)
            XCTAssertEqual(game.crossword.count, 4)
            var letters: [String: Character] = [:]
            var owners: [String: Set<String>] = [:]
            for entry in game.crossword {
                XCTAssertGreaterThanOrEqual(entry.row, 0)
                XCTAssertGreaterThanOrEqual(entry.column, 0)
                for (index, letter) in entry.answer.enumerated() {
                    let row = entry.row + (entry.isAcross ? 0 : index)
                    let column = entry.column + (entry.isAcross ? index : 0)
                    let key = "\(row),\(column)"
                    if let previous = letters[key] { XCTAssertEqual(previous, letter) }
                    letters[key] = letter
                    owners[key, default: []].insert(entry.id)
                }
            }
            let intersections = owners.values.filter { $0.count > 1 }
            XCTAssertEqual(intersections.count, 3)
            for entry in game.crossword {
                XCTAssertTrue(intersections.contains { $0.contains(entry.id) })
            }
        }
    }

    func testCrosswordKeepsOnlyCorrectAnswersAndCompletesOnLastEntry() throws {
        var wake = try session(.crossword)
        wake.beginChallenge(now: wake.plan.targetDate)
        let entries = try XCTUnwrap(wake.game?.crossword)
        XCTAssertEqual(wake.submit(.crossword(entryID: "missing", answer: "AAA"), now: wake.plan.targetDate), .ignored)
        XCTAssertEqual(wake.submit(.crossword(entryID: entries[0].id, answer: ""), now: wake.plan.targetDate), .incorrect)
        XCTAssertEqual(wake.submit(.crossword(entryID: entries[0].id, answer: "ZZZ"), now: wake.plan.targetDate), .incorrect)
        XCTAssertEqual(wake.game?.crosswordAnswers, [:])
        for (index, entry) in entries.enumerated() {
            let expected: PuzzleSubmission = index == entries.count - 1
                ? .completed(cancelAlarmIDs: wake.plan.eventIDs) : .progress(remaining: entries.count - index - 1)
            XCTAssertEqual(wake.submit(.crossword(entryID: entry.id, answer: " \(entry.answer.lowercased()) "), now: wake.plan.targetDate), expected)
            XCTAssertEqual(wake.game?.crosswordAnswers[entry.id], entry.answer)
            XCTAssertEqual(wake.submit(.crossword(entryID: entry.id, answer: "ZZZ"), now: wake.plan.targetDate), .ignored)
        }
    }

    func testHintsAreGradualPersistedAndNeverSilentlyComplete() throws {
        for kind in WakeGameKind.allCases {
            var wake = try session(kind)
            wake.beginChallenge(now: wake.plan.targetDate)
            var messages: [String] = []
            for level in 1...3 {
                guard case .progress = wake.submit(.hint, now: wake.plan.targetDate) else { return XCTFail("Hint should retain active progress") }
                XCTAssertEqual(wake.game?.hintLevel, level)
                messages.append(try XCTUnwrap(wake.game?.feedback))
                wake = try restored(wake)
                XCTAssertEqual(wake.game?.hintLevel, level)
                XCTAssertFalse(wake.isTerminal)
                XCTAssertFalse(wake.game?.isSolved ?? true)
                XCTAssertEqual(wake.alarmIDsToCancel, [])
            }
            XCTAssertEqual(Set(messages).count, 3)
            for _ in 0..<20 { _ = wake.submit(.hint, now: wake.plan.targetDate) }
            XCTAssertEqual(wake.game?.hintLevel, 3)
            XCTAssertFalse(wake.isTerminal)
            XCTAssertEqual(try solve(&wake), .completed(cancelAlarmIDs: wake.plan.eventIDs))
        }
    }

    func testAllProgressSurvivesRelaunchAndFinishingRetainsCancellationIntent() throws {
        for kind in WakeGameKind.allCases {
            var wake = try session(kind)
            wake.beginChallenge(now: wake.plan.targetDate)
            wake.submit(.hint, now: wake.plan.targetDate)
            let game = try XCTUnwrap(wake.game)
            switch kind {
            case .word: wake.submit(.guess("CRANE"), now: wake.plan.targetDate)
            case .groups: wake.submit(.group(game.groups[0].words), now: wake.plan.targetDate)
            case .crossword:
                wake.submit(.crossword(entryID: game.crossword[0].id, answer: game.crossword[0].answer), now: wake.plan.targetDate)
            }
            var copy: WakeSession = try restored(wake)
            XCTAssertEqual(copy, wake)
            XCTAssertEqual(copy.game?.tileWords, game.tileWords)
            XCTAssertEqual(try solve(&copy), .completed(cancelAlarmIDs: wake.plan.eventIDs))
            let finished: WakeSession = try restored(copy)
            XCTAssertEqual(finished, copy)
            XCTAssertEqual(finished.state, .completed)
            XCTAssertEqual(finished.alarmIDsToCancel, wake.plan.eventIDs)
        }
    }

    func testTerminalSessionsIgnoreEveryActionAndNeverRearm() throws {
        for kind in WakeGameKind.allCases {
            for terminal in [WakeSessionState.completed, .cancelled, .emergencyExited] {
                var wake = try session(kind)
                wake.beginChallenge(now: wake.plan.targetDate)
                switch terminal {
                case .completed: try solve(&wake)
                case .cancelled: XCTAssertEqual(wake.cancel(), wake.plan.eventIDs)
                case .emergencyExited: XCTAssertEqual(wake.emergencyExit(), wake.plan.eventIDs)
                default: XCTFail("Unexpected test state")
                }
                let snapshot = wake
                for action in [WakeGameAction.hint, .guess("APPLE"), .group([]), .crossword(entryID: "1A", answer: "ABC")] {
                    XCTAssertEqual(wake.submit(action, now: wake.plan.targetDate), .ignored)
                }
                XCTAssertEqual(wake.submit(MemoryToken.sun, now: wake.plan.targetDate), .ignored)
                XCTAssertFalse(wake.beginChallenge(now: wake.plan.targetDate))
                XCTAssertFalse(wake.hideSequence())
                XCTAssertEqual(wake.cancel(), [])
                XCTAssertEqual(wake.emergencyExit(), [])
                XCTAssertEqual(wake, snapshot)
                XCTAssertEqual(try restored(wake).alarmIDsToCancel, wake.plan.eventIDs)
            }
        }
    }

    func testEmergencyExitBeforeOrDuringEveryGame() throws {
        for kind in WakeGameKind.allCases {
            for hasBegun in [false, true] {
                var wake = try session(kind)
                if hasBegun { wake.beginChallenge(now: wake.plan.targetDate); wake.submit(.hint, now: wake.plan.targetDate) }
                XCTAssertEqual(wake.emergencyExit(), wake.plan.eventIDs)
                let copy: WakeSession = try restored(wake)
                XCTAssertEqual(copy.state, .emergencyExited)
                XCTAssertEqual(copy.alarmIDsToCancel, wake.plan.eventIDs)
            }
        }
    }

    func testUnrelatedStyleActionsDoNotChangeProgressOrFeedback() throws {
        var wake = try session(.word)
        wake.beginChallenge(now: wake.plan.targetDate)
        let snapshot = wake
        XCTAssertEqual(wake.submit(.group(["A", "B", "C", "D"]), now: wake.plan.targetDate), .ignored)
        XCTAssertEqual(wake.submit(.crossword(entryID: "1A", answer: "CAT"), now: wake.plan.targetDate), .ignored)
        XCTAssertEqual(wake, snapshot)
    }

    func testOldMemoryJSONWithoutGameStillRestoresAndFinishes() throws {
        let pattern = try MemoryChallenge(sequence: [.sun, .leaf, .moon])
        var legacy = WakeSession(plan: try plan(), challenge: pattern)
        legacy.beginChallenge(now: legacy.plan.targetDate)
        legacy.hideSequence()
        legacy.submit(.sun, now: legacy.plan.targetDate)
        let data = try editedJSON(legacy) { $0.removeValue(forKey: "game") }
        var copy = try JSONDecoder().decode(WakeSession.self, from: data)
        XCTAssertNil(copy.game)
        XCTAssertEqual(copy.challenge, pattern)
        XCTAssertEqual(copy.correctTapCount, 1)
        XCTAssertEqual(copy.submit(.hint, now: copy.plan.targetDate), .ignored)
        XCTAssertEqual(copy.submit(.leaf, now: copy.plan.targetDate), .progress(remaining: 1))
        XCTAssertEqual(copy.submit(.moon, now: copy.plan.targetDate), .completed(cancelAlarmIDs: legacy.plan.eventIDs))
        XCTAssertEqual(try restored(copy).alarmIDsToCancel, legacy.plan.eventIDs)
    }

    func testDecoderRejectsClaimedCompletionWithoutCorrectAnswers() throws {
        for kind in WakeGameKind.allCases {
            let wake = try session(kind)
            let corrupt = try editedJSON(wake) { $0["state"] = "completed" }
            XCTAssertThrowsError(try JSONDecoder().decode(WakeSession.self, from: corrupt))
        }
        var wake = try session(.word)
        wake.beginChallenge(now: wake.plan.targetDate)
        try solve(&wake)
        let corrupt = try editedJSON(wake) { $0["state"] = "answering" }
        XCTAssertThrowsError(try JSONDecoder().decode(WakeSession.self, from: corrupt))
    }

    func testDecoderRejectsMalformedWordHintsAndProgress() throws {
        let game = try XCTUnwrap(try session(.word).game)
        let edits: [(inout [String: Any]) -> Void] = [
            { $0["wordAnswer"] = "FOUR" },
            { $0["guesses"] = ["NOT A WORD"] },
            { $0["guesses"] = [game.wordAnswer, "CRANE"] },
            { $0["hintLevel"] = -1 },
            { $0["hintLevel"] = 4 }
        ]
        for edit in edits {
            let corrupt = try editedJSON(game, edit: edit)
            XCTAssertThrowsError(try JSONDecoder().decode(WakeGame.self, from: corrupt))
        }
    }

    func testDecoderRejectsDuplicateOverlappingOrFalselySolvedGroups() throws {
        let game = try XCTUnwrap(try session(.groups).game)
        let edits: [(inout [String: Any]) -> Void] = [
            { $0["tileWords"] = Array(repeating: game.tileWords[0], count: game.tileWords.count) },
            { $0["solvedGroupIDs"] = [game.groups[0].id] },
            { $0["solvedGroupIDs"] = ["unknown"] },
            {
                var groups = $0["groups"] as! [[String: Any]]
                groups[1]["words"] = groups[0]["words"]
                $0["groups"] = groups
            },
            {
                $0["solvedGroupIDs"] = [game.groups[0].id]
                $0["solvedGroupWords"] = [game.groups[0].id: game.groups[1].words]
            }
        ]
        for edit in edits {
            XCTAssertThrowsError(try JSONDecoder().decode(WakeGame.self, from: editedJSON(game, edit: edit)))
        }
    }

    func testDecoderRejectsCrosswordConflictsOutOfBoundsAndWrongAnswers() throws {
        let game = try XCTUnwrap(try session(.crossword).game)
        let edits: [(inout [String: Any]) -> Void] = [
            { $0["crosswordAnswers"] = [game.crossword[0].id: "ZZZ"] },
            { $0["crosswordAnswers"] = ["unknown": "CAT"] },
            {
                var entries = $0["crossword"] as! [[String: Any]]
                entries[0]["row"] = -1
                $0["crossword"] = entries
            },
            {
                var entries = $0["crossword"] as! [[String: Any]]
                entries[0]["column"] = 999
                $0["crossword"] = entries
            },
            {
                var entries = $0["crossword"] as! [[String: Any]]
                entries[0]["answer"] = "ZZZ"
                $0["crossword"] = entries
            },
            {
                var entries = $0["crossword"] as! [[String: Any]]
                entries[0]["answer"] = String(repeating: "A", count: 100)
                $0["crossword"] = entries
            },
            {
                var entries = $0["crossword"] as! [[String: Any]]
                entries[1]["id"] = entries[0]["id"]
                $0["crossword"] = entries
            },
            {
                var entries = $0["crossword"] as! [[String: Any]]
                entries[0]["column"] = 5 // Disconnect the first across entry.
                $0["crossword"] = entries
            }
        ]
        for edit in edits {
            XCTAssertThrowsError(try JSONDecoder().decode(WakeGame.self, from: editedJSON(game, edit: edit)))
        }
    }

    func testDecoderRejectsProgressBeforeBeginningAndMemoryProgressInNewGame() throws {
        let wake = try session(.word)
        let corruptTapCount = try editedJSON(wake) { $0["correctTapCount"] = 1 }
        XCTAssertThrowsError(try JSONDecoder().decode(WakeSession.self, from: corruptTapCount))
        var active = wake
        active.beginChallenge(now: active.plan.targetDate)
        active.submit(.hint, now: active.plan.targetDate)
        let corruptArmed = try editedJSON(active) { $0["state"] = "armed" }
        XCTAssertThrowsError(try JSONDecoder().decode(WakeSession.self, from: corruptArmed))
    }
}
