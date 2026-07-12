import SwiftUI

// MARK: - Score dial

/// The hero number — ds.css `.dial`. A 9pt ring: paper-dim track, forest-gradient meter with
/// round caps starting at 12 o'clock, animating in over ~1.4s. Center: serif 700 number with
/// a mono "/100" tail and a tracked forest micro-label beneath.
struct ScoreDial: View {
    let score: Int?
    var label: String = "Health score"
    var size: CGFloat = 148

    @State private var progress: CGFloat = 0
    @State private var shownValue: Int = 0

    private var target: CGFloat { CGFloat(score ?? 0) / 100 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.paperDim, lineWidth: 9)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(
                        colors: [Color.scoreA, Color.scoreB],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(score == nil ? "—" : "\(shownValue)")
                        .font(.clarionDisplay(size * 0.28))
                        .foregroundStyle(Color.ink)
                        .monospacedDigit()
                    Text("/100")
                        .font(.clarionData(size * 0.095))
                        .foregroundStyle(Color.ink3)
                }
                Text(label.uppercased())
                    .font(.clarionLabel(size * 0.072))
                    .tracking(1.2)
                    .foregroundStyle(Color.forest)
            }
        }
        .frame(width: size, height: size)
        .onAppear { animateIn() }
        .onChange(of: score) { _, _ in animateIn() }
    }

    private func animateIn() {
        progress = 0
        withAnimation(.easeOut(duration: 1.4)) { progress = target }
        guard let score else { shownValue = 0; return }
        let steps = 36
        for i in 0...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * (1.2 / Double(steps))) {
                let t = Double(i) / Double(steps)
                shownValue = Int((1 - pow(1 - t, 3)) * Double(score))
            }
        }
    }
}

// MARK: - Honest range bar

/// THE signature Clarion instrument — the web's dual-range bar (`.dr` / `.range`). Shows your
/// value against Clarion's personal optimal band AND what a lab slip would call "normal", so
/// "lab-normal but off for your goal" is visible instead of asserted.
///
///  - track: paper-dim pill
///  - optimal band: forest gradient (clay gradient when the row is flagged)
///  - lab-normal range: thin hairline bar underneath, with end ticks
///  - your value: 16pt white dot, 2.5pt border in the status tone
///  - mono scale labels
struct HonestRangeBar: View {
    let value: Double
    let optimalMin: Double?
    let optimalMax: Double?
    var labNormalMin: Double? = nil
    var labNormalMax: Double? = nil
    let status: String

    private var tone: Color { Color.tone(for: status) }
    private var isFlagged: Bool {
        ["deficient", "low", "high", "suboptimal"].contains(status.lowercased())
    }

    /// Visible axis: spans everything we must show, padded so out-of-band values breathe.
    private var axis: (lo: Double, hi: Double)? {
        guard let bandLo = optimalMin ?? labNormalMin, let bandHi = optimalMax ?? labNormalMax, bandHi > bandLo else { return nil }
        var lo = min(bandLo, value)
        var hi = max(bandHi, value)
        if let l = labNormalMin { lo = min(lo, l) }
        if let h = labNormalMax { hi = max(hi, h) }
        let pad = (hi - lo) * 0.12
        return (lo - pad, hi + pad)
    }

    private func x(_ v: Double, in width: CGFloat, axis: (lo: Double, hi: Double)) -> CGFloat {
        let t = (v - axis.lo) / (axis.hi - axis.lo)
        return width * CGFloat(min(1, max(0, t)))
    }

    var body: some View {
        if let axis {
            VStack(alignment: .leading, spacing: 5) {
                GeometryReader { geo in
                    let w = geo.size.width
                    ZStack(alignment: .leading) {
                        // Track.
                        Capsule().fill(Color.paperDim).frame(height: 8)

                        // Clarion optimal band.
                        if let lo = optimalMin, let hi = optimalMax, hi > lo {
                            let x0 = x(lo, in: w, axis: axis)
                            let x1 = x(hi, in: w, axis: axis)
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        // Spec charts.flagged: clay → claySoft gradient tail.
                                        colors: isFlagged && !(value >= lo && value <= hi)
                                            ? [Color.clay, Color.claySoft]
                                            : [Color.forestBright, Color.forest],
                                        startPoint: .leading, endPoint: .trailing
                                    )
                                )
                                .frame(width: max(6, x1 - x0), height: 8)
                                .offset(x: x0)
                        }

                        // Your value — white dot, tone border.
                        Circle()
                            .fill(Color.surface)
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(tone, lineWidth: 2.5))
                            .offset(x: x(value, in: w, axis: axis) - 8)
                            .shadow(color: Color.black.opacity(0.15), radius: 2, y: 1)
                    }
                    .frame(height: 16)

                    // Lab-normal reference: hairline bar with end ticks, under the track.
                    if let lLo = labNormalMin, let lHi = labNormalMax, lHi > lLo {
                        let x0 = x(lLo, in: w, axis: axis)
                        let x1 = x(lHi, in: w, axis: axis)
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.lineStrong)
                                .frame(width: max(2, x1 - x0), height: 1.5)
                                .offset(x: x0)
                            Rectangle().fill(Color.lineStrong).frame(width: 1.5, height: 5).offset(x: x0)
                            Rectangle().fill(Color.lineStrong).frame(width: 1.5, height: 5).offset(x: x1 - 1.5)
                        }
                        .frame(height: 5)
                        .offset(y: 21)
                    }
                }
                .frame(height: labNormalMin != nil ? 27 : 16)

                // Mono scale: Clarion band bounds (+ lab range caption when it differs).
                HStack {
                    if let lo = optimalMin { scaleLabel(lo) }
                    Spacer()
                    Text("your target")
                        .font(.clarionLabel(9.5))
                        .tracking(1)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.forest.opacity(0.75))
                    Spacer()
                    if let hi = optimalMax { scaleLabel(hi) }
                }
                if let lLo = labNormalMin, let lHi = labNormalMax,
                   lLo != optimalMin || lHi != optimalMax {
                    Text("lab calls \(fmt(lLo))–\(fmt(lHi)) “normal”")
                        .font(.clarionData(10))
                        .foregroundStyle(Color.ink3)
                }
            }
        }
    }

    private func scaleLabel(_ v: Double) -> some View {
        Text(fmt(v))
            .font(.clarionData(10.5))
            .foregroundStyle(Color.ink3)
    }

    private func fmt(_ v: Double) -> String {
        let a = abs(v)
        if a >= 100 { return String(Int(v.rounded())) }
        if v == v.rounded() { return String(Int(v)) }
        return a >= 10 ? String(format: "%.1f", v) : String(format: "%.2f", v).replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
    }
}

// MARK: - Money bar

/// The three-bucket money story — a segmented pill bar: need (forest) / maintain (amber) /
/// skip (paper-dim), 3pt gaps, with mono dollar figures. "$X/mo · $Y backed by your blood."
struct MoneyBar: View {
    let need: Double
    let maintain: Double
    let skip: Double

    private var total: Double { max(need + maintain + skip, 0.01) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width - 6 // two 3pt gaps
            HStack(spacing: 3) {
                if need > 0 {
                    Capsule().fill(
                        LinearGradient(colors: [Color.forestBright, Color.forest], startPoint: .leading, endPoint: .trailing)
                    ).frame(width: max(10, w * need / total))
                }
                if maintain > 0 {
                    Capsule().fill(Color.amber.opacity(0.75)).frame(width: max(10, w * maintain / total))
                }
                if skip > 0 {
                    Capsule().fill(Color.paperDim).frame(maxWidth: .infinity)
                }
            }
        }
        .frame(height: 12)
    }
}
