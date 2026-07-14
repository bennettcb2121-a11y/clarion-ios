import SwiftUI

/// The native Biomarkers library — parity with the web's BiomarkersHandoff:
/// every marker from the latest panel against BOTH ranges (your personalized
/// band + the standard lab range), filter chips, and a per-marker sheet with
/// the verdict + science drawer.
///
/// Data rides the existing GET /api/report through the shared ReportStore —
/// the enriched fields (labNormal*, verdict, science) are already optional on
/// BiomarkerResult, so the screen renders fine before the API enrichment ships
/// and gets richer the moment it does.
struct BiomarkersView: View {
    @ObservedObject var store: ReportStore
    @EnvironmentObject private var subscription: SubscriptionStore

    private enum Filter: Hashable {
        case all, review, inRange
    }

    @State private var filter: Filter = .all
    @State private var showAll = false
    @State private var detail: BiomarkerResult? = nil

    private static let defaultVisible = 10

    var body: some View {
        ScrollView {
            if !subscription.entitled {
                // Clarion+ gates the analysis surfaces (web parity) — the wall,
                // never a purchase button. Fails open; see SubscriptionStore.
                MembershipWall(surface: "biomarker library")
            } else {
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
        }
        .background(Color.paper.ignoresSafeArea())
        .navigationTitle("Biomarkers")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await store.load() }
        .task { if case .loading = store.state { await store.load() } }
        .sheet(item: $detail) { marker in
            MarkerDetailSheet(marker: marker)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ r: ReportResponse) -> some View {
        let sorted = (r.results ?? []).sorted {
            $0.sortRank != $1.sortRank ? $0.sortRank < $1.sortRank : $0.name < $1.name
        }
        let review = sorted.filter(\.isFlagged).count
        let inRange = sorted.filter { $0.status == "optimal" }.count
        let filtered = applyFilter(sorted)
        let visible = showAll ? filtered : Array(filtered.prefix(Self.defaultVisible))

        VStack(alignment: .leading, spacing: Brand.s5) {
            hero(total: sorted.count, profileLabel: sorted.compactMap(\.profileLabel).first)
                .entrance(0)

            filterChips(total: sorted.count, review: review, inRange: inRange)
                .entrance(1)

            legend.entrance(1)

            VStack(spacing: Brand.s3) {
                ForEach(visible) { marker in
                    markerRow(marker)
                }
            }
            .entrance(2)

            if filtered.count > Self.defaultVisible && !showAll {
                Button("Show all \(filtered.count) markers") {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { showAll = true }
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            if filtered.isEmpty {
                Text("No markers match this filter.")
                    .font(.clarionBody(13.5))
                    .foregroundStyle(Color.ink3)
            }

            Text("Educational, not medical advice. Discuss changes with your clinician.")
                .font(.clarionBody(12))
                .foregroundStyle(Color.ink4)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.top, Brand.s2)
        }
        .padding(Brand.s5)
    }

    private func applyFilter(_ results: [BiomarkerResult]) -> [BiomarkerResult] {
        switch filter {
        case .all: return results
        case .review: return results.filter(\.isFlagged)
        case .inRange: return results.filter { $0.status == "optimal" }
        }
    }

    // MARK: - Hero

    private func hero(total: Int, profileLabel: String?) -> some View {
        VStack(alignment: .leading, spacing: Brand.s3) {
            Text("All \(total) markers from your latest panel, each against your personalized range and the standard lab range.")
                .font(.clarionBody(14.5))
                .foregroundStyle(Color.ink2)

            if let label = profileLabel, !label.isEmpty, label != "general adult" {
                VStack(alignment: .leading, spacing: Brand.s1) {
                    Eyebrow("Calibrated for", color: .forest)
                    Text(label.prefix(1).uppercased() + label.dropFirst())
                        .font(.clarionDisplay(17))
                        .tracking(-0.015 * 17)
                        .foregroundStyle(Color.ink)
                    Text("These aren't textbook ranges. Each one is rebuilt for your sex, age, and training — so \u{201C}normal\u{201D} on a lab slip can still be off for your goal.")
                        .font(.clarionBody(12.5))
                        .foregroundStyle(Color.ink3)
                }
                .padding(Brand.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clarionCardQuiet()
            }
        }
    }

    // MARK: - Filters + legend

    private func filterChips(total: Int, review: Int, inRange: Int) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Brand.s2) {
                filterChip("All \(total)", .all)
                if review > 0 {
                    filterChip("To review · \(review)", .review)
                }
                filterChip("In range · \(inRange)", .inRange)
            }
        }
    }

    private func filterChip(_ label: String, _ value: Filter) -> some View {
        let active = filter == value
        return Button {
            filter = value
            showAll = false
        } label: {
            Text(label)
                .font(.clarionLabel(12))
                .foregroundStyle(active ? Color.white : Color.ink2)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(active ? Color.forest : Color.surface2, in: Capsule())
                .overlay(Capsule().stroke(active ? Color.clear : Color.line2))
        }
        .buttonStyle(PressableStyle())
    }

    private var legend: some View {
        HStack(spacing: Brand.s4) {
            HStack(spacing: 5) {
                Circle()
                    .fill(Color.surface)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color.forest, lineWidth: 2))
                Text("Your value")
            }
            HStack(spacing: 5) {
                Capsule().fill(Color.forest).frame(width: 16, height: 6)
                Text("Your range")
            }
            HStack(spacing: 5) {
                Rectangle().fill(Color.lineStrong).frame(width: 16, height: 1.5)
                Text("Standard lab range")
            }
        }
        .font(.clarionBody(11))
        .foregroundStyle(Color.ink3)
    }

    // MARK: - Rows

    private func markerRow(_ marker: BiomarkerResult) -> some View {
        Button {
            detail = marker
        } label: {
            VStack(alignment: .leading, spacing: Brand.s3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(marker.name)
                        .font(.clarionDisplay(16))
                        .tracking(-0.015 * 16)
                        .foregroundStyle(Color.ink)
                    Spacer()
                    TagPill(status: marker.status, label: marker.statusLabel)
                }

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(LabsLabels.fmtValue(marker.value))
                        .font(.clarionData(19))
                        .foregroundStyle(marker.isFlagged ? Color.clay : Color.ink)
                    if let unit = marker.unit, !unit.isEmpty {
                        Text(unit)
                            .font(.clarionData(12))
                            .foregroundStyle(Color.ink3)
                    }
                }

                HonestRangeBar(
                    value: marker.value,
                    optimalMin: marker.optimalMin,
                    optimalMax: marker.optimalMax,
                    labNormalMin: marker.labNormalMin,
                    labNormalMax: marker.labNormalMax,
                    status: marker.status
                )

                if let verdict = marker.verdict, !verdict.isEmpty {
                    Text(verdict)
                        .font(.clarionBody(12.5))
                        .foregroundStyle(Color.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Brand.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clarionCard()
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - Empty / error

    private var emptyState: some View {
        VStack(spacing: Brand.s4) {
            Image(systemName: "drop")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color.ink3)
                .padding(.top, Brand.s8)
            Text("No bloodwork yet")
                .font(.clarionDisplay(21))
                .tracking(-0.015 * 21)
                .foregroundStyle(Color.ink)
            Text("Upload a panel and every marker lands here — graded against ranges built for you, not the average patient.")
                .font(.clarionBody(14))
                .foregroundStyle(Color.ink2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity)
        .padding(Brand.s5)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: Brand.s3) {
            Text(message)
                .font(.clarionBody(14))
                .foregroundStyle(Color.ink2)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await store.load() } }
                .buttonStyle(SecondaryButtonStyle())
                .frame(maxWidth: 160)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .padding(Brand.s5)
    }
}

// MARK: - Marker detail sheet

/// The consult view for one marker: value + honest axis, the verdict sentence,
/// and the science drawer (foods / lifestyle / supplement notes / retest /
/// research) — whichever fields the API has sent.
private struct MarkerDetailSheet: View {
    let marker: BiomarkerResult

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Brand.s4) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(marker.name)
                                .font(.clarionDisplay(22))
                                .tracking(-0.015 * 22)
                                .foregroundStyle(Color.ink)
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text(LabsLabels.fmtValue(marker.value))
                                    .font(.clarionData(24))
                                    .foregroundStyle(marker.isFlagged ? Color.clay : Color.ink)
                                if let unit = marker.unit, !unit.isEmpty {
                                    Text(unit)
                                        .font(.clarionData(13))
                                        .foregroundStyle(Color.ink3)
                                }
                            }
                        }
                        Spacer()
                        TagPill(status: marker.status, label: marker.statusLabel)
                    }

                    HonestRangeBar(
                        value: marker.value,
                        optimalMin: marker.optimalMin,
                        optimalMax: marker.optimalMax,
                        labNormalMin: marker.labNormalMin,
                        labNormalMax: marker.labNormalMax,
                        status: marker.status
                    )

                    if let verdict = marker.verdict, !verdict.isEmpty {
                        Text(verdict)
                            .font(.clarionBody(14))
                            .foregroundStyle(Color.ink)
                            .padding(Brand.s3 + 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                marker.verdictIsFlagged == true ? Color.clayWash : Color.forestWash,
                                in: RoundedRectangle(cornerRadius: Brand.r)
                            )
                    }

                    scienceSection("About", text: marker.description)
                    scienceSection("Why it matters", text: marker.whyItMatters)
                    scienceSection("Foods", text: marker.foods)
                    scienceSection("Lifestyle", text: marker.lifestyle)
                    scienceSection("Supplement notes", text: marker.supplementNotes)
                    scienceSection("When to retest", text: marker.retest)
                    scienceSection("Research", text: marker.researchSummary)

                    if !marker.hasScience && marker.description == nil {
                        Text("Open your full report on the web for this marker's science drawer.")
                            .font(.clarionBody(12.5))
                            .foregroundStyle(Color.ink3)
                    }
                }
                .padding(Brand.s5)
            }
            .background(Color.paper.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func scienceSection(_ title: String, text: String?) -> some View {
        if let text, !text.isEmpty {
            VStack(alignment: .leading, spacing: Brand.s1) {
                Eyebrow(title)
                Text(text)
                    .font(.clarionBody(13.5))
                    .foregroundStyle(Color.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
