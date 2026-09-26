import Foundation
import HashlineCore
import Observation

enum AssistantSettings {
    /// Off by default; switched on in Settings ▸ General ▸ Advanced (ADR 0019).
    static let enabledKey = "assistantEnabled"
    static let showsPanelKey = "showsAssistant"
    /// The last model chosen in a chat (`provider/model`), used for new chats.
    static let modelKey = "assistantModel"
    /// The panel's width in points, set by dragging its divider.
    static let panelWidthKey = "assistantSplitWidth"
    static let panelWidths: ClosedRange<CGFloat> = 260...560
    static let defaultPanelWidth: CGFloat = 340
    /// Visible lines of the chat's message field, set by dragging the handle above it.
    static let inputLinesKey = "assistantInputLines"
    static let defaultInputLines = 5
    static let inputLines: ClosedRange<Int> = 2...24

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
}

/// Which providers have a key. Cached so views do not query the Keychain on every redraw.
@MainActor
@Observable
final class AssistantKeys {
    static let shared = AssistantKeys()

    private(set) var configured: Set<AssistantProvider>

    private init() {
        #if DEBUG || HASHLINE_TEST_HOOKS
        if AssistantFake.isEnabled {
            configured = [.claude]
            return
        }
        #endif
        configured = Set(AssistantProvider.allCases.filter(APIKeyStore.hasKey(for:)))
    }

    /// Keys read in this run. Reading a key from the Keychain may ask for the login password (an ad-hoc
    /// signed build is a new app to the Keychain after every build or update), so it is read at most
    /// once per launch, when the first message needs it, and then kept in memory.
    @ObservationIgnored private var cachedKeys: [AssistantProvider: String] = [:]

    func key(for provider: AssistantProvider) -> String? {
        #if DEBUG || HASHLINE_TEST_HOOKS
        if AssistantFake.isEnabled { return "fake" }
        #endif
        if let key = cachedKeys[provider] { return key }
        // A cancelled password prompt is not remembered: the next message asks again.
        guard let key = APIKeyStore.key(for: provider) else { return nil }
        cachedKeys[provider] = key
        return key
    }

    /// Models of the providers with a key, in menu order.
    var models: [AssistantModel] {
        AssistantProvider.allCases.filter(configured.contains).flatMap(\.models)
    }

    func save(_ key: String, for provider: AssistantProvider) -> Bool {
        let saved = APIKeyStore.setKey(key, for: provider)
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        cachedKeys[provider] = saved && !trimmed.isEmpty ? trimmed : nil
        refresh(provider)
        return saved
    }

    func remove(_ provider: AssistantProvider) {
        APIKeyStore.setKey("", for: provider)
        cachedKeys[provider] = nil
        refresh(provider)
    }

    private func refresh(_ provider: AssistantProvider) {
        if APIKeyStore.hasKey(for: provider) { configured.insert(provider) } else { configured.remove(provider) }
        NotificationCenter.default.post(name: .assistantAvailabilityChanged, object: nil)
    }

    /// Switched on in Settings and at least one key entered: only then the toolbar and the View menu
    /// offer the assistant. The Keychain is not touched while the assistant is off.
    static var isAvailable: Bool {
        AssistantSettings.isEnabled && !shared.configured.isEmpty
    }
}

extension Notification.Name {
    /// A key was saved or removed.
    static let assistantAvailabilityChanged = Notification.Name("HashlineAssistantAvailabilityChanged")
}
