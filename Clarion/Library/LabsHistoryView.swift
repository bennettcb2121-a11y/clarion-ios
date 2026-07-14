import SwiftUI

/// The native Labs history screen — parity with the web Labs tab (LabsHandoff):
/// latest-panel hero + earlier-draw archive, the featured marker journey with a
/// scrubbable honest-gap line, and the movers grid with an honest all-steady state.
struct LabsHistoryView: View {
    @ObservedObject var store: LabsHistoryStore
    let auth: SupabaseAuth
    @EnvironmentObject private var subscription: SubscriptionStore

    /// nil → the server-ranked first journey is featured.
    @State private var activeMarker: String? = nil
    @State private var showArchive = false
    @State private var markerPickerShown = false
    @State private var openingWeb = false

    var body: some View {
        ScrollView {
            if !subscription.entitled {
                // Clarion+ gates the analysis surfaces (web parity) — the wall,
                // never a purchase button. Fails open; see SubscriptionStore.
                MembershipWall(surface: "labs history")
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
        .navigationTitle("Labs")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await store.load() }
        .task { if case .loading = store.state { await store.load() } }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ r: LabsHistoryResponse) -> some View {
        let hasTrends = r.journeys.contains { $0.points.count >= 2 }
        let featured = featuredJourney(r)

        VStack(alignment: .leading, spacing: Brand.s5) {
            hero(hasTrends: hasTrends).entrance(0)

            if let latest = r.panels.first {
                sectionLabel("Latest panel").entrance(1)
                latestPanelCard(latest, prior: r.panels.count > 1 ? r.panels[1] : nil)
                    .entrance(1)
                if r.panels.count > 1 {
                    archiveSection(r.panels).entrance(2)
                }
            }

            if !hasTrends && !r.panels.isEmpty {
                sectionLabel("Trends").entrance(3)
                trendsLockedCard.entrance(3)
            }

            if let featured, featured.points.count >= 2 {
                sectionLabel("How a marker moved over time").entrance(3)
                journeyCard(featured, all: r.journeys).entrance(3)
            }

            moversSection(r).entrance(4)
        }
        .padding(Brand.s5)
        .sheet(isPresented: $markerPickerShown) {
            MarkerPickerSheet(journeys: r.journeys, activeKey: featured?.markerKey) { key in
                activeMarker = key
                markerPickerShown = false
            }
        }
    }

    private func featuredJourney(_ r: LabsHistoryResponse) -> LabJourney? {
        let key = activeMarker ?? r.journeys.first?.markerKey
        return r.journeys.first { $0.markerKey == key } ?? r.journeys.first
    }

    // MARK: - Hero

    private func hero(hasTrends: Bool) -> some View {
        VStack(alignment: .leading, spacing: Brand.s2) {
            Text(hasTrends
                 ? "Every panel you've uploaded, newest first. Tap one to open its report — and below, how each marker has moved between draws."
                 : "Every panel you've uploaded, newest first. Tap one to open its report. Trends appear here once a marker shows up on two panels.")
                .font(.clarionBody(14.5))
                .foregroundStyle(Color.ink2)

            Button {
                openWeb("/labs/upload")
            } label: {
                Label("Add a panel", systemImage: "arrow.right")
                    .labelStyle(.titleOnly)
                    .font(.clarionLabel(13.5))
                    .foregroundStyle(Color.forest)
            }
            .buttonStyle(PressableStyle())
            .disabled(openingWeb)
        }
    }

    // MARK: - Panels

    private func latestPanelCard(_ panel: LabPanel, prior: LabPanel?) -> some View {
        Button {
            openWeb("/dashboard/analysis")
        } label: {
            HStack(alignment: .center, spacing: Brand.s4) {
                Text(panel.score.map(String.init) ?? "—")
                    .font(.clarionDisplay(44))
                    .tracking(-0.015 * 44)
                    .foregroundStyle(Color.ink)
                    .monospacedDigit()

                VStack(alignment: .leading, spacing: 3) {
                    Text(panel.dateLabel)
                        .font(.clarionData(15))
                        .foregroundStyle(Color.ink)
                    Text(LabsLabels.panelReviewMeta(markerCount: panel.markerCount, reviewCount: panel.reviewCount))
                        .font(.clarionBody(12.5))
                        .foregroundStyle(Color.ink3)
                    if let prior {
                        let delta = LabsLabels.panelScoreDelta(current: panel.score, prior: prior.score)
                        Text("\(delta) since previous draw")
                            .font(.clarionData(12))
                            .foregroundStyle(deltaTone(current: panel.score, prior: prior.score))
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Open report")
                        .font(.clarionLabel(11.5))
                        .foregroundStyle(Color.forest)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.forest)
                }
            }
            .padding(Brand.s5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clarionCard()
        }
        .buttonStyle(PressableStyle())
        .disabled(openingWeb)
    }

    private func deltaTone(current: Int?, prior: Int?) -> Color {
        guard let current, let prior else { return .ink3 }
        return current > prior ? .forest : .ink3
    }

    private func archiveSection(_ panels: [LabPanel]) -> some View {
        VStack(alignment: .leading, spacing: Brand.s3) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showArchive.toggle() }
            } label: {
                HStack(spacing: Brand.s2) {
                    Text("Open an earlier draw")
                        .font(.clarionLabel(13))
                        .foregroundStyle(Color.ink2)
                    Text("\(panels.count - 1)")
                        .font(.clarionData(11.5))
                        .foregroundStyle(Color.ink3)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.paperDim, in: Capsule())
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.ink3)
                        .rotationEffect(.degrees(showArchive ? 180 : 0))
                }
                .padding(.horizontal, Brand.s4)
                .padding(.vertical, Brand.s3)
                .clarionCardQuiet(cornerRadius: Brand.r)
            }
            .buttonStyle(PressableStyle())

            if showArchive {
                VStack(spacing: 0) {
                    ForEach(Array(panels.dropFirst().enumerated()), id: \.element.id) { i, panel in
                        let prior = i + 2 < panels.count ? panels[i + 2] : nil
                        archiveRow(panel, prior: prior)
                        if panel.id != panels.last?.id { Divider().overlay(Color.line) }
                    }
                }
                .clarionCard()
            }
        }
    }

    private func archiveRow(_ panel: LabPanel, prior: LabPanel?) -> some View {
        Button {
            // v1 lands on the web report (the ?panel= deep link needs a wider
            // login-link whitelist server-side — see build notes).
            openWeb("/dashboard/analysis")
        } label: {
            HStack(spacing: Brand.s3) {
                Text(panel.score.map(String.init) ?? "—")
                    .font(.clarionData(17))
                    .foregroundStyle(Color.ink)
                    .frame(width: 40, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(panel.dateLabel)
                        .font(.clarionData(13.5))
                        .foregroundStyle(Color.ink)
                    Text(LabsLabels.panelReviewMeta(markerCount: panel.markerCount, reviewCount: panel.reviewCount))
                        .font(.clarionBody(11.5))
                        .foregroundStyle(Color.ink3)
                }
                Spacer()
                Text(LabsLabels.panelScoreDelta(current: panel.score, prior: prior?.score))
                    .font(.clarionData(11.5))
                    .foregroundStyle(Color.ink3)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.ink4)
            }
            .padding(.horizontal, Brand.s4)
            .padding(.vertical, Brand.s3)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(openingWeb)
    }

    // MARK: - Trends locked

    private var trendsLockedCard: some View {
        (Text("Trends unlock with your second panel. ").bold()
            + Text("Once any marker appears on two draws, this page shows its line over time — the proof your supplements and habits are working."))
            .font(.clarionBody(13.5))
            .foregroundStyle(Color.ink2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Brand.s4)
            .clarionCardQuiet()
    }

    // MARK: - Featured journey

    private func journeyCard(_ journey: LabJourney, all: [LabJourney]) -> some View {
        VStack(alignment: .leading, spacing: Brand.s4) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(journey.displayName)
                        .font(.clarionDisplay(18))
                        .tracking(-0.015 * 18)
                        .foregroundStyle(Color.ink)
                    let draws = "\(journey.points.count) draw\(journey.points.count == 1 ? "" : "s")"
                    let span = LabsLabels.journeySpanLabel(journey.points).map { " · \($0)" } ?? ""
                    Text("\(draws)\(span)")
                        .font(.clarionBody(12))
                        .foregroundStyle(Color.ink3)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(journey.lastPoint.map { LabsLabels.fmtValue($0.value) } ?? "—")
                            .font(.clarionData(20))
                            .foregroundStyle(Color.ink)
                        if let unit = journey.unit, !unit.isEmpty {
                            Text(unit)
                                .font(.clarionData(12))
                                .foregroundStyle(Color.ink3)
                        }
                    }
                    Text(LabsLabels.journeyDeltaLabel(journey.points, improved: journey.improved))
                        .font(.clarionData(11.5))
                        .foregroundStyle(journey.improved == false ? Color.clay : Color.forest)
                }
            }

            markerChips(featured: journey, all: all)

            JourneyChart(journey: journey)

            let labels = LabsLabels.axisLabels(journey.points)
            if !labels.isEmpty {
                HStack {
                    ForEach(Array(labels.enumerated()), id: \.offset) { i, label in
                        if i > 0 { Spacer() }
                        Text(label)
                            .font(.clarionData(10))
                            .foregroundStyle(Color.ink4)
                    }
                }
            }
        }
        .padding(Brand.s4 + 2)
        .clarionCard()
    }

    /// The top-ranked markers as inline chips (MAX_VISIBLE_CHIPS = 5, matching the
    /// web); the active choice is always visible; the rest live in "All markers".
    private func markerChips(featured: LabJourney, all: [LabJourney]) -> some View {
        var chips = Array(all.prefix(5))
        if !chips.contains(where: { $0.markerKey == featured.markerKey }) {
            chips.append(featured)
        }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Brand.s2) {
                ForEach(chips) { j in
                    chip(j.displayName, active: j.markerKey == featured.markerKey) {
                        activeMarker = j.markerKey
                    }
                }
                if all.count > chips.count {
                    chip("All markers · \(all.count)", active: false) {
                        markerPickerShown = true
                    }
                }
            }
        }
    }

    private func chip(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
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

    // MARK: - Movers

    @ViewBuilder
    private func moversSection(_ r: LabsHistoryResponse) -> some View {
        let tiles = r.movers.markerKeys.compactMap { key in
            r.journeys.first { $0.markerKey == key }
        }
        if !tiles.isEmpty || r.movers.steadyCount > 0 {
            VStack(alignment: .leading, spacing: Brand.s3) {
                sectionLabel(tiles.count >= 2 ? "Biggest movers since your last draw" : "Since your last draw")

                if tiles.count < 2 && r.movers.steadyCount > 0 {
                    let n = r.movers.steadyCount
                    Text(tiles.count == 1
                         ? "Mostly steady — \(n) marker\(n == 1 ? "" : "s") unchanged since your previous draw."
                         : "All steady — \(n) marker\(n == 1 ? "" : "s") held within 2% of your previous draw.")
                        .font(.clarionBody(13))
                        .foregroundStyle(Color.ink3)
                }

                if !tiles.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: Brand.s3), GridItem(.flexible())], spacing: Brand.s3) {
                        ForEach(tiles) { journey in
                            moverTile(journey)
                        }
                    }
                }
            }
        }
    }

    private func moverTile(_ journey: LabJourney) -> some View {
        let trend = LabsLabels.trendTileLabel(journey)
        return Button {
            activeMarker = journey.markerKey
        } label: {
            VStack(alignment: .leading, spacing: Brand.s2) {
                Text(journey.displayName)
                    .font(.clarionLabel(12))
                    .foregroundStyle(Color.ink2)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(journey.lastPoint.map { LabsLabels.fmtValue($0.value) } ?? "—")
                        .font(.clarionData(17))
                        .foregroundStyle(trend.valueMuted ? Color.clay : Color.ink)
                    Text(trend.label)
                        .font(.clarionData(10.5))
                        .foregroundStyle(trendColor(trend.trendClass))
                }
                MoverSparkline(journey: journey, trendClass: trend.trendClass)
            }
            .padding(Brand.s3 + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clarionCard(cornerRadius: Brand.r)
        }
        .buttonStyle(PressableStyle())
    }

    private func trendColor(_ trendClass: LabsLabels.TrendClass) -> Color {
        switch trendClass {
        case .up: return .forest
        case .down: return .clay
        case .flat: return .ink3
        }
    }

    // MARK: - Empty / error

    private var emptyState: some View {
        VStack(spacing: Brand.s4) {
            Image(systemName: "testtube.2")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.ink3)
                .padding(.top, Brand.s8)
            Text("Start your lab history")
                .font(.clarionDisplay(22))
                .tracking(-0.015 * 22)
                .foregroundStyle(Color.ink)
            Text("Upload a PDF or photo, or enter values manually. Clarion keeps every panel so retests build a real journey.")
                .font(.clarionBody(14.5))
                .foregroundStyle(Color.ink2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            VStack(spacing: Brand.s3) {
                Button("Upload labs") { openWeb("/labs/upload") }
                    .buttonStyle(PrimaryButtonStyle())
                Button("Enter manually") { openWeb("/labs/upload?mode=manual") }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.horizontal, Brand.s7)
            .disabled(openingWeb)
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

    // MARK: - Bits

    private func sectionLabel(_ text: String) -> some View {
        Eyebrow(text)
    }

    private func openWeb(_ path: String) {
        Task {
            openingWeb = true
            defer { openingWeb = false }
            await LibraryWeb.open(path: path, auth: auth)
        }
    }
}

// MARK: - All-markers picker

/// Searchable marker list — the web's "All markers" menu (search appears past 8).
private struct MarkerPickerSheet: View {
    let journeys: [LabJourney]
    let activeKey: String?
    let onSelect: (String) -> Void

    @State private var search = ""
    @Environment(\.dismiss) private var dismiss

    private var filtered: [LabJourney] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return journeys }
        return journeys.filter { $0.displayName.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                if journeys.count > 8 {
                    TextField("Search markers…", text: $search)
                        .font(.clarionBody(15))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                if filtered.isEmpty {
                    Text("No markers match “\(search)”.")
                        .font(.clarionBody(13.5))
                        .foregroundStyle(Color.ink3)
                } else {
                    ForEach(filtered) { j in
                        Button {
                            onSelect(j.markerKey)
                        } label: {
                            HStack {
                                Text(j.displayName)
                                    .font(.clarionBody(15))
                                    .foregroundStyle(Color.ink)
                                Spacer()
                                Text("\(j.points.count) draw\(j.points.count == 1 ? "" : "s")")
                                    .font(.clarionData(12))
                                    .foregroundStyle(Color.ink3)
                                if j.markerKey == activeKey {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Color.forest)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("All markers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
