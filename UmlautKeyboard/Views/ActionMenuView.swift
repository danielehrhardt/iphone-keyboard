import UIKit

/// One row of the action menu.
struct KeyboardAction: Equatable {
    enum Kind: Equatable { case clipboard, emoji, language, dismiss }
    let kind: Kind
    let title: String
    let symbol: String
    var identifier: String {
        switch kind {
        case .clipboard: return "action-clipboard"
        case .emoji: return "action-emoji"
        case .language: return "action-language"
        case .dismiss: return "action-dismiss"
        }
    }
}

/// Dropdown under the strip's "⋯" button: a small card with one row per action. The view
/// covers the whole keyboard while open so a tap anywhere outside the card closes it.
final class ActionMenuView: UIView {
    var onSelect: ((KeyboardAction) -> Void)?
    var onClose: (() -> Void)?
    private(set) var actions: [KeyboardAction] = []
    private let card = UIView()
    private var rows: [UIButton] = []
    private var separators: [UIView] = []
    private var theme: KeyboardTheme
    /// Top-left corner of the card in this view's coordinates (set by the owner to sit under the button).
    var anchor: CGPoint = CGPoint(x: 6, y: 40) { didSet { setNeedsLayout() } }

    static let rowHeight: CGFloat = 44
    static let cardWidth: CGFloat = 236

    init(theme: KeyboardTheme) {
        self.theme = theme
        super.init(frame: .zero)
        accessibilityIdentifier = "action-menu"
        backgroundColor = .clear
        card.layer.cornerCurve = .continuous
        card.layer.cornerRadius = 14
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.18
        card.layer.shadowRadius = 12
        card.layer.shadowOffset = CGSize(width: 0, height: 4)
        addSubview(card)
        let backdrop = UITapGestureRecognizer(target: self, action: #selector(backdropTapped))
        backdrop.cancelsTouchesInView = false
        addGestureRecognizer(backdrop)
        apply(theme: theme)
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(theme: KeyboardTheme) {
        self.theme = theme
        card.backgroundColor = theme.popupBackground
        card.layer.borderColor = theme.popupRim.cgColor
        card.layer.borderWidth = 0.5
        separators.forEach { $0.backgroundColor = theme.suggestionDivider }
        for b in rows { configure(b, action: actions[b.tag]) }
    }

    func set(actions new: [KeyboardAction]) {
        guard new != actions else { return }
        actions = new
        rows.forEach { $0.removeFromSuperview() }
        separators.forEach { $0.removeFromSuperview() }
        rows = []
        separators = []
        for (i, action) in actions.enumerated() {
            let b = UIButton(type: .custom)
            b.tag = i
            configure(b, action: action)
            b.addTarget(self, action: #selector(rowTapped(_:)), for: .touchUpInside)
            b.addTarget(self, action: #selector(highlight(_:)), for: [.touchDown, .touchDragEnter])
            b.addTarget(self, action: #selector(unhighlight(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
            card.addSubview(b)
            rows.append(b)
            if i > 0 {
                let s = UIView()
                s.backgroundColor = theme.suggestionDivider
                card.addSubview(s)
                separators.append(s)
            }
        }
        setNeedsLayout()
    }

    private func configure(_ b: UIButton, action: KeyboardAction) {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: action.symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium))
        config.imagePadding = 12
        config.imagePlacement = .leading
        var title = AttributedString(action.title)
        title.font = .systemFont(ofSize: 16)
        config.attributedTitle = title
        config.baseForegroundColor = theme.keyText
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14)
        b.configuration = config
        b.contentHorizontalAlignment = .leading
        b.accessibilityIdentifier = action.identifier
        b.accessibilityLabel = action.title
        b.layer.cornerCurve = .continuous
        b.layer.cornerRadius = 10
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let height = Self.rowHeight * CGFloat(rows.count) + 8
        let width = min(Self.cardWidth, max(bounds.width - 12, 0))
        var x = anchor.x
        if x + width > bounds.width - 6 { x = max(6, bounds.width - 6 - width) }
        card.frame = CGRect(x: x, y: anchor.y, width: width, height: height)
        for (i, b) in rows.enumerated() {
            b.frame = CGRect(x: 4, y: 4 + CGFloat(i) * Self.rowHeight, width: width - 8, height: Self.rowHeight)
        }
        for (i, s) in separators.enumerated() {
            s.frame = CGRect(x: 44, y: 4 + CGFloat(i + 1) * Self.rowHeight - 0.5, width: width - 48, height: 0.5)
        }
    }

    @objc private func rowTapped(_ sender: UIButton) {
        guard actions.indices.contains(sender.tag) else { return }
        onSelect?(actions[sender.tag])
    }

    @objc private func backdropTapped(_ g: UITapGestureRecognizer) {
        guard !card.frame.contains(g.location(in: self)) else { return }
        onClose?()
    }

    @objc private func highlight(_ sender: UIButton) { sender.backgroundColor = theme.suggestionHighlight }
    @objc private func unhighlight(_ sender: UIButton) {
        UIView.animate(withDuration: 0.15, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            sender.backgroundColor = .clear
        }
    }
}
