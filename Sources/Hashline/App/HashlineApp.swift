import SwiftUI

@main
struct HashlineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        LaunchMetrics.begin()
        // Open an untitled document at launch instead of the iCloud open panel.
        UserDefaults.standard.register(defaults: ["NSShowAppCentricOpenPanelInsteadOfUntitledFile": false])
    }

    var body: some Scene {
        DocumentGroup(newDocument: { MarkdownDocument() }, editor: { file in
            DocumentView(document: file.document, fileURL: file.fileURL)
                .frame(minWidth: 640, minHeight: 300)
        })
        .defaultSize(width: 1280, height: 860)
        .commands {
            PreviewCommands()
            FormatCommands()
        }

        Settings {
            SettingsView()
        }
    }
}
