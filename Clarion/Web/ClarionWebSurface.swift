import SwiftUI

/// A content surface backed by the real signed-in Clarion web page. Wraps
/// `ClarionWebView` with native chrome: a loading spinner overlay, a clean
/// error/retry state, and the SFSafariViewController hand-off for external links.
///
/// It deliberately does NOT own a `NavigationStack` — it only sets the navigation
/// title — so it composes both ways:
///   • as a tab root:   `NavigationStack { ClarionWebSurface(auth:, path:, title:) }`
///   • as a pushed row: `ClarionWebSurface(auth:, path:, title:)` inside an
///                       existing stack (e.g. the Library), which supplies the
///                       back button and title bar.
struct ClarionWebSurface: View {
    let auth: SupabaseAuth
    let path: String
    let title: String

    @StateObject private var controller = ClarionWebController()

    var body: some View {
        ZStack {
            Color.paper.ignoresSafeArea()

            ClarionWebView(path: path, auth: auth, controller: controller)
                .ignoresSafeArea(.container, edges: .bottom)
                .opacity(controller.phase == .failed ? 0 : 1)

            if controller.phase == .loading {
                loadingOverlay.transition(.opacity)
            }
            if controller.phase == .failed {
                errorState.transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: controller.phase)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $controller.externalLink) { link in
            ClarionSafariView(url: link.url).ignoresSafeArea()
        }
    }

    // MARK: - Overlays

    private var loadingOverlay: some View {
        VStack(spacing: Brand.s3) {
            ProgressView()
                .controlSize(.large)
                .tint(Color.forest)
            Text("Loading \(title.lowercased())…")
                .font(.clarionBody(13))
                .foregroundStyle(Color.ink3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.paper)
    }

    private var errorState: some View {
        VStack(spacing: Brand.s4) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.amber)
                .frame(width: 52, height: 52)
                .background(Color.amberWash, in: Circle())

            VStack(spacing: Brand.s2) {
                Text("Couldn't reach Clarion")
                    .font(.clarionDisplay(22))
                    .tracking(-0.015 * 22)
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
                Text("Check your connection and try again — your \(title.lowercased()) lives on clarionlabs.tech.")
                    .font(.clarionBody(14.5))
                    .foregroundStyle(Color.ink2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Haptics.tap()
                controller.retry()
            } label: {
                Text("Try again").frame(maxWidth: 220)
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(Brand.s6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.paper)
    }
}
