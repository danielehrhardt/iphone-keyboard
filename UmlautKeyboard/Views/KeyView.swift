import UIKit
import KeyboardCore

enum ShiftState {
    case off, on, locked
    var isActive: Bool { self != .off }
}

/// A single key cap. Pure presentation; touches are handled by `KeyGridView`.
///
/// Drawn as a frosted glass cap on top of the system keyboard material: a translucent fill,
/// a hairline bright rim and a soft drop shadow. Presses animate the fill.
final class KeyView: UIView {
    let key: Key
    private let label = UILabel()
    private let hintLabel = UILabel()
    private let iconView = UIImageView()
    private let rim = CAShapeLayer()
    private var theme: KeyboardTheme
    private(set) var isPressed = false

    /// Long-press digit/symbol shown in the corner (top row numbers).
    var hint: String? { didSet { hintLabel.text = hint; hintLabel.isHidden = hint == nil } }
    var shiftState: ShiftState = .off { didSet { refresh() } }
    var returnLabel: String? { didSet { refresh() } }
    var isAccented = false { didSet { refresh() } }
    var isCompact = false { didSet { refresh() } }

    init(key: Key, theme: KeyboardTheme) {
        self.key = key
        self.theme = theme
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        // Keys are announced by VoiceOver and addressable by UI tests; touches still go to the grid.
        isAccessibilityElement = true
        accessibilityTraits = .keyboardKey
        accessibilityIdentifier = "key-\(key.id)"
        accessibilityLabel = Self.accessibilityName(for: key)
        layer.cornerRadius = theme.cornerRadius
        layer.cornerCurve = .continuous
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 0.6
        layer.masksToBounds = false

        rim.fillColor = nil
        rim.lineWidth = 1
        layer.addSublayer(rim)

        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.6
        label.baselineAdjustment = .alignCenters
        addSubview(label)

        hintLabel.font = .systemFont(ofSize: 10, weight: .medium)
        hintLabel.textAlignment = .right
        hintLabel.isHidden = true
        addSubview(hintLabel)

        iconView.contentMode = .center
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        addSubview(iconView)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(theme: KeyboardTheme) {
        self.theme = theme
        layer.cornerRadius = theme.cornerRadius
        refresh()
    }

    func setPressed(_ pressed: Bool) {
        guard pressed != isPressed else { return }
        isPressed = pressed
        // Press instantly, release with a short fade — feels snappy and never lags a fast typist.
        if pressed {
            refresh()
        } else {
            UIView.animate(withDuration: 0.16, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]) {
                self.refresh()
            }
        }
    }

    /// Trackpad mode (dragging on the space bar) blanks the caps like the system keyboard does.
    func setContentHidden(_ hidden: Bool, animated: Bool) {
        let alpha: CGFloat = hidden ? 0 : 1
        let changes = { self.label.alpha = alpha; self.hintLabel.alpha = alpha; self.iconView.alpha = alpha }
        if animated {
            UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction], animations: changes)
        } else {
            changes()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds
        iconView.frame = bounds
        hintLabel.frame = CGRect(x: 0, y: 2, width: bounds.width - 4, height: 12)
        let r = layer.cornerRadius
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: r).cgPath
        // The rim is a rounded rect inset by half a point, drawn only along its upper half
        // (a full stroke looks like a border; a top-only highlight looks like light on glass).
        rim.frame = bounds
        rim.path = Self.topRimPath(in: bounds.insetBy(dx: 0.5, dy: 0.5), radius: max(0, r - 0.5))
    }

    private static func topRimPath(in rect: CGRect, radius r: CGFloat) -> CGPath {
        let path = UIBezierPath()
        let start = CGPoint(x: rect.minX, y: rect.midY)
        path.move(to: start)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addArc(withCenter: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r, startAngle: .pi, endAngle: 1.5 * .pi, clockwise: true)
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addArc(withCenter: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r, startAngle: 1.5 * .pi, endAngle: 2 * .pi, clockwise: true)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path.cgPath
    }

    static func accessibilityName(for key: Key) -> String {
        switch key.action {
        case .character(let s): return s
        case .backspace: return "Löschen"
        case .shift: return "Umschalt"
        case .space: return "Leerzeichen"
        case .newline: return "Return"
        case .switchLayer(let l): return l == .letters ? "Buchstaben" : (l == .symbols ? "Zahlen" : "Sonderzeichen")
        case .globe: return "Nächste Tastatur"
        case .emoji: return "Emoji"
        case .dismiss: return "Tastatur ausblenden"
        }
    }

    private static var symbolCache: [String: UIImage] = [:]
    private static func symbolImage(_ name: String) -> UIImage? {
        if let cached = symbolCache[name] { return cached }
        let image = UIImage(systemName: name)
        symbolCache[name] = image
        return image
    }

    private func refresh() {
        if key.isLetter, let c = key.character {
            accessibilityLabel = shiftState.isActive ? String(c).uppercased() : String(c)
        }
        let isFunction = key.isFunction
        let accentFill = isAccented && key.action == .newline
        let shiftFill = key.action == .shift && shiftState.isActive
        let base: UIColor
        if accentFill {
            base = isPressed ? theme.accentPressed : theme.accent
        } else if shiftFill {
            base = isPressed ? UIColor(white: 0.92, alpha: 1) : .white
        } else if isFunction {
            base = isPressed ? theme.functionKeyPressedBackground : theme.functionKeyBackground
        } else {
            base = isPressed ? theme.keyPressedBackground : theme.keyBackground
        }
        backgroundColor = base
        layer.shadowColor = theme.keyShadow.cgColor
        layer.shadowOpacity = theme.keyShadowOpacity
        rim.strokeColor = (accentFill ? UIColor(white: 1, alpha: 0.35) : theme.keyRim).cgColor

        let textColor: UIColor = accentFill ? theme.onAccent : (shiftFill ? .black : (isFunction ? theme.functionKeyText : theme.keyText))
        label.textColor = textColor
        hintLabel.textColor = theme.hintText
        iconView.tintColor = textColor

        // Content
        var text: String? = nil
        var symbol: String? = key.symbolName
        switch key.action {
        case .character(let s):
            let shown = key.isLetter && shiftState.isActive ? s.uppercased() : s
            text = shown
            symbol = nil
        case .space:
            text = key.label
        case .newline:
            if let returnLabel { text = returnLabel; symbol = nil }
        case .shift:
            symbol = shiftState == .locked ? "capslock.fill" : (shiftState == .on ? "shift.fill" : "shift")
        case .switchLayer:
            text = key.label
        case .backspace, .globe, .emoji, .dismiss:
            break
        }
        label.text = text
        label.isHidden = text == nil
        iconView.isHidden = symbol == nil
        if let symbol { iconView.image = Self.symbolImage(symbol) }

        let isPad = traitCollection.userInterfaceIdiom == .pad
        if key.isLetter || (!isFunction && key.action != .space) {
            let size: CGFloat = isPad ? 24 : (isCompact ? 20 : 23)
            label.font = .systemFont(ofSize: size, weight: .regular)
        } else if key.action == .space {
            label.font = .systemFont(ofSize: isPad ? 17 : 16, weight: .regular)
            label.textColor = textColor.withAlphaComponent(0.8)
        } else {
            label.font = .systemFont(ofSize: isPad ? 17 : 16, weight: .regular)
        }
        if key.action == .newline && returnLabel != nil {
            label.font = .systemFont(ofSize: isPad ? 17 : 16, weight: .medium)
        }
    }
}
