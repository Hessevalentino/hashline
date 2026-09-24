import Foundation

/// GitHub-style `:shortcode:` emoji (gemoji aliases). Loaded on first use.
public enum Emoji {
    public static let table: [String: String] = {
        guard let url = Bundle.module.url(forResource: "emoji", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let table = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return table
    }()

    private static let sortedNames: [String] = table.keys.sorted()

    public static func emoji(for shortcode: String) -> String? {
        table[shortcode]
    }

    /// Shortcodes starting with `prefix` first, then containing it; at most `limit`.
    public static func completions(for prefix: String, limit: Int = 20) -> [(name: String, emoji: String)] {
        let query = prefix.lowercased()
        guard !query.isEmpty else { return [] }
        let starting = sortedNames.filter { $0.hasPrefix(query) }
        let containing = sortedNames.filter { !$0.hasPrefix(query) && $0.contains(query) }
        return (starting + containing).prefix(limit).compactMap { name in table[name].map { (name, $0) } }
    }
}
