import Foundation

/// The static German word list with frequencies and a bigram model, laid out for fast
/// swipe decoding and fuzzy matching. Word ids are frequency ranks (0 = most frequent).
///
/// Memory matters (keyboard extensions are killed around 60–70 MB), so everything lives in flat
/// arrays: no string-keyed dictionaries, no per-word objects. Loading works directly on UTF-8 bytes.
public final class Lexicon: @unchecked Sendable {

    public let words: [String]
    /// Natural-log unigram probability per word id.
    public let logProb: [Float]
    /// Swipe codes (duplicates collapsed) for all words, flat, with offsets.
    let swipeCodes: [UInt8]
    let swipeOffsets: [UInt32]
    /// Full letter codes (one per letter), flat, with offsets.
    let letterCodes: [UInt8]
    let letterOffsets: [UInt32]
    /// Word ids grouped by (first swipe code, last swipe code), frequency order within each bucket.
    let bucketIDs: [Int32]
    let bucketOffsets: [Int32]     // KeyAlphabet.count² + 1 entries
    /// Word ids sorted by lowercase spelling (UTF-8 byte order); ties are ordered by frequency.
    /// All spelling lookups are binary searches over `lowerBytes`.
    let sortedByLower: [Int32]
    let lowerBytes: [UInt8]               // lowercase UTF-8 of each entry, in `sortedByLower` order
    let lowerOffsets: [UInt32]
    /// Bigram successors, flat: for word id w, entries bigramOffsets[w]..<bigramOffsets[w+1].
    private(set) var bigramNext: [Int32] = []
    private(set) var bigramLogProb: [Float] = []
    private(set) var bigramOffsets: [Int32] = []

    public var count: Int { words.count }
    public let minLogProb: Float

    // MARK: Loading

    public static func loadBundled() throws -> Lexicon {
        guard let wordsURL = Bundle.module.url(forResource: "de_words", withExtension: "txt") else {
            throw LexiconError.missingResource("de_words.txt")
        }
        let bigramsURL = Bundle.module.url(forResource: "de_bigrams", withExtension: "txt")
        return try Lexicon(wordsFile: wordsURL, bigramsFile: bigramsURL)
    }

    /// `wordsFile`: "word<TAB>count" lines, **sorted by lowercase spelling** (code-point order).
    /// `bigramsFile`: "w1<TAB>w2<TAB>count" lines grouped by w1, most frequent first.
    public convenience init(wordsFile: URL, bigramsFile: URL?) throws {
        let data = try Data(contentsOf: wordsFile, options: .mappedIfSafe)
        let bigramData = bigramsFile.flatMap { try? Data(contentsOf: $0, options: .mappedIfSafe) }
        self.init(wordsData: data, bigramData: bigramData)
    }

    /// Convenience for tests and tools: words in any order.
    public convenience init(words: [String], counts: [Double], bigramText: String? = nil) {
        let order = words.indices.sorted { (words[$0].lowercased(), -counts[$0]) < (words[$1].lowercased(), -counts[$1]) }
        var text = ""
        for i in order { text += "\(words[i])\t\(Int(counts[i]))\n" }
        self.init(wordsData: Data(text.utf8), bigramData: bigramText?.data(using: .utf8))
    }

    init(wordsData: Data, bigramData: Data?) {
        // ---- pass 1: words, counts, lowercase bytes, letter codes (all in file order) ----
        var fileWords: [String] = []; fileWords.reserveCapacity(140_000)
        var fileCounts: [UInt32] = []; fileCounts.reserveCapacity(140_000)
        var lb: [UInt8] = []; lb.reserveCapacity(1_300_000)
        var lbOff: [UInt32] = [0]; lbOff.reserveCapacity(140_001)
        // letter codes in file order; re-ordered by rank below
        var fileLetterCodes: [UInt8] = []; fileLetterCodes.reserveCapacity(1_300_000)
        var fileLetterOffsets: [UInt32] = [0]; fileLetterOffsets.reserveCapacity(140_001)
        var scratch: [UInt8] = []

        Self.forEachLine(in: wordsData) { fields in
            guard fields.count >= 2 else { return }
            let word = fields[0], countField = fields[1]
            fileWords.append(String(decoding: word, as: UTF8.self))
            var n: UInt32 = 0
            for b in countField where b >= 0x30 && b <= 0x39 { n = n &* 10 &+ UInt32(b - 0x30) }
            fileCounts.append(max(1, n))

            if !KeyAlphabet.appendLowercased(word, to: &lb) {
                lb.append(contentsOf: String(decoding: word, as: UTF8.self).lowercased().utf8)
            }
            lbOff.append(UInt32(lb.count))

            scratch.removeAll(keepingCapacity: true)
            var i = 0, unsupported = false
            while i < word.count {
                if let c = KeyAlphabet.code(utf8: word, at: &i, unsupported: &unsupported) { scratch.append(c) }
            }
            if unsupported { scratch = KeyAlphabet.codes(String(decoding: word, as: UTF8.self)) }
            fileLetterCodes.append(contentsOf: scratch)
            fileLetterOffsets.append(UInt32(fileLetterCodes.count))
        }
        let n = fileWords.count
        lowerBytes = lb; lowerOffsets = lbOff

        // ---- ranks: ids are frequency ranks; `fileToID` maps file order (lowercase-sorted) to ids ----
        let byCount = (0..<n).sorted { fileCounts[$0] > fileCounts[$1] }
        var fileToID = [Int32](repeating: 0, count: n)
        for (rank, fileIndex) in byCount.enumerated() { fileToID[fileIndex] = Int32(rank) }
        sortedByLower = fileToID

        var words: [String] = []; words.reserveCapacity(n)
        var total: Double = 0
        for f in byCount { words.append(fileWords[f]); total += Double(fileCounts[f]) }
        self.words = words
        var lp = [Float](); lp.reserveCapacity(n)
        for f in byCount { lp.append(Float(log(Double(fileCounts[f]) / total))) }
        logProb = lp
        minLogProb = lp.last ?? -20
        fileWords.removeAll()

        // ---- letter & swipe codes in id order, buckets ----
        var lc: [UInt8] = []; lc.reserveCapacity(fileLetterCodes.count)
        var lcOff: [UInt32] = [0]; lcOff.reserveCapacity(n + 1)
        var sw: [UInt8] = []; sw.reserveCapacity(fileLetterCodes.count)
        var swOff: [UInt32] = [0]; swOff.reserveCapacity(n + 1)
        let k = KeyAlphabet.count
        var bucketCounts = [Int32](repeating: 0, count: k * k + 1)
        var firstLast = [Int32](repeating: -1, count: n)
        for f in byCount {
            let range = Int(fileLetterOffsets[f])..<Int(fileLetterOffsets[f + 1])
            var last: UInt8 = 255
            let swStart = sw.count
            for j in range {
                let c = fileLetterCodes[j]
                lc.append(c)
                if c != last { sw.append(c); last = c }
            }
            lcOff.append(UInt32(lc.count)); swOff.append(UInt32(sw.count))
            if sw.count > swStart {
                let b = Int32(Int(sw[swStart]) * k + Int(sw[sw.count - 1]))
                firstLast[lcOff.count - 2] = b
                bucketCounts[Int(b) + 1] += 1
            }
        }
        letterCodes = lc; letterOffsets = lcOff
        swipeCodes = sw; swipeOffsets = swOff
        fileLetterCodes.removeAll()

        for b in 1...(k * k) { bucketCounts[b] += bucketCounts[b - 1] }   // prefix sums = offsets
        var bIDs = [Int32](repeating: 0, count: Int(bucketCounts[k * k]))
        var fill = bucketCounts
        for id in 0..<n where firstLast[id] >= 0 {
            let b = Int(firstLast[id])
            bIDs[Int(fill[b])] = Int32(id)
            fill[b] += 1
        }
        bucketIDs = bIDs; bucketOffsets = bucketCounts

        // ---- bigrams (needs the spelling index, so after all stored properties) ----
        if let bigramData { loadBigrams(bigramData) }
    }

    private func loadBigrams(_ data: Data) {
        let n = words.count
        var offsets = [Int32](repeating: 0, count: n + 1)
        var next: [Int32] = []; next.reserveCapacity(70_000)
        var counts: [Float] = []; counts.reserveCapacity(70_000)
        var currentFirst: Int32 = -1
        var runStart = 0
        var key: [UInt8] = []

        func flush() {
            guard currentFirst >= 0, next.count > runStart else { return }
            var sum: Float = 0
            for i in runStart..<next.count { sum += counts[i] }
            for i in runStart..<next.count { counts[i] = log(counts[i] / (sum * 1.5)) }  // leave mass for unseen
            offsets[Int(currentFirst) + 1] = Int32(next.count)
            runStart = next.count
        }
        Self.forEachLine(in: data) { fields in
            guard fields.count == 3, let a = id(exactUTF8: fields[0], scratch: &key), let b = id(exactUTF8: fields[1], scratch: &key) else { return }
            var c: Float = 0
            for byte in fields[2] where byte >= 0x30 && byte <= 0x39 { c = c * 10 + Float(byte - 0x30) }
            if a != currentFirst {
                flush()
                currentFirst = a
            }
            next.append(b); counts.append(c)
        }
        flush()
        // Turn the sparse per-word end markers into proper offsets.
        var last: Int32 = 0
        for i in 1...n {
            if offsets[i] == 0 { offsets[i] = last } else { last = offsets[i] }
        }
        // Words without successors must point at the previous end (offsets are monotone).
        for i in 1...n where offsets[i] < offsets[i - 1] { offsets[i] = offsets[i - 1] }
        bigramOffsets = offsets
        bigramNext = next
        bigramLogProb = counts
    }

    /// Splits UTF-8 data into tab-separated fields per line, handing out byte slices (no Strings).
    static func forEachLine(in data: Data, _ body: ([UnsafeBufferPointer<UInt8>]) -> Void) {
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            let count = raw.count
            var fields: [UnsafeBufferPointer<UInt8>] = []
            fields.reserveCapacity(3)
            var i = 0
            var fieldStart = 0
            while i <= count {
                let byte: UInt8 = i < count ? base[i] : 10
                if byte == 9 || byte == 10 {
                    var end = i
                    if end > fieldStart, base[end - 1] == 13 { end -= 1 }     // tolerate CRLF
                    if end > fieldStart {
                        fields.append(UnsafeBufferPointer(start: base + fieldStart, count: end - fieldStart))
                    }
                    fieldStart = i + 1
                    if byte == 10 {
                        if !fields.isEmpty { body(fields) }
                        fields.removeAll(keepingCapacity: true)
                    }
                }
                i += 1
            }
        }
    }

    // MARK: Accessors

    @inlinable public func word(_ id: Int32) -> String { words[Int(id)] }

    func swipeCodeRange(_ id: Int32) -> Range<Int> {
        Int(swipeOffsets[Int(id)])..<Int(swipeOffsets[Int(id) + 1])
    }

    func letterCodeRange(_ id: Int32) -> Range<Int> {
        Int(letterOffsets[Int(id)])..<Int(letterOffsets[Int(id) + 1])
    }

    func letterCount(_ id: Int32) -> Int { letterCodeRange(id).count }

    /// Ids in the (first, last) swipe bucket, most frequent first.
    func bucket(first: UInt8, last: UInt8) -> ArraySlice<Int32> {
        let b = Int(first) * KeyAlphabet.count + Int(last)
        return bucketIDs[Int(bucketOffsets[b])..<Int(bucketOffsets[b + 1])]
    }

    // MARK: Spelling lookups (binary search over lowercase UTF-8)

    @inline(__always)
    private func compare(entry i: Int, with key: UnsafeBufferPointer<UInt8>) -> Int {
        let start = Int(lowerOffsets[i]), end = Int(lowerOffsets[i + 1])
        let len = end - start
        let m = min(len, key.count)
        var j = 0
        while j < m {
            let a = lowerBytes[start + j], b = key[j]
            if a != b { return a < b ? -1 : 1 }
            j += 1
        }
        return len == key.count ? 0 : (len < key.count ? -1 : 1)
    }

    @inline(__always)
    private func hasPrefix(entry i: Int, _ key: UnsafeBufferPointer<UInt8>) -> Bool {
        let start = Int(lowerOffsets[i]), end = Int(lowerOffsets[i + 1])
        guard end - start >= key.count else { return false }
        var j = 0
        while j < key.count {
            if lowerBytes[start + j] != key[j] { return false }
            j += 1
        }
        return true
    }

    /// First index whose entry is >= key.
    private func lowerBound(_ key: UnsafeBufferPointer<UInt8>) -> Int {
        var lo = 0, hi = sortedByLower.count
        while lo < hi {
            let mid = (lo + hi) >> 1
            if compare(entry: mid, with: key) < 0 { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    /// Range in the sorted table whose lowercase spelling equals `key` (already lowercase UTF-8).
    private func run(ofLowercase key: UnsafeBufferPointer<UInt8>) -> Range<Int> {
        let lo = lowerBound(key)
        var hi = lo
        while hi < sortedByLower.count, compare(entry: hi, with: key) == 0 { hi += 1 }
        return lo..<hi
    }

    private func withLowercaseKey<R>(_ word: String, _ body: (UnsafeBufferPointer<UInt8>) -> R) -> R {
        var key = Array(word.lowercased().utf8)
        return key.withUnsafeMutableBufferPointer { body(UnsafeBufferPointer($0)) }
    }

    /// Exact-spelling lookup on raw bytes (loader path; `scratch` avoids reallocations).
    private func id(exactUTF8 bytes: UnsafeBufferPointer<UInt8>, scratch: inout [UInt8]) -> Int32? {
        scratch.removeAll(keepingCapacity: true)
        if !KeyAlphabet.appendLowercased(bytes, to: &scratch) {
            scratch.append(contentsOf: String(decoding: bytes, as: UTF8.self).lowercased().utf8)
        }
        return scratch.withUnsafeBufferPointer { key -> Int32? in
            for i in run(ofLowercase: key) {
                let id = sortedByLower[i]
                if words[Int(id)].utf8.elementsEqual(bytes) { return id }
            }
            return nil
        }
    }

    public func id(exact word: String) -> Int32? {
        withLowercaseKey(word) { key in
            for i in run(ofLowercase: key) {
                let id = sortedByLower[i]
                if words[Int(id)] == word { return id }
            }
            return nil
        }
    }

    /// Most frequent id whose lowercase spelling matches.
    public func id(caseInsensitive word: String) -> Int32? {
        withLowercaseKey(word) { key in run(ofLowercase: key).map { sortedByLower[$0] }.min() }
    }

    public func contains(_ word: String) -> Bool { id(exact: word) != nil }
    public func containsIgnoringCase(_ word: String) -> Bool { withLowercaseKey(word) { !run(ofLowercase: $0).isEmpty } }

    /// Casings that exist for this spelling, most frequent first (e.g. ["sie", "Sie"]).
    public func casings(of word: String) -> [String] {
        withLowercaseKey(word) { key in run(ofLowercase: key).map { sortedByLower[$0] }.sorted().map { words[Int($0)] } }
    }

    public func logProbability(of word: String) -> Float {
        if let id = id(exact: word) { return logProb[Int(id)] }
        return minLogProb - 2
    }

    /// True when the lowercase table is in strict byte order (what the binary search assumes).
    func isSortedForBinarySearch() -> Bool {
        guard sortedByLower.count > 1 else { return true }
        for i in 1..<sortedByLower.count {
            let start = Int(lowerOffsets[i]), end = Int(lowerOffsets[i + 1])
            let ok = lowerBytes[start..<end].withUnsafeBufferPointer { compare(entry: i - 1, with: $0) <= 0 }
            if !ok { return false }
        }
        return true
    }

    // MARK: Bigrams

    /// log P(next | previous) if the bigram is known.
    public func bigramLogProb(previous: Int32, next: Int32) -> Float? {
        guard !bigramOffsets.isEmpty else { return nil }
        let lo = Int(bigramOffsets[Int(previous)]), hi = Int(bigramOffsets[Int(previous) + 1])
        var i = lo
        while i < hi {
            if bigramNext[i] == next { return bigramLogProb[i] }
            i += 1
        }
        return nil
    }

    public func successors(of previous: String) -> [(word: String, logProb: Float)] {
        guard !bigramOffsets.isEmpty, let pid = id(exact: previous) ?? id(caseInsensitive: previous) else { return [] }
        let lo = Int(bigramOffsets[Int(pid)]), hi = Int(bigramOffsets[Int(pid) + 1])
        return (lo..<hi).map { (words[Int(bigramNext[$0])], bigramLogProb[$0]) }
    }

    /// Ids of words starting with `prefix` (case-insensitive), most frequent first, at most `limit`.
    public func completions(prefix: String, limit: Int) -> [Int32] {
        guard !prefix.isEmpty else { return [] }
        var candidates: [Int32] = []
        withLowercaseKey(prefix) { key in
            var i = lowerBound(key)
            while i < sortedByLower.count, hasPrefix(entry: i, key) {
                candidates.append(sortedByLower[i])
                i += 1
                if candidates.count > 20_000 { break }
            }
        }
        candidates.sort()
        return Array(candidates.prefix(limit))
    }
}

public enum LexiconError: Error {
    case missingResource(String)
}
