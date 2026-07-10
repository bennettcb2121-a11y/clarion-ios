import Foundation

/// A small static sample so the Vitals tab is meaningful before anything has synced (mirrors
/// the web's demo-fallback philosophy). Clearly flagged isDemo so the UI labels it "Sample data".
enum DemoSnapshot {
    static func endurance() -> SnapshotResponse {
        let cal = Calendar.current
        let today = Date()
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"

        var daily: [WearableDailyMetrics] = []
        for i in stride(from: 13, through: 0, by: -1) {
            let day = cal.date(byAdding: .day, value: -i, to: today)!
            let w = sin(Double(i) * 1.3)
            var d = WearableDailyMetrics(date: df.string(from: day))
            d.restingHeartRate = (48 + w * 3).rounded()
            d.hrv = (78 + w * 10 + Double(13 - i) * 0.4).rounded()
            d.respiratoryRate = ((135 + w * 6) / 10).rounded()
            d.sleepDurationMin = (430 + w * 40).rounded()
            d.sleepEfficiencyPct = (89 + w * 4).rounded()
            d.deepSleepMin = (95 + w * 20).rounded()
            d.remSleepMin = (105 + w * 20).rounded()
            d.sleepScore = (85 + w * 6).rounded()
            d.steps = (11000 + w * 3000).rounded()
            d.activeEnergyKcal = (720 + w * 200).rounded()
            d.readinessScore = (82 + w * 8).rounded()
            d.vo2Max = (56 + Double(13 - i) * 0.05).rounded(toPlaces: 1)
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
