import Foundation

/// German orthography helpers.
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
    public static let sentenceTerminators: Set<Character> = [".", "!", "?", "…"]

    /// Whether the text before the cursor means the next letter should be capitalised.
    public static func isSentenceStart(_ before: String) -> Bool {
        var trimmed = Substring(before)
        // Opening quotes/brackets don't change what comes next: „Hallo“, (Hallo).
        var strippedQuote = false
        while let last = trimmed.last, last == " " || last == "\u{00A0}" || openingDelimiters.contains(last) {
            if openingDelimiters.contains(last) && last != "(" && last != "[" && last != "{" { strippedQuote = true }
            trimmed = trimmed.dropLast()
        }
        guard let last = trimmed.last else { return true }
        if last == "\n" { return true }
        if last == ":" && strippedQuote { return true }          // Er sagte: „Hallo“
        if sentenceTerminators.contains(last) {
            // "z.B." / "3.5" / "Dr." / "A." – abbreviations, decimals and initials don't start sentences.
            let word = lastToken(of: String(trimmed.dropLast()))
            let looksAbbreviated = word.count == 1 || word.contains(".") || abbreviations.contains(word.lowercased())
            if last == ".", looksAbbreviated || word.last?.isNumber == true {
                return false
            }
            // Only once whitespace follows the terminator – "Hallo." is still being typed.
            return trimmed.count < before.count
        }
        return false
    }

    public static let openingDelimiters: Set<Character> = ["(", "[", "{", "„", "“", "\"", "‚", "‘", "«", "»", "›"]

    static let abbreviations: Set<String> = ["z.b", "bzw", "usw", "etc", "ca", "dr", "prof", "nr", "str", "evtl", "ggf", "inkl", "vgl", "zzgl", "mfg", "vlt", "vllt", "bsp", "d.h", "u.a", "o.ä", "s.o", "s.u"]

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
}
