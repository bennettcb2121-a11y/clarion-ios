import SwiftUI

// MARK: - Shared survey typography (Direction A: Fraunces speaks, Inter reads)

/// "THE CLARION SURVEY" — tracked-caps kicker above every prompt.
struct SurveyKicker: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.clarionLabel(11.5))
            .tracking(0.14 * 11.5)
            .foregroundStyle(Color.ink3)
    }
}

/// The big Fraunces prompt with an italic emphasis phrase — "How active *are you?*".
struct SurveyPrompt: View {
    let plain: String
    let emphasis: String
    var size: CGFloat = 30

    var body: some View {
        (Text(plain).font(.clarionDisplay(size))
         + Text(emphasis).font(.clarionDisplayItalic(size)).foregroundStyle(Color.forest))
            .tracking(-0.02 * size)
            .foregroundStyle(Color.ink)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SurveySub: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.clarionBody(14.5))
            .foregroundStyle(Color.ink2)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Choice option card (single + multi)

struct SurveyOptionCard: View {
    let label: String
    var description: String? = nil
    let selected: Bool
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Brand.s3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.clarionDisplay(compact ? 15.5 : 17))
                        .tracking(-0.015 * 17)
                        .foregroundStyle(Color.ink)
                        .multilineTextAlignment(.leading)
                    if let description {
                        Text(description)
                            .font(.clarionBody(12.5))
                            .foregroundStyle(Color.ink3)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(selected ? Color.forest : Color.ink4.opacity(0.5))
            }
            .padding(.horizontal, Brand.s4)
            .padding(.vertical, compact ? Brand.s3 : Brand.s3 + 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Brand.r, style: .continuous)
                    .fill(selected ? Color.forestWash : Color.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Brand.r, style: .continuous)
                    .stroke(selected ? Color.forest.opacity(0.5) : Color.line, lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Single/multi choice screens (the web's SurveyChoiceScreen)

struct SurveyChoiceStep: View {
    let kicker: String
    let promptPlain: String
    let promptEmphasis: String
    var sub: String? = nil
    let options: [SurveyCatalog.Option]
    let mode: Mode
    @Binding var selection: [String]
    var optional = false
    let onAdvance: () -> Void

    enum Mode { case single, multi }
    @State private var advancing = false

    private var compact: Bool { options.count > 4 }

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.s5) {
            VStack(alignment: .leading, spacing: Brand.s2 + 2) {
                SurveyKicker(kicker)
                SurveyPrompt(plain: promptPlain, emphasis: promptEmphasis)
                if let sub { SurveySub(sub) }
            }

            VStack(spacing: Brand.s2 + 2) {
                ForEach(options) { opt in
                    SurveyOptionCard(
                        label: opt.label,
                        description: opt.description,
                        selected: selection.contains(opt.id),
                        compact: compact
                    ) { pick(opt.id) }
                }
            }

            if mode == .multi {
                Button {
                    Haptics.commit()
                    onAdvance()
                } label: {
                    Text(selection.isEmpty && optional ? "Skip" : "Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(selection.isEmpty && !optional)
                .opacity(selection.isEmpty && !optional ? 0.4 : 1)
            }
        }
    }

    private func pick(_ id: String) {
        switch mode {
        case .single:
            guard !advancing else { return }
            selection = [id]
            Haptics.selection()
            // One tap is a complete answer — glide on after the selection visibly lands
            // (the web's 340ms beat). Multi waits for an explicit Continue.
            advancing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
                advancing = false
                onAdvance()
            }
        case .multi:
            Haptics.selection()
            if let i = selection.firstIndex(of: id) { selection.remove(at: i) }
            else { selection.append(id) }
        }
    }
}
