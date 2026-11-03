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
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Smart Wake")
                                .font(.largeTitle.bold())
                            Text("A gentler start, one little game at a time.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        WakeSunrise(size: 76)
                    }
                    .padding(.top, 8)

                    Label(store.status, systemImage: "info.circle")
                        .font(.subheadline).accessibilityIdentifier("alarmStatus")

                    if let plan = store.plan {
                        armedCard(plan)
                    }

                    WakeCard {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(store.plan == nil ? "Set your wake-up" : "Change your wake-up")
                                    .font(.title2.bold())
                                Text(store.plan == nil
                                     ? "Choose a time and a game for your morning."
                                     : "These are draft changes. Your current alarm stays armed until you confirm an update.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            Picker("Wake mode", selection: $smart) {
                                Text("Set a time").tag(false)
                                Text("Smart window").tag(true)
                            }.pickerStyle(.segmented).disabled(store.busy).accessibilityIdentifier("wakeModePicker")

                            if smart {
                                smartWindowEditor
                            } else {
                                VStack(alignment: .leading, spacing: 0) {
                                    Label("Wake-up time", systemImage: "clock")
                                        .font(.headline)
                                    DatePicker("Wake-up time", selection: $manualTime, displayedComponents: .hourAndMinute)
                                        .datePickerStyle(.wheel).labelsHidden().frame(maxWidth: .infinity)
                                        .disabled(store.busy).accessibilityIdentifier("manualWakeTime")
                                }
                            }

                            Divider().overlay(.white.opacity(0.12))
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Morning game").font(.headline)
                                Picker("Wake-up game", selection: $gameKind) {
                                    Text("Daily rotation").tag(Optional<WakeGameKind>.none)
                                    Text("Five-letter word").tag(Optional(WakeGameKind.word))
                                    Text("Find the groups").tag(Optional(WakeGameKind.groups))
                                    Text("Mini crossword").tag(Optional(WakeGameKind.crossword))
                                }.pickerStyle(.menu).disabled(store.busy).accessibilityIdentifier("wakeGamePicker")
                                Text("Daily rotation picks a game for the wake-up date. Your progress is saved.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }

                            if let plan = store.plan {
                                Button("Update wake-up") {
                                    pendingUpdate = WakeUpEdit(sessionID: plan.id, manualTime: manualTime,
                                                               smart: smart, gameKind: gameKind)
                                    showUpdateConfirmation = true
                                }.buttonStyle(WakePrimaryButtonStyle()).disabled(store.busy)
                                    .accessibilityIdentifier("updateWakeUp")
                            } else {
                                Button {
                                    Task { await store.arm(manualTime: manualTime, smart: smart, gameKind: gameKind) }
                                } label: {
                                    Label(store.busy ? "Arming…" : "Arm wake-up", systemImage: "alarm.fill")
                                }.buttonStyle(WakePrimaryButtonStyle()).disabled(store.busy)
                                    .accessibilityIdentifier("armWakeUp")
                            }
                        }
                    }

                    WakeCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Keep a backup alarm", systemImage: "exclamationmark.shield")
                                .font(.headline)
                            Text("Smart Wake is a prototype. Keep a separate trusted alarm while testing. Delivery and audio depend on system permissions and device state.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }

                    DisclosureGroup("How reminders and Watch work") {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Up to 10 follow-ups are scheduled one minute apart after the wake-up or latest fallback. The smart fallback follow-ups run from 8:16 through 8:25; an earlier smart target can also have up to 10 reminders before 8:15. Solving the game cancels the rest. iOS always lets you stop an individual alarm.")
                                .font(.footnote).foregroundStyle(.secondary)
                            WatchStatusView(bridge: store.watch)
                        }.padding(.top, 10)
                    }
                }.padding(.horizontal, 20).padding(.bottom, 28)
            }
            .background(WakeBackdrop())
            .safeAreaInset(edge: .bottom) {
                Button("Emergency stop · cancel all alarms", role: .destructive) { store.cancelAll() }
                    .buttonStyle(.bordered).controlSize(.large)
                    .frame(maxWidth: .infinity).padding(12)
                    .background(.ultraThinMaterial)
            }
            .navigationBarTitleDisplayMode(.inline)
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

    private func armedCard(_ plan: WakePlan) -> some View {
        WakeCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Your next wake-up", systemImage: "alarm.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(WakePalette.sunrise)
                Text(plan.targetDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.title.bold())
                Text(planningExplanation(plan)).font(.footnote).foregroundStyle(.secondary)
                if let deadline = plan.latestWakeDate {
                    Text("Latest fallback: \(deadline.formatted(date: .omitted, time: .shortened))")
                        .font(.subheadline)
                }
                Text("Game: \(armedGameName)").font(.subheadline)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let unlocked = context.date >= plan.targetDate
                    Button(unlocked ? "Open wake-up game" : "Game opens at \(plan.targetDate.formatted(date: .omitted, time: .shortened))") {
                        store.beginPuzzle()
                    }.buttonStyle(.bordered).controlSize(.large).disabled(store.busy || !unlocked)
                        .accessibilityIdentifier("openWakeGame")
                }
                DisclosureGroup("Alarm details") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(store.scheduledCount) alarms currently registered · \(plan.timeZoneIdentifier)")
                        ForEach(plan.events, id: \.id) { event in
                            HStack {
                                Text(event.kind == .fallback ? "Fallback" : event.kind == .retry ? "Reminder" : "Wake-up")
                                Spacer()
                                Text(event.fireDate.formatted(date: .omitted, time: .shortened))
                            }
                        }
                    }.font(.footnote).foregroundStyle(.secondary).padding(.top, 8)
                }
            }
        }
    }

    private var smartWindowEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("6:30 – 8:15").font(.system(size: 36, weight: .bold, design: .rounded))
            Text("A bedtime and history-based target, with an 8:15 fallback armed first.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button { store.markBedtime() } label: {
                Label(store.bedtime == nil ? "I'm going to bed" : "Bedtime saved", systemImage: "moon.zzz.fill")
                    .frame(maxWidth: .infinity)
            }.buttonStyle(.bordered).controlSize(.large).disabled(store.busy)
            if let bedtime = store.effectiveBedtime {
                Text("Bedtime: \(bedtime.formatted(date: .omitted, time: .shortened))").font(.footnote).foregroundStyle(.secondary)
            }
            Text("Without a bedtime, the 8:15 fallback and its one-minute follow-ups are used. Without usable history, the target uses an 8-hour preference. This is not live sleep-stage detection.")
                .font(.footnote).foregroundStyle(.secondary)
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
