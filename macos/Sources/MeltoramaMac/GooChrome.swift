import SwiftUI
import MeltoramaCore

/// One light source, above and to the left, ties the console's materials
/// together. Opaque fills also work with Reduce Transparency enabled.
enum GooTint {
    case berry, aqua, lime, amber, violet, ice

    var color: Color {
        switch self {
        case .berry: return Color(red: 0.94, green: 0.15, blue: 0.46)
        case .aqua: return Color(red: 0.02, green: 0.66, blue: 0.72)
        case .lime: return Color(red: 0.64, green: 0.80, blue: 0.14)
        case .amber: return Color(red: 0.96, green: 0.57, blue: 0.09)
        case .violet: return Color(red: 0.56, green: 0.31, blue: 0.91)
        case .ice: return Color(red: 0.42, green: 0.76, blue: 0.91)
        }
    }

    var ink: Color {
        switch self {
        case .violet: return .white
        default: return Color(white: 0.06)
        }
    }

    static func brush(_ tool: BrushTool) -> Self {
        switch tool {
        case .smear, .move, .smudge, .nudge, .comb, .fault, .echo, .whip: return .berry
        case .grow, .shrink, .melt, .smooth, .ungoo, .rewind: return .lime
        case .vortex, .unwind, .fuse: return .violet
        case .pond, .freeze: return .ice
        case .pins: return .amber
        }
    }
}

struct GooPanelSurface: View {
    var cornerRadius: CGFloat = 10
    var inset = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let dark = scheme == .dark
        let shades: [Color] = dark
            ? [Color(white: 0.26), Color(white: 0.18), Color(white: 0.21), Color(white: 0.13)]
            : [Color(white: 0.96), Color(white: 0.83), Color(white: 0.89), Color(white: 0.78)]
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(LinearGradient(colors: inset ? Array(shades.reversed()) : shades,
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(dark ? 0.22 : 0.8), .black.opacity(0.35)],
                                                 startPoint: inset ? .bottomTrailing : .topLeading,
                                                 endPoint: inset ? .topLeading : .bottomTrailing),
                                  lineWidth: contrast == .increased ? 2 : 1)
            }
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct GooWellSurface: View {
    var cornerRadius: CGFloat = 8
    var dark = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(LinearGradient(colors: scheme == .dark || dark ? [Color(white: 0.075), Color(white: 0.13)]
                                                        : [Color(white: 0.69), Color(white: 0.82)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.black.opacity(contrast == .increased ? 0.8 : 0.38), lineWidth: 1)
            }
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct GooScrew: View {
    var body: some View {
        Circle().fill(LinearGradient(colors: [Color(white: 0.82), Color(white: 0.30)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(Circle().strokeBorder(.black.opacity(0.55), lineWidth: 0.7))
            .overlay(Rectangle().fill(.black.opacity(0.7)).frame(width: 6, height: 1).rotationEffect(.degrees(-35)))
            .frame(width: 9, height: 9).shadow(color: .black.opacity(0.25), radius: 1, y: 1)
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct GooWordmark: View {
    var compact = false
    var body: some View {
        HStack(spacing: compact ? 4 : 8) {
            Text(L("Meltorama").uppercased())
                .font(.system(size: compact ? 12 : 25, weight: .black, design: .rounded))
                .italic().tracking(compact ? 0.5 : 1)
                .shadow(color: .white.opacity(0.15), radius: 0, y: 1)
            Text(L("2000"))
                .font(.system(size: compact ? 9 : 13, weight: .bold, design: .monospaced))
                .padding(.horizontal, compact ? 4 : 7).padding(.vertical, compact ? 3 : 5)
                .background(GooPanelSurface(cornerRadius: 4, inset: true))
        }.accessibilityElement(children: .ignore).accessibilityLabel(L("Meltorama 2000"))
    }
}

struct GooDome: View {
    let tint: GooTint
    let symbol: String
    var selected = false
    var size: CGFloat = 32
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(white: 0.94), Color(white: 0.28), Color(white: 0.70)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().fill(RadialGradient(gradient: Gradient(stops: [
                .init(color: tint.color, location: 0), .init(color: tint.color, location: 0.75),
                .init(color: Color(white: 0.08), location: 1)
            ]), center: .init(x: 0.3, y: 0.15), startRadius: 0, endRadius: size * 0.85))
                .padding(2.5)
            Circle().strokeBorder(.black.opacity(0.55), lineWidth: 1).padding(2)
            Ellipse().fill(LinearGradient(colors: [.white.opacity(0.78), .white.opacity(0.03)],
                                         startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.55, height: size * 0.25).rotationEffect(.degrees(-15))
                .offset(x: -size * 0.07, y: -size * 0.22)
            Image(systemName: symbol).font(.system(size: size * 0.43, weight: .semibold))
                .foregroundStyle(tint.ink).shadow(color: .black.opacity(0.25), radius: 0, y: 1)
        }.frame(width: size, height: size)
            .shadow(color: selected ? tint.color.opacity(0.45) : .black.opacity(0.3), radius: selected ? 4 : 1.5, y: 2)
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct GooToolButtonStyle: ButtonStyle {
    let tint: GooTint
    let selected: Bool
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity).padding(.vertical, 3)
            .background(GooPanelSurface(cornerRadius: 7, inset: selected || configuration.isPressed))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(selected ? tint.color : .clear,
                                                                    lineWidth: contrast == .increased ? 3 : 2)
                .allowsHitTesting(false).accessibilityHidden(true))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(focused ? Color.accentColor : .clear, lineWidth: 3).padding(-2)
                .allowsHitTesting(false).accessibilityHidden(true))
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(enabled ? 1 : 0.45)
    }
}

struct GooModeButtonStyle: ButtonStyle {
    let selected: Bool
    @Environment(\.isFocused) private var focused
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity).frame(height: 30)
            .background(GooPanelSurface(cornerRadius: 5, inset: selected || configuration.isPressed))
            .overlay(alignment: .bottom) {
                if selected { Capsule().fill(Color.primary).frame(width: 14, height: 3).padding(.bottom, 2).allowsHitTesting(false).accessibilityHidden(true) }
            }
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(focused ? Color.accentColor : .clear, lineWidth: 2)
                .allowsHitTesting(false).accessibilityHidden(true))
    }
}

struct GooActionButtonStyle: ButtonStyle {
    var tint: GooTint = .aqua
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint.ink).padding(.horizontal, 13).frame(minHeight: 28)
            .background {
                // The color stays opaque behind every text stroke. Depth is
                // confined to the lower lip instead of dimming the text band.
                Capsule().fill(LinearGradient(gradient: Gradient(stops: [
                    .init(color: tint.color, location: 0), .init(color: tint.color, location: 0.83),
                    .init(color: tint.color.opacity(0.65), location: 1)
                ]), startPoint: .top, endPoint: .bottom))
                    .background(Capsule().fill(Color(white: 0.08)))
                    .overlay(Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.75), .black.opacity(0.5)],
                                                                  startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5))
                    .overlay(alignment: .top) { Capsule().fill(.white.opacity(0.25)).frame(height: 8).padding(.horizontal, 5).padding(.top, 2) }
                    .shadow(color: .black.opacity(0.25), radius: 2, y: configuration.isPressed ? 0 : 2)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            .overlay(Capsule().strokeBorder(focused ? Color.accentColor : .clear, lineWidth: 3).padding(-3)
                .allowsHitTesting(false).accessibilityHidden(true))
            .contentShape(Capsule()).scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(enabled ? 1 : 0.4)
    }
}

struct GooUtilityButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.primary).padding(.horizontal, 8).frame(minHeight: 26)
            .background(GooPanelSurface(cornerRadius: 5, inset: configuration.isPressed))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(focused ? Color.accentColor : .clear, lineWidth: 2).padding(-1)
                .allowsHitTesting(false).accessibilityHidden(true))
            .contentShape(RoundedRectangle(cornerRadius: 5)).opacity(enabled ? 1 : 0.4)
    }
}
