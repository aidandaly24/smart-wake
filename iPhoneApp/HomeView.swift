import SwiftUI
import SmartWakeCore

struct HomeView: View {
    @ObservedObject var store: AlarmStore
    @State private var smart = false
    @State private var gameKind: WakeGameKind? = nil
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
                    Picker("Wake mode", selection: $smart) {
                        Text("Set a time").tag(false)
                        Text("Smart window").tag(true)
                    }.pickerStyle(.segmented).disabled(store.plan != nil || store.busy)

                    Group {
                        if smart {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("6:30 – 8:15").font(.system(size: 44, weight: .bold, design: .rounded))
                                Text("A bedtime + history-based target, with an 8:15 fallback armed first.")
                                Button { store.markBedtime() } label: {
                                    Label(store.bedtime == nil ? "I'm going to bed" : "Bedtime saved", systemImage: "moon.zzz.fill")
                                        .frame(maxWidth: .infinity)
                                }.buttonStyle(.bordered)
                                if let bedtime = store.effectiveBedtime {
                                    Text("Bedtime: \(bedtime.formatted(date: .omitted, time: .shortened))").font(.footnote).foregroundStyle(.secondary)
                                }
                                Text("Without a bedtime, the 8:15 fallback and its one-minute follow-ups are used. Without usable history, the target uses an 8-hour preference. This is not live sleep-stage detection.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        } else {
                            DatePicker("Wake-up time", selection: $manualTime, displayedComponents: .hourAndMinute)
                                .datePickerStyle(.wheel).labelsHidden().frame(maxWidth: .infinity)
                                .disabled(store.plan != nil || store.busy)
                        }
                    }.padding(20).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 24))

                    if store.plan == nil {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("Wake-up game", selection: $gameKind) {
                                Text("Daily rotation").tag(Optional<WakeGameKind>.none)
                                Text("Five-letter word").tag(Optional(WakeGameKind.word))
                                Text("Find the groups").tag(Optional(WakeGameKind.groups))
                                Text("Mini crossword").tag(Optional(WakeGameKind.crossword))
                            }.disabled(store.busy)
                            Text("Original, bite-size puzzles. Daily rotation cycles through all three, with hints and no attempt limit.")
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
                            Button("Open wake-up game") { store.beginPuzzle() }.buttonStyle(.borderedProminent).disabled(store.busy)
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
        }
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
