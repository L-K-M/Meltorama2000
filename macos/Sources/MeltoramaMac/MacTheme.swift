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

/// Coordinated surfaces surround the photo without changing its rendered pixels.
struct MacTheme {
    let preference: ThemePreference

    var accent: Color { Color(nsColor: accentColor) }
    var chromeBackground: Color { Color(nsColor: chromeBackgroundColor) }
    var panelBackground: Color { Color(nsColor: panelBackgroundColor) }
    var workspaceBackground: Color { Color(nsColor: workspaceBackgroundColor) }

    var accentColor: NSColor {
        let palette = palette
        return NSColor(name: nil) { appearance in
            let dark = Self.isDark(appearance)
            let rgb = palette.map { (dark ? $0.dark : $0.light).accent }
                ?? (dark ? (0.73, 0.92, 0.25) : (0.33, 0.46, 0.00))
            return Self.color(rgb)
        }
    }

    var chromeBackgroundColor: NSColor {
        background(\.chrome, classic: .windowBackgroundColor)
    }

    var panelBackgroundColor: NSColor {
        background(\.panel, classic: .controlBackgroundColor)
    }

    var workspaceBackgroundColor: NSColor {
        background(\.workspace, classic: .textBackgroundColor)
    }

    // The original welcome and photo canvas deliberately use different native
    // surfaces. A themed workspace unifies them; Classic retains that distinction.
    var canvasBackgroundColor: NSColor {
        preference == .classic ? .underPageBackgroundColor : workspaceBackgroundColor
    }

    private typealias RGB = (CGFloat, CGFloat, CGFloat)

    private struct Colors {
        let chrome: RGB
        let panel: RGB
        let workspace: RGB
        let accent: RGB
    }

    private struct Palette {
        let light: Colors
        let dark: Colors
    }

    private func background(_ role: KeyPath<Colors, RGB>, classic: NSColor) -> NSColor {
        guard let palette else { return classic }
        return NSColor(name: nil) { appearance in
            let colors = Self.isDark(appearance) ? palette.dark : palette.light
            return Self.color(colors[keyPath: role])
        }
    }

    private static func color(_ rgb: RGB) -> NSColor {
        NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
    }

    // Each palette pairs quiet, opaque background colors with a distinct accent.
    // Values are authored in sRGB rather than washing every surface with one hue.
    private var palette: Palette? {
        switch preference {
        case .classic: return nil
        case .candy:
            return Palette(
                light: Colors(chrome: (0.92, 0.87, 0.98), panel: (0.99, 0.92, 0.95),
                              workspace: (0.975, 0.96, 0.99), accent: (0.67, 0.045, 0.31)),
                dark: Colors(chrome: (0.21, 0.14, 0.29), panel: (0.245, 0.135, 0.19),
                             workspace: (0.145, 0.10, 0.185), accent: (1.00, 0.47, 0.71)))
        case .tangerine:
            return Palette(
                light: Colors(chrome: (1.00, 0.89, 0.77), panel: (1.00, 0.95, 0.89),
                              workspace: (1.00, 0.98, 0.93), accent: (0.00, 0.38, 0.36)),
                dark: Colors(chrome: (0.27, 0.16, 0.08), panel: (0.215, 0.155, 0.10),
                             workspace: (0.145, 0.12, 0.075), accent: (0.28, 0.86, 0.80)))
        case .ocean:
            return Palette(
                light: Colors(chrome: (0.81, 0.92, 0.99), panel: (0.89, 0.97, 0.95),
                              workspace: (0.94, 0.98, 1.00), accent: (0.73, 0.17, 0.12)),
                dark: Colors(chrome: (0.085, 0.205, 0.29), panel: (0.105, 0.215, 0.20),
                             workspace: (0.075, 0.125, 0.17), accent: (1.00, 0.56, 0.42)))
        case .grape:
            return Palette(
                light: Colors(chrome: (0.90, 0.86, 0.98), panel: (0.96, 0.92, 0.99),
                              workspace: (0.98, 0.96, 1.00), accent: (0.48, 0.33, 0.00)),
                dark: Colors(chrome: (0.205, 0.135, 0.29), panel: (0.185, 0.12, 0.255),
                             workspace: (0.115, 0.075, 0.165), accent: (1.00, 0.82, 0.29)))
        case .mint:
            return Palette(
                light: Colors(chrome: (0.81, 0.96, 0.87), panel: (0.91, 0.98, 0.94),
                              workspace: (0.96, 0.99, 0.965), accent: (0.67, 0.08, 0.35)),
                dark: Colors(chrome: (0.08, 0.245, 0.17), panel: (0.10, 0.205, 0.155),
                             workspace: (0.07, 0.135, 0.10), accent: (1.00, 0.47, 0.69)))
        case .sunshine:
            return Palette(
                light: Colors(chrome: (1.00, 0.94, 0.68), panel: (1.00, 0.98, 0.88),
                              workspace: (1.00, 0.99, 0.945), accent: (0.035, 0.33, 0.67)),
                dark: Colors(chrome: (0.27, 0.225, 0.08), panel: (0.215, 0.19, 0.095),
                             workspace: (0.145, 0.135, 0.08), accent: (0.42, 0.71, 1.00)))
        case .cherry:
            return Palette(
                light: Colors(chrome: (1.00, 0.85, 0.88), panel: (0.99, 0.92, 0.93),
                              workspace: (1.00, 0.97, 0.96), accent: (0.00, 0.38, 0.32)),
                dark: Colors(chrome: (0.285, 0.115, 0.155), panel: (0.23, 0.125, 0.155),
                             workspace: (0.16, 0.085, 0.11), accent: (0.39, 0.88, 0.70)))
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
