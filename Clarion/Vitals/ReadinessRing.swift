import SwiftUI

/// The hero readiness ring — the vitals rendition of the Clarion score dial: paper-dim track,
/// forest-gradient arc with round caps from 12 o'clock, serif count-up numeral, tracked
/// forest micro-label. (Color tokens live in Support/Brand.swift.)
struct ReadinessRing: View {
    let score: Int?
    private let size: CGFloat = 180

    @State private var progress: CGFloat = 0
    @State private var shownValue: Int = 0
    /// Animate the intro ONCE; TabView re-fires `.onAppear` on every return, which otherwise
    /// reset the number to 0 and re-counted — the visible "glitchy reload" on the Vitals tab.
    @State private var didAnimate = false
    @State private var animGen = 0
    /// Ambient breath behind the ring — the one living element on the tab.
    @State private var breathing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var target: CGFloat { CGFloat(score ?? 0) / 100 }

    var body: some View {
        ZStack {
            // A slow soft glow (3.6s in/out) gives the hero quiet life — opacity only,
            // skipped entirely under Reduce Motion and when there's no score yet.
            if score != nil && !reduceMotion {
                Circle()
                    .fill(Color.forest.opacity(breathing ? 0.10 : 0.04))
                    .blur(radius: 18)
                    .padding(6)
                    .animation(.easeInOut(duration: 3.6).repeatForever(autoreverses: true), value: breathing)
                    .onAppear { breathing = true }
                    .allowsHitTesting(false)
            }

            Circle()
                .stroke(Color.paperDim, lineWidth: 11)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(
                        colors: [Color.scoreA, Color.scoreB],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    style: StrokeStyle(lineWidth: 11, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 4) {
                Text(score == nil ? "—" : "\(shownValue)")
                    .font(.clarionDisplay(52))
                    .monospacedDigit()
                    .foregroundStyle(Color.ink)
                Text("READINESS")
                    .font(.clarionLabel(10.5))
                    .tracking(1.8)
                    .foregroundStyle(Color.forest)
            }
        }
        .frame(width: size, height: size)
        .onAppear { guard !didAnimate else { return }; didAnimate = true; animateIn() }
        // Pull-to-refresh changes the score in place; without this the ring kept the OLD
        // number/arc until you left and re-entered the tab.
        .onChange(of: score) { _, _ in animateIn() }
    }

    private func animateIn() {
        animGen &+= 1
        let gen = animGen
        if reduceMotion {
            progress = target
            shownValue = score ?? 0
            return
        }
        progress = 0
        withAnimation(.easeOut(duration: 1.4)) { progress = target }
        guard let score else { shownValue = 0; return }
        let steps = 30
        for i in 0...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * (1.1 / Double(steps))) {
                guard gen == animGen else { return }
                let t = Double(i) / Double(steps)
                shownValue = Int((1 - pow(1 - t, 3)) * Double(score))
            }
        }
    }
}
