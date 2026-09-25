import UIKit
import KeyboardCore

struct Suggestion: Equatable {
    /// `.ai` is a result of the assistant (a corrected sentence, a continuation), marked with ✦.
    enum Kind: Equatable { case primary, alternate, literal, prediction, ai }
    let text: String
    let kind: Kind
    var display: String {
        switch kind {
        case .literal: return "„\(text)“"
        case .ai: return "✦ \(text)"
        default: return text
        }
    }
}

/// The strip above the keys: up to three suggestions with hairline dividers, the primary one in
/// the middle and bold, flanked by a few quiet icon buttons – each action exists exactly once:
///
///     [✦ assistant] [clipboard]   word | WORD | word   [DE] [hide]
///
/// The assistant shows while it is switched on, the clipboard while the history is kept, the
/// language badge while several typing languages are enabled (a tap switches to the next one),
/// and the hide button always (iPhone has no system dismiss key). Emoji live on the comma key.
/// While a glide is in flight the words give way to a live preview of the word being traced.
final class SuggestionBarView: UIView {
    var onSelect: ((Suggestion) -> Void)?
    var onDismiss: (() -> Void)?
    var onLanguage: (() -> Void)?
    var onClipboard: (() -> Void)?
    var onAI: (() -> Void)?
    private var buttons: [UIButton] = []
    /// Visual pill per cell. The button itself spans the whole cell so the tap target is large;
    /// only this inset view shows the highlight.
    private var pills: [UIView] = []
    private var dividers: [UIView] = []
    let dismissButton = StripIconButton(symbol: "keyboard.chevron.compact.down", identifier: "dismiss-keyboard", label: "Tastatur ausblenden")
    let clipboardButton = StripIconButton(symbol: "list.clipboard", identifier: "keyboard-clipboard", label: "Zwischenablage")
    let languageButton = StripIconButton(symbol: nil, identifier: "switch-language", label: "Sprache")
    /// The sparkles that open the AI panel; hidden while the assistant is off.
    let aiButton = AIStripButton()
    /// The word being traced while a glide is in flight.
    private let previewLabel = UILabel()

    /// Width of each icon button (the whole strip height is its touch area).
    static let iconWidth: CGFloat = 40
    /// Gap between the strip's edge and the first icon, and between the icons and the words.
    static let edgeInset: CGFloat = 2

    /// Where the suggestion cells sit, after layout.
    private(set) var wordArea: CGRect = .zero

    /// Whether the assistant button is shown (the assistant is switched on in the app).
    var showsAI = false {
        didSet {
            guard showsAI != oldValue else { return }
            aiButton.isHidden = !showsAI
            setNeedsLayout()
        }
    }

    /// Whether the clipboard button is shown (the history is switched on in the app).
    var showsClipboard = true {
        didSet {
            guard showsClipboard != oldValue else { return }
            clipboardButton.isHidden = !showsClipboard
            setNeedsLayout()
        }
    }

    private(set) var suggestions: [Suggestion] = []
    private var theme: KeyboardTheme

    /// The badge text of the current language, or nil to hide the language switch.
    var language: KeyboardLanguage? {
        didSet {
            guard language != oldValue else { return }
            languageButton.isHidden = language == nil
            languageButton.badge = language?.badge
            languageButton.accessibilityLabel = language.map { "Sprache: \($0.title). Zum Wechseln tippen" }
            setNeedsLayout()
        }
    }

    /// The word under the finger while a glide is in flight; nil shows the suggestions again.
    var glidePreview: String? {
        didSet {
            guard glidePreview != oldValue else { return }
            if let glidePreview { previewLabel.text = glidePreview }
            let showing = glidePreview != nil
            guard showing != (oldValue != nil) else { return }
            UIView.animate(withDuration: showing ? 0.12 : 0.18, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.previewLabel.alpha = showing ? 1 : 0
                let wordsAlpha: CGFloat = showing ? 0 : 1
                self.buttons.forEach { $0.alpha = wordsAlpha }
                self.dividers.forEach { $0.alpha = wordsAlpha }
            }
        }
    }

    init(theme: KeyboardTheme) {
        self.theme = theme
        super.init(frame: .zero)
        backgroundColor = .clear
        for i in 0..<3 {
            let b = UIButton(type: .custom)
            b.tag = i
            b.titleLabel?.lineBreakMode = .byTruncatingTail
            b.titleLabel?.adjustsFontSizeToFitWidth = true
            b.titleLabel?.minimumScaleFactor = 0.7
            b.contentEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
            b.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
            b.addTarget(self, action: #selector(highlight(_:)), for: [.touchDown, .touchDragEnter])
            b.addTarget(self, action: #selector(unhighlight(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
            b.accessibilityIdentifier = "suggestion-\(i)"
            let pill = UIView()
            pill.isUserInteractionEnabled = false
            pill.layer.cornerCurve = .continuous
            b.insertSubview(pill, at: 0)
            pills.append(pill)
            addSubview(b)
            buttons.append(b)
        }
        for _ in 0..<2 {
            let d = UIView()
            addSubview(d)
            dividers.append(d)
        }
        previewLabel.textAlignment = .center
        previewLabel.adjustsFontSizeToFitWidth = true
        previewLabel.minimumScaleFactor = 0.6
        previewLabel.alpha = 0
        previewLabel.isAccessibilityElement = false
        addSubview(previewLabel)

        dismissButton.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)
        addSubview(dismissButton)
        languageButton.isHidden = true
        languageButton.addTarget(self, action: #selector(languageTapped), for: .touchUpInside)
        addSubview(languageButton)
        clipboardButton.addTarget(self, action: #selector(clipboardTapped), for: .touchUpInside)
        addSubview(clipboardButton)
        aiButton.isHidden = true
        aiButton.addTarget(self, action: #selector(aiTapped), for: .touchUpInside)
        addSubview(aiButton)
        apply(theme: theme)
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(theme: KeyboardTheme) {
        self.theme = theme
        dividers.forEach { $0.backgroundColor = theme.suggestionDivider }
        [dismissButton, languageButton, clipboardButton].forEach { $0.apply(theme: theme) }
        aiButton.apply(theme: theme)
        previewLabel.textColor = theme.suggestionText
        previewLabel.font = .systemFont(ofSize: traitCollection.userInterfaceIdiom == .pad ? 21 : 19, weight: .semibold)
        render()
    }

    func set(_ new: [Suggestion]) {
        guard new != suggestions else { return }
        let hadContent = !suggestions.isEmpty
        let countChanged = new.count != suggestions.count
        suggestions = new
        render()
        if countChanged { setNeedsLayout() }
        // A soft fade when the strip fills after being empty (e.g. first letter of a word).
        if !hadContent, !new.isEmpty {
            buttons.forEach { $0.titleLabel?.alpha = 0 }
            UIView.animate(withDuration: 0.16, delay: 0, options: [.allowUserInteraction, .curveEaseOut]) {
                self.buttons.forEach { $0.titleLabel?.alpha = 1 }
            }
        }
    }

    private func render() {
        for (i, b) in buttons.enumerated() {
            let s = suggestions.indices.contains(i) ? suggestions[i] : nil
            let weight: UIFont.Weight = s?.kind == .primary ? .semibold : .regular
            let size: CGFloat = traitCollection.userInterfaceIdiom == .pad ? 19 : 17
            b.setTitle(s?.display, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: size, weight: weight)
            b.setTitleColor(s?.kind == .ai ? theme.accent : theme.suggestionText, for: .normal)
            b.isHidden = s == nil
            b.accessibilityLabel = s.map { ($0.kind == .ai ? "KI-Vorschlag " : "Vorschlag ") + $0.text }
        }
        let visible = suggestions.count
        dividers[0].isHidden = visible < 2
        dividers[1].isHidden = visible < 3
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let icon = Self.iconWidth
        // Leading icons from the left edge, trailing ones from the right; each spans the full
        // strip height so a tap anywhere around the glyph lands.
        var left = Self.edgeInset
        for view in [aiButton, clipboardButton] as [UIView] where !view.isHidden {
            view.frame = CGRect(x: left, y: 0, width: icon, height: bounds.height)
            left += icon
        }
        var right = bounds.width - Self.edgeInset
        for view in [dismissButton, languageButton] as [UIView] where !view.isHidden {
            right -= icon
            view.frame = CGRect(x: right, y: 0, width: icon, height: bounds.height)
        }
        // A little air between the icons and the words, none when there is no icon on that side.
        if left > Self.edgeInset { left += 2 }
        if right < bounds.width - Self.edgeInset { right -= 2 }
        wordArea = CGRect(x: left, y: 0, width: max(right - left, 0), height: bounds.height)
        previewLabel.frame = wordArea.insetBy(dx: 8, dy: 0)

        // The visible words share the whole word area: one word gets all of it, two get halves.
        // A tap anywhere around a word then reaches it instead of a dead third of the strip.
        let visible = max(min(suggestions.count, buttons.count), 1)
        let w = wordArea.width / CGFloat(visible)
        let inset: CGFloat = 4
        let h = bounds.height - 12
        // The button covers its whole cell (full height, no gaps) so a tap anywhere near the
        // word registers; the pill inside carries the inset look.
        for (i, b) in buttons.enumerated() {
            b.frame = CGRect(x: wordArea.minX + CGFloat(min(i, visible - 1)) * w, y: 0, width: w, height: bounds.height)
            let pill = pills[i]
            pill.frame = CGRect(x: inset, y: 6, width: max(w - inset * 2, 0), height: max(h, 0))
            pill.layer.cornerRadius = min(max(h, 0) / 2, 12)
        }
        for (i, d) in dividers.enumerated() {
            d.frame = CGRect(x: wordArea.minX + w * CGFloat(i + 1) - 0.5, y: bounds.height * 0.3, width: 1, height: bounds.height * 0.4)
        }
    }

    @objc private func tapped(_ sender: UIButton) {
        guard glidePreview == nil, suggestions.indices.contains(sender.tag) else { return }
        onSelect?(suggestions[sender.tag])
    }

    @objc private func dismissTapped() { onDismiss?() }

    @objc private func languageTapped() { onLanguage?() }

    @objc private func clipboardTapped() { onClipboard?() }

    @objc private func aiTapped() { onAI?() }

    @objc private func highlight(_ sender: UIButton) {
        pills[safe: sender.tag]?.backgroundColor = theme.suggestionHighlight
    }

    @objc private func unhighlight(_ sender: UIButton) {
        guard let pill = pills[safe: sender.tag] else { return }
        UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            pill.backgroundColor = .clear
        }
    }
}

/// A quiet icon in the strip: a glyph (or a short text badge such as "DE") in the strip's
/// secondary colour, no capsule, and a soft round highlight while pressed.
final class StripIconButton: UIControl {
    private let symbol: String?
    private let imageView = UIImageView()
    private let badgeLabel = UILabel()
    private let halo = UIView()

    /// Text shown in a thin rounded frame instead of a glyph (the language badge).
    var badge: String? {
        didSet { badgeLabel.text = badge; setNeedsLayout() }
    }

    init(symbol: String?, identifier: String, label: String) {
        self.symbol = symbol
        super.init(frame: .zero)
        accessibilityIdentifier = identifier
        accessibilityLabel = label
        accessibilityTraits = .button
        isAccessibilityElement = true
        halo.isUserInteractionEnabled = false
        halo.alpha = 0
        addSubview(halo)
        imageView.contentMode = .center
        imageView.isUserInteractionEnabled = false
        if let symbol {
            imageView.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .regular))
        }
        addSubview(imageView)
        badgeLabel.font = .systemFont(ofSize: 11.5, weight: .semibold)
        badgeLabel.textAlignment = .center
        badgeLabel.layer.cornerCurve = .continuous
        badgeLabel.layer.cornerRadius = 5
        badgeLabel.layer.borderWidth = 1.2
        badgeLabel.isHidden = symbol != nil
        addSubview(badgeLabel)
        addTarget(self, action: #selector(pressDown), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(pressUp), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(theme: KeyboardTheme) {
        let color = theme.suggestionText.withAlphaComponent(theme.isDark ? 0.78 : 0.62)
        imageView.tintColor = color
        badgeLabel.textColor = color
        badgeLabel.layer.borderColor = color.cgColor
        halo.backgroundColor = theme.suggestionHighlight
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side = min(bounds.width - 4, bounds.height - 8, 34)
        halo.frame = CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
        halo.layer.cornerRadius = side / 2
        imageView.frame = bounds
        badgeLabel.frame = CGRect(x: bounds.midX - 14, y: bounds.midY - 10, width: 28, height: 20)
    }

    @objc private func pressDown() {
        halo.alpha = 1
        UIView.animate(withDuration: 0.1, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.imageView.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
            self.badgeLabel.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        }
    }

    @objc private func pressUp() {
        UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5,
                       options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.halo.alpha = 0
            self.imageView.transform = .identity
            self.badgeLabel.transform = .identity
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
