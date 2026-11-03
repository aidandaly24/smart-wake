import SwiftUI
import SmartWakeCore

struct PuzzleView: View {
    @ObservedObject var store: AlarmStore

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                WakeSunrise(size: 76)
                    .padding(.top, 8)
                VStack(spacing: 6) {
                    Text("Good morning.")
                        .font(.largeTitle.bold())
                    Text("One little game, then you're on your way.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if let session = store.wakeSession {
                    if let game = session.game, session.state == .answering {
                        WakeCard {
                            DailyWakeGameView(game: game, submit: store.submitGame)
                        }
                    } else if session.state == .memorizing {
                        Text("Remember these symbols, in order.").multilineTextAlignment(.center)
                        HStack(spacing: 18) {
                            ForEach(Array(session.challenge.sequence.enumerated()), id: \.offset) { index, token in
                                VStack(spacing: 8) {
                                    Image(systemName: token.symbol).font(.title)
                                    Text(token.label).font(.caption)
                                    Text("\(index + 1)").font(.caption2).foregroundStyle(.secondary)
                                }.accessibilityElement(children: .combine)
                            }
                        }.padding(.vertical, 20)
                        Button("Got it · hide the pattern") { store.hideSequence() }.buttonStyle(.borderedProminent)
                    } else if session.state == .answering {
                        Text("Tap the symbols in the same order.")
                        Text("\(session.correctTapCount) / \(session.challenge.sequence.count)").font(.title.monospacedDigit())
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            ForEach(MemoryToken.allCases, id: \.self) { token in
                                Button { store.submit(token) } label: {
                                    VStack(spacing: 12) {
                                        Image(systemName: token.symbol).font(.largeTitle)
                                        Text(token.label).font(.headline)
                                    }.frame(maxWidth: .infinity).padding(.vertical, 24)
                                }.buttonStyle(.bordered)
                            }
                        }
                        Text("A missed tap shows the pattern again. No penalties.").font(.footnote).foregroundStyle(.secondary)
                    } else if session.state == .completed {
                        Text("Puzzle complete!").font(.title2.bold())
                        Button("Retry cancelling remaining alarms") { store.finishPuzzle() }.buttonStyle(.borderedProminent)
                    } else if session.isTerminal {
                        Text("Stopping your alarms").font(.title2.bold())
                        Button("Retry emergency stop", role: .destructive) { store.cancelAll() }.buttonStyle(.borderedProminent)
                    }
                }
                Text(store.status).font(.footnote).multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button("Back to alarm · keep reminders") { store.showPuzzle = false }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }.padding(.horizontal, 20).padding(.bottom, 24)
        }.background(WakeBackdrop())
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                Button("Emergency stop · cancel all alarms", role: .destructive) { store.cancelAll() }
                    .buttonStyle(.bordered).controlSize(.large)
                    .frame(maxWidth: .infinity).padding(12)
                    .background(.ultraThinMaterial)
            }
    }
}

/// Original short puzzles. Each action goes through the persisted session before
/// the alarm adapter can cancel anything. No timer, attempt limit or lock-in.
private struct DailyWakeGameView: View {
    let game: WakeGame
    let submit: (WakeGameAction) -> Void
    @State private var guess = ""
    @State private var selection: Set<String> = []
    @State private var selectedClueID: String?
    @State private var crosswordInput = ""

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text(game.title).font(.title2.bold())
                Text(game.instructions).font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity)
            switch game.kind {
            case .word: wordGame
            case .groups: groupGame
            case .crossword: crosswordGame
            }
            if !game.feedback.isEmpty {
                Text(game.feedback)
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(WakePalette.lavender.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("puzzleFeedback")
            }
            Button { submit(.hint) } label: { Label("Give me a hint", systemImage: "lightbulb") }
                .buttonStyle(.bordered)
            Text("No time limit or lost lives. Your progress is saved.")
                .font(.caption).foregroundStyle(.secondary)
        }.onChange(of: game.guesses) { _, _ in
            // Clear only after the guess has actually been saved. Invalid input
            // and persistence failures remain available for correction.
            guess = ""
        }.onChange(of: game.crosswordAnswers) { _, _ in
            crosswordInput = ""
            selectedClueID = nil
        }.onChange(of: game.solvedGroupIDs) { _, _ in
            // Keep rejected groups and failed saves selected for correction.
            selection.removeAll()
        }
    }

    private var wordGame: some View {
        VStack(spacing: 12) {
            ForEach(Array(game.guesses.enumerated()), id: \.offset) { _, word in
                wordRow(word, results: WakeGame.letterFeedback(guess: word, answer: game.wordAnswer))
            }
            wordRow(guess.uppercased(), results: [])
            HStack(spacing: 10) {
                TextField("Five letters", text: $guess)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder).submitLabel(.go)
                    .accessibilityLabel("Five-letter guess")
                    .onSubmit(submitWord)
                Button("Guess", action: submitWord)
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }
            Text("● Right spot   ◐ Elsewhere   − No match left")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityLabel("Filled circle: right spot. Half circle: elsewhere. Dash: no unmatched occurrence left in the answer.")
        }
    }

    private func submitWord() {
        submit(.guess(guess))
    }

    private func wordRow(_ word: String, results: [WakeLetterResult]) -> some View {
        let letters = Array(word)
        return HStack(spacing: 8) {
            ForEach(0..<5) { index in
                let result = results.indices.contains(index) ? results[index] : nil
                let letter = letters.indices.contains(index) ? String(letters[index]) : ""
                VStack(spacing: 1) {
                    Text(letter.isEmpty ? " " : letter).font(.title2.bold().monospaced())
                    if let result {
                        Text(letterMark(result)).font(.caption2.bold()).accessibilityHidden(true)
                    }
                }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .foregroundStyle(result == .exact || result == .present ? Color.black : Color.white)
                    .background(letterColor(result), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(result == nil ? 0.16 : 0)))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(letterAccessibility(letter, result: result, position: index + 1))
            }
        }
    }

    private func letterMark(_ result: WakeLetterResult) -> String {
        switch result {
        case .exact: return "●"
        case .present: return "◐"
        case .absent: return "−"
        }
    }

    private func letterColor(_ result: WakeLetterResult?) -> Color {
        switch result {
        case .exact: return .mint
        case .present: return .yellow
        case .absent: return .gray.opacity(0.45)
        case nil: return .white.opacity(0.10)
        }
    }

    private func letterAccessibility(_ letter: String, result: WakeLetterResult?, position: Int) -> String {
        let state: String
        switch result {
        case .exact: state = "correct position"
        case .present: state = "in the word, different position"
        case .absent: state = "not an unmatched letter in the answer"
        case nil: state = "not submitted"
        }
        return "Position \(position), \(letter.isEmpty ? "empty" : letter), \(state)"
    }

    private var groupGame: some View {
        VStack(spacing: 12) {
            ForEach(game.groups.filter { game.solvedGroupIDs.contains($0.id) }, id: \.id) { group in
                VStack(spacing: 5) {
                    Text(group.title).font(.headline)
                    Text(group.words.joined(separator: " · ")).font(.caption)
                }.frame(maxWidth: .infinity).padding(14)
                    .foregroundStyle(.black).background(.mint, in: RoundedRectangle(cornerRadius: 14))
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(remainingTiles, id: \.self) { word in
                    Button {
                        if selection.contains(word) { selection.remove(word) }
                        else if selection.count < 4 { selection.insert(word) }
                    } label: {
                        Text(word).font(.subheadline.bold()).minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .foregroundStyle(selection.contains(word) ? Color.black : Color.white)
                            .background(selection.contains(word) ? Color.mint : Color.white.opacity(0.10),
                                        in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain)
                        .accessibilityAddTraits(selection.contains(word) ? .isSelected : [])
                }
            }
            HStack {
                Button("Clear") { selection.removeAll() }.buttonStyle(.bordered)
                Button("Check \(selection.count)/4") {
                    submit(.group(selection.sorted()))
                }.buttonStyle(.borderedProminent).disabled(selection.count != 4)
            }
        }
    }

    private var remainingTiles: [String] {
        let solved = Set(game.groups.filter { game.solvedGroupIDs.contains($0.id) }.flatMap(\.words))
        return game.tileWords.filter { !solved.contains($0) }
    }

    private var activeClue: WakeCrosswordEntry? {
        game.crossword.first { $0.id == selectedClueID && game.crosswordAnswers[$0.id] == nil }
            ?? game.crossword.first { game.crosswordAnswers[$0.id] == nil }
            ?? game.crossword.first
    }

    private var crosswordGame: some View {
        VStack(spacing: 14) {
            crosswordGrid
            ForEach(game.crossword, id: \.id) { entry in
                Button {
                    selectedClueID = entry.id
                    crosswordInput = game.crosswordAnswers[entry.id] ?? ""
                } label: {
                    HStack(alignment: .top) {
                        Image(systemName: game.crosswordAnswers[entry.id] == nil ? "square" : "checkmark.square.fill")
                        Text("\(clueNumber(entry)) \(entry.isAcross ? "Across" : "Down"): \(entry.clue) (\(entry.answer.count))")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.font(.subheadline).padding(10)
                        .background(activeClue?.id == entry.id ? Color.mint.opacity(0.15) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).disabled(game.crosswordAnswers[entry.id] != nil)
            }
            if let entry = activeClue {
                Text("\(clueNumber(entry)) \(entry.isAcross ? "Across" : "Down")")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField("\(entry.answer.count)-letter answer", text: $crosswordInput)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder).submitLabel(.go)
                        .accessibilityLabel("Answer for \(clueNumber(entry)) \(entry.isAcross ? "Across" : "Down")")
                        .onSubmit(submitCrossword)
                    Button("Fill", action: submitCrossword).buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func submitCrossword() {
        guard let entry = activeClue else { return }
        selectedClueID = entry.id
        submit(.crossword(entryID: entry.id, answer: crosswordInput))
        // Only accepted answers change crosswordAnswers and advance the clue.
        // Rejected answers keep the selected clue and the text for correction.
    }

    private var gridWidth: Int {
        max(1, game.crossword.map { $0.column + ($0.isAcross ? $0.answer.count : 1) }.max() ?? 1)
    }

    private var gridHeight: Int {
        max(1, game.crossword.map { $0.row + ($0.isAcross ? 1 : $0.answer.count) }.max() ?? 1)
    }

    private func clueNumber(_ entry: WakeCrosswordEntry) -> Int {
        let starts = Set(game.crossword.map { $0.row * gridWidth + $0.column }).sorted()
        return (starts.firstIndex(of: entry.row * gridWidth + entry.column) ?? 0) + 1
    }

    private func covers(_ entry: WakeCrosswordEntry, row: Int, column: Int) -> Bool {
        entry.isAcross
            ? row == entry.row && (entry.column..<(entry.column + entry.answer.count)).contains(column)
            : column == entry.column && (entry.row..<(entry.row + entry.answer.count)).contains(row)
    }

    private var crosswordGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: gridWidth), spacing: 4) {
            ForEach(0..<(gridWidth * gridHeight), id: \.self) { index in
                let row = index / gridWidth
                let column = index % gridWidth
                let entries = game.crossword.filter { covers($0, row: row, column: column) }
                let solvedEntry = entries.first { game.crosswordAnswers[$0.id] != nil }
                let letter: String = solvedEntry.map {
                    let offset = $0.isAcross ? column - $0.column : row - $0.row
                    return String(Array($0.answer)[offset])
                } ?? ""
                let start = game.crossword.first { $0.row == row && $0.column == column }
                let highlighted = activeClue.map { covers($0, row: row, column: column) } ?? false
                Text(letter).font(.title3.bold().monospaced())
                    .frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
                    .background(entries.isEmpty ? Color.clear : highlighted ? Color.mint.opacity(0.25) : Color.white.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 5))
                    .overlay(alignment: .topLeading) {
                        if let start { Text("\(clueNumber(start))").font(.system(size: 9)).padding(3) }
                    }
                    .accessibilityLabel(entries.isEmpty ? "Blocked cell" : "Row \(row + 1), column \(column + 1), \(letter.isEmpty ? "empty" : letter)")
            }
        }.frame(maxWidth: 320)
    }
}
