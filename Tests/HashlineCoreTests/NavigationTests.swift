import Foundation
import Testing
@testable import HashlineCore

struct NavigationTests {
    // MARK: Outline

    @Test func outlineListsHeadingsWithRanges() {
        let text = "# Úvod\n\nText\n\nDruhý\n-----\n\n```\n# not a heading\n```\n### Třetí *kurzíva*\n"
        let items = DocumentOutline.items(in: BlockMap(text: text).blocks)
        #expect(items.map(\.title) == ["Úvod", "Druhý", "Třetí kurzíva"])
        #expect(items.map(\.level) == [1, 2, 3])
        #expect((text as NSString).substring(with: items[0].range) == "# Úvod")
        #expect(DocumentOutline.currentIndex(in: items, offset: 10) == 0)
        #expect(DocumentOutline.currentIndex(in: items, offset: items[2].range.location) == 2)
        #expect(DocumentOutline.currentIndex(in: [], offset: 3) == nil)
    }

    // MARK: Folder tree

    @Test func folderTreeGroupsFoldersFirst() {
        func document(_ path: String) -> LibraryDocument {
            LibraryDocument(url: URL(fileURLWithPath: "/lib/" + path), relativePath: path, title: path,
                            modified: .now, snippet: "")
        }
        let tree = FolderTree.build([document("b.md"), document("Notes/x.md"), document("a.md"),
                                     document("Notes/2026/y.md")])
        #expect(tree.map(\.name) == ["Notes", "a.md", "b.md"])
        #expect(tree[0].children?.map(\.name) == ["2026", "x.md"])
        #expect(tree[0].children?[0].children?.first?.path == "Notes/2026/y.md")
    }

    // MARK: Fuzzy

    @Test func fuzzyRanksWordStartsAndConsecutive() {
        let names = ["Zápisky z porady.md", "readme.md", "Plán projektu.md", "zprava.md"]
        #expect(FuzzyMatch.rank(names, query: "zp", key: { $0 }).first == "Zápisky z porady.md"
                || FuzzyMatch.rank(names, query: "zp", key: { $0 }).first == "zprava.md")
        #expect(FuzzyMatch.rank(names, query: "plan", key: { $0 }) == ["Plán projektu.md"])
        #expect(FuzzyMatch.score("xyz", in: "readme.md") == nil)
        #expect(FuzzyMatch.rank(names, query: "rdm", key: { $0 }).first == "readme.md")
    }

    // MARK: Find and replace

    @Test func literalSearchEscapesAndHonoursOptions() throws {
        let text = "a.b a.b A.B ab" as NSString
        #expect(try TextSearch.matches(of: SearchQuery(text: "a.b"), in: text).count == 3)
        #expect(try TextSearch.matches(of: SearchQuery(text: "a.b", caseSensitive: true), in: text).count == 2)
        let words = "cat concat cat." as NSString
        #expect(try TextSearch.matches(of: SearchQuery(text: "cat", wholeWords: true), in: words)
                == [NSRange(location: 0, length: 3), NSRange(location: 11, length: 3)])
    }

    @Test func regexReplaceAllUsesTemplatesAsOneEdit() throws {
        let text = "x 2026-09-24 y 2025-01-02 z" as NSString
        let query = SearchQuery(text: #"(\d{4})-(\d\d)-(\d\d)"#, isRegex: true)
        let result = try #require(try TextSearch.replaceAll(query, with: "$3.$2.$1", in: text))
        #expect(result.count == 2)
        #expect(result.edit.applied(to: text as String) == "x 24.09.2026 y 02.01.2025 z")
        #expect(result.edit.range == NSRange(location: 2, length: 23))
        let single = try TextSearch.replacement(for: NSRange(location: 2, length: 10), in: text, query: query,
                                                template: "[$1]")
        #expect(single == "[2026]")
    }

    @Test func literalReplacementIsNotATemplate() throws {
        let result = try #require(try TextSearch.replaceAll(SearchQuery(text: "a"), with: "$1\\", in: "banana"))
        #expect(result.edit.applied(to: "banana") == "b$1\\n$1\\n$1\\")
    }

    @Test func invalidRegexIsReported() {
        #expect(throws: SearchQuery.Failure.invalidPattern("(")) {
            try TextSearch.matches(of: SearchQuery(text: "(", isRegex: true), in: "()")
        }
    }

    @Test func nextWraps() {
        let matches = [NSRange(location: 2, length: 1), NSRange(location: 8, length: 1)]
        #expect(TextSearch.next(in: matches, after: 3) == matches[1])
        #expect(TextSearch.next(in: matches, after: 9) == matches[0])
        #expect(TextSearch.next(in: matches, after: 2, backwards: true) == matches[1])
    }

    // MARK: Folder search

    @Test func folderSearchReportsLinesAndIgnoresDiacritics() throws {
        let folder = try LibraryIndexTests.makeFolder([
            "a.md": "# Kůň\n\nPříliš žluťoučký kůň\núpěl ďábelské ódy\nkůň",
            "b.md": "nic",
            "c.md": "line one\r\nline two KUN",
        ])
        defer { try? FileManager.default.removeItem(at: folder) }
        let items = LibraryIndex.scan(folder)
        let results = try LibraryIndex.searchFiles(items, query: SearchQuery(text: "kun"))
            .sorted { $0.document.relativePath < $1.document.relativePath }
        #expect(results.map(\.document.relativePath) == ["a.md", "c.md"])
        #expect(results[0].lines.map(\.number) == [1, 3, 5])
        let line = results[0].lines[1]
        #expect(line.text == "Příliš žluťoučký kůň")
        #expect((line.text as NSString).substring(with: line.highlight) == "kůň")
        #expect(results[1].lines.map(\.number) == [2])

        let regex = try LibraryIndex.searchFiles(items, query: SearchQuery(text: #"^line \w+"#, isRegex: true))
        #expect(regex.first?.lines.count == 2)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["HASHLINE_PERF"] != nil))
    func folderSearchOf5000FilesIsFast() throws {
        var files: [String: String] = [:]
        for index in 0..<5_000 {
            files["d\(index / 100)/note\(index).md"] = "# Poznámka \(index)\n\n"
                + String(repeating: "Lorem ipsum dolor. ", count: 60)
                + (index % 250 == 0 ? "\nhledaný výraz\n" : "")
        }
        let folder = try LibraryIndexTests.makeFolder(files)
        defer { try? FileManager.default.removeItem(at: folder) }
        let items = LibraryIndex.scan(folder)
        let clock = ContinuousClock()
        var results: [FileSearchResult] = []
        let elapsed = try clock.measure {
            results = try LibraryIndex.searchFiles(items, query: SearchQuery(text: "hledany vyraz"))
        }
        print("Folder search 5 000 files: \(elapsed)")
        #expect(results.count == 20)
        #expect(elapsed < .milliseconds(300))
    }
}
