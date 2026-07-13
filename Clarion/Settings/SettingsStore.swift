import Foundation
import SwiftUI

/// Settings read/write against GET/PATCH /api/account/profile. Mirrors ReportStore's
/// shape (one @Published state, bearer via auth.validAccessToken). Saves are per-control
/// (the web's persistProfilePatch): optimistic UI is the caller's job — this store only
/// replaces its profile with the server's echoed fresh row on success, and surfaces the
/// server's 400 message (inline, next to the control) on rejection.
@MainActor
final class SettingsStore: ObservableObject {
    enum State {
        case loading
        /// nil profile = survey not finished yet (the API returns null, not 404).
        case ready(ProfileSettings?)
        case error(String)
    }

    @Published private(set) var state: State = .loading
    /// The last PATCH rejection, keyed by a caller-chosen field group (e.g. "age",
    /// "reminders"). Cleared on the next successful save of that group.
    @Published private(set) var fieldErrors: [String: String] = [:]
    @Published private(set) var saving = false

    private let auth: SupabaseAuth

    init(auth: SupabaseAuth) { self.auth = auth }

    var profile: ProfileSettings? {
        if case .ready(let p) = state { return p }
        return nil
    }

    func load() async {
        do {
            let token = try await auth.validAccessToken()
            let profile = try await ClarionAPI.fetchProfileSettings(accessToken: token)
            state = .ready(profile)
        } catch ClarionAPI.APIError.http(404, _) {
            // Prod main can lag the branch that ships the settings API.
            state = .error("Account settings are still rolling out — manage them on the web for now.")
        } catch {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("UITEST_VITALS") {
                state = .ready(SettingsStore.demo)
                return
            }
            #endif
            state = .error("Couldn't load your settings. Pull to retry.")
        }
    }

    /// PATCH a subset of fields. `field` labels the control group for inline errors.
    /// Returns true on success (the echoed fresh profile replaces local state).
    @discardableResult
    func save(_ patch: [String: Any], field: String) async -> Bool {
        guard !patch.isEmpty else { return true }
        saving = true
        defer { saving = false }
        do {
            let token = try await auth.validAccessToken()
            let fresh = try await ClarionAPI.updateProfileSettings(patch: patch, accessToken: token)
            state = .ready(fresh)
            fieldErrors[field] = nil
            return true
        } catch ClarionAPI.APIError.http(let code, let msg) {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("UITEST_VITALS") {
                applyDemoPatch(patch)
                return true
            }
            #endif
            fieldErrors[field] = code == 400 ? msg : "Couldn't save (\(code)). Try again."
            return false
        } catch {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("UITEST_VITALS") {
                applyDemoPatch(patch)
                return true
            }
            #endif
            fieldErrors[field] = "Couldn't save — check your connection."
            return false
        }
    }

    func clearError(_ field: String) {
        fieldErrors[field] = nil
    }

    #if DEBUG
    /// Screenshot harness: apply the patch locally so toggles/pickers respond in demo mode.
    private func applyDemoPatch(_ patch: [String: Any]) {
        guard var p = profile else { return }
        for (key, value) in patch {
            switch key {
            case "age": p.age = value as? String ?? p.age
            case "sex": p.sex = value as? String ?? p.sex
            case "profile_type": p.profileType = value as? String
            case "symptoms": p.symptoms = value as? String
            case "diet_preference": p.dietPreference = value as? String
            case "height_cm": p.heightCm = value as? Double
            case "weight_kg": p.weightKg = value as? Double
            case "improvement_preference": p.improvementPreference = value as? String
            case "supplement_form_preference": p.supplementFormPreference = value as? String
            case "retest_weeks": p.retestWeeks = (value as? NSNumber)?.doubleValue
            case "score_goal": p.scoreGoal = (value as? NSNumber)?.doubleValue
            case "streak_milestones": p.streakMilestones = value as? Bool
            case "daily_reminder": p.dailyReminder = value as? Bool
            case "daily_reminder_time": p.dailyReminderTime = value as? String
            case "daily_reminder_timezone": p.dailyReminderTimezone = value as? String
            case "daily_reminder_channel": p.dailyReminderChannel = value as? String
            case "notify_reorder_email": p.notifyReorderEmail = value as? Bool
            case "notify_reorder_days": p.notifyReorderDays = (value as? NSNumber)?.doubleValue
            default: break
            }
        }
        state = .ready(p)
    }

    /// Demo profile for the screenshot harness — same persona as ReportStore.demo
    /// (female endurance athlete, 34).
    static let demo = ProfileSettings(
        age: "34",
        sex: "Female",
        profileType: "endurance_athlete",
        symptoms: "fatigue,poor_recovery",
        healthGoals: nil,
        dietPreference: nil,
        heightCm: 170,
        weightKg: 62,
        improvementPreference: "Combination",
        supplementFormPreference: "any",
        currentSupplements: "",
        currentSupplementSpend: "$40",
        shoppingPreference: "Best value",
        retestWeeks: 8,
        scoreGoal: 90,
        streakMilestones: true,
        dailyReminder: true,
        dailyReminderTime: "08:00",
        dailyReminderTimezone: "America/New_York",
        dailyReminderChannel: "email",
        phone: nil,
        smsReminderVerifiedAt: nil,
        smsReminderOptedOutAt: nil,
        notifyReorderEmail: true,
        notifyReorderDays: 7,
        vitalsWidgets: nil,
        email: "demo@clarionlabs.tech",
        analysisPurchasedAt: "2026-03-14T12:00:00.000Z",
        planTier: "full",
        menopauseStage: nil,
        updatedAt: "2026-07-01T12:00:00.000Z"
    )
    #endif
}
