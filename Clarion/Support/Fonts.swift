import SwiftUI
import UIKit
import CoreText

/// Clarion's four-role type system, matching the web (`app/layout.tsx` + ds.css):
///
///  - **Display (serif)** — Libre Baskerville. Hero numbers, marker/supplement names,
///    card titles, the wordmark. Editorial moments — including data-bearing names.
///  - **UI sans** — Plus Jakarta Sans. Labels, buttons, chips, nav, tracked eyebrows.
///  - **Body sans** — Hanken Grotesk. Paragraphs, descriptions, notes.
///  - **Data mono** — IBM Plex Mono. Values, prices, doses, ranges, deltas.
///
/// Fonts are bundled TTFs (OFL-licensed) registered at launch — no Info.plist keys needed.
/// Baskerville/Jakarta/Hanken are variable fonts; weights are instantiated via the `wght` axis.
enum ClarionFonts {

    private static let files = [
        "LibreBaskerville", "LibreBaskerville-Italic",
        "PlusJakartaSans", "HankenGrotesk",
        "IBMPlexMono-Regular", "IBMPlexMono-Medium", "IBMPlexMono-SemiBold",
    ]

    /// Register every bundled brand font. Idempotent; call once from App.init.
    static func registerAll() {
        for name in files {
            let url = Bundle.main.url(forResource: name, withExtension: "ttf")
                ?? Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
            guard let url else {
                #if DEBUG
                print("ClarionFonts: missing \(name).ttf in bundle")
                #endif
                continue
            }
            // Ignore "already registered" errors — registration is per-process.
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// A UIFont for a (possibly variable) family at a given wght-axis value.
    /// Falls back to the closest system font if the family is missing so the app
    /// never renders blank text.
    static func uiFont(family: String, size: CGFloat, weight: CGFloat, italic: Bool = false) -> UIFont {
        let wghtAxisID = 0x77676874 // 'wght'
        var attributes: [UIFontDescriptor.AttributeName: Any] = [
            .family: family,
            kCTFontVariationAttribute as UIFontDescriptor.AttributeName: [wghtAxisID: weight],
        ]
        if italic {
            attributes[.traits] = [UIFontDescriptor.TraitKey.symbolic: UIFontDescriptor.SymbolicTraits.traitItalic.rawValue]
        }
        let descriptor = UIFontDescriptor(fontAttributes: attributes)
        let font = UIFont(descriptor: descriptor, size: size)
        // UIFont(descriptor:) silently falls back to Helvetica when the family is absent;
        // detect that and use the system face instead so the fallback at least matches iOS.
        if font.familyName.lowercased().contains("helvetica") && !family.lowercased().contains("helvetica") {
            return .systemFont(ofSize: size, weight: UIFont.Weight(rawValue: (weight - 400) / 400))
        }
        return font
    }
}

extension Font {

    /// Display serif — Libre Baskerville (wght axis 400–700).
    static func display(_ size: CGFloat, weight: CGFloat = 700) -> Font {
        Font(ClarionFonts.uiFont(family: "Libre Baskerville", size: size, weight: weight))
    }

    /// Display serif italic — the web softens phrases with `em` in Baskerville italic.
    static func displayItalic(_ size: CGFloat) -> Font {
        Font(ClarionFonts.uiFont(family: "Libre Baskerville", size: size, weight: 400, italic: true))
    }

    /// UI sans — Plus Jakarta Sans (wght 200–800).
    static func ui(_ size: CGFloat, weight: CGFloat = 600) -> Font {
        Font(ClarionFonts.uiFont(family: "Plus Jakarta Sans", size: size, weight: weight))
    }

    /// Body sans — Hanken Grotesk (wght 100–900).
    static func bodyFace(_ size: CGFloat, weight: CGFloat = 400) -> Font {
        Font(ClarionFonts.uiFont(family: "Hanken Grotesk", size: size, weight: weight))
    }

    /// Data mono — IBM Plex Mono (static 400/500/600), tabular by design.
    static func data(_ size: CGFloat, weight: CGFloat = 500) -> Font {
        let name = weight >= 600 ? "IBMPlexMono-SemiBold" : (weight >= 500 ? "IBMPlexMono-Medium" : "IBMPlexMono")
        if UIFont(name: name, size: size) != nil {
            return .custom(name, size: size)
        }
        return .system(size: size, design: .monospaced)
    }
}
