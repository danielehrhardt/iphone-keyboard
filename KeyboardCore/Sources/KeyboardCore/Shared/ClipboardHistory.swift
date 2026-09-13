import Foundation

/// How long copied items stay in the clipboard history.
public enum ClipboardRetention: String, CaseIterable, Sendable, Identifiable {
    case hour, day, week, month, forever
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .hour: return "1 Stunde"
        case .day: return "1 Tag"
        case .week: return "1 Woche"
        case .month: return "30 Tage"
        case .forever: return "Unbegrenzt"
        }
    }

    /// Seconds an item is kept, or nil for no time limit.
    public var duration: TimeInterval? {
        switch self {
        case .hour: return 3_600
        case .day: return 86_400
        case .week: return 7 * 86_400
        case .month: return 30 * 86_400
        case .forever: return nil
        }
    }
}

/// One entry of the clipboard history: a piece of text or an image.
public struct ClipboardItem: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case text, image }

    public let id: UUID
    public let kind: Kind
    /// The copied text (`kind == .text`).
    public let text: String?
    /// File names inside the history's image directory (`kind == .image`): the stored copy of
    /// the image and a small preview of it.
    public let imageFile: String?
    public let thumbnailFile: String?
    /// Pixel size of the stored image.
    public let imageWidth: Int?
    public let imageHeight: Int?
    /// When the item was (last) copied; the same content copied again moves to the top.
    public var createdAt: Date
    /// Identifies the content so a repeated copy does not add a duplicate.
    public let contentHash: String

    public init(id: UUID = UUID(), kind: Kind, text: String? = nil, imageFile: String? = nil, thumbnailFile: String? = nil,
                imageWidth: Int? = nil, imageHeight: Int? = nil, createdAt: Date, contentHash: String) {
        self.id = id
        self.kind = kind
        self.text = text
        self.imageFile = imageFile
        self.thumbnailFile = thumbnailFile
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.createdAt = createdAt
        self.contentHash = contentHash
    }

    /// One-line preview for lists: the text with runs of whitespace collapsed, or a label for images.
    public var preview: String {
        switch kind {
        case .text:
            let collapsed = (text ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return collapsed.isEmpty ? "(leer)" : collapsed
        case .image:
            if let w = imageWidth, let h = imageHeight { return "Bild · \(w) × \(h)" }
            return "Bild"
        }
    }
}

/// Copied text and images, newest first, persisted as JSON plus image files in the shared
/// app-group container so the keyboard extension and the app see the same history. Items
/// older than the retention period are dropped on load and on every `prune`.
///
/// Thread-safe in the simple way `UserLexicon` is: every access takes one lock, writes go to
/// disk right away (the history changes rarely, and the extension may be killed any time).
public final class ClipboardHistory: @unchecked Sendable {

    private struct Store: Codable {
        var items: [ClipboardItem] = []
    }

    /// Upper bound on entries; the oldest go first.
    public var maxItems = 100
    /// Images cost disk space and memory when shown; only this many are kept.
    public var maxImageItems = 20
    /// Text longer than this is cut when captured.
    public static let maxTextLength = 20_000

    private let directory: URL?
    private var store = Store()
    private let lock = NSLock()
    private var loadedModificationDate: Date?

    /// `directory` holds `index.json` and an `images` folder; nil keeps the history in memory only.
    public init(directory: URL?) {
        self.directory = directory
        if let directory {
            try? FileManager.default.createDirectory(at: directory.appendingPathComponent("images"), withIntermediateDirectories: true)
        }
        load()
    }

    /// The history shared between the app and the keyboard extension.
    public static func shared(appGroup: String) -> ClipboardHistory {
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        return ClipboardHistory(directory: container?.appendingPathComponent("clipboard", isDirectory: true))
    }

    private var indexURL: URL? { directory?.appendingPathComponent("index.json") }
    private var imagesURL: URL? { directory?.appendingPathComponent("images", isDirectory: true) }

    // MARK: Queries

    /// Every item, newest first.
    public var items: [ClipboardItem] {
        lock.lock(); defer { lock.unlock() }
        return store.items
    }

    public var isEmpty: Bool {
        lock.lock(); defer { lock.unlock() }
        return store.items.isEmpty
    }

    public func item(id: UUID) -> ClipboardItem? {
        lock.lock(); defer { lock.unlock() }
        return store.items.first { $0.id == id }
    }

    /// The stored image bytes of an image item.
    public func imageData(for item: ClipboardItem) -> Data? {
        guard let imagesURL, let file = item.imageFile else { return nil }
        return try? Data(contentsOf: imagesURL.appendingPathComponent(file))
    }

    /// The preview bytes of an image item (falls back to the full image).
    public func thumbnailData(for item: ClipboardItem) -> Data? {
        guard let imagesURL, let file = item.thumbnailFile ?? item.imageFile else { return nil }
        return try? Data(contentsOf: imagesURL.appendingPathComponent(file))
    }

    /// Whether `text` would be stored as a new item (empty and whitespace-only text is ignored).
    public static func isStorable(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Changes

    /// Adds copied text at the top. The same text copied again just moves to the top with a fresh
    /// date. Returns the item, or nil when the text is blank.
    @discardableResult
    public func addText(_ text: String, at date: Date = Date()) -> ClipboardItem? {
        guard Self.isStorable(text) else { return nil }
        let stored = text.count > Self.maxTextLength ? String(text.prefix(Self.maxTextLength)) : text
        let hash = Self.hash(of: Data(stored.utf8), prefix: "t")
        lock.lock()
        if let i = store.items.firstIndex(where: { $0.contentHash == hash }) {
            var existing = store.items.remove(at: i)
            existing.createdAt = date
            store.items.insert(existing, at: 0)
            let result = existing
            lock.unlock()
            save()
            return result
        }
        let item = ClipboardItem(kind: .text, text: stored, createdAt: date, contentHash: hash)
        store.items.insert(item, at: 0)
        trimLocked()
        lock.unlock()
        save()
        return item
    }

    /// Adds a copied image: `data` is the (already downscaled) image to hand back on reuse,
    /// `thumbnail` a small preview of it, both in the format named by `fileExtension`
    /// (`"jpg"`/`"png"`). `hash` identifies the source image so a repeated copy is recognised.
    /// Returns the item, or nil when the files could not be written.
    @discardableResult
    public func addImage(data: Data, thumbnail: Data, fileExtension: String, width: Int, height: Int,
                         hash sourceHash: String, at date: Date = Date()) -> ClipboardItem? {
        let hash = "i" + sourceHash
        lock.lock()
        if let i = store.items.firstIndex(where: { $0.contentHash == hash }) {
            var existing = store.items.remove(at: i)
            existing.createdAt = date
            store.items.insert(existing, at: 0)
            let result = existing
            lock.unlock()
            save()
            return result
        }
        let id = UUID()
        let imageFile = "\(id.uuidString).\(fileExtension)"
        let thumbFile = "\(id.uuidString)-thumb.\(fileExtension)"
        if let imagesURL {
            do {
                try data.write(to: imagesURL.appendingPathComponent(imageFile), options: .atomic)
                try thumbnail.write(to: imagesURL.appendingPathComponent(thumbFile), options: .atomic)
            } catch {
                lock.unlock()
                return nil
            }
        }
        let item = ClipboardItem(id: id, kind: .image, imageFile: imageFile, thumbnailFile: thumbFile,
                                 imageWidth: width, imageHeight: height, createdAt: date, contentHash: hash)
        store.items.insert(item, at: 0)
        trimLocked()
        lock.unlock()
        save()
        return item
    }

    public func remove(id: UUID) {
        lock.lock()
        let removed = store.items.filter { $0.id == id }
        store.items.removeAll { $0.id == id }
        removed.forEach(deleteFiles)
        lock.unlock()
        save()
    }

    public func removeAll() {
        lock.lock()
        let removed = store.items
        store.items = []
        removed.forEach(deleteFiles)
        lock.unlock()
        save()
    }

    /// Drops items older than the retention period. Returns how many went.
    @discardableResult
    public func prune(retention: ClipboardRetention, now: Date = Date()) -> Int {
        guard let duration = retention.duration else { return 0 }
        let cutoff = now.addingTimeInterval(-duration)
        lock.lock()
        let expired = store.items.filter { $0.createdAt < cutoff }
        guard !expired.isEmpty else { lock.unlock(); return 0 }
        store.items.removeAll { $0.createdAt < cutoff }
        expired.forEach(deleteFiles)
        lock.unlock()
        save()
        return expired.count
    }

    /// Caller holds the lock. Enforces `maxItems` and `maxImageItems`, oldest first.
    private func trimLocked() {
        var images = 0
        var kept: [ClipboardItem] = []
        var dropped: [ClipboardItem] = []
        for item in store.items {
            if item.kind == .image {
                images += 1
                if images > maxImageItems { dropped.append(item); continue }
            }
            if kept.count >= maxItems { dropped.append(item); continue }
            kept.append(item)
        }
        store.items = kept
        dropped.forEach(deleteFiles)
    }

    private func deleteFiles(of item: ClipboardItem) {
        guard let imagesURL else { return }
        for file in [item.imageFile, item.thumbnailFile].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: imagesURL.appendingPathComponent(file))
        }
    }

    // MARK: Hashing

    /// A short, stable content hash (FNV-1a 64 bit) – collisions only matter for de-duplication.
    public static func hash(of data: Data, prefix: String = "") -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for byte in data {
            h ^= UInt64(byte)
            h = h &* 0x100000001b3
        }
        return prefix + String(h, radix: 16)
    }

    // MARK: Persistence

    private func load() {
        guard let indexURL, let data = try? Data(contentsOf: indexURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        if let s = try? decoder.decode(Store.self, from: data) {
            store = s
            loadedModificationDate = Self.modificationDate(of: indexURL)
        }
    }

    private static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// Picks up items the other process (app ↔ keyboard) added or removed meanwhile.
    public func reloadIfChanged() {
        guard let indexURL else { return }
        let current = Self.modificationDate(of: indexURL)
        guard current != loadedModificationDate else { return }
        lock.lock()
        load()
        lock.unlock()
    }

    private func save() {
        guard let indexURL else { return }
        lock.lock()
        let snapshot = store
        lock.unlock()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: indexURL, options: .atomic)
            lock.lock()
            loadedModificationDate = Self.modificationDate(of: indexURL)
            lock.unlock()
        }
    }
}
