import Foundation

/// Sends one prompt to one model and returns the parsed text. Stateless apart from its session.
public final class AIClient: @unchecked Sendable {

    public static let shared = AIClient()

    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = AIRequestBuilder.timeout
            config.timeoutIntervalForResource = AIRequestBuilder.timeout * 2
            config.waitsForConnectivity = false
            self.session = URLSession(configuration: config)
        }
    }

    /// The raw text the model replied with.
    public func complete(_ prompt: AIPrompt, model: AIModel, apiKey: String) async throws -> String {
        let request = try AIRequestBuilder.urlRequest(prompt: prompt, model: model, apiKey: apiKey)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw AIError.cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw AIError.cancelled
        } catch {
            throw AIError.network(error.localizedDescription)
        }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw AIError.http(http.statusCode, AIRequestBuilder.errorMessage(from: data, provider: model.provider))
        }
        let text = try AIRequestBuilder.text(from: data, provider: model.provider)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIError.emptyResponse }
        return text
    }

    /// Runs a feature request and returns its results, one per alternative.
    public func run(_ spec: AIRequestSpec, model: AIModel, apiKey: String) async throws -> [String] {
        guard !spec.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIError.emptySource }
        let prompt = AIPrompts.prompt(for: spec)
        let raw = try await complete(prompt, model: model, apiKey: apiKey)
        let results = prompt.expectsList ? AIText.parseList(raw, max: prompt.maxItems) : [AIText.cleanSingle(raw)]
        let usable = results.filter { !$0.isEmpty }
        guard !usable.isEmpty else { throw AIError.emptyResponse }
        return usable
    }

    /// A one-word round trip to check a key; throws the same errors a real request would.
    public func verify(model: AIModel, apiKey: String) async throws {
        let prompt = AIPrompt(system: "Reply with the single word OK.", user: "ping", expectsList: false, maxItems: 1)
        _ = try await complete(prompt, model: model, apiKey: apiKey)
    }
}
