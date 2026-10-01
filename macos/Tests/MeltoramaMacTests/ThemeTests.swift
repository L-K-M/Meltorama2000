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
                for surface in [NSColor.controlBackgroundColor, NSColor.textBackgroundColor, theme.panelBackgroundColor] {
                    let background = try resolve(surface, in: appearance)
                    XCTAssertGreaterThanOrEqual(contrast(accent, background), 4.5, "\(preference) in \(name)")
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
                for surface in [theme.panelBackgroundColor, NSColor.controlBackgroundColor] {
                    let base = try resolve(surface, in: appearance)
                    let selected = try XCTUnwrap(base.blended(withFraction: 0.2, of: accent)?.usingColorSpace(.sRGB))
                    XCTAssertGreaterThanOrEqual(contrast(label, selected), 4.5, "\(preference) selection in \(name)")
                }
            }
        }
    }

    func testClassicPreservesTheOriginalAccentAndNativePanelSurface() throws {
        let theme = MacTheme(preference: .classic)
        for (name, expected) in [(NSAppearance.Name.aqua, [0.33, 0.46, 0.0]), (.darkAqua, [0.73, 0.92, 0.25])] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            let accent = try resolve(theme.accentColor, in: appearance)
            for (actual, expected) in zip([accent.redComponent, accent.greenComponent, accent.blueComponent], expected) {
                XCTAssertEqual(actual, expected, accuracy: 0.000001)
            }
            let panel = try resolve(theme.panelBackgroundColor, in: appearance)
            let native = try resolve(.controlBackgroundColor, in: appearance)
            XCTAssertEqual(panel.redComponent, native.redComponent, accuracy: 0.000001)
            XCTAssertEqual(panel.greenComponent, native.greenComponent, accuracy: 0.000001)
            XCTAssertEqual(panel.blueComponent, native.blueComponent, accuracy: 0.000001)
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
