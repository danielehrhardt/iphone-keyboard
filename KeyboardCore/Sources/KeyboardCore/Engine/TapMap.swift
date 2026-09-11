import Foundation
import CoreGraphics

/// Where this user's fingers actually land – the keyboard's "tap map".
///
/// Everybody taps a little off centre, and systematically so: thumbs reach the far side of the
/// keyboard low and inward, the index finger lands high, and so on. For every letter key the map
/// keeps the running mean of the touch offset from the key's geometric centre, learned from words
/// the user committed (an autocorrection tells us which key was *meant*), and feeds it back into
/// the hit test: each key's effective centre drifts to where this user taps it, so the decision
/// boundaries between keys follow the fingers instead of the printed caps.
///
/// Offsets are stored in units of the key pitch (key plus gap), so one map serves every key-size
/// setting; a separate layer is kept per keyboard width (portrait, landscape, iPad …) because
/// the hand posture differs. Persisted as JSON in the app group like the personal dictionary.
public final class TapMap: @unchecked Sendable {

    // MARK: Model

    /// One confirmed tap: the touch landed `dx`/`dy` key pitches away from the centre of the key
    /// the user meant (`code`).
    public struct Sample: Hashable, Sendable {
        public let code: UInt8
        public let dx: Float
        public let dy: Float

        public init(code: UInt8, dx: Float, dy: Float) {
            self.code = code
            self.dx = dx
            self.dy = dy
        }
    }

    /// Running mean of the offsets seen for one key, with the (capped) number of taps behind it.
    public struct KeyStat: Codable, Hashable, Sendable {
        public var dx: Float = 0
        public var dy: Float = 0
        public var count: Float = 0

        mutating func add(_ s: Sample) {
            // Plain running mean until `maxCount`, then an exponential moving average with the
            // same weight, so the map keeps following slow changes in how the user holds the phone.
            count = min(count + 1, Tuning.maxCount)
            dx += (s.dx - dx) / count
            dy += (s.dy - dy) / count
        }
    }

    /// The map for one keyboard width, indexed by `KeyAlphabet` code.
    public struct Layer: Codable, Hashable, Sendable {
        public var stats: [KeyStat]
        /// Confirmed taps fed into this layer since it was created (not capped).
        public var sampleCount: Int

        public init() {
            stats = Array(repeating: KeyStat(), count: KeyAlphabet.count)
            sampleCount = 0
        }

        /// Keys with enough taps behind them for their shift to be trusted.
        public var learnedKeyCount: Int {
            stats.filter { $0.count >= Tuning.pseudoCount }.count
        }

        /// The per-key shifts the hit test uses, blended with the built-in default and clamped.
        public var offsets: Offsets {
            var dx = [CGFloat](repeating: 0, count: KeyAlphabet.count)
            var dy = [CGFloat](repeating: 0, count: KeyAlphabet.count)
            for (i, s) in stats.enumerated() {
                // Bayesian-style blend: the default (0, `defaultDy`) counts as `pseudoCount` taps.
                let n = s.count + Tuning.pseudoCount
                let bx = (s.dx * s.count) / n
                let by = (s.dy * s.count + Tuning.defaultDy * Tuning.pseudoCount) / n
                dx[i] = CGFloat(max(-Tuning.maxShift, min(Tuning.maxShift, bx)))
                dy[i] = CGFloat(max(-Tuning.maxShift, min(Tuning.maxShift, by)))
            }
            return Offsets(dx: dx, dy: dy)
        }
    }

    /// Per-letter centre shifts in pitch units, ready for `KeyboardGeometry.keyFrame(at:prior:offsets:)`.
    public struct Offsets: Hashable, Sendable {
        public let dx: [CGFloat]
        public let dy: [CGFloat]

        public init(dx: [CGFloat], dy: [CGFloat]) {
            precondition(dx.count == KeyAlphabet.count && dy.count == KeyAlphabet.count)
            self.dx = dx
            self.dy = dy
        }

        /// What an empty map yields: every key shifted down by the default finger bias.
        public static let neutral = Layer().offsets

        /// The shift of one key in points.
        public func shift(code: UInt8, pitchX: CGFloat, pitchY: CGFloat) -> CGPoint {
            let i = Int(code)
            guard i < dx.count else { return .zero }
            return CGPoint(x: dx[i] * pitchX, y: dy[i] * pitchY)
        }
    }

    public enum Tuning {
        /// Finger pads land a little below where the user believes they tapped. Starting value
        /// for every key, in pitch units (≈ `KeyboardGeometry.HitTuning.touchOffsetY` row heights).
        public static let defaultDy: Float = 0.06
        /// Weight of the default before taps accumulate: with this many taps the learned offset
        /// counts as much as the default, so a handful of taps cannot yank a key around.
        public static let pseudoCount: Float = 8
        /// Taps per key after which the mean turns into an exponential average.
        public static let maxCount: Float = 150
        /// A key's centre never moves further than this (pitch units – a quarter key), so no key
        /// can wander off its cap or swallow a neighbour.
        public static let maxShift: Float = 0.25
        /// Taps further off the intended centre than this are slips, not bias, and are ignored.
        public static let maxSampleDeviation: Float = 0.55
    }

    // MARK: Attribution

    /// Turns the taps of a committed word into samples.
    ///
    /// `typed` is what the taps produced, `committed` what ended up in the text (identical when
    /// no correction happened). Only same-length corrections are trusted, i.e. substitutions like
    /// "hakko" → "hallo": the tap that produced the wrong letter is attributed to the letter the
    /// user meant, provided the two keys are neighbours on the layout (a correction across the
    /// keyboard is a spelling fix, not a slip). Non-letters are skipped.
    public static func samples(taps: [CGPoint], typed: String, committed: String, keyMap: KeyMap) -> [Sample] {
        let typedChars = Array(typed), committedChars = Array(committed)
        guard taps.count == typedChars.count, typedChars.count == committedChars.count else { return [] }
        var out: [Sample] = []
        out.reserveCapacity(taps.count)
        for i in taps.indices {
            guard let typedCode = KeyAlphabet.code(for: typedChars[i]),
                  let meantCode = KeyAlphabet.code(for: committedChars[i]) else { continue }
            if typedCode != meantCode, !keyMap.areAdjacent(typedCode, meantCode) { continue }
            let c = keyMap.centers[Int(meantCode)]
            let dx = Float((taps[i].x - c.x) / keyMap.pitchX), dy = Float((taps[i].y - c.y) / keyMap.pitchY)
            guard abs(dx) <= Tuning.maxSampleDeviation, abs(dy) <= Tuning.maxSampleDeviation else { continue }
            out.append(Sample(code: meantCode, dx: dx, dy: dy))
        }
        return out
    }

    // MARK: Storage

    private struct Store: Codable {
        var layers: [String: Layer] = [:]
    }

    private var store = Store()
    private let lock = NSLock()
    private let fileURL: URL?
    private var dirty = false
    private var loadedModificationDate: Date?
    /// What the last `learn` changed, so an autocorrection the user reverts can be taken back.
    private var lastBatch: (layer: String, previous: [(code: UInt8, stat: KeyStat)], count: Int)?

    public init(fileURL: URL?) {
        self.fileURL = fileURL
        load()
    }

    public static func shared(appGroup: String) -> TapMap {
        let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        return TapMap(fileURL: dir?.appendingPathComponent("tap-map.json"))
    }

    /// The process-wide instance backed by the app group (host app and extension each have one).
    public static let standard = TapMap.shared(appGroup: KeyboardSettings.appGroup)

    /// Layers are keyed by the horizontal key pitch in points, which is stable per device and
    /// orientation and unaffected by the key-size setting (that only changes the height).
    static func layerKey(for keyMap: KeyMap) -> String {
        "p\(Int(keyMap.pitchX.rounded()))"
    }

    // MARK: Queries

    public func layer(for keyMap: KeyMap) -> Layer? {
        lock.lock(); defer { lock.unlock() }
        return store.layers[Self.layerKey(for: keyMap)]
    }

    /// The shifts to hit-test with on a keyboard laid out like `keyMap`; neutral until taps arrive.
    public func offsets(for keyMap: KeyMap) -> Offsets {
        layer(for: keyMap)?.offsets ?? .neutral
    }

    /// Every learned layer with its horizontal pitch, narrow (portrait) first.
    public var layers: [(pitchX: CGFloat, layer: Layer)] {
        lock.lock(); defer { lock.unlock() }
        return store.layers.compactMap { key, layer in
            guard key.hasPrefix("p"), let p = Int(key.dropFirst()) else { return nil }
            return (pitchX: CGFloat(p), layer: layer)
        }.sorted { $0.pitchX < $1.pitchX }
    }

    public var totalSamples: Int {
        lock.lock(); defer { lock.unlock() }
        return store.layers.values.reduce(0) { $0 + $1.sampleCount }
    }

    // MARK: Learning

    /// Feeds confirmed taps into the layer for `keyMap`.
    public func learn(_ samples: [Sample], keyMap: KeyMap) {
        guard !samples.isEmpty else { return }
        let key = Self.layerKey(for: keyMap)
        lock.lock()
        var layer = store.layers[key] ?? Layer()
        var previous: [(code: UInt8, stat: KeyStat)] = []
        for s in samples where Int(s.code) < layer.stats.count {
            previous.append((s.code, layer.stats[Int(s.code)]))
            layer.stats[Int(s.code)].add(s)
        }
        layer.sampleCount += previous.count
        store.layers[key] = layer
        lastBatch = (key, previous, previous.count)
        dirty = true
        lock.unlock()
        scheduleSave()
    }

    /// Takes back the most recent `learn` (the user reverted the autocorrection it was based on).
    public func undoLastLearning() {
        lock.lock()
        guard let batch = lastBatch, var layer = store.layers[batch.layer] else { lock.unlock(); return }
        // Restore in reverse so a key that occurred twice ends up at its state before the batch.
        for (code, stat) in batch.previous.reversed() { layer.stats[Int(code)] = stat }
        layer.sampleCount = max(0, layer.sampleCount - batch.count)
        store.layers[batch.layer] = layer
        lastBatch = nil
        dirty = true
        lock.unlock()
        scheduleSave()
    }

    public func removeAll() {
        lock.lock()
        store = Store()
        lastBatch = nil
        dirty = true
        lock.unlock()
        scheduleSave()
    }

    // MARK: Persistence

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        if let s = try? JSONDecoder().decode(Store.self, from: data) {
            // Tolerate a layer written by a build with a different alphabet size.
            store.layers = s.layers.filter { $0.value.stats.count == KeyAlphabet.count }
            loadedModificationDate = Self.modificationDate(of: fileURL)
        }
    }

    private static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// Picks up changes the other process (host app ↔ keyboard) wrote, e.g. a reset in the app.
    public func reloadIfChanged() {
        guard let fileURL else { return }
        lock.lock()
        let isDirty = dirty
        lock.unlock()
        if isDirty { saveNow() }
        let current = Self.modificationDate(of: fileURL)
        guard current != loadedModificationDate else { return }
        lock.lock()
        store = Store()
        load()
        lastBatch = nil
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
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: fileURL, options: .atomic)
            lock.lock()
            loadedModificationDate = Self.modificationDate(of: fileURL)
            lock.unlock()
        }
    }
}

// MARK: - Hit test

extension KeyboardGeometry {
    /// Hit test against the learned tap map: on the letters layer every letter key is judged from
    /// its personal centre (geometric centre plus learned shift) instead of the printed one, and
    /// the next-letter `prior`, when given, tilts the decision as in `keyFrame(at:prior:)`.
    /// With neutral offsets this is that hit test; without offsets it falls back to it entirely.
    /// Function keys are never affected: a touch in their hit box is theirs, whatever the map says.
    public func keyFrame(at touch: CGPoint, prior: LetterPrior?, offsets: TapMap.Offsets?) -> KeyFrame? {
        guard let offsets, layout.layer == .letters else { return keyFrame(at: touch, prior: prior) }
        let plain = keyFrame(at: touch)
        guard plain?.key.isLetter ?? false else { return plain }
        let pitchX = unitWidth + horizontalGap, pitchY = rowHeight + verticalGap
        let sigmaX = pitchX * HitTuning.sigmaX, sigmaY = pitchY * HitTuning.sigmaY
        // Candidates reach beyond their own (shifted) hit box by the prior's allowance.
        let reachX = pitchX * HitTuning.maxReachX, reachY = pitchY * HitTuning.maxReachY

        var best: KeyFrame?
        var bestScore = -CGFloat.infinity
        for kf in keyFrames where kf.key.isLetter {
            guard let c = kf.key.character, let code = KeyAlphabet.code(for: c) else { continue }
            let shift = offsets.shift(code: code, pitchX: pitchX, pitchY: pitchY)
            guard kf.hitFrame.offsetBy(dx: shift.x, dy: shift.y).insetBy(dx: -reachX, dy: -reachY).contains(touch) else { continue }
            let dx = (touch.x - kf.center.x - shift.x) / sigmaX, dy = (touch.y - kf.center.y - shift.y) / sigmaY
            var score = -0.5 * (dx * dx + dy * dy)
            if let prior { score += HitTuning.priorWeight * CGFloat(prior.logProbability(code: code)) }
            if score > bestScore { bestScore = score; best = kf }
        }
        return best ?? plain
    }
}
