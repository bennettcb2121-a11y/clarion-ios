import Foundation

/// Home "one sheet" helpers — a faithful port of the web's src/lib/homeSheet.ts:
/// the one-line reason under each dose ("Vitamin D 19 · aim for 30+") and the weekly
/// research note matched to the person's own flagged markers.
///
/// Do-no-harm: a dose only gets a reason when a real lab value backs it; the weekly note only
/// shows when a flagged marker matches a note whose source we cite. No match → nothing renders.
enum HomeSheet {

    // MARK: - Supplement → marker

    /// Supplement preset → the marker it is taken for (web PRESET_MARKER).
    private static let presetMarker: [String: String] = [
        "vitamin_d": #"^vitamin d\b|25-?oh"#,
        "iron": #"ferritin"#,
        "magnesium": #"magnesium"#,
        "b12": #"\bb-?12\b|cobalamin"#,
        "folate": #"folate|folic"#,
        "zinc": #"^zinc"#,
    ]

    private static let flagged: Set<String> = ["deficient", "low", "suboptimal", "high"]

    /// Case-insensitive regex test (JS `/…/i.test`).
    static func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// "Vitamin D (25-OH)" → "Vitamin D" (web shortName).
    static func shortName(_ name: String) -> String {
        name.replacingOccurrences(of: #"\s*\(.*?\)\s*"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Integers print bare; everything else rounds to one decimal (web fmt).
    static func fmt(_ n: Double) -> String {
        if n.rounded() == n, abs(n) < 1e15 { return String(Int(n)) }
        let r = Double(MorningBrief.jsRound(n * 10)) / 10
        if r.rounded() == r { return String(Int(r)) }
        return String(r)
    }

    private static func findMarker(_ results: [BiomarkerResult], _ pattern: String) -> BiomarkerResult? {
        results.first { matches(pattern, $0.name) && $0.value.isFinite }
    }

    /// "Vitamin D 19 · aim for 30+" — nil when no lab value backs this supplement.
    static func doseReason(supplementName: String, results: [BiomarkerResult]) -> String? {
        guard let preset = SupplementPresets.resolve(supplementName),
              let pattern = presetMarker[preset],
              let m = findMarker(results, pattern)
        else { return nil }
        let head = "\(shortName(m.name)) \(fmt(m.value))"
        if let lo = m.optimalMin, m.value < lo { return "\(head) · aim for \(fmt(lo))+" }
        if let hi = m.optimalMax, m.value > hi { return "\(head) · aim under \(fmt(hi))" }
        if m.status == "optimal" { return "\(head) · in range" }
        return head
    }

    // MARK: - Weekly note

    struct WeeklyNote: Equatable {
        var marker: String
        var headline: String
        var body: String
        var source: String
    }

    /// Each note: one finding, plain words, the study it comes from (web NOTES, verbatim).
    private static let notes: [(match: String, headline: String, body: String, source: String)] = [
        (
            #"ferritin"#,
            "Coffee with a meal can cut the iron you absorb by about 40%.",
            "Have coffee before an iron-rich meal — not with it or right after.",
            "Morck et al., American Journal of Clinical Nutrition, 1983"
        ),
        (
            #"^vitamin d\b|25-?oh"#,
            "Vitamin D3 absorbs about a third better with a meal that has some fat.",
            "Take it with breakfast or dinner, not on an empty stomach.",
            "Dawson-Hughes et al., Journal of the Academy of Nutrition and Dietetics, 2015"
        ),
        (
            #"\bb-?12\b|cobalamin"#,
            "Long-term metformin use is linked to lower B12.",
            "If you take metformin, ask your doctor about checking B12 each year.",
            "de Jager et al., BMJ, 2010"
        ),
        (
            #"\bldl\b"#,
            "About 10 g a day of psyllium fiber lowered LDL by roughly 13 mg/dL in trials.",
            "Oats, beans and psyllium are the easiest food lever for LDL.",
            "Jovanovski et al., American Journal of Clinical Nutrition, 2018"
        ),
        (
            #"glucose|a1c"#,
            "In one trial, 10-minute walks after meals lowered blood sugar more than one 30-minute walk.",
            "A short walk after your biggest meals is the simplest lever.",
            "Reynolds et al., Diabetologia, 2016"
        ),
    ]

    /// Week number from a YYYY-MM-DD key parsed as UTC midnight, so the note changes once a
    /// week, not every load (web weekIndex).
    static func weekIndex(_ dateKey: String) -> Int {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let parts = dateKey.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let d = utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        else { return 0 }
        return Int(floor(d.timeIntervalSince1970 * 1000 / (7 * 86_400_000)))
    }

    /// This week's note for the person's flagged markers, or nil.
    static func pickWeeklyNote(results: [BiomarkerResult], dateKey: String) -> WeeklyNote? {
        let flaggedResults = results.filter { flagged.contains($0.status) }
        var found: [WeeklyNote] = []
        for n in notes {
            if let m = flaggedResults.first(where: { matches(n.match, $0.name) }) {
                found.append(WeeklyNote(marker: shortName(m.name), headline: n.headline, body: n.body, source: n.source))
            }
        }
        guard !found.isEmpty else { return nil }
        let i = weekIndex(dateKey) % found.count
        return found[(i + found.count) % found.count]
    }
}

/// Port of the web's resolveSupplementToPresetId (src/lib/supplementMetadata.ts): exact
/// label/alias match first, then word-boundary containment preferring the LONGEST match so
/// "magnesium glycinate" beats "magnesium" and "vitamin d" never hijacks "vitamin e".
/// Table generated from SUPPLEMENT_PRESETS — keep in sync (each row: id, [label, aliases…]).
enum SupplementPresets {
    private static func normalize(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func dashless(_ s: String) -> String {
        s.replacingOccurrences(of: #"[—–\-]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    static func resolve(_ label: String) -> String? {
        let n = normalize(label)
        guard !n.isEmpty else { return nil }
        for (id, names) in table where names.contains(where: { normalize($0) == n }) {
            return id
        }
        let padded = " \(dashless(n)) "
        var best: (id: String, len: Int)?
        for (id, names) in table {
            for cand in names {
                let cn = dashless(normalize(cand))
                if cn.count < 3 { continue }
                if padded.contains(" \(cn) ") {
                    if best == nil || cn.count > best!.len { best = (id, cn.count) }
                }
            }
        }
        return best?.id
    }

    static let table: [(String, [String])] = [
        ("vitamin_d", ["Vitamin D", "vitamin d", "vitamin d3", "vit d", "d3", "cholecalciferol"]),
        ("magnesium", ["Magnesium", "magnesium", "mg", "magnesium glycinate", "magnesium citrate", "magnesium oxide", "natural vitality calm", "calm magnesium"]),
        ("omega3", ["Omega-3 / Fish oil", "omega-3", "omega 3", "fish oil", "epa", "dha"]),
        ("iron", ["Iron", "iron", "ferrous", "ferritin support"]),
        ("zinc", ["Zinc", "zinc"]),
        ("creatine", ["Creatine", "creatine"]),
        ("protein_powder", ["Protein powder", "protein powder", "whey protein", "plant protein"]),
        ("b12", ["B12", "b12", "vitamin b12", "cobalamin"]),
        ("folate", ["Folate", "folate", "folic acid", "methylfolate", "5-mthf"]),
        ("fiber", ["Fiber", "fiber", "fibre", "psyllium"]),
        ("electrolytes", ["Electrolytes", "electrolytes", "electrolyte", "lmnt", "liquid iv", "hydration mix"]),
        ("multivitamin", ["Multivitamin", "multivitamin", "multi", "mv"]),
        ("probiotic", ["Probiotic", "probiotic", "probiotics"]),
        ("calcium", ["Calcium", "calcium", "calcium citrate", "calcium carbonate"]),
        ("potassium", ["Potassium", "potassium", "potassium chloride", "potassium gluconate"]),
        ("selenium", ["Selenium", "selenium"]),
        ("iodine", ["Iodine", "iodine", "kelp"]),
        ("chromium", ["Chromium", "chromium", "chromium picolinate"]),
        ("vitamin_c", ["Vitamin C", "vitamin c", "vit c", "ascorbic acid", "ascorbate", "ester-c", "ester c", "emergen-c", "emergen c", "buffered c", "liposomal c"]),
        ("vitamin_k2", ["Vitamin K2", "vitamin k2", "k2", "mk-7", "mk7", "menaquinone"]),
        ("vitamin_e", ["Vitamin E", "vitamin e", "tocopherol"]),
        ("biotin", ["Biotin", "biotin", "b7", "vitamin b7"]),
        ("b_complex", ["B-complex", "b complex", "b-complex", "b complex vitamins", "b vitamins"]),
        ("coq10", ["CoQ10", "coq10", "coenzyme q10", "ubiquinol", "ubiquinone"]),
        ("collagen", ["Collagen", "collagen", "collagen peptides", "collagen powder"]),
        ("melatonin", ["Melatonin", "melatonin"]),
        ("ashwagandha", ["Ashwagandha", "ashwagandha"]),
        ("turmeric", ["Turmeric / Curcumin", "turmeric", "curcumin", "curcuma"]),
        ("l_theanine", ["L-Theanine", "theanine", "l-theanine", "l theanine"]),
        ("bcaa", ["BCAAs", "bcaa", "bcaas", "branched chain amino acids"]),
        ("glutamine", ["L-Glutamine", "glutamine", "l-glutamine", "l glutamine"]),
        ("beta_alanine", ["Beta-alanine", "beta alanine", "beta-alanine"]),
        ("citrulline", ["Citrulline", "citrulline", "l-citrulline", "l citrulline"]),
        ("nac", ["NAC", "nac", "n-acetylcysteine", "n acetyl cysteine"]),
        ("berberine", ["Berberine", "berberine"]),
        ("prenatal", ["Prenatal multivitamin", "prenatal", "prenatal vitamin", "prenatal multi"]),
        ("greens_powder", ["Greens powder", "greens powder", "green powder", "supergreens"]),
        ("gaba", ["GABA", "gaba", "gamma aminobutyric acid", "gamma-aminobutyric acid", "pharma gaba", "pharmagaba"]),
        ("nad_precursor", ["NAD+ booster", "nad booster", "nad+", "nad+ precursor (nr / nmn)", "niagen", "nicotinamide mononucleotide", "nicotinamide riboside", "nmn", "tru niagen", "nr"]),
        ("hyaluronic_acid", ["Hyaluronic acid", "hyabest", "hyaluronan", "hyaluronic acid", "hyaluronic acid (oral)", "injuv", "sodium hyaluronate"]),
        ("garlic", ["Garlic", "aged garlic extract", "allicin", "garlic", "garlic (aged garlic extract)", "garlic extract", "garlic pills", "garlique", "kyolic", "odorless garlic"]),
        ("vitamin_b6", ["Vitamin B6", "b-6", "p-5-p", "p5p", "pyridoxal 5'-phosphate", "pyridoxal phosphate", "pyridoxine", "pyridoxine hcl", "vit b6", "vitamin b6", "b6"]),
        ("tart_cherry", ["Tart cherry", "cherry extract", "cherrypure", "montmorency", "montmorency cherry", "sour cherry", "tart cherries", "tart cherry", "tart cherry juice"]),
        ("glucosamine_chondroitin", ["Glucosamine & Chondroitin", "chondroitin", "chondroitin sulfate", "cosamin", "cosamin ds", "glucosamine", "glucosamine + chondroitin", "glucosamine chondroitin", "glucosamine hcl", "glucosamine sulfate", "move free", "triple flex", "tripleflex"]),
        ("rhodiola", ["Rhodiola rosea", "arctic root", "golden root", "rhodiola", "rhodiola rosea", "rosavins", "roseroot", "salidroside", "shr-5"]),
        ("saw_palmetto", ["Saw Palmetto", "palmettoguard", "permixon", "sabal", "saw palmeto", "saw palmetto", "serenoa", "serenoa repens"]),
        ("ginkgo", ["Ginkgo biloba", "egb 761", "egb761", "gingko", "ginkgo", "ginkgo biloba", "ginkgold", "ginko", "maidenhair tree", "tebonin"]),
        ("ginger", ["Ginger root", "ginger", "ginger capsules", "ginger extract", "ginger root", "gingerol", "gingerols", "zingiber", "zingiber officinale"]),
        ("copper", ["Copper", "chelated copper", "copper", "copper bisglycinate", "copper citrate", "copper gluconate", "copper glycinate", "zinc and copper"]),
        ("colostrum", ["Colostrum", "armra", "bovine colostrum", "colostrum", "colostrum powder", "colostrum-ld"]),
        ("elderberry", ["Black elderberry (Sambucus nigra)", "black elderberry", "elder berry", "elderberry", "elderberry gummies", "elderberry syrup", "sambucol", "sambucus", "sambucus nigra"]),
        ("maca", ["Maca root (Lepidium meyenii)", "black maca", "gelatinized maca", "lepidium meyenii", "maca", "maca powder", "maca root", "peruvian ginseng", "red maca"]),
        ("cranberry", ["Cranberry extract (PACs)", "azo cranberry", "cranberry", "cranberry extract", "cranberry pills", "ellura", "pacran", "proanthocyanidins", "theracran"]),
        ("ginseng", ["Panax ginseng (Asian / Korean red ginseng)", "asian ginseng", "cheong kwan jang", "g115", "ginsana", "ginseng", "ginseng (panax)", "ginsenosides", "jung kwan jang", "korean ginseng", "korean red ginseng", "panax ginseng", "red ginseng"]),
        ("red_yeast_rice", ["Red yeast rice (Monascus purpureus)", "beni-koji", "monacolin k", "monascus", "monascus purpureus", "red yeast rice", "ryr"]),
        ("boron", ["Boron", "boroganic glycine", "boron", "boron citrate", "boron for testosterone", "boron glycinate", "bororganic", "calcium fructoborate"]),
        ("digestive_enzymes", ["Digestive enzymes (broad-spectrum)", "digest gold", "digestive enzymes", "lactase", "pancreatin", "super enzymes"]),
        ("apple_cider_vinegar", ["Apple cider vinegar (liquid)", "acetic acid", "acv", "acv gummies", "apple cider vinegar", "apple cider vinegar pills", "bragg", "braggs", "cider vinegar"]),
        ("quercetin", ["Quercetin", "onion flavonoid", "quercefit", "quercetin", "quercetin bromelain", "quercetin dihydrate", "quercetin phytosome"]),
        ("lutein_zeaxanthin", ["Lutein + zeaxanthin", "areds2", "floraglo", "lutein", "lutein & zeaxanthin", "lutein zeaxanthin", "lutemax", "meso-zeaxanthin", "preservision", "zeaxanthin"]),
        ("valerian", ["Valerian root", "valerenic acid", "valerian", "valerian root", "valeriana officinalis"]),
        ("plant_sterols", ["Plant sterols & stanols", "benecol", "cardioaid", "cholest-off", "cholestoff", "phytosterols", "plant stanols", "plant sterols", "reducol", "stanols", "sterol esters", "sterols", "beta-sitosterol"]),
        ("taurine", ["Taurine", "amino acid taurine", "l-taurine", "taurine", "taurine capsules", "taurine powder"]),
        ("spirulina", ["Spirulina", "arthrospira", "blue-green algae", "hawaiian spirulina", "phycocyanin", "spirulina", "spirulina pacifica", "spirulina powder", "spirulina tablets"]),
        ("lions_mane", ["Lion's Mane mushroom", "hericium", "hericium erinaceus", "lion mane", "lion's mane", "lions mane", "yamabushitake"]),
        ("alpha_lipoic_acid", ["Alpha-lipoic acid (ALA)", "alpha lipoic acid", "alpha-lipoic acid", "lipoic acid", "r-ala", "r-lipoic acid", "thiocid", "thioctic acid"]),
        ("astaxanthin", ["Astaxanthin", "astareal", "astaxanthin", "bioastin", "haematococcus", "zanthin"]),
        ("st_johns_wort", ["St. John's Wort", "hypericin", "hypericum", "hypericum perforatum", "perika", "saint john's wort", "sjw", "st john's wort", "st johns wort", "st. john's wort", "st. johns wort", "st john's wort"]),
        ("inositol", ["Inositol (myo-inositol)", "d-chiro-inositol", "dci", "inositol", "myo inositol", "myo-inositol", "ovasitol", "pcos inositol"]),
        ("glycine", ["Glycine", "amino acid glycine", "glycine", "glycine powder", "glycine sleep", "l-glycine"]),
        ("saffron", ["Saffron extract", "affron", "crocin", "crocus sativus", "saffron", "saffron extract", "safranal", "satiereal"]),
        ("five_htp", ["5-HTP (5-hydroxytryptophan)", "5 htp", "5-htp", "5-hydroxytryptophan", "5htp", "griffonia", "griffonia simplicifolia", "hydroxytryptophan"]),
        ("resveratrol", ["Resveratrol (trans-resveratrol)", "japanese knotweed", "polygonum cuspidatum", "red wine extract", "resveratrol", "resvinol", "trans resveratrol", "trans-resveratrol"]),
        ("msm", ["MSM (methylsulfonylmethane)", "dimethyl sulfone", "methyl sulfonyl methane", "methylsulfonylmethane", "optimsm", "organic sulfur", "msm"]),
        ("dhea", ["DHEA (dehydroepiandrosterone)", "dehydroepiandrosterone", "dhea", "dhea-s", "dheas", "micronized dhea", "prasterone"]),
        ("vitamin_a", ["Vitamin A (retinol / retinyl palmitate)", "beta carotene", "beta-carotene", "fish liver oil vitamin a", "preformed vitamin a", "retinol", "retinyl acetate", "retinyl palmitate", "vitamin a"]),
        ("carnitine", ["L-Carnitine", "acetyl l carnitine", "acetyl-l-carnitine", "alcar", "carnipure", "carnitine", "carnitine fumarate", "l carnitine", "l-carnitine", "l-carnitine tartrate", "lclt"]),
    ]
}
