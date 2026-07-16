import Foundation
import SwiftUI

/// Loads the vitals snapshot from the web backend. Falls back to a sample so the tab is never
/// empty (isDemo drives a "Sample data" label + a Sync prompt).
@MainActor
final class VitalsStore: ObservableObject {
    enum State {
        case loading
        case loaded(SnapshotResponse)
        case demo(SnapshotResponse)

        var response: SnapshotResponse? {
            switch self {
            case .loaded(let r), .demo(let r): return r
            case .loading: return nil
            }
        }
    }

    @Published private(set) var state: State = .loading
    /// The user's widget order (server-resolved: custom if stored, else persona-recommended).
    @Published private(set) var widgetKeys: [String] = []
    private let auth: SupabaseAuth

    init(auth: SupabaseAuth) { self.auth = auth }

    func load() async {
        do {
            let token = try await auth.validAccessToken()
            var req = URLRequest(url: Config.apiBase.appendingPathComponent("api/wearables/snapshot"))
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let decoded = try JSONDecoder().decode(SnapshotResponse.self, from: data)
            widgetKeys = decoded.widgetKeys
            // The server already falls back to demo when nothing is synced; honor its flag.
            state = decoded.snapshot.isDemo ? .demo(decoded) : .loaded(decoded)
        } catch {
            // Preserve real last-good vitals on a flaky reload — never swap a loaded snapshot
            // for the sample (that dropped Home's readiness to "New day." on pull-to-refresh,
            // since briefWindow only honors .loaded in production). Fall back to the local
            // sample ONLY on a first load, when nothing real is on screen yet.
            if case .loaded = state { return }
            let demo = DemoSnapshot.endurance()
            if widgetKeys.isEmpty { widgetKeys = demo.widgetKeys }
            state = .demo(demo)
        }
    }

    /// Persist a new widget selection (shared with the web dashboard via profiles.vitals_widgets).
    /// Optimistic: the UI reorders immediately; a failed save just logs (next load re-syncs).
    func saveWidgets(_ keys: [String]) async {
        widgetKeys = keys
        do {
            let token = try await auth.validAccessToken()
            var req = URLRequest(url: Config.apiBase.appendingPathComponent("api/account/vitals-widgets"))
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.httpBody = try JSONEncoder().encode(["keys": keys])
            _ = try await URLSession.shared.data(for: req)
        } catch {
            // Non-fatal; the local order stands for this session.
        }
    }
}
