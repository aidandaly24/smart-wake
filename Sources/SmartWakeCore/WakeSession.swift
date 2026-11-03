import Foundation

/// An original, short memory sequence. No proprietary puzzle content is used.
public enum MemoryToken: String, CaseIterable, Codable, Hashable, Sendable {
    case sun
    case moon
    case leaf
    case wave

    public var label: String {
        switch self {
        case .sun: return "Sun"
        case .moon: return "Moon"
        case .leaf: return "Leaf"
        case .wave: return "Wave"
        }
    }

    /// SF Symbols name for UI adapters. The core itself does not import SwiftUI.
    public var symbol: String {
        switch self {
        case .sun: return "sun.max.fill"
        case .moon: return "moon.stars.fill"
        case .leaf: return "leaf.fill"
        case .wave: return "water.waves"
        }
    }
}

public enum MemoryChallengeError: Error, Equatable, Sendable {
    case invalidLength
}

public struct MemoryChallenge: Codable, Equatable, Sendable {
    public let sequence: [MemoryToken]

    public init(sequence: [MemoryToken]) throws {
        guard (3...6).contains(sequence.count) else {
            throw MemoryChallengeError.invalidLength
        }
        self.sequence = sequence
    }

    private init(randomLength: Int) {
        let choices = MemoryToken.allCases
        self.sequence = (0..<randomLength).map { _ in
            choices[Int.random(in: 0..<choices.count)]
        }
    }

    public static func random(length: Int = 4) -> Self {
        Self(randomLength: min(6, max(3, length)))
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(sequence: container.decode([MemoryToken].self, forKey: .sequence))
    }
}

public enum WakeSessionState: String, Codable, Equatable, Sendable {
    case armed
    case memorizing
    case answering
    case completed
    case cancelled
    case emergencyExited

    public var isTerminal: Bool {
        switch self {
        case .completed, .cancelled, .emergencyExited: return true
        case .armed, .memorizing, .answering: return false
        }
    }
}

public enum PuzzleSubmission: Equatable, Sendable {
    case ignored
    case incorrect
    case progress(remaining: Int)
    case completed(cancelAlarmIDs: [UUID])
}

/// Session state and cancellation intent are persisted together.
///
/// A terminal state means the user is done, not proof that OS cancellation worked.
/// The platform adapter must cancel `alarmIDsToCancel`, retry on failure, and avoid
/// announcing that alarms are off until the platform confirms removal. The model
/// never traps a user: cancel and emergency exit work without solving the puzzle.
public struct WakeSession: Codable, Equatable, Sendable {
    public let plan: WakePlan
    public let challenge: MemoryChallenge
    public private(set) var game: WakeGame?
    public private(set) var state: WakeSessionState
    public private(set) var correctTapCount: Int

    /// New sessions rotate original games by the target date in the armed zone.
    /// The optional choice is saved as a complete puzzle, not regenerated at play time.
    public init(plan: WakePlan, gameKind: WakeGameKind? = nil) {
        self.plan = plan
        self.challenge = .random() // Kept solely for compatibility with legacy sessions.
        self.game = WakeGame.make(for: plan.targetDate,
            timeZone: TimeZone(identifier: plan.timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)!,
            kind: gameKind)
        self.state = .armed
        self.correctTapCount = 0
    }

    /// Explicit memory challenges preserve the original API and saved-session behavior.
    public init(plan: WakePlan, challenge: MemoryChallenge) {
        self.plan = plan
        self.challenge = challenge
        self.game = nil
        self.state = .armed
        self.correctTapCount = 0
    }

    public var isTerminal: Bool { state.isTerminal }

    /// Remains available after persistence/relaunch for idempotent OS cleanup.
    public var alarmIDsToCancel: [UUID] { isTerminal ? plan.eventIDs : [] }

    /// A challenge may start or resume only once its scheduled wake time arrives.
    /// Check on every action too: restored progress or a clock adjustment must not
    /// let a puzzle complete early and cancel alarms that have not fired yet.
    public func canPlay(at date: Date) -> Bool {
        !isTerminal && date.timeIntervalSinceReferenceDate.isFinite && date >= plan.targetDate
    }

    @discardableResult
    public mutating func beginChallenge(now: Date = Date()) -> Bool {
        guard canPlay(at: now), state == .armed else { return false }
        state = game == nil ? .memorizing : .answering
        return true
    }

    @discardableResult
    public mutating func hideSequence() -> Bool {
        guard game == nil, state == .memorizing else { return false }
        state = .answering
        return true
    }

    @discardableResult
    public mutating func submit(_ token: MemoryToken, now: Date = Date()) -> PuzzleSubmission {
        guard canPlay(at: now), game == nil, state == .answering,
              challenge.sequence.indices.contains(correctTapCount) else { return .ignored }
        guard token == challenge.sequence[correctTapCount] else {
            correctTapCount = 0
            state = .memorizing
            return .incorrect
        }
        correctTapCount += 1
        if correctTapCount == challenge.sequence.count {
            state = .completed
            return .completed(cancelAlarmIDs: plan.eventIDs)
        }
        return .progress(remaining: challenge.sequence.count - correctTapCount)
    }

    @discardableResult
    public mutating func submit(_ action: WakeGameAction, now: Date = Date()) -> PuzzleSubmission {
        guard canPlay(at: now), state == .answering, var activeGame = game else { return .ignored }
        let result = activeGame.apply(action)
        game = activeGame
        switch result {
        case .ignored: return .ignored
        case .incorrect: return .incorrect
        case .progress: return .progress(remaining: activeGame.remainingCount)
        case .solved:
            state = .completed
            return .completed(cancelAlarmIDs: plan.eventIDs)
        }
    }

    @discardableResult
    public mutating func cancel() -> [UUID] {
        terminate(as: .cancelled)
    }

    @discardableResult
    public mutating func emergencyExit() -> [UUID] {
        terminate(as: .emergencyExited)
    }

    private mutating func terminate(as terminalState: WakeSessionState) -> [UUID] {
        guard !isTerminal else { return [] }
        state = terminalState
        return plan.eventIDs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        plan = try container.decode(WakePlan.self, forKey: .plan)
        challenge = try container.decode(MemoryChallenge.self, forKey: .challenge)
        state = try container.decode(WakeSessionState.self, forKey: .state)
        correctTapCount = try container.decode(Int.self, forKey: .correctTapCount)
        // Absence means a pre-games memory session. Never replace its challenge.
        game = try container.decodeIfPresent(WakeGame.self, forKey: .game)
        if let game {
            guard correctTapCount == 0, state != .memorizing,
                  state != .completed || game.isSolved,
                  ![WakeSessionState.armed, .answering].contains(state) || !game.isSolved,
                  state != .armed || (game.guesses.isEmpty && game.solvedGroupIDs.isEmpty &&
                      game.crosswordAnswers.isEmpty && game.hintLevel == 0 && game.feedback.isEmpty) else {
                throw DecodingError.dataCorruptedError(forKey: .game, in: container,
                    debugDescription: "Saved game progress does not match the session state.")
            }
            return
        }
        guard (0...challenge.sequence.count).contains(correctTapCount),
              state != .completed || correctTapCount == challenge.sequence.count,
              state != .answering || correctTapCount < challenge.sequence.count,
              ![WakeSessionState.armed, .memorizing].contains(state) || correctTapCount == 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .correctTapCount,
                in: container,
                debugDescription: "Persisted puzzle progress does not match its state."
            )
        }
    }
}
