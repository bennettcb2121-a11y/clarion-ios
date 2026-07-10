import Foundation
import HealthKit

/// Thin async wrapper over HKHealthStore: authorization, per-day statistics, sample reads,
/// and background delivery registration. All reads are day-bucketed in the user's local
/// calendar to match the backend's one-row-per-local-day model.
final class HealthStore {
    static let shared = HealthStore()
    let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization(persona: Persona) async throws {
        try await store.requestAuthorization(toShare: [], read: PersonaScopes.readTypes(for: persona))
    }

    // MARK: - Day-bucketed statistics

    /// Sum of a cumulative quantity (steps, energy) per local day over [start, end].
    func dailySums(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async throws -> [Date: Double] {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return [:] }
        return try await collect(type: type, options: .cumulativeSum, unit: unit, start: start, end: end) {
            $0.sumQuantity()
        }
    }

    /// Average of a discrete quantity (RHR, HRV, SpO2, respiratory rate) per local day.
    func dailyAverages(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async throws -> [Date: Double] {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return [:] }
        return try await collect(type: type, options: .discreteAverage, unit: unit, start: start, end: end) {
            $0.averageQuantity()
        }
    }

    private func collect(
        type: HKQuantityType,
        options: HKStatisticsOptions,
        unit: HKUnit,
        start: Date,
        end: Date,
        extract: @escaping (HKStatistics) -> HKQuantity?
    ) async throws -> [Date: Double] {
        let calendar = Calendar.current
        let anchor = calendar.startOfDay(for: start)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: options,
                anchorDate: anchor,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, collection, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                var out: [Date: Double] = [:]
                collection?.enumerateStatistics(from: start, to: end) { stats, _ in
                    if let quantity = extract(stats) {
                        out[calendar.startOfDay(for: stats.startDate)] = quantity.doubleValue(for: unit)
                    }
                }
                continuation.resume(returning: out)
            }
            store.execute(query)
        }
    }

    /// Average + max heart rate over an interval (one workout). Returns (nil, nil) if the
    /// heart-rate type is unavailable or no samples fall in the window.
    func heartRateStats(start: Date, end: Date) async throws -> (avg: Double?, max: Double?) {
        guard let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return (nil, nil) }
        let unit = HKUnit.count().unitDivided(by: .minute())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: hrType,
                quantitySamplePredicate: predicate,
                options: [.discreteAverage, .discreteMax]
            ) { _, stats, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (
                    stats?.averageQuantity()?.doubleValue(for: unit),
                    stats?.maximumQuantity()?.doubleValue(for: unit)
                ))
            }
            store.execute(query)
        }
    }

    // MARK: - Samples

    func samples<T: HKSample>(
        of type: HKSampleType,
        start: Date,
        end: Date,
        limit: Int = HKObjectQueryNoLimit
    ) async throws -> [T] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: limit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (samples as? [T]) ?? [])
                }
            }
            store.execute(query)
        }
    }

    // MARK: - Background delivery

    /// Observer + background delivery on the types whose arrival should trigger a sync.
    /// Re-register at EVERY app launch — registrations don't survive relaunch.
    func registerBackgroundSync(persona: Persona, onUpdate: @escaping () -> Void) {
        let triggers: [HKSampleType?] = [
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
            HKObjectType.workoutType(),
        ]
        for case let type? in triggers {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
                if error == nil { onUpdate() }
                completion()
            }
            store.execute(query)
            store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
        }
    }
}
