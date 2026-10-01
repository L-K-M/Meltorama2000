import AppKit
import SwiftUI

/// Color belongs to the window; controls keep their native macOS appearance.
enum MacTheme {
    static let windowNSColor = adaptive(light: (0.78, 0.93, 0.91), dark: (0.07, 0.25, 0.26))
    static let window = Color(nsColor: windowNSColor)
    static let welcome = Color(nsColor: adaptive(light: (0.86, 0.97, 0.95), dark: (0.08, 0.29, 0.30)))
    static let accent = Color(nsColor: adaptive(light: (0.00, 0.40, 0.43), dark: (0.34, 0.84, 0.81)))
    static let berry = Color(nsColor: adaptive(light: (0.75, 0.09, 0.39), dark: (0.94, 0.37, 0.62)))

    private static func adaptive(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> NSColor {
        NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        }
    }
}
