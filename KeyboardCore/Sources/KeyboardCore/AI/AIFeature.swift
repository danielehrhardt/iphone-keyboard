import Foundation

/// What the AI panel can do with the text around the cursor.
public enum AIFeature: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    /// Fixes spelling, grammar and punctuation; also runs quietly on finished sentences when
    /// `KeyboardSettings.aiAutocorrect` is on.
    case proofread
    /// Rewrites in a chosen tone; three versions to pick from.
    case rewrite
    /// Suggests how the text could go on; also feeds the strip when `aiSuggestions` is on.
    case continueWriting
    /// Translates into a chosen language.
    case translate
    /// Treats the text as a question and inserts the answer.
    case answer

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .proofread: return "Korrigieren"
        case .rewrite: return "Umformulieren"
        case .continueWriting: return "Weiterschreiben"
        case .translate: return "Übersetzen"
        case .answer: return "Antworten"
        }
    }

    /// One line for the settings list.
    public var detail: String {
        switch self {
        case .proofread: return "Rechtschreibung, Grammatik und Zeichensetzung"
        case .rewrite: return "Förmlich, locker, kürzer oder länger"
        case .continueWriting: return "Schlägt vor, wie es weitergeht"
        case .translate: return "In eine andere Sprache"
        case .answer: return "Beantwortet eine Frage im Textfeld"
        }
    }

    /// SF Symbol for chips and lists.
    public var symbol: String {
        switch self {
        case .proofread: return "checkmark.circle"
        case .rewrite: return "wand.and.stars"
        case .continueWriting: return "text.append"
        case .translate: return "globe"
        case .answer: return "bubble.left.and.text.bubble.right"
        }
    }

    /// Whether a picked result replaces the source text (else it is inserted at the cursor).
    public var replacesSource: Bool {
        switch self {
        case .proofread, .rewrite, .translate, .answer: return true
        case .continueWriting: return false
        }
    }

    /// How many alternatives the model is asked for.
    public var resultCount: Int {
        switch self {
        case .rewrite, .continueWriting: return 3
        case .proofread, .translate, .answer: return 1
        }
    }

    /// Verb on a result card.
    public var applyLabel: String {
        switch self {
        case .continueWriting: return "Einsetzen"
        case .proofread, .rewrite, .translate, .answer: return "Ersetzen"
        }
    }
}

/// Tone options of `AIFeature.rewrite`.
public enum AIRewriteTone: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case neutral, formal, casual, shorter, longer

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .neutral: return "Neutral"
        case .formal: return "Förmlich"
        case .casual: return "Locker"
        case .shorter: return "Kürzer"
        case .longer: return "Länger"
        }
    }

    /// The instruction the prompt carries for this tone.
    var instruction: String {
        switch self {
        case .neutral: return "Make the text clearer and more polished while keeping its tone and length roughly the same."
        case .formal: return "Make the text polite and formal, suitable for a business or official message."
        case .casual: return "Make the text relaxed and friendly, like a message to a good friend."
        case .shorter: return "Make the text as short as possible without losing any information."
        case .longer: return "Make the text more detailed and complete; add helpful detail but do not invent facts."
        }
    }
}

/// Target languages of `AIFeature.translate`.
public enum AITranslationTarget: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case german = "de"
    case english = "en"
    case french = "fr"
    case spanish = "es"
    case italian = "it"
    case turkish = "tr"

    public var id: String { rawValue }

    /// The language's own name, for the chips.
    public var title: String {
        switch self {
        case .german: return "Deutsch"
        case .english: return "English"
        case .french: return "Français"
        case .spanish: return "Español"
        case .italian: return "Italiano"
        case .turkish: return "Türkçe"
        }
    }

    /// Name used inside the prompt.
    var englishName: String {
        switch self {
        case .german: return "German"
        case .english: return "English"
        case .french: return "French"
        case .spanish: return "Spanish"
        case .italian: return "Italian"
        case .turkish: return "Turkish"
        }
    }

    /// The natural target for a keyboard language: German text goes to English and back.
    public static func suggested(for language: KeyboardLanguage) -> AITranslationTarget {
        switch language {
        case .german: return .english
        case .english: return .german
        }
    }
}

/// One request to the assistant: the feature, its option and the text it works on.
public struct AIRequestSpec: Equatable, Sendable {
    public var feature: AIFeature
    public var tone: AIRewriteTone
    public var target: AITranslationTarget
    public var text: String
    /// The keyboard's typing language, the tie-breaker when the text's language is unclear.
    public var language: KeyboardLanguage

    public init(feature: AIFeature, text: String, language: KeyboardLanguage,
                tone: AIRewriteTone = .neutral, target: AITranslationTarget = .english) {
        self.feature = feature
        self.text = text
        self.language = language
        self.tone = tone
        self.target = target
    }
}
