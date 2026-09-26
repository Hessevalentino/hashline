/// Rough size of what a message sends. Prices change too often to keep in the app (ADR 0019); the
/// panel shows tokens and links to the provider's price list.
public enum AssistantCost {
    /// Above this the user confirms before a message sends the whole document.
    public static let confirmationThreshold = 100_000

    /// About three UTF-16 units per token: deliberately high for Czech and other accented text
    /// (English is closer to four), so the warning comes rather too early than too late.
    public static func estimatedTokens(_ text: String) -> Int {
        text.utf16.count / 3
    }
}
