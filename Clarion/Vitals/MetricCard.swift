import SwiftUI
import Charts

/// A metric tile: big value + trend chip + a line over the "your usual range" band with a
/// today-dot. Native rendition of the web BandChart.
struct MetricCard: View {
    let metric: VitalsMetric
    let daily: [WearableDailyMetrics]

    private var series: [Double] { WearableDailyMetrics.series(daily, metric.keyPath) }
    private var latest: Double? { WearableDailyMetrics.latest(daily, metric.keyPath) }

    /// The hero ring already announces today's readiness — this card becomes the TREND view
    /// (sparkline as hero, no duplicated big number).
    private var isTrendVariant: Bool { metric.id == "readiness" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(isTrendVariant ? "Readiness trend" : metric.title)
                    .font(.clarionDisplay(15.5))
                    .foregroundStyle(Color.ink)
                Spacer()
                if let t = trend { trendChip(t) }
                Text("\(min(series.count, daily.count))d")
                    .font(.clarionLabel(11))
                    .foregroundStyle(Color.ink3)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.paperDim, in: Capsule())
            }

            if !isTrendVariant {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(latest.map { format($0) } ?? "—")
                        .font(.clarionData(26))
                        .foregroundStyle(Color.ink)
                    if !metric.unit.isEmpty && metric.id != "sleep_quality" {
                        // sleep's value embeds its units ("6h 48m") — a trailing "min" would double up
                        Text(metric.unit).font(.clarionData(11)).foregroundStyle(Color.ink3)
                    }
                }
            }

            if series.count >= 2 {
                chart
                    .frame(height: isTrendVariant ? 92 : 64)
                    .clipped() // marks may draw outside their frame — never let the band flood the card
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.forest.opacity(0.10))
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.forest.opacity(0.25), lineWidth: 0.8))
                        .frame(width: 16, height: 8)
                    Text("your usual range").font(.clarionBody(11)).foregroundStyle(Color.ink3)
                }
            }

            Text(isTrendVariant ? "How your recovery has moved across the window" : metric.caption)
                .font(.clarionBody(13)).foregroundStyle(Color.ink3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .clarionCard()
    }

    // MARK: - Chart

    private var band: (lo: Double, hi: Double) {
        let n = Double(series.count)
        let mean = series.reduce(0, +) / n
        let sd = (series.reduce(0) { $0 + pow($1 - mean, 2) } / n).squareRoot()
        return (max(series.min() ?? mean, mean - 0.9 * sd), min(series.max() ?? mean, mean + 0.9 * sd))
    }

    private var chart: some View {
        let pts = Array(series.enumerated())
        let b = band
        return Chart {
            // "Your usual range" band — forest at fixed opacity (forestWash alone vanished
            // into the white card; the legend swatch looked like an empty box).
            RectangleMark(
                xStart: .value("s", 0), xEnd: .value("e", series.count - 1),
                yStart: .value("lo", b.lo), yEnd: .value("hi", b.hi)
            )
            .foregroundStyle(Color.forest.opacity(0.09))

            // Curve-following gradient fill under the line (not a flat block).
            ForEach(pts, id: \.offset) { i, v in
                AreaMark(x: .value("i", i), y: .value("v", v))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.forest.opacity(0.22), Color.forest.opacity(0.0)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            }
            ForEach(pts, id: \.offset) { i, v in
                LineMark(x: .value("i", i), y: .value("v", v))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.forest)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
            }
            if let last = series.last {
                // Ringed endpoint — a paper core inside the bright dot reads "today".
                PointMark(x: .value("i", series.count - 1), y: .value("v", last))
                    .symbolSize(110)
                    .foregroundStyle(Color.forestBright)
                PointMark(x: .value("i", series.count - 1), y: .value("v", last))
                    .symbolSize(34)
                    .foregroundStyle(Color.paper)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        // A hair of x-headroom so the today-dot sits fully inside the (now clipped) plot.
        .chartXScale(domain: -0.35 ... Double(series.count - 1) + 0.35)
        .chartYScale(domain: (series.min() ?? 0) * 0.92 ... (series.max() ?? 1) * 1.08)
        // Clip marks to the plot — the band RectangleMark was escaping the 64pt frame and
        // flooding the card below the chart (legend + caption sat on a pale green field).
        .chartPlotStyle { $0.clipShape(Rectangle()) }
    }

    // MARK: - Trend

    private var trend: (rising: Bool, pct: Int)? {
        guard series.count >= 4 else { return nil }
        let half = series.count / 2
        let first = series.prefix(half)
        let second = series.suffix(series.count - half)
        let m1 = first.reduce(0, +) / Double(first.count)
        let m2 = second.reduce(0, +) / Double(second.count)
        guard m1 != 0 else { return nil }
        let pct = Int(((m2 - m1) / m1 * 100).rounded())
        if abs(pct) < 2 { return nil }
        return (pct > 0, abs(pct))
    }

    private func trendChip(_ t: (rising: Bool, pct: Int)) -> some View {
        let good = t.rising == metric.higherIsBetter
        return Text("\(t.rising ? "▲" : "▼") \(t.pct)%")
            .font(.clarionData(12))
            .foregroundStyle(good ? Color.forest : Color.amber)
    }

    private func format(_ v: Double) -> String {
        if metric.id == "steps_energy" { return "\(Int(v))" }
        if metric.id == "sleep_quality" {
            // "6h 48m", not "408 min" — nights are read in hours.
            let h = Int(v) / 60, m = Int(v) % 60
            return h > 0 ? "\(h)h \(m)m" : "\(m)m"
        }
        return v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v)
    }
}

/// Correlation insight card (bloodwork × wearable) — the differentiator.
struct InsightCard: View {
    let insight: CorrelationInsight

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(insight.title)
                .font(.clarionDisplay(15.5))
                .foregroundStyle(Color.ink)
            Text(insight.body)
                .font(.clarionBody(14))
                .foregroundStyle(Color.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .clarionCard(cornerRadius: 16)
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16)
                .fill(insight.severity == "watch" ? Color.amber : Color.forest)
                .frame(width: 3)
        }
    }
}

struct WorkoutsCard: View {
    let workouts: [WearableWorkout]
    @AppStorage("clarion_units_imperial") private var unitsImperial = true

    private let symbols = [
        "run": "figure.run", "ride": "figure.outdoor.cycle", "swim": "figure.pool.swim",
        "strength": "figure.strengthtraining.traditional", "walk": "figure.walk",
        "hike": "figure.hiking", "row": "figure.rower",
    ]

    /// "52m · 5:24 /mi · 148 bpm" — duration, the sport's own metric, then heart rate.
    private func subtitle(_ w: WearableWorkout) -> String {
        var parts = ["\(Int(w.durationMin))m"]
        if let m = w.primaryMetric(imperial: unitsImperial) { parts.append(m.value) }
        if let hr = w.avgHeartRate { parts.append("\(Int(hr)) bpm") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(workouts.enumerated()), id: \.element.id) { i, w in
                HStack(spacing: 12) {
                    Image(systemName: symbols[w.type] ?? "figure.mixed.cardio")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.forestInk)
                        .frame(width: 34, height: 34)
                        .background(Color.forestWash, in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(w.type.capitalized).font(.clarionDisplay(14)).foregroundStyle(Color.ink)
                        Text(prettyDate(w.date)).font(.clarionData(12)).foregroundStyle(Color.ink3) // dates are data
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        if let km = w.distanceKm { Text(UnitsMath.distanceString(km: km, imperial: unitsImperial)).font(.clarionData(13)).foregroundStyle(Color.ink) }
                        Text(subtitle(w))
                            .font(.clarionData(11.5)).foregroundStyle(Color.ink3)
                    }
                }
                .padding(.vertical, 10)
                if i < workouts.count - 1 { Divider() }
            }
        }
        .padding(.horizontal, 16)
        .clarionCard(cornerRadius: 16)
    }

    private func prettyDate(_ iso: String) -> String {
        // Server day keys are Gregorian — parse and render them that way.
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: iso) else { return iso }
        let out = DateFormatter()
        out.calendar = Calendar(identifier: .gregorian)
        out.dateFormat = "MMM d"
        return out.string(from: d)
    }
}

