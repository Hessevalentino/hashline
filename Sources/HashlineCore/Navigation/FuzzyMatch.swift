import Foundation

/// Quick Open (⌘P) matching: the query's characters in order, ignoring case and diacritics.
/// Consecutive characters and matches at word starts score higher; shorter names win ties.
public enum FuzzyMatch {
    public static func score(_ query: String, in candidate: String) -> Int? {
        let needle = Array(fold(query).filter { !$0.isWhitespace })
        guard !needle.isEmpty else { return 0 }
        let haystack = Array(fold(candidate))
        var score = 0, index = 0, previous = -2
        for (position, character) in haystack.enumerated() where index < needle.count {
            guard character == needle[index] else { continue }
            score += 1
            if position == previous + 1 { score += 5 }
            if position == 0 || !haystack[position - 1].isLetter && !haystack[position - 1].isNumber { score += 8 }
            previous = position
            index += 1
        }
        guard index == needle.count else { return nil }
        return score * 100 - haystack.count
    }

    /// Candidates that match, best first.
    public static func rank<T>(_ items: [T], query: String, key: (T) -> String) -> [T] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return items }
        return items.compactMap { item in score(query, in: key(item)).map { (item, $0) } }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
