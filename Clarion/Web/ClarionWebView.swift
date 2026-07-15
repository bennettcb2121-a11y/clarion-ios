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

    /// ONE persistent cookie jar for the whole process. The @supabase/ssr session
    /// cookie written by the first surface's web-session handoff therefore persists
    /// across every tab AND across relaunches — never `.nonPersistent()`, which would
    /// force a fresh handoff on every surface.
    static let dataStore: WKWebsiteDataStore = .default()

    /// Launch-scoped hint: has any surface completed the signed-in handoff yet? The
    /// cookie itself outlives the process (it lives in `dataStore`); this flag just
    /// lets subsequent surfaces of a launch load `path?embed=1` directly instead of
    /// re-running the handoff. Reset to false whenever a load lands on an auth wall.
    @MainActor static var sessionEstablished = false

    /// OAuth-provider hosts that MUST never render inside the embedded webview —
    /// Google (and Apple/Facebook) block their OAuth flow in a WKWebView, which is the
    /// "oauth_state" dead-end the handoff exists to avoid.
    static func isOAuthProviderHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "accounts.google.com"
            || host == "appleid.apple.com"
            || host == "facebook.com" || host.hasSuffix(".facebook.com")
    }

    /// Hosts we consider internal for main-frame navigation decisions.
    static func isInternalHost(_ host: String?) -> Bool {
        guard let host else { return false }
        return host == ClarionWeb.host || host.hasSuffix(".\(ClarionWeb.host)")
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
/// signs the webview in via the `/api/app/web-session` header handoff: one request
/// carrying the Supabase tokens writes the @supabase/ssr cookie and 302s onto the
/// embed target. No magic link, no in-webview Google/Apple OAuth, no login page.
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

        /// True while the `/api/app/web-session` handoff navigation is in flight (from
        /// firing the header request until it lands on the embed target or fails).
        private var handoffInFlight = false
        /// Handoffs per user-initiated load cycle — the loop guard. The first handoff
        /// may legitimately fail (a just-expired token, a transient hiccup), so we allow
        /// ONE automatic retry; after that we surface the native error state (whose "Try
        /// again" re-runs the handoff) rather than looping forever.
        private var handoffAttempts = 0
        private static let maxHandoffAttempts = 2

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
            handoffAttempts = 0
            if ClarionWeb.sessionEstablished {
                // Cookie already written this launch — load the target directly.
                loadEmbed()
            } else {
                // First web surface of the launch (or after a sign-out) — establish the
                // session cookie via the header handoff, which lands us on the target.
                handoff()
            }
        }

        /// Load the real target page in the web's chromeless embed mode (cookie already set).
        @MainActor
        private func loadEmbed() {
            handoffInFlight = false
            controller.phase = .loading
            webView?.load(URLRequest(url: Self.embedURL(for: path)))
        }

        /// Sign the webview in: load `GET /api/app/web-session?next=<target?embed=1>`
        /// with the Supabase tokens as headers. The route writes the @supabase/ssr
        /// cookie into the shared data store and 302s onto the embed target — so this
        /// ONE request lands the webview signed-in on the destination, with no login
        /// page and no in-webview OAuth. The native loading overlay stays up until that
        /// final target commits (didFinish), so the 302 hop never flashes.
        ///
        /// If there's no device session (or the token refresh fails) we show the native
        /// error state — NEVER the web login page.
        @MainActor
        private func handoff() {
            guard handoffAttempts < Self.maxHandoffAttempts else {
                // Retry budget spent — surface the native error (Try again re-runs load()).
                handoffInFlight = false
                controller.phase = .failed
                return
            }
            handoffAttempts += 1
            handoffInFlight = true
            controller.phase = .loading
            Task { @MainActor in
                guard let tokens = try? await auth.validSessionTokens() else {
                    // No signed-in device session — can't hand off. Show the native error
                    // rather than letting the webview render a login page.
                    handoffInFlight = false
                    controller.phase = .failed
                    return
                }
                var req = URLRequest(url: Self.handoffURL(for: path))
                req.setValue("Bearer \(tokens.access)", forHTTPHeaderField: "Authorization")
                req.setValue(tokens.refresh, forHTTPHeaderField: "X-Refresh-Token")
                webView?.load(req)
            }
        }

        /// Auth failure recovery, shared by the guard, didFinish, and the KVO hook:
        /// forget the launch flag and re-run the handoff (which itself falls over to the
        /// native error state once the retry budget is spent).
        @MainActor
        private func recoverFromAuthFailure() {
            ClarionWeb.sessionEstablished = false
            handoff()
        }

        // MARK: Refresh

        @objc func handleRefresh() {
            // A pull is a fresh user-initiated cycle: reset the auth-failure budget so an
            // expired cookie can re-handoff. Reload the current page; if the cookie has
            // expired the load will bounce toward /login, which the guard cancels and
            // recovers via a fresh handoff. endRefreshing happens in didFinish/didFail.
            handoffAttempts = 0
            if ClarionWeb.sessionEstablished {
                webView?.reload()
            } else {
                handoff()
            }
        }

        // MARK: WKNavigationDelegate

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else { decisionHandler(.allow); return }
            let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true

            // HARD GUARD: the webview must NEVER render an auth wall — a login page or an
            // OAuth provider (Google/Apple/Facebook), which is the "oauth_state" dead-end
            // Google throws inside embedded webviews. Cancel any such main-frame nav and
            // recover by re-running the header handoff (or the native error if spent).
            if isMainFrame && Self.isBlockedAuthNavigation(url) {
                decisionHandler(.cancel)
                recoverFromAuthFailure()
                return
            }

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

            if handoffInFlight {
                // The handoff navigation (web-session route → 302 → embed target) has
                // finished. Trust the cookie only if it actually landed on a real page.
                handoffInFlight = false
                if Self.handoffLanded(finalURL) {
                    ClarionWeb.sessionEstablished = true
                    handoffAttempts = 0 // episode over — restore the budget for a later re-auth
                    controller.phase = .loaded
                } else {
                    // The route returned an error body (401/400 — no redirect fired) or
                    // bounced to an auth wall. Retry the handoff once; handoff() itself
                    // fails over to the native error state when the budget is spent. The
                    // overlay stays up throughout, so the raw error is never revealed.
                    recoverFromAuthFailure()
                }
                return
            }

            // A direct embed load (cookie already set this launch) that bounced to an
            // auth wall means the cookie expired — re-handoff. (The decidePolicyFor guard
            // catches full navigations to /login first; this is the belt-and-suspenders.)
            if Self.isAuthFailure(finalURL) {
                recoverFromAuthFailure()
                return
            }

            handoffAttempts = 0 // a clean load means we're healthy — restore the budget
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
            if handoffInFlight { handoffInFlight = false }
            controller.phase = .failed
        }

        // MARK: Helpers

        @MainActor
        private func handleURLChange(_ url: URL?) {
            // Catch client-side (Next.js router.replace) redirects to an auth wall that
            // decidePolicyFor never sees — a same-document push doesn't hit the delegate.
            guard let url, Self.isBlockedAuthNavigation(url) else { return }
            guard !handoffInFlight else { return }
            recoverFromAuthFailure()
        }

        private func openExternal(_ url: URL) {
            Task { @MainActor in controller.externalLink = ClarionExternalLink(url: url) }
        }

        /// `https://clarionlabs.tech{path}?embed=1` — the chromeless web experience,
        /// loaded directly once the session cookie is set for the launch.
        static func embedURL(for path: String) -> URL {
            var comps = URLComponents(url: Config.apiBase, resolvingAgainstBaseURL: false)!
            comps.path = path.components(separatedBy: "?").first ?? path
            comps.queryItems = [URLQueryItem(name: "embed", value: "1")]
            return comps.url ?? Config.apiBase
        }

        /// The embed-mode path (`{path}?embed=1`) used as the handoff's `next` target.
        static func embedTargetPath(for path: String) -> String {
            if path.contains("embed=") { return path }
            return path.contains("?") ? "\(path)&embed=1" : "\(path)?embed=1"
        }

        /// `https://clarionlabs.tech/api/app/web-session?next=<embed target, encoded>` —
        /// the handoff URL. Loading it with the token headers sets the cookie and 302s to
        /// `next`. `next` is fully percent-encoded so its own `?embed=1` can't be misread
        /// as a second query param by the route's `searchParams.get("next")`.
        static func handoffURL(for path: String) -> URL {
            let next = embedTargetPath(for: path)
            let encoded = next.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? next
            let base = Config.apiBase.absoluteString
            return URL(string: "\(base)/api/app/web-session?next=\(encoded)") ?? Config.apiBase
        }

        /// Would loading `url` in the main frame render an auth wall we must never show —
        /// the web login page, our OAuth start routes, or an OAuth provider's own domain?
        static func isBlockedAuthNavigation(_ url: URL) -> Bool {
            if ClarionWeb.isOAuthProviderHost(url.host) { return true }
            let path = url.path
            if path == "/login" || path.hasPrefix("/login/") { return true }
            if path.hasPrefix("/auth/google") || path.hasPrefix("/auth/apple") { return true }
            return false
        }

        /// Did a URL land somewhere that means auth failed — the web login page, or an
        /// auth error carried in the fragment/query (#error= / ?error=)?
        static func isAuthFailure(_ url: URL?) -> Bool {
            guard let url else { return true }
            if isBlockedAuthNavigation(url) { return true }
            if url.fragment?.contains("error=") == true { return true }
            if url.query?.contains("error=") == true { return true }
            return false
        }

        /// The handoff only counts as landed if it 302'd OFF the web-session route onto a
        /// real clarion page (not stranded on the route's 401/400 JSON body) with no auth
        /// error — proof the cookie was written.
        static func handoffLanded(_ url: URL?) -> Bool {
            guard let url, let host = url.host else { return false }
            let onClarion = host == ClarionWeb.host || host.hasSuffix(".\(ClarionWeb.host)")
            return onClarion && url.path != "/api/app/web-session" && !isAuthFailure(url)
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
