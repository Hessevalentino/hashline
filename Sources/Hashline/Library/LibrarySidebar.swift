import AppKit
import HashlineCore
import SwiftUI

/// Library panel on the left of the document window (ADR 0006).
struct LibrarySidebar: View {
    @Bindable var store: LibraryStore
    @State private var selection: URL?
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            if store.folder == nil {
                LibraryEmptyState(store: store)
            } else {
                searchField
                Divider()
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

    private var list: some View {
        List(selection: $selection) {
            ForEach(store.visibleItems) { item in
                LibraryRow(title: item.title, detail: item.snippet, date: item.modified, path: item.relativePath)
                    .tag(item.url)
            }
            if !store.contentMatches.isEmpty {
                Section("In text") {
                    ForEach(store.contentMatches, id: \.item.url) { match in
                        LibraryRow(title: match.item.title, detail: match.line, date: match.item.modified,
                                   path: match.item.relativePath)
                            .tag(match.item.url)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if store.items.isEmpty && !store.isScanning {
                Text("No documents yet").foregroundStyle(.secondary)
            }
        }
        .onChange(of: selection) { _, url in
            guard let url, let item = (store.items.first { $0.url == url }) else { return }
            store.openDocument(item, besides: NSApp.keyWindow)
        }
        .contextMenu(forSelectionType: URL.self) { urls in
            LibraryItemMenu(store: store, urls: Array(urls))
        }
        // Edit ▸ Delete and ⌘⌫ on the selected document.
        .onDeleteCommand { if let selection { store.moveToTrash([selection]) } }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button { store.createDocument(besides: NSApp.keyWindow) } label: { Image(systemName: "square.and.pencil") }
                .help("New Document in Library (⌥⌘N)")
            Button { store.importFiles() } label: { Image(systemName: "plus") }
                .help("Add Files to Library…")
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
            Divider()
            Button("Move to Trash", role: .destructive) { store.moveToTrash(urls) }
                .keyboardShortcut(.delete, modifiers: .command)
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.body.weight(.semibold)).lineLimit(1)
            if !detail.isEmpty {
                Text(detail).font(.callout).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack(spacing: 4) {
                Text(date, format: .dateTime.day().month(.abbreviated).year())
                if path.contains("/") { Text("· " + (path as NSString).deletingLastPathComponent) }
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
