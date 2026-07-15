import CoreText
import UIKit

/// Bundled Fraunces — the web's display serif, brought to iOS so the app matches
/// clarionlabs.tech exactly instead of substituting Apple's (wider, colder) New York.
/// Three static instances live in Clarion/Fonts/ (opsz pinned to 72 for a warm display
/// cut): Fraunces-Regular, Fraunces-SemiBold, Fraunces-SemiBoldItalic.
enum Fonts {
    static let regular = "Fraunces-Regular"
    static let semibold = "Fraunces-SemiBold"
    static let semiboldItalic = "Fraunces-SemiBoldItalic"

    /// Register the bundled faces once at launch. Programmatic registration avoids an
    /// Info.plist UIAppFonts entry (this target's Info.plist is generated from build
    /// settings). Safe to call once from ClarionApp.init before applyBrandChrome.
    static func registerBundled() {
        for name in [regular, semibold, semiboldItalic] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else {
                #if DEBUG
                print("[Fonts] MISSING \(name).ttf in bundle")
                #endif
                continue
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        #if DEBUG
        print("[Fonts] Fraunces available: \(isAvailable) · families: \(UIFont.familyNames.filter { $0.localizedCaseInsensitiveContains("Fraunces") })")
        #endif
    }

    /// True once the SemiBold display face has loaded — callers fall back to the system
    /// serif so text never vanishes if a face fails to register.
    static var isAvailable: Bool { UIFont(name: semibold, size: 17) != nil }

    /// A Fraunces UIFont, or the system serif at the same size/weight as a safe fallback.
    static func display(_ size: CGFloat, italic: Bool = false) -> UIFont {
        if let f = UIFont(name: italic ? semiboldItalic : semibold, size: size) { return f }
        let base = UIFont.systemFont(ofSize: size, weight: .semibold)
        let d = base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor
        let uf = UIFont(descriptor: d, size: size)
        return italic ? UIFont(descriptor: d.withSymbolicTraits(.traitItalic) ?? d, size: size) : uf
    }
}
