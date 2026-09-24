import Foundation

/// A Markdown document in the library folder.
public struct LibraryDocument: Sendable, Identifiable, Hashable {
    public let url: URL
    /// Path inside the library folder, e.g. `Notes/Idea.md`.
    public let relativePath: String
    /// First heading (or front matter `title:`), otherwise the file name.
    public let title: String
    public let modified: Date
    /// First lines of body text without Markdown markers.
    public let snippet: String

    public var id: URL { url }

    public init(url: URL, relativePath: String, title: String, modified: Date, snippet: String) {
        self.url = url
        self.relativePath = relativePath
        self.title = title
        self.modified = modified
        self.snippet = snippet
    }
}

/// A content search hit: the document and the line that matched.
public struct LibraryMatch: Sendable, Hashable {
    public let item: LibraryDocument
    public let line: String
}

/// Reading and searching the library folder. Pure file-system code, no UI; call off the main thread.
public enum LibraryIndex {
    public static let extensions: Set<String> = ["md", "markdown", "mdown", "mkd"]
    /// Bytes read per file for title and snippet.
    static let summaryLength = 4_096

    /// All Markdown files under `folder` (recursively, skipping hidden files and packages),
    /// newest first.
    public static func scan(_ folder: URL) -> [LibraryDocument] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        let base = folder.standardizedFileURL.path
        var items: [LibraryDocument] = []
        for case let url as URL in enumerator where extensions.contains(url.pathExtension.lowercased()) {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else {
                continue
            }
            let summary = summarize(url)
            let fallbackTitle = url.deletingPathExtension().lastPathComponent
            var relative = url.standardizedFileURL.path
            if relative.hasPrefix(base) { relative = String(relative.dropFirst(base.count)) }
            relative = relative.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            items.append(LibraryDocument(url: url, relativePath: relative, title: summary.title ?? fallbackTitle,
                                     modified: values.contentModificationDate ?? .distantPast,
                                     snippet: summary.snippet))
        }
        return items.sorted { $0.modified > $1.modified }
    }

    static func summarize(_ url: URL) -> (title: String?, snippet: String) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return (nil, "") }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: summaryLength)) ?? Data()
        // A cut in the middle of a UTF-8 sequence is dropped by the lossy decode.
        // A read cut inside a UTF-8 sequence fails strict decoding; drop the partial character.
        let text = (try? TextFileCodec.decode(data).text)
            ?? (try? TextFileCodec.decode(data.dropLast(3)).text) ?? ""
        return summarize(text: text)
    }

    // Line classification reads best as one loop.
    // swiftlint:disable:next cyclomatic_complexity
    static func summarize(text: String) -> (title: String?, snippet: String) {
        var title: String?
        var snippet: [String] = []
        var inFrontMatter = false
        var inCode = false
        for (index, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if index == 0, line == "---" { inFrontMatter = true; continue }
            if inFrontMatter {
                if line == "---" || line == "..." {
                    inFrontMatter = false
                } else if title == nil, line.lowercased().hasPrefix("title:") {
                    let value = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    if !value.isEmpty { title = value }
                }
                continue
            }
            if line.hasPrefix("```") || line.hasPrefix("~~~") { inCode.toggle(); continue }
            if inCode || line.isEmpty { continue }
            if line.hasPrefix("#") {
                let heading = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                if title == nil, !heading.isEmpty { title = heading; continue }
            }
            let plain = stripMarkers(line)
            if !plain.isEmpty { snippet.append(plain) }
            if snippet.joined(separator: " ").count > 160 { break }
        }
        let joined = snippet.joined(separator: " ")
        return (title, joined.count > 160 ? String(joined.prefix(160)) + "…" : joined)
    }

    private static func stripMarkers(_ line: String) -> String {
        var text = line
        text = text.replacingOccurrences(of: #"^(#{1,6}|>|[-*+]|\d+[.)])\s+(\[[ xX]\]\s+)?"#, with: "",
                                         options: .regularExpression)
        text = text.replacingOccurrences(of: #"!?\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"[*_`~]+"#, with: "", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Search

    /// Case- and diacritic-insensitive, so "zlutoucky" finds "žluťoučký".
    static let searchOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    public static func matchesName(_ item: LibraryDocument, query: String) -> Bool {
        item.title.range(of: query, options: searchOptions) != nil
            || item.relativePath.range(of: query, options: searchOptions) != nil
    }

    /// Searches file contents. Checks `isCancelled` between files; returns partial results then.
    public static func searchContent(_ items: [LibraryDocument], query: String,
                                     isCancelled: () -> Bool = { false }) -> [LibraryMatch] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        var matches: [LibraryMatch] = []
        for item in items {
            if isCancelled() { break }
            guard let data = try? Data(contentsOf: item.url, options: .mappedIfSafe),
                  let text = try? TextFileCodec.decode(data).text,
                  let range = text.range(of: trimmed, options: searchOptions) else { continue }
            let line = text.lineRange(for: range)
            let excerpt = text[line].trimmingCharacters(in: .whitespacesAndNewlines)
            let shortened = excerpt.count > 160 ? String(excerpt.prefix(160)) + "…" : excerpt
            matches.append(LibraryMatch(item: item, line: shortened))
        }
        return matches
    }

    // MARK: Files

    /// `name` in `folder`, or `name 2`, `name 3`… when taken.
    public static func uniqueURL(for fileName: String, in folder: URL) -> URL {
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var candidate = folder.appendingPathComponent(fileName)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)"
            candidate = folder.appendingPathComponent(name)
            number += 1
        }
        return candidate
    }

    /// Copies files into the library under unique names; returns the new URLs.
    public static func importFiles(_ urls: [URL], into folder: URL) throws -> [URL] {
        try urls.map { source in
            let target = uniqueURL(for: source.lastPathComponent, in: folder)
            try FileManager.default.copyItem(at: source, to: target)
            return target
        }
    }
}
