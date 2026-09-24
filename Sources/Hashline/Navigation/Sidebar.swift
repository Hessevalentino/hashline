import AppKit
import HashlineCore
import SwiftUI

/// The left panel (⇧⌘L): library documents, folder tree, outline of this document, find in library.
struct Sidebar: View {
    enum Tab: String, CaseIterable {
        case documents, folders, outline, search

        var title: LocalizedStringResource {
            switch self {
            case .documents: "Documents"
            case .folders: "Folders"
            case .outline: "Outline"
            case .search: "Find in Library"
            }
        }

        var symbol: String {
            switch self {
            case .documents: "doc.text"
            case .folders: "folder"
            case .outline: "list.bullet.indent"
            case .search: "magnifyingglass"
            }
        }
    }

    let store: LibraryStore
    let session: EditorSession
    @AppStorage(LibrarySettings.sidebarTabKey) private var tab = Tab.documents

    var body: some View {
        VStack(spacing: 0) {
            Picker("Sidebar", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Image(systemName: tab.symbol).help(Text(tab.title)).tag(tab)
                        .accessibilityLabel(Text(tab.title))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            Divider()
            switch tab {
            case .documents:
                LibrarySidebar(store: store)
            case .folders:
                if store.folder == nil { LibraryEmptyState(store: store) } else { FolderTreeView(store: store) }
            case .outline:
                OutlineView(navigation: session.navigation, session: session)
            case .search:
                if store.folder == nil { LibraryEmptyState(store: store) } else { FolderSearchView(store: store) }
            }
        }
        .background(.background.secondary)
        .onChange(of: tab, initial: true) { _, tab in session.navigation.isOutlineVisible = tab == .outline }
        .onDisappear { session.navigation.isOutlineVisible = false }
    }
}

/// Library folders and documents as a tree.
private struct FolderTreeView: View {
    let store: LibraryStore
    @State private var selection: String?

    var body: some View {
        let tree = FolderTree.build(store.items)
        List(tree, children: \.children, selection: $selection) { node in
            Label(node.document?.title ?? node.name, systemImage: node.document == nil ? "folder" : "doc.text")
                .lineLimit(1)
                .help(node.path)
        }
        .listStyle(.sidebar)
        .onChange(of: selection) { _, path in
            guard let path, let document = store.items.first(where: { $0.relativePath == path }) else { return }
            store.openDocument(document, besides: NSApp.keyWindow)
        }
    }
}

/// Headings of the current document; the section with the caret is selected.
private struct OutlineView: View {
    let navigation: DocumentNavigation
    let session: EditorSession

    var body: some View {
        if navigation.outline.isEmpty {
            // In place of the list, not over it: text over the sidebar material fails the contrast check.
            Text("No headings")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            list
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(Array(navigation.outline.enumerated()), id: \.element.id) { index, item in
                    Button { session.jump(to: item) } label: {
                        Text(item.title)
                            .font(item.level == 1 ? .body.weight(.semibold) : .body)
                            .lineLimit(1)
                            .padding(.leading, CGFloat(item.level - 1) * 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(index == navigation.currentIndex
                                       ? Color.accentColor.opacity(0.18) : Color.clear)
                    .id(item.id)
                }
            }
            .listStyle(.sidebar)
            .onChange(of: navigation.currentIndex) { _, index in
                guard let index, navigation.outline.indices.contains(index) else { return }
                proxy.scrollTo(navigation.outline[index].id)
            }
        }
    }
}

/// Find in library (⇧⌘F): every matching line of every document; a click opens it at the match.
private struct FolderSearchView: View {
    @Bindable var store: LibraryStore
    @FocusState private var isFieldFocused: Bool
    @State private var focus = SidebarFocus.shared

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                TextField("Find in library", text: $store.folderQuery.text)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFieldFocused)
                    .accessibilityIdentifier("folderSearchField")
                HStack(spacing: 6) {
                    Toggle("Aa", isOn: $store.folderQuery.caseSensitive).help("Match Case")
                    Toggle("W", isOn: $store.folderQuery.wholeWords).help("Whole Words")
                    Toggle(".*", isOn: $store.folderQuery.isRegex).help("Regular Expression")
                    Spacer()
                    if store.isSearchingFolder { ProgressView().controlSize(.small) }
                    Text(summary).font(.caption).monospacedDigit()
                        .foregroundStyle(store.folderSearchError == nil ? Color.secondary : Color.red)
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .font(.system(.caption, design: .monospaced))
            }
            .padding(8)
            Divider()
            List {
                ForEach(store.folderResults) { result in
                    Section {
                        ForEach(result.lines) { line in
                            Button {
                                DocumentReveal.open(result.document.url, range: line.range, besides: NSApp.keyWindow)
                            } label: {
                                ResultLine(line: line)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text(result.document.relativePath).lineLimit(1).truncationMode(.middle)
                    }
                }
            }
            .listStyle(.sidebar)
        }
        // Focus only on request (⇧⌘F); a window opening with this tab keeps focus in the editor.
        .onAppear { if focus.takeSearchFocus() { focusField() } }
        .onChange(of: focus.searchRequest) { if focus.takeSearchFocus() { focusField() } }
    }

    /// When ⇧⌘F also opens the sidebar, the field joins the window a few run-loop turns later and the
    /// editor may take the focus back meanwhile; retry briefly until the field has it.
    private func focusField() {
        Task { @MainActor in
            for _ in 0..<10 {
                isFieldFocused = true
                try? await Task.sleep(for: .milliseconds(50))
                if isFieldFocused { return }
            }
        }
    }

    private var summary: String {
        if let error = store.folderSearchError { return error }
        guard !store.folderQuery.text.isEmpty, !store.isSearchingFolder else { return "" }
        let lines = store.folderResults.reduce(0) { $0 + $1.lines.count }
        return "\(lines) in \(store.folderResults.count) files"
    }
}

private struct ResultLine: View {
    let line: FileSearchResult.Line

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(line.number)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                .frame(minWidth: 24, alignment: .trailing)
            Text(highlighted).font(.callout).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var highlighted: AttributedString {
        let text = line.text
        var result = AttributedString(text)
        if let range = Range(line.highlight, in: text),
           let lower = AttributedString.Index(range.lowerBound, within: result),
           let upper = AttributedString.Index(range.upperBound, within: result) {
            result[lower..<upper].backgroundColor = .yellow.opacity(0.4)
            result[lower..<upper].font = .callout.bold()
        }
        return result
    }
}

/// Requests from menu commands to focus parts of the sidebar.
@MainActor
@Observable
final class SidebarFocus {
    static let shared = SidebarFocus()
    private(set) var searchRequest = 0
    @ObservationIgnored private var isSearchFocusPending = false

    /// Find in Library (⇧⌘F): shows the sidebar on the search tab and focuses its field.
    func showFolderSearch() {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: LibrarySettings.showsLibraryKey)
        defaults.set(Sidebar.Tab.search.rawValue, forKey: LibrarySettings.sidebarTabKey)
        isSearchFocusPending = true
        searchRequest += 1
    }

    /// True once per ⇧⌘F, for the search field that shows it.
    func takeSearchFocus() -> Bool {
        defer { isSearchFocusPending = false }
        return isSearchFocusPending
    }
}
