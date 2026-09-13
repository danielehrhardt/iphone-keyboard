import XCTest
@testable import KeyboardCore

final class AITests: XCTestCase {

    private func json(_ request: URLRequest) -> [String: Any] {
        try! JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
    }

    // MARK: Models

    func testModelIDsRoundTripThroughSettings() {
        let settings = KeyboardSettings(defaults: UserDefaults(suiteName: "ai-tests-\(UUID())")!)
        XCTAssertNil(settings.aiDefaultModel)
        XCTAssertFalse(settings.aiEnabled)
        settings.aiDefaultModel = AIProvider.anthropic.model(withID: "claude-opus-5")
        XCTAssertEqual(settings.aiDefaultModel?.modelID, "claude-opus-5")
        XCTAssertEqual(settings.aiDefaultModel?.title, "Claude Opus 5")
        XCTAssertEqual(settings.aiModel(for: .rewrite)?.modelID, "claude-opus-5", "features follow the default")
        settings.setAIModelOverride(AIProvider.google.fastModel, for: .proofread)
        XCTAssertEqual(settings.aiModel(for: .proofread)?.provider, .google)
        XCTAssertEqual(settings.aiModel(for: .rewrite)?.provider, .anthropic)
        settings.setAIModelOverride(nil, for: .proofread)
        XCTAssertEqual(settings.aiModel(for: .proofread)?.provider, .anthropic)
    }

    func testCustomModelIDsAreKept() {
        let custom = AIModel(id: "openai:gpt-9-experimental")
        XCTAssertEqual(custom?.modelID, "gpt-9-experimental")
        XCTAssertEqual(custom?.isCustom, true)
        XCTAssertNil(AIModel(id: "nope:model"))
        XCTAssertNil(AIModel(id: "openai:"))
        XCTAssertFalse(AIModel(custom: "claude-haiku-4-5-20251001", provider: .anthropic).supportsEffort)
        XCTAssertTrue(AIModel(custom: "claude-opus-6", provider: .anthropic).supportsEffort)
    }

    func testEveryProviderHasADefaultAndAFastModel() {
        for provider in AIProvider.allCases {
            XCTAssertTrue(provider.models.contains(provider.defaultModel), provider.title)
            XCTAssertEqual(provider.fastModel.tier, .fast, provider.title)
            XCTAssertEqual(Set(provider.models.map(\.modelID)).count, provider.models.count, "unique IDs")
        }
    }

    // MARK: Requests

    func testAnthropicRequestShape() throws {
        let prompt = AIPrompts.prompt(for: AIRequestSpec(feature: .proofread, text: "Hallo wie gehts", language: .german))
        let r = try AIRequestBuilder.urlRequest(prompt: prompt, model: AIProvider.anthropic.defaultModel, apiKey: "sk-ant-test")
        XCTAssertEqual(r.url, AIRequestBuilder.anthropicURL)
        XCTAssertEqual(r.httpMethod, "POST")
        XCTAssertEqual(r.value(forHTTPHeaderField: "x-api-key"), "sk-ant-test")
        XCTAssertEqual(r.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        let body = json(r)
        XCTAssertEqual(body["model"] as? String, "claude-opus-5")
        XCTAssertEqual(body["system"] as? String, prompt.system)
        XCTAssertEqual((body["messages"] as? [[String: Any]])?.first?["content"] as? String, "Hallo wie gehts")
        XCTAssertEqual((body["output_config"] as? [String: Any])?["effort"] as? String, "low")
        XCTAssertNil(body["temperature"], "sampling parameters are rejected by current Claude models")
        XCTAssertNil(body["thinking"], "adaptive thinking is the default; an explicit config is not sent")
    }

    func testHaikuGetsNoEffortHint() throws {
        let prompt = AIPrompts.prompt(for: AIRequestSpec(feature: .proofread, text: "x y", language: .german))
        let haiku = AIProvider.anthropic.model(withID: "claude-haiku-4-5")
        let r = try AIRequestBuilder.urlRequest(prompt: prompt, model: haiku, apiKey: "k")
        XCTAssertNil(json(r)["output_config"])
    }

    func testOpenAIRequestShape() throws {
        let prompt = AIPrompts.prompt(for: AIRequestSpec(feature: .rewrite, text: "hi", language: .english, tone: .formal))
        let r = try AIRequestBuilder.urlRequest(prompt: prompt, model: AIProvider.openai.defaultModel, apiKey: "sk-x")
        XCTAssertEqual(r.url, AIRequestBuilder.openAIURL)
        XCTAssertEqual(r.value(forHTTPHeaderField: "Authorization"), "Bearer sk-x")
        let body = json(r)
        XCTAssertEqual(body["model"] as? String, "gpt-5.6-sol")
        XCTAssertEqual(body["instructions"] as? String, prompt.system)
        XCTAssertEqual(body["input"] as? String, "hi")
        XCTAssertEqual(body["store"] as? Bool, false)
        XCTAssertEqual((body["reasoning"] as? [String: Any])?["effort"] as? String, "low")
    }

    func testGoogleRequestShape() throws {
        let prompt = AIPrompts.prompt(for: AIRequestSpec(feature: .translate, text: "Guten Morgen", language: .german, target: .french))
        let r = try AIRequestBuilder.urlRequest(prompt: prompt, model: AIProvider.google.defaultModel, apiKey: "AIza1")
        XCTAssertEqual(r.url?.absoluteString, "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent")
        XCTAssertEqual(r.value(forHTTPHeaderField: "x-goog-api-key"), "AIza1")
        let body = json(r)
        let system = body["system_instruction"] as? [String: Any]
        XCTAssertEqual(((system?["parts"] as? [[String: Any]])?.first?["text"] as? String), prompt.system)
        let contents = body["contents"] as? [[String: Any]]
        XCTAssertEqual(contents?.first?["role"] as? String, "user")
        let generation = body["generationConfig"] as? [String: Any]
        XCTAssertEqual((generation?["thinkingConfig"] as? [String: Any])?["thinkingLevel"] as? String, "low")
        XCTAssertTrue(prompt.system.contains("French"))
    }

    func testMissingKeyIsRejectedBeforeTheNetwork() {
        let prompt = AIPrompts.prompt(for: AIRequestSpec(feature: .answer, text: "?", language: .german))
        XCTAssertThrowsError(try AIRequestBuilder.urlRequest(prompt: prompt, model: AIProvider.openai.defaultModel, apiKey: "  ")) {
            XCTAssertEqual($0 as? AIError, .missingKey(.openai))
        }
    }

    // MARK: Responses

    func testAnthropicResponseText() throws {
        let data = #"{"content":[{"type":"thinking","thinking":""},{"type":"text","text":"Hallo, "},{"type":"text","text":"wie geht's?"}],"stop_reason":"end_turn"}"#.data(using: .utf8)!
        XCTAssertEqual(try AIRequestBuilder.text(from: data, provider: .anthropic), "Hallo, wie geht's?")
        let refusal = #"{"content":[],"stop_reason":"refusal"}"#.data(using: .utf8)!
        XCTAssertThrowsError(try AIRequestBuilder.text(from: refusal, provider: .anthropic)) { XCTAssertEqual($0 as? AIError, .refused) }
    }

    func testOpenAIResponseText() throws {
        let data = #"{"output":[{"type":"reasoning","summary":[]},{"type":"message","content":[{"type":"output_text","text":"Hello"}]}]}"#.data(using: .utf8)!
        XCTAssertEqual(try AIRequestBuilder.text(from: data, provider: .openai), "Hello")
    }

    func testGoogleResponseTextSkipsThoughts() throws {
        let data = #"{"candidates":[{"content":{"parts":[{"text":"secret","thought":true},{"text":"Bonjour"}]},"finishReason":"STOP"}]}"#.data(using: .utf8)!
        XCTAssertEqual(try AIRequestBuilder.text(from: data, provider: .google), "Bonjour")
        let blocked = #"{"promptFeedback":{"blockReason":"SAFETY"}}"#.data(using: .utf8)!
        XCTAssertThrowsError(try AIRequestBuilder.text(from: blocked, provider: .google)) { XCTAssertEqual($0 as? AIError, .refused) }
    }

    func testErrorMessages() {
        let a = #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#.data(using: .utf8)!
        XCTAssertEqual(AIRequestBuilder.errorMessage(from: a, provider: .anthropic), "invalid x-api-key")
        let g = #"{"error":{"code":400,"message":"API key not valid","status":"INVALID_ARGUMENT"}}"#.data(using: .utf8)!
        XCTAssertEqual(AIRequestBuilder.errorMessage(from: g, provider: .google), "API key not valid")
        XCTAssertNil(AIRequestBuilder.errorMessage(from: Data("nope".utf8), provider: .openai))
        XCTAssertEqual(AIError.http(401, "x").errorDescription, "Der API-Schlüssel wurde abgelehnt.")
        XCTAssertTrue(AIError.missingKey(.google).needsSetup)
        XCTAssertFalse(AIError.http(500, nil).needsSetup)
    }

    // MARK: Text helpers

    func testParseListReadsJSONAndFallsBackToLines() {
        XCTAssertEqual(AIText.parseList(#"["eins", "zwei", "drei", "vier"]"#, max: 3), ["eins", "zwei", "drei"])
        XCTAssertEqual(AIText.parseList("```json\n[\"a\",\"b\"]\n```", max: 3), ["a", "b"])
        XCTAssertEqual(AIText.parseList("1. Erste Version\n2) Zweite Version\n- Dritte\n\n", max: 3), ["Erste Version", "Zweite Version", "Dritte"])
        XCTAssertEqual(AIText.parseList("\"Hallo\"\n\"Hallo\"\n„Welt“", max: 3), ["Hallo", "Welt"], "duplicates and quotes go")
        XCTAssertEqual(AIText.parseList("   ", max: 3), [])
    }

    func testCleanSingleStripsFencesAndWrappingQuotes() {
        XCTAssertEqual(AIText.cleanSingle("```\nHallo Welt\n```"), "Hallo Welt")
        XCTAssertEqual(AIText.cleanSingle("„Hallo Welt“"), "Hallo Welt")
        XCTAssertEqual(AIText.cleanSingle("\"Hallo\" und \"Welt\""), "\"Hallo\" und \"Welt\"", "quotes around parts stay")
        XCTAssertEqual(AIText.cleanSingle("  Text mit\nZeilen  "), "Text mit\nZeilen")
    }

    func testLastSentence() {
        XCTAssertEqual(AIText.lastSentence(in: "Hallo Welt. Das ist ein Test. ")?.sentence, "Das ist ein Test.")
        XCTAssertEqual(AIText.lastSentence(in: "Hallo Welt. Das ist ein Test. ")?.trailing, " ")
        XCTAssertEqual(AIText.lastSentence(in: "Erste Zeile\nWie geht es dir?\n")?.sentence, "Wie geht es dir?")
        XCTAssertEqual(AIText.lastSentence(in: "Das ist ein Test")?.sentence, nil, "no terminator")
        XCTAssertNil(AIText.lastSentence(in: "Ok. "), "too short")
        XCTAssertEqual(AIText.lastSentence(in: "Wirklich?! Das glaube ich nicht… ")?.sentence, "Das glaube ich nicht…")
    }

    func testSourceKeepsTheTailAtABoundary() {
        let text = String(repeating: "Ein Satz. ", count: 300)
        let source = AIText.source(before: text, limit: 100)
        XCTAssertLessThanOrEqual(source.count, 100)
        XCTAssertTrue(source.hasPrefix("Ein Satz."), "starts at a sentence start: \(source)")
        XCTAssertTrue(text.hasSuffix(source))
        XCTAssertEqual(AIText.source(before: "  kurz"), "kurz")
    }

    func testJoiner() {
        XCTAssertEqual(AIText.joiner(before: "Hallo", continuation: "Welt"), " ")
        XCTAssertEqual(AIText.joiner(before: "Hallo ", continuation: "Welt"), "")
        XCTAssertEqual(AIText.joiner(before: "Hallo", continuation: ", Welt"), "")
        XCTAssertEqual(AIText.joiner(before: "", continuation: "Welt"), "")
    }

    func testPromptsMentionTheTaskAndTheOptions() {
        let rewrite = AIPrompts.prompt(for: AIRequestSpec(feature: .rewrite, text: "t", language: .german, tone: .shorter))
        XCTAssertTrue(rewrite.expectsList)
        XCTAssertEqual(rewrite.maxItems, 3)
        XCTAssertTrue(rewrite.system.contains("as short as possible"))
        XCTAssertTrue(rewrite.system.contains("German"))
        let cont = AIPrompts.prompt(for: AIRequestSpec(feature: .continueWriting, text: "t", language: .english))
        XCTAssertTrue(cont.system.contains("continuations"))
        XCTAssertTrue(cont.system.contains("English"))
        let single = AIPrompts.prompt(for: AIRequestSpec(feature: .proofread, text: "t", language: .german))
        XCTAssertFalse(single.expectsList)
    }

    func testInMemoryKeyStore() {
        let store = AIKeyStore(inMemory: true)
        XCTAssertFalse(store.hasKey(for: .openai))
        store.setKey("  sk-abc  ", for: .openai)
        XCTAssertEqual(store.key(for: .openai), "sk-abc")
        XCTAssertEqual(store.configuredProviders, [.openai])
        store.setKey("", for: .openai)
        XCTAssertFalse(store.hasKey(for: .openai))
    }

    func testKeyPlausibility() {
        XCTAssertTrue(AIProvider.anthropic.looksLikeKey("sk-ant-api03-0123456789abcdefghij"))
        XCTAssertFalse(AIProvider.anthropic.looksLikeKey("sk-0123456789abcdefghij"))
        XCTAssertTrue(AIProvider.google.looksLikeKey("AIzaSyA0123456789abcdefghijklmnop"))
        XCTAssertFalse(AIProvider.openai.looksLikeKey("short"))
    }
}
