import Foundation
import CoreGraphics

/// A key placed on screen.
public struct KeyFrame: Hashable, Sendable {
    public let key: Key
    /// Visible cap rectangle.
    public let frame: CGRect
    /// Larger rectangle that owns touches (gaps are split between neighbours).
    public let hitFrame: CGRect

    public var center: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }
}

/// Lays out a `KeyboardLayout` in a given size. Mirrors the proportions of the system keyboard:
/// small horizontal gaps, slightly taller vertical gaps, space bar takes the remaining width.
public struct KeyboardGeometry: Hashable, Sendable {
    public let layout: KeyboardLayout
    public let size: CGSize
    public let keyFrames: [KeyFrame]
    public let unitWidth: CGFloat
    public let rowHeight: CGFloat
    public let horizontalGap: CGFloat
    public let verticalGap: CGFloat

    public struct Metrics: Hashable, Sendable {
        public var horizontalGap: CGFloat
        public var verticalGap: CGFloat
        public var sideInset: CGFloat
        public var topInset: CGFloat
        public var bottomInset: CGFloat

        public init(horizontalGap: CGFloat = 6, verticalGap: CGFloat = 11, sideInset: CGFloat = 3, topInset: CGFloat = 8, bottomInset: CGFloat = 4) {
            self.horizontalGap = horizontalGap
            self.verticalGap = verticalGap
            self.sideInset = sideInset
            self.topInset = topInset
            self.bottomInset = bottomInset
        }

        public static let phonePortrait = Metrics()
        public static let phoneLandscape = Metrics(horizontalGap: 6, verticalGap: 7, sideInset: 3, topInset: 5, bottomInset: 3)
        public static let pad = Metrics(horizontalGap: 8, verticalGap: 10, sideInset: 6, topInset: 8, bottomInset: 6)
    }

    public init(layout: KeyboardLayout, size: CGSize, metrics: Metrics = .phonePortrait) {
        self.layout = layout
        self.size = size
        horizontalGap = metrics.horizontalGap
        verticalGap = metrics.verticalGap

        let horizontalGap = metrics.horizontalGap, verticalGap = metrics.verticalGap
        let usableWidth = size.width - metrics.sideInset * 2
        let unit = (usableWidth - horizontalGap * (layout.columns - 1)) / layout.columns
        unitWidth = unit
        let rowCount = CGFloat(layout.rows.count)
        let usableHeight = size.height - metrics.topInset - metrics.bottomInset
        let rh = (usableHeight - verticalGap * (rowCount - 1)) / rowCount
        rowHeight = rh

        var frames: [KeyFrame] = []
        for (rowIndex, row) in layout.rows.enumerated() {
            let y = metrics.topInset + CGFloat(rowIndex) * (rh + verticalGap)
            // Space bar (or any single width-1 flexible key marked "space") absorbs leftover width.
            let fixedWidths = row.keys.map { key -> CGFloat in
                key.action == .space ? 0 : key.width * unit + (key.width - 1) * horizontalGap
            }
            let fixedTotal = fixedWidths.reduce(0, +) + horizontalGap * CGFloat(row.keys.count - 1)
            let insets = (row.leadingInset + row.trailingInset) * (unit + horizontalGap)
            let hasSpace = row.keys.contains { $0.action == .space }
            let spaceWidth = hasSpace ? max(unit, usableWidth - fixedTotal - insets) : 0
            let rowWidth = fixedTotal + spaceWidth + insets
            // Rows framed by function keys fill the width, the slack widening those two keys.
            let flankExtra = row.stretchesFlankKeys && !hasSpace && row.keys.count > 2
                ? max(0, usableWidth - rowWidth) / 2 : 0
            var x = metrics.sideInset + (usableWidth - rowWidth - flankExtra * 2) / 2 + row.leadingInset * (unit + horizontalGap)

            var caps: [CGRect] = []
            for (i, key) in row.keys.enumerated() {
                let isFlank = i == 0 || i == row.keys.count - 1
                let w = key.action == .space ? spaceWidth : fixedWidths[i] + (isFlank ? flankExtra : 0)
                caps.append(CGRect(x: x, y: y, width: w, height: rh))
                x += w + horizontalGap
            }

            // Gaps are split between neighbours, so no touch inside the row falls between keys.
            for (i, key) in row.keys.enumerated() {
                let frame = caps[i]
                let isFirst = i == 0, isLast = i == row.keys.count - 1
                let left = isFirst ? 0 : (caps[i - 1].maxX + frame.minX) / 2
                let right = isLast ? size.width : (frame.maxX + caps[i + 1].minX) / 2
                let hit = CGRect(x: left, y: frame.minY - verticalGap / 2,
                                 width: right - left, height: rh + verticalGap).integral
                frames.append(KeyFrame(key: key, frame: frame, hitFrame: hit))
            }
        }
        keyFrames = frames
    }

    public func keyFrame(at point: CGPoint) -> KeyFrame? {
        if let exact = keyFrames.first(where: { $0.hitFrame.contains(point) }) { return exact }
        // Outside every hit box (e.g. beyond the last row): pick the nearest key on the nearest row.
        return keyFrames.min { distanceSquared($0.hitFrame, point) < distanceSquared($1.hitFrame, point) }
    }

    /// Tunables for the probabilistic hit test, in units of the key pitch (key + gap).
    public enum HitTuning {
        /// Assumed touch scatter around the intended key centre. With a flat prior the decision
        /// boundary between neighbours stays at the midpoint, exactly like the plain hit test.
        public static let sigmaX: CGFloat = 0.3
        public static let sigmaY: CGFloat = 0.3
        /// Tempering of the prior (1 = trust it fully). Keeps the Gaussian term meaningful: a
        /// moderately likely key wins the gap and a sliver of its neighbour, only a near-certain
        /// one reaches the cap below.
        public static let priorWeight: CGFloat = 0.75
        /// How far a likely key may reach beyond its own hit box. The winner takes the whole gap
        /// plus a good part of the neighbour's cap edge, so a slightly off tap towards a likely
        /// letter lands on it instead of feeling like it hit dead space. The neighbour always
        /// keeps the central half of its cap (see `LetterPriorTests`), well inside normal touch
        /// scatter, so a deliberate tap on an "unexpected" key is never stolen.
        public static let maxReachX: CGFloat = 0.26
        public static let maxReachY: CGFloat = 0.2
        /// Finger pads land a little below where the user believes they tapped; touches are
        /// nudged upward to compensate (fraction of the row height). Part of the feature, so
        /// disabling dynamic hit targets restores the plain hit test exactly.
        public static let touchOffsetY: CGFloat = 0.08
    }

    /// Hit test with dynamic key resizing: on the letters layer, letter keys that are likely to
    /// be typed next (`prior`) own the gaps around them and a sliver of their neighbours' edges.
    /// Without a prior, or for any non-letter key, this is the plain geometric hit test.
    public func keyFrame(at touch: CGPoint, prior: LetterPrior?) -> KeyFrame? {
        guard let prior, layout.layer == .letters else { return keyFrame(at: touch) }
        let point = CGPoint(x: touch.x, y: touch.y - rowHeight * HitTuning.touchOffsetY)
        guard let exact = keyFrame(at: point), exact.key.isLetter else { return keyFrame(at: point) }

        let pitchX = unitWidth + horizontalGap, pitchY = rowHeight + verticalGap
        let sigmaX = pitchX * HitTuning.sigmaX, sigmaY = pitchY * HitTuning.sigmaY
        let reachX = pitchX * HitTuning.maxReachX, reachY = pitchY * HitTuning.maxReachY

        func score(_ kf: KeyFrame, _ code: UInt8) -> CGFloat {
            let dx = (point.x - kf.center.x) / sigmaX, dy = (point.y - kf.center.y) / sigmaY
            return HitTuning.priorWeight * CGFloat(prior.logProbability(code: code)) - 0.5 * (dx * dx + dy * dy)
        }

        var best = exact
        var bestScore = exact.key.character.flatMap(KeyAlphabet.code(for:)).map { score(exact, $0) } ?? -.infinity
        for kf in keyFrames where kf.key.isLetter && kf.key.id != exact.key.id {
            guard let c = kf.key.character, let code = KeyAlphabet.code(for: c),
                  kf.hitFrame.insetBy(dx: -reachX, dy: -reachY).contains(point) else { continue }
            let s = score(kf, code)
            if s > bestScore { bestScore = s; best = kf }
        }
        return best
    }

    public func keyFrame(for key: Key) -> KeyFrame? {
        keyFrames.first { $0.key.id == key.id }
    }

    /// Letter key centres keyed by lowercase character, used by the swipe decoder and autocorrect.
    public var letterCenters: [Character: CGPoint] {
        var result: [Character: CGPoint] = [:]
        for kf in keyFrames where kf.key.isLetter {
            if let c = kf.key.character { result[c] = kf.center }
        }
        return result
    }

    private func distanceSquared(_ rect: CGRect, _ p: CGPoint) -> CGFloat {
        let dx = max(rect.minX - p.x, 0, p.x - rect.maxX)
        let dy = max(rect.minY - p.y, 0, p.y - rect.maxY)
        return dx * dx + dy * dy
    }
}
