import SwiftUI

/// The native shop — the web's lab-tuned storefront (ShopHandoff.tsx) told the same way:
///  - hero: "Shop." + the tuned-to-your-labs promise
///  - filter chips (All / Backed by your labs / Maintenance / Browse everything)
///  - a shelf per bucket with the web's SECTION_HEAD_COPY and a 2-col card grid
///  - tapping a card opens the Clarion Pick sheet (hero + alternatives + buy)
/// Everything is server-computed by GET /api/shop — no bucketing/verdict logic lives here.
struct ShopView: View {
    @StateObject private var store: ShopStore
    @State private var filter: ShopFilter = .all
    @State private var presented: ShopCard?
    @State private var deepLinkConsumed = false

    /// Deep-link target — web parity with /dashboard/shop?preset=<id>: the matching
    /// card's pick sheet opens once the catalog loads.
    private let deepLinkPresetId: String?

    init(auth: SupabaseAuth, presetId: String? = nil) {
        _store = StateObject(wrappedValue: ShopStore(auth: auth))
        deepLinkPresetId = presetId
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                switch store.state {
                case .loading:
                    ClarionLoadingView()
                case .empty:
                    empty("The shop catalog isn't available yet — check back soon.")
                case .error(let m):
                    empty(m)
                case .ready(let r):
                    content(r)
                }
            }
            .contentMargins(.bottom, 96, for: .scrollContent)
            .background(Color.paper.ignoresSafeArea())
            // The in-content serif "Shop." hero IS the display title (web parity); the
            // nav bar stays inline so the tab doesn't say Shop twice.
            .navigationTitle("Shop")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                await store.load()
            }
        }
        .sheet(item: $presented) { card in
            PickSheet(card: card)
        }
        .task {
            if case .loading = store.state { await store.load() }
            consumeDeepLink()
        }
    }

    /// Open the deep-linked preset's pick sheet exactly once, after the catalog lands.
    private func consumeDeepLink() {
        guard !deepLinkConsumed, let pid = deepLinkPresetId,
              case .ready(let r) = store.state,
              let card = r.cards.first(where: { $0.presetId == pid }) else { return }
        deepLinkConsumed = true
        presented = card
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ r: ShopResponse) -> some View {
        let backed = r.cards.filter { $0.bucketKind == .backed }
        let maintenance = r.cards.filter { $0.bucketKind == .maintenance }
        let skip = r.cards.filter { $0.bucketKind == .skip }

        VStack(alignment: .leading, spacing: Brand.s5) {
            hero(hasLabs: r.hasLabs).entrance(0)
            filterChips.entrance(1)
            section(.backed, cards: backed, hasLabs: r.hasLabs, index: 2)
            section(.maintenance, cards: maintenance, hasLabs: r.hasLabs, index: 3)
            section(.skip, cards: skip, hasLabs: r.hasLabs, index: 4)

            Text("Educational, not medical advice. Discuss changes with your clinician.")
                .font(.clarionBody(12))
                .foregroundStyle(Color.ink4)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.top, Brand.s1)
        }
        .padding(Brand.s5)
    }

    // MARK: - Hero

    private func hero(hasLabs: Bool) -> some View {
        VStack(alignment: .leading, spacing: Brand.s2) {
            Text("Shop.")
                .font(.clarionDisplay(30))
                .tracking(-0.015 * 30)
                .foregroundStyle(Color.ink)
            Text(
                hasLabs
                    ? "Tuned to your labs. **What your results actually call for is marked** — everything else is clearly optional, so you only buy what earns its place."
                    : "Upload labs to see what's **backed by your results** — until then, browse with clear optional vs skip labels."
            )
            .font(.clarionBody(14.5))
            .foregroundStyle(Color.ink2)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Filters

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Brand.s2) {
                ForEach(ShopFilter.allCases, id: \.self) { f in
                    let active = filter == f
                    Button {
                        Haptics.tap()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { filter = f }
                    } label: {
                        Text(f.label)
                            .font(.clarionLabel(13))
                            .foregroundStyle(active ? Color.white : Color.ink2)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(active ? Color.forest : Color.surface, in: Capsule())
                            .overlay(Capsule().stroke(active ? Color.clear : Color.line2))
                    }
                    .buttonStyle(PressableStyle(haptic: false))
                }
            }
            .padding(.horizontal, Brand.s5)
        }
        .padding(.horizontal, -Brand.s5) // bleed the scroller to the screen edges
    }

    // MARK: - Shelves

    private let columns = [
        GridItem(.flexible(), spacing: Brand.s3, alignment: .top),
        GridItem(.flexible(), spacing: Brand.s3, alignment: .top),
    ]

    @ViewBuilder
    private func section(_ bucket: ShopBucket, cards: [ShopCard], hasLabs: Bool, index: Int) -> some View {
        // Same visibility rules as the web: a filtered-out bucket disappears entirely;
        // an empty bucket only shows its empty line under the filter that asked for it.
        if filter.shows(bucket) && (!cards.isEmpty || filter.showsEmpty(for: bucket)) {
            VStack(alignment: .leading, spacing: Brand.s3) {
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow(bucket.title, color: bucket == .backed ? .forestInk : .ink3)
                    Text(bucket.desc)
                        .font(.clarionBody(12.5))
                        .foregroundStyle(Color.ink3)
                }

                if cards.isEmpty {
                    Text(bucket.emptyLine(hasLabs: hasLabs))
                        .font(.clarionBody(13))
                        .foregroundStyle(Color.ink3)
                        .padding(.vertical, Brand.s2)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: Brand.s3) {
                        ForEach(cards) { card in
                            Button {
                                Haptics.tap()
                                presented = card
                            } label: {
                                ShopProductCard(card: card)
                            }
                            .buttonStyle(PressableStyle(haptic: false))
                        }
                    }
                }
            }
            .entrance(index)
        }
    }

    private func empty(_ m: String) -> some View {
        VStack(spacing: Brand.s3) {
            Image(systemName: "bag.fill").font(.largeTitle).foregroundStyle(Color.forest)
            Text(m).font(.clarionBody(15)).foregroundStyle(Color.ink3).multilineTextAlignment(.center)
        }
        .padding(40)
    }
}

// MARK: - Filter semantics

/// The web's four filter chips (ShopHandoff.tsx). Visibility mirrors the web exactly:
/// All and Browse show every bucket; Labs/Maintenance isolate one shelf. Empty lines
/// only render for the shelf a filter explicitly asked for (or all of them on Browse).
private enum ShopFilter: CaseIterable {
    case all, labs, maint, browse

    var label: String {
        switch self {
        case .all: return "All"
        case .labs: return "Backed by your labs"
        case .maint: return "Maintenance"
        case .browse: return "Browse everything"
        }
    }

    func shows(_ bucket: ShopBucket) -> Bool {
        switch self {
        case .all, .browse: return true
        case .labs: return bucket == .backed
        case .maint: return bucket == .maintenance
        }
    }

    func showsEmpty(for bucket: ShopBucket) -> Bool {
        switch self {
        case .browse: return true
        case .labs: return bucket == .backed
        case .maint: return bucket == .maintenance
        case .all: return false
        }
    }
}

// MARK: - Product card

/// One grid card — the web's ProductCard: flag tag, bottle art, serif name, data-voice
/// dose, quality cue, verdict reason chip + text, and the $X/mo footer. Tap opens the
/// pick sheet; there is no inline buy on the card.
private struct ShopProductCard: View {
    let card: ShopCard

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.s2) {
            flagPill

            BottleArt(presetId: card.presetId)
                .frame(height: 72)
                .frame(maxWidth: .infinity)

            Text(card.displayName)
                .font(.clarionDisplay(15))
                .tracking(-0.015 * 15)
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let dose = card.hero?.dose {
                Text(dose)
                    .font(.clarionData(11))
                    .foregroundStyle(Color.ink3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            HStack(spacing: 4) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.forest)
                Text(card.qualityCue)
                    .font(.clarionBody(11))
                    .foregroundStyle(Color.ink3)
                    .lineLimit(1)
            }

            if let reason = card.reason {
                VStack(alignment: .leading, spacing: 4) {
                    if let chip = reason.chip {
                        Text(chip)
                            .font(.clarionData(10.5))
                            .foregroundStyle(Color.ink2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.paperDim, in: Capsule())
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Text(reason.text)
                        .font(.clarionBody(11.5))
                        .foregroundStyle(Color.ink2)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(card.monthlyLabel)
                    .font(.clarionData(15))
                    .foregroundStyle(Color.ink)
                Text("/mo")
                    .font(.clarionData(11))
                    .foregroundStyle(Color.ink3)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.ink4)
            }
            .padding(.top, 2)
        }
        .padding(Brand.s4)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .clarionCard()
    }

    /// The web's flag tags, tone-for-tone from ds.css: for-you = forest need chip,
    /// pairs-well + skip = quiet neutrals, optional = amber. Skip stays muted (NOT clay —
    /// clay is rationed for flagged results, and "skip" is an absence of signal).
    private var flagPill: some View {
        switch card.flag {
        case "for-you": return TagPill(card.flagLabel, tone: .forest, wash: .forestWash)
        case "pairs-well": return TagPill(card.flagLabel, tone: .ink2, wash: .paperDim)
        case "optional": return TagPill(card.flagLabel, tone: .amber, wash: .amberWash)
        default: return TagPill(card.flagLabel, tone: .ink3, wash: .paperDim)
        }
    }
}

// MARK: - Bottle art

/// The web's photoreal bottle art (/public/bottles/*.png), reused over the wire from the
/// production origin. Presets without a dedicated bottle get the generic capsule jar, and
/// anything offline (UITEST screenshots included) falls back to a drawn Clarion bottle.
struct BottleArt: View {
    let presetId: String

    /// Mirror of the web's PRESET_IMAGE map (ClarionBottle.tsx).
    private static let presetImage: [String: String] = [
        "vitamin_c": "vitamin-c",
        "vitamin_d": "vitamin-d",
        "b12": "b12",
        "magnesium": "magnesium",
        "zinc": "zinc",
        "folate": "folate",
        "coq10": "coq10",
        "omega3": "omega3",
        "iron": "iron",
        "beta_alanine": "beta-alanine",
    ]

    private var url: URL {
        let name = Self.presetImage[presetId] ?? "generic-capsule"
        return Config.apiBase.appendingPathComponent("bottles/\(name).png")
    }

    var body: some View {
        AsyncImage(url: url) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFit()
            } else {
                DrawnBottle()
            }
        }
    }
}

/// Fallback bottle glyph — cap, jar, and a forest-wash label band, all token colors.
private struct DrawnBottle: View {
    var body: some View {
        GeometryReader { geo in
            let w = min(geo.size.width * 0.56, geo.size.height * 0.62)
            let h = geo.size.height
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.forestDeep)
                    .frame(width: w * 0.46, height: h * 0.16)
                RoundedRectangle(cornerRadius: w * 0.18)
                    .fill(Color.surface2)
                    .overlay(RoundedRectangle(cornerRadius: w * 0.18).stroke(Color.line2))
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.forestWash)
                            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.line))
                            .frame(width: w * 0.68, height: h * 0.34)
                    )
                    .frame(width: w, height: h * 0.78)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
