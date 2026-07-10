import Foundation
import HealthKit

/// HKWorkout → WearableWorkout. `id` is the HealthKit UUID, which the server dedupes on
/// (user_id + external_id), so re-syncing the same window is idempotent.
enum WorkoutNormalizer {
    private static func normalizedType(_ activity: HKWorkoutActivityType) -> String {
        switch activity {
        case .running: return "run"
        case .cycling: return "ride"
        case .swimming: return "swim"
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "strength"
        case .walking: return "walk"
        case .hiking: return "hike"
        case .rowing: return "row"
        default: return "other"
        }
    }

    static func build(start: Date, end: Date, health: HealthStore) async throws -> [WearableWorkout] {
        let workouts: [HKWorkout] = try await health.samples(of: HKObjectType.workoutType(), start: start, end: end)
        var out: [WearableWorkout] = []
        for w in workouts {
            let durationMin = w.duration / 60
            let meters = w.totalDistance?.doubleValue(for: .meter())
            let distanceKm = meters.map { $0 / 1000 }
            let kcal = w.totalEnergyBurned?.doubleValue(for: .kilocalorie())
            var pace: Double?
            if let km = distanceKm, km > 0.2, durationMin > 0 {
                pace = (durationMin * 60 / km).rounded()
            }
            // Avg/max HR from the samples inside the workout window (nil if HR permission
            // wasn't granted or the workout has no HR samples).
            let hr = (try? await health.heartRateStats(start: w.startDate, end: w.endDate)) ?? (nil, nil)
            out.append(WearableWorkout(
                id: w.uuid.uuidString,
                date: DailyNormalizer.dayString(w.startDate),
                type: normalizedType(w.workoutActivityType),
                durationMin: (durationMin * 10).rounded() / 10,
                distanceKm: distanceKm.map { ($0 * 100).rounded() / 100 },
                avgHeartRate: hr.avg.map { $0.rounded() },
                maxHeartRate: hr.max.map { $0.rounded() },
                activeEnergyKcal: kcal.map { $0.rounded() },
                avgPaceSecPerKm: pace,
                provider: "apple_health"
            ))
        }
        return out
    }
}
