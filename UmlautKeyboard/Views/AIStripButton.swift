import UIKit

/// The sparkles capsule in the suggestion strip that opens the AI panel. A soft accent
/// gradient with a glow, a pulsing sparkle while a request runs, and a dot when a result waits
/// in the strip. Same size as the language badge next to it.
final class AIStripButton: UIControl {

    private let gradient = CAGradientLayer()
    private let icon = UIImageView()
    private let badge = UIView()
    private var accent: UIColor = .systemBlue

    /// A request is running: the sparkle breathes.
    var isBusy = false {
        didSet {
            guard isBusy != oldValue else { return }
            isBusy ? startPulse() : stopPulse()
        }
    }

    /// An AI suggestion waits in the strip.
    var showsBadge = false {
        didSet {
            guard showsBadge != oldValue else { return }
            badge.isHidden = !showsBadge
            if showsBadge {
                badge.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
                UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.55, initialSpringVelocity: 0.8) {
                    self.badge.transform = .identity
                }
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "ai-button"
        accessibilityLabel = "KI-Assistent"
        accessibilityTraits = .button
        isAccessibilityElement = true
        layer.cornerCurve = .continuous
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 6
        layer.shadowOpacity = 0.28
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        gradient.cornerCurve = .continuous
        layer.addSublayer(gradient)
        icon.image = UIImage(systemName: "sparkles", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
        icon.tintColor = .white
        icon.contentMode = .center
        icon.isUserInteractionEnabled = false
        addSubview(icon)
        badge.backgroundColor = .white
        badge.layer.borderWidth = 1.5
        badge.isHidden = true
        badge.isUserInteractionEnabled = false
        addSubview(badge)
        addTarget(self, action: #selector(pressDown), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(pressUp), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(theme: KeyboardTheme) {
        accent = theme.accent
        let bright = theme.accentPressed
        // A second hue keeps the capsule from reading as "just another accent key".
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        accent.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let shifted = UIColor(hue: fmod(h + 0.08, 1), saturation: min(1, s + 0.05), brightness: min(1, b + 0.05), alpha: 1)
        gradient.colors = [bright.cgColor, accent.cgColor, shifted.cgColor]
        gradient.locations = [0, 0.55, 1]
        layer.shadowColor = accent.cgColor
        badge.layer.borderColor = accent.cgColor
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let radius = bounds.height / 2
        layer.cornerRadius = radius
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: radius).cgPath
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        gradient.cornerRadius = radius
        CATransaction.commit()
        icon.frame = bounds
        let d: CGFloat = 9
        badge.frame = CGRect(x: bounds.width - d - 3, y: 2, width: d, height: d)
        badge.layer.cornerRadius = d / 2
    }

    private func startPulse() {
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.85
        scale.toValue = 1.15
        scale.duration = 0.55
        scale.autoreverses = true
        scale.repeatCount = .infinity
        scale.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        icon.layer.add(scale, forKey: "pulse")
        let glow = CABasicAnimation(keyPath: "shadowOpacity")
        glow.fromValue = 0.28
        glow.toValue = 0.7
        glow.duration = 0.55
        glow.autoreverses = true
        glow.repeatCount = .infinity
        layer.add(glow, forKey: "glow")
    }

    private func stopPulse() {
        icon.layer.removeAnimation(forKey: "pulse")
        layer.removeAnimation(forKey: "glow")
    }

    @objc private func pressDown() {
        UIView.animate(withDuration: 0.1) { self.transform = CGAffineTransform(scaleX: 0.92, y: 0.92) }
    }

    @objc private func pressUp() {
        UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.5) { self.transform = .identity }
    }
}
