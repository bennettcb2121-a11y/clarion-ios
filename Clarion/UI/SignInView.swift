import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @EnvironmentObject private var auth: SupabaseAuth
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var emailExpanded = false
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

                    // Email is the secondary path (disclosed on tap).
                    if emailExpanded {
                        emailForm
                    } else {
                        Button("Sign in with email instead") {
                            Haptics.tap()
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { emailExpanded = true }
                        }
                        .font(.clarionBody(13.5))
                        .foregroundStyle(Color.ink3)
                        .padding(.top, 2)
                    }

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

    private var emailForm: some View {
        VStack(spacing: 12) {
            TextField("Email", text: $email)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.clarionBody(16))
                .padding(14)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: Brand.rSM + 2))
                .overlay(RoundedRectangle(cornerRadius: Brand.rSM + 2).stroke(Color.line2))
            SecureField("Password", text: $password)
                .textContentType(.password)
                .font(.clarionBody(16))
                .padding(14)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: Brand.rSM + 2))
                .overlay(RoundedRectangle(cornerRadius: Brand.rSM + 2).stroke(Color.line2))

            Button {
                Task { await signIn() }
            } label: {
                Text("Sign in").frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(busy || email.isEmpty || password.isEmpty)

            Link("Forgot password?", destination: Config.apiBase.appendingPathComponent("reset-password"))
                .font(.clarionLabel(13))
                .foregroundStyle(Color.forest)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
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
