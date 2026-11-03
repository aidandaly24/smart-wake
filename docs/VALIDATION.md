# Validation checkpoint

Recorded 2026-11-03 UTC in a Linux cloud workspace.

## Executed

- Project generation from the standard-library Python script.
- Structural/privacy smoke checks: plist and scheme XML parsing, synthetic fixture JSON parsing, source inclusion, usage descriptions, Watch embedding/entitlements, and absence of workout/background-runtime/server networking code.
- Python syntax compilation for both helper scripts.
- Seven synthetic fixture checks comparing UTC/local time and DST expectations with Python `zoneinfo`.
- Independent source review. Fixed stale-phone-bedtime precedence over a newer Watch bedtime and the in-flight arming/game/cancellation race.

These are **not** substitutes for Swift compilation, XCTest execution, or alarm delivery tests.

## Written, not executed here

64 XCTest methods are now written, including 23 new game tests. They cover manual clock resolution, midnight, DST gap/repeated hours, absolute-date persistence, smart deadlines, retry bounds, insufficient/stale history, denied permission, malformed input, puzzle progress, completion, emergency exit and persisted cancellation intent.

`swift test` was attempted and failed to launch: `swift: command not found`. This environment has no Swift compiler or Xcode/iOS/watchOS SDK. No app was installed on a device, and no alarm or HealthKit permission was requested on the user's devices.

The checked-in GitHub Actions workflow is prepared to run core tests and Xcode simulator builds **after repository publication is authorized**. It has not run at this checkpoint. A green compile would still not establish overnight reliability.

## Required next

1. Run package tests and both Xcode simulator builds; fix any SDK/compiler findings.
2. Verify signing and app installation using the user's existing Apple account and permission.
3. Complete `DEVICE_TEST_PLAN.md` on the actual iPhone/Watch, with a separate trusted alarm throughout.

Repository visibility/publication is a separate decision from keeping personal health data on device. No personal health data belongs in version control regardless of repository visibility.

## Games, icon and fallback update (2026-11-03 06:17 UTC)

- Passed 94 structural/privacy checks, including both opaque 1024×1024 icon assets and project references.
- Independently validated the source-data catalog: 30 distinct five-letter answers, 12 eight-tile group boards, and all 12 intersecting mini crossword grids.
- Python helper syntax and `git diff --check` passed.
- Source review checked game-state validation, legacy memory-session migration, completion-before-cancellation persistence, emergency exit, and the authorized fallback-follow-up changes. Fixed clue-selection loss after a rejected answer and a redundant initial word hint.
- `swift test` was attempted again and could not launch because Swift is absent. All 64 XCTest methods remain unexecuted here. No native asset compilation, UI rendering or device installation was performed by this cloud update.
- The user reported an existing device alarm ringing; that is not validation of this new source update or all its follow-ups. Existing sessions are not silently rescheduled. Stop and re-arm after a verified update to get the new games and ten follow-ups after the fallback.
