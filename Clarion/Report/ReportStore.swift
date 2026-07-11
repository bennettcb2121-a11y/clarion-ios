import Foundation
import SwiftUI

/// Loads GET /api/report (score + biomarkers + supplement stack). Shared by the Report and
/// Plan tabs so the underlying row is fetched once.
@MainActor
final class ReportStore: ObservableObject {
    enum State {
        case loading
        case ready(ReportResponse)
        case empty            // signed in, no bloodwork yet
        case error(String)
    }

    @Published private(set) var state: State = .loading
    private let auth: SupabaseAuth

    init(auth: SupabaseAuth) { self.auth = auth }

    func load() async {
        do {
            let token = try await auth.validAccessToken()
            var req = URLRequest(url: Config.apiBase.appendingPathComponent("api/report"))
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let decoded = try JSONDecoder().decode(ReportResponse.self, from: data)
            state = decoded.hasBloodwork ? .ready(decoded) : .empty
        } catch {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("UITEST_VITALS") {
                state = .ready(ReportStore.demo)
                return
            }
            #endif
            state = .error("Couldn't load your report. Pull to retry.")
        }
    }

    #if DEBUG
    static let demo = ReportResponse(
        hasBloodwork: true,
        score: 86,
        scoreLabel: "Strong",
        counts: StatusCounts(optimal: 4, low: 1, high: 0, suboptimal: 1),
        lastUpdated: "2026-06-28T14:20:00Z",
        results: [
            BiomarkerResult(
                name: "Ferritin", value: 34, unit: "ng/mL", optimalMin: 50, optimalMax: 150,
                status: "low",
                whyItMatters: "Iron stores — low ferritin blunts recovery and endurance.",
                labNormalMin: 15, labNormalMax: 300, labReferenceSource: "Typical US lab interval",
                isPersonalized: true, mismatch: "standard_optimal_personal_low",
                profileLabel: "female endurance athlete, 34",
                verdict: "Your 34 is “normal” on a lab slip (15–300) but 16 below Clarion's target for a female endurance athlete (50–150).",
                verdictIsFlagged: true,
                description: "Ferritin reflects your body's iron stores.",
                foods: "Red meat, lentils, spinach — pair plant iron with vitamin C.",
                lifestyle: "Avoid tea/coffee within an hour of iron-rich meals.",
                supplementNotes: "Gentle bisglycinate is easier on the gut than sulfate forms.",
                retest: "Retest in 8–10 weeks — ferritin moves slowly.",
                researchSummary: "Endurance athletes below ~50 ng/mL show measurable performance and recovery deficits even without anemia."
            ),
            BiomarkerResult(
                name: "Vitamin D", value: 28, unit: "ng/mL", optimalMin: 30, optimalMax: 50,
                status: "suboptimal",
                whyItMatters: "Bone, immune, and mood support.",
                labNormalMin: 20, labNormalMax: 100, labReferenceSource: "Typical US lab interval",
                isPersonalized: false, mismatch: "standard_optimal_personal_low",
                profileLabel: "female endurance athlete, 34",
                verdict: "Your 28 clears the lab's floor of 20 but sits just under Clarion's 30–50 band.",
                verdictIsFlagged: true,
                retest: "Retest in 8–12 weeks, ideally end of winter.",
                researchSummary: "Levels of 30–50 ng/mL associate with better bone density and immune resilience."
            ),
            BiomarkerResult(name: "HDL", value: 62, unit: "mg/dL", optimalMin: 40, optimalMax: 90, status: "optimal", labNormalMin: 40, labNormalMax: 100, profileLabel: "female endurance athlete, 34", verdict: "Right where you want it — protective at 62.", verdictIsFlagged: false),
            BiomarkerResult(name: "ApoB", value: 74, unit: "mg/dL", optimalMin: 40, optimalMax: 90, status: "optimal", labNormalMin: 40, labNormalMax: 130, profileLabel: "female endurance athlete, 34", verdict: "74 keeps particle count comfortably in band.", verdictIsFlagged: false),
            BiomarkerResult(name: "HbA1c", value: 5.1, unit: "%", optimalMin: 4.0, optimalMax: 5.6, status: "optimal", labNormalMin: 4.0, labNormalMax: 5.6, verdict: "Steady glucose control at 5.1%.", verdictIsFlagged: false),
            BiomarkerResult(name: "TSH", value: 2.1, unit: "mIU/L", optimalMin: 0.5, optimalMax: 4.0, status: "optimal", labNormalMin: 0.4, labNormalMax: 4.5, verdict: "Thyroid signaling looks unremarkable at 2.1.", verdictIsFlagged: false),
        ],
        stack: [
            StackItem(name: "Iron — gentle (bisglycinate)", dose: "25 mg", monthlyCost: 12, recommendationType: "add", reason: "Your ferritin (34) is below the endurance floor of 50 — repletion supports oxygen transport and recovery.", marker: "Ferritin"),
            StackItem(name: "Vitamin D3", dose: "2000 IU", monthlyCost: 8, recommendationType: "add", reason: "Nudges your 28 ng/mL into the 30–50 optimal band.", marker: "Vitamin D"),
            StackItem(name: "Magnesium glycinate", dose: "300 mg", monthlyCost: 9, recommendationType: "keep", reason: "Training support — worth keeping through your current block.", marker: nil),
            StackItem(name: "Zinc picolinate", dose: "30 mg", monthlyCost: 7, recommendationType: "consider_cut", reason: "Nothing in your labs needs it — save $7/mo.", marker: nil),
        ],
        stackMonthlyCost: 29
    )
    #endif
}
