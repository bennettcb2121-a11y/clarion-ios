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

/// Primary CTA: forest fill, white text, press physics, medium haptic.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                LinearGradient(colors: [Color.forestBright, Color.forest], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 15)
            )
            .shadow(color: Color.forest.opacity(configuration.isPressed ? 0.15 : 0.35), radius: configuration.isPressed ? 4 : 10, y: configuration.isPressed ? 1 : 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptics.commit() }
            }
    }
}

// MARK: - Entrance motion

/// Staggered card entrance: fade + rise, delayed per index. Gives lists a composed,
/// intentional arrival instead of popping in all at once.
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

extension View {
    /// Staggered entrance by position (0-based).
    func entrance(_ index: Int) -> some View { modifier(EntranceModifier(index: index)) }

    /// The app's standard card chrome.
    func clarionCard(cornerRadius: CGFloat = 18) -> some View {
        self
            .background(Color.white, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(Color.black.opacity(0.05)))
            .shadow(color: Color.black.opacity(0.04), radius: 10, y: 3)
    }
}
