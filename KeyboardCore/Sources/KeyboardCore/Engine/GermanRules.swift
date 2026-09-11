import Foundation

/// German orthography helpers. The shared mechanics live in `LanguageRules`; this keeps the
/// German-specific pieces and the static entry points the rest of the code grew up with.
public enum GermanRules {

    /// Spellings with ASCII digraphs resolved: "schoen" → ["schön"], "strasse" → ["straße"],
    /// "Fuesse" → ["Füße", "Füsse", "Fueße"]. Returns candidates other than the input.
    public static func umlautVariants(of word: String) -> [String] {
        let pairs: [(String, String)] = [("ae", "ä"), ("oe", "ö"), ("ue", "ü"), ("Ae", "Ä"), ("Oe", "Ö"), ("Ue", "Ü"), ("ss", "ß")]
        var results: Set<String> = [word]
        for (from, to) in pairs {
            var next = results
            for w in results where w.contains(from) {
                next.insert(w.replacingOccurrences(of: from, with: to))
                // also single replacements from the right (Strasse → Straße but "Wasser" stays)
                if let r = w.range(of: from, options: .backwards) {
                    next.insert(w.replacingCharacters(in: r, with: to))
                }
            }
            results = next
        }
        results.remove(word)
        return results.sorted()
    }

    /// Characters that end a sentence.
    public static let sentenceTerminators: Set<Character> = LanguageRules.sentenceTerminators

    /// Whether the text before the cursor means the next letter should be capitalised (German abbreviations).
    public static func isSentenceStart(_ before: String) -> Bool {
        LanguageRules.german.isSentenceStart(before)
    }

    public static let openingDelimiters: Set<Character> = LanguageRules.openingDelimiters

    /// Last whitespace-separated token.
    public static func lastToken(of text: String) -> String { LanguageRules.lastToken(of: text) }
}
