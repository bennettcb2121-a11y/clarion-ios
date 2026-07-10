import SwiftUI

/// The hero readiness ring — vibrant arc, glowing leading tip, fills + counts up on appear.
/// Native rendition of the web dashboard's ring.
struct ReadinessRing: View {
    let score: Int?
    private let size: CGFloat = 190

    @State private var progress: CGFloat = 0
    @State private var shownValue: Int = 0

    private var target: CGFloat { CGFloat(score ?? 0) / 100 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.forestWash, lineWidth: 15)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [Color.forestBright, Color.forest]),
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: 15, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: Color.forest.opacity(0.35), radius: 6, y: 2)

            VStack(spacing: 4) {
                Text(score == nil ? "—" : "\(shownValue)")
                    .font(.system(size: 56, weight: .bold, design: .serif))
                    .monospacedDigit()
                    .foregroundStyle(Color.ink)
                Text("READINESS")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(Color.inkMuted)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.easeOut(duration: 1.1)) { progress = target }
            animateCount()
        }
    }

    private func animateCount() {
        guard let score else { return }
        let steps = 30
        for i in 0...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * (0.95 / Double(steps))) {
                let t = Double(i) / Double(steps)
                shownValue = Int((1 - pow(1 - t, 3)) * Double(score))
            }
        }
    }
}

extension Color {
    static let forest = Color(red: 0.12, green: 0.44, blue: 0.36)
    static let forestBright = Color(red: 0.16, green: 0.55, blue: 0.45)
    static let forestWash = Color(red: 0.84, green: 0.91, blue: 0.88)
    static let forestInk = Color(red: 0.05, green: 0.29, blue: 0.23)
    static let ink = Color(red: 0.09, green: 0.13, blue: 0.11)
    static let inkMuted = Color(red: 0.47, green: 0.51, blue: 0.49)
    static let clay = Color(red: 0.69, green: 0.27, blue: 0.22)
    static let paper = Color(red: 0.94, green: 0.95, blue: 0.94)
}
