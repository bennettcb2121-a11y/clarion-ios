import Foundation

/// Wire format shared with the web backend — mirrors `src/lib/wearables/types.ts` in
/// bloodwise-frontend EXACTLY (camelCase keys). Changes to either side are breaking API
/// changes: installed apps take days to update through App Store review.
struct WearableDailyMetrics: Codable {
    var date: String // YYYY-MM-DD, user-local
    var restingHeartRate: Double?
    var hrv: Double?
    var respiratoryRate: Double?
    var sleepDurationMin: Double?
    var sleepEfficiencyPct: Double?
    var deepSleepMin: Double?
    var remSleepMin: Double?
    var sleepScore: Double?
    var skinTempDeviationC: Double?
    var steps: Double?
    var activeEnergyKcal: Double?
    var totalEnergyKcal: Double?
    var readinessScore: Double?
    var spo2Pct: Double?
    var daytimeStressMin: Double?
    var cycleDay: Int?
    var vo2Max: Double?
    var provider: String?

    init(date: String) {
        self.date = date
    }
}

struct WearableWorkout: Codable {
    var id: String
    var date: String // YYYY-MM-DD, user-local
    var type: String // run | ride | swim | strength | walk | hike | row | other
    var durationMin: Double
    var distanceKm: Double?
    var avgHeartRate: Double?
    var maxHeartRate: Double?
    var activeEnergyKcal: Double?
    var avgPaceSecPerKm: Double?
    var provider: String?
}

struct IngestPayload: Codable {
    var provider: String
    var clientVersion: String
    var daily: [WearableDailyMetrics]
    var workouts: [WearableWorkout]
}

struct IngestResponse: Codable {
    var ok: Bool?
    var daily: Int?
    var workouts: Int?
    var error: String?
}

/// The persona driving scoped HealthKit permission requests — fetched from the user's
/// Clarion web profile at sign-in (profile_type / menopause_stage / sex).
enum Persona: String {
    case endurance
    case strength
    case menopause
    case general
}
