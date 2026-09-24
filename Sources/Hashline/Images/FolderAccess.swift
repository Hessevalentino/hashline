import AppKit
import HashlineCore
import Observation

/// Folders the sandboxed app may read and write beyond the open document: the library and folders
/// the user granted (security-scoped bookmarks, remembered across launches).
@MainActor
@Observable
final class FolderAccess {
    static let shared = FolderAccess()

    private(set) var grantedFolders: [URL] = []
    private static let bookmarksKey = "grantedFolderBookmarks"

    private init() {
        for data in UserDefaults.standard.array(forKey: Self.bookmarksKey) as? [Data] ?? [] {
            var isStale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                     bookmarkDataIsStale: &isStale),
                  url.startAccessingSecurityScopedResource() else { continue }
            grantedFolders.append(url)
        }
    }

    /// Whether `url` lies inside the library, a granted folder or the app's own container.
    nonisolated static func isAccessible(_ url: URL, roots: [URL]) -> Bool {
        let container = FileManager.default.temporaryDirectory.deletingLastPathComponent()
        return ImageLinks.isInside(url, roots: roots + [container])
    }

    /// Roots readable right now (library folder included when the library is configured).
    var roots: [URL] {
        grantedFolders + [LibraryStore.shared.folder].compactMap { $0 }
    }

    func canAccess(_ url: URL) -> Bool {
        Self.isAccessible(url, roots: roots)
    }

    /// Asks the user to grant a folder (the open panel starts there). Returns the granted folder.
    @discardableResult
    func requestAccess(to folder: URL, message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = folder
        panel.prompt = String(localized: "Allow Access")
        panel.message = message
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard url.startAccessingSecurityScopedResource() || canAccess(url) else { return nil }
        grantedFolders.append(url)
        if let bookmark = try? url.bookmarkData(options: .withSecurityScope) {
            var stored = UserDefaults.standard.array(forKey: Self.bookmarksKey) as? [Data] ?? []
            stored.append(bookmark)
            UserDefaults.standard.set(stored, forKey: Self.bookmarksKey)
        }
        return url
    }
}
