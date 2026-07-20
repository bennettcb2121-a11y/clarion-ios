import SwiftUI

/// The delivery form a plan row actually represents — inferred from the dose FIRST
/// (the thing the user takes; same conflict rule as StackItem.coherentName), then the
/// name, defaulting to capsule. Drives the little vessel glyph on Plan rows.
enum SupplementForm {
    case capsule, tablet, gummy, liquid, powder

    static func infer(name: String, dose: String) -> SupplementForm {
        if let f = detect(in: dose) { return f }
        if let f = detect(in: name) { return f }
        return .capsule
    }

    private static func detect(in text: String) -> SupplementForm? {
        let t = text.lowercased()
        if t.contains("gumm") { return .gummy }
        if t.contains("tbsp") || t.contains("tsp") || t.contains(" ml") || t.contains("liquid")
            || t.contains("dropper") || t.contains("drop") { return .liquid }
        if t.contains("scoop") || t.contains("powder") { return .powder }
        if t.contains("tablet") || t.contains("caplet") { return .tablet }
        if t.contains("capsule") || t.contains("caps") || t.contains("softgel") { return .capsule }
        return nil
    }
}

/// A small hand-drawn vessel chip for a plan row: capsule, tablet, gumdrop, dropper
/// bottle, or scoop — drawn with shapes (no generic SF symbol pills). Done rows warm up:
/// the chip takes the forest wash and the glyph goes forest.
struct SupplementGlyph: View {
    let form: SupplementForm
    var done: Bool = false

    private var tone: Color { done ? Color.forest : Color.forestInk.opacity(0.85) }

    var body: some View {
        ZStack {
            switch form {
            case .capsule: capsule
            case .tablet: tablet
            case .gummy: gummy
            case .liquid: liquid
            case .powder: powder
            }
        }
        .frame(width: 30, height: 30)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(done ? Color.forestWash : Color.ink.opacity(0.045))
        )
        .animation(.easeOut(duration: 0.2), value: done)
        .accessibilityHidden(true)
    }

    /// Two-tone pill at a jaunty angle.
    private var capsule: some View {
        ZStack {
            Capsule().fill(tone.opacity(0.22))
            HStack(spacing: 0) {
                Rectangle().fill(tone)
                Color.clear
            }
            .clipShape(Capsule())
            Capsule().stroke(tone, lineWidth: 1.1)
        }
        .frame(width: 15.5, height: 8)
        .rotationEffect(.degrees(-32))
    }

    /// Scored disc.
    private var tablet: some View {
        ZStack {
            Circle().fill(tone.opacity(0.2))
            Circle().stroke(tone, lineWidth: 1.2)
            Rectangle().fill(tone).frame(width: 8.5, height: 1.1)
        }
        .frame(width: 13, height: 13)
    }

    /// Gumdrop with sugar dots.
    private var gummy: some View {
        ZStack {
            UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: 7.5, bottomLeading: 2.5, bottomTrailing: 2.5, topTrailing: 7.5)
            )
            .fill(tone.opacity(0.24))
            UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: 7.5, bottomLeading: 2.5, bottomTrailing: 2.5, topTrailing: 7.5)
            )
            .stroke(tone, lineWidth: 1.1)
            HStack(spacing: 2.5) {
                Circle().fill(tone).frame(width: 1.4, height: 1.4)
                Circle().fill(tone).frame(width: 1.4, height: 1.4)
                Circle().fill(tone).frame(width: 1.4, height: 1.4)
            }
            .offset(y: 1.5)
        }
        .frame(width: 14, height: 12.5)
    }

    /// Dropper bottle with a liquid level.
    private var liquid: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 1.4).fill(tone).frame(width: 7, height: 3).offset(y: -8)
            RoundedRectangle(cornerRadius: 3.4).stroke(tone, lineWidth: 1.1).frame(width: 11.5, height: 13).offset(y: 1)
            RoundedRectangle(cornerRadius: 2.2).fill(tone.opacity(0.3)).frame(width: 8.8, height: 6).offset(y: 3.8)
        }
    }

    /// Scoop resting in a mound.
    private var powder: some View {
        ZStack {
            UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: 2, bottomLeading: 6.5, bottomTrailing: 6.5, topTrailing: 2)
            )
            .fill(tone.opacity(0.22))
            .frame(width: 12, height: 7.5)
            .offset(x: -2, y: 2.5)
            UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: 2, bottomLeading: 6.5, bottomTrailing: 6.5, topTrailing: 2)
            )
            .stroke(tone, lineWidth: 1.1)
            .frame(width: 12, height: 7.5)
            .offset(x: -2, y: 2.5)
            Capsule().fill(tone).frame(width: 7, height: 1.6).offset(x: 6, y: -1.4)
            Circle().fill(tone).frame(width: 1.4, height: 1.4).offset(x: -4, y: -4)
            Circle().fill(tone).frame(width: 1.2, height: 1.2).offset(x: 0.5, y: -5.5)
        }
    }
}
