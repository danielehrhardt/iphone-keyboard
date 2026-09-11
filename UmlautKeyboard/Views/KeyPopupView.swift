import UIKit
import KeyboardCore

/// The bubble that appears above a key: a magnified preview on tap, or a row of alternates on
/// long-press. Drawn as a single shape (bubble + stem) like the system keyboard.
final class KeyPopupView: UIView {
    private let shape = CAShapeLayer()
    private var labels: [UILabel] = []
    private(set) var options: [String] = []
    private(set) var selectedIndex = 0
    private var theme: KeyboardTheme
    private var keyFrame: CGRect = .zero
    private var isExpanded = false
    private var optionWidth: CGFloat = 0
    private var bubbleRect: CGRect = .zero

    init(theme: KeyboardTheme) {
        self.theme = theme
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        layer.addSublayer(shape)
        shape.fillColor = theme.popupBackground.cgColor
        shape.shadowColor = UIColor.black.cgColor
        shape.shadowOpacity = theme.isDark ? 0.6 : 0.28
        shape.shadowRadius = 4
        shape.shadowOffset = CGSize(width: 0, height: 1)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Shows a single magnified character above `keyFrame` (coordinates in the superview).
    func showPreview(text: String, keyFrame: CGRect, in container: CGRect) {
        isExpanded = false
        self.keyFrame = keyFrame
        options = [text]
        selectedIndex = 0
        let w = max(keyFrame.width * 1.55, 46)
        let h = keyFrame.height * 1.12
        var x = keyFrame.midX - w / 2
        x = min(max(x, container.minX + 2), container.maxX - w - 2)
        bubbleRect = CGRect(x: x, y: keyFrame.minY - h - 6, width: w, height: h)
        rebuildLabels(fontSize: 34)
        layoutBubble()
        isHidden = false
    }

    /// Shows alternates in a row; `preferLeft` puts the extra options toward the left edge for keys on the right side.
    func showAlternates(_ alternates: [String], keyFrame: CGRect, in container: CGRect, preferLeft: Bool) {
        isExpanded = true
        self.keyFrame = keyFrame
        options = alternates
        selectedIndex = 0
        optionWidth = max(keyFrame.width * 1.1, 38)
        let w = optionWidth * CGFloat(alternates.count) + 8
        let h = keyFrame.height * 1.12
        var x = preferLeft ? keyFrame.maxX + 4 - w : keyFrame.minX - 4
        x = min(max(x, container.minX + 2), container.maxX - w - 2)
        if preferLeft {
            options = alternates.reversed()
            selectedIndex = options.count - 1
        }
        bubbleRect = CGRect(x: x, y: keyFrame.minY - h - 6, width: w, height: h)
        rebuildLabels(fontSize: 24)
        layoutBubble()
        isHidden = false
    }

    /// Updates the highlighted alternate for a finger at `point` (superview coordinates).
    /// Returns true if the selection changed.
    @discardableResult
    func select(at point: CGPoint) -> Bool {
        guard isExpanded, options.count > 1 else { return false }
        let rel = point.x - bubbleRect.minX - 4
        let idx = max(0, min(options.count - 1, Int(floor(rel / optionWidth))))
        guard idx != selectedIndex else { return false }
        selectedIndex = idx
        updateHighlights()
        return true
    }

    var selectedOption: String? { options.indices.contains(selectedIndex) ? options[selectedIndex] : nil }

    func hide() {
        isHidden = true
        options = []
    }

    private func rebuildLabels(fontSize: CGFloat) {
        labels.forEach { $0.removeFromSuperview() }
        labels = options.map { text in
            let l = UILabel()
            l.text = text
            l.textAlignment = .center
            l.font = .systemFont(ofSize: fontSize, weight: .regular)
            l.adjustsFontSizeToFitWidth = true
            l.minimumScaleFactor = 0.5
            l.layer.cornerRadius = 5
            l.layer.cornerCurve = .continuous
            l.layer.masksToBounds = true
            addSubview(l)
            return l
        }
        updateHighlights()
    }

    private func updateHighlights() {
        for (i, l) in labels.enumerated() {
            let selected = isExpanded && i == selectedIndex
            l.backgroundColor = selected ? theme.accent : .clear
            l.textColor = selected ? theme.onAccent : theme.keyText
        }
    }

    private func layoutBubble() {
        let r = layer.cornerRadius > 0 ? layer.cornerRadius : 9
        let path = UIBezierPath()
        let b = bubbleRect
        let k = keyFrame
        let stemTop = b.maxY
        // Bubble
        path.move(to: CGPoint(x: b.minX + r, y: b.minY))
        path.addLine(to: CGPoint(x: b.maxX - r, y: b.minY))
        path.addQuadCurve(to: CGPoint(x: b.maxX, y: b.minY + r), controlPoint: CGPoint(x: b.maxX, y: b.minY))
        path.addLine(to: CGPoint(x: b.maxX, y: stemTop - r))
        path.addQuadCurve(to: CGPoint(x: b.maxX - r, y: stemTop), controlPoint: CGPoint(x: b.maxX, y: stemTop))
        // Stem down to the key (right side)
        let stemRight = min(b.maxX - r, k.maxX)
        let stemLeft = max(b.minX + r, k.minX)
        path.addLine(to: CGPoint(x: stemRight + 6, y: stemTop))
        path.addQuadCurve(to: CGPoint(x: stemRight, y: stemTop + 8), controlPoint: CGPoint(x: stemRight, y: stemTop))
        path.addLine(to: CGPoint(x: k.maxX, y: k.maxY - r))
        path.addQuadCurve(to: CGPoint(x: k.maxX - r, y: k.maxY), controlPoint: CGPoint(x: k.maxX, y: k.maxY))
        path.addLine(to: CGPoint(x: k.minX + r, y: k.maxY))
        path.addQuadCurve(to: CGPoint(x: k.minX, y: k.maxY - r), controlPoint: CGPoint(x: k.minX, y: k.maxY))
        path.addLine(to: CGPoint(x: stemLeft, y: stemTop + 8))
        path.addQuadCurve(to: CGPoint(x: stemLeft - 6, y: stemTop), controlPoint: CGPoint(x: stemLeft, y: stemTop))
        path.addLine(to: CGPoint(x: b.minX + r, y: stemTop))
        path.addQuadCurve(to: CGPoint(x: b.minX, y: stemTop - r), controlPoint: CGPoint(x: b.minX, y: stemTop))
        path.addLine(to: CGPoint(x: b.minX, y: b.minY + r))
        path.addQuadCurve(to: CGPoint(x: b.minX + r, y: b.minY), controlPoint: CGPoint(x: b.minX, y: b.minY))
        path.close()
        shape.path = path.cgPath
        shape.shadowPath = path.cgPath
        shape.fillColor = theme.popupBackground.cgColor

        if isExpanded {
            for (i, l) in labels.enumerated() {
                l.frame = CGRect(x: b.minX + 4 + CGFloat(i) * optionWidth, y: b.minY + 4, width: optionWidth, height: b.height - 8)
            }
        } else {
            labels.first?.frame = b.insetBy(dx: 2, dy: 2)
        }
    }

    func apply(theme: KeyboardTheme) {
        self.theme = theme
        shape.fillColor = theme.popupBackground.cgColor
        shape.shadowOpacity = theme.isDark ? 0.6 : 0.28
        updateHighlights()
    }
}
