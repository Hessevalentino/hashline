import AppKit
import HashlineCore
import SwiftUI

/// Library panel on the left of the document window (ADR 0006).
struct LibrarySidebar: View {
    @Bindable var store: LibraryStore
    @State private var selection: Selection?
    @State private var isDropTargeted = false

    /// A row of the list: a sub-folder to enter or a document to open.
    private enum Selection: Hashable {
        case folder(String)
        case document(URL)
    }

    private var isBrowsing: Bool { store.query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            if store.folder == nil {
                LibraryEmptyState(store: store)
            } else {
                searchField
                Divider()
                if isBrowsing && !store.currentFolder.isEmpty {
                    folderBar
                    Divider()
                }
                list
                Divider()
                bottomBar
            }
        }
        .background(.background.secondary)
        .dropDestination(for: URL.self) { urls, _ in
            store.importFiles(urls)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: 2).padding(2)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search title or text", text: $store.query)
                .textFieldStyle(.plain)
            if store.isSearchingContent { ProgressView().controlSize(.small) }
            if !store.query.isEmpty {
                Button { store.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    /// The browsed folder and the way back up.
    private var folderBar: some View {
        HStack(spacing: 6) {
            Button {
                store.currentFolder = (store.currentFolder as NSString).deletingLastPathComponent
            } label: {
                Label("Back", systemImage: "chevron.left").labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Back")
            Image(systemName: "folder").foregroundStyle(.secondary)
            Text((store.currentFolder as NSString).lastPathComponent)
                .font(.body.weight(.semibold)).lineLimit(1)
                .help(store.currentFolder)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private var list: some View {
        let listing = store.currentListing
        return List(selection: $selection) {
            if isBrowsing {
                ForEach(listing.folders) { folder in
                    Label(folder.name, systemImage: "folder")
                        .lineLimit(1)
                        .badge(folder.documentCount)
                        .help(folder.path)
                        .tag(Selection.folder(folder.path))
                }
                ForEach(listing.documents) { item in
                    LibraryRow(title: item.title, detail: item.snippet, date: item.modified, path: item.relativePath,
                               showsFolder: false)
                        .tag(Selection.document(item.url))
                }
            } else {
                ForEach(store.visibleItems) { item in
                    LibraryRow(title: item.title, detail: item.snippet, date: item.modified, path: item.relativePath)
                        .tag(Selection.document(item.url))
                }
            }
            if !store.contentMatches.isEmpty {
                Section("In text") {
                    ForEach(store.contentMatches, id: \.item.url) { match in
                        LibraryRow(title: match.item.title, detail: match.line, date: match.item.modified,
                                   path: match.item.relativePath)
                            .tag(Selection.document(match.item.url))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if isBrowsing && !store.isScanning && listing.folders.isEmpty && listing.documents.isEmpty {
                Text(store.currentFolder.isEmpty ? "No documents yet" : "Empty folder").foregroundStyle(.secondary)
            }
        }
        .onChange(of: selection) { _, selection in
            switch selection {
            case .folder(let path):
                store.currentFolder = path
                self.selection = nil
            case .document(let url):
                guard let item = (store.items.first { $0.url == url }) else { return }
                store.openDocument(item, besides: NSApp.keyWindow)
            case nil:
                break
            }
        }
        .contextMenu(forSelectionType: Selection.self) { selections in
            if selections.isEmpty {
                Button("New Folder…") { store.createFolder() }
                Button("New Document") { store.createDocument(besides: NSApp.keyWindow) }
            } else if selections.count == 1, case .folder(let path) = selections.first {
                LibraryFolderMenu(store: store, path: path)
            } else {
                LibraryItemMenu(store: store, urls: selections.compactMap {
                    if case .document(let url) = $0 { url } else { nil }
                })
            }
        }
        // Edit ▸ Delete and ⌘⌫ on the selected document.
        .onDeleteCommand { if case .document(let url) = selection { store.moveToTrash([url]) } }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button { store.createDocument(besides: NSApp.keyWindow) } label: { Image(systemName: "square.and.pencil") }
                .help("New Document in Library (⌥⌘N)")
            Button { store.importFiles() } label: { Image(systemName: "plus") }
                .help("Add Files to Library…")
            Button { store.createFolder() } label: { Image(systemName: "folder.badge.plus") }
                .help("New Folder…")
            Spacer()
            Menu {
                Button("Show in Finder") { store.revealInFinder() }
                Button("Change Library Folder…") { store.chooseFolder() }
            } label: {
                Label(store.folder?.lastPathComponent ?? "", systemImage: "folder")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

/// Right-click menu of library documents (list and folder tree).
struct LibraryItemMenu: View {
    let store: LibraryStore
    let urls: [URL]

    var body: some View {
        if !urls.isEmpty {
            Button("Open") {
                for url in urls { store.openDocument(at: url, besides: NSApp.keyWindow) }
            }
            Button("Show in Finder") { store.revealInFinder(urls) }
            if urls.count == 1, let url = urls.first {
                Button("Rename…") { store.rename(url) }
            }
            Divider()
            ShareLink(items: urls)
            Button("Send with AirDrop…") { Sharing.sendWithAirDrop(urls) }
            Divider()
            Button("Move to Trash", role: .destructive) { store.moveToTrash(urls) }
                .keyboardShortcut(.delete, modifiers: .command)
        }
    }
}

/// Right-click menu of a library folder. Moving it to the Trash asks first (ADR 0006).
private struct LibraryFolderMenu: View {
    let store: LibraryStore
    let path: String

    var body: some View {
        Button("Open") { store.currentFolder = path }
        Button("Show in Finder") {
            if let root = store.folder { store.revealInFinder([root.appendingPathComponent(path, isDirectory: true)]) }
        }
        Divider()
        Button("Move to Trash…", role: .destructive) { store.moveFolderToTrash(path) }
    }
}

/// Shown instead of library content until a folder is chosen.
struct LibraryEmptyState: View {
    let store: LibraryStore

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical").font(.system(size: 34)).foregroundStyle(.secondary)
            Text("Library").font(.headline)
            Text("Choose a folder for your Markdown documents. New documents are saved there.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Choose Folder…") { store.chooseFolder() }
                .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LibraryRow: View {
    let title: String
    let detail: String
    let date: Date
    let path: String
    /// The folder under the date; off while browsing, where it is the browsed folder.
    var showsFolder = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.body.weight(.semibold)).lineLimit(1)
            if !detail.isEmpty {
                Text(detail).font(.callout).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack(spacing: 4) {
                Text(date, format: .dateTime.day().month(.abbreviated).year())
                if showsFolder, path.contains("/") { Text("· " + (path as NSString).deletingLastPathComponent) }
            }
            .font(.caption).foregroundStyle(.tertiary).lineLimit(1)
        }
        .padding(.vertical, 3)
        .help(path)
    }
}

enum LibrarySettings {
    static let showsLibraryKey = "showsLibrary"
    static let sidebarTabKey = "sidebarTab"
}
