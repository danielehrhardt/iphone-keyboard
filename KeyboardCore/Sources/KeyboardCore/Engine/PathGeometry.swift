import Foundation
import CoreGraphics

/// Small vector helpers for gesture paths. Everything is Float-based for speed in hot loops.
struct FPoint: Equatable {
    var x: Float
    var y: Float
    @inline(__always) init(_ x: Float, _ y: Float) { self.x = x; self.y = y }
    @inline(__always) init(_ p: CGPoint) { x = Float(p.x); y = Float(p.y) }
    @inline(__always) static func - (a: FPoint, b: FPoint) -> FPoint { FPoint(a.x - b.x, a.y - b.y) }
    @inline(__always) static func + (a: FPoint, b: FPoint) -> FPoint { FPoint(a.x + b.x, a.y + b.y) }
    @inline(__always) static func * (a: FPoint, s: Float) -> FPoint { FPoint(a.x * s, a.y * s) }
    @inline(__always) var length: Float { (x * x + y * y).squareRoot() }
    @inline(__always) func distance(to o: FPoint) -> Float { (self - o).length }
    @inline(__always) func squaredDistance(to o: FPoint) -> Float {
        let dx = x - o.x, dy = y - o.y
        return dx * dx + dy * dy
    }
}

enum PathGeometry {

    static func length(_ pts: [FPoint]) -> Float {
        guard pts.count > 1 else { return 0 }
        var l: Float = 0
        for i in 1..<pts.count { l += pts[i].distance(to: pts[i - 1]) }
        return l
    }

    /// Resamples a polyline into `n` points equidistant along its arc length.
    /// A degenerate (single point / zero length) path yields `n` copies of the point.
    static func resample(_ pts: [FPoint], count n: Int) -> [FPoint] {
        var out: [FPoint] = []
        resample(pts, count: n, into: &out)
        return out
    }

    /// `resample(_:count:)` into a caller-owned buffer, so hot loops don't allocate.
    static func resample(_ pts: [FPoint], count n: Int, into out: inout [FPoint]) {
        out.removeAll(keepingCapacity: true)
        guard let first = pts.first else { return }
        let total = length(pts)
        guard pts.count > 1, total > 0 else {
            for _ in 0..<n { out.append(first) }
            return
        }
        let step = total / Float(n - 1)
        out.append(first)
        var acc: Float = 0
        var i = 1
        var prev = pts[0]
        while out.count < n - 1 && i < pts.count {
            let cur = pts[i]
            let seg = prev.distance(to: cur)
            if acc + seg >= step {
                let t = (step - acc) / seg
                let np = prev + (cur - prev) * t
                out.append(np)
                prev = np
                acc = 0
            } else {
                acc += seg
                prev = cur
                i += 1
            }
        }
        while out.count < n { out.append(pts[pts.count - 1]) }
    }

    /// Light exponential smoothing to tame touch jitter without rounding corners too much.
    static func smooth(_ pts: [FPoint], alpha: Float = 0.6) -> [FPoint] {
        guard pts.count > 2 else { return pts }
        var out = pts
        for i in 1..<(pts.count - 1) {
            out[i] = pts[i] * alpha + (pts[i - 1] + pts[i + 1]) * ((1 - alpha) / 2)
        }
        return out
    }

    /// Translates the centroid to the origin and scales the larger bounding-box side to 1.
    static func normalizeShape(_ pts: [FPoint]) -> [FPoint] {
        var out = pts
        normalizeShape(&out)
        return out
    }

    static func normalizeShape(_ pts: inout [FPoint]) {
        guard !pts.isEmpty else { return }
        var minX = Float.greatestFiniteMagnitude, minY = minX, maxX = -minX, maxY = -minX
        var cx: Float = 0, cy: Float = 0
        for p in pts {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
            cx += p.x; cy += p.y
        }
        cx /= Float(pts.count); cy /= Float(pts.count)
        let extent = max(maxX - minX, maxY - minY)
        let s: Float = extent > 1e-3 ? 1 / extent : 0
        for i in pts.indices { pts[i] = FPoint((pts[i].x - cx) * s, (pts[i].y - cy) * s) }
    }

    /// Mean squared point-to-point distance of two equally long sequences, each term capped at
    /// `cap` so a single stray point (a lift-off hook) can't dominate. `.infinity` once the mean
    /// is certain to exceed `abortAbove`.
    @inline(__always)
    static func alignedSquaredDistance(_ a: [FPoint], _ b: [FPoint], cap: Float, abortAbove limit: Float = .infinity) -> Float {
        let n = min(a.count, b.count)
        guard n > 0 else { return .infinity }
        var sum: Float = 0
        let bound = limit * Float(n)
        for i in 0..<n {
            sum += min(a[i].squaredDistance(to: b[i]), cap)
            if sum > bound { return .infinity }
        }
        return sum / Float(n)
    }

    /// Banded DTW over capped squared distances of two equally long sequences, normalised by the
    /// sequence length. `rows` is scratch space (resized as needed). `.infinity` when every
    /// alignment already exceeds `abortAbove` (as a mean) part-way through.
    static func dtwSquaredDistance(_ a: [FPoint], _ b: [FPoint], band: Int, cap: Float,
                                   abortAbove limit: Float = .infinity, rows: inout [Float]) -> Float {
        let n = a.count
        guard n > 0, b.count == n else { return .infinity }
        let inf = Float.infinity
        if rows.count < 2 * (n + 1) { rows = [Float](repeating: inf, count: 2 * (n + 1)) }
        let bound = limit * Float(n)
        return rows.withUnsafeMutableBufferPointer { buf -> Float in
            var prev = buf.baseAddress!, cur = buf.baseAddress! + (n + 1)
            for j in 0...n { prev[j] = inf; cur[j] = inf }
            prev[0] = 0
            for i in 1...n {
                let lo = max(1, i - band), hi = min(n, i + band)
                cur[lo - 1] = inf
                let p = a[i - 1]
                var rowMin = inf
                for j in lo...hi {
                    let d = min(p.squaredDistance(to: b[j - 1]), cap)
                    let v = d + min(prev[j], prev[j - 1], cur[j - 1])
                    cur[j] = v
                    if v < rowMin { rowMin = v }
                }
                if hi < n { cur[hi + 1] = inf }
                if rowMin > bound { return inf }
                swap(&prev, &cur)
            }
            return prev[n] / Float(n)
        }
    }
}
