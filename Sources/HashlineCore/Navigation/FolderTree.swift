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
