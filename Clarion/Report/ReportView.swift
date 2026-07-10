import SwiftUI

/// Native bloodwork report: overall score, a status summary, and biomarkers grouped
/// flagged-first. Reads GET /api/report (shared ReportStore).
struct ReportView: View {
    @ObservedObject var store: ReportStore

    var body: some View {
        NavigationStack {
            ScrollView {
                switch store.state {
                case .loading:
                    ProgressView().padding(.top, 80)
                case .empty:
                    emptyState
                case .error(let m):
                    errorState(m)
                case .ready(let r):
                    content(r)
                }
            }
            .background(Color.paper.ignoresSafeArea())
            .navigationTitle("Report")
            .refreshable { await store.load() }
        }
        .task { if case .loading = store.state { await store.load() } }
    }

    @ViewBuilder
    private func content(_ r: ReportResponse) -> some View {
        VStack(spacing: 18) {
            scoreCard(r)

            let results = (r.results ?? []).sorted {
                $0.sortRank != $1.sortRank ? $0.sortRank < $1.sortRank : $0.name < $1.name
            }
            let flagged = results.filter { $0.isFlagged }
            let optimal = results.filter { $0.status == "optimal" }

            if !flagged.isEmpty {
                sectionLabel("Worth a look")
                ForEach(flagged) { BiomarkerRow(result: $0) }
            }
            if !optimal.isEmpty {
                sectionLabel("In range")
                ForEach(optimal) { BiomarkerRow(result: $0) }
            }
        }
        .padding(20)
    }

    private func scoreCard(_ r: ReportResponse) -> some View {
        VStack(spacing: 8) {
            Text("\(r.score ?? 0)")
                .font(.system(size: 64, weight: .bold, design: .serif))
                .foregroundStyle(Color.forest)
            Text((r.scoreLabel ?? "").uppercased())
                .font(.system(size: 12, weight: .bold)).tracking(2)
                .foregroundStyle(Color.inkMuted)
            if let c = r.counts {
                HStack(spacing: 8) {
                    pill("\(c.optimal) in range", .forest)
                    if c.low + c.high + c.suboptimal > 0 {
                        pill("\(c.low + c.high + c.suboptimal) to review", .clay)
                    }
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            LinearGradient(colors: [Color.white, Color.forestWash.opacity(0.5)], startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 24)
        )
    }

    private func pill(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(c.opacity(0.14), in: Capsule())
            .foregroundStyle(c)
    }

    private func sectionLabel(_ t: String) -> some View {
        Text(t.uppercased()).font(.system(size: 12, weight: .semibold)).tracking(1.6)
            .foregroundStyle(Color.inkMuted).frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "drop.fill").font(.largeTitle).foregroundStyle(Color.forest)
            Text("No bloodwork yet").font(.headline)
            Text("Add a panel on clarionlabs.tech to see your personalized report.")
                .font(.subheadline).foregroundStyle(Color.inkMuted).multilineTextAlignment(.center)
        }
        .padding(40)
    }

    private func errorState(_ m: String) -> some View {
        Text(m).font(.subheadline).foregroundStyle(Color.inkMuted).padding(40)
    }
}

/// One biomarker: name, value, a range bar showing where the value sits, and its status.
struct BiomarkerRow: View {
    let result: BiomarkerResult

    private var tone: Color {
        switch result.status {
        case "optimal": return .forest
        case "high", "deficient": return .clay
        default: return Color(red: 0.7, green: 0.5, blue: 0.2) // amber
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(result.name).font(.system(.body, design: .serif)).foregroundStyle(Color.ink)
                Spacer()
                Text(format(result.value))
                    .font(.system(.body, design: .monospaced)).foregroundStyle(Color.ink)
                Text(result.statusLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(tone.opacity(0.14), in: Capsule())
                    .foregroundStyle(tone)
            }
            if let lo = result.optimalMin, let hi = result.optimalMax, hi > lo {
                rangeBar(lo: lo, hi: hi, value: result.value)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.05)))
    }

    private func rangeBar(lo: Double, hi: Double, value: Double) -> some View {
        // Pad the visible axis 25% beyond the optimal band so out-of-range values still show.
        let span = hi - lo
        let axisLo = lo - span * 0.5
        let axisHi = hi + span * 0.5
        let pos = min(1, max(0, (value - axisLo) / (axisHi - axisLo)))
        let bandLo = (lo - axisLo) / (axisHi - axisLo)
        let bandHi = (hi - axisLo) / (axisHi - axisLo)
        return GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.systemGray6)).frame(height: 6)
                Capsule().fill(Color.forestWash)
                    .frame(width: w * (bandHi - bandLo), height: 6)
                    .offset(x: w * bandLo)
                Circle().fill(tone).frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .offset(x: w * pos - 6)
            }
        }
        .frame(height: 12)
    }

    private func format(_ v: Double) -> String {
        v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v)
    }
}
