import Foundation

/// A typing language the keyboard supports. Everything language-specific hangs off this value:
/// the letter layout, the bundled dictionary, the orthography rules, the personal dictionary
/// file and the labels the keys show. Adding a language means adding a case here, a layout, a
/// `LanguageRules` value and the two dictionary files (see `scripts/build_dictionary.py`).
public enum KeyboardLanguage: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case german = "de"
    case english = "en"

    public var id: String { rawValue }

    /// What a fresh install types in.
    public static let `default`: KeyboardLanguage = .german

    /// The language's own name, shown on the space bar while several languages are enabled and
    /// in the settings list.
    public var title: String {
        switch self {
        case .german: return "Deutsch"
        case .english: return "English"
        }
    }

    /// Short marker for the language switch in the suggestion strip.
    public var badge: String { rawValue.uppercased() }

    /// Label of the space bar when only one language is enabled.
    public var spaceLabel: String {
        switch self {
        case .german: return "Leerzeichen"
        case .english: return "space"
        }
    }

    public var localeIdentifier: String {
        switch self {
        case .german: return "de_DE"
        case .english: return "en_US"
        }
    }

    /// Orthography: sentence boundaries, digraph spellings, cold-start suggestions.
    public var rules: LanguageRules {
        switch self {
        case .german: return .german
        case .english: return .english
        }
    }

    /// Base names of the bundled dictionary resources (`de_words.txt`, `de_bigrams.txt`).
    var wordsResource: String { "\(rawValue)_words" }
    var bigramsResource: String { "\(rawValue)_bigrams" }

    /// File name of the personal dictionary in the app group. German keeps the original name so
    /// words learned before there were several languages stay where they are.
    var userLexiconFileName: String {
        self == .german ? "user-lexicon.json" : "user-lexicon-\(rawValue).json"
    }

    /// The letter layout family for this language (QWERTZ with umlaut keys, QWERTY, …).
    public func layout(for layer: KeyboardLayer, options: LayoutOptions = LayoutOptions()) -> KeyboardLayout {
        var o = options
        o.language = self
        return KeyboardLayouts.layout(for: layer, options: o)
    }
}
