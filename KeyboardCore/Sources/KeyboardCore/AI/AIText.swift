import Foundation

/// String helpers around the assistant: what to send, and how to read what comes back.
public enum AIText {

    /// Longest text sent in one request (characters). The trailing part of a longer field is
    /// used, cut at a sentence or line boundary.
    public static let sourceLimit = 2000

    public static let sentenceTerminators: Set<Character> = [".", "!", "?", "…"]

    /// The part of the text before the cursor the assistant works on: everything when it fits
    /// the limit, else the last sentences. Leading whitespace is dropped so a replacement
    /// starts where the words start.
    public static func source(before text: String, limit: Int = sourceLimit) -> String {
        var s = Substring(text)
        if s.count > limit {
            s = s.suffix(limit)
            // Skip the (probably cut) first sentence when there is enough text after it.
            if let boundary = s.firstIndex(where: { sentenceTerminators.contains($0) || $0.isNewline }) {
                let rest = s[s.index(after: boundary)...]
                if rest.count >= limit / 3 { s = rest }
            }
        }
        while let first = s.first, first.isWhitespace || first.isNewline { s = s.dropFirst() }
        return String(s)
    }

    /// The sentence that was just finished: text before the cursor ends with a terminator and
    /// optional whitespace. Returns the sentence (without leading whitespace) and the trailing
    /// whitespace after it, or nil when the text doesn't end a sentence of at least two words.
    public static func lastSentence(in text: String) -> (sentence: String, trailing: String)? {
        var body = Substring(text)
        var trailing = ""
        while let last = body.last, last.isWhitespace || last.isNewline {
            trailing.insert(last, at: trailing.startIndex)
            body = body.dropLast()
        }
        guard let last = body.last, sentenceTerminators.contains(last) else { return nil }
        // Closing quotes after the terminator belong to the sentence; a terminator right before
        // the last one (ellipsis, "?!") too.
        var end = body.index(before: body.endIndex)
        while end > body.startIndex, sentenceTerminators.contains(body[body.index(before: end)]) { end = body.index(before: end) }
        var start = end
        while start > body.startIndex {
            let c = body[body.index(before: start)]
            if sentenceTerminators.contains(c) || c.isNewline { break }
            start = body.index(before: start)
        }
        var sentence = body[start...]
        while let first = sentence.first, first.isWhitespace { sentence = sentence.dropFirst() }
        let words = sentence.split(whereSeparator: { $0.isWhitespace }).count
        guard words >= 2, sentence.count >= 8 else { return nil }
        return (String(sentence), trailing)
    }

    /// Reads a list reply: a JSON array of strings when the model obeyed, else the non-empty
    /// lines with bullets, numbering and quotes stripped. Never more than `max` items.
    public static func parseList(_ raw: String, max: Int) -> [String] {
        let text = stripFences(raw)
        if let start = text.firstIndex(of: "["), let end = text.lastIndex(of: "]"), start < end,
           let data = String(text[start...end]).data(using: .utf8),
           let array = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            let items = array.compactMap { $0 as? String }.map(cleanSingle).filter { !$0.isEmpty }
            if !items.isEmpty { return dedupe(items, max: max) }
        }
        let lines = text.split(whereSeparator: { $0.isNewline }).map { line -> String in
            var s = Substring(line)
            while let f = s.first, f.isWhitespace { s = s.dropFirst() }
            // "1. ", "1) ", "- ", "• ", "* "
            if let dot = s.firstIndex(where: { $0 == "." || $0 == ")" }), s[..<dot].allSatisfy(\.isNumber), !s[..<dot].isEmpty, s.distance(from: s.startIndex, to: dot) <= 2 {
                s = s[s.index(after: dot)...]
            } else if let f = s.first, "-•*–".contains(f) {
                s = s.dropFirst()
            }
            return cleanSingle(String(s))
        }.filter { !$0.isEmpty }
        return dedupe(lines, max: max)
    }

    /// A single-result reply: fences, surrounding quotes and whitespace removed.
    public static func cleanSingle(_ raw: String) -> String {
        var s = stripFences(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        let pairs: [(Character, Character)] = [("\"", "\""), ("„", "“"), ("“", "”"), ("‘", "’"), ("'", "'")]
        for (open, close) in pairs where s.count >= 2 && s.first == open && s.last == close {
            let inner = s.dropFirst().dropLast()
            // Only strip a pair that wraps the whole text, not quotes that happen to bracket it.
            if !inner.contains(close) || open == close && !inner.contains(open) {
                s = String(inner).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return s
    }

    /// Removes ``` fences (with or without a language tag) around the text.
    public static func stripFences(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("```") else { return s }
        s = String(s.dropFirst(3))
        if let newline = s.firstIndex(where: { $0.isNewline }) { s = String(s[s.index(after: newline)...]) }
        if s.hasSuffix("```") { s = String(s.dropLast(3)) }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether a correction is worth showing: something other than surrounding whitespace changed.
    public static func differs(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: .whitespacesAndNewlines) != b.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The text to insert after `before` so a continuation reads on naturally: a space is added
    /// when the text ends in a word or punctuation and the continuation doesn't start with one.
    public static func joiner(before: String, continuation: String) -> String {
        guard let last = before.last, let first = continuation.first else { return "" }
        if last.isWhitespace || last.isNewline || first.isWhitespace { return "" }
        if first.isPunctuation && !"(\"„“‘'[".contains(first) { return "" }
        return " "
    }

    private static func dedupe(_ items: [String], max: Int) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for item in items where seen.insert(item.lowercased()).inserted {
            out.append(item)
            if out.count == max { break }
        }
        return out
    }
}
