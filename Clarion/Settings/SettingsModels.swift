import Foundation

/// GET/PATCH /api/account/profile — the settings-relevant slice of the `profiles` row,
/// exactly as src/lib/profileSettingsApiPayload.ts shapes it (snake_case keys; age/sex
/// are TEXT columns so they stay strings). Everything is optional-tolerant: the API
/// promises every key is present (null when unset), but decoding stays defensive.
struct ProfileSettings: Codable, Equatable {
    var age: String
    var sex: String
    var profileType: String?
    /// Comma-separated symptom ids, e.g. "fatigue,low_energy".
    var symptoms: String?
    var healthGoals: String?
    var dietPreference: String?
    /// Canonical metric — the UI converts to imperial locally; units are never persisted.
    var heightCm: Double?
    var weightKg: Double?
    var improvementPreference: String?
    /// The gummy preference: any | gummy | no_pills.
    var supplementFormPreference: String?
    var currentSupplements: String
    var currentSupplementSpend: String
    var shoppingPreference: String
    var retestWeeks: Double?
    var scoreGoal: Double?
    /// null/true = on (the web treats !== false as on).
    var streakMilestones: Bool?
    var dailyReminder: Bool?
    /// "HH:mm"
    var dailyReminderTime: String?
    /// IANA id, e.g. "America/New_York".
    var dailyReminderTimezone: String?
    /// email | sms (push is web-only until APNs lands — Phase D).
    var dailyReminderChannel: String?
    var phone: String?
    /// Read-only: written by the SMS verify flow.
    var smsReminderVerifiedAt: String?
    var smsReminderOptedOutAt: String?
    var notifyReorderEmail: Bool?
    var notifyReorderDays: Double?
    var vitalsWidgets: String?
    var email: String?
    /// READ-ONLY (payment-locked).
    var analysisPurchasedAt: String?
    /// READ-ONLY: none | lite | full.
    var planTier: String?
    var menopauseStage: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case age, sex, symptoms, phone, email
        case profileType = "profile_type"
        case healthGoals = "health_goals"
        case dietPreference = "diet_preference"
        case heightCm = "height_cm"
        case weightKg = "weight_kg"
        case improvementPreference = "improvement_preference"
        case supplementFormPreference = "supplement_form_preference"
        case currentSupplements = "current_supplements"
        case currentSupplementSpend = "current_supplement_spend"
        case shoppingPreference = "shopping_preference"
        case retestWeeks = "retest_weeks"
        case scoreGoal = "score_goal"
        case streakMilestones = "streak_milestones"
        case dailyReminder = "daily_reminder"
        case dailyReminderTime = "daily_reminder_time"
        case dailyReminderTimezone = "daily_reminder_timezone"
        case dailyReminderChannel = "daily_reminder_channel"
        case smsReminderVerifiedAt = "sms_reminder_verified_at"
        case smsReminderOptedOutAt = "sms_reminder_opted_out_at"
        case notifyReorderEmail = "notify_reorder_email"
        case notifyReorderDays = "notify_reorder_days"
        case vitalsWidgets = "vitals_widgets"
        case analysisPurchasedAt = "analysis_purchased_at"
        case planTier = "plan_tier"
        case menopauseStage = "menopause_stage"
        case updatedAt = "updated_at"
    }

    /// SMS delivery is actually reachable: verified and not opted out.
    var smsVerified: Bool {
        smsReminderVerifiedAt != nil && smsReminderOptedOutAt == nil
    }
}

// MARK: - Option catalogs (mirrors of the web's src/lib sources)

/// PROFILE_TYPE_OPTIONS from src/lib/clarionProfiles.ts — ids must match exactly
/// (the PATCH validates against this set server-side).
enum ProfileTypeCatalog {
    struct Option: Identifiable {
        let id: String
        let label: String
        let group: String
    }

    static let options: [Option] = [
        // Universal
        Option(id: "general_health_adult", label: "General health adult", group: "Universal"),
        Option(id: "fatigue_low_energy", label: "Fatigue / low energy", group: "Universal"),
        Option(id: "weight_loss_insulin_resistance", label: "Weight loss / insulin resistance", group: "Universal"),
        Option(id: "heart_health_longevity", label: "Heart-health / longevity", group: "Universal"),
        Option(id: "vegetarian_vegan", label: "Vegetarian / vegan", group: "Universal"),
        // Performance
        Option(id: "endurance_athlete", label: "Endurance athlete", group: "Performance"),
        Option(id: "strength_hypertrophy_athlete", label: "Strength / hypertrophy athlete", group: "Performance"),
        Option(id: "mixed_sport_athlete", label: "Mixed sport / field sport athlete", group: "Performance"),
        Option(id: "female_athlete", label: "Female athlete / menstruating athlete", group: "Performance"),
        Option(id: "high_volume_adolescent", label: "High-volume adolescent athlete", group: "Performance"),
        // Age / hormone
        Option(id: "older_adult_healthy_aging", label: "Older adult / healthy aging", group: "Age & hormone"),
        // Clinical-pattern screens
        Option(id: "prediabetes_metabolic_risk", label: "Prediabetes / metabolic risk", group: "Clinical"),
        Option(id: "anemia_low_iron", label: "Anemia / low iron symptoms", group: "Clinical"),
        Option(id: "thyroid_symptom_screen", label: "Thyroid symptom screen", group: "Clinical"),
        Option(id: "high_inflammation_poor_recovery", label: "High inflammation / poor recovery", group: "Clinical"),
        Option(id: "sleep_stress_overreaching", label: "Sleep / stress / overreaching", group: "Clinical"),
    ]

    static func label(for id: String?) -> String {
        guard let id, let match = options.first(where: { $0.id == id }) else { return "Not set" }
        return match.label
    }
}

/// SYMPTOM_OPTIONS from src/lib/priorityRanking.ts (minus "none" — absence of pills = none).
enum SymptomCatalog {
    static let options: [(id: String, label: String)] = [
        ("fatigue", "Fatigue"),
        ("brain_fog", "Brain fog"),
        ("low_energy", "Low energy"),
        ("poor_recovery", "Poor recovery"),
        ("sleep_issues", "Sleep issues"),
    ]
}

enum DietCatalog {
    static let options: [(id: String, label: String)] = [
        ("vegetarian", "Vegetarian"),
        ("vegan", "Vegan"),
        ("high_protein", "High protein"),
        ("low_carb", "Low carb"),
        ("mediterranean", "Mediterranean"),
    ]

    static func label(for id: String?) -> String {
        guard let id, let match = options.first(where: { $0.id == id }) else { return "No preference" }
        return match.label
    }
}

/// Height/weight conversions — exact mirrors of the web settings page math
/// (feet = floor(cm/30.48); inches = round(remainder × 12); lb = kg × 2.205 to 0.1).
enum UnitsMath {
    static func feetInches(fromCm cm: Double) -> (feet: Int, inches: Int) {
        let totalFeet = cm / 30.48
        var feet = Int(totalFeet)
        var inches = Int((totalFeet.truncatingRemainder(dividingBy: 1) * 12).rounded())
        if inches == 12 { feet += 1; inches = 0 }
        return (feet, inches)
    }

    static func cm(fromFeet feet: Int, inches: Int) -> Double {
        (Double(feet) * 30.48 + Double(inches) * 2.54).rounded()
    }

    static func pounds(fromKg kg: Double) -> Double {
        (kg * 2.205 * 10).rounded() / 10
    }

    static func kg(fromPounds lb: Double) -> Double {
        (lb / 2.205 * 10).rounded() / 10
    }

    // MARK: - Distance & pace (canonical storage is metric: km + sec/km)

    static let kmPerMile = 1.609344

    /// A canonical-km distance split into (value, unit) under the imperial pref,
    /// so a view can size the number and unit separately. "12.4" · "mi" / "19.9" · "km".
    static func distanceParts(km: Double, imperial: Bool) -> (value: String, unit: String) {
        imperial
            ? (String(format: "%.1f", km / kmPerMile), "mi")
            : (String(format: "%.1f", km), "km")
    }

    /// One-string distance, e.g. "12.4 mi" / "19.9 km".
    static func distanceString(km: Double, imperial: Bool) -> String {
        let (v, u) = distanceParts(km: km, imperial: imperial)
        return "\(v) \(u)"
    }

    /// Seconds-per-km → "M:SS /mi" or "M:SS /km" in the user's unit.
    static func paceString(secPerKm: Double, imperial: Bool) -> String {
        let perUnit = imperial ? secPerKm * kmPerMile : secPerKm
        let s = Int(perUnit.rounded())
        return "\(s / 60):\(String(format: "%02d", s % 60)) /\(imperial ? "mi" : "km")"
    }

    /// Speed for wheeled/moving sports where pace makes no sense (cycling): "18.4 mph" / "29.6 km/h".
    static func speedString(kmh: Double, imperial: Bool) -> String {
        let v = imperial ? kmh / kmPerMile : kmh
        return String(format: "%.1f %@", v, imperial ? "mph" : "km/h")
    }

    /// Speed from a canonical sec-per-km pace (avg moving speed).
    static func speedString(secPerKm: Double, imperial: Bool) -> String {
        speedString(kmh: secPerKm > 0 ? 3600.0 / secPerKm : 0, imperial: imperial)
    }

    /// Speed from raw distance + duration (fallback when no pace is recorded).
    static func speedString(km: Double, minutes: Double, imperial: Bool) -> String {
        speedString(kmh: minutes > 0 ? km / (minutes / 60.0) : 0, imperial: imperial)
    }

    /// Swim split, "M:SS /100m" from sec-per-km (÷10) — the universal training convention.
    static func pacePer100m(secPerKm: Double) -> String {
        let s = Int((secPerKm / 10).rounded())
        return "\(s / 60):\(String(format: "%02d", s % 60)) /100m"
    }

    /// Row split, "M:SS /500m" from sec-per-km (÷2) — how ergs and rowers report.
    static func pacePer500m(secPerKm: Double) -> String {
        let s = Int((secPerKm / 2).rounded())
        return "\(s / 60):\(String(format: "%02d", s % 60)) /500m"
    }
}
