import Foundation
import SwiftUI

/// Loads GET /api/shop?platform=ios — the server-computed shop catalog. Same shape as
/// ReportStore: one @Published state, load() carries the Supabase bearer, DEBUG demo
/// under the UITEST screenshot harness.
@MainActor
final class ShopStore: ObservableObject {
    enum State {
        case loading
        case ready(ShopResponse)
        case empty            // signed in, no catalog yet
        case error(String)
    }

    @Published private(set) var state: State = .loading
    private let auth: SupabaseAuth

    init(auth: SupabaseAuth) { self.auth = auth }

    func load() async {
        do {
            let token = try await auth.validAccessToken()
            var comps = URLComponents(
                url: Config.apiBase.appendingPathComponent("api/shop"),
                resolvingAgainstBaseURL: false
            )
            comps?.queryItems = [URLQueryItem(name: "platform", value: "ios")]
            guard let url = comps?.url else { throw URLError(.badURL) }
            var req = URLRequest(url: url)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            // Prod main can lag the branch that ships GET /api/shop — a 404 means
            // "not rolled out yet", not a failure worth a retry prompt.
            if http.statusCode == 404 {
                state = .error("The Shop update is still rolling out — check back soon.")
                return
            }
            guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
            let decoded = try JSONDecoder().decode(ShopResponse.self, from: data)
            state = decoded.cards.isEmpty ? .empty : .ready(decoded)
        } catch {
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if args.contains("UITEST_VITALS") || args.contains("UITEST_SHOP") {
                state = .ready(ShopStore.demo)
                return
            }
            #endif
            state = .error("Couldn't load the shop. Pull to retry.")
        }
    }

    #if DEBUG
    /// Demo catalog for the screenshot harness — same persona as ReportStore.demo
    /// (female endurance athlete, ferritin 34): two lab-backed picks, a pairing,
    /// a maintenance staple, and a suppressed accumulator to show the ghost CTA.
    private static func demoBuy(_ presetId: String, asin: String) -> ShopBuy {
        ShopBuy(
            provider: "amazon",
            mode: "external_link",
            label: "Buy on Amazon",
            url: "https://clarionlabs.tech/go/amazon?asin=\(asin)&src=ios_shop_\(presetId)",
            presetId: presetId,
            external: true,
            fulfillmentNote: "Opens on Amazon · Clarion may earn a commission"
        )
    }

    static let demo = ShopResponse(
        hasLabs: true,
        cards: [
            ShopCard(
                presetId: "iron",
                displayName: "Iron",
                category: "mineral",
                overview: "Iron rebuilds ferritin — the oxygen-carrying reserve endurance training drains. Low stores blunt recovery and performance long before anemia shows.",
                caution: "Take away from coffee and tea. Don't supplement above a ferritin of 150 without clinician guidance — iron accumulates.",
                bucket: "backed",
                flag: "for-you",
                status: "priority",
                monthlyUsd: 13,
                reason: ShopReason(
                    text: "Your ferritin (34) is below the endurance floor of 50 — repletion supports oxygen transport and recovery.",
                    chip: "34 ng/mL · below your 50–150 target"
                ),
                warning: ShopWarning(
                    level: "lab_priority",
                    label: "Lab priority",
                    detail: "Your latest labs support buying this — still confirm dose with your clinician if unsure.",
                    suppressPurchase: false
                ),
                labGap: ShopLabGap(
                    markerName: "Ferritin", value: 34, targetMin: 50, targetMax: 150,
                    direction: "below", clause: "below your 50–150 target",
                    retest: "Retest in 8–10 weeks"
                ),
                options: [
                    ShopOption(
                        id: "hero", isHero: true, tierLabel: "Clarion Pick · best overall",
                        brand: "Thorne", productName: "Iron Bisglycinate",
                        dose: "25 mg elemental per capsule", priceLabel: "~$13",
                        why: "Chelated bisglycinate absorbs well without the GI upset of sulfate forms.",
                        qualityMarks: ["Third-party tested", "Gentle on the gut"],
                        asin: "B0797H79JG", buy: demoBuy("iron", asin: "B0797H79JG")
                    ),
                    ShopOption(
                        id: "alt-0", isHero: false, tierLabel: "Lower cost",
                        brand: "Nature Made", productName: "Iron 65 mg",
                        dose: "65 mg per tablet", priceLabel: "~$8",
                        why: nil, qualityMarks: ["USP verified"],
                        asin: "B00008I8NJ", buy: demoBuy("iron", asin: "B00008I8NJ")
                    ),
                    ShopOption(
                        id: "alt-1", isHero: false, tierLabel: "Liquid",
                        brand: "Floradix", productName: "Iron + Herbs",
                        dose: "10 mL twice daily", priceLabel: "~$24",
                        why: nil, qualityMarks: [],
                        asin: "B00014DAOG", buy: demoBuy("iron", asin: "B00014DAOG")
                    ),
                ]
            ),
            ShopCard(
                presetId: "vitamin_d",
                displayName: "Vitamin D3",
                category: "vitamin",
                overview: "Vitamin D supports bone density, immune resilience, and mood. Most indoor-training athletes run low through winter.",
                caution: "High-dose D (10,000 IU+) should be clinician-supervised.",
                bucket: "backed",
                flag: "for-you",
                status: "priority",
                monthlyUsd: 11,
                reason: ShopReason(
                    text: "Nudges your 28 ng/mL into the 30–50 optimal band.",
                    chip: "28 ng/mL · below your 30–50 target"
                ),
                warning: ShopWarning(
                    level: "lab_priority",
                    label: "Lab priority",
                    detail: "Your latest labs support buying this — still confirm dose with your clinician if unsure.",
                    suppressPurchase: false
                ),
                labGap: ShopLabGap(
                    markerName: "Vitamin D", value: 28, targetMin: 30, targetMax: 50,
                    direction: "below", clause: "below your 30–50 target",
                    retest: "Retest in 8–12 weeks"
                ),
                options: [
                    ShopOption(
                        id: "hero", isHero: true, tierLabel: "Clarion Pick · best overall",
                        brand: "Sports Research", productName: "Vitamin D3 + K2",
                        dose: "5,000 IU D3 + 100 mcg K2", priceLabel: "~$11",
                        why: "Pairs D3 with K2 so the calcium it mobilizes lands in bone, not arteries.",
                        qualityMarks: ["Third-party tested", "Coconut-oil base"],
                        asin: "B01N0XJ9SP", buy: demoBuy("vitamin_d", asin: "B01N0XJ9SP")
                    ),
                    ShopOption(
                        id: "alt-0", isHero: false, tierLabel: "Lower cost",
                        brand: "NOW", productName: "Vitamin D3 2,000 IU",
                        dose: "2,000 IU per softgel", priceLabel: "~$6",
                        why: nil, qualityMarks: [],
                        asin: "B003FQF3JY", buy: demoBuy("vitamin_d", asin: "B003FQF3JY")
                    ),
                ]
            ),
            ShopCard(
                presetId: "vitamin_c",
                displayName: "Vitamin C",
                category: "vitamin",
                overview: "Ascorbic acid — taken with iron-rich meals it multiplies non-heme iron absorption, which is why it rides along with an iron protocol.",
                caution: nil,
                bucket: "maintenance",
                flag: "pairs-well",
                status: "unknown",
                monthlyUsd: 7,
                reason: nil,
                warning: ShopWarning(
                    level: "optional",
                    label: "Optional / not currently needed",
                    detail: "Your labs don't flag this as urgent — buying is optional.",
                    suppressPurchase: false
                ),
                labGap: nil,
                options: [
                    ShopOption(
                        id: "hero", isHero: true, tierLabel: "Clarion Pick · best overall",
                        brand: "NOW", productName: "Vitamin C-1000",
                        dose: "1,000 mg per tablet", priceLabel: "~$7",
                        why: "Simple, clean C — take alongside your iron dose to boost absorption.",
                        qualityMarks: ["GMP certified"],
                        asin: "B0000CFO4H", buy: demoBuy("vitamin_c", asin: "B0000CFO4H")
                    ),
                ]
            ),
            ShopCard(
                presetId: "magnesium",
                displayName: "Magnesium",
                category: "mineral",
                overview: "The workhorse mineral behind sleep quality, muscle relaxation, and 300+ enzymatic reactions — a reasonable staple for heavy training blocks.",
                caution: nil,
                bucket: "maintenance",
                flag: "optional",
                status: "maintenance",
                monthlyUsd: 9,
                reason: nil,
                warning: ShopWarning(
                    level: "optional",
                    label: "Optional / not currently needed",
                    detail: "Your labs don't flag this as urgent — buying is optional.",
                    suppressPurchase: false
                ),
                labGap: ShopLabGap(
                    markerName: "Magnesium", value: 2.1, targetMin: 1.9, targetMax: 2.4,
                    direction: "in_band", clause: "in your 1.9–2.4 target",
                    retest: nil
                ),
                options: [
                    ShopOption(
                        id: "hero", isHero: true, tierLabel: "Clarion Pick · best overall",
                        brand: "Pure Encapsulations", productName: "Magnesium Glycinate",
                        dose: "120 mg per capsule", priceLabel: "~$9",
                        why: "Glycinate is the form that supports sleep without the laxative effect of oxide.",
                        qualityMarks: ["Third-party tested", "Hypoallergenic"],
                        asin: "B0016QTC0G", buy: demoBuy("magnesium", asin: "B0016QTC0G")
                    ),
                    ShopOption(
                        id: "alt-0", isHero: false, tierLabel: "Lower cost",
                        brand: "Nature Made", productName: "Magnesium Oxide 250 mg",
                        dose: "250 mg per tablet", priceLabel: "~$5",
                        why: nil, qualityMarks: ["USP verified"],
                        asin: "B00012NGIU", buy: demoBuy("magnesium", asin: "B00012NGIU")
                    ),
                ]
            ),
            ShopCard(
                presetId: "zinc",
                displayName: "Zinc",
                category: "mineral",
                overview: "Immune and hormone support — but zinc competes with copper and builds up, so it only earns a place when labs actually ask for it.",
                caution: "Sustained doses above 40 mg/day deplete copper.",
                bucket: "skip",
                flag: "skip",
                status: "optimal",
                monthlyUsd: 8,
                reason: nil,
                warning: ShopWarning(
                    level: "likely_unnecessary",
                    label: "Not recommended at your levels",
                    detail: "Your numbers look good and this one builds up in the body — adding more can do harm, not just waste money. Skip unless your clinician says otherwise.",
                    suppressPurchase: true
                ),
                labGap: ShopLabGap(
                    markerName: "Zinc", value: 95, targetMin: 80, targetMax: 120,
                    direction: "in_band", clause: "in your 80–120 target",
                    retest: nil
                ),
                options: [
                    ShopOption(
                        id: "hero", isHero: true, tierLabel: "Clarion Pick · best overall",
                        brand: "Thorne", productName: "Zinc Picolinate",
                        dose: "15 mg per capsule", priceLabel: "~$8",
                        why: "Picolinate is the best-absorbed form at a sensible maintenance dose.",
                        qualityMarks: ["Third-party tested"],
                        asin: "B0797JZ9WK", buy: demoBuy("zinc", asin: "B0797JZ9WK")
                    ),
                ]
            ),
            ShopCard(
                presetId: "omega3",
                displayName: "Omega-3 (EPA/DHA)",
                category: "fatty-acid",
                overview: "Marine omega-3s support cardiovascular health and recovery — the case is strongest when triglycerides or inflammation markers are elevated.",
                caution: nil,
                bucket: "skip",
                flag: "skip",
                status: "unknown",
                monthlyUsd: 21,
                reason: nil,
                warning: ShopWarning(
                    level: "optional",
                    label: "Optional / not currently needed",
                    detail: "Your labs don't flag this as urgent — buying is optional.",
                    suppressPurchase: false
                ),
                labGap: nil,
                options: [
                    ShopOption(
                        id: "hero", isHero: true, tierLabel: "Clarion Pick · best overall",
                        brand: "Nordic Naturals", productName: "Ultimate Omega",
                        dose: "1,280 mg omega-3 per serving", priceLabel: "~$21",
                        why: "Concentrated triglyceride-form fish oil with clean third-party oxidation testing.",
                        qualityMarks: ["Third-party tested", "Triglyceride form"],
                        asin: "B002CQU564", buy: demoBuy("omega3", asin: "B002CQU564")
                    ),
                ]
            ),
        ]
    )
    #endif
}
