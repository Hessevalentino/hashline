import AppKit
import SwiftUI

/// Editor font, size, line height and text width.
struct EditorSettingsView: View {
    @AppStorage(AppearanceSettings.fontNameKey) private var fontName = ""
    @AppStorage(AppearanceSettings.fontSizeKey) private var fontSize = AppearanceSettings.defaultFontSize
    @AppStorage(AppearanceSettings.lineHeightKey) private var lineHeight = AppearanceSettings.defaultLineHeight
    @AppStorage(ViewSettings.textWidthKey) private var textWidth = ViewSettings.defaultWidth
    @AppStorage(ViewSettings.statusBarKey) private var showsStatusBar = false

    /// Fixed-width families: Markdown source reads best monospaced. Value = the family's regular face.
    private static let fonts: [(family: String, face: String)] = {
        let manager = NSFontManager.shared
        return manager.availableFontFamilies.compactMap { family in
            guard let face = manager.availableMembers(ofFontFamily: family)?.first?.first as? String,
                  NSFont(name: face, size: 12)?.isFixedPitch == true else { return nil }
            return (family, face)
        }
    }()

    var body: some View {
        Form {
            Picker("Font:", selection: $fontName) {
                Text("System Monospaced").tag("")
                Divider()
                ForEach(Self.fonts, id: \.face) { font in
                    Text(verbatim: font.family).tag(font.face)
                }
            }
            Stepper(value: $fontSize, in: 9...36, step: 1) {
                Text("Size: \(Int(fontSize)) pt")
            }
            Picker("Line height:", selection: $lineHeight) {
                ForEach([1.0, 1.15, 1.25, 1.4, 1.6, 1.8], id: \.self) { value in
                    Text(value.formatted(.number.precision(.fractionLength(0...2)))).tag(value)
                }
            }
            Picker("Text width:", selection: $textWidth) {
                ForEach(ViewSettings.widths, id: \.characters) { width in
                    Text(width.label).tag(width.characters)
                }
            }
            Toggle("Show status bar (words, characters, reading time)", isOn: $showsStatusBar)
        }
        .formStyle(.columns)
    }
}

/// Library folder and what a new window shows.
struct GeneralSettingsView: View {
    @AppStorage(PreviewSettings.showsPreviewKey) private var showsPreview = true
    @AppStorage(LibrarySettings.showsLibraryKey) private var showsLibrary = false
    @State private var library = LibraryStore.shared

    var body: some View {
        Form {
            Section("Library") {
                LabeledContent("Folder:") {
                    Text(verbatim: library.folder.map { ($0.path as NSString).abbreviatingWithTildeInPath }
                         ?? String(localized: "Not chosen"))
                        .lineLimit(1).truncationMode(.middle)
                }
                HStack {
                    Button("Choose Folder…") { library.chooseFolder() }
                    Button("Show in Finder") { library.revealInFinder() }
                        .disabled(library.folder == nil)
                }
                Text("New documents from the library (⌥⌘N) are saved in this folder.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Windows") {
                Toggle("Show the preview", isOn: $showsPreview)
                Toggle("Show the sidebar", isOn: $showsLibrary)
            }
            if Updater.isEnabled {
                Section("Updates") {
                    Toggle("Check for updates weekly", isOn: Binding(
                        get: { Updater.shared.automaticallyChecks },
                        set: { Updater.shared.automaticallyChecks = $0 }))
                    Button("Check for Updates…") { Updater.shared.checkForUpdates() }
                }
            }
        }
        .formStyle(.columns)
    }
}
