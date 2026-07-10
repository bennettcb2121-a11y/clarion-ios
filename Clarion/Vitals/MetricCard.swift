import SwiftUI
import Charts

/// A metric tile: big value + trend chip + a line over the "your usual range" band with a
/// today-dot. Native rendition of the web BandChart.
struct MetricCard: View {
    let metric: VitalsMetric
    let daily: [WearableDailyMetrics]

    private var series: [Double] { WearableDailyMetrics.series(daily, metric.keyPath) }
    private var latest: Double? { WearableDailyMetrics.latest(daily, metric.keyPath) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(metric.title)
                    .font(.system(.headline, design: .serif))
                    .foregroundStyle(Color.ink)
                Spacer()
                if let t = trend { trendChip(t) }
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(latest.map { format($0) } ?? "—")
                    .font(.system(size: 30, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.ink)
                if !metric.unit.isEmpty {
                    Text(metric.unit).font(.caption).foregroundStyle(Color.inkMuted)
                }
            }

            if series.count >= 2 {
                chart
                    .frame(height: 64)
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.forestWash).frame(width: 16, height: 8)
                    Text("your usual range").font(.system(size: 11)).foregroundStyle(Color.inkMuted)
                }
            }

            Text(metric.caption).font(.footnote).foregroundStyle(Color.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.06)))
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
            RectangleMark(
                xStart: .value("s", 0), xEnd: .value("e", series.count - 1),
                yStart: .value("lo", b.lo), yEnd: .value("hi", b.hi)
            )
            .foregroundStyle(Color.forestWash.opacity(0.6))

            ForEach(pts, id: \.offset) { i, v in
                LineMark(x: .value("i", i), y: .value("v", v))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.forest)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
            }
            if let last = series.last {
                PointMark(x: .value("i", series.count - 1), y: .value("v", last))
                    .symbolSize(90)
                    .foregroundStyle(Color.forestBright)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: (series.min() ?? 0) * 0.92 ... (series.max() ?? 1) * 1.08)
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
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(good ? Color.forest : Color.clay)
    }

    private func format(_ v: Double) -> String {
        if metric.id == "steps_energy" { return "\(Int(v))" }
        return v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v)
    }
}

/// Correlation insight card (bloodwork × wearable) — the differentiator.
struct InsightCard: View {
    let insight: CorrelationInsight

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(insight.title)
                .font(.system(.headline, design: .serif))
                .foregroundStyle(Color.ink)
            Text(insight.body)
                .font(.subheadline)
                .foregroundStyle(Color.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(insight.severity == "watch" ? Color.clay : Color.forest)
                .frame(width: 4)
                .clipShape(RoundedRectangle(cornerRadius: 2))
        }
    }
}

struct WorkoutsCard: View {
    let workouts: [WearableWorkout]

    private let emoji = ["run": "🏃", "ride": "🚴", "swim": "🏊", "strength": "🏋️", "walk": "🚶", "hike": "🥾", "row": "🚣"]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(workouts.enumerated()), id: \.element.id) { i, w in
                HStack(spacing: 12) {
                    Text(emoji[w.type] ?? "💪").font(.title3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(w.type.capitalized).font(.system(.subheadline, design: .serif)).foregroundStyle(Color.ink)
                        Text(prettyDate(w.date)).font(.caption).foregroundStyle(Color.inkMuted)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        if let km = w.distanceKm { Text(String(format: "%.1f km", km)).font(.system(size: 13, design: .monospaced)) }
                        Text("\(Int(w.durationMin))m · \(w.avgHeartRate.map { "\(Int($0)) bpm" } ?? "—")")
                            .font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.inkMuted)
                    }
                }
                .padding(.vertical, 10)
                if i < workouts.count - 1 { Divider() }
            }
        }
        .padding(.horizontal, 16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.06)))
    }

    private func prettyDate(_ iso: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: iso) else { return iso }
        let out = DateFormatter(); out.dateFormat = "MMM d"
        return out.string(from: d)
    }
}

extension VitalsView {
    var sampleBanner: some View {
        HStack {
            Image(systemName: "sparkles")
            Text("Sample data — connect a device to see your own.").font(.footnote)
            Spacer()
        }
        .foregroundStyle(Color.forestInk)
        .padding(12)
        .background(Color.forestWash, in: RoundedRectangle(cornerRadius: 12))
    }
}
