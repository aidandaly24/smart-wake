# Before relying on Smart Wake

Status: **not yet run on physical iPhone/Watch**. Use a separate trusted alarm for every test night.

## Current simulator regression checklist

Use synthetic state only. The current requested QA is simulator-only; do not use the user's physical phone or Watch without new permission. A simulator pass cannot establish physical alarm delivery.

- Start with no saved session. Select each wake mode, change the time, choose each game, and verify a clearly labeled primary action.
- Restore an armed session. The editor should show its saved mode/time/game, permit draft changes, and retain the current schedule until Update is explicitly confirmed.
- Cancel the Update confirmation and verify the old IDs and session remain unchanged. Confirm a replacement and verify old alarms are removed before the new schedule is saved/registered.
- Try early play, an early deep link, restored answering state, and clock rollback in synthetic tests. No game action or completion may cancel a future session. At the exact target boundary play must unlock.
- Interrupt replacement during authorization or scheduling. Emergency stop must remain effective, partial state must be reported honestly, and no second operation may silently reset cancellation intent.
- Try all three games, wrong/duplicate input, hints, save failures, and relaunch midway. Invalid or unsaved typed guesses/group selections must remain editable. Completion should cancel the remaining app alarms; leaving the game should not.
- Inspect a small phone simulator with keyboard open, maximum Dynamic Type, VoiceOver, Reduce Motion and Reduce Transparency. The emergency stop must stay reachable, text must remain understandable, and reduced-motion/inactive scenes must pause decoration.
- Keep actual screenshots and observed results separate from source review and compile results.

## Future physical-device validation

These checks remain necessary before relying on the app, but are not part of the currently authorized simulator-only QA.

## Build / signing

- Record iPhone/Watch models, OS versions and Xcode version.
- Run `swift test` and both simulator compile commands from README.
- Verify phone app embeds the Watch app, pairing identifiers match, HealthKit capability is present, and both install with your existing signing setup.

## Manual alarms

1. Choose a time 2–3 minutes ahead and allow AlarmKit permission.
2. Confirm displayed schedule: primary + at most ten reminders at 60-second intervals.
3. Lock the phone, test Focus/silent mode, and check expected system alert and Watch mirroring separately.
4. Tap Play. Confirm the correct session opens, the selected word/group/crossword game is shown, wrong input gives recoverable feedback, and completing the game cancels remaining alarms. Also verify legacy saved memory-pattern sessions remain usable.
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
