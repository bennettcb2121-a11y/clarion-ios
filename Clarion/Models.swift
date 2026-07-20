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

extension WearableWorkout {
    /// Recorded average pace, or one derived from distance ÷ duration.
    var derivedPaceSecPerKm: Double? {
        if let p = avgPaceSecPerKm, p > 0 { return p }
        guard let km = distanceKm, km > 0, durationMin > 0 else { return nil }
        return (durationMin * 60) / km
    }

    /// The intensity metric the sport is actually measured in, as (value, label). Cyclists read
    /// speed, runners/walkers pace, swimmers a /100m split, rowers a /500m split — a running pace
    /// on a bike ride is meaningless. `nil` when there's no distance to work from (e.g. strength).
    func primaryMetric(imperial: Bool) -> (value: String, label: String)? {
        switch type {
        case "ride":
            if let pace = avgPaceSecPerKm, pace > 0 {
                return (UnitsMath.speedString(secPerKm: pace, imperial: imperial), "SPEED")
            }
            guard let km = distanceKm, km > 0, durationMin > 0 else { return nil }
            return (UnitsMath.speedString(km: km, minutes: durationMin, imperial: imperial), "SPEED")
        case "swim":
            guard let pace = derivedPaceSecPerKm else { return nil }
            return (UnitsMath.pacePer100m(secPerKm: pace), "PACE")
        case "row":
            guard let pace = derivedPaceSecPerKm else { return nil }
            return (UnitsMath.pacePer500m(secPerKm: pace), "SPLIT")
        default: // run, walk, hike
            guard let pace = derivedPaceSecPerKm else { return nil }
            return (UnitsMath.paceString(secPerKm: pace, imperial: imperial), "PACE")
        }
    }
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
