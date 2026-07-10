import Foundation

/// Response of GET /api/wearables/snapshot — mirrors what the web /dashboard/vitals renders.
struct SnapshotResponse: Codable {
    var snapshot: WearableSnapshot
    var widgetKeys: [String]
    var insights: [CorrelationInsight]
}

struct WearableSnapshot: Codable {
    var provider: String
    var isDemo: Bool
    var connectedAt: String?
    var lastSyncedAt: String?
    var daily: [WearableDailyMetrics]
    var workouts: [WearableWorkout]

    /// Most recent day carrying any data.
    var latest: WearableDailyMetrics? { daily.last }

    /// The newest date (YYYY-MM-DD) with a REAL reading — used to warn when the device hasn't
    /// delivered fresh data even though the pipeline is running. A day counts if any core
    /// recovery/sleep field is present (steps alone don't count; phones generate those).
    var latestReadingDate: String? {
        for d in daily.reversed() {
            if d.hrv != nil || d.restingHeartRate != nil || d.sleepDurationMin != nil || d.readinessScore != nil {
                return d.date
            }
        }
        return nil
    }

    /// Days since the latest real reading (0 = today). Nil when no readings at all.
    var readingAgeDays: Int? {
        guard let dateStr = latestReadingDate else { return nil }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
        guard let date = f.date(from: dateStr) else { return nil }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: date), to: Calendar.current.startOfDay(for: Date())).day
    }

    /// True when the newest real reading is old enough that showing it as "current" would
    /// mislead (>1 full day behind).
    var isStale: Bool { (readingAgeDays ?? 0) >= 2 }
}

struct CorrelationInsight: Codable, Identifiable {
    var id: String
    var severity: String // "info" | "watch"
    var title: String
    var body: String
    var markerName: String?
    var ctaLabel: String?
    var ctaHref: String?
}

extension WearableDailyMetrics {
    /// Non-nil numeric series for a keypath across the daily window (chronological).
    static func series(_ daily: [WearableDailyMetrics], _ keyPath: KeyPath<WearableDailyMetrics, Double?>) -> [Double] {
        daily.compactMap { $0[keyPath: keyPath] }
    }

    static func latest(_ daily: [WearableDailyMetrics], _ keyPath: KeyPath<WearableDailyMetrics, Double?>) -> Double? {
        for d in daily.reversed() { if let v = d[keyPath: keyPath] { return v } }
        return nil
    }
}

/// One tile's spec — the Swift side of the web widget catalog (only the keys we render natively).
struct VitalsMetric: Identifiable {
    let id: String
    let title: String
    let unit: String
    let keyPath: KeyPath<WearableDailyMetrics, Double?>
    let higherIsBetter: Bool
    let caption: String

    static let catalog: [String: VitalsMetric] = [
        "hrv_trend": .init(id: "hrv_trend", title: "HRV", unit: "ms", keyPath: \.hrv, higherIsBetter: true, caption: "Heart-rate variability — your recovery signal"),
        "resting_hr": .init(id: "resting_hr", title: "Resting heart rate", unit: "bpm", keyPath: \.restingHeartRate, higherIsBetter: false, caption: "Rises with fatigue, stress, and under-recovery"),
        "vo2max": .init(id: "vo2max", title: "VO₂max", unit: "", keyPath: \.vo2Max, higherIsBetter: true, caption: "Your aerobic fitness trend"),
        "readiness": .init(id: "readiness", title: "Readiness", unit: "", keyPath: \.readinessScore, higherIsBetter: true, caption: "How recovered your body is today"),
        "respiratory_rate": .init(id: "respiratory_rate", title: "Respiratory rate", unit: "br/min", keyPath: \.respiratoryRate, higherIsBetter: false, caption: "Overnight breathing rate"),
        "steps_energy": .init(id: "steps_energy", title: "Activity", unit: "steps", keyPath: \.steps, higherIsBetter: true, caption: "Steps today"),
        "skin_temp": .init(id: "skin_temp", title: "Overnight body temperature", unit: "°C", keyPath: \.skinTempDeviationC, higherIsBetter: false, caption: "Deviation from your baseline"),
        "sleep_quality": .init(id: "sleep_quality", title: "Sleep", unit: "min", keyPath: \.sleepDurationMin, higherIsBetter: true, caption: "Nightly duration over the window"),
        "spo2": .init(id: "spo2", title: "Blood oxygen", unit: "%", keyPath: \.spo2Pct, higherIsBetter: true, caption: "Average overnight SpO₂"),
        "total_energy": .init(id: "total_energy", title: "Energy burn", unit: "kcal", keyPath: \.totalEnergyKcal, higherIsBetter: true, caption: "Total daily energy expenditure"),
    ]

    /// Display order for the "add more" list in Customize.
    static let allKeys: [String] = [
        "readiness", "hrv_trend", "resting_hr", "sleep_quality", "vo2max",
        "skin_temp", "spo2", "respiratory_rate", "steps_energy", "total_energy",
    ]
}
