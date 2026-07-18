import Foundation
import SwiftUI

/// The native survey's answers + step machine + save. Mirrors the web survey's question
/// flow (OnboardingFlow.tsx steps 0–10) and persists through PATCH /api/account/profile —
/// the same `profiles` columns the web survey writes, so the dashboard/report calibrate
/// identically no matter where the survey was taken.
@MainActor
final class SurveyState: ObservableObject {
    enum Step: Int, CaseIterable {
        case welcome, aboutYou, activity, sleep, alcohol, training, goals, symptoms, supplements, spend, saving, done
    }

    @Published var step: Step = .welcome
    /// Steps counted in the progress bar (welcome/saving/done excluded, like the web's 6-question frame).
    static let questionSteps: [Step] = [.aboutYou, .activity, .sleep, .alcohol, .training, .goals, .symptoms, .supplements, .spend]

    // Answers — ids per SurveyCatalog; empty string = unanswered.
    @Published var age = ""
    @Published var sex = ""
    @Published var heightCm = ""   // canonical metric, stringified
    @Published var weightKg = ""
    @Published var activityLevel = ""
    @Published var sleepBand = ""
    @Published var alcohol = ""
    @Published var trainingFocus = ""
    @Published var goalIds: [String] = []
    @Published var symptomIds: [String] = []
    @Published var supplementNames: [String] = []
    @Published var spend: Double = 0   // $0–300/mo
    @Published var saveError: String? = nil

    private let auth: SupabaseAuth
    private let onFinished: () -> Void

    init(auth: SupabaseAuth, onFinished: @escaping () -> Void) {
        self.auth = auth
        self.onFinished = onFinished
    }

    var isAthlete: Bool { SurveyCatalog.isAthleteActivity(activityLevel) }

    /// Ordered path for THIS user (athletes see training; others skip it) — the web's
    /// conditional STEP_TRAINING branch.
    var path: [Step] {
        var p: [Step] = [.welcome, .aboutYou, .activity, .sleep, .alcohol]
        if isAthlete { p.append(.training) }
        p += [.goals, .symptoms, .supplements, .spend, .saving, .done]
        return p
    }

    /// 0…1 progress across the question steps (welcome = 0).
    var progress: Double {
        let questions = path.filter { $0 != .welcome && $0 != .saving && $0 != .done }
        guard let i = questions.firstIndex(of: step) else { return step == .welcome ? 0 : 1 }
        return Double(i + 1) / Double(questions.count)
    }

    func advance() {
        guard let i = path.firstIndex(of: step), i + 1 < path.count else { return }
        let next = path[i + 1]
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { step = next }
        if next == .saving { Task { await save() } }
    }

    func back() {
        guard let i = path.firstIndex(of: step), i > 0, step != .saving, step != .done else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { step = path[i - 1] }
    }

    var canGoBack: Bool {
        step != .welcome && step != .saving && step != .done
    }

    // MARK: - Save (PATCH only the answered fields — the route updates present keys only,
    // so an unanswered optional can never blank a column)

    func save() async {
        saveError = nil
        var patch: [String: Any] = [:]
        let trimmedAge = age.trimmingCharacters(in: .whitespaces)
        if !trimmedAge.isEmpty { patch["age"] = trimmedAge }
        // "Prefer not to say" isn't in the API's sex enum — persist as empty (the web's direct
        // write path stores it; through the PATCH API the honest equivalent is unset).
        if !sex.isEmpty { patch["sex"] = SurveyCatalog.sexOptions.prefix(3).contains(sex) ? sex : "" }
        if let h = Double(heightCm), h > 0 { patch["height_cm"] = h }
        if let w = Double(weightKg), w > 0 { patch["weight_kg"] = w }
        if !activityLevel.isEmpty { patch["activity_level"] = activityLevel }
        if !sleepBand.isEmpty { patch["sleep_hours_band"] = sleepBand }
        if !alcohol.isEmpty { patch["alcohol_frequency"] = alcohol }
        if isAthlete && !trainingFocus.isEmpty { patch["training_focus"] = trainingFocus }
        if !goalIds.isEmpty { patch["health_goals"] = goalIds.joined(separator: ",") }
        patch["symptoms"] = symptomIds.isEmpty ? "none" : symptomIds.joined(separator: ",")
        patch["current_supplements"] = supplementNames.joined(separator: ", ")
        patch["current_supplement_spend"] = String(Int(spend.rounded()))
        patch["profile_type"] = SurveyCatalog.resolveProfileType(
            goalIds: goalIds, trainingFocus: trainingFocus, age: trimmedAge, sex: sex
        )

        #if DEBUG
        // Screenshot harness: no session in the sim — let the flow complete visually.
        if ProcessInfo.processInfo.arguments.contains("UITEST_SURVEY") {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { step = .done }
            return
        }
        #endif
        do {
            let token = try await auth.validAccessToken()
            _ = try await ClarionAPI.updateProfileSettings(patch: patch, accessToken: token)
            Haptics.success()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { step = .done }
        } catch {
            saveError = "Couldn't save your answers — check your connection and try again."
            Haptics.warning()
        }
    }

    func retrySave() {
        Task { await save() }
    }

    func finish() {
        onFinished()
    }
}
