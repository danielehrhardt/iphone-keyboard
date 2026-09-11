import UIKit
import KeyboardCore

protocol EmojiPanelDelegate: AnyObject {
    func emojiPanel(_ panel: EmojiPanelView, didPick emoji: String)
    func emojiPanelDidTapBackspace(_ panel: EmojiPanelView)
    func emojiPanelDidTapLetters(_ panel: EmojiPanelView)
}

/// Emoji picker: a horizontally paged grid per category with a category bar underneath.
final class EmojiPanelView: UIView, UICollectionViewDataSource, UICollectionViewDelegate {
    weak var delegate: EmojiPanelDelegate?
    private var theme: KeyboardTheme
    private let collection: UICollectionView
    private let categoryBar = UIStackView()
    private let titleLabel = UILabel()
    private var categoryButtons: [UIButton] = []
    private var sections: [EmojiData.Category] = []
    private let defaults = UserDefaults(suiteName: KeyboardSettings.appGroup) ?? .standard
    private static let recentsKey = "recentEmoji"

    init(theme: KeyboardTheme) {
        self.theme = theme
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        layout.sectionInset = UIEdgeInsets(top: 4, left: 6, bottom: 8, right: 6)
        layout.headerReferenceSize = CGSize(width: 0, height: 22)
        collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: .zero)
        rebuildSections()
        collection.register(EmojiCell.self, forCellWithReuseIdentifier: "cell")
        collection.register(HeaderView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "header")
        collection.dataSource = self
        collection.delegate = self
        collection.backgroundColor = .clear
        collection.showsVerticalScrollIndicator = false
        addSubview(collection)

        categoryBar.axis = .horizontal
        categoryBar.distribution = .fillEqually
        categoryBar.alignment = .fill
        addSubview(categoryBar)
        buildCategoryBar()
        apply(theme: theme)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func rebuildSections() {
        let recents = defaults.stringArray(forKey: Self.recentsKey) ?? []
        var s = EmojiData.categories
        if !recents.isEmpty { s.insert(EmojiData.Category(title: "Zuletzt verwendet", symbol: "clock", emoji: recents), at: 0) }
        sections = s
    }

    private func buildCategoryBar() {
        categoryBar.arrangedSubviews.forEach { $0.removeFromSuperview() }
        categoryButtons = []
        let abc = makeBarButton(title: "ABC", symbol: nil)
        abc.addTarget(self, action: #selector(lettersTapped), for: .touchUpInside)
        categoryBar.addArrangedSubview(abc)
        for (i, cat) in sections.enumerated() {
            let b = makeBarButton(title: nil, symbol: cat.symbol)
            b.tag = i
            b.accessibilityLabel = cat.title
            b.addTarget(self, action: #selector(categoryTapped(_:)), for: .touchUpInside)
            categoryBar.addArrangedSubview(b)
            categoryButtons.append(b)
        }
        let del = makeBarButton(title: nil, symbol: "delete.left")
        del.addTarget(self, action: #selector(backspaceTapped), for: .touchUpInside)
        categoryBar.addArrangedSubview(del)
    }

    private func makeBarButton(title: String?, symbol: String?) -> UIButton {
        let b = UIButton(type: .system)
        if let title { b.setTitle(title, for: .normal); b.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium) }
        if let symbol { b.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)), for: .normal) }
        return b
    }

    func apply(theme: KeyboardTheme) {
        self.theme = theme
        backgroundColor = theme.background
        categoryBar.arrangedSubviews.forEach { ($0 as? UIButton)?.tintColor = theme.functionKeyText.withAlphaComponent(0.8) }
        collection.reloadData()
    }

    func refreshRecents() {
        rebuildSections()
        buildCategoryBar()
        collection.reloadData()
        collection.setContentOffset(.zero, animated: false)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let barHeight: CGFloat = 40
        collection.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height - barHeight)
        categoryBar.frame = CGRect(x: 4, y: bounds.height - barHeight, width: bounds.width - 8, height: barHeight - 2)
        if let layout = collection.collectionViewLayout as? UICollectionViewFlowLayout {
            let columns: CGFloat = traitCollection.userInterfaceIdiom == .pad ? 12 : 8
            let side = floor((bounds.width - 12) / columns)
            layout.itemSize = CGSize(width: side, height: side)
        }
    }

    // MARK: Actions

    @objc private func lettersTapped() { delegate?.emojiPanelDidTapLetters(self) }
    @objc private func backspaceTapped() { delegate?.emojiPanelDidTapBackspace(self) }
    @objc private func categoryTapped(_ sender: UIButton) {
        guard sender.tag < sections.count else { return }
        let indexPath = IndexPath(item: 0, section: sender.tag)
        if let attrs = collection.layoutAttributesForSupplementaryElement(ofKind: UICollectionView.elementKindSectionHeader, at: indexPath) {
            let y = min(attrs.frame.minY, max(0, collection.contentSize.height - collection.bounds.height))
            collection.setContentOffset(CGPoint(x: 0, y: y), animated: true)
        }
    }

    private func remember(_ emoji: String) {
        var recents = defaults.stringArray(forKey: Self.recentsKey) ?? []
        recents.removeAll { $0 == emoji }
        recents.insert(emoji, at: 0)
        defaults.set(Array(recents.prefix(32)), forKey: Self.recentsKey)
    }

    // MARK: Collection view

    func numberOfSections(in collectionView: UICollectionView) -> Int { sections.count }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { sections[section].emoji.count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! EmojiCell
        cell.label.text = sections[indexPath.section].emoji[indexPath.item]
        cell.highlightColor = theme.suggestionHighlight
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        let h = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "header", for: indexPath) as! HeaderView
        h.label.text = sections[indexPath.section].title.uppercased()
        h.label.textColor = theme.hintText
        return h
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let e = sections[indexPath.section].emoji[indexPath.item]
        remember(e)
        delegate?.emojiPanel(self, didPick: e)
    }

    final class EmojiCell: UICollectionViewCell {
        let label = UILabel()
        var highlightColor: UIColor = .clear
        override init(frame: CGRect) {
            super.init(frame: frame)
            label.font = .systemFont(ofSize: 30)
            label.textAlignment = .center
            label.adjustsFontSizeToFitWidth = true
            contentView.addSubview(label)
            contentView.layer.cornerRadius = 8
        }
        required init?(coder: NSCoder) { fatalError() }
        override func layoutSubviews() { super.layoutSubviews(); label.frame = contentView.bounds }
        override var isHighlighted: Bool { didSet { contentView.backgroundColor = isHighlighted ? highlightColor : .clear } }
    }

    final class HeaderView: UICollectionReusableView {
        let label = UILabel()
        override init(frame: CGRect) {
            super.init(frame: frame)
            label.font = .systemFont(ofSize: 11, weight: .semibold)
            addSubview(label)
        }
        required init?(coder: NSCoder) { fatalError() }
        override func layoutSubviews() { super.layoutSubviews(); label.frame = bounds.insetBy(dx: 10, dy: 0) }
    }
}
