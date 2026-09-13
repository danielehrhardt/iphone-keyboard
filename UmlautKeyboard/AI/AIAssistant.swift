import Foundation
import os.log
import KeyboardCore

private let aiLog = Logger(subsystem: "de.codext.umlaut.keyboard", category: "ai")

/// Why the assistant cannot run right now, for the panel's empty state.
enum AIAvailability: Equatable {
    case ready(AIModel)
    case disabled
    case noKey(AIProvider)
    case noModel

    var error: AIError? {
        switch self {
        case .ready: return nil
        case .disabled: return .disabled
        case .noKey(let p): return .missingKey(p)
        case .noModel: return .noModel
        }
    }
}

/// The keyboard's side of the AI features: knows which model and key a feature uses, runs the
/// panel's requests (one at a time) and the two passive ones (sentence check, continuations).
/// Everything is called and called back on the main queue.
@MainActor
final class AIAssistant {

    let settings: KeyboardSettings
    let keys: AIKeyStore
    let client: AIClient

    private var panelTask: Task<Void, Never>?
    private var sentenceTask: Task<Void, Never>?
    private var continuationTask: Task<Void, Never>?
    /// Results of recent passive requests, so the same sentence or context isn't sent twice.
    private var sentenceCache: [String: String?] = [:]
    private var continuationCache: [String: [String]] = [:]

    /// Debounce before a passive continuation request; typing on cancels it.
    static let continuationDelay: TimeInterval = 0.8

    init(settings: KeyboardSettings, keys: AIKeyStore = .shared, client: AIClient = .shared) {
        self.settings = settings
        self.keys = keys
        self.client = client
    }

    var isEnabled: Bool { settings.aiEnabled }

    func availability(for feature: AIFeature) -> AIAvailability {
        guard settings.aiEnabled else { return .disabled }
        guard let model = settings.aiModel(for: feature) else { return .noModel }
        guard keys.hasKey(for: model.provider) else { return .noKey(model.provider) }
        return .ready(model)
    }

    /// The app may have changed keys or models while the keyboard was away.
    func reload() {
        keys.invalidateCache()
    }

    // MARK: Panel

    /// Runs a feature request for the panel. A request still running is cancelled first.
    func run(_ spec: AIRequestSpec, completion: @escaping (Result<[String], AIError>) -> Void) {
        panelTask?.cancel()
        let model: AIModel
        let key: String
        switch availability(for: spec.feature) {
        case .ready(let m):
            model = m
            key = keys.key(for: m.provider) ?? ""
        case let unavailable:
            completion(.failure(unavailable.error ?? .disabled))
            return
        }
        let client = self.client
        panelTask = Task { [weak self] in
            let result: Result<[String], AIError>
            do {
                let start = CFAbsoluteTimeGetCurrent()
                let items = try await client.run(spec, model: model, apiKey: key)
                aiLog.notice("\(spec.feature.rawValue, privacy: .public) via \(model.modelID, privacy: .public) in \(CFAbsoluteTimeGetCurrent() - start, format: .fixed(precision: 2))s")
                result = .success(items)
            } catch {
                result = .failure(Self.aiError(error))
            }
            guard !Task.isCancelled, self != nil else { return }
            completion(result)
        }
    }

    func cancel() {
        panelTask?.cancel()
        panelTask = nil
    }

    // MARK: Passive

    /// Proofreads a finished sentence; `completion` gets the corrected sentence when it differs
    /// from the original, nil otherwise or on any error (the strip just stays as it is).
    func checkSentence(_ sentence: String, language: KeyboardLanguage, completion: @escaping (String?) -> Void) {
        guard settings.aiAutocorrect, case .ready(let model) = availability(for: .proofread) else { return }
        if let cached = sentenceCache[sentence] { completion(cached); return }
        sentenceTask?.cancel()
        let key = keys.key(for: model.provider) ?? ""
        let spec = AIRequestSpec(feature: .proofread, text: sentence, language: language)
        let client = self.client
        sentenceTask = Task { [weak self] in
            let corrected = (try? await client.run(spec, model: model, apiKey: key))?.first
            guard !Task.isCancelled, let self else { return }
            let result = corrected.flatMap { AIText.differs($0, sentence) ? $0 : nil }
            self.remember(sentence: sentence, result: result)
            completion(result)
        }
    }

    /// After a pause at a word boundary: short continuations of `text` for the strip.
    func continuations(after text: String, language: KeyboardLanguage, completion: @escaping ([String]) -> Void) {
        continuationTask?.cancel()
        guard settings.aiSuggestions, case .ready(let model) = availability(for: .continueWriting) else { return }
        let source = AIText.source(before: text)
        guard source.count >= 3 else { return }
        if let cached = continuationCache[source] { completion(cached); return }
        let key = keys.key(for: model.provider) ?? ""
        let spec = AIRequestSpec(feature: .continueWriting, text: source, language: language)
        let client = self.client
        continuationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.continuationDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            let items = (try? await client.run(spec, model: model, apiKey: key)) ?? []
            guard !Task.isCancelled, let self else { return }
            self.continuationCache[source] = items
            if self.continuationCache.count > 32 { self.continuationCache.removeAll() }
            completion(items)
        }
    }

    /// Typing resumed: a pending continuation request is moot.
    func cancelContinuations() {
        continuationTask?.cancel()
        continuationTask = nil
    }

    private func remember(sentence: String, result: String?) {
        sentenceCache[sentence] = .some(result)
        if sentenceCache.count > 64 { sentenceCache.removeAll() }
    }

    private static func aiError(_ error: Error) -> AIError {
        if let e = error as? AIError { return e }
        if error is CancellationError { return .cancelled }
        return .network(error.localizedDescription)
    }
}
