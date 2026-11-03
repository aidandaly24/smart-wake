import SwiftUI
import SmartWakeCore

struct HomeView: View {
    @ObservedObject var store: AlarmStore
    @State private var smart = false
    @State private var gameKind: WakeGameKind? = nil
    @State private var hasLoadedDraft = false
    @State private var showUpdateConfirmation = false
    @State private var pendingUpdate: WakeUpEdit?
    @State private var manualTime = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("A better first minute.").font(.largeTitle.bold())
                            Text("Wake up. Play a little. Get going.").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "sun.max.fill").font(.system(size: 42)).foregroundStyle(.mint)
                    }
                    if store.plan != nil {
                        Text("Edit below, then tap Update wake-up. Your current alarm stays armed while you make changes.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Picker("Wake mode", selection: $smart) {
                        Text("Set a time").tag(false)
                        Text("Smart window").tag(true)
                    }.pickerStyle(.segmented).disabled(store.busy).accessibilityIdentifier("wakeModePicker")

                    Group {
                        if smart {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("6:30 – 8:15").font(.system(size: 44, weight: .bold, design: .rounded))
                                Text("A bedtime + history-based target, with an 8:15 fallback armed first.")
                                Button { store.markBedtime() } label: {
                                    Label(store.bedtime == nil ? "I'm going to bed" : "Bedtime saved", systemImage: "moon.zzz.fill")
                                        .frame(maxWidth: .infinity)
                                }.buttonStyle(.bordered).disabled(store.busy)
                                if let bedtime = store.effectiveBedtime {
                                    Text("Bedtime: \(bedtime.formatted(date: .omitted, time: .shortened))").font(.footnote).foregroundStyle(.secondary)
                                }
                                Text("Without a bedtime, the 8:15 fallback and its one-minute follow-ups are used. Without usable history, the target uses an 8-hour preference. This is not live sleep-stage detection.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        } else {
                            DatePicker("Wake-up time", selection: $manualTime, displayedComponents: .hourAndMinute)
                                .datePickerStyle(.wheel).labelsHidden().frame(maxWidth: .infinity)
                                .disabled(store.busy).accessibilityIdentifier("manualWakeTime")
                        }
                    }.padding(20).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 24))

                    Group {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("Wake-up game", selection: $gameKind) {
                                Text("Daily rotation").tag(Optional<WakeGameKind>.none)
                                Text("Five-letter word").tag(Optional(WakeGameKind.word))
                                Text("Find the groups").tag(Optional(WakeGameKind.groups))
                                Text("Mini crossword").tag(Optional(WakeGameKind.crossword))
                            }.disabled(store.busy).accessibilityIdentifier("wakeGamePicker")
                            Text("Daily rotation changes with the wake-up date. The same saved alarm keeps its puzzle and progress. Choose a different style here, then arm or update to change games.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }

                    if let plan = store.plan {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Your next wake-up", systemImage: "alarm.fill").foregroundStyle(.mint)
                            Text(plan.targetDate.formatted(date: .abbreviated, time: .shortened)).font(.title2.bold())
                            Text(planningExplanation(plan)).font(.footnote).foregroundStyle(.secondary)
                            Text("\(store.scheduledCount) alarms currently registered · \(plan.timeZoneIdentifier)")
                                .font(.footnote).foregroundStyle(.secondary)
                            if let deadline = plan.latestWakeDate {
                                Text("Latest fallback: \(deadline.formatted(date: .omitted, time: .shortened))").font(.subheadline)
                            }
                            Text("Armed game: \(armedGameName)").font(.subheadline)
                            Button("Update wake-up") {
                                pendingUpdate = WakeUpEdit(sessionID: plan.id, manualTime: manualTime,
                                                         smart: smart, gameKind: gameKind)
                                showUpdateConfirmation = true
                            }.buttonStyle(.borderedProminent).disabled(store.busy)
                                .accessibilityIdentifier("updateWakeUp")
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                let unlocked = context.date >= plan.targetDate
                                Button(unlocked ? "Open wake-up game" : "Game unlocks at \(plan.targetDate.formatted(date: .omitted, time: .shortened))") {
                                    store.beginPuzzle()
                                }.buttonStyle(.bordered).disabled(store.busy || !unlocked)
                                    .accessibilityIdentifier("openWakeGame")
                            }
                            DisclosureGroup("See every planned alarm") {
                                ForEach(plan.events, id: \.id) { event in
                                    HStack {
                                        Text(event.kind == .fallback ? "Fallback" : event.kind == .retry ? "Reminder" : "Wake-up")
                                        Spacer()
                                        Text(event.fireDate.formatted(date: .omitted, time: .shortened))
                                    }.font(.footnote)
                                }
                            }
                        }
                    } else {
                        Button {
                            Task { await store.arm(manualTime: manualTime, smart: smart, gameKind: gameKind) }
                        } label: {
                            Label(store.busy ? "Arming…" : "Arm wake-up", systemImage: "alarm.fill")
                                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 10)
                        }.buttonStyle(.borderedProminent).disabled(store.busy)
                    }

                    Text(store.status).font(.subheadline).accessibilityIdentifier("alarmStatus")
                    WatchStatusView(bridge: store.watch)
                    VStack(alignment: .leading, spacing: 10) {
                        Label("A nudge, never a lock-in", systemImage: "hand.raised.fill").font(.headline)
                        Text("Up to 10 pre-scheduled follow-ups, one minute apart, after the wake-up or latest fallback. Smart fallback follow-ups run from 8:16 through 8:25; an earlier smart target can also have up to 10 reminders before 8:15. Solving the game cancels the rest. iOS always lets you stop an individual alarm; this app cannot prevent it.")
                        Text("Prototype: keep a separate trusted alarm until tested on your iPhone and Watch. Delivery, audio and Watch mirroring depend on the OS, permissions and device state.")
                    }.font(.footnote).foregroundStyle(.secondary)
                    Button("Emergency stop · cancel all alarms", role: .destructive) { store.cancelAll() }
                        .buttonStyle(.bordered).frame(maxWidth: .infinity)
                }.padding(24)
            }
            .background(Color(red: 0.035, green: 0.055, blue: 0.09))
            .navigationTitle("Smart Wake").navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $store.showPuzzle) { PuzzleView(store: store) }
            .onAppear(perform: loadSavedDraftOnce)
            .alert("Replace your current wake-up?", isPresented: $showUpdateConfirmation, presenting: pendingUpdate) { edit in
                Button("Keep current alarm", role: .cancel) { }
                Button("Update wake-up", role: .destructive) {
                    Task {
                        await store.arm(manualTime: edit.manualTime, smart: edit.smart,
                                        gameKind: edit.gameKind, replacingSessionID: edit.sessionID)
                    }
                }
            } message: { edit in
                Text("This stops the current alarms and arms \(edit.smart ? "the 6:30–8:15 smart window" : edit.manualTime.formatted(date: .omitted, time: .shortened)) with your selected game. If replacement fails, you may have no alarm. Keep a separate trusted backup.")
            }
        }
    }

    private struct WakeUpEdit {
        let sessionID: UUID
        let manualTime: Date
        let smart: Bool
        let gameKind: WakeGameKind?
    }

    private var armedGameName: String {
        store.wakeSession?.game?.title ?? "Memory pattern (saved earlier session)"
    }

    private func loadSavedDraftOnce() {
        guard !hasLoadedDraft else { return }
        hasLoadedDraft = true
        guard let session = store.wakeSession else { return }
        switch session.plan.mode {
        case .smart: smart = true
        case .manual(let clock):
            smart = false
            manualTime = Calendar.current.date(bySettingHour: clock.hour, minute: clock.minute,
                                               second: 0, of: Date()) ?? manualTime
        }
        // Old saves do not record whether the style originally came from Daily
        // rotation. Show its concrete saved style rather than inventing that choice.
        gameKind = session.game?.kind
    }

    private func planningExplanation(_ plan: WakePlan) -> String {
        switch plan.basis {
        case .manualSelection: return "Your chosen time, followed by bounded one-minute reminders."
        case .bedtimeAndRecentHistory: return "Target based on bedtime and the median of recent usable sleep history."
        case .bedtimeAndPreferredDuration: return "No usable recent history. Target uses bedtime plus an eight-hour preference."
        case .fallbackWithoutRecentBedtime: return "No recent bedtime was available. The latest fallback and its one-minute follow-ups are planned."
        }
    }
}

private struct WatchStatusView: View {
    @ObservedObject var bridge: WatchBridge
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Watch companion", systemImage: "applewatch").font(.headline)
            Text(bridge.status).font(.footnote).foregroundStyle(.secondary)
            Text("On Watch: allow sleep access, refresh history, then send the summary to this iPhone. It stays on your paired devices.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}
