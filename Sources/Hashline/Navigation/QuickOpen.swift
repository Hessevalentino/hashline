import AppKit
import HashlineCore
import SwiftUI

/// Quick Open (⌘P): library documents and recent files, fuzzy-matched by name, title and path.
struct QuickOpenView: View {
    struct Candidate: Identifiable, Hashable {
        let url: URL
        let title: String
        let detail: String
        var id: URL { url }
        var searchKey: String { url.lastPathComponent + " " + title + " " + detail }
    }

    let onClose: () -> Void
    @State private var query = ""
    @State private var selection: URL?
    @FocusState private var isFieldFocused: Bool

    private var candidates: [Candidate] {
        let library = LibraryStore.shared.items.map {
            Candidate(url: $0.url, title: $0.title, detail: $0.relativePath)
        }
        let known = Set(library.map(\.url.standardizedFileURL))
        let recent = NSDocumentController.shared.recentDocumentURLs
            .filter { !known.contains($0.standardizedFileURL) }
            .map { Candidate(url: $0, title: $0.deletingPathExtension().lastPathComponent,
                             detail: ($0.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath) }
        return recent + library
    }

    private var results: [Candidate] {
        Array(FuzzyMatch.rank(candidates, query: query, key: \.searchKey).prefix(50))
    }

    var body: some View {
        let results = results
        VStack(spacing: 0) {
            TextField("Open quickly", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(12)
                .focused($isFieldFocused)
                .accessibilityIdentifier("quickOpenField")
                .onSubmit { open(selection ?? results.first?.url) }
                .onKeyPress(.downArrow) { move(1, in: results) }
                .onKeyPress(.upArrow) { move(-1, in: results) }
            Divider()
            List(results, selection: $selection) { candidate in
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.title).lineLimit(1)
                    Text(candidate.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        .truncationMode(.middle)
                }
                .tag(candidate.url)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { open(candidate.url) }
            }
            .listStyle(.plain)
            .overlay {
                if results.isEmpty {
                    Text(candidates.isEmpty ? String(localized: "Choose a library folder to open documents quickly.")
                         : String(localized: "No matches"))
                        .foregroundStyle(.secondary).padding()
                }
            }
        }
        .frame(width: 520, height: 380)
        .onAppear { isFieldFocused = true }
        .onChange(of: query) { selection = nil }
        .onExitCommand { onClose() }
    }

    private func move(_ delta: Int, in results: [Candidate]) -> KeyPress.Result {
        guard !results.isEmpty else { return .handled }
        let current = results.firstIndex { $0.url == selection } ?? (delta > 0 ? -1 : results.count)
        selection = results[min(max(current + delta, 0), results.count - 1)].url
        return .handled
    }

    private func open(_ url: URL?) {
        guard let url else { return }
        let window = NSApp.keyWindow
        onClose()
        DocumentReveal.open(url, range: nil, besides: window)
    }
}
