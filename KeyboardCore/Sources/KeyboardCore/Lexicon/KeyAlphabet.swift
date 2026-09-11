import Foundation
import CoreGraphics

/// Compact letter codes (0..<30) for the German alphabet as it maps onto layout keys.
/// ß is folded onto the s key because it has no key of its own on the base layer.
public enum KeyAlphabet {
    public static let letters: [Character] = Array("abcdefghijklmnopqrstuvwxyzäöü")
    public static let count = letters.count   // 29

    private static let table: [Character: UInt8] = {
        var t: [Character: UInt8] = [:]
        for (i, c) in letters.enumerated() { t[c] = UInt8(i) }
        t["ß"] = t["s"]!
        return t
    }()

    /// Letter code for a character, folding case, ß→s and common diacritics onto base keys.
    public static func code(for character: Character) -> UInt8? {
        guard let lower = character.lowercased().first else { return nil }
        if let c = table[lower] { return c }
        return foldedCode(lower)
    }

    /// True for letters outside the German alphabet that map onto a key only by folding ("á", "ç").
    public static func isFoldedLetter(_ c: Character) -> Bool {
        guard let lower = c.lowercased().first, table[lower] == nil else { return false }
        return foldedCode(lower) != nil
    }

    static func foldedCode(_ c: Character) -> UInt8? {
        guard let scalar = c.unicodeScalars.first else { return nil }
        // Strip diacritics: "é" -> "e"
        let base = String(scalar).folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en"))
        guard let bc = base.first, bc != c else { return nil }
        return table[Character(bc.lowercased())]
    }

    public static func character(for code: UInt8) -> Character { letters[Int(code)] }

    /// Codes of a word with consecutive duplicates collapsed ("hallo" → h a l o), the form a swipe path visits.
    public static func swipeCodes(_ word: String) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(word.count)
        for ch in word {
            guard let c = code(for: ch) else { continue }
            if out.last != c { out.append(c) }
        }
        return out
    }

    /// Codes of a word, one per letter, nil for words containing non-letters (hyphens etc. are skipped).
    public static func codes(_ word: String) -> [UInt8] {
        word.compactMap { code(for: $0) }
    }

    // MARK: Byte-level helpers (used by the lexicon loader to avoid per-character String work)

    /// Letter code for a UTF-8 sequence starting at `i`; advances `i`. Handles ASCII and the
    /// Latin-1 supplement (ä ö ü ß, accented vowels). Returns nil for non-letters.
    /// `unsupported` is set when a script outside Latin-1 is met (caller falls back to Strings).
    @inline(__always)
    static func code(utf8 bytes: UnsafeBufferPointer<UInt8>, at i: inout Int, unsupported: inout Bool) -> UInt8? {
        let b = bytes[i]
        if b < 0x80 {
            i += 1
            switch b {
            case 0x61...0x7A: return b - 0x61            // a-z
            case 0x41...0x5A: return b - 0x41            // A-Z
            default: return nil
            }
        }
        if b == 0xC3, i + 1 < bytes.count {
            let c = bytes[i + 1]
            i += 2
            return latin1Codes[Int(c & 0x3F)]
        }
        // 2–4 byte sequences outside Latin-1: skip the sequence, flag it.
        unsupported = true
        i += b >= 0xF0 ? 4 : (b >= 0xE0 ? 3 : 2)
        return nil
    }

    /// Codes for the 64 code points U+00C0…U+00FF (second UTF-8 byte 0x80…0xBF after 0xC3).
    /// 255 = not a letter.
    static let latin1Codes: [UInt8?] = {
        var t = [UInt8?](repeating: nil, count: 64)
        func set(_ scalar: UInt32, _ ch: Character) { t[Int(scalar - 0xC0)] = table[ch] }
        // À Á Â Ã Ä Å Æ Ç È É Ê Ë Ì Í Î Ï Ð Ñ Ò Ó Ô Õ Ö × Ø Ù Ú Û Ü Ý Þ ß
        // à á â ã ä å æ ç è é ê ë ì í î ï ð ñ ò ó ô õ ö ÷ ø ù ú û ü ý þ ÿ
        let map: [(UInt32, Character)] = [
            (0xC0, "a"), (0xC1, "a"), (0xC2, "a"), (0xC3, "a"), (0xC4, "ä"), (0xC5, "a"), (0xC6, "a"), (0xC7, "c"),
            (0xC8, "e"), (0xC9, "e"), (0xCA, "e"), (0xCB, "e"), (0xCC, "i"), (0xCD, "i"), (0xCE, "i"), (0xCF, "i"),
            (0xD0, "d"), (0xD1, "n"), (0xD2, "o"), (0xD3, "o"), (0xD4, "o"), (0xD5, "o"), (0xD6, "ö"), (0xD8, "o"),
            (0xD9, "u"), (0xDA, "u"), (0xDB, "u"), (0xDC, "ü"), (0xDD, "y"), (0xDE, "t"), (0xDF, "s"),
            (0xE0, "a"), (0xE1, "a"), (0xE2, "a"), (0xE3, "a"), (0xE4, "ä"), (0xE5, "a"), (0xE6, "a"), (0xE7, "c"),
            (0xE8, "e"), (0xE9, "e"), (0xEA, "e"), (0xEB, "e"), (0xEC, "i"), (0xED, "i"), (0xEE, "i"), (0xEF, "i"),
            (0xF0, "d"), (0xF1, "n"), (0xF2, "o"), (0xF3, "o"), (0xF4, "o"), (0xF5, "o"), (0xF6, "ö"), (0xF8, "o"),
            (0xF9, "u"), (0xFA, "u"), (0xFB, "u"), (0xFC, "ü"), (0xFD, "y"), (0xFE, "t"), (0xFF, "y"),
        ]
        for (scalar, ch) in map { set(scalar, ch) }
        return t
    }()

    /// Appends the lowercase UTF-8 of `bytes` to `out` for ASCII + Latin-1 text.
    /// Returns false (and appends nothing) when other scripts are present.
    static func appendLowercased(_ bytes: UnsafeBufferPointer<UInt8>, to out: inout [UInt8]) -> Bool {
        let start = out.count
        var i = 0
        while i < bytes.count {
            let b = bytes[i]
            if b < 0x80 {
                out.append(b >= 0x41 && b <= 0x5A ? b + 0x20 : b)
                i += 1
            } else if b == 0xC3, i + 1 < bytes.count {
                let c = bytes[i + 1]
                // U+00C0…U+00DE (except ×) lowercase by +0x20 in the second byte.
                out.append(0xC3)
                out.append((c >= 0x80 && c <= 0x9E && c != 0x97) ? c + 0x20 : c)
                i += 2
            } else {
                out.removeSubrange(start..<out.count)
                return false
            }
        }
        return true
    }
}

/// Key centres in layout space for every letter code, plus the key size for distance normalisation.
public struct KeyMap: Sendable {
    public let centers: [CGPoint]          // indexed by letter code
    public let keyWidth: CGFloat
    public let keyHeight: CGFloat

    /// nil when the layout doesn't place every letter exactly once (swipe is then unavailable).
    public init?(geometry: KeyboardGeometry) {
        var centers = [CGPoint](repeating: .zero, count: KeyAlphabet.count)
        var seen = Set<UInt8>()
        for kf in geometry.keyFrames where kf.key.isLetter {
            if let ch = kf.key.character, let code = KeyAlphabet.code(for: ch), seen.insert(code).inserted {
                centers[Int(code)] = kf.center
            }
        }
        guard seen.count == KeyAlphabet.count else { return nil }
        self.centers = centers
        keyWidth = geometry.unitWidth
        keyHeight = geometry.rowHeight
    }

    public init(centers: [CGPoint], keyWidth: CGFloat, keyHeight: CGFloat) {
        self.centers = centers
        self.keyWidth = keyWidth
        self.keyHeight = keyHeight
    }

    /// Standard German letters layout at a reference size, for tests and offline tools.
    public static func reference(width: CGFloat = 390, height: CGFloat = 216) -> KeyMap {
        KeyMap(geometry: KeyboardGeometry(layout: GermanLayouts.letters(), size: CGSize(width: width, height: height)))!
    }

    /// Letter codes sorted by distance from a point, limited to those within `radius`.
    public func nearestCodes(to p: CGPoint, radius: CGFloat, limit: Int) -> [(code: UInt8, distance: CGFloat)] {
        var result: [(UInt8, CGFloat)] = []
        for (i, c) in centers.enumerated() {
            let d = hypot(c.x - p.x, c.y - p.y)
            if d <= radius { result.append((UInt8(i), d)) }
        }
        result.sort { $0.1 < $1.1 }
        return Array(result.prefix(limit)).map { (code: $0.0, distance: $0.1) }
    }

    /// Whether two letter codes are horizontal/vertical/diagonal neighbours on the layout.
    public func areAdjacent(_ a: UInt8, _ b: UInt8) -> Bool {
        let pa = centers[Int(a)], pb = centers[Int(b)]
        // Gaps make neighbouring centres ~1.17 key widths apart; rows are ~1.25 key heights apart.
        return abs(pa.x - pb.x) <= keyWidth * 1.4 && abs(pa.y - pb.y) <= keyHeight * 1.5
    }
}
