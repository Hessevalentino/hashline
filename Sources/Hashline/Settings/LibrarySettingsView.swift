import AppKit
import SwiftUI

/// The library folders: add, remove, show in Finder. Removing a folder changes nothing on disk.
struct LibrarySettingsView: View {
    @State private var library = LibraryStore.shared
    @State private var selection: LibraryRoot.ID?

    private var selectedRoot: LibraryRoot? { library.roots.first { $0.id == selection } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(library.roots, selection: $selection) { root in
                HStack(spacing: 8) {
                    Image(systemName: "folder").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: root.name)
                        Text(verbatim: (root.url.path as NSString).abbreviatingWithTildeInPath)
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
                .contextMenu {
                    Button("Show in Finder") { library.revealInFinder([root.url]) }
                    Button("Remove from Library") { library.removeFolder(root) }
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .accessibilityLabel("Library folders")
            .frame(height: 200)
            .overlay {
                if library.roots.isEmpty { Text("No folders").foregroundStyle(.secondary) }
            }
            HStack(spacing: 2) {
                Button { library.addFolders() } label: {
                    Image(systemName: "plus").frame(width: 22, height: 20)
                }
                .help("Add Folders…")
                Button {
                    if let root = selectedRoot { library.removeFolder(root) }
                } label: {
                    Image(systemName: "minus").frame(width: 22, height: 20)
                }
                .help("Remove from Library")
                .disabled(selectedRoot == nil)
                Spacer()
                Button("Show in Finder") {
                    if let root = selectedRoot { library.revealInFinder([root.url]) }
                }
                .disabled(selectedRoot == nil)
            }
            .buttonStyle(.borderless)
            .padding(.vertical, 6)
            Text("""
                Each folder appears at the top of the library under its name. New documents created at the \
                top level go to the first folder. Removing a folder from the library does not delete it.
                """)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
