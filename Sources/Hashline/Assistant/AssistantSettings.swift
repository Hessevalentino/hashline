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
    /// A connected local server's address (`assistantServer.ollama`); its presence means connected.
    static func serverKey(_ provider: AssistantProvider) -> String { "assistantServer.\(provider.rawValue)" }
    /// The model ids the local server listed last, so the chat's menu needs no request at launch.
    static func localModelsKey(_ provider: AssistantProvider) -> String {
        "assistantLocalModels.\(provider.rawValue)"
    }

    /// A server address as typed: `localhost:11434` gets `http://`. Plain http only where App Transport
    /// Security allows it without an exception (localhost, IP addresses, `.local` names); other hosts need https.
    static func serverURL(from text: String) -> URL? {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        if !text.contains("://") { text = "http://" + text }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              let host = url.host()?.lowercased(), !host.isEmpty else { return nil }
        switch scheme {
        case "https": return url
        case "http":
            let isLocal = host == "localhost" || host.hasSuffix(".local") || !host.contains(".")
                || host.contains(":") || host.allSatisfy { $0.isNumber || $0 == "." }
            return isLocal ? url : nil
        default: return nil
        }
    }

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
}

/// Which providers have a key (or a connected local server). Cached so views do not query the
/// Keychain on every redraw.
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
        let providers = AssistantProvider.allCases
        configured = Set(providers.filter { !$0.isLocal && APIKeyStore.hasKey(for: $0) })
        for provider in providers where provider.isLocal {
            guard let server = Self.savedServer(provider) else { continue }
            configured.insert(provider)
            servers[provider] = server
            let ids = UserDefaults.standard.stringArray(forKey: AssistantSettings.localModelsKey(provider)) ?? []
            localModels[provider] = ids.map(provider.localModel(id:))
        }
    }

    /// Addresses of the connected local servers.
    private(set) var servers: [AssistantProvider: URL] = [:]
    /// Models of the connected local servers, as they listed them last.
    private(set) var localModels: [AssistantProvider: [AssistantModel]] = [:]

    private static func savedServer(_ provider: AssistantProvider) -> URL? {
        UserDefaults.standard.string(forKey: AssistantSettings.serverKey(provider))
            .flatMap(AssistantSettings.serverURL(from:))
    }

    /// Keys read in this run. Reading a key from the Keychain may ask for the login password (an ad-hoc
    /// signed build is a new app to the Keychain after every build or update), so it is read at most
    /// once per launch, when the first message needs it, and then kept in memory.
    @ObservationIgnored private var cachedKeys: [AssistantProvider: String] = [:]

    func key(for provider: AssistantProvider) -> String? {
        #if DEBUG || HASHLINE_TEST_HOOKS
        if AssistantFake.isEnabled { return "fake" }
        #endif
        // A local server takes no key; the Keychain is never asked.
        if provider.isLocal { return configured.contains(provider) ? "" : nil }
        if let key = cachedKeys[provider] { return key }
        // A cancelled password prompt is not remembered: the next message asks again.
        guard let key = APIKeyStore.key(for: provider) else { return nil }
        cachedKeys[provider] = key
        return key
    }

    /// Models of the providers with a key or a connected server, in menu order.
    var models: [AssistantModel] {
        AssistantProvider.allCases.filter(configured.contains).flatMap { provider in
            provider.isLocal ? localModels[provider] ?? [] : provider.models
        }
    }

    /// Connects a local server: it must answer with its models; then it is remembered.
    func connect(_ provider: AssistantProvider, server: URL) async -> Result<[AssistantModel], AssistantError> {
        let result = await AssistantClient.localModels(provider, server: server)
        if case .success(let models) = result {
            UserDefaults.standard.set(server.absoluteString, forKey: AssistantSettings.serverKey(provider))
            servers[provider] = server
            configured.insert(provider)
            store(models, for: provider)
            NotificationCenter.default.post(name: .assistantAvailabilityChanged, object: nil)
        }
        return result
    }

    func disconnect(_ provider: AssistantProvider) {
        UserDefaults.standard.removeObject(forKey: AssistantSettings.serverKey(provider))
        UserDefaults.standard.removeObject(forKey: AssistantSettings.localModelsKey(provider))
        servers[provider] = nil
        localModels[provider] = nil
        configured.remove(provider)
        NotificationCenter.default.post(name: .assistantAvailabilityChanged, object: nil)
    }

    /// Asks the connected local servers again (the user may have downloaded or removed models).
    /// An unreachable server keeps its last list; sending then reports the error.
    func refreshLocalModels() async {
        for (provider, server) in servers {
            let result = await AssistantClient.localModels(provider, server: server)
            // Disconnected or moved to another address while the request ran: keep the newer state.
            guard case .success(let models) = result, servers[provider] == server else { continue }
            store(models, for: provider)
        }
    }

    private func store(_ models: [AssistantModel], for provider: AssistantProvider) {
        guard localModels[provider] != models else { return }
        localModels[provider] = models
        UserDefaults.standard.set(models.map(\.id), forKey: AssistantSettings.localModelsKey(provider))
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

    /// Switched on in Settings and at least one key entered or server connected: only then the toolbar
    /// and the View menu offer the assistant. The Keychain is not touched while the assistant is off.
    static var isAvailable: Bool {
        AssistantSettings.isEnabled && !shared.configured.isEmpty
    }
}

extension Notification.Name {
    /// A key was saved or removed.
    static let assistantAvailabilityChanged = Notification.Name("HashlineAssistantAvailabilityChanged")
}
