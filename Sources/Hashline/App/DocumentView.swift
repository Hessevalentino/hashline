import AppKit
import SwiftUI

/// Document window: library (optional), source editor and HTML preview (as in MacDown).
struct DocumentView: View {
    @State private var session: EditorSession
    @AppStorage(PreviewSettings.showsPreviewKey) private var showsPreview = true
    @AppStorage(LibrarySettings.showsLibraryKey) private var showsLibrary = false

    let fileURL: URL?

    init(document: MarkdownDocument, fileURL: URL?) {
        _session = State(initialValue: EditorSession(document: document))
        self.fileURL = fileURL
    }

    @AppStorage(ViewSettings.readingModeKey) private var readingMode = false
    @AppStorage(ViewSettings.statusBarKey) private var showsStatusBar = false
    @State private var showsQuickOpen = false

    var body: some View {
        VStack(spacing: 0) {
            if session.conflict.diskText != nil {
                ConflictBanner(session: session, name: fileURL?.lastPathComponent ?? "This document")
            }
            HSplitView {
                if showsLibrary {
                    // The store (and the folder scan) is created only when the panel is first shown.
                    Sidebar(store: LibraryStore.shared, session: session)
                        .frame(minWidth: SplitSettings.libraryWidths.lowerBound, idealWidth: 270,
                               maxWidth: SplitSettings.libraryWidths.upperBound, maxHeight: .infinity)
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("Sidebar")
                }
                // Reading mode removes the editor but keeps its view in the session (caret, scroll,
                // undo survive). The preview keeps its place, so its web view is never re-parented.
                if !readingMode {
                    VStack(spacing: 0) {
                        if session.find.isVisible {
                            FindBar(find: session.find)
                            Divider()
                        }
                        MarkdownEditor(session: session)
                    }
                    .frame(minWidth: SplitSettings.editorMinWidth, idealWidth: 600,
                           maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Editor")
                }
                if showsPreview || readingMode {
                    PreviewColumn(controller: session.previewController())
                        .frame(minWidth: SplitSettings.previewMinWidth, idealWidth: 600,
                               maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("Preview")
                }
            }
            .background {
                // Opened in reading mode: the editor joins the window unseen, outside the split,
                // so it becomes editable (and starts the preview) without flashing the split layout.
                if readingMode && !session.readiness.isEditable {
                    MarkdownEditor(session: session)
                        .frame(width: 1, height: 1)
                        .opacity(0)
                        .accessibilityHidden(true)
                }
            }
            if showsStatusBar {
                StatusBar(status: session.status)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Status bar")
            }
        }
        .focusedSceneValue(\.editorSession, session)
        .sheet(isPresented: $showsQuickOpen) {
            QuickOpenView { showsQuickOpen = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showQuickOpen)) { notification in
            if (notification.object as? EditorSession) === session { showsQuickOpen = true }
        }
        .onAppear {
            session.documentURL = fileURL
            session.setReadingMode(readingMode)
        }
        .onChange(of: fileURL) { _, url in session.documentURL = url }
        .onChange(of: session.readiness.isEditable) { _, editable in
            // Opened in reading mode: the editor was shown until it was ready; hide it now.
            if editable, readingMode { DispatchQueue.main.async { session.setReadingMode(true) } }
        }
        .onChange(of: readingMode) { _, reading in
            // After SwiftUI has moved the preview, which may create its web view.
            DispatchQueue.main.async { session.setReadingMode(reading) }
        }
        .onChange(of: showsStatusBar) { _, shows in if shows { session.refreshStatus() } }
    }
}

/// The file was changed by another application while it has unsaved edits here.
private struct ConflictBanner: View {
    let session: EditorSession
    let name: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
            Text("“\(name)” was changed by another application.").lineLimit(1)
            Spacer()
            Button("Reload") { session.reloadFromDisk() }
                .help("Discard your changes and show the version on disk")
            Button("Keep Mine") { session.keepEditedVersion() }
                .help("Keep your version; saving replaces the one on disk")
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.orange.opacity(0.15))
    }
}

/// Words, characters, lines and reading time; the selection's counts while text is selected.
private struct StatusBar: View {
    let status: DocumentStatus

    var body: some View {
        HStack(spacing: 14) {
            if let selection = status.selection {
                Text("Selection: \(selection.words) words, \(selection.characters) characters")
            }
            Spacer()
            let document = status.document
            Text("\(document.words) words")
            Text("\(document.characters) characters")
            Text("\(document.lines) lines")
            Text("\(document.readingMinutes) min read")
        }
        .font(.caption)
        .monospacedDigit()
        .padding(.horizontal, 12)
        .frame(height: 22)
        // Opaque: text on a translucent material fails the contrast check.
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// The preview with a banner when images in a folder cannot be read yet.
private struct PreviewColumn: View {
    let controller: PreviewController

    var body: some View {
        VStack(spacing: 0) {
            if let folder = controller.status.blockedFolder {
                HStack(spacing: 8) {
                    Image(systemName: "photo.badge.exclamationmark")
                    Text("Images in “\(folder.lastPathComponent)” need access.")
                        .lineLimit(1)
                    Spacer()
                    Button("Allow Access…") {
                        let message = "Hashline needs access to this folder to show its images."
                        if FolderAccess.shared.requestAccess(to: folder, message: message) != nil {
                            controller.reloadAfterAccessGranted()
                        }
                    }
                    Button { controller.status.blockedFolder = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                }
                .font(.callout)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.yellow.opacity(0.15))
            }
            PreviewPane(controller: controller)
        }
    }
}

enum SyntaxExtensionSettings {
    static let highlightKey = "extensionHighlight"
    static let superscriptKey = "extensionSuperscript"
    static let subscriptKey = "extensionSubscript"
}

enum PreviewSettings {
    static let showsPreviewKey = "showsPreview"

    /// Editor + preview ↔ editor alone. From reading mode it goes straight to editor + preview.
    @MainActor
    static func togglePreview() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: ViewSettings.readingModeKey) {
            defaults.set(true, forKey: showsPreviewKey)
            defaults.set(false, forKey: ViewSettings.readingModeKey)
            return
        }
        let shows = defaults.object(forKey: showsPreviewKey) == nil || defaults.bool(forKey: showsPreviewKey)
        defaults.set(!shows, forKey: showsPreviewKey)
    }
}

extension FocusedValues {
    /// The editor session of the key document window.
    @Entry var editorSession: EditorSession?
}

extension Notification.Name {
    static let showQuickOpen = Notification.Name("HashlineShowQuickOpen")
}

struct PreviewCommands: Commands {
    @FocusedValue(\.editorSession) private var session
    @AppStorage(PreviewSettings.showsPreviewKey) private var showsPreview = true
    @AppStorage(LibrarySettings.showsLibraryKey) private var showsLibrary = false
    @AppStorage(ViewSettings.readingModeKey) private var readingMode = false

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button(showsLibrary ? String(localized: "Hide Library") : String(localized: "Show Library")) {
                showsLibrary.toggle()
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            let hidesPreview = showsPreview && !readingMode
            Button(hidesPreview ? String(localized: "Hide Preview") : String(localized: "Show Preview")) {
                PreviewSettings.togglePreview()
            }
            .keyboardShortcut("p", modifiers: [.command, .option])
        }
        CommandGroup(before: .sidebar) {
            ViewModeCommands()
        }
        CommandGroup(after: .appInfo) {
            UpdateCommand()
        }
        CommandGroup(after: .newItem) {
            Button("New Document in Library") {
                LibraryStore.shared.createDocument(besides: NSApp.keyWindow)
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
            Button("Add Files to Library…") { LibraryStore.shared.importFiles() }
            Divider()
            Button("Quick Open…") {
                NotificationCenter.default.post(name: .showQuickOpen, object: session)
            }
            .keyboardShortcut("p")
            .disabled(session == nil)
        }
        CommandGroup(replacing: .importExport) {
            Menu("Export") {
                ForEach(ExportFormat.allCases, id: \.identifier) { format in
                    if case .pandoc(.docx) = format { Divider() }
                    Button(String(localized: "\(format.title)…")) {
                        session.map { Exporter.export($0, format: format) }
                    }
                        .disabled(session == nil)
                }
            }
            Button("Export…") { session.map { Exporter.export($0, format: nil) } }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(session == nil)
            Button("Export as Markdown…") { session.map { Exporter.export($0, format: .markdown) } }
                .keyboardShortcut("e", modifiers: [.command, .option])
                .disabled(session == nil)
            Divider()
            Button("Share…") { session.map(Sharing.showPicker(for:)) }
                .disabled(session == nil)
            Button("Send with AirDrop…") { session.map(Sharing.sendWithAirDrop) }
                .disabled(session == nil)
            Button("Import with Pandoc…") { Exporter.importDocument() }
        }
        CommandGroup(replacing: .printItem) {
            // ⌘P is Quick Open (as in Typora and code editors); printing uses the preview.
            Button("Print…") { session?.printPreview() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(session == nil)
        }
        CommandGroup(after: .textEditing) {
            Menu("Find") {
                findButton("Find…", .showFindInterface, "f")
                findButton("Find and Replace…", .showReplaceInterface, "f", [.command, .option])
                findButton("Find Next", .nextMatch, "g")
                findButton("Find Previous", .previousMatch, "g", [.command, .shift])
                findButton("Use Selection for Find", .setSearchString, "e")
                Divider()
                Button("Find in Library…") { SidebarFocus.shared.showFolderSearch() }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
            }
        }
    }

    private func findButton(_ title: LocalizedStringKey, _ action: NSTextFinder.Action, _ key: KeyEquivalent,
                            _ modifiers: EventModifiers = .command) -> some View {
        Button(title) { session?.find.perform(action) }
            .keyboardShortcut(key, modifiers: modifiers)
            .disabled(session == nil)
    }
}

/// View ▸ reading mode, focus, typewriter, status bar and text width.
private struct ViewModeCommands: View {
    @AppStorage(AppearanceMode.key) private var appearance = AppearanceMode.system.rawValue
    @AppStorage(ViewSettings.readingModeKey) private var readingMode = false
    @AppStorage(ViewSettings.focusModeKey) private var focusMode = false
    @AppStorage(ViewSettings.typewriterModeKey) private var typewriterMode = false
    @AppStorage(ViewSettings.statusBarKey) private var showsStatusBar = false
    @AppStorage(ViewSettings.textWidthKey) private var textWidth = ViewSettings.defaultWidth

    var body: some View {
        Picker("Appearance", selection: $appearance) {
            ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                Text(mode.title).tag(mode.rawValue)
            }
        }
        Toggle("Reading Mode", isOn: measured("reading", $readingMode))
            .keyboardShortcut("/", modifiers: .command)
        Toggle("Focus Mode", isOn: measured("focus", $focusMode))
            .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSF8FunctionKey) ?? " ")), modifiers: [])
        Toggle("Typewriter Mode", isOn: measured("typewriter", $typewriterMode))
            .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSF9FunctionKey) ?? " ")), modifiers: [])
        Toggle("Show Status Bar", isOn: measured("status bar", $showsStatusBar))
            .keyboardShortcut("i", modifiers: [.command, .option])
        Picker("Text Width", selection: measured("text width", $textWidth)) {
            ForEach(ViewSettings.widths, id: \.characters) { width in
                Text(width.label).tag(width.characters)
            }
        }
        Divider()
    }

    /// Logs how long the switch takes to reach the screen (budget < 50 ms).
    private func measured<Value>(_ name: String, _ binding: Binding<Value>) -> Binding<Value> {
        Binding(get: { binding.wrappedValue }, set: { value in
            ModeSwitchMetrics.measure(name) { binding.wrappedValue = value }
        })
    }
}

/// Hashline ▸ Check for Updates… (release builds only).
private struct UpdateCommand: View {
    @State private var updater = Updater.shared

    var body: some View {
        if Updater.isEnabled {
            Button("Check for Updates…") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
        }
    }
}
