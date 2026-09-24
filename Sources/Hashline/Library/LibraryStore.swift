import AppKit
import CoreServices
import HashlineCore
import Observation
import UniformTypeIdentifiers

/// The library folder shared by all windows: access via a security-scoped bookmark,
/// the scanned list, search and file operations.
@MainActor
@Observable
final class LibraryStore {
    static let shared = LibraryStore()

    private(set) var folder: URL?
    private(set) var items: [LibraryDocument] = []
    private(set) var contentMatches: [LibraryMatch] = []
    private(set) var isScanning = false
    private(set) var isSearchingContent = false
    var query = "" {
        didSet { scheduleContentSearch() }
    }

    /// Documents whose title or path matches the query; all documents without a query.
    var visibleItems: [LibraryDocument] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return items }
        return items.filter { LibraryIndex.matchesName($0, query: trimmed) }
    }

    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var watcher: FolderWatcher?
    private static let bookmarkKey = "libraryBookmark"

    private init() {
        #if DEBUG || HASHLINE_TEST_HOOKS
        if let name = UserDefaults.standard.string(forKey: "HashlineLibraryFolder") {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            open(url, persist: false)
            return
        }
        #endif
        restoreBookmark()
    }

    // MARK: Folder

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Choose Library")
        panel.message = String(localized: "Choose the folder where your Markdown documents are stored.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url, persist: true)
    }

    private func open(_ url: URL, persist: Bool) {
        folder?.stopAccessingSecurityScopedResource()
        _ = url.startAccessingSecurityScopedResource()
        folder = url
        if persist, let bookmark = try? url.bookmarkData(options: .withSecurityScope) {
            UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
        }
        watcher = FolderWatcher(url: url) { [weak self] in self?.rescan() }
        rescan()
    }

    private func restoreBookmark() {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                 bookmarkDataIsStale: &isStale) else { return }
        open(url, persist: isStale)
    }

    func revealInFinder() {
        guard let folder else { return }
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    // MARK: Scanning and search

    func rescan() {
        guard let folder else { return }
        scanTask?.cancel()
        isScanning = true
        scanTask = Task { [weak self] in
            let signpost = Performance.signposter.beginInterval("LibraryScan")
            let items = await Task.detached(priority: .userInitiated) { LibraryIndex.scan(folder) }.value
            Performance.signposter.endInterval("LibraryScan", signpost)
            guard let self, !Task.isCancelled else { return }
            self.items = items
            self.isScanning = false
            self.scheduleContentSearch()
            self.scheduleFolderSearch()
        }
    }

    private func scheduleContentSearch() {
        searchTask?.cancel()
        let query = query.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2 else {
            contentMatches = []
            isSearchingContent = false
            return
        }
        let items = items
        isSearchingContent = true
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))  // wait for the user to stop typing
            guard !Task.isCancelled else { return }
            let matches = await Task.detached(priority: .userInitiated) {
                LibraryIndex.searchContent(items, query: query) { Task.isCancelled }
            }.value
            guard let self, !Task.isCancelled else { return }
            let named = Set(self.visibleItems.map(\.url))
            self.contentMatches = matches.filter { !named.contains($0.item.url) }
            self.isSearchingContent = false
        }
    }

    // MARK: Find in library (⇧⌘F)

    var folderQuery = SearchQuery(text: "") {
        didSet { if folderQuery != oldValue { scheduleFolderSearch() } }
    }
    private(set) var folderResults: [FileSearchResult] = []
    private(set) var isSearchingFolder = false
    private(set) var folderSearchError: String?
    @ObservationIgnored private var folderSearchTask: Task<Void, Never>?

    private func scheduleFolderSearch() {
        folderSearchTask?.cancel()
        let query = folderQuery
        guard !query.text.isEmpty, !(query.text.count < 2 && !query.isRegex) else {
            folderResults = []
            isSearchingFolder = false
            folderSearchError = nil
            return
        }
        let items = items
        isSearchingFolder = true
        folderSearchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            let signpost = Performance.signposter.beginInterval("FolderSearch")
            let result = await Task.detached(priority: .userInitiated) { () -> Result<[FileSearchResult], Error> in
                Result { try LibraryIndex.searchFiles(items, query: query) { Task.isCancelled } }
            }.value
            Performance.signposter.endInterval("FolderSearch", signpost)
            guard let self, !Task.isCancelled else { return }
            switch result {
            case .success(let results):
                self.folderResults = results
                self.folderSearchError = nil
            case .failure:
                self.folderResults = []
                self.folderSearchError = String(localized: "Invalid pattern")
            }
            self.isSearchingFolder = false
        }
    }

    // MARK: Documents

    /// Opens a library document as a tab of `window` (or brings it forward if already open).
    func openDocument(_ item: LibraryDocument, besides window: NSWindow?) {
        openDocument(at: item.url, besides: window)
    }

    func openDocument(at url: URL, besides window: NSWindow?) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { document, _, error in
            if let error {
                let path = url.lastPathComponent
                Performance.logger.error(
                    "Opening \(path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
                )
                return
            }
            MainActor.assumeIsolated {
                guard let window, let newWindow = document?.windowControllers.first?.window, newWindow !== window,
                      !(window.tabbedWindows ?? []).contains(newWindow) else { return }
                window.addTabbedWindow(newWindow, ordered: .above)
                newWindow.makeKeyAndOrderFront(nil)
            }
        }
    }

    /// Creates `Untitled.md` in the library and opens it; no save panel.
    func createDocument(besides window: NSWindow?) {
        guard let folder else { return chooseFolder() }
        let url = LibraryIndex.uniqueURL(for: "Untitled.md", in: folder)
        guard FileManager.default.createFile(atPath: url.path, contents: Data()) else { return }
        rescan()
        let item = LibraryDocument(url: url, relativePath: url.lastPathComponent, title: "Untitled",
                               modified: .now, snippet: "")
        openDocument(item, besides: window)
    }

    func importFiles() {
        guard let folder else { return chooseFolder() }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [UTType(importedAs: "net.daringfireball.markdown"), .plainText]
        panel.prompt = String(localized: "Add to Library")
        guard panel.runModal() == .OK else { return }
        importFiles(panel.urls, into: folder)
    }

    func importFiles(_ urls: [URL]) {
        guard let folder else { return }
        let documents = urls.filter {
            LibraryIndex.extensions.contains($0.pathExtension.lowercased()) || $0.pathExtension.lowercased() == "txt"
        }
        importFiles(documents, into: folder)
    }

    private func importFiles(_ urls: [URL], into folder: URL) {
        do {
            _ = try LibraryIndex.importFiles(urls, into: folder)
        } catch {
            NSAlert(error: error).runModal()
        }
        rescan()
    }
}

/// FSEvents on a folder (recursive), coalesced to one callback per 0.5 s: the library and the
/// themes folder. Delivered on the main queue, so a callback can never overlap with deinit.
@MainActor
final class FolderWatcher {
    // Set once in init, released in deinit; FSEvents functions are thread-safe.
    nonisolated(unsafe) private var stream: FSEventStreamRef?
    private let onChange: @MainActor () -> Void

    init(url: URL, onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            MainActor.assumeIsolated { watcher.onChange() }
        }
        stream = FSEventStreamCreate(nil, callback, &context, [url.path] as CFArray,
                                     FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5,
                                     FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer))
        if let stream {
            FSEventStreamSetDispatchQueue(stream, .main)
            FSEventStreamStart(stream)
        }
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
