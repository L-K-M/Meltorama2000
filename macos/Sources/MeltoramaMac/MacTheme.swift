import AppKit
import SwiftUI

/// Bright accents sit on native system surfaces, keeping photo editing neutral.
enum MacTheme {
    static let accent = Color(nsColor: adaptive(light: (0.33, 0.46, 0.00), dark: (0.73, 0.92, 0.25)))

    private static func adaptive(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> NSColor {
        NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        }
    }
}
