import Foundation

/// The wire formats of the three providers: one `URLRequest` per prompt, one parser per reply.
/// Pure functions so they can be tested without a network.
public enum AIRequestBuilder {

    public static let anthropicURL = URL(string: "https://api.anthropic.com/v1/messages")!
    public static let openAIURL = URL(string: "https://api.openai.com/v1/responses")!
    public static func googleURL(modelID: String) -> URL {
        URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelID):generateContent")!
    }

    /// Room for the answer plus the model's reasoning tokens, which every provider counts here.
    public static let maxOutputTokens = 4096
    public static let timeout: TimeInterval = 45

    public static func urlRequest(prompt: AIPrompt, model: AIModel, apiKey: String) throws -> URLRequest {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw AIError.missingKey(model.provider) }
        var request: URLRequest
        let body: [String: Any]
        switch model.provider {
        case .anthropic:
            request = URLRequest(url: anthropicURL)
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            var b: [String: Any] = [
                "model": model.modelID,
                "max_tokens": maxOutputTokens,
                "system": prompt.system,
                "messages": [["role": "user", "content": prompt.user]],
            ]
            // Keyboard work is quick work: low effort keeps adaptive thinking short.
            if model.supportsEffort { b["output_config"] = ["effort": "low"] }
            body = b
        case .openai:
            request = URLRequest(url: openAIURL)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            var b: [String: Any] = [
                "model": model.modelID,
                "instructions": prompt.system,
                "input": prompt.user,
                "max_output_tokens": maxOutputTokens,
                "store": false,
            ]
            if model.supportsEffort { b["reasoning"] = ["effort": "low"] }
            body = b
        case .google:
            request = URLRequest(url: googleURL(modelID: model.modelID))
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            var generation: [String: Any] = ["maxOutputTokens": maxOutputTokens]
            if model.supportsEffort { generation["thinkingConfig"] = ["thinkingLevel": "low"] }
            body = [
                "system_instruction": ["parts": [["text": prompt.system]]],
                "contents": [["role": "user", "parts": [["text": prompt.user]]]],
                "generationConfig": generation,
            ]
        }
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    /// The reply's text, joined from every text block. Throws for refusals and unreadable bodies.
    public static func text(from data: Data, provider: AIProvider) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AIError.invalidResponse }
        var parts: [String] = []
        switch provider {
        case .anthropic:
            if json["stop_reason"] as? String == "refusal" { throw AIError.refused }
            for block in json["content"] as? [[String: Any]] ?? [] where block["type"] as? String == "text" {
                if let t = block["text"] as? String { parts.append(t) }
            }
        case .openai:
            for item in json["output"] as? [[String: Any]] ?? [] where item["type"] as? String == "message" {
                for block in item["content"] as? [[String: Any]] ?? [] {
                    let type = block["type"] as? String
                    if type == "refusal" { throw AIError.refused }
                    if type == "output_text", let t = block["text"] as? String { parts.append(t) }
                }
            }
        case .google:
            if let feedback = json["promptFeedback"] as? [String: Any], feedback["blockReason"] != nil { throw AIError.refused }
            let candidate = (json["candidates"] as? [[String: Any]])?.first
            if candidate?["finishReason"] as? String == "SAFETY" { throw AIError.refused }
            let content = candidate?["content"] as? [String: Any]
            for part in content?["parts"] as? [[String: Any]] ?? [] where part["thought"] as? Bool != true {
                if let t = part["text"] as? String { parts.append(t) }
            }
        }
        return parts.joined()
    }

    /// The provider's error message from a non-2xx body, if it has one.
    public static func errorMessage(from data: Data, provider: AIProvider) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let error = json["error"]
        if let e = error as? [String: Any] {
            if let m = e["message"] as? String { return m }
            if let m = e["status"] as? String { return m }
        }
        if let e = error as? String { return e }
        return json["message"] as? String
    }
}

/// Everything that can go wrong on the way to a result, with a German line for the panel.
public enum AIError: Error, Equatable, LocalizedError, Sendable {
    case disabled
    case missingKey(AIProvider)
    case noModel
    case emptySource
    case network(String)
    case http(Int, String?)
    case invalidResponse
    case emptyResponse
    case refused
    case cancelled
    case textChanged
    /// The extension runs without "Allow Full Access": no network, no shared keys.
    case needsFullAccess

    public var errorDescription: String? {
        switch self {
        case .disabled: return "KI-Funktionen sind ausgeschaltet."
        case .missingKey(let p): return "Kein API-Schlüssel für \(p.title) hinterlegt."
        case .noModel: return "Kein KI-Modell ausgewählt."
        case .emptySource: return "Erst etwas schreiben oder markieren."
        case .network(let m): return m.isEmpty ? "Keine Verbindung." : m
        case .http(let status, let message):
            switch status {
            case 401, 403: return "Der API-Schlüssel wurde abgelehnt."
            case 402: return "Kein Guthaben beim Anbieter."
            case 404: return "Das Modell wurde nicht gefunden."
            case 429: return "Zu viele Anfragen – kurz warten."
            case 500...599: return "Der Anbieter hat gerade ein Problem (\(status))."
            default: return message.map { "Fehler \(status): \($0)" } ?? "Fehler \(status)."
            }
        case .invalidResponse: return "Unerwartete Antwort des Anbieters."
        case .emptyResponse: return "Das Modell hat nichts zurückgegeben."
        case .refused: return "Das Modell hat diese Anfrage abgelehnt."
        case .cancelled: return "Abgebrochen."
        case .textChanged: return "Der Text hat sich inzwischen geändert."
        case .needsFullAccess: return "Die KI braucht „Vollen Zugriff“ (iOS-Einstellungen › Tastaturen › Umlaut)."
        }
    }

    /// True when the fix lives in the app's settings rather than in retrying.
    public var needsSetup: Bool {
        switch self {
        case .disabled, .missingKey, .noModel, .needsFullAccess: return true
        default: return false
        }
    }
}
