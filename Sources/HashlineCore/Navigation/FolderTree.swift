import Foundation

/// A folder or document in the library tree.
public struct FolderNode: Sendable, Hashable, Identifiable {
    public let name: String
    /// Path inside the library, e.g. `Notes/2026`.
    public let path: String
    /// The document, for leaves.
    public let document: LibraryDocument?
    /// Sub-folders first, then documents, each sorted by name; nil for documents.
    public let children: [FolderNode]?

    public var id: String { path }
}

public enum FolderTree {
    /// Builds the tree from the scanned documents' relative paths.
    public static func build(_ documents: [LibraryDocument]) -> [FolderNode] {
        final class Folder {
            var folders: [String: Folder] = [:]
            var documents: [LibraryDocument] = []
        }
        let root = Folder()
        for document in documents {
            var folder = root
            for component in document.relativePath.split(separator: "/").dropLast() {
                let name = String(component)
                let next = folder.folders[name] ?? Folder()
                folder.folders[name] = next
                folder = next
            }
            folder.documents.append(document)
        }
        func nodes(_ folder: Folder, prefix: String) -> [FolderNode] {
            let order: (String, String) -> Bool = { $0.localizedStandardCompare($1) == .orderedAscending }
            let folders = folder.folders.keys.sorted(by: order).map { name -> FolderNode in
                let path = prefix.isEmpty ? name : prefix + "/" + name
                return FolderNode(name: name, path: path, document: nil,
                                  children: nodes(folder.folders[name] ?? Folder(), prefix: path))
            }
            let files = folder.documents
                .sorted { order($0.url.lastPathComponent, $1.url.lastPathComponent) }
                .map { FolderNode(name: $0.url.lastPathComponent, path: $0.relativePath, document: $0, children: nil) }
            return folders + files
        }
        return nodes(root, prefix: "")
    }
}

/// One level of the library: its sub-folders and the documents directly inside it.
public struct FolderListing: Sendable, Equatable {
    public struct Subfolder: Sendable, Hashable, Identifiable {
        public let name: String
        /// Path inside the library, e.g. `Notes/2026`.
        public let path: String
        /// Documents in the folder and all its sub-folders.
        public let documentCount: Int

        public var id: String { path }
    }

    /// Sorted by name.
    public let folders: [Subfolder]
    /// In the order of the scanned documents (newest first).
    public let documents: [LibraryDocument]
}

extension FolderTree {
    /// The content of the folder at `path` (`""` is the library itself). Folders exist only as far
    /// as they contain documents, so an `assets` folder with images alone is not listed.
    public static func listing(_ documents: [LibraryDocument], in path: String) -> FolderListing {
        let prefix = path.isEmpty ? "" : path + "/"
        var counts: [String: Int] = [:]
        var direct: [LibraryDocument] = []
        for document in documents where document.relativePath.hasPrefix(prefix) {
            let rest = document.relativePath.dropFirst(prefix.count)
            if let slash = rest.firstIndex(of: "/") {
                counts[String(rest[..<slash]), default: 0] += 1
            } else {
                direct.append(document)
            }
        }
        let folders = counts.keys
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { FolderListing.Subfolder(name: $0, path: prefix + $0, documentCount: counts[$0] ?? 0) }
        return FolderListing(folders: folders, documents: direct)
    }

    /// `path` or its nearest ancestor that still contains documents (after a rescan).
    public static func existingFolder(_ path: String, in documents: [LibraryDocument]) -> String {
        var path = path
        while !path.isEmpty, !documents.contains(where: { $0.relativePath.hasPrefix(path + "/") }) {
            path = (path as NSString).deletingLastPathComponent
        }
        return path
    }
}
