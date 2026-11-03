import SwiftUI

struct WatchHomeView: View {
    @ObservedObject var model: WatchModel
    @ObservedObject var connection: WatchPhoneConnection
    @Environment(\.scenePhase) private var scenePhase
    @State private var recordingHours = 8

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Tonight starts here")
                        .font(.headline)
                    Text("This companion collects history. Arm your alarm on iPhone; this watch app cannot wake you.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    bedtimeSection
                    Divider()
                    healthSection
                    Divider()
                    motionSection
                    Divider()
                    transferSection
                    Divider()
                    Text("Prototype, not a medical device. No live sleep-stage detection, timed background wake, or smart-wake guarantee. Keep an Apple Clock backup alarm.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle("Smart Wake")
            .task {
                connection.refreshConnection()
                await model.refreshCapability()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    connection.refreshConnection()
                    Task { await model.refreshCapability() }
                }
            }
        }
    }

    private var bedtimeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                model.markBedtime()
            } label: {
                Label("I'm going to bed", systemImage: "moon.stars.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
            .disabled(model.isBusy)
            if let bedtime = model.bedtimeAt {
                Text("Bedtime: \(bedtime.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote)
                Button("Clear bedtime") { model.clearBedtime() }
                    .font(.footnote)
                    .disabled(model.isBusy)
            }
            Text("Saves a timestamp only. It does not start recording or set an alarm.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var healthSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Sleep history", systemImage: "bed.double.fill")
                .font(.headline)
            Text(model.sleep.message)
                .font(.footnote)
            if !model.sleep.intervals.isEmpty {
                Text("\(model.sleep.intervals.count) merged sleep intervals")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button(model.healthRequestAttempted ? "Review sleep access" : "Read sleep history") {
                Task { await model.requestSleepAccess() }
            }
            .disabled(model.isBusy)
            Text("Read-only Health access. No sleep records are written or uploaded.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var motionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Overnight motion", systemImage: "waveform.path")
                .font(.headline)
            Text(model.motion.message)
                .font(.footnote)
            Picker("Record for", selection: $recordingHours) {
                ForEach([6, 8, 10, 12], id: \.self) { hours in
                    Text("\(hours) hours").tag(hours)
                }
            }
            .disabled(model.recordingRequestedForFuture || model.isBusy)
            Button("Record motion") {
                Task { await model.recordMotion(hours: recordingHours) }
            }
            .disabled(!model.canRequestRecording)
            if let window = model.recordingWindow {
                Text("Requested through \(window.end.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if model.motion.sampleCount > 0 {
                Text("\(model.motion.sampleCount.formatted()) samples summarized")
                    .font(.footnote)
            }
            Text("Optional motion permission. Apple records for the requested duration, up to 12 hours. This API has no stop button. Samples may be delayed and are retained for up to 3 days. Summary values include gravity, not sleep stages.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Refresh summaries") {
                Task { await model.refreshSummary() }
            }
            .disabled(model.isBusy)
        }
    }

    private var transferSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your devices only")
                .font(.headline)
            Text("Sends sleep intervals, bedtime, and aggregate motion to your paired iPhone. No raw motion or server upload.")
                .font(.footnote)
            Button("Send summary to iPhone") {
                Task { await model.sendSummary(using: connection) }
            }
            .disabled(model.isBusy || !connection.canSend)
            if model.isBusy {
                ProgressView("Working…")
                    .font(.footnote)
            }
            Text(connection.status)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
