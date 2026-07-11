import SwiftUI
import UIKit

/// The Clarion design system — a faithful port of the web's `ds.css` (the single source of
/// truth for the brand re-skin). Light is the hero theme; dark is the alternate. Every color
/// in the app routes through these tokens: one green hue family carries the brand, and
/// amber/clay appear only to convey clinical meaning, never decoration.
///
/// Values are verbatim from bloodwise-frontend `app/(clarion-app)/clarion/ds.css`.
enum Brand {

    // MARK: - Radii (ds.css --r-*)

    static let rXS: CGFloat = 6
    static let rSM: CGFloat = 10
    static let r: CGFloat = 14
    static let rLG: CGFloat = 18
    static let rXL: CGFloat = 24
    static let r2XL: CGFloat = 32

    // MARK: - Spacing (4pt rhythm, ds.css --s*)

    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 20
    static let s6: CGFloat = 24
    static let s7: CGFloat = 32
    static let s8: CGFloat = 48

    // MARK: - Motion (ds.css --t-*)

    static let tFast: Double = 0.16
    static let t: Double = 0.24
    static let tSlow: Double = 0.38
}

// MARK: - Color tokens

extension Color {

    /// Light/dark dynamic color from two hex values (0xRRGGBB) with optional alphas.
    private static func dynamic(_ light: UInt32, _ dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkAlpha)
                : UIColor(hex: light, alpha: lightAlpha)
        })
    }

    // Surfaces — warm paper world, slightly green-tinted, never pure white/gray canvas.
    static let paper = dynamic(0xEFF3F0, 0x0F1614)
    static let paperDim = dynamic(0xE6ECE8, 0x0B100E)
    static let surface = dynamic(0xFFFFFF, 0x15201C)
    static let surface2 = dynamic(0xF6F9F7, 0x131D19)
    static let surface3 = dynamic(0xFBFCFB, 0x18241F)

    // Ink — green-black, never pure black.
    static let ink = dynamic(0x16201C, 0xF3F6F4)
    static let ink2 = dynamic(0x46514C, 0xF3F6F4, darkAlpha: 0.74)
    static let ink3 = dynamic(0x79827D, 0xF3F6F4, darkAlpha: 0.50)
    static let ink4 = dynamic(0xA2A9A4, 0xF3F6F4, darkAlpha: 0.32)
    /// Legacy alias — existing views use `inkMuted` for captions/secondary.
    static let inkMuted = ink3

    // Hairlines.
    static let line = dynamic(0x16201C, 0xFFFFFF, lightAlpha: 0.09, darkAlpha: 0.08)
    static let line2 = dynamic(0x16201C, 0xFFFFFF, lightAlpha: 0.16, darkAlpha: 0.14)
    static let lineStrong = dynamic(0x16201C, 0xFFFFFF, lightAlpha: 0.24, darkAlpha: 0.22)

    // Forest green family — the brand.
    static let forest = dynamic(0x1F6F5B, 0x2A8C72)
    static let forestDeep = dynamic(0x18584A, 0x1F6F5B)
    static let forestBright = dynamic(0x2A8C72, 0x36A98A)
    static let forestInk = dynamic(0x0E4A3B, 0x8FE3C9)
    static let forestWash = dynamic(0xE6F0EB, 0x1F6F5B, darkAlpha: 0.16)
    static let forestWash2 = dynamic(0xD7E8E0, 0x1F6F5B, darkAlpha: 0.24)

    // Semantic — meaning only. Amber = watch/maintain, clay = flagged/low/drop.
    static let amber = dynamic(0x9A6B2E, 0xC4A060)
    static let amberInk = dynamic(0x6E4A18, 0xE2C589)
    static let amberWash = dynamic(0xF4ECDC, 0xC4A060, darkAlpha: 0.14)
    static let clay = dynamic(0xB0443A, 0xC75C5C)
    static let clayInk = dynamic(0x8A2E26, 0xE89292)
    static let clayWash = dynamic(0xF6E4E1, 0xC75C5C, darkAlpha: 0.14)

    // Score dial ring gradient stops.
    static let scoreA = dynamic(0x2A8C72, 0x36A98A)
    static let scoreB = dynamic(0x1F6F5B, 0x2A8C72)

    /// Semantic tone for a biomarker/metric status string.
    static func tone(for status: String) -> Color {
        switch status.lowercased() {
        case "optimal", "normal", "in range": return .forest
        case "deficient", "low": return .clay
        case "high", "suboptimal": return .amber
        default: return .ink3
        }
    }

    /// Wash (background) matching `tone(for:)`.
    static func toneWash(for status: String) -> Color {
        switch status.lowercased() {
        case "optimal", "normal", "in range": return .forestWash
        case "deficient", "low": return .clayWash
        case "high", "suboptimal": return .amberWash
        default: return .paperDim
        }
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
