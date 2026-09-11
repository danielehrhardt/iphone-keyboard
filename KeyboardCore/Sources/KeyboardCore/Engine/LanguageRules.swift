import Foundation

/// Orthography of one language: where sentences start, which ASCII spellings stand in for
/// letters the typist may not have on the keyboard, and what to suggest without any context.
/// The mechanics are shared; only the data differs per language.
public struct LanguageRules: Sendable {
    /// Lowercase abbreviations (without the trailing period) after which a period does not end
    /// the sentence: "usw. morgen", "Mr. Smith". Dotted ones ("z.B.", "e.g.") and single letters
    /// need no entry: any token with a period inside is already treated as an abbreviation.
    public let abbreviations: Set<String>
    /// Spellings the typed word may stand for ("schoen" → "schön"); empty for languages without
    /// such conventions. Candidates other than the input.
    public let spellingVariants: @Sendable (String) -> [String]
    /// Suggestions at a sentence start when nothing else is known.
    public let coldStartWords: [String]
    /// Filler suggestions mid-sentence when no bigram is known.
    public let commonWords: [String]

    public init(abbreviations: Set<String>,
                spellingVariants: @escaping @Sendable (String) -> [String] = { _ in [] },
                coldStartWords: [String],
                commonWords: [String]) {
        self.abbreviations = abbreviations
        self.spellingVariants = spellingVariants
        self.coldStartWords = coldStartWords
        self.commonWords = commonWords
    }

    // MARK: Shared mechanics

    /// Characters that end a sentence.
    public static let sentenceTerminators: Set<Character> = [".", "!", "?", "…"]

    /// Quotes and brackets that may open a sentence without changing what follows.
    public static let openingDelimiters: Set<Character> = ["(", "[", "{", "„", "“", "\"", "‚", "‘", "«", "»", "›"]

    /// Whether the text before the cursor means the next letter should be capitalised.
    public func isSentenceStart(_ before: String) -> Bool {
        var trimmed = Substring(before)
        // Opening quotes/brackets don't change what comes next: „Hallo“, (Hallo).
        var strippedQuote = false
        while let last = trimmed.last, last == " " || last == "\u{00A0}" || Self.openingDelimiters.contains(last) {
            if Self.openingDelimiters.contains(last) && last != "(" && last != "[" && last != "{" { strippedQuote = true }
            trimmed = trimmed.dropLast()
        }
        guard let last = trimmed.last else { return true }
        if last == "\n" { return true }
        if last == ":" && strippedQuote { return true }          // Er sagte: „Hallo“
        if Self.sentenceTerminators.contains(last) {
            // "z.B." / "3.5" / "Dr." / "A." – abbreviations, decimals and initials don't start sentences.
            let word = Self.lastToken(of: String(trimmed.dropLast()))
            let looksAbbreviated = word.count == 1 || word.contains(".") || abbreviations.contains(word.lowercased())
            if last == ".", looksAbbreviated || word.last?.isNumber == true {
                return false
            }
            // Only once whitespace follows the terminator – "Hallo." is still being typed.
            return trimmed.count < before.count
        }
        return false
    }

    /// Last whitespace-separated token.
    public static func lastToken(of text: String) -> String {
        var end = text.endIndex
        while end > text.startIndex, text[text.index(before: end)].isWhitespace { end = text.index(before: end) }
        var start = end
        while start > text.startIndex {
            let c = text[text.index(before: start)]
            if c.isWhitespace || c == "\n" { break }
            start = text.index(before: start)
        }
        return String(text[start..<end])
    }

    // MARK: Languages

    public static let german = LanguageRules(
        abbreviations: ["bzw", "usw", "etc", "ca", "dr", "prof", "nr", "str", "evtl", "ggf", "inkl", "vgl", "zzgl",
                        "mfg", "vlt", "vllt", "bsp"],
        spellingVariants: { GermanRules.umlautVariants(of: $0) },
        coldStartWords: ["Ich", "Hallo", "Danke", "Ja", "Nein", "Wir", "Guten", "Alles"],
        commonWords: ["und", "ich", "die", "das", "nicht", "auch"]
    )

    public static let english = LanguageRules(
        abbreviations: ["mr", "mrs", "ms", "dr", "prof", "sr", "jr", "st", "vs", "etc", "approx", "inc",
                        "ltd", "co", "dept", "est", "fig", "vol", "misc", "govt", "asap"],
        coldStartWords: ["I", "Hello", "Thanks", "Yes", "No", "We", "Good", "The"],
        commonWords: ["and", "the", "I", "to", "a", "not"]
    )
}
