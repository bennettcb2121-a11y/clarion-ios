import SwiftUI

/// The hero readiness ring — the vitals rendition of the Clarion score dial: paper-dim track,
/// forest-gradient arc with round caps from 12 o'clock, serif count-up numeral, tracked
/// forest micro-label. (Color tokens live in Support/Brand.swift.)
struct ReadinessRing: View {
    let score: Int?
    private let size: CGFloat = 180

    @State private var progress: CGFloat = 0
    @State private var shownValue: Int = 0

    private var target: CGFloat { CGFloat(score ?? 0) / 100 }

    var body: some View {
        ZStack {
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
        .onAppear {
            withAnimation(.easeOut(duration: 1.4)) { progress = target }
            animateCount()
        }
    }

    private func animateCount() {
        guard let score else { return }
        let steps = 30
        for i in 0...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * (1.1 / Double(steps))) {
                let t = Double(i) / Double(steps)
                shownValue = Int((1 - pow(1 - t, 3)) * Double(score))
            }
        }
    }
}
