import SwiftUI
import UIKit

// =============================================================================
// Generated from bloodwise-frontend/design/clarion-tokens.json — keep in sync.
// =============================================================================
//
// Clarion Design Language — Direction A ("Editorial Instrument"), iOS twin.
// The rule: the serif speaks (brand voice), SF Pro reads (instrument voice),
// SF Mono appears only as report document metadata. Every content class gets
// exactly ONE voice:
//
//   display  — New York serif 600 (maps the web's Fraunces role).
//              Headlines, product names, hero numbers (score, readiness).
//   data     — SF Pro 600 + monospacedDigit(). EVERY working numeral:
//              values, ranges, doses, prices, counts, dates.
//   body     — SF Pro 400. Paragraphs, explanations.
//   label    — SF Pro 600, tracked caps at 0.14em. Eyebrows, buttons, chips.
//   docmono  — SF Mono. The report "issued" metadata line ONLY.
//
// Semantics: optimal/need = forest, maintain/watch = amber, flagged/low = clay.
// Score tiers, chart accents and deltas NEVER leave those three families.

// MARK: - Shape & spacing tokens

enum Brand {

    // Radii (tokens.shape.radii)
    static let rXS: CGFloat = 6
    static let rSM: CGFloat = 10
    static let r: CGFloat = 14      // md
    static let rLG: CGFloat = 18    // the card radius
    static let rXL: CGFloat = 24

    // Spacing (tokens.spacing.scale4pt)
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 20
    static let s6: CGFloat = 24
    static let s7: CGFloat = 32
    static let s8: CGFloat = 48
}

// MARK: - Color tokens (tokens.color.light / tokens.color.dark)

extension Color {

    /// Dynamic light/dark color from two hex values (0xRRGGBB) with optional alphas,
    /// keyed on userInterfaceStyle.
    private static func dynamic(_ light: UInt32, _ dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkAlpha)
                : UIColor(hex: light, alpha: lightAlpha)
        })
    }

    // Surfaces — warm paper world, slightly green-tinted, never pure white/gray canvas.
    static let paper = dynamic(0xEFF3F0, 0x0F1614)
    static let paperDim = dynamic(0xE6ECE8, 0x0B100E)
    static let surface = dynamic(0xFFFFFF, 0x15201C)
    static let surface2 = dynamic(0xF6F9F7, 0x131D19)

    // Ink — green-black, never pure black. Dark ink2–4 are alpha'd per the spec.
    static let ink = dynamic(0x16201C, 0xF3F6F4)
    static let ink2 = dynamic(0x46514C, 0xF3F6F4, darkAlpha: 0.74)
    static let ink3 = dynamic(0x79827D, 0xF3F6F4, darkAlpha: 0.50)
    static let ink4 = dynamic(0xA2A9A4, 0xF3F6F4, darkAlpha: 0.32)
    /// Legacy alias — older views use `inkMuted` for captions/secondary.
    static let inkMuted = ink3

    // Hairlines (derived from ink/white — the card recipe's "1px line border").
    static let line = dynamic(0x16201C, 0xFFFFFF, lightAlpha: 0.09, darkAlpha: 0.08)
    static let line2 = dynamic(0x16201C, 0xFFFFFF, lightAlpha: 0.16, darkAlpha: 0.14)
    static let lineStrong = dynamic(0x16201C, 0xFFFFFF, lightAlpha: 0.24, darkAlpha: 0.22)

    /// The e1 card shadow — always shadow-colored, never ink (ink flips light in
    /// dark mode and would glow). Dark cards read via border + lighter surface.
    static let shadowE1 = dynamic(0x16201C, 0x000000, lightAlpha: 0.05, darkAlpha: 0.35)

    // Forest green family — the brand.
    static let forest = dynamic(0x1F6F5B, 0x2A8C72)
    static let forestDeep = dynamic(0x18584A, 0x1F6F5B)
    static let forestBright = dynamic(0x2A8C72, 0x36A98A)
    static let forestInk = dynamic(0x0E4A3B, 0x8FE3C9)
    static let forestWash = dynamic(0xE6F0EB, 0x1F6F5B, darkAlpha: 0.16)

    // Amber — maintain / watch. Meaning only, never decoration.
    static let amber = dynamic(0x9A6B2E, 0xC4A060)
    static let amberSoft = dynamic(0xCF8F49, 0xD9A968)
    static let amberWash = dynamic(0xF4ECDC, 0xC4A060, darkAlpha: 0.14)

    // Clay — flagged / low. Meaning only, never decoration.
    static let clay = dynamic(0xB0443A, 0xC75C5C)
    static let claySoft = dynamic(0xC97A6E, 0xD98B84)
    static let clayWash = dynamic(0xF6E4E1, 0xC75C5C, darkAlpha: 0.14)

    // Score dial ring gradient stops.
    static let scoreA = dynamic(0x2A8C72, 0x36A98A)
    static let scoreB = dynamic(0x1F6F5B, 0x2A8C72)

    /// Semantic tone for a biomarker/metric status string — forest/amber/clay only.
    static func tone(for status: String) -> Color {
        switch status.lowercased() {
        case "optimal", "normal", "in range": return .forest
        case "deficient", "low": return .clay
        case "high", "suboptimal": return .amber
        default: return .ink3
        }
    }

    /// Wash (background) matching `tone(for:)`.
    static func toneWash(for status: String) -> Color {
        switch status.lowercased() {
        case "optimal", "normal", "in range": return .forestWash
        case "deficient", "low": return .clayWash
        case "high", "suboptimal": return .amberWash
        default: return .paperDim
        }
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

// MARK: - Type roles (tokens.type)

extension Font {

    /// Display — bundled Fraunces SemiBold (the web's display serif, exact parity),
    /// falling back to the system serif if the face failed to register. Screen titles,
    /// product/marker names, hero numbers. Tracking ~-0.015em on large sizes.
    static func clarionDisplay(_ size: CGFloat) -> Font {
        Font(Fonts.display(size))
    }

    /// Display italic — the web softens phrases with `em`; one coaching sentence per screen, max.
    static func clarionDisplayItalic(_ size: CGFloat) -> Font {
        Font(Fonts.display(size, italic: true))
    }

    /// Data — SF Pro 600 with monospaced digits. EVERY working numeral: values,
    /// ranges, doses, prices, counts, dates. Never a full monospace face.
    static func clarionData(_ size: CGFloat) -> Font {
        Font.system(size: size, weight: .semibold).monospacedDigit()
    }

    /// Body — SF Pro 400. Paragraphs, explanations, captions.
    static func clarionBody(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular)
    }

    /// Label — SF Pro 600. Buttons as-is; eyebrows/chips add tracked caps
    /// (`.tracking(0.14 * size)` + uppercase — see `Eyebrow`/`TagPill`).
    static func clarionLabel(_ size: CGFloat = 11.5) -> Font {
        .system(size: size, weight: .semibold)
    }

    /// Doc mono — SF Mono, sanctioned ONLY for the report "ID · issued" metadata line.
    /// Working numerals never use this; they use `.clarionData`.
    static func clarionDocMono(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .monospaced)
    }
}

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

/// Primary CTA — the web's `.btn--primary`: vertical forest gradient with an inset top
/// highlight, label 600, radius 14, press = down 1pt + scale .99.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.clarionLabel(15))
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

/// Secondary button — the web's `.btn--secondary`: surface bg, ink text, hairline border.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.clarionLabel(15))
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

    /// THE card recipe (tokens.shape.cardRecipe): surface bg + 1px line border + e1 shadow
    /// + r-lg (18) radius. One recipe for every card; tier is expressed by badge, never by
    /// a different card style. Dark mode reads via border + lighter surface (shadow goes black).
    func clarionCard(cornerRadius: CGFloat = Brand.rLG) -> some View {
        self
            .background(Color.surface, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(Color.line))
            .shadow(color: Color.shadowE1, radius: 2, y: 1)
    }

    /// Quiet card variant — surface-2, no shadow (the web's `.card--quiet`).
    func clarionCardQuiet(cornerRadius: CGFloat = Brand.rLG) -> some View {
        self
            .background(Color.surface2, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(Color.line))
    }
}

/// Tracked-caps eyebrow — the label role at spec size: 11.5, 0.14em tracking, uppercase.
struct Eyebrow: View {
    let text: String
    var color: Color = .ink3

    init(_ text: String, color: Color = .ink3) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.clarionLabel(11.5))
            .tracking(0.14 * 11.5)
            .foregroundStyle(color)
    }
}

/// Status tag — the web's `.tag`: pill with a leading 6px dot, label 11, tracked uppercase.
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
                .font(.clarionLabel(11))
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
                .font(.clarionDisplay(nameSize))
                .tracking(-0.015 * nameSize)
                .foregroundStyle(Color.ink)
            Text("brilliantly clear")
                .font(.clarionBody(nameSize * 0.55))
                .tracking(0.12 * nameSize * 0.55)
                .textCase(.lowercase)
                .foregroundStyle(Color.ink3)
        }
    }
}
