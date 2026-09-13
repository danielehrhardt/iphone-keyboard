import UIKit
import KeyboardCore

protocol AIPanelDelegate: AnyObject {
    /// A feature chip (or one of its option chips) was tapped: run it on the current source.
    func aiPanel(_ panel: AIPanelView, didRequest feature: AIFeature, tone: AIRewriteTone, target: AITranslationTarget)
    /// A result card was tapped.
    func aiPanel(_ panel: AIPanelView, didPick result: String)
    func aiPanelDidTapLetters(_ panel: AIPanelView)
    func aiPanelDidTapUndo(_ panel: AIPanelView)
    /// The user wants to add a key or pick a model: open the app.
    func aiPanelDidTapSettings(_ panel: AIPanelView)
}

/// The AI panel: feature chips on top, option chips for tone or target language below them,
/// the result cards (or the loading / error state) in the middle, and a bottom bar with the
/// way back to the letters, undo and the model in use. Covers strip and grid like the emoji panel.
final class AIPanelView: UIView {

    enum Phase: Equatable {
        case idle
        case loading
        case results([String])
        case failed(AIError)
    }

    weak var delegate: AIPanelDelegate?
    private(set) var feature: AIFeature?
    private(set) var tone: AIRewriteTone
    private(set) var target: AITranslationTarget
    private(set) var phase: Phase = .idle
    /// The text a request would work on, for the idle state.
    var sourcePreview: String? { didSet { if phase == .idle { renderContent() } } }
    var isSelection = false
    /// Name of the model behind the current feature, shown in the bottom bar.
    var modelTitle: String? { didSet { modelLabel.text = modelTitle; setNeedsLayout() } }
    var canUndo = false { didSet { undoButton.isHidden = !canUndo; setNeedsLayout() } }

    private var theme: KeyboardTheme
    private let featureScroll = UIScrollView()
    private let featureStack = UIStackView()
    private var featureButtons: [UIButton] = []
    private let optionScroll = UIScrollView()
    private let optionStack = UIStackView()
    private var optionButtons: [UIButton] = []
    private let contentScroll = UIScrollView()
    private let contentStack = UIStackView()
    private let lettersButton = UIButton(type: .system)
    private let undoButton = UIButton(type: .system)
    private let settingsButton = UIButton(type: .system)
    private let modelLabel = UILabel()
    private var loadingView: LoadingView?

    static let headerHeight: CGFloat = 46
    static let optionsHeight: CGFloat = 36
    static let barHeight: CGFloat = 40
    private static let sideInset: CGFloat = 8

    init(theme: KeyboardTheme, tone: AIRewriteTone, target: AITranslationTarget) {
        self.theme = theme
        self.tone = tone
        self.target = target
        super.init(frame: .zero)
        accessibilityIdentifier = "ai-panel"
        backgroundColor = .clear

        for scroll in [featureScroll, optionScroll] {
            scroll.showsHorizontalScrollIndicator = false
            scroll.alwaysBounceHorizontal = true
            scroll.contentInset = UIEdgeInsets(top: 0, left: Self.sideInset, bottom: 0, right: Self.sideInset)
            addSubview(scroll)
        }
        featureStack.axis = .horizontal
        featureStack.spacing = 6
        featureScroll.addSubview(featureStack)
        optionStack.axis = .horizontal
        optionStack.spacing = 6
        optionScroll.addSubview(optionStack)

        for f in AIFeature.allCases {
            let b = makeChip(title: f.title, symbol: f.symbol, size: 15)
            b.accessibilityIdentifier = "ai-feature-\(f.rawValue)"
            b.tag = AIFeature.allCases.firstIndex(of: f)!
            b.addTarget(self, action: #selector(featureTapped(_:)), for: .touchUpInside)
            featureStack.addArrangedSubview(b)
            featureButtons.append(b)
        }

        contentScroll.showsVerticalScrollIndicator = false
        contentScroll.alwaysBounceVertical = true
        contentScroll.clipsToBounds = true
        addSubview(contentScroll)
        contentStack.axis = .vertical
        contentStack.spacing = 8
        contentScroll.addSubview(contentStack)

        lettersButton.setTitle("ABC", for: .normal)
        lettersButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        lettersButton.accessibilityIdentifier = "ai-letters"
        lettersButton.addTarget(self, action: #selector(lettersTapped), for: .touchUpInside)
        addSubview(lettersButton)

        undoButton.setImage(UIImage(systemName: "arrow.uturn.backward", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)), for: .normal)
        undoButton.setTitle(" Rückgängig", for: .normal)
        undoButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        undoButton.accessibilityIdentifier = "ai-undo"
        undoButton.isHidden = true
        undoButton.addTarget(self, action: #selector(undoTapped), for: .touchUpInside)
        addSubview(undoButton)

        settingsButton.setImage(UIImage(systemName: "gearshape", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .regular)), for: .normal)
        settingsButton.accessibilityIdentifier = "ai-settings"
        settingsButton.accessibilityLabel = "KI-Einstellungen in der App"
        settingsButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
        addSubview(settingsButton)

        modelLabel.font = .systemFont(ofSize: 11, weight: .medium)
        modelLabel.textAlignment = .right
        modelLabel.adjustsFontSizeToFitWidth = true
        modelLabel.minimumScaleFactor = 0.8
        addSubview(modelLabel)

        apply(theme: theme)
        renderOptions()
        renderContent()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Public

    /// Fresh panel for a new visit: nothing selected, the source shown.
    func open(source: String?, isSelection: Bool, tone: AIRewriteTone, target: AITranslationTarget) {
        self.isSelection = isSelection
        self.tone = tone
        self.target = target
        feature = nil
        phase = .idle
        sourcePreview = source
        renderChips()
        renderOptions()
        renderContent()
        contentScroll.setContentOffset(.zero, animated: false)
    }

    func set(phase new: Phase) {
        guard new != phase else { return }
        phase = new
        renderContent()
    }

    /// Selects a feature from outside (e.g. the strip's badge leads to the check).
    func select(_ f: AIFeature) {
        feature = f
        renderChips()
        renderOptions()
        delegate?.aiPanel(self, didRequest: f, tone: tone, target: target)
    }

    func apply(theme: KeyboardTheme) {
        self.theme = theme
        lettersButton.tintColor = theme.functionKeyText
        lettersButton.backgroundColor = theme.functionKeyBackground
        lettersButton.layer.cornerCurve = .continuous
        lettersButton.layer.cornerRadius = 8
        undoButton.tintColor = theme.keyText
        settingsButton.tintColor = theme.hintText
        modelLabel.textColor = theme.hintText
        renderChips()
        renderOptions()
        renderContent()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        setNeedsLayout()
    }

    // MARK: Layout

    private var showsOptions: Bool { feature == .rewrite || feature == .translate }

    override func layoutSubviews() {
        super.layoutSubviews()
        let insets = safeAreaInsets
        let x = insets.left
        let width = max(0, bounds.width - insets.left - insets.right)
        let contentBottom = max(0, bounds.height - insets.bottom)
        var y: CGFloat = 0

        featureScroll.frame = CGRect(x: x, y: y, width: width, height: Self.headerHeight)
        featureStack.frame = CGRect(x: 0, y: 7, width: featureStack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width, height: Self.headerHeight - 14)
        featureScroll.contentSize = CGSize(width: featureStack.frame.width, height: Self.headerHeight)
        y += Self.headerHeight

        optionScroll.isHidden = !showsOptions
        if showsOptions {
            optionScroll.frame = CGRect(x: x, y: y, width: width, height: Self.optionsHeight)
            optionStack.frame = CGRect(x: 0, y: 2, width: optionStack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width, height: Self.optionsHeight - 8)
            optionScroll.contentSize = CGSize(width: optionStack.frame.width, height: Self.optionsHeight)
            y += Self.optionsHeight
        }

        let barY = contentBottom - Self.barHeight
        contentScroll.frame = CGRect(x: x + Self.sideInset, y: y, width: width - Self.sideInset * 2, height: max(0, barY - y))
        let contentWidth = contentScroll.bounds.width
        let contentHeight = contentStack.systemLayoutSizeFitting(CGSize(width: contentWidth, height: UIView.layoutFittingCompressedSize.height),
                                                                 withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        contentStack.frame = CGRect(x: 0, y: 4, width: contentWidth, height: contentHeight)
        contentScroll.contentSize = CGSize(width: contentWidth, height: contentHeight + 8)
        loadingView?.frame = CGRect(x: 0, y: 0, width: contentWidth, height: contentScroll.bounds.height)

        let barH = Self.barHeight - 6
        lettersButton.frame = CGRect(x: x + Self.sideInset, y: barY + 3, width: 52, height: barH)
        let undoWidth: CGFloat = undoButton.isHidden ? 0 : 120
        undoButton.frame = CGRect(x: lettersButton.frame.maxX + 8, y: barY + 3, width: undoWidth, height: barH)
        settingsButton.frame = CGRect(x: x + width - Self.sideInset - 36, y: barY + 3, width: 36, height: barH)
        let labelMaxX = settingsButton.frame.minX - 4
        let labelMinX = undoButton.frame.maxX + 8
        modelLabel.frame = CGRect(x: labelMinX, y: barY + 3, width: max(0, labelMaxX - labelMinX), height: barH)
    }

    // MARK: Chips

    private func makeChip(title: String, symbol: String?, size: CGFloat) -> UIButton {
        let b = UIButton(type: .custom)
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        if let symbol {
            config.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: size - 2, weight: .semibold))
            config.imagePadding = 5
        }
        var t = AttributedString(title)
        t.font = .systemFont(ofSize: size, weight: .medium)
        config.attributedTitle = t
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)
        b.configuration = config
        b.layer.cornerCurve = .continuous
        return b
    }

    private func style(_ b: UIButton, selected: Bool) {
        guard var config = b.configuration else { return }
        config.baseBackgroundColor = selected ? theme.accent : theme.functionKeyBackground
        config.baseForegroundColor = selected ? theme.onAccent : theme.keyText
        b.configuration = config
        b.accessibilityTraits = selected ? [.button, .selected] : .button
    }

    private func renderChips() {
        for (i, b) in featureButtons.enumerated() {
            style(b, selected: AIFeature.allCases[i] == feature)
        }
    }

    private func renderOptions() {
        optionStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        optionButtons = []
        let titles: [String]
        let selected: Int
        switch feature {
        case .rewrite:
            titles = AIRewriteTone.allCases.map(\.title)
            selected = AIRewriteTone.allCases.firstIndex(of: tone) ?? 0
        case .translate:
            titles = AITranslationTarget.allCases.map(\.title)
            selected = AITranslationTarget.allCases.firstIndex(of: target) ?? 0
        default:
            setNeedsLayout()
            return
        }
        for (i, title) in titles.enumerated() {
            let b = makeChip(title: title, symbol: nil, size: 13)
            b.tag = i
            b.accessibilityIdentifier = "ai-option-\(i)"
            b.addTarget(self, action: #selector(optionTapped(_:)), for: .touchUpInside)
            style(b, selected: i == selected)
            optionStack.addArrangedSubview(b)
            optionButtons.append(b)
        }
        setNeedsLayout()
    }

    // MARK: Content

    private func clearContent() {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        loadingView?.removeFromSuperview()
        loadingView = nil
    }

    private func renderContent() {
        clearContent()
        switch phase {
        case .idle:
            let title: String
            let detail: String
            if let source = sourcePreview, !source.isEmpty {
                title = feature == nil ? "Was soll die KI tun?" : "Bereit."
                detail = (isSelection ? "Auswahl: „" : "Text: „") + Self.preview(source) + "“"
            } else {
                title = "Erst etwas schreiben."
                detail = "Die KI bearbeitet die Auswahl oder den Text vor dem Cursor."
            }
            contentStack.addArrangedSubview(makeMessage(symbol: "sparkles", title: title, detail: detail, tint: theme.accent))
        case .loading:
            let v = LoadingView(theme: theme, feature: feature)
            contentScroll.addSubview(v)
            loadingView = v
        case .results(let items):
            for (i, item) in items.enumerated() {
                let card = ResultCard(theme: theme, text: item, action: feature?.applyLabel ?? "Einsetzen", tag: i)
                card.accessibilityIdentifier = "ai-result-\(i)"
                card.addTarget(self, action: #selector(resultTapped(_:)), for: .touchUpInside)
                contentStack.addArrangedSubview(card)
                card.alpha = 0
                card.transform = CGAffineTransform(translationX: 0, y: 8)
                UIView.animate(withDuration: 0.28, delay: 0.05 * Double(i), options: [.curveEaseOut, .allowUserInteraction]) {
                    card.alpha = 1
                    card.transform = .identity
                }
            }
        case .failed(let error):
            let message = makeMessage(symbol: error.needsSetup ? "key" : "exclamationmark.triangle",
                                      title: error.errorDescription ?? "Fehler",
                                      detail: error.needsSetup ? "API-Schlüssel und Modell legst du in der Umlaut-App unter Einstellungen › KI fest." : "Tippe auf die Funktion, um es noch einmal zu versuchen.",
                                      tint: error.needsSetup ? theme.accent : theme.keyText)
            contentStack.addArrangedSubview(message)
            if error.needsSetup {
                let b = makeChip(title: "In der App einrichten", symbol: "arrow.up.forward.app", size: 14)
                b.accessibilityIdentifier = "ai-open-settings"
                style(b, selected: true)
                b.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
                let row = UIStackView(arrangedSubviews: [b, UIView()])
                row.axis = .horizontal
                contentStack.addArrangedSubview(row)
            }
        }
        setNeedsLayout()
        layoutIfNeeded()
    }

    private func makeMessage(symbol: String, title: String, detail: String, tint: UIColor) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)))
        icon.tintColor = tint
        icon.contentMode = .center
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.widthAnchor.constraint(equalToConstant: 30).isActive = true
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = theme.keyText
        titleLabel.numberOfLines = 2
        let detailLabel = UILabel()
        detailLabel.text = detail
        detailLabel.font = .systemFont(ofSize: 13)
        detailLabel.textColor = theme.hintText
        detailLabel.numberOfLines = 3
        let texts = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        texts.axis = .vertical
        texts.spacing = 3
        let row = UIStackView(arrangedSubviews: [icon, texts])
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = 8
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 8, left: 6, bottom: 8, right: 6)
        return row
    }

    private static func preview(_ text: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        return flat.count > 90 ? "…" + flat.suffix(88) : flat
    }

    // MARK: Actions

    @objc private func featureTapped(_ sender: UIButton) {
        let f = AIFeature.allCases[sender.tag]
        select(f)
    }

    @objc private func optionTapped(_ sender: UIButton) {
        switch feature {
        case .rewrite: tone = AIRewriteTone.allCases[sender.tag]
        case .translate: target = AITranslationTarget.allCases[sender.tag]
        default: return
        }
        for (i, b) in optionButtons.enumerated() { style(b, selected: i == sender.tag) }
        if let feature { delegate?.aiPanel(self, didRequest: feature, tone: tone, target: target) }
    }

    @objc private func resultTapped(_ sender: UIControl) {
        guard case .results(let items) = phase, items.indices.contains(sender.tag) else { return }
        delegate?.aiPanel(self, didPick: items[sender.tag])
    }

    @objc private func lettersTapped() { delegate?.aiPanelDidTapLetters(self) }
    @objc private func undoTapped() { delegate?.aiPanelDidTapUndo(self) }
    @objc private func settingsTapped() { delegate?.aiPanelDidTapSettings(self) }

    // MARK: Subviews

    /// One result: the text and, bottom right, what a tap does.
    final class ResultCard: UIControl {
        private let label = UILabel()
        private let hint = UILabel()
        private let theme: KeyboardTheme

        init(theme: KeyboardTheme, text: String, action: String, tag: Int) {
            self.theme = theme
            super.init(frame: .zero)
            self.tag = tag
            isAccessibilityElement = true
            accessibilityLabel = text
            accessibilityHint = action
            accessibilityTraits = .button
            backgroundColor = theme.keyBackground
            layer.cornerCurve = .continuous
            layer.cornerRadius = 12
            layer.borderWidth = 0.5
            layer.borderColor = theme.popupRim.cgColor
            label.text = text
            label.font = .systemFont(ofSize: 15)
            label.textColor = theme.keyText
            label.numberOfLines = 0
            label.isUserInteractionEnabled = false
            addSubview(label)
            hint.text = action + "  ↩"
            hint.font = .systemFont(ofSize: 12, weight: .semibold)
            hint.textColor = theme.accent
            hint.isUserInteractionEnabled = false
            addSubview(hint)
            addTarget(self, action: #selector(down), for: [.touchDown, .touchDragEnter])
            addTarget(self, action: #selector(up), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
        }

        required init?(coder: NSCoder) { fatalError() }

        override var intrinsicContentSize: CGSize {
            let width = bounds.width > 0 ? bounds.width : 300
            let textHeight = label.sizeThatFits(CGSize(width: width - 24, height: .greatestFiniteMagnitude)).height
            return CGSize(width: UIView.noIntrinsicMetric, height: min(textHeight, 140) + 12 + 22)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            let textHeight = min(label.sizeThatFits(CGSize(width: bounds.width - 24, height: .greatestFiniteMagnitude)).height, 140)
            label.frame = CGRect(x: 12, y: 9, width: bounds.width - 24, height: textHeight)
            hint.frame = CGRect(x: 12, y: bounds.height - 22, width: bounds.width - 24, height: 16)
            hint.textAlignment = .right
            invalidateIntrinsicContentSize()
        }

        @objc private func down() { backgroundColor = theme.keyPressedBackground }
        @objc private func up() {
            UIView.animate(withDuration: 0.18) { self.backgroundColor = self.theme.keyBackground }
        }
    }

    /// "Denkt nach…" with three breathing dots.
    final class LoadingView: UIView {
        private let label = UILabel()
        private let dots: [UIView] = (0..<3).map { _ in UIView() }
        private let icon = UIImageView()

        init(theme: KeyboardTheme, feature: AIFeature?) {
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            icon.image = UIImage(systemName: "sparkles", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .medium))
            icon.tintColor = theme.accent
            icon.contentMode = .center
            addSubview(icon)
            label.text = Self.title(for: feature)
            label.font = .systemFont(ofSize: 15, weight: .medium)
            label.textColor = theme.keyText
            label.textAlignment = .center
            addSubview(label)
            for (i, d) in dots.enumerated() {
                d.backgroundColor = theme.accent
                d.layer.cornerRadius = 3
                addSubview(d)
                let a = CABasicAnimation(keyPath: "opacity")
                a.fromValue = 0.25
                a.toValue = 1
                a.duration = 0.5
                a.autoreverses = true
                a.repeatCount = .infinity
                a.beginTime = CACurrentMediaTime() + Double(i) * 0.16
                d.layer.add(a, forKey: "breathe")
            }
            let pulse = CABasicAnimation(keyPath: "transform.scale")
            pulse.fromValue = 0.9
            pulse.toValue = 1.1
            pulse.duration = 0.6
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            icon.layer.add(pulse, forKey: "pulse")
        }

        required init?(coder: NSCoder) { fatalError() }

        private static func title(for feature: AIFeature?) -> String {
            switch feature {
            case .proofread: return "Prüft den Text…"
            case .rewrite: return "Formuliert um…"
            case .continueWriting: return "Denkt weiter…"
            case .translate: return "Übersetzt…"
            case .answer: return "Antwortet…"
            case nil: return "Denkt nach…"
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            let midY = bounds.midY
            icon.frame = CGRect(x: bounds.midX - 15, y: midY - 34, width: 30, height: 30)
            label.frame = CGRect(x: 0, y: midY, width: bounds.width, height: 20)
            let spacing: CGFloat = 12
            let startX = bounds.midX - spacing
            for (i, d) in dots.enumerated() {
                d.frame = CGRect(x: startX + CGFloat(i) * spacing - 3, y: midY + 26, width: 6, height: 6)
            }
        }
    }
}
