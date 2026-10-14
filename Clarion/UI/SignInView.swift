import SwiftUI
import AuthenticationServices

struct SignInView: View {
    /// Came from the guest survey — their answers are waiting to be saved to the account.
    var savingAnswers = false
    @EnvironmentObject private var auth: SupabaseAuth
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    /// Email first (web parity): enter email → we say whether it has an account and how it signs in.
    enum EmailStage: Equatable { case email, password, create, oauthOnly([String]), checkInbox }
    @State private var stage: EmailStage = .email
    @State private var errorMessage: String?
    /// Raw nonce for the in-flight Sign in with Apple request (hashed into the request,
    /// raw copy handed to Supabase to match the token's nonce claim).
    @State private var appleRawNonce: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Wordmark(nameSize: 36, centered: true)
                        .padding(.top, 60)
                        .padding(.bottom, 8)

                    if savingAnswers {
                        VStack(spacing: 6) {
                            Text("Save your answers.")
                                .font(.clarionDisplay(26))
                                .foregroundStyle(Color.ink)
                            Text("Make a free account to add your labs.")
                                .font(.clarionBody(15))
                                .foregroundStyle(Color.ink2)
                        }
                        .multilineTextAlignment(.center)
                    }

                    // Primary path: the providers most Clarion accounts were created with.
                    // NATIVE Sign in with Apple — a real ASAuthorization request (nonce-protected),
                    // exchanged with Supabase via the id_token grant. No web browser.
                    SignInWithAppleButton(.signIn) { request in
                        let raw = AppleNonce.random()
                        appleRawNonce = raw
                        request.requestedScopes = [.fullName, .email]
                        request.nonce = AppleNonce.sha256(raw)
                    } onCompletion: { result in
                        Task { await handleApple(result) }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .disabled(busy)

                    Button { Task { await oauth(.google) } } label: {
                        HStack(spacing: 10) {
                            // Google's official "G" (their hosted branding asset, unmodified) —
                            // the guidelines forbid recreating or recoloring the mark.
                            Image("GoogleG")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 18, height: 18)
                            Text("Continue with Google").font(.clarionLabel(15))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .foregroundStyle(Color.ink)
                        .background(Color.surface, in: RoundedRectangle(cornerRadius: Brand.r))
                        .overlay(RoundedRectangle(cornerRadius: Brand.r).stroke(Color.line2))
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(busy)

                    HStack(spacing: 10) {
                        Rectangle().fill(Color.line2).frame(height: 1)
                        Text("or").font(.clarionBody(12.5)).foregroundStyle(Color.ink3)
                        Rectangle().fill(Color.line2).frame(height: 1)
                    }
                    emailForm

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.clarionBody(13))
                            .foregroundStyle(Color.clay)
                            .multilineTextAlignment(.center)
                    }

                    if busy { ProgressView().padding(.top, 4) }

                    Text("Use the same account as clarionlabs.tech. Your health data syncs privately to your own dashboard — never for advertising.")
                        .font(.clarionBody(12.5))
                        .foregroundStyle(Color.ink3)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                }
                .padding(24)
            }
            .background(Color.paper.ignoresSafeArea())
        }
    }

    private func field<F: View>(_ f: F) -> some View {
        f.font(.clarionBody(16))
            .padding(14)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: Brand.rSM + 2))
            .overlay(RoundedRectangle(cornerRadius: Brand.rSM + 2).stroke(Color.line2))
    }

    @ViewBuilder
    private var emailForm: some View {
        VStack(spacing: 12) {
            switch stage {
            case .email:
                field(TextField("Email", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.continue)
                    .onSubmit { Task { await checkEmail() } })
                Button { Task { await checkEmail() } } label: {
                    Text("Continue").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy || !email.contains("@"))

            case .password, .create:
                let creating = stage == .create
                VStack(spacing: 4) {
                    Text(creating ? "Create your account." : "Welcome back.")
                        .font(.clarionDisplay(22)).foregroundStyle(Color.ink)
                    Text(email).font(.clarionBody(13.5)).foregroundStyle(Color.ink3)
                }
                field(SecureField(creating ? "Choose a password (6+ characters)" : "Password", text: $password)
                    .textContentType(creating ? .newPassword : .password))
                Button { Task { creating ? await createAccount() : await signIn() } } label: {
                    Text(creating ? "Create account" : "Sign in").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy || password.count < 6)
                if !creating {
                    Link("Forgot password?", destination: Config.apiBase.appendingPathComponent("reset-password"))
                        .font(.clarionLabel(13))
                        .foregroundStyle(Color.forest)
                }
                differentEmail

            case .oauthOnly(let providers):
                VStack(spacing: 4) {
                    Text("Welcome back.").font(.clarionDisplay(22)).foregroundStyle(Color.ink)
                    Text("\(email) signs in with \(providers.contains("google") ? "Google" : "Apple"). Use that button above.")
                        .font(.clarionBody(14)).foregroundStyle(Color.ink2)
                        .multilineTextAlignment(.center)
                }
                Link("Set a password instead", destination: Config.apiBase.appendingPathComponent("reset-password"))
                    .font(.clarionLabel(13))
                    .foregroundStyle(Color.forest)
                differentEmail

            case .checkInbox:
                VStack(spacing: 6) {
                    Text("Check your email.").font(.clarionDisplay(22)).foregroundStyle(Color.ink)
                    Text("Tap the link we sent to \(email), then sign in here.")
                        .font(.clarionBody(14)).foregroundStyle(Color.ink2)
                        .multilineTextAlignment(.center)
                }
                Button("I've confirmed — sign in") { stage = .password }
                    .font(.clarionLabel(14)).foregroundStyle(Color.forest)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: stage)
    }

    private var differentEmail: some View {
        Button("Use a different email") {
            Haptics.tap()
            password = ""; errorMessage = nil
            stage = .email
        }
        .font(.clarionBody(13.5))
        .foregroundStyle(Color.ink3)
    }

    private func checkEmail() async {
        let e = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard e.contains("@") else { return }
        email = e
        busy = true; errorMessage = nil
        defer { busy = false }
        do {
            let s = try await ClarionAPI.emailStatus(e)
            let p = s.providers ?? []
            if s.exists == false { stage = .create }
            else if s.exists == true, !p.isEmpty, !p.contains("email") { stage = .oauthOnly(p) }
            else { stage = .password }
        } catch ClarionAPI.APIError.http(429, _) {
            errorMessage = "Too many tries. Wait a minute."
        } catch {
            stage = .password // can't check — log in is the safe guess
        }
    }

    private func createAccount() async {
        busy = true; errorMessage = nil
        defer { busy = false }
        do {
            if try await auth.signUp(email: email, password: password) == .confirmEmail { stage = .checkInbox }
        } catch { errorMessage = error.localizedDescription }
    }

    private func signIn() async {
        busy = true; errorMessage = nil
        do { try await auth.signIn(email: email, password: password) }
        catch { errorMessage = error.localizedDescription }
        busy = false
    }

    private func oauth(_ provider: OAuthProvider) async {
        busy = true; errorMessage = nil
        Haptics.commit()
        do {
            try await auth.signInWithOAuth(provider)
            Haptics.success()
        } catch {
            errorMessage = error.localizedDescription
        }
        busy = false
    }

    /// Native Sign in with Apple completion: pull the identity token from the credential and
    /// exchange it (with the raw nonce) for a Supabase session.
    private func handleApple(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = appleRawNonce else {
                errorMessage = "Apple sign-in didn't return a token. Please try again."
                return
            }
            busy = true; errorMessage = nil
            Haptics.commit()
            do {
                try await auth.signInWithApple(idToken: idToken, nonce: nonce)
                Haptics.success()
            } catch {
                errorMessage = error.localizedDescription
            }
            busy = false
        case .failure(let error):
            // A user-cancelled sheet is not an error worth surfacing.
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            errorMessage = error.localizedDescription
        }
    }
}
