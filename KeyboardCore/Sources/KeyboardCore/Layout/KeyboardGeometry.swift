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
            var x = metrics.sideInset + (usableWidth - rowWidth) / 2 + row.leadingInset * (unit + horizontalGap)

            for (i, key) in row.keys.enumerated() {
                let w = key.action == .space ? spaceWidth : fixedWidths[i]
                let frame = CGRect(x: x, y: y, width: w, height: rh)
                let isFirst = i == 0, isLast = i == row.keys.count - 1
                let hit = CGRect(
                    x: isFirst ? 0 : frame.minX - horizontalGap / 2,
                    y: frame.minY - verticalGap / 2,
                    width: (isFirst ? frame.maxX : frame.width + horizontalGap / 2) + (isLast ? size.width - frame.maxX : horizontalGap / 2),
                    height: rh + verticalGap
                ).integral
                frames.append(KeyFrame(key: key, frame: frame, hitFrame: hit))
                x += w + horizontalGap
            }
        }
        keyFrames = frames
    }

    public func keyFrame(at point: CGPoint) -> KeyFrame? {
        if let exact = keyFrames.first(where: { $0.hitFrame.contains(point) }) { return exact }
        // Outside every hit box (e.g. beyond the last row): pick the nearest key on the nearest row.
        return keyFrames.min { distanceSquared($0.hitFrame, point) < distanceSquared($1.hitFrame, point) }
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
