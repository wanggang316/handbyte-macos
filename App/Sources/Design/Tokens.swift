import AppKit
import SwiftUI

/// Design tokens of the app: ink on paper and one green signal. Each color
/// has a light and a dark value; views use these and no literal colors.
enum HB {
    enum Palette {
        static let background = Color(light: 0xFFFFFF, dark: 0x141517)
        /// Soft fill of cards and of the meter track.
        static let surface = Color(light: 0xF6F6F7, dark: 0x1C1D20)
        static let surfaceHover = Color(light: 0xEFEFF1, dark: 0x25262A)
        static let hover = Color(light: 0x111214, dark: 0xFFFFFF, lightAlpha: 0.04, darkAlpha: 0.055)
        static let active = Color(light: 0x111214, dark: 0xFFFFFF, lightAlpha: 0.07, darkAlpha: 0.10)
        static let border = Color(light: 0x111214, dark: 0xFFFFFF, lightAlpha: 0.08, darkAlpha: 0.09)
        static let borderStrong = Color(light: 0x111214, dark: 0xFFFFFF, lightAlpha: 0.20, darkAlpha: 0.20)

        static let text = Color(light: 0x111214, dark: 0xF1F1F2)
        static let textSecondary = Color(light: 0x585B63, dark: 0xA7AAB1)
        static let textTertiary = Color(light: 0x696D76, dark: 0x878B94)

        /// Fill of the primary action: ink on light, paper on dark.
        static let ink = Color(light: 0x111214, dark: 0xF4F4F5)
        static let inkHover = Color(light: 0x2B2D33, dark: 0xFFFFFF)
        static let onInk = Color(light: 0xFFFFFF, dark: 0x111214)

        /// The one brand color. It means safe, progress and done.
        static let brand = Color(light: 0x12B76A, dark: 0x3DDC97)
        static let safe = Color(light: 0x0B7A50, dark: 0x4FD39A)
        static let review = Color(light: 0x955800, dark: 0xF2B04C)
        static let danger = Color(light: 0xC0283A, dark: 0xD13B4A)
    }

    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 10
        static let large: CGFloat = 16
    }

    enum Space {
        static let page: CGFloat = 28
        static let section: CGFloat = 40
        /// Width of the centered content column.
        static let column: CGFloat = 760
    }

    enum Typography {
        /// The one large number of a screen.
        static let hero = Font.system(size: 64, weight: .semibold)
        static let title = Font.system(size: 20, weight: .semibold)
        static let head = Font.system(size: 14, weight: .semibold)
        static let body = Font.system(size: 13)
        /// Upper-case group label.
        static let label = Font.system(size: 11, weight: .semibold)
    }

    enum Motion {
        /// State changes of controls: hover, press.
        static let quick = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.12)
        /// Content that moves or grows.
        static let standard = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.2)
    }
}

extension Color {
    /// A color that follows the appearance. Values are 0xRRGGBB.
    init(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let value = isDark ? dark : light
            return NSColor(
                srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: isDark ? darkAlpha : lightAlpha
            )
        })
    }
}

extension View {
    /// The upper-case group label of the type scale.
    func hbLabel() -> some View {
        font(HB.Typography.label)
            .tracking(0.66)
            .textCase(.uppercase)
            .foregroundStyle(HB.Palette.textTertiary)
    }
}
