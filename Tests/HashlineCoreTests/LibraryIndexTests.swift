import Foundation
import Testing
@testable import HashlineCore

struct LibraryIndexTests {
    static func makeFolder(_ files: [String: String]) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lib-\(UUID().uuidString)")
        for (path, content) in files {
            let url = folder.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data(content.utf8).write(to: url)
        }
        return folder
    }

    @Test func scansMarkdownRecursivelyNewestFirst() throws {
        let folder = try Self.makeFolder([
            "a.md": "# Alpha\n\nFirst **text** here.",
            "Sub/b.markdown": "No heading, just [a link](/x).",
            "c.txt": "not markdown",
            ".hidden.md": "# Hidden",
        ])
        defer { try? FileManager.default.removeItem(at: folder) }
        let old = Date(timeIntervalSinceNow: -3_600)
        let path = folder.appendingPathComponent("a.md").path
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: path)

        let items = LibraryIndex.scan(folder)
        #expect(items.map(\.relativePath) == ["Sub/b.markdown", "a.md"])
        #expect(items.map(\.title) == ["b", "a"])
        #expect(items.map(\.snippet) == ["No heading, just a link.", "Alpha · First text here."])
    }

    @Test func titleFromFrontMatter() {
        let summary = LibraryIndex.summarize(text: "---\ntitle: \"Kniha\"\ndate: 2026\n---\n# Kapitola\n\nText")
        #expect(summary.title == "Kniha")
        #expect(summary.snippet == "Kapitola Text")
    }

    @Test func searchIgnoresCaseAndDiacritics() throws {
        let folder = try Self.makeFolder([
            "kun.md": "# Kůň\n\nPříliš žluťoučký kůň úpěl.",
            "other.md": "# Other\n\nNothing here.",
        ])
        defer { try? FileManager.default.removeItem(at: folder) }
        let items = LibraryIndex.scan(folder)
        #expect(items.filter { LibraryIndex.matchesName($0, query: "kun") }.map(\.title) == ["kun"])
        let matches = LibraryIndex.searchContent(items, query: "ZLUTOUCKY")
        #expect(matches.map(\.item.title) == ["kun"])
        #expect(matches.first?.line == "Příliš žluťoučký kůň úpěl.")
    }

    @Test func importUsesUniqueNames() throws {
        let folder = try Self.makeFolder(["note.md": "old"])
        let source = try Self.makeFolder(["note.md": "new"])
        defer {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: source)
        }
        let imported = try LibraryIndex.importFiles([source.appendingPathComponent("note.md")], into: folder)
        #expect(imported.map(\.lastPathComponent) == ["note 2.md"])
        #expect(try String(contentsOf: imported[0], encoding: .utf8) == "new")
    }

    /// Budget from F6: 5 000 files listed within 300 ms. Opt-in (creates 5 000 files):
    /// `HASHLINE_PERF=1 swift test -c release --filter LibraryIndexTests`
    @Test(.enabled(if: ProcessInfo.processInfo.environment["HASHLINE_PERF"] != nil))
    func scanFiveThousandFiles() throws {
        var files: [String: String] = [:]
        for index in 0..<5_000 {
            files["Folder \(index % 50)/note \(index).md"] = "# Note \(index)\n\nPříliš žluťoučký kůň \(index)."
        }
        let folder = try Self.makeFolder(files)
        defer { try? FileManager.default.removeItem(at: folder) }
        let clock = ContinuousClock()
        var count = 0
        let scan = clock.measure { count = LibraryIndex.scan(folder).count }
        let items = LibraryIndex.scan(folder)
        let search = clock.measure { _ = LibraryIndex.searchContent(items, query: "kun 4999") }
        print("PERF library scan \(count) files: \(scan), content search: \(search)")
        #expect(count == 5_000)
    }

    @Test func renamedURLKeepsExtensionAndRejectsBadNames() throws {
        let folder = try Self.makeFolder(["a.md": "", "Taken.md": ""])
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("a.md")
        #expect(try LibraryIndex.renamedURL(url, to: " Notes ")?.lastPathComponent == "Notes.md")
        #expect(try LibraryIndex.renamedURL(url, to: "Notes.markdown")?.lastPathComponent == "Notes.markdown")
        #expect(try LibraryIndex.renamedURL(url, to: "v1.2")?.lastPathComponent == "v1.2.md")
        #expect(try LibraryIndex.renamedURL(url, to: "A")?.lastPathComponent == "A.md")
        #expect(try LibraryIndex.renamedURL(url, to: "a") == nil)
        #expect(throws: LibraryIndex.RenameError.empty) { try LibraryIndex.renamedURL(url, to: "  ") }
        #expect(throws: LibraryIndex.RenameError.invalidCharacters) { try LibraryIndex.renamedURL(url, to: "x/y") }
        #expect(throws: LibraryIndex.RenameError.exists) { try LibraryIndex.renamedURL(url, to: "Taken") }
    }
}
