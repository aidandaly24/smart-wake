import SwiftUI

@main
@MainActor
struct SmartWakeWatchApp: App {
    @StateObject private var model = WatchModel()
    @StateObject private var connection = WatchPhoneConnection()

    var body: some Scene {
        WindowGroup {
            WatchHomeView(model: model, connection: connection)
        }
    }
}
