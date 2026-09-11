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
}

enum PathGeometry {

    /// Removes consecutive (near-)duplicate points.
    static func dedupe(_ pts: [FPoint], epsilon: Float = 0.5) -> [FPoint] {
        var out: [FPoint] = []
        out.reserveCapacity(pts.count)
        for p in pts {
            if let last = out.last, last.distance(to: p) < epsilon { continue }
            out.append(p)
        }
        return out
    }

    static func length(_ pts: [FPoint]) -> Float {
        guard pts.count > 1 else { return 0 }
        var l: Float = 0
        for i in 1..<pts.count { l += pts[i].distance(to: pts[i - 1]) }
        return l
    }

    /// Resamples a polyline into `n` points equidistant along its arc length.
    /// A degenerate (single point / zero length) path yields `n` copies of the point.
    static func resample(_ pts: [FPoint], count n: Int) -> [FPoint] {
        guard let first = pts.first else { return [] }
        guard pts.count > 1 else { return [FPoint](repeating: first, count: n) }
        let total = length(pts)
        guard total > 0 else { return [FPoint](repeating: first, count: n) }
        let step = total / Float(n - 1)
        var out: [FPoint] = [first]
        out.reserveCapacity(n)
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
        return out
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
        guard !pts.isEmpty else { return pts }
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
        return pts.map { FPoint(($0.x - cx) * s, ($0.y - cy) * s) }
    }

    /// Mean point-to-point distance of two equally long sequences.
    @inline(__always)
    static func alignedDistance(_ a: [FPoint], _ b: [FPoint], abortAbove limit: Float = .infinity) -> Float {
        let n = min(a.count, b.count)
        guard n > 0 else { return .infinity }
        var sum: Float = 0
        let cap = limit * Float(n)
        for i in 0..<n {
            sum += a[i].distance(to: b[i])
            if sum > cap { return .infinity }
        }
        return sum / Float(n)
    }

    /// Banded dynamic time warping (Sakoe–Chiba) returning the mean matched distance.
    static func dtwDistance(_ a: [FPoint], _ b: [FPoint], band: Int = 4) -> Float {
        let n = a.count, m = b.count
        guard n > 0, m > 0 else { return .infinity }
        let inf = Float.infinity
        var prev = [Float](repeating: inf, count: m + 1)
        var cur = [Float](repeating: inf, count: m + 1)
        prev[0] = 0
        for i in 1...n {
            cur[0] = inf
            let lo = max(1, i - band), hi = min(m, i + band)
            guard lo <= hi else { swap(&prev, &cur); continue }
            if lo > 1 { for j in 1..<lo { cur[j] = inf } }
            for j in lo...hi {
                let d = a[i - 1].distance(to: b[j - 1])
                cur[j] = d + min(prev[j], prev[j - 1], cur[j - 1])
            }
            if hi < m { for j in (hi + 1)...m { cur[j] = inf } }
            swap(&prev, &cur)
        }
        // Path length is at least max(n, m); normalise by that for a mean-like value.
        return prev[m] / Float(max(n, m))
    }
}
