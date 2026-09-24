import AppKit
import HashlineCore

/// Pandoc, installed and chosen by the user (Settings ▸ Export). Hashline never looks for it on
/// its own and runs it only for an export or import the user started; arguments are an array.
@MainActor
enum PandocRunner {
    private static let bookmarkKey = "pandocBookmark"

    enum Failure: LocalizedError {
        case notConfigured
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured: String(localized: "Pandoc is needed for this format.")
            case .failed(let message): String(localized: "Pandoc could not convert the document.\n\n\(message)")
            }
        }
    }

    /// The chosen executable, with sandbox access started; nil until the user chooses one.
    static var executable: URL? {
        #if DEBUG || HASHLINE_TEST_HOOKS
        if let path = UserDefaults.standard.string(forKey: "HashlinePandocPath") { return URL(fileURLWithPath: path) }
        #endif
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                 bookmarkDataIsStale: &isStale) else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        return url
    }

    /// Lets the user pick the pandoc binary (the dialog starts where Homebrew installs it).
    @discardableResult
    static func choose() -> URL? {
        let panel = NSOpenPanel()
        panel.message = String(localized: "Choose the pandoc program (install it from pandoc.org or with Homebrew).")
        panel.prompt = String(localized: "Use Pandoc")
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        panel.treatsFilePackagesAsDirectories = true
        for folder in ["/opt/homebrew/bin", "/usr/local/bin"] where FileManager.default.fileExists(atPath: folder) {
            panel.directoryURL = URL(fileURLWithPath: folder, isDirectory: true)
            break
        }
        guard panel.runModal() == .OK, let url = panel.url,
              let bookmark = try? url.bookmarkData(options: .withSecurityScope) else { return nil }
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        return url
    }

    static func forget() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }

    /// Explains what is missing and offers to choose Pandoc; true when it is configured afterwards.
    static func ensureConfigured(for window: NSWindow?) -> Bool {
        if executable != nil { return true }
        let alert = NSAlert()
        alert.messageText = String(localized: "Pandoc is needed for this format")
        alert.informativeText = String(localized: """
            Hashline exports HTML, PDF and PNG by itself. Word, OpenDocument, RTF, ePub, LaTeX and other \
            formats go through Pandoc, a free converter. Install it (pandoc.org or “brew install pandoc”), \
            then choose the program here.
            """)
        alert.addButton(withTitle: String(localized: "Choose Pandoc…"))
        alert.addButton(withTitle: String(localized: "Download Pandoc"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return choose() != nil
        case .alertSecondButtonReturn:
            if let url = URL(string: "https://pandoc.org/installing.html") { NSWorkspace.shared.open(url) }
            return false
        default:
            return false
        }
    }

    /// Version line, for Settings.
    static func version() async -> String? {
        guard let executable else { return nil }
        let result = try? await run(executable, arguments: ["--version"], input: nil)
        return result.flatMap { String(data: $0, encoding: .utf8) }?.split(whereSeparator: \.isNewline).first
            .map(String.init)
    }

    /// Runs Pandoc off the main thread with standard input and output through temporary files
    /// (large documents cannot fill and block a pipe). Throws with Pandoc's error text.
    /// `resultFile` names a file Pandoc writes in its working folder (binary formats); without it the
    /// result is standard output.
    static func run(arguments: [String], input: Data?, resultFile: String? = nil) async throws -> Data {
        guard let executable else { throw Failure.notConfigured }
        return try await run(executable, arguments: arguments, input: input, resultFile: resultFile)
    }

    private static func run(_ executable: URL, arguments: [String], input: Data?,
                            resultFile: String? = nil) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("pandoc-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let inputURL = folder.appendingPathComponent("in")
            let outputURL = folder.appendingPathComponent("out")
            let errorURL = folder.appendingPathComponent("err")
            try (input ?? Data()).write(to: inputURL)
            FileManager.default.createFile(atPath: outputURL.path, contents: nil)
            FileManager.default.createFile(atPath: errorURL.path, contents: nil)

            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.currentDirectoryURL = folder
            process.standardInput = try FileHandle(forReadingFrom: inputURL)
            process.standardOutput = try FileHandle(forWritingTo: outputURL)
            process.standardError = try FileHandle(forWritingTo: errorURL)
            try process.run()
            let deadline = Date(timeIntervalSinceNow: 120)
            while process.isRunning, Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
            if process.isRunning { process.terminate() }
            guard process.terminationStatus == 0 else {
                let message = (try? String(contentsOf: errorURL, encoding: .utf8)) ?? ""
                throw Failure.failed(String(message.suffix(600)))
            }
            return try Data(contentsOf: resultFile.map { folder.appendingPathComponent($0) } ?? outputURL)
        }.value
    }
}
