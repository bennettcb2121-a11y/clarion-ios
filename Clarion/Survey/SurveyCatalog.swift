import Foundation

/// The survey's option vocabularies + profile-type resolution — exact mirrors of the web
/// survey (OnboardingFlow.tsx option arrays + clarionProfiles.ts resolution). Every choice
/// PERSISTS the option `id` and RENDERS the `label`; the dashboard's calibration engines
/// match on ids, so these must never drift from the web.
enum SurveyCatalog {
    struct Option: Identifiable, Equatable {
        let id: String
        let label: String
        var description: String? = nil
    }

    // ACTIVITY_CHOICE_OPTIONS (OnboardingFlow.tsx)
    static let activity: [Option] = [
        Option(id: "sedentary", label: "Mostly sedentary"),
        Option(id: "light", label: "Light — a few times a week"),
        Option(id: "moderate", label: "Active — most days"),
        Option(id: "very_active", label: "Training hard — daily"),
    ]

    // LIFESTYLE_SLEEP_OPTIONS
    static let sleep: [Option] = [
        Option(id: "under_6", label: "Under 6 hrs"),
        Option(id: "6_7", label: "6–7 hrs"),
        Option(id: "7_8", label: "7–8 hrs"),
        Option(id: "8_plus", label: "8+ hrs"),
    ]

    // LIFESTYLE_ALCOHOL_OPTIONS
    static let alcohol: [Option] = [
        Option(id: "no", label: "No"),
        Option(id: "occasionally", label: "Occasionally"),
        Option(id: "regularly", label: "Regularly"),
    ]

    // TRAINING_FOCUS_OPTIONS (clarionProfiles.ts) — athletes only (activity moderate/very_active)
    static let trainingFocusNoneId = "none"
    static let training: [Option] = [
        Option(id: trainingFocusNoneId, label: "Not performance-focused",
               description: "General wellness or lifestyle—no sport-specific targets"),
        Option(id: "endurance_athlete", label: "Endurance athlete",
               description: "Running, cycling, triathlon—iron, oxygen transport, recovery"),
        Option(id: "strength_hypertrophy_athlete", label: "Strength / hypertrophy",
               description: "Lifting, power—vitamin D, magnesium, recovery context"),
        Option(id: "mixed_sport_athlete", label: "Mixed / field sport",
               description: "Team sports, hybrid training—balanced performance panel"),
        Option(id: "female_athlete", label: "Female athlete",
               description: "Menstrual cycle, iron, energy—RED-S–aware context"),
        Option(id: "high_volume_adolescent", label: "High-volume adolescent",
               description: "Growth + heavy training load"),
    ]

    // HEALTH_GOAL_OPTIONS + GOAL_CARD_META descriptions
    static let goals: [Option] = [
        Option(id: "more_energy", label: "More energy", description: "Beat the afternoon crash"),
        Option(id: "improve_fitness", label: "Improve fitness", description: "Run, ride, go longer"),
        Option(id: "longevity", label: "Longevity", description: "Stay sharp for decades"),
        Option(id: "better_sleep", label: "Better sleep", description: "Rest deeper, wake clearer"),
        Option(id: "improve_recovery", label: "Improve recovery", description: "Bounce back faster"),
        Option(id: "general_health", label: "General health", description: "Cover the basics well"),
    ]

    // SYMPTOM_OPTIONS (priorityRanking.ts) minus "none" — an empty pick IS none.
    static let symptoms: [Option] = [
        Option(id: "fatigue", label: "Fatigue"),
        Option(id: "brain_fog", label: "Brain fog"),
        Option(id: "low_energy", label: "Low energy"),
        Option(id: "poor_recovery", label: "Poor recovery"),
        Option(id: "sleep_issues", label: "Sleep issues"),
    ]

    static let sexOptions = ["Female", "Male", "Other", "Prefer not to say"]

    // COMMON_IDS from SurveySupplements.tsx, with display names. current_supplements is a
    // comma-joined name list (parseCurrentSupplementsEntries handles that format).
    static let commonSupplements: [Option] = [
        Option(id: "vitamin_d", label: "Vitamin D"),
        Option(id: "magnesium", label: "Magnesium"),
        Option(id: "omega3", label: "Omega-3"),
        Option(id: "iron", label: "Iron"),
        Option(id: "multivitamin", label: "Multivitamin"),
        Option(id: "creatine", label: "Creatine"),
        Option(id: "vitamin_c", label: "Vitamin C"),
        Option(id: "zinc", label: "Zinc"),
        Option(id: "b12", label: "B12"),
        Option(id: "probiotic", label: "Probiotic"),
    ]

    /// Athlete branch: sees the Training step (onboardingSteps.ts ATHLETE_ACTIVITY_LEVELS).
    static func isAthleteActivity(_ level: String) -> Bool {
        level == "moderate" || level == "very_active"
    }

    // MARK: - Profile-type resolution (clarionProfiles.ts port)

    private static let goalToProfileType: [String: String] = [
        "more_energy": "fatigue_low_energy",
        "improve_fitness": "mixed_sport_athlete",
        "longevity": "heart_health_longevity",
        "better_sleep": "sleep_stress_overreaching",
        "improve_recovery": "high_inflammation_poor_recovery",
        "general_health": "general_health_adult",
    ]

    private static func trainingFocusToProfileType(_ id: String?) -> String? {
        guard let t = id?.trimmingCharacters(in: .whitespaces), !t.isEmpty, t != trainingFocusNoneId else { return nil }
        return training.first(where: { $0.id == t }) != nil ? t : nil
    }

    /// resolveProfileTypeWithLifeStage: life-stage routing beats goal mapping, athletic
    /// focus beats both. Mirrors clarionProfiles.ts exactly.
    static func resolveProfileType(goalIds: [String], trainingFocus: String?, age: String, sex: String) -> String {
        if trainingFocusToProfileType(trainingFocus) == nil {
            let nonSpecific = goalIds.isEmpty || goalIds.allSatisfy { $0 == "general_health" || $0 == "longevity" }
            if nonSpecific, let ageNum = Int(age.trimmingCharacters(in: .whitespaces)), ageNum > 0 {
                if ageNum >= 65 { return "older_adult_healthy_aging" }
                let s = sex.lowercased().trimmingCharacters(in: .whitespaces)
                if s.hasPrefix("f") && ageNum >= 45 && ageNum <= 58 { return "perimenopause_menopause" }
            }
        }
        if let fromTraining = trainingFocusToProfileType(trainingFocus) { return fromTraining }
        guard let first = goalIds.first else { return "general_health_adult" }
        return goalToProfileType[first] ?? "general_health_adult"
    }
}
