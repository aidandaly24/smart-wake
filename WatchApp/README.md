# Watch companion v0

This target is a small, device-only companion, not a watch alarm or a live sleep-stage detector.
It requires watchOS 10 or later. Pair it with the iPhone target in this repository.

## What it does

- **I'm going to bed** stores a local bedtime timestamp. It does not arm an alarm or begin recording.
- **Read sleep history** explicitly requests read-only HealthKit access to `sleepAnalysis`, then reads the last 14 days. Asleep records are clipped to the query range and overlapping records are merged. Awake gaps are preserved; in-bed records do not count as sleep. Stages and source identities are not transferred.
- **Record motion** checks hardware support and Core Motion authorization, then requests 6, 8, 10, or 12 hours of recording. The underlying method rejects durations outside 1 minute to 12 hours. It does not create a workout or keep the app running.
- **Refresh summaries** manually reads available motion from the most recently requested recording window and refreshes permitted sleep history. The motion actor computes count, mean acceleration magnitude, and population standard deviation without retaining a raw array. Acceleration includes gravity. These values do not estimate sleep stage, sleep quality, or time asleep.
- **Send summary to iPhone** refreshes and queues the current summary for the paired phone with WatchConnectivity. No server, telemetry, HealthKit writes, automatic background polling, or alarm scheduling is present in the watch target.

The iPhone must explicitly arm its own alarm. Keep a separate Apple Clock backup alarm while testing this prototype.

## Important platform limits

The Health authorization callback means the request finished, not that the user granted read access. HealthKit deliberately makes denied read access look like missing data. The UI therefore says **No readable sleep records**, never **Health permission granted**. Limited, absent, or delayed history is possible. [Apple: authorizing Health access](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data).

`CMSensorRecorder.recordAccelerometer(forDuration:)` supports at most 43,200 seconds. Recording can continue while this app is suspended or terminated, but the app does not execute or evaluate motion during that time. The method returns no recording-success acknowledgement. [Apple: recording duration and behavior](https://developer.apple.com/documentation/coremotion/cmsensorrecorder/recordaccelerometer(forduration:)).

Retrieval is limited to a 12-hour range. Samples can have gaps, can lag up to three minutes, and are retained by the system for at most three days. Reopen the app after sleeping to read whatever is available. There is no public stop-recording method on this recorder, and v0 does not pretend to provide one. [Apple: retrieving recorded samples](https://developer.apple.com/documentation/coremotion/cmsensorrecorder/accelerometerdata(from:to:)), [recorder overview and permissions](https://developer.apple.com/documentation/coremotion/cmsensorrecorder).

WatchConnectivity application context is a latest-state channel: a newer queued summary replaces the previous one. Queue acceptance does not confirm delivery. The phone must be opened to confirm arrival. No immediate reachability is required for the background context transfer. [Apple: WatchConnectivity transfers](https://developer.apple.com/documentation/watchconnectivity/transferring-data-with-watch-connectivity).

## Wire format, version 1

All timestamps are Unix seconds (`Double`). No `Date`, custom object, `nil`, or raw accelerometer sample enters the property-list dictionary.

```text
kind: "watchSummary"
schemaVersion: 1
generatedAt: Double
bedtimeAt: Double (optional; absent means no current bedtime)
sleepStatus: String
sleepIntervals: [{ start: Double, end: Double }]
motion:
  available: Bool
  status: String
  sampleCount: Int
  windowStart: Double (optional)
  windowEnd: Double (optional)
  meanAccelerationMagnitudeG: Double (optional)
  magnitudeStandardDeviationG: Double (optional)
```

Sleep statuses: `notRequested`, `available`, `noDataOrNotAuthorized`, `unavailable`, `error`.

Motion statuses: `unsupported`, `notDetermined`, `denied`, `restricted`, `ready`, `recordingRequested`, `noSamples`, `available`, `expired`, `invalidDuration`, `unknown`.

`motion.available` means at least one finite sample was retrieved, not that the hardware is supported or permission was granted. `windowStart` and `windowEnd` describe the requested or queried range, not confirmed coverage. Available samples may cover only part of it. A queued context must never automatically arm an alarm or be interpreted as a live wake decision.

Serialization is checked before sending and limited to 48 KiB. A larger summary is rejected visibly rather than silently dropping sleep intervals.

## Project integration

- Add these Swift files to the watch app target only.
- Use `Info.plist` and `SmartWakeWatch.entitlements` for that target.
- Set `COMPANION_APP_BUNDLE_IDENTIFIER` to the actual iPhone bundle identifier.
- Include `PrivacyInfo.xcprivacy` as a resource. It declares app-local UserDefaults access (`CA92.1`); there is no developer data collection or tracking. [Apple: required-reason manifest entries](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest).
- Keep the target's default actor isolation nonisolated. UI and store orchestration are explicitly `@MainActor`; Core Motion runs in its own actor. The WatchConnectivity delegate is nonisolated and passes only primitive Sendable values into a MainActor task.
- No background mode, workout-processing entitlement, smart-alarm extended-runtime category, or HealthKit write description is required by this target.

## Verification status and device checklist

The XML plists were parsed and the sources reviewed in a Linux environment without Swift, Xcode, Apple SDKs, or paired devices. **The native watch target has not been compiled or run here.** Unit-test, simulator, signing, permission-sheet, connectivity, and overnight battery behavior must not be described as passing until checked in Xcode/on devices.

Before trusting any nightly workflow, test:

1. A simulator or unsupported device shows motion unavailable, without crashing.
2. Declining Health read access and an account with no sleep history both show the same neutral empty state. No Health write prompt appears.
3. Granting read access returns recent sleep only. Duplicate sources do not double count; awake gaps and in-bed-only records are excluded.
4. Declining Motion permission shows denied access. After enabling it in Settings, the Record button can be used again rather than remaining blocked by the old request.
5. Starting recording twice does not extend an existing pending window. Each offered duration remains at most 12 hours.
6. After suspension/relaunch, requested-window metadata remains. Retrieval shortly after starting can legitimately return no samples. Retrieval after more than three days shows expired.
7. Summary enumeration does not freeze UI or retain a large raw sample array. Exercise a full overnight record on a physical watch and measure memory/battery.
8. Sending while the phone is temporarily unavailable says queued, not delivered. A subsequent summary replaces the older queued one; received data never arms the phone alarm.
9. Clearing bedtime and sending again clears bedtime on the phone. Stale bedtime/summary timestamps are rejected or ignored there.
10. Changing permissions or reinstalling either app yields recoverable UI. No screen implies that this companion schedules a watch wake-up or a reliable live sleep-stage alarm.
