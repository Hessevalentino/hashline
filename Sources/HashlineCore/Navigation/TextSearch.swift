import Foundation

/// Find and replace in one document or in files: literal text or a regular expression.
public struct SearchQuery: Sendable, Equatable {
    public var text: String
    public var isRegex = false
    public var caseSensitive = false
    public var wholeWords = false

    public init(text: String, isRegex: Bool = false, caseSensitive: Bool = false, wholeWords: Bool = false) {
        self.text = text
        self.isRegex = isRegex
        self.caseSensitive = caseSensitive
        self.wholeWords = wholeWords
    }

    public enum Failure: Error, Equatable {
        case invalidPattern(String)
    }

    /// The query as a regular expression; literal text is escaped. Anchors match at line starts and ends.
    public func expression() throws -> NSRegularExpression? {
        guard !text.isEmpty else { return nil }
        var pattern = isRegex ? text : NSRegularExpression.escapedPattern(for: text)
        if wholeWords { pattern = "\\b(?:" + pattern + ")\\b" }
        var options: NSRegularExpression.Options = [.anchorsMatchLines]
        if !caseSensitive { options.insert(.caseInsensitive) }
        do {
            return try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            throw Failure.invalidPattern(text)
        }
    }
}

public enum TextSearch {
    /// Ranges of all matches (empty matches skipped), at most `limit`.
    public static func matches(of query: SearchQuery, in text: NSString, limit: Int = .max) throws -> [NSRange] {
        guard let expression = try query.expression() else { return [] }
        var result: [NSRange] = []
        let whole = NSRange(location: 0, length: text.length)
        expression.enumerateMatches(in: text as String, range: whole) { match, _, stop in
            guard let match, match.range.length > 0 else { return }
            result.append(match.range)
            if result.count >= limit { stop.pointee = true }
        }
        return result
    }

    /// The match after (or before) `location`, wrapping around.
    public static func next(in matches: [NSRange], after location: Int, backwards: Bool = false) -> NSRange? {
        guard !matches.isEmpty else { return nil }
        if backwards {
            return matches.last { $0.location < location } ?? matches.last
        }
        return matches.first { $0.location >= location } ?? matches.first
    }

    /// The replacement for one match: regex templates (`$1`) for regex queries, literal otherwise.
    public static func replacement(for range: NSRange, in text: NSString, query: SearchQuery,
                                   template: String) throws -> String {
        guard query.isRegex, let expression = try query.expression(),
              let match = expression.firstMatch(in: text as String, options: [.anchored], range: range),
              match.range == range else { return template }
        return expression.replacementString(for: match, in: text as String, offset: 0, template: template)
    }

    /// Replaces every match as one edit covering the first to the last match (one undo step,
    /// one text-storage change). Returns nil when nothing matches.
    public static func replaceAll(_ query: SearchQuery, with template: String,
                                  in text: NSString) throws -> (edit: TextEdit, count: Int)? {
        guard let expression = try query.expression() else { return nil }
        let whole = NSRange(location: 0, length: text.length)
        let found = expression.matches(in: text as String, range: whole).filter { $0.range.length > 0 }
        guard let first = found.first, let last = found.last else { return nil }
        let span = NSRange(location: first.range.location, length: NSMaxRange(last.range) - first.range.location)
        let result = NSMutableString()
        var cursor = span.location
        for match in found {
            result.append(text.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            result.append(query.isRegex
                ? expression.replacementString(for: match, in: text as String, offset: 0, template: template)
                : template)
            cursor = NSMaxRange(match.range)
        }
        let edit = TextEdit(range: span, replacement: result as String,
                            selection: NSRange(location: span.location + result.length, length: 0))
        return (edit, found.count)
    }
}

/// All matches in one file of a folder search.
public struct FileSearchResult: Sendable, Identifiable {
    public struct Line: Sendable, Hashable, Identifiable {
        /// 1-based line number.
        public let number: Int
        public let text: String
        /// Match range in the document (UTF-16), for selecting it after opening.
        public let range: NSRange
        /// Match range inside `text`.
        public let highlight: NSRange

        public var id: Int { range.location }
    }

    public let document: LibraryDocument
    public let lines: [Line]
    public var id: URL { document.url }
}

extension LibraryIndex {
    /// Every match in every document, per line (capped per file). Checks `isCancelled` between files.
    public static func searchFiles(_ items: [LibraryDocument], query: SearchQuery, maxLinesPerFile: Int = 50,
                                   isCancelled: () -> Bool = { false }) throws -> [FileSearchResult] {
        if !query.isRegex, !query.caseSensitive {
            // Literal search ignores diacritics like the library search: fold both sides.
            return searchFolded(items, text: query.text, wholeWords: query.wholeWords,
                                maxLinesPerFile: maxLinesPerFile, isCancelled: isCancelled)
        }
        guard let expression = try query.expression() else { return [] }
        var results: [FileSearchResult] = []
        for item in items {
            if isCancelled() { break }
            guard let text = read(item.url) else { continue }
            var ranges: [NSRange] = []
            let whole = NSRange(location: 0, length: text.length)
            expression.enumerateMatches(in: text as String, range: whole) { match, _, stop in
                guard let match, match.range.length > 0 else { return }
                ranges.append(match.range)
                if ranges.count >= maxLinesPerFile { stop.pointee = true }
            }
            if !ranges.isEmpty { results.append(FileSearchResult(document: item, lines: lines(for: ranges, in: text))) }
        }
        return results
    }

    private static func searchFolded(_ items: [LibraryDocument], text query: String, wholeWords: Bool,
                                     maxLinesPerFile: Int, isCancelled: () -> Bool) -> [FileSearchResult] {
        guard !query.isEmpty else { return [] }
        var results: [FileSearchResult] = []
        for item in items {
            if isCancelled() { break }
            guard let text = read(item.url) else { continue }
            var ranges: [NSRange] = []
            var searchRange = NSRange(location: 0, length: text.length)
            while ranges.count < maxLinesPerFile {
                let found = text.range(of: query, options: searchOptions, range: searchRange)
                guard found.location != NSNotFound else { break }
                if !wholeWords || isWordBoundary(found, in: text) { ranges.append(found) }
                let next = NSMaxRange(found)
                searchRange = NSRange(location: next, length: text.length - next)
            }
            if !ranges.isEmpty { results.append(FileSearchResult(document: item, lines: lines(for: ranges, in: text))) }
        }
        return results
    }

    private static func isWordBoundary(_ range: NSRange, in text: NSString) -> Bool {
        func isWord(_ offset: Int) -> Bool {
            guard offset >= 0, offset < text.length, let scalar = UnicodeScalar(text.character(at: offset)) else {
                return false
            }
            return CharacterSet.alphanumerics.contains(scalar)
        }
        return !isWord(range.location - 1) && !isWord(NSMaxRange(range))
    }

    private static func read(_ url: URL) -> NSString? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let text = try? TextFileCodec.decode(data).text else { return nil }
        return text as NSString
    }

    /// One result line per match with its 1-based line number; long lines are cut around the match.
    private static func lines(for ranges: [NSRange], in text: NSString) -> [FileSearchResult.Line] {
        var lineNumber = 1
        var counted = 0
        return ranges.map { range in
            // Count line breaks incrementally: ranges are in document order.
            var index = counted
            while index < range.location {
                let character = text.character(at: index)
                let isCRLF = character == 0x0D && index + 1 < text.length && text.character(at: index + 1) == 0x0A
                if character == 0x0A || (character == 0x0D && !isCRLF) {
                    lineNumber += 1
                }
                index += 1
            }
            counted = range.location
            var start = 0, contentsEnd = 0
            text.getLineStart(&start, end: nil, contentsEnd: &contentsEnd, for: range)
            let lineRange = NSRange(location: start, length: max(contentsEnd - start, NSMaxRange(range) - start))
            var excerpt = NSRange(location: lineRange.location, length: min(lineRange.length, 200))
            if NSMaxRange(range) > NSMaxRange(excerpt) {
                let begin = max(lineRange.location, range.location - 60)
                excerpt = NSRange(location: begin, length: min(NSMaxRange(lineRange) - begin, 200))
            }
            let highlight = NSIntersectionRange(range, excerpt)
            return FileSearchResult.Line(number: lineNumber, text: text.substring(with: excerpt), range: range,
                                         highlight: NSRange(location: highlight.location - excerpt.location,
                                                            length: highlight.length))
        }
    }
}
