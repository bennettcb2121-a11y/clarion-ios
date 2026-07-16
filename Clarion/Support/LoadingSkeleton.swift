import SwiftUI

/// A soft highlight sweep for skeleton placeholders. Uses ink-toned bands so it reads in both
/// light and dark, and animates with a repeating offset (no timers).
private struct Shimmer: ViewModifier {
    @State private var x: CGFloat = -1
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, Color.ink.opacity(0.07), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: geo.size.width)
                    .offset(x: x * geo.size.width)
                    .animation(.linear(duration: 1.3).repeatForever(autoreverses: false), value: x)
                }
            )
            .onAppear { x = 1 }
    }
}

private extension View {
    func shimmering() -> some View { modifier(Shimmer()) }
}

/// The standard "content is loading" placeholder — a shimmering skeleton in the app's own card
/// shapes, so a slow network reads as an intentional loading state instead of a bare spinner
/// floating on an empty screen. Shared by Report, Plan, Shop, and Vitals.
struct ClarionLoadingView: View {
    /// The skeleton card heights, top to bottom — a tall lead card then a couple of rows,
    /// echoing the real screens' rhythm.
    var blocks: [CGFloat] = [138, 96, 96, 60]

    var body: some View {
        VStack(spacing: Brand.s4) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, h in
                skeleton(height: h)
            }
            Spacer(minLength: 0)
        }
        .padding(Brand.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement()
        .accessibilityLabel("Loading")
    }

    private func skeleton(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: Brand.r, style: .continuous)
            .fill(Color.ink.opacity(0.06))
            .frame(height: height)
            .shimmering()
            .clipShape(RoundedRectangle(cornerRadius: Brand.r, style: .continuous))
    }
}
