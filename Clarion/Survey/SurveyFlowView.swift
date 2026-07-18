import SwiftUI

/// The native Clarion survey — shown full-screen when a signed-in user hasn't completed
/// their profile yet (GET /api/account/profile → null). Reproduces the web survey's
/// questions verbatim in the app's own design language; answers PATCH the same
/// `profiles` columns the web writes, so the dashboard calibrates identically.
struct SurveyFlowView: View {
    @StateObject private var state: SurveyState

    init(auth: SupabaseAuth, onFinished: @escaping () -> Void) {
        _state = StateObject(wrappedValue: SurveyState(auth: auth, onFinished: onFinished))
    }

    var body: some View {
        VStack(spacing: 0) {
            chrome
            ScrollView {
                stepBody
                    .padding(.horizontal, Brand.s5)
                    .padding(.top, Brand.s4)
                    .padding(.bottom, Brand.s7)
                    .frame(maxWidth: .infinity, minHeight: 420, alignment: .topLeading)
                    // One directional slide per step — the web's screen-to-screen entrance.
                    .id(state.step)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color.paper.ignoresSafeArea())
    }

    /// Progress bar + back chevron — question steps only (welcome/saving/done are chromeless).
    private var chrome: some View {
        VStack(spacing: Brand.s2) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.ink.opacity(0.07))
                    Capsule()
                        .fill(Color.forest)
                        .frame(width: max(0, geo.size.width * state.progress))
                        .animation(.spring(response: 0.5, dampingFraction: 0.9), value: state.progress)
                }
            }
            .frame(height: 3)
            .padding(.horizontal, Brand.s5)
            .opacity(state.step == .welcome || state.step == .saving || state.step == .done ? 0 : 1)

            HStack {
                if state.canGoBack {
                    Button {
                        Haptics.tap()
                        state.back()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                            Text("Back").font(.clarionLabel(13))
                        }
                        .foregroundStyle(Color.ink3)
                    }
                    .buttonStyle(PressableStyle())
                }
                Spacer()
            }
            .padding(.horizontal, Brand.s5)
            .frame(height: 28)
        }
        .padding(.top, Brand.s3)
    }

    @ViewBuilder
    private var stepBody: some View {
        switch state.step {
        case .welcome:
            SurveyWelcomeStep { state.advance() }
        case .aboutYou:
            SurveyAboutYouStep(state: state) { state.advance() }
        case .activity:
            SurveyChoiceStep(
                kicker: "Daily activity",
                promptPlain: "How active ", promptEmphasis: "are you?",
                sub: "This helps determine which biomarkers matter most.",
                options: SurveyCatalog.activity, mode: .single,
                selection: singleBinding(\.activityLevel)
            ) { state.advance() }
        case .sleep:
            SurveyChoiceStep(
                kicker: "Sleep",
                promptPlain: "How much do you ", promptEmphasis: "sleep?",
                sub: "A typical night over the last few weeks.",
                options: SurveyCatalog.sleep, mode: .single,
                selection: singleBinding(\.sleepBand)
            ) { state.advance() }
        case .alcohol:
            SurveyChoiceStep(
                kicker: "Alcohol",
                promptPlain: "Do you ", promptEmphasis: "drink?",
                sub: "It affects liver markers, sleep, and recovery.",
                options: SurveyCatalog.alcohol, mode: .single,
                selection: singleBinding(\.alcohol)
            ) { state.advance() }
        case .training:
            SurveyChoiceStep(
                kicker: "Training",
                promptPlain: "Do you train ", promptEmphasis: "for performance?",
                sub: "Optional. If you train for a sport, we adjust target ranges and supplement emphasis — on top of your health goals.",
                options: SurveyCatalog.training, mode: .single,
                selection: Binding(
                    get: { [state.trainingFocus.isEmpty ? SurveyCatalog.trainingFocusNoneId : state.trainingFocus] },
                    set: { state.trainingFocus = $0.first ?? "" }
                )
            ) { state.advance() }
        case .goals:
            SurveyChoiceStep(
                kicker: "Your goals",
                promptPlain: "What are you ", promptEmphasis: "optimizing for?",
                sub: "Pick all that apply — we tailor your panel to every focus you choose.",
                options: SurveyCatalog.goals, mode: .multi,
                selection: $state.goalIds
            ) { state.advance() }
        case .symptoms:
            SurveyChoiceStep(
                kicker: "Symptoms · pick any",
                promptPlain: "Anything ", promptEmphasis: "nagging you?",
                sub: "We'll make sure the right markers are covered.",
                options: SurveyCatalog.symptoms, mode: .multi,
                selection: $state.symptomIds,
                optional: true
            ) { state.advance() }
        case .supplements:
            SurveySupplementsStep(selection: $state.supplementNames) { state.advance() }
        case .spend:
            SurveySpendStep(spend: $state.spend) { state.advance() }
        case .saving:
            SurveySavingStep(state: state)
        case .done:
            SurveyDoneStep { state.finish() }
        }
    }

    /// Single-select steps store one id; the choice component works in arrays.
    private func singleBinding(_ keyPath: ReferenceWritableKeyPath<SurveyState, String>) -> Binding<[String]> {
        Binding(
            get: { state[keyPath: keyPath].isEmpty ? [] : [state[keyPath: keyPath]] },
            set: { state[keyPath: keyPath] = $0.first ?? "" }
        )
    }
}
