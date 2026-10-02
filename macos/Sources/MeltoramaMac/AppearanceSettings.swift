import AppKit
import SwiftUI

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark
    static let storageKey = "appearancePreference"
    var id: Self { self }
    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    static func applySaved() {
        let preference = UserDefaults.standard.string(forKey: storageKey).flatMap(Self.init(rawValue:)) ?? .system
        preference.apply()
    }

    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

struct SettingsView: View {
    @AppStorage(AppearancePreference.storageKey) private var appearance: AppearancePreference = .system
    @AppStorage(ThemePreference.storageKey) private var storedTheme = ThemePreference.classic.rawValue
    @AppStorage("hideBrushCursor") private var hideBrushCursor = false
    private var theme: MacTheme { MacTheme(preference: ThemePreference.resolve(storedTheme)) }
    private var themeSelection: Binding<ThemePreference> {
        Binding(get: { ThemePreference.resolve(storedTheme) }, set: { storedTheme = $0.rawValue })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L("Meltorama Settings")).font(.title2)
            Picker(L("Appearance"), selection: $appearance) {
                ForEach(AppearancePreference.allCases) { preference in
                    Text(L(preference.title)).tag(preference)
                }
            }.pickerStyle(.menu)
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Theme")).font(.headline)
                Picker(L("Theme"), selection: themeSelection) {
                    ForEach(ThemePreference.allCases) { preference in
                        HStack(spacing: 8) {
                            palettePreview(preference).accessibilityHidden(true)
                            Text(L(preference.title))
                        }.tag(preference)
                    }
                }.pickerStyle(.radioGroup).labelsHidden()
                Text(L("Themes coordinate the titlebar, panels, workspace, and accents. Your photos keep their original colors."))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Toggle(L("Show brush cursor"), isOn: Binding(get: { !hideBrushCursor }, set: { hideBrushCursor = !$0 }))
            Text(L("Projects autosave after editing. Recovery drafts protect photos you have not named yet. All editing and export happen on your Mac."))
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }.padding(24).frame(width: 410)
            .background(theme.panelBackground)
            .tint(theme.accent)
            .onChange(of: appearance) { preference in preference.apply() }
    }

    private func palettePreview(_ preference: ThemePreference) -> some View {
        let palette = MacTheme(preference: preference)
        return HStack(spacing: -4) {
            swatch(palette.workspaceBackground)
            swatch(palette.chromeBackground)
            swatch(palette.accent)
        }
    }

    private func swatch(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 14, height: 14)
            .overlay(Circle().strokeBorder(.primary.opacity(0.2), lineWidth: 1))
    }
}
