import SwiftUI
import WebKit
import SafariServices

// =============================================================================
// Hybrid shell: the content-heavy surfaces (Report, Plan, Shop, Labs, Biomarkers,
// Guides) are the REAL signed-in clarionlabs.tech pages, rendered inside a
// WKWebView with the native chrome (nav bar, spinner, error/retry, pull-to-refresh)
// wrapped around them. The native reconstructions never matched the live site and
// couldn't load real data; the web is the source of truth, so we embed it honestly.
// =============================================================================

/// Process-wide web configuration shared by every ClarionWebView.
enum ClarionWeb {
    /// The canonical host. Anything else (esp. amazon.com) is treated as external.
    static let host = "clarionlabs.tech"

    /// Supabase auth host — the magic-link's FIRST hop lands here before it 302s
    /// back to clarionlabs.tech, so it must count as "internal" for navigation
    /// (otherwise bootstrap would be diverted to Safari and never set the cookie).
    static let authHost = Config.supabaseURL.host ?? "supabase.co"

    /// ONE persistent cookie jar for the whole process. The Supabase session cookie
    /// set during the first surface's bootstrap therefore persists across every tab
    /// AND across relaunches — never `.nonPersistent()`, which would force a fresh
    /// sign-in on every surface.
    static let dataStore: WKWebsiteDataStore = .default()

    /// Launch-scoped hint: has any surface completed the signed-in bootstrap yet?
    /// The cookie itself outlives the process (it lives in `dataStore`); this flag
    /// just lets the first surface of a launch mint proactively rather than flash
    /// the web login screen. Reset to false whenever a load lands on /login.
    @MainActor static var sessionBootstrapped = false

    /// Hosts we consider internal for main-frame navigation decisions.
    static func isInternalHost(_ host: String?) -> Bool {
        guard let host else { return false }
        return host == ClarionWeb.host || host.hasSuffix(".\(ClarionWeb.host)")
            || host == authHost || host.hasSuffix(".\(authHost)")
    }
}

/// Presentable wrapper so `.sheet(item:)` can carry an external URL out to Safari.
struct ClarionExternalLink: Identifiable {
    let id = UUID()
    let url: URL
}

/// Drives one ClarionWebView. Owned by ClarionWebSurface as a `@StateObject` so the
/// native overlays (spinner / error / external-link sheet) and the Retry action can
/// talk to the underlying WKWebView.
@MainActor
final class ClarionWebController: ObservableObject {
    enum Phase: Equatable { case loading, loaded, failed }

    @Published var phase: Phase = .loading
    /// Set by the coordinator when a link leaves our world (external host / amazon).
    @Published var externalLink: ClarionExternalLink?

    fileprivate var reload: (() -> Void)?

    /// Retry from the error state — re-runs the load (re-checking session state).
    func retry() { reload?() }
}

/// The WKWebView itself. Loads `path?embed=1` (the web's chromeless embed mode) and
/// bootstraps a signed-in session via the existing app-login-link handoff.
struct ClarionWebView: UIViewRepresentable {
    let path: String
    let auth: SupabaseAuth
    @ObservedObject var controller: ClarionWebController

    func makeCoordinator() -> Coordinator {
        Coordinator(path: path, auth: auth, controller: controller)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = ClarionWeb.dataStore
        config.allowsInlineMediaPlayback = true
        // Minimal embed smoothing: kill the long-press callout + tap highlight so
        // links/images feel native. We let the web's ?embed=1 do the real chrome work.
        let css = """
        var s=document.createElement('style');
        s.textContent='*{-webkit-touch-callout:none;-webkit-tap-highlight-color:transparent}';
        document.documentElement.appendChild(s);
        """
        config.userContentController.addUserScript(
            WKUserScript(source: css, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        // Paper-toned canvas so there's no white flash under the spinner overlay.
        webView.isOpaque = false
        webView.backgroundColor = UIColor(Color.paper)
        webView.scrollView.backgroundColor = UIColor(Color.paper)

        // Pull-to-refresh on the web scroll view.
        let refresh = UIRefreshControl()
        refresh.addTarget(context.coordinator, action: #selector(Coordinator.handleRefresh), for: .valueChanged)
        webView.scrollView.refreshControl = refresh
        webView.scrollView.bounces = true

        context.coordinator.bind(webView: webView)
        // Wire the controller's imperative hooks (Retry) to this coordinator.
        controller.reload = { [weak coordinator = context.coordinator] in coordinator?.load() }

        context.coordinator.load()
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // The path is fixed per surface; nothing to reconcile. Reloads flow through
        // the controller (Retry) and the refresh control.
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let path: String
        private let auth: SupabaseAuth
        private let controller: ClarionWebController

        private weak var webView: WKWebView?
        private var urlObservation: NSKeyValueObservation?

        /// True while the magic-link (mint) navigation is in flight.
        private var isBootstrapping = false
        /// Mints per user-initiated load cycle — the loop guard. The first mint may
        /// legitimately bounce (clock skew, transient Supabase hiccup), so we allow
        /// ONE automatic retry; after that we surface the native error state rather
        /// than minting forever.
        private var mintAttempts = 0
        private static let maxMintAttempts = 2

        init(path: String, auth: SupabaseAuth, controller: ClarionWebController) {
            self.path = path
            self.auth = auth
            self.controller = controller
        }

        func bind(webView: WKWebView) {
            self.webView = webView
            // Catch client-side redirects to /login (Next.js router.replace) that the
            // navigation delegate's didFinish never sees — KVO on the live URL does.
            urlObservation = webView.observe(\.url, options: [.new]) { [weak self] wv, _ in
                Task { @MainActor in self?.handleURLChange(wv.url) }
            }
        }

        func tearDown() {
            urlObservation?.invalidate()
            urlObservation = nil
        }

        // MARK: Load orchestration

        /// Entry point for the initial load, Retry, and (indirectly) refresh.
        @MainActor
        func load() {
            mintAttempts = 0
            if ClarionWeb.sessionBootstrapped {
                loadEmbed()
            } else {
                bootstrap()
            }
        }

        /// Load the real target page in the web's chromeless embed mode.
        @MainActor
        private func loadEmbed() {
            isBootstrapping = false
            controller.phase = .loading
            webView?.load(URLRequest(url: Self.embedURL(for: path)))
        }

        /// Mint a one-time signed-in URL (sets the Supabase cookie), then land on the
        /// embed target. The mint ALWAYS targets `bootstrapPath` — Supabase only
        /// honors redirect targets on its URL-configuration allowlist, and
        /// /dashboard/vitals is the one path proven allowlisted (the HomeView footer
        /// flow has always used it). Minting the surface's own path risks a Supabase
        /// redirect rejection that strands the webview on an error page.
        ///
        /// If the mint API itself is unavailable (no session / request failed) we
        /// load the embed directly — the web shows its own login/paywall inside the
        /// frame, which is the honest fallback.
        @MainActor
        private func bootstrap() {
            guard mintAttempts < Self.maxMintAttempts else {
                // Both mints bounced — show the native error state (Try again re-runs
                // load()) instead of stranding on Supabase's error/login page.
                isBootstrapping = false
                controller.phase = .failed
                return
            }
            mintAttempts += 1
            isBootstrapping = true
            controller.phase = .loading
            Task { @MainActor in
                guard let token = try? await auth.validAccessToken(),
                      let url = try? await ClarionAPI.dashboardLoginLink(path: Self.bootstrapPath, accessToken: token)
                else {
                    // No session (or mint failed) — just show the embed; the site handles auth.
                    isBootstrapping = false
                    loadEmbed()
                    return
                }
                webView?.load(URLRequest(url: url))
            }
        }

        // MARK: Refresh

        @objc func handleRefresh() {
            // Reload the current page; an expired cookie will bounce to /login and the
            // didFinish/KVO hooks re-mint. A pull is a fresh user-initiated load cycle,
            // so reset the mint budget. endRefreshing happens in didFinish/didFail.
            mintAttempts = 0
            webView?.reload()
        }

        // MARK: WKNavigationDelegate

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else { decisionHandler(.allow); return }
            let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
            let isAmazonRedirect = url.path.hasPrefix("/go/amazon")
            let isExternalHost = !ClarionWeb.isInternalHost(url.host)

            // Divert only main-frame navigations that leave clarionlabs.tech, or that
            // hit our /go/amazon affiliate redirect — hand those to SFSafariViewController.
            // Subresources (fonts, images, analytics, iframes) load normally.
            if isMainFrame && (isExternalHost || isAmazonRedirect) {
                decisionHandler(.cancel)
                openExternal(url)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.scrollView.refreshControl?.endRefreshing()
            let finalURL = webView.url

            if isBootstrapping {
                // The magic-link navigation (mint → Supabase verify → 302 back to
                // clarionlabs.tech/dashboard/vitals) has finished. Check where it
                // actually landed before trusting the cookie.
                isBootstrapping = false
                if Self.bootstrapSucceeded(finalURL) {
                    // Cookie is set. Hop onward to the real target; phase stays
                    // .loading, so the native overlay covers the intermediate
                    // vitals page — the webview is only revealed once the FINAL
                    // target finishes below.
                    ClarionWeb.sessionBootstrapped = true
                    loadEmbed()
                } else {
                    // Supabase rejected the redirect (login page, #error=/?error=
                    // fragment, or stranded on the auth host). Retry the mint once;
                    // bootstrap() itself fails over to the native error state when
                    // attempts are exhausted.
                    ClarionWeb.sessionBootstrapped = false
                    bootstrap()
                }
                return
            }

            if finalURL?.path.hasPrefix("/login") == true, mintAttempts < Self.maxMintAttempts {
                // Cookie missing/expired on a direct embed load — mint. (When the
                // mint API is unavailable — signed out, offline mint — attempts are
                // consumed without a hop and we fall through to reveal the site's
                // own login page, the honest fallback.)
                ClarionWeb.sessionBootstrapped = false
                bootstrap()
                return
            }

            // Never reveal the intermediate bootstrap hop as if it were the
            // destination — if we somehow finished on /dashboard/vitals while this
            // surface targets another path, keep the overlay up and hop onward.
            if path != Self.bootstrapPath, finalURL?.path == Self.bootstrapPath {
                loadEmbed()
                return
            }

            controller.phase = .loaded
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            finishWithFailure(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            finishWithFailure(error)
        }

        @MainActor
        private func finishWithFailure(_ error: Error) {
            webView?.scrollView.refreshControl?.endRefreshing()
            let ns = error as NSError
            // Ignore the errors we cause ourselves: cancelled loads (external diversion)
            // and policy-change frame interruptions.
            if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
            if ns.domain == "WebKitErrorDomain" && ns.code == 102 { return } // frame load interrupted by policy
            if isBootstrapping { isBootstrapping = false }
            controller.phase = .failed
        }

        // MARK: Helpers

        @MainActor
        private func handleURLChange(_ url: URL?) {
            guard let url, url.path.hasPrefix("/login") else { return }
            guard !isBootstrapping, mintAttempts == 0 else { return }
            ClarionWeb.sessionBootstrapped = false
            bootstrap()
        }

        private func openExternal(_ url: URL) {
            Task { @MainActor in controller.externalLink = ClarionExternalLink(url: url) }
        }

        /// `https://clarionlabs.tech{path}?embed=1` — the chromeless web experience.
        static func embedURL(for path: String) -> URL {
            var comps = URLComponents(url: Config.apiBase, resolvingAgainstBaseURL: false)!
            comps.path = path
            comps.queryItems = [URLQueryItem(name: "embed", value: "1")]
            return comps.url ?? Config.apiBase
        }

        /// The ONLY path we ever mint login links for. Supabase's redirect allowlist
        /// (Auth → URL Configuration) is the gate: /dashboard/vitals is proven
        /// allowlisted by the long-standing HomeView footer flow, so every surface
        /// bootstraps its cookie through it and then navigates to its real target.
        static let bootstrapPath = "/dashboard/vitals"

        /// Did a URL land somewhere that means auth failed — the web login page, or
        /// a Supabase auth error carried in the fragment/query (#error= / ?error=)?
        static func isAuthFailure(_ url: URL?) -> Bool {
            guard let url else { return true }
            if url.path.hasPrefix("/login") { return true }
            if url.fragment?.contains("error=") == true { return true }
            if url.query?.contains("error=") == true { return true }
            return false
        }

        /// The bootstrap hop only counts as a success if it ended back on the
        /// clarion host (not stranded on the Supabase auth host) with no auth error.
        static func bootstrapSucceeded(_ url: URL?) -> Bool {
            guard let url, let host = url.host else { return false }
            let onClarion = host == ClarionWeb.host || host.hasSuffix(".\(ClarionWeb.host)")
            return onClarion && !isAuthFailure(url)
        }
    }
}

/// In-app Safari for external / affiliate handoffs. The `/go/amazon` redirect and any
/// off-site link open here so the affiliate hop starts on our domain — never a raw
/// `UIApplication.open` on amazon.com.
struct ClarionSafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
