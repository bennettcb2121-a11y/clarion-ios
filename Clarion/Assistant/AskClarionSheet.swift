import SwiftUI

/// The native Ask Clarion chat — parity with the web's assistant panel (ClarionAssistant.tsx)
/// plus the richer biomarker-aware variant: sends {message, biomarkerSnapshot?,
/// conversationHistory} to POST /api/chat and renders the single JSON reply under a
/// "Thinking…" row (the endpoint deliberately does not stream). The consent wall
/// (403 consent_required) is handled inline; rate limits and outages get honest rows.
struct AskClarionSheet: View {
    @StateObject private var store: AssistantStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    init(auth: SupabaseAuth, snapshotProvider: @escaping () -> String?) {
        _store = StateObject(wrappedValue: AssistantStore(auth: auth, snapshotProvider: snapshotProvider))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.line)
            transcript
        }
        .background(Color.paper.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            if store.needsConsent {
                consentCard
            } else {
                inputBar
            }
        }
    }

    // MARK: - Header (serif title + the exact web disclaimer)

    private var header: some View {
        VStack(alignment: .leading, spacing: Brand.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text("Ask Clarion")
                    .font(.clarionDisplay(22))
                    .tracking(-0.015 * 22)
                    .foregroundStyle(Color.ink)
                Spacer()
                if !store.turns.isEmpty {
                    Button {
                        Haptics.warning()
                        store.clear()
                    } label: {
                        Text("Clear")
                            .font(.clarionLabel(13))
                            .foregroundStyle(Color.ink3)
                    }
                    .buttonStyle(PressableStyle(haptic: false))
                }
                Button {
                    Haptics.tap()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.ink3)
                        .padding(8)
                        .background(Color.surface2, in: Circle())
                        .frame(width: 44, height: 44)   // 44pt hit target
                        .contentShape(Circle())
                }
                .buttonStyle(PressableStyle(haptic: false))
                .accessibilityLabel("Close")
            }
            // Same copy as the web panel (ClarionAssistant.tsx) — the honesty contract.
            Text("For education only—not medical advice. This chat does not cite studies or guidelines line by line; do not treat replies as a literature review. Answers may be incomplete or wrong for your situation—verify with your clinician.")
                .font(.clarionBody(12))
                .foregroundStyle(Color.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Brand.s5)
        .padding(.top, Brand.s5)
        .padding(.bottom, Brand.s3)
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Brand.s3) {
                    if store.turns.isEmpty && !store.thinking {
                        Text("Ask a question about your biomarkers or wellness. I'll explain in plain language and suggest when to talk to your doctor.")
                            .font(.clarionBody(14.5))
                            .foregroundStyle(Color.ink3)
                            .padding(.top, Brand.s4)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Brand.s5)
                    }
                    ForEach(store.turns) { turn in
                        bubble(turn)
                    }
                    if store.thinking {
                        thinkingRow.id("thinking")
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(Brand.s5)
            }
            .onChange(of: store.turns) { _, _ in
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: store.thinking) { _, thinking in
                if thinking {
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    @ViewBuilder
    private func bubble(_ turn: AssistantStore.Turn) -> some View {
        switch turn.role {
        case .user:
            Text(turn.content)
                .font(.clarionBody(15))
                .foregroundStyle(Color.forestInk)
                .padding(.horizontal, Brand.s4)
                .padding(.vertical, Brand.s3)
                .background(Color.forestWash, in: RoundedRectangle(cornerRadius: Brand.rLG))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, Brand.s7)
                .textSelection(.enabled)
        case .assistant:
            Text(turn.content)
                .font(.clarionBody(15))
                .foregroundStyle(Color.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Brand.s4)
                .padding(.vertical, Brand.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clarionCard()
                .padding(.trailing, Brand.s6)
                .textSelection(.enabled)
        case .notice:
            HStack(spacing: Brand.s2) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.clay)
                Text(turn.content)
                    .font(.clarionBody(13))
                    .foregroundStyle(Color.clay)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Brand.s4)
            .padding(.vertical, Brand.s2 + 2)
            .background(Color.clayWash, in: RoundedRectangle(cornerRadius: Brand.rSM))
        }
    }

    private var thinkingRow: some View {
        HStack(spacing: Brand.s2) {
            ProgressView().controlSize(.small)
            Text("Thinking…")
                .font(.clarionBody(14))
                .foregroundStyle(Color.ink3)
        }
        .padding(.horizontal, Brand.s4)
        .padding(.vertical, Brand.s3)
        .clarionCardQuiet()
    }

    // MARK: - Consent wall (403 consent_required)

    private var consentCard: some View {
        VStack(alignment: .leading, spacing: Brand.s3) {
            Eyebrow("AI insights", color: .forest)
            Text("Turn on AI insights to use the assistant")
                .font(.clarionDisplay(17))
                .foregroundStyle(Color.ink)
            Text("Your questions (and, if you choose, a summary of your panel) are processed by an AI service to generate educational answers. You can revoke this any time in settings.")
                .font(.clarionBody(13.5))
                .foregroundStyle(Color.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task { await store.grantConsentAndRetry() }
            } label: {
                if store.grantingConsent {
                    ProgressView().tint(.white).frame(maxWidth: .infinity)
                } else {
                    Text("Turn on AI insights").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(store.grantingConsent)
        }
        .padding(Brand.s4 + 2)
        .clarionCard()
        .padding(.horizontal, Brand.s5)
        .padding(.bottom, Brand.s3)
        .background(Color.paper.opacity(0.95))
    }

    // MARK: - Input bar (pinned bottom)

    private var inputBar: some View {
        HStack(spacing: Brand.s2) {
            TextField("Ask about your results…", text: $draft, axis: .vertical)
                .font(.clarionBody(15))
                .foregroundStyle(Color.ink)
                .lineLimit(1...4)
                .focused($inputFocused)
                .padding(.horizontal, Brand.s4)
                .padding(.vertical, 10)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: Brand.r))
                .overlay(RoundedRectangle(cornerRadius: Brand.r).stroke(Color.line2))
                .disabled(store.thinking)
            Button {
                let text = draft
                draft = ""
                Haptics.commit()
                Task { await store.send(text) }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(
                        LinearGradient(colors: [Color.forestBright, Color.forest], startPoint: .top, endPoint: .bottom),
                        in: Circle()
                    )
                    .frame(width: 44, height: 44)   // 44pt hit target; visual stays 38
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle(haptic: false))
            .disabled(store.thinking || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(store.thinking || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, Brand.s5)
        .padding(.vertical, Brand.s3)
        .background(.bar)
    }
}
