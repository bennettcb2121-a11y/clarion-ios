#if DEBUG
import Foundation
import HealthKit

/// Writes ~14 days of believable endurance data into HealthKit so the Simulator — which has no
/// Apple Watch / Oura feeding it — can show the full wearable dashboard (readiness ring, VO₂max /
/// HRV / Sleep tiles, and the Last-run card). DEBUG only: the HealthKit write permission and this
/// whole file are absent from Release builds.
///
/// Values are deterministic (derived from the day index, not random) so re-seeding is stable and
/// the fields map exactly to what DailyNormalizer / WorkoutNormalizer read back.
enum HealthSeeder {
    static func seed(into health: HealthStore = .shared) async throws {
        try await health.requestSeedAuthorization()

        // Idempotent: drop anything a previous seed wrote before writing again. Without this a
        // second tap DOUBLES every additive value (sleep read back as 14.8h, steps twice over)
        // and duplicates every run. Only this app's own samples are touched.
        for type in HealthStore.seedableTypes {
            try? await health.deleteOwnSamples(of: type)
        }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var objects: [HKObject] = []

        func q(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ value: Double, at date: Date) -> HKQuantitySample? {
            guard let t = HKObjectType.quantityType(forIdentifier: id) else { return nil }
            return HKQuantitySample(type: t, quantity: HKQuantity(unit: unit, doubleValue: value), start: date, end: date)
        }
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())

        for offset in 0..<14 {
            guard let dayStart = cal.date(byAdding: .day, value: -offset, to: today) else { continue }

            // Morning reads (~6:30am): HRV, resting HR, respiratory rate, weekly-ish VO₂max.
            let morning = cal.date(byAdding: .minute, value: 6 * 60 + 30, to: dayStart)!
            let hrv = 72.0 + Double((offset * 7) % 22)          // 72–94 ms
            let rhr = 47.0 + Double((offset * 3) % 7)           // 47–53 bpm
            if let s = q(.heartRateVariabilitySDNN, .secondUnit(with: .milli), hrv, at: morning) { objects.append(s) }
            if let s = q(.restingHeartRate, bpmUnit, rhr, at: morning) { objects.append(s) }
            if let s = q(.respiratoryRate, bpmUnit, 14.0 + Double(offset % 3), at: morning) { objects.append(s) }
            if offset % 4 == 0, let s = q(.vo2Max, HKUnit(from: "ml/kg*min"), 54.0 + Double(offset % 5), at: morning) {
                objects.append(s)
            }

            // Steps + active energy, mid-day.
            let noon = cal.date(byAdding: .hour, value: 13, to: dayStart)!
            if let s = q(.stepCount, .count(), 8500 + Double((offset * 613) % 6000), at: noon) { objects.append(s) }
            if let s = q(.activeEnergyBurned, .kilocalorie(), 480 + Double((offset * 97) % 350), at: noon) { objects.append(s) }

            // Sleep: ~7–8h, attributed to the WAKE date (DailyNormalizer keys nights by end date).
            if let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
                let wake = cal.date(byAdding: .minute, value: 6 * 60 + 45, to: dayStart)!  // ~6:45am
                let asleepMin = 420 + (offset % 3) * 25                                    // 420–470 min
                // inBed spans asleepMin + 25 (25m awake before sleep onset). The STAGES tile only
                // onset→wake, so the asleep total is exactly asleepMin — tiling the whole in-bed
                // window instead would over-report sleep and imply 100% efficiency.
                let bedtime = cal.date(byAdding: .minute, value: -(asleepMin + 25), to: wake)!
                let onset = cal.date(byAdding: .minute, value: 25, to: bedtime)!
                let deepEnd = cal.date(byAdding: .minute, value: 95, to: onset)!
                let remStart = cal.date(byAdding: .minute, value: -70, to: wake)!
                func sleepSample(_ v: HKCategoryValueSleepAnalysis, _ start: Date, _ end: Date) -> HKCategorySample {
                    HKCategorySample(type: sleepType, value: v.rawValue, start: start, end: end)
                }
                objects.append(sleepSample(.inBed, bedtime, wake))
                objects.append(sleepSample(.asleepDeep, onset, deepEnd))
                objects.append(sleepSample(.asleepCore, deepEnd, remStart))
                objects.append(sleepSample(.asleepREM, remStart, wake))
            }

            // Runs on every other day (incl. today → "Last run" reads TODAY), with HR samples
            // across the window so WorkoutNormalizer can derive avg/max HR.
            if offset % 2 == 0 {
                let runStart = cal.date(byAdding: .hour, value: 17, to: dayStart)!
                let durMin = 45 + (offset % 4) * 8                 // 45–69 min
                let runEnd = cal.date(byAdding: .minute, value: durMin, to: runStart)!
                let distanceM = (9.0 + Double(offset % 4)) * 1000  // 9–12 km
                let energy = 560.0 + Double((offset * 41) % 220)

                if let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) {
                    for m in stride(from: 0, to: durMin, by: 5) {
                        let t = cal.date(byAdding: .minute, value: m, to: runStart)!
                        let bpm = 138.0 + Double((m / 5 + offset) % 34) // 138–171
                        objects.append(HKQuantitySample(type: hrType, quantity: HKQuantity(unit: bpmUnit, doubleValue: bpm), start: t, end: t))
                    }
                }

                // Legacy initializer intentionally: it populates totalDistance/totalEnergyBurned,
                // which WorkoutNormalizer reads via those (deprecated) accessors. A builder-made
                // workout leaves them nil, so distance/pace would vanish from the card.
                let workout = HKWorkout(
                    activityType: .running,
                    start: runStart, end: runEnd,
                    duration: TimeInterval(durMin * 60),
                    totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: energy),
                    totalDistance: HKQuantity(unit: .meter(), doubleValue: distanceM),
                    metadata: nil
                )
                objects.append(workout)
            }
        }

        try await health.save(objects)
    }
}

/// Launch-arg verification (`SEED_AND_DUMP`): seed, then read back through the real normalizers
/// and print a summary — so the write→normalize path can be confirmed in the Simulator without a
/// signed-in session or a server round-trip. Debug only.
enum DebugSeedDump {
    static func run() async {
        do {
            try await HealthSeeder.seed()
            // The seeder only asks for WRITE. Reading back needs the read scopes too — the real
            // app gets these from SyncCoordinator before its first read; this harness must ask.
            try await HealthStore.shared.requestAuthorization()
            let cal = Calendar.current
            let end = Date()
            let start = cal.date(byAdding: .day, value: -14, to: end)!
            let daily = try await DailyNormalizer.build(start: start, end: end, health: .shared)
            let workouts = try await WorkoutNormalizer.build(start: start, end: end, health: .shared)
            let last = daily.last
            print("‼️SEEDDUMP daily=\(daily.count) workouts=\(workouts.count) todayHRV=\(String(describing: last?.hrv)) todaySleepMin=\(String(describing: last?.sleepDurationMin)) todayVO2=\(String(describing: last?.vo2Max)) todayRHR=\(String(describing: last?.restingHeartRate))")
            if let w = workouts.max(by: { $0.date < $1.date }) {
                print("‼️SEEDDUMP lastRun type=\(w.type) date=\(w.date) km=\(String(describing: w.distanceKm)) durMin=\(w.durationMin) paceSec=\(String(describing: w.avgPaceSecPerKm)) avgHR=\(String(describing: w.avgHeartRate))")
            }
        } catch {
            print("‼️SEEDDUMP error=\(error)")
        }
    }
}
#endif
