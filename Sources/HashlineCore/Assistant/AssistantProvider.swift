import Foundation

/// The wire protocol a provider speaks (ADR 0019: two protocols for three providers).
public enum AssistantProtocol: Sendable {
    case anthropicMessages
    case openAIResponses
}

/// A provider of the document assistant. The user enters a key for each one they want to use.
public enum AssistantProvider: String, CaseIterable, Sendable, Codable {
    case claude
    case openAI = "openai"
    case deepSeek = "deepseek"

    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .openAI: "OpenAI"
        case .deepSeek: "DeepSeek"
        }
    }

    public var wireProtocol: AssistantProtocol {
        switch self {
        case .claude, .deepSeek: .anthropicMessages
        case .openAI: .openAIResponses
        }
    }

    /// Base URL; the protocol appends `/v1/messages`, `/v1/responses` or `/v1/models`.
    public var baseURL: URL {
        switch self {
        case .claude: .web("https://api.anthropic.com")
        case .openAI: .web("https://api.openai.com")
        // DeepSeek's Anthropic-compatible endpoint (research 2026-09-26).
        case .deepSeek: .web("https://api.deepseek.com/anthropic")
        }
    }

    /// The provider's price list; prices change too often to keep in the app.
    public var pricingURL: URL {
        switch self {
        case .claude: .web("https://www.anthropic.com/pricing#api")
        case .openAI: .web("https://openai.com/api/pricing/")
        case .deepSeek: .web("https://api-docs.deepseek.com/quick_start/pricing")
        }
    }

    /// Where keys are created.
    public var keysURL: URL {
        switch self {
        case .claude: .web("https://platform.claude.com/settings/keys")
        case .openAI: .web("https://platform.openai.com/api-keys")
        case .deepSeek: .web("https://platform.deepseek.com/api_keys")
        }
    }

    public var models: [AssistantModel] {
        switch self {
        case .claude:
            [AssistantModel(provider: self, id: "claude-opus-5", name: "Claude Opus 5", webSearch: .anthropicDynamic),
             AssistantModel(provider: self, id: "claude-sonnet-5", name: "Claude Sonnet 5",
                            webSearch: .anthropicDynamic),
             AssistantModel(provider: self, id: "claude-haiku-4-5", name: "Claude Haiku 4.5",
                            webSearch: .anthropicBasic)]
        case .openAI:
            [AssistantModel(provider: self, id: "gpt-6-sol", name: "GPT-6 Sol", webSearch: .openAI),
             AssistantModel(provider: self, id: "gpt-6-astra", name: "GPT-6 Astra", webSearch: .openAI),
             AssistantModel(provider: self, id: "gpt-6-luna", name: "GPT-6 Luna", webSearch: .openAI)]
        case .deepSeek:
            // Web search is hidden until a real call shows DeepSeek runs it (research, A5).
            [AssistantModel(provider: self, id: "deepseek-v4-pro", name: "DeepSeek V4 Pro", webSearch: nil),
             AssistantModel(provider: self, id: "deepseek-flash", name: "DeepSeek Flash", webSearch: nil)]
        }
    }

    /// Request headers with the key (never logged).
    public func headers(apiKey: String) -> [String: String] {
        var headers = ["content-type": "application/json"]
        switch wireProtocol {
        case .anthropicMessages:
            headers["x-api-key"] = apiKey
            headers["anthropic-version"] = "2023-06-01"
        case .openAIResponses:
            headers["authorization"] = "Bearer \(apiKey)"
        }
        return headers
    }

    /// The key check: every provider lists its models for a valid key.
    public func modelsRequest(apiKey: String) -> URLRequest {
        var request = URLRequest(url: modelsURL)
        for (field, value) in headers(apiKey: apiKey) where field != "content-type" {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.timeoutInterval = 20
        return request
    }

    private var modelsURL: URL {
        switch self {
        case .claude, .openAI: baseURL.appending(path: "v1/models")
        // The Anthropic-compatible path has no model list; the provider's own one takes the same key.
        case .deepSeek: .web("https://api.deepseek.com/models")
        }
    }
}

/// A model offered in the chat's model menu.
public struct AssistantModel: Sendable, Hashable, Identifiable {
    public enum WebSearch: Sendable, Hashable {
        /// `web_search_20260209` (dynamic filtering; Opus 5, Sonnet 5).
        case anthropicDynamic
        /// `web_search_20250305` (older models such as Haiku 4.5).
        case anthropicBasic
        /// `{"type": "web_search"}` in the Responses API.
        case openAI
    }

    public let provider: AssistantProvider
    public let id: String
    public let name: String
    public let webSearch: WebSearch?

    /// `provider/model`, the value stored for the last chosen model.
    public var key: String { "\(provider.rawValue)/\(id)" }

    public static func model(forKey key: String) -> AssistantModel? {
        let parts = key.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, let provider = AssistantProvider(rawValue: parts[0]) else { return nil }
        return provider.models.first { $0.id == parts[1] }
    }
}

extension URL {
    /// A URL from a literal known to be valid (no force unwrap outside tests).
    static func web(_ literal: StaticString) -> URL {
        URL(string: "\(literal)") ?? URL(fileURLWithPath: "/")
    }
}
