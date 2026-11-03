import Foundation

public enum WakeGameKind: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case word
    case groups
    case crossword
}

public enum WakeLetterResult: String, Codable, Equatable, Sendable {
    case exact
    case present
    case absent
}

public enum WakeGameAction: Equatable, Sendable {
    case guess(String)
    case group([String])
    case crossword(entryID: String, answer: String)
    case hint
}

public struct WakeWordGroup: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let words: [String]

    public init(id: String, title: String, words: [String]) {
        self.id = id
        self.title = title
        self.words = words
    }
}

public struct WakeCrosswordEntry: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let clue: String
    public let answer: String
    public let row: Int
    public let column: Int
    public let isAcross: Bool

    public init(id: String, clue: String, answer: String, row: Int, column: Int, isAcross: Bool) {
        self.id = id
        self.clue = clue
        self.answer = answer
        self.row = row
        self.column = column
        self.isAcross = isAcross
    }
}

/// Original, offline puzzles. The entire selected puzzle, tile order, hints and
/// progress are saved, so midnight, a time-zone change or a catalog update cannot
/// replace a puzzle that is already armed. These are gentle games, not wake tests.
public struct WakeGame: Codable, Equatable, Sendable {
    public let kind: WakeGameKind
    public let title: String
    public let instructions: String
    public let wordAnswer: String
    public let wordHint: String
    public private(set) var guesses: [String]
    public let groups: [WakeWordGroup]
    public let tileWords: [String]
    public private(set) var solvedGroupIDs: [String]
    public let crossword: [WakeCrosswordEntry]
    public private(set) var crosswordAnswers: [String: String]
    public private(set) var hintLevel: Int
    public private(set) var feedback: String

    // Retain the actual accepted selection, not an independently trusted solved flag.
    private var solvedGroupWords: [String: [String]]

    public var isSolved: Bool {
        switch kind {
        case .word: return guesses.last == wordAnswer
        case .groups: return !groups.isEmpty && solvedGroupIDs.count == groups.count
        case .crossword:
            return !crossword.isEmpty && crossword.allSatisfy { crosswordAnswers[$0.id] == $0.answer }
        }
    }

    var remainingCount: Int {
        switch kind {
        case .word: return isSolved ? 0 : 1
        case .groups: return groups.count - solvedGroupIDs.count
        case .crossword: return crossword.filter { crosswordAnswers[$0.id] != $0.answer }.count
        }
    }

    private init(kind: WakeGameKind, word: (String, String)? = nil,
                 groups: [WakeWordGroup] = [], tileWords: [String] = [],
                 crossword: [WakeCrosswordEntry] = []) {
        self.kind = kind
        switch kind {
        case .word:
            title = "Morning Word"
            instructions = "Find the five-letter word. Exact letters stay put; present letters belong elsewhere. Try as often as you like."
        case .groups:
            title = "Morning Groups"
            instructions = "Find two groups of four related words. Select four tiles, then check your group. No mistake limit."
        case .crossword:
            title = "Mini Cross"
            instructions = "Solve four clues in a shared grid. Each correct answer fills its crossing letters. Try as often as you like."
        }
        wordAnswer = word?.0 ?? ""
        wordHint = word?.1 ?? ""
        guesses = []
        self.groups = groups
        self.tileWords = tileWords
        solvedGroupIDs = []
        solvedGroupWords = [:]
        self.crossword = crossword
        crosswordAnswers = [:]
        hintLevel = 0
        feedback = ""
    }

    /// Rotates word → groups → crossword on consecutive Gregorian local dates.
    /// Selection uses calendar days, not elapsed 24-hour periods (important at DST).
    /// Explicit style selection still changes that style's puzzle with the date.
    public static func make(for date: Date, timeZone: TimeZone, kind: WakeGameKind? = nil) -> WakeGame {
        let day = localDayNumber(for: date, timeZone: timeZone)
        let selection = kind ?? WakeGameKind.allCases[positiveModulo(day, 3)]
        // Floor division means each visit to a style advances its catalog by one,
        // including for dates before the fixed epoch. Avoid randomized hashValue.
        let cycle = kind == nil ? (day - positiveModulo(day, 3)) / 3 : day
        switch selection {
        case .word:
            return WakeGame(kind: .word, word: words[positiveModulo(cycle, words.count)])
        case .groups:
            let pair = groupPairs[positiveModulo(cycle, groupPairs.count)]
            let groups = [
                WakeWordGroup(id: "group-1", title: pair.0, words: pair.1),
                WakeWordGroup(id: "group-2", title: pair.2, words: pair.3)
            ]
            var tiles = groups.flatMap(\.words)
            var seed = UInt64(bitPattern: Int64(day)) ^ 0xA0761D6478BD642F
            for index in stride(from: tiles.count - 1, through: 1, by: -1) {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                tiles.swapAt(index, Int(seed % UInt64(index + 1)))
            }
            return WakeGame(kind: .groups, groups: groups, tileWords: tiles)
        case .crossword:
            let mini = miniCrosswords[positiveModulo(cycle, miniCrosswords.count)]
            let entries = [
                WakeCrosswordEntry(id: "1A", clue: mini.1.1, answer: mini.1.0, row: 0, column: 0, isAcross: true),
                WakeCrosswordEntry(id: "2D", clue: mini.0.1, answer: mini.0.0, row: 0, column: 1, isAcross: false),
                WakeCrosswordEntry(id: "3A", clue: mini.2.1, answer: mini.2.0, row: 2, column: 0, isAcross: true),
                WakeCrosswordEntry(id: "4A", clue: mini.3.1, answer: mini.3.0, row: 4, column: 0, isAcross: true)
            ]
            return WakeGame(kind: .crossword, crossword: entries)
        }
    }

    /// Each answer letter is consumed once: exact matches first, then present
    /// matches from left to right. Invalid/mismatched lengths return no tiles.
    public static func letterFeedback(guess: String, answer: String) -> [WakeLetterResult] {
        guard let normalizedGuess = normalizedWord(guess),
              let normalizedAnswer = normalizedWord(answer),
              normalizedGuess.count == normalizedAnswer.count else { return [] }
        let attempted = Array(normalizedGuess)
        let expected = Array(normalizedAnswer)
        var result = Array(repeating: WakeLetterResult.absent, count: expected.count)
        var unmatched: [Character: Int] = [:]
        for index in expected.indices {
            if attempted[index] == expected[index] { result[index] = .exact }
            else { unmatched[expected[index], default: 0] += 1 }
        }
        for index in attempted.indices where result[index] != .exact {
            if unmatched[attempted[index], default: 0] > 0 {
                result[index] = .present
                unmatched[attempted[index], default: 0] -= 1
            }
        }
        return result
    }

    enum Submission { case ignored, incorrect, progress, solved }

    mutating func apply(_ action: WakeGameAction) -> Submission {
        guard !isSolved else { return .ignored }
        switch action {
        case .hint:
            revealHint()
            return .progress
        case .guess(let input):
            guard kind == .word else { return .ignored }
            guard let guess = Self.normalizedWord(input), guess.count == 5 else {
                feedback = "Enter five letters, with no spaces or numbers."
                return .incorrect
            }
            guesses.append(guess)
            if guess == wordAnswer {
                feedback = "You found it!"
                return .solved
            }
            feedback = "Keep going. There is no guess limit, and hints are always available."
            return .incorrect
        case .group(let inputs):
            guard kind == .groups else { return .ignored }
            let selected = inputs.compactMap(Self.normalizedWord)
            guard inputs.count == 4, selected.count == 4, Set(selected).count == 4 else {
                feedback = "Choose four different word tiles."
                return .incorrect
            }
            let available = Set(groups.filter { !solvedGroupIDs.contains($0.id) }.flatMap(\.words))
            guard Set(selected).isSubset(of: available) else {
                feedback = "Choose four tiles from the unsolved words."
                return .incorrect
            }
            guard let match = groups.first(where: { Set($0.words) == Set(selected) }) else {
                feedback = "Those four do not share a group. Try another combination, or ask for a hint."
                return .incorrect
            }
            solvedGroupIDs.append(match.id)
            solvedGroupWords[match.id] = selected
            feedback = "Found: \(match.title)."
            return isSolved ? .solved : .progress
        case .crossword(let entryID, let input):
            guard kind == .crossword,
                  let entry = crossword.first(where: { $0.id == entryID }),
                  crosswordAnswers[entryID] == nil else { return .ignored }
            guard let answer = Self.normalizedWord(input), answer.count == entry.answer.count else {
                feedback = "\(entry.id) needs \(entry.answer.count) letters."
                return .incorrect
            }
            guard answer == entry.answer else {
                feedback = "Not quite. Check the clue and the crossing letters, or ask for a hint."
                return .incorrect
            }
            crosswordAnswers[entryID] = answer
            feedback = "\(entry.id) is filled in."
            return isSolved ? .solved : .progress
        }
    }

    private mutating func revealHint() {
        hintLevel = min(3, hintLevel + 1)
        switch kind {
        case .word:
            switch hintLevel {
            case 1: feedback = "Hint: \(wordHint)"
            case 2: feedback = "It starts with \(wordAnswer.prefix(1)). \(wordHint)"
            default: feedback = "The word is \(wordAnswer). Enter it to finish."
            }
        case .groups:
            guard let group = groups.first(where: { !solvedGroupIDs.contains($0.id) }) else { return }
            switch hintLevel {
            case 1: feedback = "Look for: \(group.title)."
            case 2: feedback = "\(group.words[0]) and \(group.words[1]) belong in \(group.title.lowercased())."
            default: feedback = "\(group.title): \(group.words.joined(separator: ", ")). Select these four and check the group."
            }
        case .crossword:
            guard let entry = crossword.first(where: { crosswordAnswers[$0.id] == nil }) else { return }
            switch hintLevel {
            case 1: feedback = "\(entry.id) starts with \(entry.answer.prefix(1)) and has \(entry.answer.count) letters."
            case 2: feedback = "\(entry.id) starts with \(entry.answer.prefix(2)). Clue: \(entry.clue)"
            default: feedback = "\(entry.id) is \(entry.answer). Enter it for that clue."
            }
        }
    }

    /// Trims edges and accepts lowercase, accents and full-width Latin letters,
    /// but never silently removes punctuation, internal spaces, digits or emoji.
    private static func normalizedWord(_ input: String) -> String? {
        guard input.utf8.count <= 128 else { return nil }
        let result = input.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .uppercased(with: Locale(identifier: "en_US_POSIX"))
        guard !result.isEmpty, result.utf8.allSatisfy({ (65...90).contains($0) }) else { return nil }
        return result
    }

    private static func positiveModulo(_ value: Int, _ divisor: Int) -> Int {
        let remainder = value % divisor
        return remainder < 0 ? remainder + divisor : remainder
    }

    private static func localDayNumber(for date: Date, timeZone: TimeZone) -> Int {
        guard date.timeIntervalSinceReferenceDate.isFinite else { return 0 }
        var local = Calendar(identifier: .gregorian)
        local.timeZone = timeZone
        let components = local.dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let epoch = Date(timeIntervalSince1970: 946684800) // 2000-01-01 UTC
        guard let localDateInUTC = utc.date(from: components) else { return 0 }
        return utc.dateComponents([.day], from: epoch, to: localDateInUTC).day ?? 0
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(WakeGameKind.self, forKey: .kind)
        title = try container.decode(String.self, forKey: .title)
        instructions = try container.decode(String.self, forKey: .instructions)
        wordAnswer = try container.decode(String.self, forKey: .wordAnswer)
        wordHint = try container.decode(String.self, forKey: .wordHint)
        guesses = try container.decode([String].self, forKey: .guesses)
        groups = try container.decode([WakeWordGroup].self, forKey: .groups)
        tileWords = try container.decode([String].self, forKey: .tileWords)
        solvedGroupIDs = try container.decode([String].self, forKey: .solvedGroupIDs)
        solvedGroupWords = try container.decode([String: [String]].self, forKey: .solvedGroupWords)
        crossword = try container.decode([WakeCrosswordEntry].self, forKey: .crossword)
        crosswordAnswers = try container.decode([String: String].self, forKey: .crosswordAnswers)
        hintLevel = try container.decode(Int.self, forKey: .hintLevel)
        feedback = try container.decode(String.self, forKey: .feedback)
        guard hasValidContents else {
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container,
                debugDescription: "Saved game definitions or progress are inconsistent.")
        }
    }

    private var hasValidContents: Bool {
        guard !title.isEmpty, !instructions.isEmpty, (0...3).contains(hintLevel) else { return false }
        let emptyWord = wordAnswer.isEmpty && wordHint.isEmpty && guesses.isEmpty
        let emptyGroups = groups.isEmpty && tileWords.isEmpty && solvedGroupIDs.isEmpty && solvedGroupWords.isEmpty
        let emptyCrossword = crossword.isEmpty && crosswordAnswers.isEmpty
        switch kind {
        case .word:
            return emptyGroups && emptyCrossword && !wordHint.isEmpty &&
                Self.normalizedWord(wordAnswer) == wordAnswer && wordAnswer.count == 5 &&
                guesses.allSatisfy { Self.normalizedWord($0) == $0 && $0.count == 5 } &&
                !guesses.dropLast().contains(wordAnswer)
        case .groups:
            guard emptyWord, emptyCrossword, (2...4).contains(groups.count),
                  Set(groups.map(\.id)).count == groups.count,
                  groups.allSatisfy({ !$0.id.isEmpty && !$0.title.isEmpty && $0.words.count == 4 &&
                      $0.words.allSatisfy { Self.normalizedWord($0) == $0 } }) else { return false }
            let words = groups.flatMap(\.words)
            guard Set(words).count == words.count, tileWords.count == words.count,
                  Set(tileWords) == Set(words), Set(solvedGroupIDs).count == solvedGroupIDs.count,
                  Set(solvedGroupIDs).isSubset(of: Set(groups.map(\.id))),
                  Set(solvedGroupWords.keys) == Set(solvedGroupIDs) else { return false }
            return groups.allSatisfy { group in
                guard let selection = solvedGroupWords[group.id] else { return true }
                return selection.count == 4 && Set(selection) == Set(group.words)
            }
        case .crossword:
            return emptyWord && emptyGroups && Self.isValidCrossword(crossword) &&
                crosswordAnswers.allSatisfy { id, answer in
                    crossword.contains { $0.id == id && $0.answer == answer }
                }
        }
    }

    private struct Cell: Hashable { let row: Int; let column: Int }

    /// Reject contradictory intersections, disconnected entries, duplicate runs,
    /// and side-by-side letters that would create an un-clued answer.
    private static func isValidCrossword(_ entries: [WakeCrosswordEntry]) -> Bool {
        guard (3...8).contains(entries.count), Set(entries.map(\.id)).count == entries.count else { return false }
        var letters: [Cell: Character] = [:]
        var across: [Cell: String] = [:]
        var down: [Cell: String] = [:]
        var cellsByID: [String: [Cell]] = [:]
        for entry in entries {
            guard !entry.id.isEmpty, !entry.clue.isEmpty, normalizedWord(entry.answer) == entry.answer,
                  (2...7).contains(entry.answer.count), (0...8).contains(entry.row),
                  (0...8).contains(entry.column) else { return false }
            var occupied: [Cell] = []
            for (offset, letter) in entry.answer.enumerated() {
                let cell = Cell(row: entry.row + (entry.isAcross ? 0 : offset),
                                column: entry.column + (entry.isAcross ? offset : 0))
                guard cell.row <= 8, cell.column <= 8,
                      letters[cell] == nil || letters[cell] == letter,
                      (entry.isAcross ? across[cell] : down[cell]) == nil else { return false }
                letters[cell] = letter
                if entry.isAcross { across[cell] = entry.id } else { down[cell] = entry.id }
                occupied.append(cell)
            }
            cellsByID[entry.id] = occupied
        }
        var neighbors: [String: Set<String>] = [:]
        for cell in letters.keys {
            if let horizontal = across[cell], let vertical = down[cell] {
                neighbors[horizontal, default: []].insert(vertical)
                neighbors[vertical, default: []].insert(horizontal)
            }
            let right = Cell(row: cell.row, column: cell.column + 1)
            let below = Cell(row: cell.row + 1, column: cell.column)
            if letters[right] != nil, across[cell] == nil || across[cell] != across[right] { return false }
            if letters[below] != nil, down[cell] == nil || down[cell] != down[below] { return false }
        }
        // All entries must share a connected grid; isolated answers are not a crossword.
        var visited: Set<String> = []
        var pending = [entries[0].id]
        while let next = pending.popLast() {
            guard visited.insert(next).inserted else { continue }
            pending.append(contentsOf: neighbors[next, default: []])
        }
        return visited.count == entries.count && cellsByID.count == entries.count
    }

    // Authored here, not downloaded from or associated with any puzzle publisher.
    private static let words: [(String, String)] = [
        ("LIGHT", "It brightens a room when you switch on a lamp."),
        ("BRAVE", "Showing courage even while feeling afraid."),
        ("PLANT", "Give it soil, water and sunlight."),
        ("CLOUD", "A soft-looking shape that may bring rain."),
        ("SMILE", "A happy expression you can share without a word."),
        ("BREAD", "Slice this loaf for toast."),
        ("OCEAN", "A very large stretch of salty water."),
        ("TRAIL", "A path you might follow on a hike."),
        ("MUSIC", "Melody and rhythm make this."),
        ("HEART", "It beats inside your chest."),
        ("FRESH", "Newly made, picked or aired."),
        ("WATER", "Fill a glass with this to quench thirst."),
        ("PEACH", "A fuzzy fruit with a stone inside."),
        ("GREEN", "The usual color of healthy grass."),
        ("DREAM", "A story your mind may make while you sleep."),
        ("CHAIR", "Pull one up when you need a seat."),
        ("RIVER", "Flowing water on its way toward a lake or sea."),
        ("HONEY", "A sweet food made by bees."),
        ("SPARK", "A tiny flash that can start a fire."),
        ("BLOOM", "What a flower does when it opens."),
        ("SHORE", "Land beside a body of water."),
        ("APPLE", "A crisp fruit that can be baked in a pie."),
        ("QUIET", "Making very little sound."),
        ("EARTH", "The planet that is home to us."),
        ("MAPLE", "A tree whose sap can become syrup."),
        ("SHELL", "A hard outer covering you may find on a beach."),
        ("DANCE", "Move your body to the beat."),
        ("BERRY", "A small fruit, such as a raspberry."),
        ("STORY", "A tale with events and characters."),
        ("LEMON", "A sour yellow citrus fruit.")
    ]

    private static let groupPairs: [(String, [String], String, [String])] = [
        ("Kitchen utensils", ["WHISK", "LADLE", "SPATULA", "TONGS"], "Garden flowers", ["ROSE", "TULIP", "DAISY", "LILY"]),
        ("Shapes", ["CIRCLE", "SQUARE", "TRIANGLE", "OVAL"], "Farm animals", ["COW", "PIG", "GOAT", "SHEEP"]),
        ("Musical instruments", ["PIANO", "FLUTE", "VIOLIN", "DRUM"], "Citrus fruits", ["LEMON", "LIME", "ORANGE", "GRAPEFRUIT"]),
        ("Things on your feet", ["SOCK", "BOOT", "SLIPPER", "SANDAL"], "Parts of a tree", ["ROOT", "TRUNK", "BRANCH", "LEAF"]),
        ("Weather", ["RAIN", "SNOW", "HAIL", "SLEET"], "Desk supplies", ["PENCIL", "ERASER", "STAPLER", "RULER"]),
        ("Ocean animals", ["WHALE", "SHARK", "DOLPHIN", "OCTOPUS"], "Baked treats", ["COOKIE", "BROWNIE", "MUFFIN", "CUPCAKE"]),
        ("Ball sports", ["SOCCER", "TENNIS", "BASEBALL", "BASKETBALL"], "Winter clothes", ["SCARF", "MITTENS", "COAT", "BEANIE"]),
        ("Things with pages", ["BOOK", "MAGAZINE", "NOTEBOOK", "CATALOG"], "Flying insects", ["BEE", "MOTH", "BUTTERFLY", "DRAGONFLY"]),
        ("Herbs", ["BASIL", "THYME", "MINT", "PARSLEY"], "Gemstones", ["RUBY", "OPAL", "EMERALD", "SAPPHIRE"]),
        ("Breakfast foods", ["CEREAL", "PANCAKE", "OMELET", "PORRIDGE"], "Workshop tools", ["HAMMER", "SAW", "DRILL", "WRENCH"]),
        ("Things that tell time", ["CLOCK", "WATCH", "SUNDIAL", "HOURGLASS"], "Types of pasta", ["PENNE", "FUSILLI", "RIGATONI", "SPAGHETTI"]),
        ("Board game pieces", ["DICE", "PAWN", "TOKEN", "TILE"], "Birds", ["ROBIN", "SPARROW", "EAGLE", "PIGEON"])
    ]

    // A 5×3 grid: three 3-letter answers across cross one 5-letter answer down.
    // Black rows between the across answers leave only the down answer's cell.
    private static let miniCrosswords: [((String, String), (String, String), (String, String), (String, String))] = [
        (("LIGHT", "What a lamp gives off"), ("ELM", "A shade tree with a three-letter name"), ("EGG", "A breakfast food inside a shell"), ("ATE", "Had a meal, in the past")),
        (("SEEDS", "Small things planted to grow new plants"), ("ASK", "Pose a question"), ("NET", "A mesh used to catch fish"), ("USE", "Put a tool to work")),
        (("OCEAN", "A vast body of salty water"), ("FOX", "A bushy-tailed wild relative of the dog"), ("BED", "Furniture with a mattress"), ("ANT", "A tiny insect often found in a colony")),
        (("RIVER", "Water flowing along a natural channel"), ("ARM", "Body part between shoulder and wrist"), ("EVE", "The evening before a special day"), ("ART", "Painting and sculpture, for example")),
        (("PLANT", "A living thing with roots and leaves"), ("APE", "A primate with no tail"), ("CAT", "A pet that purrs"), ("ATE", "Finished eating, in the past")),
        (("CLOUD", "A floating collection of tiny water droplets"), ("ICE", "Frozen water"), ("DOG", "A pet that barks"), ("ADD", "Combine numbers to find a sum")),
        (("BREAD", "The loaf used to make toast"), ("EBB", "The tide's movement away from shore"), ("PEN", "A tool for writing in ink"), ("ODD", "Not divisible evenly by two")),
        (("DREAM", "An imagined scene while sleeping"), ("ODD", "Unusual, or not even"), ("RED", "The color of a ripe tomato"), ("EMU", "A large Australian bird that cannot fly")),
        (("HEART", "The organ that pumps blood"), ("AHA", "An exclamation when something clicks"), ("MAP", "A drawing that helps you find your way"), ("ATE", "Consumed food")),
        (("WATER", "The liquid in a glass from the tap"), ("OWL", "A bird known for hooting"), ("ATE", "Enjoyed a meal, in the past"), ("ARM", "A limb with an elbow")),
        (("MUSIC", "The art of melody and rhythm"), ("EMU", "A flightless bird from Australia"), ("ASK", "Request an answer"), ("ICE", "What water becomes in a freezer")),
        (("FRUIT", "Apples, pears and peaches, as a group"), ("AFT", "Toward the back of a boat"), ("SUN", "The star that lights our daytime sky"), ("ATE", "Took in a meal, in the past"))
    ]
}
