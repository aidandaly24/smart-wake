import CoreMotion
import Foundation

struct MotionRecordingRequest: Sendable {
    let summary: WatchMotionSummary
    let requestedWindow: RecordingWindow?
}

/// Core Motion objects never leave this actor. Enumeration and statistics run off the UI actor.
actor WatchMotionRecorder {
    private let recorder = CMSensorRecorder()
    private static let maximumDuration: TimeInterval = 12 * 60 * 60
    private static let retentionDuration: TimeInterval = 3 * 24 * 60 * 60

    func availability() -> WatchMotionSummary {
        guard CMSensorRecorder.isAccelerometerRecordingAvailable() else {
            return WatchMotionSummary(status: .unsupported)
        }
        switch CMSensorRecorder.authorizationStatus() {
        case .notDetermined: return WatchMotionSummary(status: .notDetermined)
        case .restricted: return WatchMotionSummary(status: .restricted)
        case .denied: return WatchMotionSummary(status: .denied)
        case .authorized: return WatchMotionSummary(status: .ready)
        @unknown default: return WatchMotionSummary(status: .unknown)
        }
    }

    /// Call only in response to the explicit Record motion button. The system may show consent UI.
    /// This API returns no success acknowledgement; a request is not proof samples were captured.
    func requestRecording(duration: TimeInterval, now: Date = .now) -> MotionRecordingRequest {
        guard duration.isFinite, duration >= 60, duration <= Self.maximumDuration else {
            return MotionRecordingRequest(
                summary: WatchMotionSummary(status: .invalidDuration), requestedWindow: nil
            )
        }
        let current = availability()
        guard current.status == .ready || current.status == .notDetermined else {
            return MotionRecordingRequest(summary: current, requestedWindow: nil)
        }
        recorder.recordAccelerometer(forDuration: duration)
        let afterRequest = availability()
        guard afterRequest.status == .ready || afterRequest.status == .notDetermined else {
            return MotionRecordingRequest(summary: afterRequest, requestedWindow: nil)
        }
        let window = RecordingWindow(start: now, end: now.addingTimeInterval(duration))
        return MotionRecordingRequest(
            summary: WatchMotionSummary(status: .recordingRequested, window: window),
            requestedWindow: window
        )
    }

    /// Manual, post-hoc retrieval. There is no timer, background polling, or wake-up scheduling.
    func summarize(window: RecordingWindow?, now: Date = .now) -> WatchMotionSummary {
        let current = availability()
        guard current.status == .ready else { return current }
        guard let window else { return current }
        let oldest = now.addingTimeInterval(-Self.retentionDuration)
        guard window.end > oldest else {
            return WatchMotionSummary(status: .expired, window: window)
        }
        let start = max(window.start, oldest)
        let end = min(window.end, now)
        guard end > start, end.timeIntervalSince(start) <= Self.maximumDuration else {
            return WatchMotionSummary(status: .noSamples, window: window)
        }
        let queryWindow = RecordingWindow(start: start, end: end)
        guard let list = recorder.accelerometerData(from: start, to: end) else {
            return WatchMotionSummary(status: .noSamples, window: queryWindow)
        }

        var count = 0
        var mean = 0.0
        var squaredDifferences = 0.0
        // CMSensorDataList is NSFastEnumeration, not a Swift array. Do not materialize millions
        // of samples. This streaming Welford calculation stores only three aggregate numbers.
        var iterator = NSFastEnumerationIterator(list)
        while let item = iterator.next() {
            guard let sample = item as? CMRecordedAccelerometerData else { continue }
            let acceleration = sample.acceleration
            let magnitude = sqrt(
                acceleration.x * acceleration.x +
                acceleration.y * acceleration.y +
                acceleration.z * acceleration.z
            )
            guard magnitude.isFinite else { continue }
            count += 1
            let delta = magnitude - mean
            mean += delta / Double(count)
            squaredDifferences += delta * (magnitude - mean)
        }
        guard count > 0 else {
            return WatchMotionSummary(status: .noSamples, window: queryWindow)
        }
        return WatchMotionSummary(
            status: .available,
            sampleCount: count,
            window: queryWindow,
            meanAccelerationMagnitudeG: mean,
            magnitudeStandardDeviationG: sqrt(max(0, squaredDifferences / Double(count)))
        )
    }
}
