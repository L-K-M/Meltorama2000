import AppKit
import SwiftUI

enum ThemePreference: String, CaseIterable, Identifiable {
    case classic, candy, tangerine, ocean, grape, mint, sunshine, cherry

    static let storageKey = "themePreference"
    var id: Self { self }
    var title: String {
        switch self {
        case .classic: return "Classic"
        case .candy: return "Candy"
        case .tangerine: return "Tangerine"
        case .ocean: return "Ocean"
        case .grape: return "Grape"
        case .mint: return "Mint"
        case .sunshine: return "Sunshine"
        case .cherry: return "Cherry"
        }
    }

    static func resolve(_ storedValue: String?) -> Self {
        storedValue.flatMap(Self.init(rawValue:)) ?? .classic
    }
}

/// Themes color the editing panels and accents, leaving photos on native neutral surfaces.
struct MacTheme {
    let preference: ThemePreference

    var accent: Color { Color(nsColor: accentColor) }
    var panelBackground: Color { Color(nsColor: panelBackgroundColor) }

    var accentColor: NSColor {
        NSColor(name: nil) { appearance in
            palette.color(dark: Self.isDark(appearance))
        }
    }

    var panelBackgroundColor: NSColor {
        guard preference != .classic else { return .controlBackgroundColor }
        return NSColor(name: nil) { appearance in
            var color = NSColor.controlBackgroundColor
            appearance.performAsCurrentDrawingAppearance {
                // Resolve the system surface in the provider's appearance, not the
                // current document window's appearance, before blending the wash.
                let base = NSColor.controlBackgroundColor.usingColorSpace(.sRGB) ?? .controlBackgroundColor
                color = base.blended(withFraction: Self.isDark(appearance) ? 0.10 : 0.055,
                                     of: palette.color(dark: Self.isDark(appearance))) ?? base
            }
            return color
        }
    }

    private struct Palette {
        let light: (CGFloat, CGFloat, CGFloat)
        let dark: (CGFloat, CGFloat, CGFloat)

        func color(dark usesDark: Bool) -> NSColor {
            let rgb = usesDark ? dark : light
            return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        }
    }

    private var palette: Palette {
        switch preference {
        case .classic: return Palette(light: (0.33, 0.46, 0.00), dark: (0.73, 0.92, 0.25))
        case .candy: return Palette(light: (0.72, 0.08, 0.36), dark: (1.00, 0.39, 0.69))
        case .tangerine: return Palette(light: (0.71, 0.28, 0.02), dark: (1.00, 0.63, 0.23))
        case .ocean: return Palette(light: (0.04, 0.39, 0.74), dark: (0.30, 0.70, 1.00))
        case .grape: return Palette(light: (0.45, 0.22, 0.73), dark: (0.77, 0.57, 1.00))
        case .mint: return Palette(light: (0.00, 0.43, 0.32), dark: (0.29, 0.89, 0.66))
        case .sunshine: return Palette(light: (0.53, 0.39, 0.02), dark: (1.00, 0.84, 0.20))
        case .cherry: return Palette(light: (0.74, 0.16, 0.16), dark: (1.00, 0.49, 0.44))
        }
    }

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}

private struct MacThemeKey: EnvironmentKey {
    static let defaultValue = MacTheme(preference: .classic)
}

extension EnvironmentValues {
    var macTheme: MacTheme {
        get { self[MacThemeKey.self] }
        set { self[MacThemeKey.self] = newValue }
    }
}
