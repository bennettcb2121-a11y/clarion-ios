import Foundation

/// Life-stage inputs that change how the range engine reads a panel.
///
/// These are NOT cosmetic profile fields. The web range engine suppresses or retunes real
/// markers on them, so an iOS user who cannot set them gets a different answer than a web user
/// with the identical panel:
///
///   • pregnancy — ALP runs 2–4x on placental enzyme, plasma-volume expansion lowers haemoglobin
///     and haematocrit, ferritin falls through the 2nd/3rd trimester, TSH shifts by trimester.
///     Scored against non-pregnant bands, a normal pregnancy reads as a cluster of abnormalities.
///   • menopause stage — drives the peri/post bands for ApoB, LDL-C, TSH, vitamin D, haemoglobin
///     and ferritin. Without it the engine can only guess "postmenopausal" from age >= 55, which
///     silently skips every woman aged 40–54: exactly the transition those bands exist for.
///
/// Values MUST match the web enums (src/lib/pregnancyStatus.ts, src/lib/menopauseStage.ts) and the
/// accepted values in profileSettingsApiPayload.ts, or the PATCH is rejected.
enum PregnancyCatalog {
    struct Option: Identifiable { let id: String; let label: String }

    static let options: [Option] = [
        .init(id: "not_pregnant", label: "Not pregnant"),
        .init(id: "pregnant", label: "Pregnant"),
        .init(id: "postpartum", label: "Recently gave birth"),
        .init(id: "unknown", label: "Prefer not to say"),
    ]

    static func label(for id: String?) -> String {
        guard let id, !id.isEmpty else { return "Not set" }
        return options.first { $0.id == id }?.label ?? "Not set"
    }

    /// Only shown to women of possible childbearing age — mirrors shouldAskPregnancyStatus on web.
    static func shouldAsk(sex: String?, age: String?) -> Bool {
        guard (sex ?? "").lowercased().hasPrefix("f") else { return false }
        guard let n = Double(age ?? "") else { return false }
        return n >= 16 && n <= 55
    }
}

enum MenopauseCatalog {
    struct Option: Identifiable { let id: String; let label: String }

    static let options: [Option] = [
        .init(id: "premenopausal", label: "Pre-menopause"),
        .init(id: "perimenopausal", label: "Perimenopause"),
        .init(id: "postmenopausal", label: "Post-menopause"),
        .init(id: "on_hrt", label: "On hormone therapy"),
        .init(id: "unknown", label: "Prefer not to say"),
    ]

    static func label(for id: String?) -> String {
        guard let id, !id.isEmpty else { return "Not set" }
        return options.first { $0.id == id }?.label ?? "Not set"
    }

    /// Mirrors shouldAskMenopauseStage on web: women from 40 on. We keep asking past 55 so HRT —
    /// or simply not being post-menopause yet — isn't overwritten by the age-based guess.
    static func shouldAsk(sex: String?, age: String?) -> Bool {
        guard (sex ?? "").lowercased().hasPrefix("f") else { return false }
        guard let n = Double(age ?? "") else { return false }
        return n >= 40
    }
}
