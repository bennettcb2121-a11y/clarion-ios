import Foundation

/// A small static sample so the Vitals tab is meaningful before anything has synced (mirrors
/// the web's demo-fallback philosophy). Clearly flagged isDemo so the UI labels it "Sample data".
enum DemoSnapshot {
    static func endurance() -> SnapshotResponse {
        let cal = LocalDay.calendar // Gregorian day keys, like every real snapshot
        let today = Date()
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"

        /// Deterministic "noise" — layered incommensurate sines read as believable biology,
        /// not the too-perfect single sine the design review flagged as obviously synthetic.
        func wobble(_ i: Int, _ seed: Double) -> Double {
            let x = Double(i)
            return sin(x * 1.7 + seed) * 0.55 + sin(x * 3.9 + seed * 2.1) * 0.3 + sin(x * 9.3 + seed * 0.7) * 0.15
        }

        var daily: [WearableDailyMetrics] = []
        for i in stride(from: 13, through: 0, by: -1) {
            let day = cal.date(byAdding: .day, value: -i, to: today)!
            let w = wobble(i, 4.2)
            let w2 = wobble(i, 11.8)
            var d = WearableDailyMetrics(date: df.string(from: day))
            d.restingHeartRate = (48 + w * 4).rounded()
            d.hrv = (78 + w * 12 + Double(13 - i) * 0.4).rounded()
            d.respiratoryRate = ((135 + w2 * 7) / 10).rounded()
            d.sleepDurationMin = (430 + w2 * 55).rounded()
            d.sleepEfficiencyPct = (89 + w * 5).rounded()
            d.deepSleepMin = (95 + w2 * 24).rounded()
            d.remSleepMin = (105 + w * 22).rounded()
            d.sleepScore = (85 + w2 * 7).rounded()
            d.steps = (11000 + w2 * 3600).rounded()
            d.activeEnergyKcal = (720 + w * 230).rounded()
            d.readinessScore = min(97, max(45, (82 + w * 9).rounded()))
            d.vo2Max = (56 + Double(13 - i) * 0.05 + w * 0.2).rounded(toPlaces: 1)
            // Overnight wrist-temperature deviation from baseline — the menopause flagship signal
            // (small +/- °C swings). Present in the sample so the persona-adaptive Home can show it.
            d.skinTempDeviationC = (0.1 + w2 * 0.22).rounded(toPlaces: 2)
            d.provider = "demo"
            daily.append(d)
        }

        let workouts = [
            WearableWorkout(id: "d1", date: df.string(from: cal.date(byAdding: .day, value: -1, to: today)!), type: "run", durationMin: 52, distanceKm: 11.2, avgHeartRate: 148, maxHeartRate: 171, activeEnergyKcal: 720, avgPaceSecPerKm: 279, provider: "demo"),
            WearableWorkout(id: "d2", date: df.string(from: cal.date(byAdding: .day, value: -3, to: today)!), type: "run", durationMin: 38, distanceKm: 8.0, avgHeartRate: 141, maxHeartRate: 158, activeEnergyKcal: 510, avgPaceSecPerKm: 285, provider: "demo"),
            WearableWorkout(id: "d3", date: df.string(from: cal.date(byAdding: .day, value: -4, to: today)!), type: "ride", durationMin: 74, distanceKm: 34.5, avgHeartRate: 132, maxHeartRate: 160, activeEnergyKcal: 690, avgPaceSecPerKm: nil, provider: "demo"),
        ]

        let snapshot = WearableSnapshot(
            provider: "demo", isDemo: true, connectedAt: nil, lastSyncedAt: nil,
            daily: daily, workouts: workouts
        )
        return SnapshotResponse(
            snapshot: snapshot,
            widgetKeys: ["readiness", "hrv_trend", "resting_hr", "vo2max"],
            insights: []
        )
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let f = pow(10.0, Double(places))
        return (self * f).rounded() / f
    }
}
