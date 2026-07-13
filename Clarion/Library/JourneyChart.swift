import SwiftUI

// =============================================================================
// The marker-journey line — band-free, honest gaps.
//
// Y math ports the web spark (src/lib/labsHandoffSpark.ts buildSparkPath):
// padding 12, min/max normalized, flat lines centered. X deliberately goes
// FURTHER than the web: points sit at their real elapsed-time positions, so a
// nine-month gap between draws reads wider than a two-week one (honest gaps).
// Falls back to even spacing when a timestamp won't parse.
// =============================================================================

struct SparkCoord {
    var x: CGFloat        // 0…width
    var y: CGFloat        // 0…height (inverted — larger value = higher = smaller y)
    var value: Double
    var dateLabel: String
}

enum JourneySpark {

    /// Unit x positions (0…1) proportional to elapsed time between draws.
    static func xFractions(_ points: [LabJourneyPoint]) -> [Double] {
        guard points.count > 1 else { return points.isEmpty ? [] : [0] }
        let times = points.map { VictoryCard.parseTimestamp($0.dateIso)?.timeIntervalSince1970 }
        if let t0 = times.first ?? nil, let tN = times.last ?? nil,
           tN > t0, times.allSatisfy({ $0 != nil }) {
            return times.map { (($0! - t0) / (tN - t0)) }
        }
        // Honest fallback: even spacing when dates are unparseable/identical.
        return (0..<points.count).map { Double($0) / Double(points.count - 1) }
    }

    /// Per-point pixel coordinates — same y mapping as the web's buildSparkPath.
    static func coords(
        _ points: [LabJourneyPoint],
        width: CGFloat,
        height: CGFloat,
        padding: CGFloat = 12
    ) -> [SparkCoord] {
        guard !points.isEmpty else { return [] }
        let values = points.map(\.value)
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 0
        let span = maxV - minV
        let flat = span < 1e-9
        let innerH = height - padding * 2
        let xs = xFractions(points)
        return points.enumerated().map { i, p in
            let x = width * CGFloat(xs.indices.contains(i) ? xs[i] : 0)
            let y = flat
                ? padding + innerH / 2
                : padding + innerH - CGFloat((p.value - minV) / span) * innerH
            return SparkCoord(x: x, y: y, value: p.value, dateLabel: p.dateLabel)
        }
    }

    static func linePath(_ coords: [SparkCoord]) -> Path {
        var path = Path()
        guard coords.count >= 2 else { return path }
        path.move(to: CGPoint(x: coords[0].x, y: coords[0].y))
        for c in coords.dropFirst() { path.addLine(to: CGPoint(x: c.x, y: c.y)) }
        return path
    }

    static func areaPath(_ coords: [SparkCoord], height: CGFloat) -> Path {
        var path = linePath(coords)
        guard coords.count >= 2, let last = coords.last, let first = coords.first else { return Path() }
        path.addLine(to: CGPoint(x: last.x, y: height))
        path.addLine(to: CGPoint(x: first.x, y: height))
        path.closeSubpath()
        return path
    }
}

/// The featured journey chart with the web's scrub behavior: drag anywhere to
/// read each draw (tooltip exists only while scrubbing — never pinned open);
/// at rest a quiet end-dot marks the latest value.
struct JourneyChart: View {
    let journey: LabJourney
    var height: CGFloat = 160

    @State private var scrubIdx: Int? = nil

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let coords = JourneySpark.coords(journey.points, width: w, height: height)

            ZStack(alignment: .topLeading) {
                // Two quiet dashed gridlines (the web's 40/110-of-160 fractions).
                ForEach([40.0 / 160.0, 110.0 / 160.0], id: \.self) { frac in
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: height * frac))
                        p.addLine(to: CGPoint(x: w, y: height * frac))
                    }
                    .stroke(Color.line.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
                }

                if coords.count >= 2 {
                    JourneySpark.areaPath(coords, height: height)
                        .fill(
                            LinearGradient(
                                colors: [Color.forest.opacity(0.18), Color.forest.opacity(0)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                    JourneySpark.linePath(coords)
                        .stroke(Color.forest, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }

                if let idx = scrubIdx, coords.indices.contains(idx) {
                    scrubOverlay(coords[idx], width: w)
                } else if let rest = coords.last {
                    // Resting end-dot — the value itself lives in the journey header.
                    dot(at: rest)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        guard coords.count >= 2, w > 0 else { return }
                        let x = min(max(0, g.location.x), w)
                        // Nearest draw by real x position (honest gaps ≠ even indexes).
                        var best = 0
                        var bestDist = CGFloat.greatestFiniteMagnitude
                        for (i, c) in coords.enumerated() {
                            let d = abs(c.x - x)
                            if d < bestDist { bestDist = d; best = i }
                        }
                        if scrubIdx != best {
                            scrubIdx = best
                            Haptics.selection()
                        }
                    }
                    .onEnded { _ in scrubIdx = nil }
            )
            .accessibilityElement()
            .accessibilityLabel("\(journey.displayName) over time — drag to read each draw")
        }
        .frame(height: height)
        .onChange(of: journey.markerKey) { _, _ in scrubIdx = nil }
    }

    private func dot(at c: SparkCoord) -> some View {
        Circle()
            .fill(Color.forest)
            .frame(width: 8, height: 8)
            .overlay(Circle().stroke(Color.surface, lineWidth: 2))
            .position(x: c.x, y: c.y)
    }

    @ViewBuilder
    private func scrubOverlay(_ c: SparkCoord, width: CGFloat) -> some View {
        // Vertical guide.
        Path { p in
            p.move(to: CGPoint(x: c.x, y: 0))
            p.addLine(to: CGPoint(x: c.x, y: height))
        }
        .stroke(Color.lineStrong, lineWidth: 1)

        dot(at: c)

        // Tooltip — value + unit over the draw date, clamped inside the chart.
        let tipX = min(max(width * 0.12, c.x), width * 0.88)
        VStack(spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(LabsLabels.fmtValue(c.value))
                    .font(.clarionData(13))
                    .foregroundStyle(Color.ink)
                if let unit = journey.unit, !unit.isEmpty {
                    Text(unit)
                        .font(.clarionData(10))
                        .foregroundStyle(Color.ink3)
                }
            }
            Text(c.dateLabel)
                .font(.clarionBody(10))
                .foregroundStyle(Color.ink3)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: Brand.rSM))
        .overlay(RoundedRectangle(cornerRadius: Brand.rSM).stroke(Color.line2))
        .shadow(color: Color.shadowE1, radius: 3, y: 1)
        .position(x: tipX, y: 22)
    }
}

/// Small non-interactive mover-tile sparkline (the web's 120×36 tile spark).
/// Worsening movers stroke in the clay→claySoft gradient per the tokens.
struct MoverSparkline: View {
    let journey: LabJourney
    let trendClass: LabsLabels.TrendClass
    var height: CGFloat = 36

    var body: some View {
        GeometryReader { geo in
            let coords = JourneySpark.coords(journey.points, width: geo.size.width, height: height)
            if coords.count >= 2 {
                let path = JourneySpark.linePath(coords)
                if trendClass == .down {
                    path.stroke(
                        LinearGradient(colors: [Color.clay, Color.claySoft], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )
                } else {
                    path.stroke(Color.forest, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .frame(height: height)
    }
}
