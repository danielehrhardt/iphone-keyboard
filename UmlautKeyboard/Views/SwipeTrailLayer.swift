import UIKit

/// A comet-like trail that follows the finger during glide typing: recent points are drawn
/// wide and opaque, older ones thin and faded, with a soft glow underneath; the whole thing
/// dissolves on release.
final class SwipeTrailLayer: CALayer {
    private struct Sample { let point: CGPoint; let time: CFTimeInterval }
    private var samples: [Sample] = []
    private var segments: [CAShapeLayer] = []
    private var glows: [CAShapeLayer] = []
    var color: UIColor = .systemBlue
    var maxAge: CFTimeInterval = 0.45
    var maxWidth: CGFloat = 9

    func begin(at point: CGPoint) {
        samples = [Sample(point: point, time: CACurrentMediaTime())]
        opacity = 1
        removeAllAnimations()
        redraw()
    }

    func add(point: CGPoint) {
        let now = CACurrentMediaTime()
        if let last = samples.last, hypot(last.point.x - point.x, last.point.y - point.y) < 1.5 { return }
        samples.append(Sample(point: point, time: now))
        samples.removeAll { now - $0.time > maxAge }
        redraw()
    }

    func end() {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = 0.22
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        fade.isRemovedOnCompletion = false
        fade.fillMode = .forwards
        add(fade, forKey: "fade")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.animation(forKey: "fade") != nil else { return }
            self.samples.removeAll()
            self.redraw()
        }
    }

    private func redraw() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let now = CACurrentMediaTime()
        // Draw in ~12 chunks with decreasing width/alpha; a wider, fainter copy underneath glows.
        let chunkCount = 12
        while glows.count < chunkCount {
            let g = CAShapeLayer()
            g.fillColor = nil
            g.lineCap = .round
            g.lineJoin = .round
            addSublayer(g)
            glows.append(g)
        }
        while segments.count < chunkCount {
            let s = CAShapeLayer()
            s.fillColor = nil
            s.lineCap = .round
            s.lineJoin = .round
            addSublayer(s)
            segments.append(s)
        }
        let n = samples.count
        guard n >= 2 else {
            segments.forEach { $0.path = nil }
            glows.forEach { $0.path = nil }
            CATransaction.commit()
            return
        }
        let perChunk = max(2, Int(ceil(Double(n) / Double(chunkCount))))
        var chunk = 0
        var start = 0
        while start < n - 1 && chunk < chunkCount {
            let end = min(n - 1, start + perChunk)
            let path = UIBezierPath()
            path.move(to: samples[start].point)
            for i in (start + 1)...end { path.addLine(to: samples[i].point) }
            let age = now - samples[end].time
            let life = CGFloat(max(0, 1 - age / maxAge))
            let width = max(1.5, maxWidth * (0.35 + 0.65 * life))
            let layer = segments[chunk]
            layer.path = path.cgPath
            layer.lineWidth = width
            layer.strokeColor = color.withAlphaComponent(0.25 + 0.75 * life).cgColor
            let glow = glows[chunk]
            glow.path = path.cgPath
            glow.lineWidth = width * 2.4
            glow.strokeColor = color.withAlphaComponent(0.05 + 0.17 * life).cgColor
            chunk += 1
            start = end
        }
        while chunk < chunkCount { segments[chunk].path = nil; glows[chunk].path = nil; chunk += 1 }
        CATransaction.commit()
    }
}
