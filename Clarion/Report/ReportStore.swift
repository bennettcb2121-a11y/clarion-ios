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
        counts: StatusCounts(optimal: 19, low: 1, high: 0, suboptimal: 1),
        lastUpdated: nil,
        results: [
            BiomarkerResult(name: "Ferritin", value: 34, optimalMin: 50, optimalMax: 150, status: "low", whyItMatters: "Iron stores — low ferritin blunts recovery and endurance."),
            BiomarkerResult(name: "Vitamin D", value: 28, optimalMin: 30, optimalMax: 50, status: "suboptimal", whyItMatters: "Bone, immune, and mood support."),
            BiomarkerResult(name: "HDL", value: 62, optimalMin: 40, optimalMax: 90, status: "optimal", whyItMatters: nil),
            BiomarkerResult(name: "ApoB", value: 74, optimalMin: 40, optimalMax: 90, status: "optimal", whyItMatters: nil),
            BiomarkerResult(name: "HbA1c", value: 5.1, optimalMin: 4.0, optimalMax: 5.6, status: "optimal", whyItMatters: nil),
            BiomarkerResult(name: "TSH", value: 2.1, optimalMin: 0.5, optimalMax: 4.0, status: "optimal", whyItMatters: nil),
        ],
        stack: [
            StackItem(name: "Iron — gentle (bisglycinate)", dose: "25 mg", monthlyCost: 12, recommendationType: "add", reason: "Your ferritin (34) is below the endurance floor of 50 — repletion supports oxygen transport and recovery.", marker: "Ferritin"),
            StackItem(name: "Vitamin D3", dose: "2000 IU", monthlyCost: 8, recommendationType: "add", reason: "Nudges your 28 ng/mL into the 30–50 optimal band.", marker: "Vitamin D"),
        ],
        stackMonthlyCost: 20
    )
    #endif
}
