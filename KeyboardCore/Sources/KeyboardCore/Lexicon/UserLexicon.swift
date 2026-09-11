import Foundation

/// Words and word pairs learned from the user, persisted as JSON in the shared app-group container.
/// Thread-safe for the simple read-mostly access pattern of a keyboard extension.
public final class UserLexicon: @unchecked Sendable {

    public struct Entry: Codable, Hashable, Sendable {
        public var word: String
        public var count: Int
        public var lastUsed: Date
    }

    struct SwipeEntry {
        let word: String
        let codes: [UInt8]          // swipe codes (duplicates collapsed)
        let letterCodes: [UInt8]    // one code per letter

        init(word: String) {
            self.word = word
            codes = KeyAlphabet.swipeCodes(word)
            letterCodes = KeyAlphabet.codes(word)
        }
    }

    private struct Store: Codable {
        var words: [String: Entry] = [:]
        var bigrams: [String: [String: Int]] = [:]
        var blocked: Set<String> = []       // words the user removed / autocorrections they rejected
    }

    private var store = Store()
    private let lock = NSLock()
    private let fileURL: URL?
    private var swipeCache: [SwipeEntry]?
    private var dirty = false
    private var loadedModificationDate: Date?

    /// Learn a word after it was seen this many times (typos usually aren't repeated).
    public var learnThreshold = 2
    public var maxWords = 4000

    public init(fileURL: URL?) {
        self.fileURL = fileURL
        load()
    }

    public static func shared(appGroup: String) -> UserLexicon {
        let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        return UserLexicon(fileURL: dir?.appendingPathComponent("user-lexicon.json"))
    }

    // MARK: Queries

    public var allWords: [Entry] {
        lock.lock(); defer { lock.unlock() }
        return store.words.values.sorted { $0.count == $1.count ? $0.lastUsed > $1.lastUsed : $0.count > $1.count }
    }

    /// Words that reached the learn threshold.
    public func isLearned(_ word: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return (store.words[word]?.count ?? 0) >= learnThreshold
    }

    public func isBlocked(_ word: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return store.blocked.contains(word)
    }

    /// Log-boost for a learned word; nil if unknown. Frequent personal words approach common-word probability.
    public func unigramLogBoost(_ word: String) -> Float? {
        lock.lock(); defer { lock.unlock() }
        guard let e = store.words[word], e.count >= learnThreshold else { return nil }
        return Float(-13 + min(6, log(Double(e.count))))
    }

    public func bigramLogBoost(previous: String, next: String) -> Float? {
        lock.lock(); defer { lock.unlock() }
        guard let list = store.bigrams[previous], let c = list[next] else { return nil }
        return Float(-8 + min(6, log(Double(c) + 1)))
    }

    /// Personal next-word suggestions after `previous`, most used first.
    public func successors(of previous: String) -> [(word: String, count: Int)] {
        lock.lock(); defer { lock.unlock() }
        guard let list = store.bigrams[previous] else { return [] }
        return list.sorted { $0.value > $1.value }.map { (word: $0.key, count: $0.value) }
    }

    var swipeEntries: [SwipeEntry] {
        lock.lock(); defer { lock.unlock() }
        if let c = swipeCache { return c }
        let entries = store.words.values
            .filter { $0.count >= learnThreshold && $0.word.count >= 2 }
            .map { SwipeEntry(word: $0.word) }
            .filter { !$0.codes.isEmpty }
        swipeCache = entries
        return entries
    }

    /// Learned words starting with `prefix` (case-insensitive), most used first.
    public func completions(prefix: String, limit: Int) -> [String] {
        lock.lock(); defer { lock.unlock() }
        let p = prefix.lowercased()
        return store.words.values
            .filter { $0.count >= learnThreshold && $0.word.lowercased().hasPrefix(p) && $0.word.count > p.count }
            .sorted { $0.count > $1.count }
            .prefix(limit)
            .map(\.word)
    }

    // MARK: Learning

    /// Records that the user committed `word` after `previous` (nil at sentence start).
    public func learn(word: String, after previous: String?) {
        guard Self.isLearnable(word) else { return }
        lock.lock()
        if store.blocked.contains(word) { lock.unlock(); return }
        var e = store.words[word] ?? Entry(word: word, count: 0, lastUsed: Date())
        e.count += 1
        e.lastUsed = Date()
        store.words[word] = e
        if let previous, Self.isLearnable(previous) {
            store.bigrams[previous, default: [:]][word, default: 0] += 1
        }
        if store.words.count > maxWords { prune(); swipeCache = nil }
        // Keep the swipe cache incremental: a word joins it the moment it reaches the threshold.
        if e.count == learnThreshold, word.count >= 2, swipeCache != nil {
            let entry = SwipeEntry(word: word)
            if !entry.codes.isEmpty { swipeCache?.append(entry) }
        }
        dirty = true
        lock.unlock()
        scheduleSave()
    }

    /// Adds a word immediately (e.g. user tapped "add to dictionary").
    public func add(word: String) {
        lock.lock()
        store.blocked.remove(word)
        store.words[word] = Entry(word: word, count: max(learnThreshold, store.words[word]?.count ?? 0), lastUsed: Date())
        swipeCache = nil; dirty = true
        lock.unlock()
        scheduleSave()
    }

    public func remove(word: String) {
        lock.lock()
        store.words[word] = nil
        store.blocked.insert(word)
        for k in store.bigrams.keys { store.bigrams[k]?[word] = nil }
        store.bigrams[word] = nil
        swipeCache = nil; dirty = true
        lock.unlock()
        scheduleSave()
    }

    /// The user reverted an autocorrection from `typed` to `corrected`: remember the typed form.
    public func rejectCorrection(typed: String) {
        add(word: typed)
    }

    public func removeAll() {
        lock.lock()
        store = Store()
        swipeCache = nil; dirty = true
        lock.unlock()
        scheduleSave()
    }

    static func isLearnable(_ word: String) -> Bool {
        guard word.count >= 2, word.count <= 40 else { return false }
        guard word.allSatisfy({ $0.isLetter || $0 == "-" || $0 == "'" }) else { return false }
        // Don't learn things that look like secrets/identifiers: long mixed-case runs.
        let uppers = word.filter(\.isUppercase).count
        if word.count > 8 && uppers > 2 && uppers < word.count { return false }
        return true
    }

    private func prune() {
        let keep = store.words.values.sorted { $0.lastUsed > $1.lastUsed }.prefix(maxWords * 3 / 4)
        store.words = Dictionary(uniqueKeysWithValues: keep.map { ($0.word, $0) })
    }

    // MARK: Persistence

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        if let s = try? decoder.decode(Store.self, from: data) {
            store = s
            loadedModificationDate = Self.modificationDate(of: fileURL)
        }
    }

    private static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// Picks up changes another process (host app ↔ keyboard) wrote to the file. Pending local
    /// changes are flushed first so nothing is lost.
    public func reloadIfChanged() {
        guard let fileURL else { return }
        lock.lock()
        let isDirty = dirty
        lock.unlock()
        if isDirty { saveNow() }
        let current = Self.modificationDate(of: fileURL)
        guard current != loadedModificationDate else { return }
        lock.lock()
        load()
        swipeCache = nil
        lock.unlock()
    }

    private var saveScheduled = false
    private func scheduleSave() {
        lock.lock()
        if saveScheduled { lock.unlock(); return }
        saveScheduled = true
        lock.unlock()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.saveNow()
        }
    }

    public func saveNow() {
        guard let fileURL else { return }
        lock.lock()
        saveScheduled = false
        guard dirty else { lock.unlock(); return }
        let snapshot = store
        dirty = false
        lock.unlock()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: fileURL, options: .atomic)
            lock.lock()
            loadedModificationDate = Self.modificationDate(of: fileURL)
            lock.unlock()
        }
    }
}
