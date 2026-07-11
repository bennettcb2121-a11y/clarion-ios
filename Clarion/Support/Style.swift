import SwiftUI

// MARK: - Press physics

/// Premium press feel: the control compresses under the finger (scale + slight dim) with a
/// spring release, and fires a light haptic on press. Apply to every tappable surface.
struct PressableStyle: ButtonStyle {
    var haptic: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.65), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed && haptic { Haptics.tap() }
            }
    }
}

/// Primary CTA — ds.css `.btn--primary`: vertical forest gradient with an inset top highlight,
/// Jakarta 600, radius 14, press = down 1pt + scale .99.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ui(15, weight: 600))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(colors: [Color.forestBright, Color.forest], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: Brand.r)
            )
            .overlay(
                // The web's `inset 0 1px 0 rgba(255,255,255,.18)` top highlight.
                RoundedRectangle(cornerRadius: Brand.r)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.18), .clear],
                            startPoint: .top, endPoint: .center
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.forest.opacity(configuration.isPressed ? 0.12 : 0.28), radius: configuration.isPressed ? 3 : 9, y: configuration.isPressed ? 1 : 4)
            .offset(y: configuration.isPressed ? 1 : 0)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptics.commit() }
            }
    }
}

/// Secondary button — ds.css `.btn--secondary`: surface bg, ink text, hairline border.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ui(15, weight: 600))
            .foregroundStyle(Color.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: Brand.r))
            .overlay(RoundedRectangle(cornerRadius: Brand.r).stroke(Color.line2))
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptics.tap() }
            }
    }
}

// MARK: - Entrance motion

/// Staggered card entrance: fade + rise (the web's `[data-reveal]` land), delayed per index.
struct EntranceModifier: ViewModifier {
    let index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .onAppear {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.82).delay(Double(index) * 0.06)) {
                    shown = true
                }
            }
    }
}

// MARK: - Chrome

extension View {
    /// Staggered entrance by position (0-based).
    func entrance(_ index: Int) -> some View { modifier(EntranceModifier(index: index)) }

    /// The app's standard card — ds.css `.card`: surface bg, hairline `--line` border,
    /// radius 18, `--e1` shadow.
    func clarionCard(cornerRadius: CGFloat = Brand.rLG) -> some View {
        self
            .background(Color.surface, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(Color.line))
            .shadow(color: Color.ink.opacity(0.05), radius: 2, y: 1)
    }

    /// Quiet card variant — surface-2, no shadow (ds.css `.card--quiet`).
    func clarionCardQuiet(cornerRadius: CGFloat = Brand.rLG) -> some View {
        self
            .background(Color.surface2, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(Color.line))
    }
}

/// Tracked-caps eyebrow label — ds.css `.t-label`: Jakarta 600 11.5, 0.14em tracking, uppercase.
struct Eyebrow: View {
    let text: String
    var color: Color = .ink3

    init(_ text: String, color: Color = .ink3) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.ui(11.5, weight: 600))
            .tracking(1.6)
            .foregroundStyle(color)
    }
}

/// Status tag — ds.css `.tag`: pill with a leading 6px dot, Jakarta 600 11, tracked uppercase.
/// Rationed: forest = optimal/need, amber = watch/maintain, clay = low/flag.
struct TagPill: View {
    let text: String
    let tone: Color
    let wash: Color

    init(_ text: String, tone: Color, wash: Color) {
        self.text = text
        self.tone = tone
        self.wash = wash
    }

    /// Semantic tag for a biomarker status string.
    init(status: String, label: String) {
        self.init(label, tone: Color.tone(for: status), wash: Color.toneWash(for: status))
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(tone).frame(width: 6, height: 6)
            Text(text.uppercased())
                .font(.ui(11, weight: 600))
                .tracking(0.9)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(wash, in: Capsule())
        .foregroundStyle(tone)
    }
}

/// The Clarion Labs wordmark lockup: serif name over the lowercase tracked tagline.
struct Wordmark: View {
    var nameSize: CGFloat = 19
    var centered: Bool = false

    var body: some View {
        VStack(alignment: centered ? .center : .leading, spacing: 3) {
            Text("Clarion Labs")
                .font(.display(nameSize, weight: 700))
                .tracking(-0.03 * nameSize)
                .foregroundStyle(Color.ink)
            Text("brilliantly clear")
                .font(.bodyFace(nameSize * 0.55, weight: 500))
                .tracking(0.12 * nameSize * 0.55)
                .textCase(.lowercase)
                .foregroundStyle(Color.ink3)
        }
    }
}
