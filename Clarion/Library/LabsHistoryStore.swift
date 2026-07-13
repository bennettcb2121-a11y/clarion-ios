import Foundation
import SwiftUI

/// Loads GET /api/labs/history — the panel archive + full marker journeys + movers
/// that back the native Labs history screen. Same shape as ReportStore: one
/// tab-owning store, direct Bearer fetch, four honest states.
@MainActor
final class LabsHistoryStore: ObservableObject {
    enum State {
        case loading
        case ready(LabsHistoryResponse)
        case empty            // signed in, no panels on file yet
        case error(String)
    }

    @Published private(set) var state: State = .loading
    private let auth: SupabaseAuth

    init(auth: SupabaseAuth) { self.auth = auth }

    func load() async {
        do {
            let token = try await auth.validAccessToken()
            var req = URLRequest(url: Config.apiBase.appendingPathComponent("api/labs/history"))
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let decoded = try JSONDecoder().decode(LabsHistoryResponse.self, from: data)
            state = decoded.panelCount == 0 ? .empty : .ready(decoded)
        } catch {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("UITEST") }) {
                state = .ready(LabsHistoryStore.demo)
                return
            }
            #endif
            state = .error("Couldn't load your lab history. Pull to retry.")
        }
    }

    #if DEBUG
    /// Three draws on an 8-week cadence: the ferritin repletion arc (18 → 22 → 34)
    /// plus a quiet vitamin D drift — one mover grid with a steady remainder.
    static let demo = LabsHistoryResponse(
        panelCount: 3,
        lastDrawIso: "2026-06-28",
        lastDrawLabel: "Jun 28, 2026",
        retestWeeks: 8,
        panels: [
            LabPanel(id: "save-demo-3", dateIso: "2026-06-28", dateLabel: "Jun 28, 2026",
                     sortTimestamp: "2026-06-28T12:00:00.000Z", source: "upload",
                     markerCount: 24, score: 86, reviewCount: 2),
            LabPanel(id: "save-demo-2", dateIso: "2026-03-14", dateLabel: "Mar 14, 2026",
                     sortTimestamp: "2026-03-14T12:00:00.000Z", source: "upload",
                     markerCount: 22, score: 79, reviewCount: 4),
            LabPanel(id: "save-demo-1", dateIso: "2025-11-02", dateLabel: "Nov 2, 2025",
                     sortTimestamp: "2025-11-02T12:00:00.000Z", source: "manual",
                     markerCount: 14, score: 74, reviewCount: 5),
        ],
        journeys: [
            LabJourney(markerKey: "Ferritin", displayName: "Ferritin", unit: "ng/mL",
                       delta: 16.0, improved: true,
                       points: [
                           LabJourneyPoint(panelId: "save-demo-1", dateIso: "2025-11-02T12:00:00.000Z", dateLabel: "Nov 2, 2025", value: 18),
                           LabJourneyPoint(panelId: "save-demo-2", dateIso: "2026-03-14T12:00:00.000Z", dateLabel: "Mar 14, 2026", value: 22),
                           LabJourneyPoint(panelId: "save-demo-3", dateIso: "2026-06-28T12:00:00.000Z", dateLabel: "Jun 28, 2026", value: 34),
                       ]),
            LabJourney(markerKey: "Vitamin D", displayName: "Vitamin D", unit: "ng/mL",
                       delta: 4.0, improved: true,
                       points: [
                           LabJourneyPoint(panelId: "save-demo-2", dateIso: "2026-03-14T12:00:00.000Z", dateLabel: "Mar 14, 2026", value: 24),
                           LabJourneyPoint(panelId: "save-demo-3", dateIso: "2026-06-28T12:00:00.000Z", dateLabel: "Jun 28, 2026", value: 28),
                       ]),
            LabJourney(markerKey: "HbA1c", displayName: "HbA1c", unit: "%",
                       delta: -0.1, improved: nil,
                       points: [
                           LabJourneyPoint(panelId: "save-demo-1", dateIso: "2025-11-02T12:00:00.000Z", dateLabel: "Nov 2, 2025", value: 5.2),
                           LabJourneyPoint(panelId: "save-demo-3", dateIso: "2026-06-28T12:00:00.000Z", dateLabel: "Jun 28, 2026", value: 5.1),
                       ]),
        ],
        movers: LabMovers(markerKeys: ["Ferritin", "Vitamin D"], steadyCount: 1)
    )
    #endif
}
