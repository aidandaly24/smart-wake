import Combine
import Foundation
import WatchConnectivity

@MainActor
final class WatchPhoneConnection: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var status = "Connecting to iPhone…"
    @Published private(set) var canSend = false
    private var session: WCSession?

    override init() {
        super.init()
        guard WCSession.isSupported() else {
            status = "Watch Connectivity is unavailable."
            return
        }
        let session = WCSession.default
        self.session = session
        session.delegate = self
        session.activate()
    }

    func refreshConnection() {
        guard let session else { return }
        canSend = session.activationState == .activated
        if !canSend { session.activate() }
    }

    /// The explicit user action sends a summary only to the paired companion app.
    /// Queued means accepted by WatchConnectivity, not confirmed delivered to the phone.
    func send(_ summary: WatchSummary) {
        guard let session, session.activationState == .activated else {
            status = "Connection is not ready. Open Smart Wake on both devices and try again."
            return
        }
        let context = summary.propertyList
        do {
            // Leave margin under WatchConnectivity's payload budget; never silently drop sleep.
            let encoded = try PropertyListSerialization.data(
                fromPropertyList: context, format: .binary, options: 0
            )
            guard encoded.count <= 48 * 1_024 else {
                status = "This summary is too large to transfer. No sleep records were sent."
                return
            }
            try session.updateApplicationContext(context)
            status = "Summary queued for iPhone. Open the phone app to confirm arrival and arm your alarm."
        } catch {
            status = "Summary could not be queued. Open both apps and try again."
        }
    }

    // WatchConnectivity calls delegates on its serial background queue. Extract primitive values
    // there, then enter MainActor; neither WCSession nor Error is captured by the Task.
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        let activated = activationState == .activated
        let failed = error != nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            canSend = activated && !failed
            if failed {
                status = "iPhone connection failed. Reopen both apps to try again."
            } else if !activated {
                status = "Waiting for the iPhone connection."
            } else {
                status = "Ready to queue a summary for the paired iPhone."
            }
        }
    }

}
