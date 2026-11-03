import SwiftUI

@main
struct SmartWakeApp: App {
    @StateObject private var store = AlarmStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            HomeView(store: store)
                .preferredColorScheme(.dark)
                .tint(.mint)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { store.refresh() }
                }
        }
    }
}
