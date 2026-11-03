# Architecture and honest capability boundaries

## Components

- `SmartWakeCore`: Foundation-only clock resolution, next-window planning, deadline clamping, bounded alarm lists, health-history filtering, original memory challenge and terminal session state machine.
- `iPhoneApp`: SwiftUI, AlarmKit, durable on-device ID ledger and progress, custom `LiveActivityIntent` opening the game, paired Watch receiver. No countdown UI is used, so no Live Activity widget extension is needed in v0.
- `WatchApp`: SwiftUI, read-only HealthKit sleep query, Core Motion recorder, WatchConnectivity. No workout, background runtime, remote API, or alarm scheduler.
- `Fixtures`: synthetic model inputs only. Never add a Health export or real sensor trace.

## Scheduling and recovery

Authorization is requested before planning. Existing alarms must be explicitly cancelled before replacing a session. The complete plan and ID ledger is persisted before any schedule operation. For smart mode the hard-deadline alarm is sent to AlarmKit first, then the earlier target, post-fallback reminders, and pre-fallback reminders. A partial failure is shown as partial, not success; existing successfully scheduled alarms remain registered until the user cancels. The plan is not silently rescheduled on app launch or new Watch data.

AlarmKit's own daemon owns delivery after scheduling. A suspended or terminated UI is not the scheduler. On launch the app reads its ledger and the daemon's current alarms. Completion/emergency cancellation reads all alarms belonging to this app, cancels them, and confirms the daemon list is empty before deleting the ledger. A failure leaves the ledger and a retry affordance. This protects against a crash between a scheduling call and its return.

Normal system Stop dismisses that individual alarm; remaining independently scheduled alarms remain. Users can always stop, deny permission, uninstall, power off, or use emergency stop. No bypass-proof promise is made.

## Smart mode

The window and its fallback are resolved using a captured calendar/time zone. A recent bedtime plus a preferred duration determines the target, clamped to the next 06:30–08:15 window. Valid recent history may replace the default preference using the median of plausible durations. This heuristic is not a medical finding, sleep-debt estimate, or classifier of sufficient sleep. It can choose a later target after a late bedtime; it never delays the initial fallback past 08:15. Up to ten one-minute follow-ups may extend through 08:25.

The Watch returns merged asleep intervals. The phone merges overlaps across sources again and sums asleep duration per noon-to-noon local sleep day. Awake gaps do not count as asleep time. WatchConnectivity may retain the latest application context on the paired devices; there is no app-managed health-data file or app server. Apple Health/iCloud sync follows the user’s separate system settings. No overnight automatic transfer is required for alarms to fire; explicit summary transfer informs subsequent arming only. No live re-targeting is implemented.

## Runtime boundaries

`CMSensorRecorder` may record supported motion across process suspension, but that is not permission to run app code all night. Its samples can be delayed, missing or unavailable. v0 only summarizes recordings when the app is active and the user requests it. Motion summaries are displayed as availability, not used as sleep evidence.

No watchOS extended-runtime session is scheduled. A future real smart-alarm experiment would need a separate, explicit 30-minute evaluation window and device validation; it cannot cover 06:30–08:15 by chaining sessions.

## Evidence

- [AlarmKit sample](https://developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit): authorization, fixed alerts, intents, custom countdown widget requirement.
- [AlarmKit overview](https://developer.apple.com/videos/play/wwdc2025/230/): absolute versus relative schedules and system Stop behavior.
- [AlarmManager alarms](https://developer.apple.com/documentation/alarmkit/alarmmanager/alarms): throwing daemon read and one-shot removal after stop.
- [CMSensorRecorder](https://developer.apple.com/documentation/coremotion/cmsensorrecorder): supported recording and usage-description requirement.
- [Extended runtime sessions](https://developer.apple.com/documentation/watchkit/using-extended-runtime-sessions): bounded watchOS execution categories.

Apple APIs must still be compiled against the installed SDK and exercised on physical devices. Static source inspection does not establish delivery reliability.
