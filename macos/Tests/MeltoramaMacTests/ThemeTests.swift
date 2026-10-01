import AppKit
import XCTest
@testable import MeltoramaMac

final class ThemeTests: XCTestCase {
    func testStoredPreferenceFallsBackWithoutReplacingUnknownValues() throws {
        let suite = "MeltoramaThemeTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(ThemePreference.resolve(defaults.string(forKey: ThemePreference.storageKey)), .classic)
        defaults.set("theme-from-a-newer-version", forKey: ThemePreference.storageKey)
        XCTAssertEqual(ThemePreference.resolve(defaults.string(forKey: ThemePreference.storageKey)), .classic)
        XCTAssertEqual(defaults.string(forKey: ThemePreference.storageKey), "theme-from-a-newer-version")
        for theme in ThemePreference.allCases {
            defaults.set(theme.rawValue, forKey: ThemePreference.storageKey)
            XCTAssertEqual(ThemePreference.resolve(defaults.string(forKey: ThemePreference.storageKey)), theme)
        }
        XCTAssertEqual(ThemePreference.resolve(""), .classic)
        XCTAssertNotEqual(ThemePreference.storageKey, AppearancePreference.storageKey)
    }

    func testAccentsAreReadableOnNativeAndThemedSurfacesInBothAppearances() throws {
        for name in appearances {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            for preference in ThemePreference.allCases {
                let theme = MacTheme(preference: preference)
                let accent = try resolve(theme.accentColor, in: appearance)
                let surfaces = [("native controls", NSColor.controlBackgroundColor),
                                ("native text fields", NSColor.textBackgroundColor)] + backgrounds(of: theme)
                for (role, surface) in surfaces {
                    // Classic's original canvas is dark even in Aqua, and uses
                    // the black/white brush cursor rather than the theme accent.
                    if preference == .classic && role == "canvas" { continue }
                    let background = try resolve(surface, in: appearance)
                    XCTAssertGreaterThanOrEqual(contrast(accent, background), 4.5,
                                                "\(preference) accent on \(role) in \(name)")
                }
            }
        }
    }

    func testSelectionTextRemainsReadableOnPanelAndTimelineSelections() throws {
        for name in appearances {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            for preference in ThemePreference.allCases {
                let theme = MacTheme(preference: preference)
                let accent = try resolve(theme.accentColor, in: appearance)
                let label = try resolve(.labelColor, in: appearance)
                // The native rows and the plain timeline cards keep primary text
                // over a translucent accent, rather than changing text to white.
                let surfaces = [("panel", theme.panelBackgroundColor),
                                ("chrome", theme.chromeBackgroundColor),
                                ("workspace", theme.workspaceBackgroundColor)]
                for (role, surface) in surfaces {
                    let base = try resolve(surface, in: appearance)
                    let selected = try XCTUnwrap(base.blended(withFraction: 0.2, of: accent)?.usingColorSpace(.sRGB))
                    XCTAssertGreaterThanOrEqual(contrast(label, selected), 4.5,
                                                "\(preference) selected \(role) in \(name)")
                }
            }
        }
    }

    func testThemeSurfacesKeepNativePrimaryAndSecondaryTextReadable() throws {
        for name in appearances {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            let primary = try resolve(.labelColor, in: appearance)
            let secondary = try resolve(.secondaryLabelColor, in: appearance)
            for preference in ThemePreference.allCases where preference != .classic {
                for (role, surface) in backgrounds(of: MacTheme(preference: preference)) {
                    let background = try resolve(surface, in: appearance)
                    XCTAssertGreaterThanOrEqual(contrast(primary, background), 4.5,
                                                "\(preference) primary text on \(role) in \(name)")
                    // Native secondary labels retain the system's opacity. This
                    // includes that opacity in the contrast of compact captions.
                    XCTAssertGreaterThanOrEqual(contrast(secondary, background), 3.0,
                                                "\(preference) secondary text on \(role) in \(name)")
                }
            }
        }
    }

    func testAuthoredPalettesUseOpaqueDistinctSurfacesAndAnotherAccentHue() throws {
        for name in appearances {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            for preference in ThemePreference.allCases where preference != .classic {
                let theme = MacTheme(preference: preference)
                let roles = try backgrounds(of: theme).map { role, color in
                    (role, try resolve(color, in: appearance))
                }
                for (role, color) in roles {
                    XCTAssertEqual(color.alphaComponent, 1, accuracy: 0.000001,
                                   "\(preference) \(role) is opaque in \(name)")
                }
                // Canvas and welcome deliberately share the authored workspace.
                for left in 0..<3 {
                    for right in (left + 1)..<3 {
                        XCTAssertGreaterThanOrEqual(distance(roles[left].1, roles[right].1), 0.02,
                                                    "\(preference) \(roles[left].0) differs from \(roles[right].0) in \(name)")
                    }
                }
                let accent = try resolve(theme.accentColor, in: appearance)
                let chrome = try resolve(theme.chromeBackgroundColor, in: appearance)
                let hueDifference = abs(accent.hueComponent - chrome.hueComponent)
                XCTAssertGreaterThanOrEqual(min(hueDifference, 1 - hueDifference), 0.07,
                                            "\(preference) uses another accent hue in \(name)")
                XCTAssertEqual(distance(roles[2].1, roles[3].1), 0, accuracy: 0.000001)
            }
        }
    }

    func testClassicPreservesTheOriginalAccentAndAllNativeSurfaces() throws {
        let theme = MacTheme(preference: .classic)
        for name in appearances {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            let expected = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? [0.73, 0.92, 0.25] : [0.33, 0.46, 0.0]
            let accent = try resolve(theme.accentColor, in: appearance)
            for (actual, expected) in zip([accent.redComponent, accent.greenComponent, accent.blueComponent], expected) {
                XCTAssertEqual(actual, expected, accuracy: 0.000001)
            }
            for (role, surface, original) in [("chrome", theme.chromeBackgroundColor, NSColor.windowBackgroundColor),
                                              ("panel", theme.panelBackgroundColor, NSColor.controlBackgroundColor),
                                              ("workspace", theme.workspaceBackgroundColor, NSColor.textBackgroundColor),
                                              ("canvas", theme.canvasBackgroundColor, NSColor.underPageBackgroundColor)] {
                XCTAssertEqual(distance(try resolve(surface, in: appearance), try resolve(original, in: appearance)),
                               0, accuracy: 0.000001, "Classic \(role) in \(name)")
            }
        }
    }

    private var appearances: [NSAppearance.Name] {
        [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua]
    }

    private func resolve(_ color: NSColor, in appearance: NSAppearance) throws -> NSColor {
        var resolved: NSColor?
        appearance.performAsCurrentDrawingAppearance { resolved = color.usingColorSpace(.sRGB) }
        return try XCTUnwrap(resolved)
    }

    private func backgrounds(of theme: MacTheme) -> [(String, NSColor)] {
        [("chrome", theme.chromeBackgroundColor), ("panel", theme.panelBackgroundColor),
         ("workspace", theme.workspaceBackgroundColor), ("canvas", theme.canvasBackgroundColor)]
    }

    private func distance(_ a: NSColor, _ b: NSColor) -> CGFloat {
        zip([a.redComponent, a.greenComponent, a.blueComponent, a.alphaComponent],
            [b.redComponent, b.greenComponent, b.blueComponent, b.alphaComponent])
            .map { abs($0 - $1) }.max() ?? 0
    }

    private func contrast(_ foreground: NSColor, _ background: NSColor) -> CGFloat {
        let alpha = foreground.alphaComponent
        let rgb = zip([foreground.redComponent, foreground.greenComponent, foreground.blueComponent],
                      [background.redComponent, background.greenComponent, background.blueComponent])
            .map { $0 * alpha + $1 * (1 - alpha) }
        let a = luminance(rgb)
        let b = luminance([background.redComponent, background.greenComponent, background.blueComponent])
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private func luminance(_ components: [CGFloat]) -> CGFloat {
        let linear = components.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        return zip(linear, [0.2126, 0.7152, 0.0722]).map(*).reduce(0, +)
    }
}
