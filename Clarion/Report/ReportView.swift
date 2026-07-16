import SwiftUI

/// The native Clarion report — parity with the web's consult-card report:
///  - score dial computed FRESH by the shared graded engine (never the stored value)
///  - "where the score comes from" category breakdown
///  - honest-axis grouping: clinician conversations / your levers / in range
///  - per-marker consult cards: verdict sentence, dual honest range bar, science drawer
struct ReportView: View {
    @ObservedObject var store: ReportStore
    @EnvironmentObject private var auth: SupabaseAuth
    @EnvironmentObject private var subscription: SubscriptionStore
    @State private var showChat = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if !subscription.entitled {
                    // Clarion+ gates the analysis surfaces (web parity) — the wall,
                    // never a purchase button. Fails open; see SubscriptionStore.
                    MembershipWall(surface: "report")
                } else {
                    switch store.state {
                    case .loading:
                        ClarionLoadingView()
                    case .empty:
                        emptyState
                    case .error(let m):
                        errorState(m)
                    case .ready(let r):
                        content(r)
                    }
                }
            }
            .contentMargins(.bottom, 96, for: .scrollContent)
            .background(Color.paper.ignoresSafeArea())
            .navigationTitle("Report")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.tap()
                        showChat = true
                    } label: {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                            .foregroundStyle(Color.forest)
                    }
                    .accessibilityLabel("Ask Clarion")
                }
            }
            .refreshable { await store.load() }
        }
        .sheet(isPresented: $showChat) {
            // The chat rides on THIS panel: the snapshot is rebuilt per send from the
            // loaded report, mirroring the web's biomarker-aware assistant.
            AskClarionSheet(auth: auth, snapshotProvider: { [store] in
                if case .ready(let r) = store.state { return BiomarkerSnapshot.build(from: r) }
                return nil
            })
        }
        .task { if case .loading = store.state { await store.load() } }
    }

    @ViewBuilder
    private func content(_ r: ReportResponse) -> some View {
        let results = (r.results ?? []).sorted {
            $0.sortRank != $1.sortRank ? $0.sortRank < $1.sortRank : $0.name < $1.name
        }
        // The same fresh graded score the web dashboard shows — never the stored value.
        let score = ScoreEngine.score(results)

        VStack(spacing: Brand.s4) {
            scoreCard(score: score, results: results, lastUpdated: r.lastUpdated).entrance(0)

            let breakdown = ScoreEngine.breakdown(results)
            if breakdown.count > 1 {
                breakdownCard(breakdown).entrance(1)
            }

            let doctor = results.filter { $0.isOutsideLabNormal && $0.isFlagged }
            let levers = results.filter { $0.isFlagged && !($0.isOutsideLabNormal) }
            let optimal = results.filter { $0.status == "optimal" }

            if !doctor.isEmpty {
                section("Worth a clinician conversation",
                        note: "Outside what even a lab slip calls normal.")
                    .entrance(2)
                ForEach(Array(doctor.enumerated()), id: \.element.id) { i, m in
                    MarkerConsultCard(result: m, forecast: ScoreEngine.improvementForecast(results, fixing: m.name))
                        .entrance(3 + i)
                }
            }
            if !levers.isEmpty {
                section("Your levers",
                        note: "Lab-normal, but off Clarion's target for you — the numbers you can move.")
                    .entrance(3 + doctor.count)
                ForEach(Array(levers.enumerated()), id: \.element.id) { i, m in
                    MarkerConsultCard(result: m, forecast: ScoreEngine.improvementForecast(results, fixing: m.name))
                        .entrance(4 + doctor.count + i)
                }
            }
            if !optimal.isEmpty {
                section("In range", note: nil)
                    .entrance(4 + doctor.count + levers.count)
                ForEach(optimal) { m in
                    MarkerConsultCard(result: m, forecast: nil)
                }
            }

            Text("Educational, not medical advice. Discuss changes with your clinician.")
                .font(.clarionBody(12))
                .foregroundStyle(Color.ink4)
                .multilineTextAlignment(.center)
                .padding(.top, Brand.s2)
        }
        .padding(Brand.s5)
    }

    // MARK: - Score hero

    private func scoreCard(score: Int, results: [BiomarkerResult], lastUpdated: String?) -> some View {
        VStack(spacing: Brand.s4) {
            ScoreDial(score: score, label: ScoreEngine.label(for: score))

            let flagged = results.filter(\.isFlagged).count
            let optimal = results.filter { $0.status == "optimal" }.count
            HStack(spacing: Brand.s2) {
                TagPill("\(optimal) in range", tone: .forestInk, wash: .forestWash)
                if flagged > 0 {
                    TagPill("\(flagged) to review", tone: .amber, wash: .amberWash)
                }
            }

            if let profile = results.compactMap(\.profileLabel).first {
                Text("Ranges calibrated for a \(profile).")
                    .font(.clarionBody(13.5))
                    .foregroundStyle(Color.ink3)
            }
            if let updated = prettyDate(lastUpdated) {
                // The report's "issued" metadata line — the one sanctioned docmono use.
                Text("Panel from \(updated)")
                    .font(.clarionDocMono(11))
                    .foregroundStyle(Color.ink4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Brand.s6)
        .clarionCard(cornerRadius: Brand.rXL)
    }

    // MARK: - Category breakdown

    private func breakdownCard(_ rows: [(category: ScoreEngine.Category, score: Int, count: Int)]) -> some View {
        VStack(alignment: .leading, spacing: Brand.s3) {
            Eyebrow("Where the score comes from")
            ForEach(rows, id: \.category) { row in
                HStack(spacing: Brand.s3) {
                    Text(row.category.rawValue)
                        .font(.clarionBody(14.5))
                        .foregroundStyle(Color.ink2)
                        .frame(width: 148, alignment: .leading)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.paperDim).frame(height: 6)
                            Capsule()
                                .fill(
                                    LinearGradient(colors: [Color.forestBright, Color.forest], startPoint: .leading, endPoint: .trailing)
                                )
                                .frame(width: geo.size.width * CGFloat(row.score) / 100, height: 6)
                        }
                        .frame(maxHeight: .infinity, alignment: .center)
                    }
                    Text("\(row.score)")
                        .font(.clarionData(13))
                        .foregroundStyle(row.score >= 90 ? Color.forest : (row.score >= 70 ? Color.ink2 : Color.amber))
                        .frame(width: 32, alignment: .trailing)
                }
                .frame(height: 20)
            }
        }
        .padding(Brand.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clarionCard()
    }

    // MARK: - Sections & states

    private func section(_ title: String, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Eyebrow(title)
            if let note {
                Text(note)
                    .font(.clarionBody(13))
                    .foregroundStyle(Color.ink3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Brand.s2)
    }

    private var emptyState: some View {
        VStack(spacing: Brand.s3) {
            Image(systemName: "drop.fill").font(.largeTitle).foregroundStyle(Color.forest)
            Text("No bloodwork yet").font(.clarionDisplay(19)).foregroundStyle(Color.ink)
            Text("Upload your labs when you're ready — your personalized report builds from there.")
                .font(.clarionBody(15)).foregroundStyle(Color.ink3).multilineTextAlignment(.center)
        }
        .padding(40)
    }

    private func errorState(_ m: String) -> some View {
        Text(m).font(.clarionBody(15)).foregroundStyle(Color.ink3).padding(40)
    }

    private func prettyDate(_ iso: String?) -> String? {
        guard let iso else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = f.date(from: iso) ?? {
            f.formatOptions = [.withInternetDateTime]
            return f.date(from: iso)
        }()
        guard let date else { return nil }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

// MARK: - Consult card

/// Every marker gets the consult treatment (web `.mcc`): serif name + status tag + mono value,
/// the plain-English verdict, the honest dual range bar, and an expandable science drawer.
/// Flagged rows carry a 3pt tone accent on the leading edge.
struct MarkerConsultCard: View {
    let result: BiomarkerResult
    let forecast: Int?

    @State private var showScience = false

    private var tone: Color { Color.tone(for: result.status) }

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.s3) {
            // Header: name / value / status.
            HStack(alignment: .firstTextBaseline, spacing: Brand.s2) {
                Text(result.name)
                    .font(.clarionDisplay(18))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: Brand.s2)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(format(result.value))
                        .font(.clarionData(19))
                        .foregroundStyle(Color.ink)
                    if let unit = result.unit, !unit.isEmpty {
                        Text(unit)
                            .font(.clarionData(11))
                            .foregroundStyle(Color.ink3)
                    }
                }
            }

            HStack(spacing: Brand.s2) {
                TagPill(status: result.status, label: result.statusLabel)
                if result.isPersonalized == true {
                    TagPill("Yours", tone: .forestInk, wash: .forestWash)
                }
                if let gain = forecast, gain > 0 {
                    TagPill("+\(gain) pts if fixed", tone: .forestInk, wash: .forestWash)
                }
            }

            // The verdict — Clarion's one honest sentence about this number.
            if let verdict = result.verdict, !verdict.isEmpty {
                Text(verdict)
                    .font(.clarionBody(14.5))
                    .foregroundStyle(result.verdictIsFlagged == true ? Color.ink : Color.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let why = result.whyItMatters, !why.isEmpty, result.isFlagged {
                Text(why)
                    .font(.clarionBody(14.5))
                    .foregroundStyle(Color.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HonestRangeBar(
                value: result.value,
                optimalMin: result.optimalMin,
                optimalMax: result.optimalMax,
                labNormalMin: result.labNormalMin,
                labNormalMax: result.labNormalMax,
                status: result.status
            )

            // Science drawer.
            if result.hasScience || result.whyItMatters != nil {
                Button {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showScience.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(showScience ? "Hide the science" : "Show the science")
                            .font(.clarionLabel(13))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .rotationEffect(.degrees(showScience ? 90 : 0))
                    }
                    .foregroundStyle(Color.forest)
                }
                .buttonStyle(PressableStyle())

                if showScience {
                    ScienceDrawer(result: result)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(Brand.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clarionCard(cornerRadius: Brand.r)
        .overlay(alignment: .leading) {
            if result.isFlagged {
                UnevenRoundedRectangle(topLeadingRadius: Brand.r, bottomLeadingRadius: Brand.r)
                    .fill(tone)
                    .frame(width: 3)
            }
        }
    }

    private func format(_ v: Double) -> String {
        v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v)
    }
}

/// Expanded evidence panel (web `.mcc-sci`): surface-2, uppercase forest key-labels, body copy.
struct ScienceDrawer: View {
    let result: BiomarkerResult

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.s3) {
            drawerRow("Why it matters", result.whyItMatters ?? result.description)
            drawerRow("The research", result.researchSummary)
            drawerRow("Food first", result.foods)
            drawerRow("Lifestyle", result.lifestyle)
            drawerRow("Supplements", result.supplementNotes)
            drawerRow("Retest", result.retest)
        }
        .padding(Brand.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface2, in: RoundedRectangle(cornerRadius: Brand.rSM))
    }

    @ViewBuilder
    private func drawerRow(_ label: String, _ text: String?) -> some View {
        if let text, !text.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(label.uppercased())
                    .font(.clarionLabel(10.5))
                    .tracking(1.2)
                    .foregroundStyle(Color.forest)
                Text(text)
                    .font(.clarionBody(14))
                    .foregroundStyle(Color.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
