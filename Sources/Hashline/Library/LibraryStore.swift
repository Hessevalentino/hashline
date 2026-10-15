import AppKit
import CoreServices
import HashlineCore
import Observation

/// A folder of the library: where it is and the name it shows under at the top of the library.
struct LibraryRoot: Sendable, Hashable, Identifiable {
    let name: String
    let url: URL

    var id: URL { url }
}

/// The library folders shared by all windows: access via security-scoped bookmarks,
/// the scanned list, search and file operations. Every folder is a top-level folder of the
/// library, so relative paths start with its name (`Notes/Ideas/a.md`).
@MainActor
@Observable
final class LibraryStore {
    static let shared = LibraryStore()

    private(set) var roots: [LibraryRoot] = []
    private(set) var items: [LibraryDocument] = []
    /// Relative paths of all library sub-folders, empty ones included.
    private(set) var folders: [String] = []
    private(set) var contentMatches: [LibraryMatch] = []
    private(set) var isScanning = false
    private(set) var isSearchingContent = false
    var query = "" {
        didSet { scheduleContentSearch() }
    }
    /// The folder browsed in the Documents list, relative to the library (`""` is the library itself).
    /// New and added documents go there. Shared by all windows, like the library.
    var currentFolder = ""

    /// Sub-folders and documents of `currentFolder`.
    var currentListing: FolderListing { FolderTree.listing(items, folders: folders, in: currentFolder) }

    /// Where new and added documents go: the browsed folder; at the top level the first library folder.
    var targetFolder: URL? {
        currentFolder.isEmpty ? roots.first?.url : url(forPath: currentFolder)
    }

    /// The folder at a library path (`<library folder>/…`); nil for an unknown library folder.
    func url(forPath path: String) -> URL? {
        let components = path.split(separator: "/", maxSplits: 1).map(String.init)
        guard let name = components.first, let root = roots.first(where: { $0.name == name }) else { return nil }
        return components.count > 1 ? root.url.appendingPathComponent(components[1], isDirectory: true) : root.url
    }

    /// Documents whose title or path matches the query; all documents without a query.
    var visibleItems: [LibraryDocument] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return items }
        return items.filter { LibraryIndex.matchesName($0, query: trimmed) }
    }

    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var watchers: [FolderWatcher] = []
    /// Off for the temporary folders of test hooks, which must not replace the user's library.
    @ObservationIgnored private var persistsRoots = true
    private static let bookmarksKey = "libraryBookmarks"
    /// The single library folder of versions before 0.3.4; read until `bookmarksKey` exists and kept,
    /// so an older version still finds its library.
    private static let legacyBookmarkKey = "libraryBookmark"

    private init() {
        #if DEBUG || HASHLINE_TEST_HOOKS
        // Comma-separated names of temporary folders.
        if let names = UserDefaults.standard.string(forKey: "HashlineLibraryFolder") {
            let urls = names.split(separator: ",").map {
                FileManager.default.temporaryDirectory.appendingPathComponent(String($0), isDirectory: true)
            }
            urls.forEach { try? FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true) }
            persistsRoots = false
            setRoots(urls)
            return
        }
        #endif
        restoreBookmarks()
    }

    // MARK: Folders

    /// Asks for one or more folders and adds them to the library. A folder inside a library folder
    /// (or containing one) is refused: its documents would show twice.
    func addFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Add to Library")
        panel.message = String(localized: "Choose folders where your Markdown documents are stored.")
        guard panel.runModal() == .OK else { return }
        var urls = roots.map(\.url)
        var refused: [String] = []
        for url in panel.urls {
            if LibraryIndex.overlaps(url, with: urls) {
                refused.append((url.path as NSString).abbreviatingWithTildeInPath)
            } else {
                _ = url.startAccessingSecurityScopedResource()
                urls.append(url)
            }
        }
        if urls.count > roots.count { setRoots(urls) }
        if !refused.isEmpty {
            let alert = NSAlert()
            alert.messageText = String(localized: """
                A folder that is already in the library, lies inside a library folder or contains one \
                cannot be added.
                """)
            alert.informativeText = refused.joined(separator: "\n")
            alert.runModal()
        }
    }

    /// Removes a folder from the library; nothing on disk changes. Access to the folder stays until
    /// quit, so documents still open from it can be saved.
    func removeFolder(_ root: LibraryRoot) {
        guard roots.contains(root) else { return }
        setRoots(roots.map(\.url).filter { $0 != root.url })
    }

    private func setRoots(_ urls: [URL]) {
        roots = zip(LibraryIndex.rootNames(for: urls), urls).map { LibraryRoot(name: $0, url: $1) }
        currentFolder = ""
        if persistsRoots {
            let bookmarks = urls.compactMap { try? $0.bookmarkData(options: .withSecurityScope) }
            UserDefaults.standard.set(bookmarks, forKey: Self.bookmarksKey)
        }
        watchers = urls.map { FolderWatcher(url: $0) { [weak self] in self?.rescan() } }
        rescan()
    }

    private func restoreBookmarks() {
        let defaults = UserDefaults.standard
        let current = defaults.array(forKey: Self.bookmarksKey) as? [Data]
        let stored = current ?? defaults.data(forKey: Self.legacyBookmarkKey).map { [$0] } ?? []
        var anyStale = current == nil
        let urls = stored.compactMap { data -> URL? in
            var isStale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                     bookmarkDataIsStale: &isStale) else { return nil }
            anyStale = anyStale || isStale
            _ = url.startAccessingSecurityScopedResource()
            return url
        }
        guard !urls.isEmpty else { return }
        persistsRoots = anyStale
        setRoots(urls)
        persistsRoots = true
    }

    // MARK: Scanning and search

    func rescan() {
        scanTask?.cancel()
        let roots = roots
        guard !roots.isEmpty else {
            items = []
            folders = []
            isScanning = false
            return
        }
        isScanning = true
        scanTask = Task { [weak self] in
            let signpost = Performance.signposter.beginInterval("LibraryScan")
            let (items, folders) = await Task.detached(priority: .userInitiated) {
                let parts = roots.map { LibraryIndex.scanContents($0.url, prefix: $0.name) }
                return (parts.flatMap(\.documents).sorted { $0.modified > $1.modified }, parts.flatMap(\.folders))
            }.value
            Performance.signposter.endInterval("LibraryScan", signpost)
            guard let self, !Task.isCancelled else { return }
            self.items = items
            self.folders = folders
            self.currentFolder = FolderTree.existingFolder(self.currentFolder, in: items, folders: folders)
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
}

/// FSEvents on a folder (recursive), coalesced to one callback per 0.5 s: the library folders and the
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
