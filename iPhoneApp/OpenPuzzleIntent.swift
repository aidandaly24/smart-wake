import AlarmKit
import AppIntents

struct WakeMetadata: AlarmMetadata {
    var sessionID: String
}

struct OpenPuzzleIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Play wake-up puzzle"
    static var description = IntentDescription("Open Smart Wake's memory puzzle for this alarm.")
    static var openAppWhenRun = true

    @Parameter(title: "Wake session") var sessionID: String

    init() { sessionID = "" }
    init(sessionID: String) { self.sessionID = sessionID }

    func perform() async throws -> some IntentResult {
        await MainActor.run { AlarmStore.shared.openPuzzle(sessionID: sessionID) }
        return .result()
    }
}
