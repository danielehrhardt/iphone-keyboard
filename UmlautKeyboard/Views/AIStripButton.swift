import UIKit

/// The assistant's button in the suggestion strip. No filled capsule: the sparkles glyph itself
/// carries a soft iridescent gradient (blue → violet → pink → amber), the way system AI entry
/// points look, and sits on the strip like the other icons. While a request runs a thin
/// gradient ring circles the glyph; a small dot marks a result waiting in the strip.
final class AIStripButton: UIControl {

    private let glyph = CAGradientLayer()
    private let glyphMask = CALayer()
    private let halo = CALayer()
    private let ring = CAGradientLayer()
    private let ringMask = CAShapeLayer()
    private let badge = CALayer()
    private var isDark = false

    /// Light-mode palette, deep enough to read on the pale keyboard material.
    private static let lightColors: [UIColor] = [
        UIColor(red: 0.20, green: 0.45, blue: 1.00, alpha: 1),
        UIColor(red: 0.55, green: 0.32, blue: 0.98, alpha: 1),
        UIColor(red: 0.93, green: 0.30, blue: 0.62, alpha: 1),
        UIColor(red: 1.00, green: 0.55, blue: 0.20, alpha: 1),
    ]
    /// Dark-mode palette, lifted so the glyph glows on the dark material.
    private static let darkColors: [UIColor] = [
        UIColor(red: 0.42, green: 0.62, blue: 1.00, alpha: 1),
        UIColor(red: 0.72, green: 0.52, blue: 1.00, alpha: 1),
        UIColor(red: 1.00, green: 0.48, blue: 0.74, alpha: 1),
        UIColor(red: 1.00, green: 0.70, blue: 0.38, alpha: 1),
    ]

    /// A request is running: the ring circles and the glyph breathes.
    var isBusy = false {
        didSet {
            guard isBusy != oldValue else { return }
            isBusy ? startBusy() : stopBusy()
            accessibilityValue = isBusy ? "Arbeitet" : nil
        }
    }

    /// An AI suggestion waits in the strip.
    var showsBadge = false {
        didSet {
            guard showsBadge != oldValue else { return }
            badge.isHidden = !showsBadge
            guard showsBadge else { return }
            let pop = CASpringAnimation(keyPath: "transform.scale")
            pop.fromValue = 0.2
            pop.toValue = 1
            pop.damping = 11
            pop.initialVelocity = 6
            pop.duration = pop.settlingDuration
            badge.add(pop, forKey: "pop")
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "ai-button"
        accessibilityLabel = "KI-Assistent"
        accessibilityTraits = .button
        isAccessibilityElement = true

        halo.cornerCurve = .continuous
        halo.opacity = 0
        layer.addSublayer(halo)

        ring.type = .conic
        ring.startPoint = CGPoint(x: 0.5, y: 0.5)
        ring.endPoint = CGPoint(x: 0.5, y: 0)
        ringMask.fillColor = nil
        ringMask.strokeColor = UIColor.black.cgColor
        ringMask.lineWidth = 1.6
        ring.mask = ringMask
        ring.opacity = 0
        layer.addSublayer(ring)

        glyph.startPoint = CGPoint(x: 0, y: 0)
        glyph.endPoint = CGPoint(x: 1, y: 1)
        glyphMask.contentsGravity = .resizeAspect
        glyph.mask = glyphMask
        layer.addSublayer(glyph)

        badge.isHidden = true
        badge.borderWidth = 1.5
        layer.addSublayer(badge)

        addTarget(self, action: #selector(pressDown), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(pressUp), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(theme: KeyboardTheme) {
        isDark = theme.isDark
        let colors = (isDark ? Self.darkColors : Self.lightColors).map(\.cgColor)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glyph.colors = colors
        // The conic ring closes on its first colour so it has no seam.
        ring.colors = colors + [colors[0]]
        halo.backgroundColor = theme.suggestionHighlight.cgColor
        badge.backgroundColor = (isDark ? Self.darkColors : Self.lightColors)[2].cgColor
        badge.borderColor = (isDark ? UIColor(white: 0.16, alpha: 1) : UIColor(white: 0.97, alpha: 1)).cgColor
        CATransaction.commit()
        updateGlyphImage()
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if previous?.displayScale != traitCollection.displayScale { updateGlyphImage() }
    }

    /// The symbol is rendered once as an alpha mask; the gradient shows through it.
    private func updateGlyphImage() {
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        guard let symbol = UIImage(systemName: "sparkles", withConfiguration: config) else { return }
        let format = UIGraphicsImageRendererFormat()
        format.scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 3
        let image = UIGraphicsImageRenderer(size: symbol.size, format: format).image { _ in
            symbol.withTintColor(.black, renderingMode: .alwaysOriginal).draw(at: .zero)
        }
        glyphMask.contents = image.cgImage
        glyphMask.contentsScale = format.scale
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let side = min(bounds.width, bounds.height, 34)
        let circle = CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
        halo.frame = circle
        halo.cornerRadius = side / 2
        ring.frame = circle
        ringMask.frame = ring.bounds
        ringMask.path = UIBezierPath(ovalIn: ring.bounds.insetBy(dx: 1, dy: 1)).cgPath
        let glyphSide: CGFloat = 24
        glyph.frame = CGRect(x: bounds.midX - glyphSide / 2, y: bounds.midY - glyphSide / 2, width: glyphSide, height: glyphSide)
        glyphMask.frame = glyph.bounds
        let d: CGFloat = 8
        badge.frame = CGRect(x: glyph.frame.maxX - d / 2, y: glyph.frame.minY - d / 4, width: d, height: d)
        badge.cornerRadius = d / 2
        CATransaction.commit()
    }

    private func startBusy() {
        ring.opacity = 1
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = CGFloat.pi * 2
        spin.duration = 1.4
        spin.repeatCount = .infinity
        ring.add(spin, forKey: "spin")
        let breathe = CABasicAnimation(keyPath: "opacity")
        breathe.fromValue = 1
        breathe.toValue = 0.55
        breathe.duration = 0.7
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        glyph.add(breathe, forKey: "breathe")
    }

    private func stopBusy() {
        ring.removeAnimation(forKey: "spin")
        glyph.removeAnimation(forKey: "breathe")
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = ring.presentation()?.opacity ?? 1
        fade.toValue = 0
        fade.duration = 0.2
        ring.opacity = 0
        ring.add(fade, forKey: "fade")
    }

    @objc private func pressDown() {
        halo.opacity = 1
        UIView.animate(withDuration: 0.1, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        }
    }

    @objc private func pressUp() {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = halo.presentation()?.opacity ?? 1
        fade.toValue = 0
        fade.duration = 0.2
        halo.opacity = 0
        halo.add(fade, forKey: "fade")
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.5,
                       options: [.beginFromCurrentState, .allowUserInteraction]) { self.transform = .identity }
    }
}
