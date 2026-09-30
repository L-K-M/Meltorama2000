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
    @AppStorage("hideBrushCursor") private var hideBrushCursor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L("Meltorama Settings")).font(.title2)
            Picker(L("Appearance"), selection: $appearance) {
                ForEach(AppearancePreference.allCases) { preference in
                    Text(L(preference.title)).tag(preference)
                }
            }.pickerStyle(.menu)
            Toggle(L("Show brush cursor"), isOn: Binding(get: { !hideBrushCursor }, set: { hideBrushCursor = !$0 }))
            Text(L("Projects autosave after editing. Recovery drafts protect photos you have not named yet. All editing and export happen on your Mac."))
                .font(.callout).foregroundStyle(.secondary)
        }.padding(24).frame(width: 410)
            .onChange(of: appearance) { preference in preference.apply() }
    }
}
