# Before relying on Smart Wake

Status: **not yet run on physical iPhone/Watch**. Use a separate trusted alarm for every test night.

## Build / signing

- Record iPhone/Watch models, OS versions and Xcode version.
- Run `swift test` and both simulator compile commands from README.
- Verify phone app embeds the Watch app, pairing identifiers match, HealthKit capability is present, and both install with your existing signing setup.

## Manual alarms

1. Choose a time 2–3 minutes ahead and allow AlarmKit permission.
2. Confirm displayed schedule: primary + at most ten reminders at 60-second intervals.
3. Lock the phone, test Focus/silent mode, and check expected system alert and Watch mirroring separately.
4. Tap Play. Confirm the correct session opens, four symbols are shown, wrong tap resets, correct answer cancels remaining alarms.
5. Re-arm and use system Stop without solving. Confirm the next independently scheduled reminder behaves as expected. The app must not claim Stop is disabled.
6. Relaunch/terminate the app while armed and during a puzzle. Verify saved state, no duplicate schedules, and cancellation.
7. Test emergency stop during an in-flight scheduling batch, before firing, while sounding, after individual Stop, and repeatedly. All this app's daemon alarms should disappear.
8. Deny/revoke AlarmKit permission. The UI must not call the plan armed when nothing is registered.

## Smart mode

- With no bedtime: 08:15 fallback and ten separate one-minute reminders, through 08:25.
- With bedtime and no history: explicit default-duration target, clamped inside 06:30–08:15.
- With at least three plausible past nights: verify history-informed target and unchanged 08:15 fallback.
- Near deadline: one 08:15 fallback, plus one-minute follow-ups through 08:25, with no duplicate fire dates. Test the 01:11 bedtime case, verify all eleven IDs are registered, stop 08:15 without solving, then observe 08:16 and later reminders; solve a separate run and verify all remaining IDs are cancelled.
- Disconnect/charge/remove Watch or deny HealthKit: fixed phone plan remains independent of Watch delivery.
- Travel/change zone after arming: app warns original absolute times remain; cancel/re-arm uses new zone.
- Exercise DST gaps/repeated times through core tests, not by changing a production device's clock during reliance on alarms.

## Watch / privacy

- Read permission prompt uses plain purpose text, and no HealthKit write permission appears.
- Empty/denied history states are indistinguishable and accurately described.
- Unsupported/denied Core Motion never starts recording or claims live sensing.
- Supported recording uses a bounded duration; after reopening, a missing or delayed sample set is handled without claiming sleep stages.
- Send summary to the paired iPhone explicitly; inspect that no raw motion data, app-server request or app-managed cloud health storage is involved.
- Clear bedtime, send a new summary, and verify the phone does not reuse the old Watch bedtime.

## Failure injection

- Trigger or simulate AlarmKit scheduling-limit / partial failure; never present a partially registered batch as fully armed, and retain an independent alarm. Interrupt scheduling after fallback and before remaining alarms. Reopen, confirm partial state is visible, and emergency-cancel the entire daemon set.
- Simulate failed cancellation; ledger must remain and retry control must work.
- Corrupt/delete saved local state in a simulator while daemon alarms exist. Emergency stop should clear orphaned app alarms before new arming.

Do not claim release readiness until these are recorded with results and fixes. AlarmKit daemon behavior, reboot/first-unlock behavior, battery states and Watch mirroring require real hardware validation.
