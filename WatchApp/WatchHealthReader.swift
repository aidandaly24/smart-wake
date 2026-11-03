import Foundation
import HealthKit

@MainActor
final class WatchHealthReader {
    private let store = HKHealthStore()

    /// Completion means the permission sheet finished, never that read permission was granted.
    func requestAccess() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable(),
              let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        else { return false }

        return await withCheckedContinuation { continuation in
            store.requestAuthorization(toShare: [], read: [sleepType]) { completed, error in
                continuation.resume(returning: completed && error == nil)
            }
        }
    }

    func readLastFourteenDays(now: Date = .now) async -> WatchSleepSummary {
        guard HKHealthStore.isHealthDataAvailable(),
              let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        else {
            return WatchSleepSummary(
                status: .unavailable, intervals: [], message: "Health data is unavailable on this device."
            )
        }

        let start = now.addingTimeInterval(-14 * 24 * 60 * 60)
        // Include records overlapping either boundary, then clip to the requested window below.
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: [])
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                guard error == nil else {
                    continuation.resume(returning: WatchSleepSummary(
                        status: .error, intervals: [],
                        message: "Sleep history could not be read. Try again while the watch is unlocked."
                    ))
                    return
                }
                // Convert non-Sendable HealthKit objects into small Sendable values inside this callback.
                // No framework object or [String: Any] dictionary crosses an actor boundary.
                let intervals = (samples ?? []).compactMap { sample -> WatchSleepInterval? in
                    guard let sample = sample as? HKCategorySample else { return nil }
                    let asleepValues: Set<Int> = [
                        HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                        HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                        HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                        HKCategoryValueSleepAnalysis.asleepREM.rawValue
                    ]
                    guard asleepValues.contains(sample.value) else { return nil }
                    let lower = max(sample.startDate, start)
                    let upper = min(sample.endDate, now)
                    guard upper > lower else { return nil }
                    return WatchSleepInterval(start: lower, end: upper)
                }
                let merged = WatchSleepInterval.merging(intervals)
                continuation.resume(returning: WatchSleepSummary(
                    status: merged.isEmpty ? .noDataOrNotAuthorized : .available,
                    intervals: merged,
                    message: merged.isEmpty
                        ? "No readable sleep records. There may be no history, or read access may be off."
                        : "Read available sleep history from the last 14 days. It may be incomplete or delayed."
                ))
            }
            store.execute(query)
        }
    }
}
