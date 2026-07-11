import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @EnvironmentObject private var auth: SupabaseAuth
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var emailExpanded = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 6) {
                        Text("Clarion Labs")
                            .font(.system(size: 40, weight: .bold, design: .serif))
                            .foregroundStyle(Color.ink)
                        Text("brilliantly clear")
                            .font(.footnote)
                            .foregroundStyle(Color.inkMuted)
                    }
                    .padding(.top, 60)
                    .padding(.bottom, 8)

                    // Primary path: the providers most Clarion accounts were created with.
                    SignInWithAppleButton(.signIn) { _ in } onCompletion: { _ in }
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            // Route Apple's button through our web-OAuth flow (keeps one auth path).
                            Button { Task { await oauth(.apple) } } label: { Color.clear }
                                .buttonStyle(.plain)
                        )
                        .disabled(busy)

                    Button { Task { await oauth(.google) } } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "g.circle.fill")
                            Text("Continue with Google").fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .foregroundStyle(Color.ink)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.12)))
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
                        .font(.footnote)
                        .foregroundStyle(Color.inkMuted)
                        .padding(.top, 2)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Color.clay)
                            .multilineTextAlignment(.center)
                    }

                    if busy { ProgressView().padding(.top, 4) }

                    Text("Use the same account as clarionlabs.tech. Your health data syncs privately to your own dashboard — never for advertising.")
                        .font(.caption)
                        .foregroundStyle(Color.inkMuted)
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
                .padding(14)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.1)))
            SecureField("Password", text: $password)
                .textContentType(.password)
                .padding(14)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.1)))

            Button {
                Task { await signIn() }
            } label: {
                Text("Sign in").frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(busy || email.isEmpty || password.isEmpty)

            Link("Forgot password?", destination: Config.apiBase.appendingPathComponent("reset-password"))
                .font(.footnote)
                .foregroundStyle(Color.forestInk)
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
}
