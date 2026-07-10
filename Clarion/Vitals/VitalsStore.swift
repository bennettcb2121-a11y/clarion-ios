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
            // The server already falls back to demo when nothing is synced; honor its flag.
            state = decoded.snapshot.isDemo ? .demo(decoded) : .loaded(decoded)
        } catch {
            // Offline / endpoint not deployed yet → local sample so the app still shows its value.
            state = .demo(DemoSnapshot.endurance())
        }
    }
}
