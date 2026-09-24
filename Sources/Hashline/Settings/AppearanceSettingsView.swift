import AppKit
import SwiftUI

/// Themes for light and dark mode.
struct AppearanceSettingsView: View {
    @AppStorage(AppearanceSettings.lightThemeKey) private var lightTheme = AppearanceSettings.defaultLight
    @AppStorage(AppearanceSettings.darkThemeKey) private var darkTheme = AppearanceSettings.defaultDark
    @AppStorage(AppearanceMode.key) private var appearance = AppearanceMode.system.rawValue
    @State private var store = ThemeStore.shared

    var body: some View {
        Form {
            Picker("Appearance:", selection: $appearance) {
                ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            Section("Themes") {
                themePicker("Light mode:", selection: $lightTheme, dark: false)
                    .accessibilityIdentifier("lightThemePicker")
                themePicker("Dark mode:", selection: $darkTheme, dark: true)
                    .accessibilityIdentifier("darkThemePicker")
                HStack {
                    Button("Duplicate Current Theme…") {
                        let dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                        store.duplicate(store.theme(dark: dark))
                    }
                    Button("Open Themes Folder") { store.revealUserFolder() }
                }
                Text("""
                    A theme is a folder with theme.json (editor colours) and theme.css (preview and export). \
                    Changes to themes in the folder apply immediately.
                    """)
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(store.problems, id: \.self) { problem in
                    Label(problem, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.columns)
    }

    private func themePicker(_ title: LocalizedStringKey, selection: Binding<String>, dark: Bool) -> some View {
        Picker(title, selection: selection) {
            ForEach(store.themes.filter { $0.isDark == dark }) { theme in
                Text(theme.isBuiltIn ? theme.definition.name : String(localized: "\(theme.definition.name) (custom)"))
                    .tag(theme.id)
            }
        }
    }
}
