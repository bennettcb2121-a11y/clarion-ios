import Foundation
import HealthKit

/// HealthKit samples → the wire format. All bucketing is user-local-day, and SLEEP IS
/// ATTRIBUTED TO THE WAKE DATE (a night starting July 8 23:00 belongs to July 9) — this must
/// match how the server's Oura path attributes nights, or provider switching shifts sleep by
/// a day.
enum DailyNormalizer {
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        // Wire keys are GREGORIAN + ASCII digits: an unpinned formatter follows the
        // device calendar/locale (Buddhist year 2569, localized digits) and corrupts
        // the ingest payload's date field.
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    static func dayString(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    /// Build one WearableDailyMetrics per local day in [start, end].
    static func build(start: Date, end: Date, health: HealthStore) async throws -> [WearableDailyMetrics] {
        let calendar = Calendar.current

        async let steps = health.dailySums(.stepCount, unit: .count(), start: start, end: end)
        async let activeKcal = health.dailySums(.activeEnergyBurned, unit: .kilocalorie(), start: start, end: end)
        async let basalKcal = health.dailySums(.basalEnergyBurned, unit: .kilocalorie(), start: start, end: end)
        async let rhr = health.dailyAverages(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), start: start, end: end)
        async let hrv = health.dailyAverages(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), start: start, end: end)
        async let resp = health.dailyAverages(.respiratoryRate, unit: HKUnit.count().unitDivided(by: .minute()), start: start, end: end)
        async let spo2 = health.dailyAverages(.oxygenSaturation, unit: .percent(), start: start, end: end)
        async let vo2 = health.dailyAverages(.vo2Max, unit: HKUnit(from: "ml/kg*min"), start: start, end: end)

        var byDay: [String: WearableDailyMetrics] = [:]
        func ensure(_ day: Date) -> String {
            let key = dayString(day)
            if byDay[key] == nil {
                var d = WearableDailyMetrics(date: key)
                d.provider = "apple_health"
                byDay[key] = d
            }
            return key
        }

        for (day, v) in try await steps { byDay[ensure(day)]?.steps = v.rounded() }
        for (day, v) in try await activeKcal { byDay[ensure(day)]?.activeEnergyKcal = v.rounded() }
        for (day, v) in try await rhr { byDay[ensure(day)]?.restingHeartRate = v.rounded() }
        for (day, v) in try await hrv { byDay[ensure(day)]?.hrv = (v * 10).rounded() / 10 }
        for (day, v) in try await resp { byDay[ensure(day)]?.respiratoryRate = (v * 10).rounded() / 10 }
        for (day, v) in try await spo2 {
            // HealthKit percent unit is 0–1.
            byDay[ensure(day)]?.spo2Pct = (v * 1000).rounded() / 10
        }
        for (day, v) in try await vo2 { byDay[ensure(day)]?.vo2Max = (v * 10).rounded() / 10 }

        let basal = try await basalKcal
        for (day, active) in try await activeKcal {
            let key = ensure(day)
            if let b = basal[day] {
                byDay[key]?.totalEnergyKcal = (active + b).rounded()
            }
        }

        try await addSleep(to: &byDay, start: start, end: end, health: health, calendar: calendar)
        try await addWristTemperature(to: &byDay, start: start, end: end, health: health)

        return byDay.values.sorted { $0.date < $1.date }
    }

    // MARK: - Sleep (stages + duration + efficiency, attributed to wake date)

    private static func addSleep(
        to byDay: inout [String: WearableDailyMetrics],
        start: Date,
        end: Date,
        health: HealthStore,
        calendar: Calendar
    ) async throws {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return }
        // Reach one day earlier so the night that ENDS on `start` is included.
        let sleepStart = calendar.date(byAdding: .day, value: -1, to: start) ?? start
        let samples: [HKCategorySample] = try await health.samples(of: sleepType, start: sleepStart, end: end)

        struct Night {
            var asleepSec = 0.0
            var inBedSec = 0.0
            var deepSec = 0.0
            var remSec = 0.0
        }
        var nights: [String: Night] = [:]

        for sample in samples {
            let wakeDay = dayString(calendar.startOfDay(for: sample.endDate))
            var night = nights[wakeDay] ?? Night()
            let seconds = sample.endDate.timeIntervalSince(sample.startDate)
            switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
            case .inBed:
                night.inBedSec += seconds
            case .asleepDeep:
                night.deepSec += seconds
                night.asleepSec += seconds
            case .asleepREM:
                night.remSec += seconds
                night.asleepSec += seconds
            case .asleepCore, .asleepUnspecified:
                night.asleepSec += seconds
            default:
                break
            }
            nights[wakeDay] = night
        }

        for (day, night) in nights {
            guard night.asleepSec > 0 else { continue }
            if byDay[day] == nil {
                var d = WearableDailyMetrics(date: day)
                d.provider = "apple_health"
                byDay[day] = d
            }
            byDay[day]?.sleepDurationMin = (night.asleepSec / 60).rounded()
            byDay[day]?.deepSleepMin = night.deepSec > 0 ? (night.deepSec / 60).rounded() : nil
            byDay[day]?.remSleepMin = night.remSec > 0 ? (night.remSec / 60).rounded() : nil
            if night.inBedSec > night.asleepSec {
                byDay[day]?.sleepEfficiencyPct = ((night.asleepSec / night.inBedSec) * 100).rounded()
            }
        }
    }

    // MARK: - Wrist temperature (menopause flagship)

    /// Apple exposes ABSOLUTE overnight wrist temperature; the product wants DEVIATION from
    /// the user's own baseline (trailing mean of prior nights, excluding the night itself).
    /// Needs ~5 nights of history before the first deviation is emitted.
    private static func addWristTemperature(
        to byDay: inout [String: WearableDailyMetrics],
        start: Date,
        end: Date,
        health: HealthStore
    ) async throws {
        guard HKObjectType.quantityType(forIdentifier: .appleSleepingWristTemperature) != nil else { return }
        // Pull extra history so early days in the window have a baseline to compare against.
        let calendar = Calendar.current
        let baselineStart = calendar.date(byAdding: .day, value: -21, to: start) ?? start
        let temps = try await health.dailyAverages(
            .appleSleepingWristTemperature,
            unit: .degreeCelsius(),
            start: baselineStart,
            end: end
        )

        let ordered = temps.sorted { $0.key < $1.key }
        for (index, entry) in ordered.enumerated() {
            let (day, value) = entry
            guard day >= calendar.startOfDay(for: start) else { continue }
            let prior = ordered[..<index].suffix(14).map(\.value)
            guard prior.count >= 5 else { continue }
            let baseline = prior.reduce(0, +) / Double(prior.count)
            let key = dayString(day)
            if byDay[key] == nil {
                var d = WearableDailyMetrics(date: key)
                d.provider = "apple_health"
                byDay[key] = d
            }
            byDay[key]?.skinTempDeviationC = ((value - baseline) * 100).rounded() / 100
        }
    }
}
