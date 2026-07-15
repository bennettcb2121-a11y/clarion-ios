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
        /// One mint per user-initiated load cycle — the loop guard.
        private var mintAttempts = 0

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
        /// embed target. On any failure we still load the embed directly — the web
        /// shows its own login/paywall inside the frame, which is the honest fallback.
        @MainActor
        private func bootstrap() {
            guard mintAttempts == 0 else { loadEmbed(); return }
            mintAttempts += 1
            isBootstrapping = true
            controller.phase = .loading
            Task { @MainActor in
                guard let token = try? await auth.validAccessToken(),
                      let url = try? await ClarionAPI.dashboardLoginLink(path: Self.mintPath(for: path), accessToken: token)
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
            // KVO hook re-mints. endRefreshing happens in didFinish/didFail.
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
            let landedOnLogin = (webView.url?.path.hasPrefix("/login") ?? false)

            if isBootstrapping {
                // The magic-link navigation completed and the session cookie is now set.
                isBootstrapping = false
                ClarionWeb.sessionBootstrapped = true
                loadEmbed()
                return
            }

            if landedOnLogin && mintAttempts == 0 {
                // Cookie missing/expired on a direct embed load — mint once.
                ClarionWeb.sessionBootstrapped = false
                bootstrap()
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

        /// The app-login-link route only mints for bare `/dashboard[/…]` paths. For
        /// anything else (e.g. `/guides`) we mint the cheapest valid path just to set
        /// the cookie, then navigate to the real embed target.
        static func mintPath(for path: String) -> String {
            let ok = path.range(of: "^/dashboard(/[a-z0-9/-]*)?$", options: [.regularExpression, .caseInsensitive]) != nil
            return ok ? path : "/dashboard/vitals"
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
