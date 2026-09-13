import UIKit
import KeyboardCore

protocol ClipboardPanelDelegate: AnyObject {
    func clipboardPanel(_ panel: ClipboardPanelView, didPick item: ClipboardItem)
    func clipboardPanel(_ panel: ClipboardPanelView, didDelete item: ClipboardItem)
    func clipboardPanelDidTapClear(_ panel: ClipboardPanelView)
    func clipboardPanelDidTapLetters(_ panel: ClipboardPanelView)
}

/// The clipboard history inside the keyboard: a bar with "ABC", the title and "Löschen" on
/// top, below it one row per copied item (text on two lines, images as a thumbnail). A tap
/// on a row types the text or puts the image back on the pasteboard; the "×" removes it.
final class ClipboardPanelView: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    weak var delegate: ClipboardPanelDelegate?
    /// Hands out the preview image of an image item (cached by the owner).
    var thumbnailProvider: ((ClipboardItem) -> UIImage?)?

    private var theme: KeyboardTheme
    private let collection: UICollectionView
    private let topBar = UIView()
    private let lettersButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let clearButton = UIButton(type: .system)
    private let emptyLabel = UILabel()
    private let hintLabel = UILabel()
    private var hintTimer: Timer?
    private var clearArmedUntil: CFTimeInterval = 0
    private(set) var items: [ClipboardItem] = []
    /// Shown instead of the list when the history cannot be used (no full access, switched off).
    var notice: String? { didSet { if notice != oldValue { updateEmptyState() } } }

    static let barHeight: CGFloat = 40
    static let rowHeight: CGFloat = 56
    static let rowSpacing: CGFloat = 6

    init(theme: KeyboardTheme) {
        self.theme = theme
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = Self.rowSpacing
        layout.sectionInset = UIEdgeInsets(top: 2, left: 8, bottom: 8, right: 8)
        collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: .zero)
        accessibilityIdentifier = "clipboard-panel"
        backgroundColor = .clear
        collection.register(ItemCell.self, forCellWithReuseIdentifier: "item")
        collection.dataSource = self
        collection.delegate = self
        collection.backgroundColor = .clear
        collection.alwaysBounceVertical = true
        collection.showsVerticalScrollIndicator = false
        collection.keyboardDismissMode = .none
        addSubview(collection)

        addSubview(topBar)
        lettersButton.setTitle("ABC", for: .normal)
        lettersButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        lettersButton.accessibilityIdentifier = "clipboard-letters"
        lettersButton.accessibilityLabel = "Zurück zur Tastatur"
        lettersButton.addTarget(self, action: #selector(lettersTapped), for: .touchUpInside)
        topBar.addSubview(lettersButton)
        titleLabel.text = "Zwischenablage"
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textAlignment = .center
        topBar.addSubview(titleLabel)
        clearButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        clearButton.accessibilityIdentifier = "clipboard-clear"
        clearButton.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)
        topBar.addSubview(clearButton)

        emptyLabel.font = .systemFont(ofSize: 14)
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.isHidden = true
        addSubview(emptyLabel)

        hintLabel.font = .systemFont(ofSize: 13, weight: .medium)
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 2
        hintLabel.layer.cornerCurve = .continuous
        hintLabel.layer.cornerRadius = 10
        hintLabel.clipsToBounds = true
        hintLabel.alpha = 0
        hintLabel.isUserInteractionEnabled = false
        addSubview(hintLabel)
        setClearArmed(false)
        apply(theme: theme)
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(theme: KeyboardTheme) {
        self.theme = theme
        lettersButton.tintColor = theme.functionKeyText.withAlphaComponent(0.85)
        titleLabel.textColor = theme.keyText
        clearButton.tintColor = theme.functionKeyText.withAlphaComponent(0.85)
        emptyLabel.textColor = theme.hintText
        hintLabel.backgroundColor = theme.popupBackground
        hintLabel.textColor = theme.keyText
        collection.reloadData()
    }

    /// Replaces the list; keeps the scroll position when only the content changed.
    func set(items new: [ClipboardItem]) {
        guard new != items else { return }
        items = new
        collection.reloadData()
        updateEmptyState()
    }

    func scrollToTop() { collection.setContentOffset(.zero, animated: false) }

    /// A short message at the bottom of the list (e.g. "Bild kopiert …").
    func showHint(_ text: String, duration: TimeInterval = 3) {
        hintLabel.text = text
        setNeedsLayout()
        hintTimer?.invalidate()
        UIView.animate(withDuration: 0.18) { self.hintLabel.alpha = 1 }
        hintTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            UIView.animate(withDuration: 0.25) { self?.hintLabel.alpha = 0 }
        }
    }

    private func updateEmptyState() {
        if let notice {
            emptyLabel.text = notice
        } else {
            emptyLabel.text = "Noch nichts kopiert.\nKopierte Texte und Bilder erscheinen hier."
        }
        let showsEmpty = items.isEmpty || notice != nil
        emptyLabel.isHidden = !showsEmpty
        collection.isHidden = notice != nil
        clearButton.isHidden = items.isEmpty
        setClearArmed(false)
    }

    private func setClearArmed(_ armed: Bool) {
        clearArmedUntil = armed ? CACurrentMediaTime() + 3 : 0
        clearButton.setTitle(armed ? "Alle löschen?" : "Löschen", for: .normal)
        clearButton.tintColor = armed ? .systemRed : theme.functionKeyText.withAlphaComponent(0.85)
        clearButton.accessibilityLabel = armed ? "Alle Einträge löschen, zum Bestätigen erneut tippen" : "Verlauf löschen"
        setNeedsLayout()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let insets = safeAreaInsets
        let width = max(0, bounds.width - insets.left - insets.right)
        let contentHeight = max(0, bounds.height - insets.bottom)
        topBar.frame = CGRect(x: insets.left, y: 0, width: width, height: Self.barHeight)
        lettersButton.frame = CGRect(x: 6, y: 0, width: 56, height: Self.barHeight)
        let clearWidth = clearButton.intrinsicContentSize.width + 16
        clearButton.frame = CGRect(x: width - 6 - clearWidth, y: 0, width: clearWidth, height: Self.barHeight)
        titleLabel.frame = CGRect(x: 62, y: 0, width: max(0, width - 124), height: Self.barHeight)
        collection.frame = CGRect(x: insets.left, y: Self.barHeight, width: width, height: max(0, contentHeight - Self.barHeight))
        emptyLabel.frame = CGRect(x: insets.left + 24, y: Self.barHeight, width: max(0, width - 48), height: max(0, contentHeight - Self.barHeight))
        if let layout = collection.collectionViewLayout as? UICollectionViewFlowLayout {
            let itemWidth = max(0, width - layout.sectionInset.left - layout.sectionInset.right)
            if layout.itemSize.width != itemWidth {
                layout.itemSize = CGSize(width: itemWidth, height: Self.rowHeight)
                layout.invalidateLayout()
            }
        }
        let hintWidth = min(width - 32, 360)
        let hintHeight: CGFloat = 40
        hintLabel.frame = CGRect(x: insets.left + (width - hintWidth) / 2, y: contentHeight - hintHeight - 10, width: hintWidth, height: hintHeight)
    }

    // MARK: Actions

    @objc private func lettersTapped() { delegate?.clipboardPanelDidTapLetters(self) }

    /// First tap arms the button, a second one within three seconds clears the history.
    @objc private func clearTapped() {
        if CACurrentMediaTime() < clearArmedUntil {
            setClearArmed(false)
            delegate?.clipboardPanelDidTapClear(self)
        } else {
            setClearArmed(true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.1) { [weak self] in
                guard let self, CACurrentMediaTime() >= self.clearArmedUntil else { return }
                self.setClearArmed(false)
            }
        }
    }

    // MARK: Collection view

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { items.count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "item", for: indexPath) as! ItemCell
        let item = items[indexPath.item]
        cell.configure(item: item, thumbnail: item.kind == .image ? thumbnailProvider?(item) : nil, theme: theme)
        cell.onDelete = { [weak self] in
            guard let self, let item = self.items.first(where: { $0.id == item.id }) else { return }
            self.delegate?.clipboardPanel(self, didDelete: item)
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard items.indices.contains(indexPath.item) else { return }
        delegate?.clipboardPanel(self, didPick: items[indexPath.item])
    }

    // MARK: Cell

    final class ItemCell: UICollectionViewCell {
        private let iconView = UIImageView()
        private let textLabel = UILabel()
        private let timeLabel = UILabel()
        private let deleteButton = UIButton(type: .system)
        private var highlightColor: UIColor = .clear
        private var normalColor: UIColor = .clear
        var onDelete: (() -> Void)?

        private static let relative: RelativeDateTimeFormatter = {
            let f = RelativeDateTimeFormatter()
            f.unitsStyle = .short
            return f
        }()

        override init(frame: CGRect) {
            super.init(frame: frame)
            contentView.layer.cornerCurve = .continuous
            contentView.layer.cornerRadius = 12
            iconView.contentMode = .scaleAspectFill
            iconView.clipsToBounds = true
            iconView.layer.cornerCurve = .continuous
            iconView.layer.cornerRadius = 8
            contentView.addSubview(iconView)
            textLabel.font = .systemFont(ofSize: 15)
            textLabel.numberOfLines = 2
            textLabel.lineBreakMode = .byTruncatingTail
            contentView.addSubview(textLabel)
            timeLabel.font = .systemFont(ofSize: 11)
            contentView.addSubview(timeLabel)
            deleteButton.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)), for: .normal)
            deleteButton.accessibilityLabel = "Eintrag entfernen"
            deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
            contentView.addSubview(deleteButton)
        }

        required init?(coder: NSCoder) { fatalError() }

        func configure(item: ClipboardItem, thumbnail: UIImage?, theme: KeyboardTheme) {
            normalColor = theme.keyBackground
            highlightColor = theme.keyPressedBackground
            contentView.backgroundColor = normalColor
            textLabel.textColor = theme.keyText
            timeLabel.textColor = theme.hintText
            deleteButton.tintColor = theme.hintText
            switch item.kind {
            case .text:
                iconView.image = UIImage(systemName: "text.alignleft", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .regular))
                iconView.contentMode = .center
                iconView.tintColor = theme.hintText
                iconView.backgroundColor = theme.functionKeyBackground
                textLabel.text = item.preview
            case .image:
                if let thumbnail {
                    iconView.image = thumbnail
                    iconView.contentMode = .scaleAspectFill
                    iconView.backgroundColor = .clear
                } else {
                    iconView.image = UIImage(systemName: "photo", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .regular))
                    iconView.contentMode = .center
                    iconView.backgroundColor = theme.functionKeyBackground
                }
                iconView.tintColor = theme.hintText
                textLabel.text = item.preview
            }
            timeLabel.text = Self.relative.localizedString(for: item.createdAt, relativeTo: Date())
            accessibilityIdentifier = "clipboard-item"
            isAccessibilityElement = false
            contentView.isAccessibilityElement = true
            contentView.accessibilityLabel = (item.kind == .image ? "Bild, " : "") + item.preview + ", " + (timeLabel.text ?? "")
            contentView.accessibilityTraits = .button
            setNeedsLayout()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            let b = contentView.bounds
            let icon: CGFloat = 40
            iconView.frame = CGRect(x: 8, y: (b.height - icon) / 2, width: icon, height: icon)
            deleteButton.frame = CGRect(x: b.width - 40, y: 0, width: 40, height: b.height)
            let textX = iconView.frame.maxX + 10
            let textWidth = max(0, deleteButton.frame.minX - textX - 4)
            timeLabel.frame = CGRect(x: textX, y: b.height - 18, width: textWidth, height: 14)
            textLabel.frame = CGRect(x: textX, y: 4, width: textWidth, height: b.height - 24)
        }

        override var isHighlighted: Bool {
            didSet { contentView.backgroundColor = isHighlighted ? highlightColor : normalColor }
        }

        @objc private func deleteTapped() { onDelete?() }
    }
}
