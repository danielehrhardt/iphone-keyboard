import Foundation

/// The system instruction and user message for one request.
public struct AIPrompt: Equatable, Sendable {
    public let system: String
    public let user: String
    /// The model was asked for a JSON array of `maxItems` strings.
    public let expectsList: Bool
    public let maxItems: Int

    public init(system: String, user: String, expectsList: Bool, maxItems: Int) {
        self.system = system
        self.user = user
        self.expectsList = expectsList
        self.maxItems = maxItems
    }
}

/// Builds the prompts for every feature. Prompts are English; the model is told to keep the
/// text's language and gets the keyboard language as the tie-breaker.
public enum AIPrompts {

    public static func prompt(for spec: AIRequestSpec) -> AIPrompt {
        let count = spec.feature.resultCount
        var rules = [
            "You are the writing assistant built into an iPhone keyboard. The user sends the text from a text field.",
            "Reply with the result only: no preamble, no explanation, no markdown, no code fences, no quotation marks around the result.",
            "Keep the language of the text. The keyboard is set to \(languageName(spec.language)); if the text's language is ambiguous, use that.",
            "Preserve line breaks, emoji, names, numbers, links and @mentions unless the task says otherwise.",
        ]
        switch spec.feature {
        case .proofread:
            rules += [
                "Task: correct spelling, grammar, punctuation and capitalization mistakes in the text.",
                "Keep the wording, meaning, tone and length. Do not rephrase; change only what is wrong.",
                "German text follows standard German orthography (ß, umlauts, noun capitalization); English text follows standard English.",
                "If the text is already correct, return it unchanged.",
            ]
        case .rewrite:
            rules += [
                "Task: rewrite the text. \(spec.tone.instruction)",
                "Provide \(count) genuinely different versions.",
                listRule(count),
            ]
        case .continueWriting:
            rules += [
                "Task: the text ends where the user's cursor is. Suggest \(count) different short continuations (2 to 8 words each) that could come next.",
                "Each continuation starts exactly where the text ends; never repeat the text. Match its language, tone and register.",
                listRule(count),
            ]
        case .translate:
            rules += [
                "Task: translate the text into \(spec.target.englishName).",
                "Return only the translation, nothing else. If the text is already in \(spec.target.englishName), return it unchanged.",
            ]
        case .answer:
            rules += [
                "Task: the text is a question or request from the user. Answer it helpfully and concisely in the language of the text.",
                "Aim for at most about 60 words unless a longer answer is clearly needed. Plain text that can be pasted into a message.",
            ]
        }
        return AIPrompt(system: rules.joined(separator: "\n"),
                        user: spec.text,
                        expectsList: count > 1,
                        maxItems: count)
    }

    private static func listRule(_ count: Int) -> String {
        "Respond with a JSON array of exactly \(count) strings and nothing else, for example [\"…\", \"…\", \"…\"]."
    }

    private static func languageName(_ language: KeyboardLanguage) -> String {
        switch language {
        case .german: return "German"
        case .english: return "English"
        }
    }
}
