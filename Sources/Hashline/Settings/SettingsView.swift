import SwiftUI

/// Settings: as few items as possible (ADR 0006).
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            EditorSettingsView()
                .tabItem { Label("Editor", systemImage: "character.cursor.ibeam") }
            AppearanceSettingsView()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            ImagesSettings()
                .tabItem { Label("Images", systemImage: "photo") }
            ExportSettings()
                .tabItem { Label("Export", systemImage: "square.and.arrow.up") }
        }
        .frame(width: 520)
        .scenePadding()
    }
}

private struct ImagesSettings: View {
    @AppStorage(ImageSettings.perDocumentFolderKey) private var perDocumentFolder = false
    @AppStorage(ImageSettings.uploaderEnabledKey) private var uploaderEnabled = false
    @AppStorage(ImageSettings.loadsRemoteImagesKey) private var loadsRemoteImages = true
    @State private var program = ImageUploader.chosenProgram?.path
    @AppStorage(ImageSettings.uploaderArgumentsKey) private var uploaderArguments = "{file}"

    var body: some View {
        Form {
            Picker("Store pasted and dropped images in:", selection: $perDocumentFolder) {
                Text("assets/ next to the document").tag(false)
                Text("<document name>.assets/").tag(true)
            }
            .pickerStyle(.radioGroup)
            Toggle("Load remote images in the preview", isOn: $loadsRemoteImages)
            Text("A remote image tells its server that you opened the document. Local images always show.")
                .font(.caption)

            Divider()
            Toggle("Upload images with a command", isOn: $uploaderEnabled)
            LabeledContent("Program:") {
                HStack {
                    Text(verbatim: program ?? String(localized: "Not chosen"))
                        .lineLimit(1).truncationMode(.middle)
                    Button("Choose…") { program = ImageUploader.chooseProgram()?.path ?? program }
                }
            }
            .disabled(!uploaderEnabled)
            TextField("Arguments:", text: $uploaderArguments, prompt: Text(verbatim: "upload {file}"))
                .disabled(!uploaderEnabled)
            Text("""
                The program receives the image path in place of {file} and must print the image URL. It runs only \
                when switched on here, never through a shell.
                """)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .formStyle(.columns)
    }
}

/// Pandoc for Word, OpenDocument, RTF, ePub, LaTeX… (HTML, PDF and PNG need nothing).
private struct ExportSettings: View {
    @State private var path = PandocRunner.executable?.path
    @State private var version: String?

    var body: some View {
        Form {
            LabeledContent("Pandoc:") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(path ?? "Not chosen").foregroundStyle(path == nil ? .secondary : .primary)
                        .lineLimit(1).truncationMode(.middle)
                    if let version { Text(version).font(.caption).foregroundStyle(.secondary) }
                    HStack {
                        Button("Choose…") {
                            path = PandocRunner.choose()?.path ?? path
                            Task { version = await PandocRunner.version() }
                        }
                        if path != nil {
                            Button("Forget") {
                                PandocRunner.forget()
                                path = nil
                                version = nil
                            }
                        }
                    }
                }
            }
            // One literal: a concatenated string would not be localized.
            Text("""
                HTML, PDF and PNG are exported by Hashline itself. Other formats and File ▸ Import use Pandoc, \
                which you install separately (pandoc.org or “brew install pandoc”). Hashline runs it only for \
                exports and imports you start.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task { version = await PandocRunner.version() }
    }
}
