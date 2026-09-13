import Foundation

/// A hosted model provider the keyboard can talk to with the user's own API key.
public enum AIProvider: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case anthropic
    case openai
    case google

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .anthropic: return "Anthropic"
        case .openai: return "OpenAI"
        case .google: return "Google"
        }
    }

    /// The model family, for subtitles ("Claude", "GPT", "Gemini").
    public var family: String {
        switch self {
        case .anthropic: return "Claude"
        case .openai: return "GPT"
        case .google: return "Gemini"
        }
    }

    /// How a key from this provider usually starts; shown as the placeholder of the key field.
    public var keyHint: String {
        switch self {
        case .anthropic: return "sk-ant-…"
        case .openai: return "sk-…"
        case .google: return "AIza…"
        }
    }

    /// Where the user creates a key.
    public var keyConsoleURL: URL {
        switch self {
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")!
        case .openai: return URL(string: "https://platform.openai.com/api-keys")!
        case .google: return URL(string: "https://aistudio.google.com/apikey")!
        }
    }

    /// Whether `key` looks like a key of this provider (a plausibility check, not validation).
    public func looksLikeKey(_ key: String) -> Bool {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard k.count >= 20, !k.contains(" ") else { return false }
        switch self {
        case .anthropic: return k.hasPrefix("sk-ant-")
        case .openai: return k.hasPrefix("sk-")
        case .google: return k.hasPrefix("AIza")
        }
    }

    /// The models offered in the picker, best first.
    public var models: [AIModel] {
        switch self {
        case .anthropic:
            return [
                AIModel(provider: self, modelID: "claude-opus-5", title: "Claude Opus 5", tier: .flagship),
                AIModel(provider: self, modelID: "claude-fable-5-1", title: "Claude Fable 5.1", tier: .flagship),
                AIModel(provider: self, modelID: "claude-sonnet-5", title: "Claude Sonnet 5", tier: .balanced),
                AIModel(provider: self, modelID: "claude-haiku-4-5", title: "Claude Haiku 4.5", tier: .fast, supportsEffort: false),
            ]
        case .openai:
            return [
                AIModel(provider: self, modelID: "gpt-6-astra", title: "GPT-6 Astra", tier: .flagship),
                AIModel(provider: self, modelID: "gpt-5.6-sol", title: "GPT-5.6 Sol", tier: .flagship),
                AIModel(provider: self, modelID: "gpt-5.6-terra", title: "GPT-5.6 Terra", tier: .balanced),
                AIModel(provider: self, modelID: "gpt-5.6-luna", title: "GPT-5.6 Luna", tier: .fast),
            ]
        case .google:
            return [
                AIModel(provider: self, modelID: "gemini-3.1-pro-preview", title: "Gemini 3.1 Pro", tier: .flagship),
                AIModel(provider: self, modelID: "gemini-3.8-flash", title: "Gemini 3.8 Flash", tier: .balanced),
                AIModel(provider: self, modelID: "gemini-3.5-flash-lite", title: "Gemini 3.5 Flash-Lite", tier: .fast),
            ]
        }
    }

    /// The model picked when the user adds a key of this provider without choosing one.
    public var defaultModel: AIModel {
        switch self {
        case .anthropic: return models[0]          // claude-opus-5
        case .openai: return models[1]             // gpt-5.6-sol
        case .google: return models[1]             // gemini-3.8-flash
        }
    }

    /// The quickest model of this provider, for the passive strip features (sentence check,
    /// continuations) where latency matters more than depth.
    public var fastModel: AIModel { models.last(where: { $0.tier == .fast }) ?? defaultModel }

    /// A listed model, or a custom entry for an ID the picker doesn't know.
    public func model(withID modelID: String) -> AIModel {
        models.first { $0.modelID == modelID } ?? AIModel(custom: modelID, provider: self)
    }
}

/// One model of a provider. `id` is "provider:modelID" so a selection round-trips through the
/// shared defaults as a single string.
public struct AIModel: Hashable, Codable, Sendable, Identifiable {
    public enum Tier: String, Codable, Sendable, CaseIterable {
        case flagship, balanced, fast
        public var title: String {
            switch self {
            case .flagship: return "Top"
            case .balanced: return "Ausgewogen"
            case .fast: return "Schnell"
            }
        }
    }

    public let provider: AIProvider
    public let modelID: String
    public let title: String
    public let tier: Tier
    /// Whether the request may carry a low-effort/low-thinking hint (older models reject it).
    public let supportsEffort: Bool
    public let isCustom: Bool

    public var id: String { "\(provider.rawValue):\(modelID)" }

    public init(provider: AIProvider, modelID: String, title: String, tier: Tier, supportsEffort: Bool = true, isCustom: Bool = false) {
        self.provider = provider
        self.modelID = modelID
        self.title = title
        self.tier = tier
        self.supportsEffort = supportsEffort
        self.isCustom = isCustom
    }

    /// A model ID typed by the user. Effort hints are sent unless the ID names a model known
    /// not to take them.
    public init(custom modelID: String, provider: AIProvider) {
        let id = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let effort: Bool
        switch provider {
        case .anthropic: effort = !(id.contains("haiku") || id.contains("-4-5") || id.contains("-3-"))
        case .openai, .google: effort = true
        }
        self.init(provider: provider, modelID: id, title: id, tier: .balanced, supportsEffort: effort, isCustom: true)
    }

    /// Parses "provider:modelID"; nil for anything else.
    public init?(id: String) {
        guard let colon = id.firstIndex(of: ":") else { return nil }
        guard let provider = AIProvider(rawValue: String(id[..<colon])) else { return nil }
        let modelID = String(id[id.index(after: colon)...])
        guard !modelID.isEmpty else { return nil }
        self = provider.model(withID: modelID)
    }
}
