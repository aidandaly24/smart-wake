# Synthetic planning fixtures

`planning-cases.json` contains invented dates and intervals only. It contains no
personal sleep or HealthKit data. The same edge cases are asserted by XCTest.

These cases document product behavior, not a measurement of sleep quality:

- Manual mode resolves the next selected clock date in the captured time zone.
- A spring-forward time that does not exist uses Calendar's `.nextTime` policy.
- A repeated autumn time uses its first occurrence. If that first occurrence has
  already passed, the next calendar day is selected, not the second occurrence.
- Smart mode always includes exactly one fallback at 08:15 in its chosen local
  window. A target at the deadline uses that fallback as its initial alarm, followed by the configured one-minute reminders.
- Bedtime plus an optional historical median is a scheduling heuristic. It does
  not establish that someone has had enough sleep or identify their sleep stage.
- Missing bedtime/Watch context uses the fixed fallback. Manual bedtime can be
  used with a clearly disclosed preferred duration when history is unavailable.

The pure package has no HealthKit, WatchConnectivity, AlarmKit, network, or file
storage dependency. Platform adapters supply inputs and are responsible for
permission rechecks, actual scheduling, transactional rollback, cancellation,
and protected local persistence.

## Verification status

Swift and Xcode are unavailable in the implementation container. XCTest has been
written but **has not been executed** there. Run `swift test` from the repository
root with Swift 5.10 or later, then run device integration checks separately.
Inspecting fixtures with another language does not validate the Swift runtime or
Apple's system-alarm delivery.
