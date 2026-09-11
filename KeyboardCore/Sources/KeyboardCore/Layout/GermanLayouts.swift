import Foundation
import CoreGraphics

/// Picks the layout family for the language in `options`.
public enum KeyboardLayouts {
    public static func layout(for layer: KeyboardLayer, options: LayoutOptions = LayoutOptions()) -> KeyboardLayout {
        switch options.language {
        case .german: return GermanLayouts.layout(for: layer, options: options)
        case .english: return EnglishLayouts.layout(for: layer, options: options)
        }
    }

    public static func letters(options: LayoutOptions = LayoutOptions()) -> KeyboardLayout {
        layout(for: .letters, options: options)
    }
}

/// Keys and rows every layout family shares: the function keys, the symbol layers' digit and
/// punctuation rows, the numeric pads and the bottom row.
enum LayoutParts {
    static let shift = Key(id: "shift", action: .shift, label: "⇧", width: 1.5, isFunction: true, symbolName: "shift")
    static let backspace = Key(id: "backspace", action: .backspace, label: "⌫", width: 1.5, isFunction: true, symbolName: "delete.left")
    static let newline = Key(id: "return", action: .newline, label: "Return", width: 2.2, isFunction: true, symbolName: "return")
    static let globe = Key(id: "globe", action: .globe, label: "🌐", width: 1.25, isFunction: true, symbolName: "globe")
    static let emoji = Key(id: "emoji", action: .emoji, label: "☺", width: 1.25, isFunction: true, symbolName: "face.smiling")
    static let toSymbols = Key(id: "123", action: .switchLayer(.symbols), label: "123", width: 1.5, isFunction: true)
    static let toLetters = Key(id: "ABC", action: .switchLayer(.letters), label: "ABC", width: 1.5, isFunction: true)
    static let toExtra = Key(id: "#+=", action: .switchLayer(.extraSymbols), label: "#+=", width: symbolFunctionWidth, isFunction: true)
    static let toSymbolsFromExtra = Key(id: "123b", action: .switchLayer(.symbols), label: "123", width: symbolFunctionWidth, isFunction: true)
    /// Punctuation row of the symbol layers: five keys framed by the layer switch and backspace,
    /// sized so the row spans the full width like the system keyboard.
    static let punctuationWidth: CGFloat = 1.35
    static let symbolFunctionWidth: CGFloat = 1.25
    static let symbolBackspace = Key(id: "backspace", action: .backspace, label: "⌫", width: symbolFunctionWidth, isFunction: true, symbolName: "delete.left")
    static let period = Key.symbol(".", alternates: ["…", ",", "?", "!", ";", ":"])
    static let comma = Key(id: "comma", action: .character(","), label: ",", alternates: [";", ":"], width: 1)
    /// Comma key that doubles as the emoji key: tap types ",", holding opens the emoji picker.
    /// Same id as `comma` so the key view (and UI tests) keep addressing it as the comma key.
    static let commaEmoji = Key(id: "comma", action: .character(","), label: ",", width: 1, longPressAction: .emoji)

    static let superscripts: [String: [String]] = [
        "1": ["¹", "½", "⅓", "¼"], "2": ["²", "⅔"], "3": ["³", "¾"], "0": ["°", "⁰"], "5": ["⁵"], "7": ["⁷"],
    ]

    static let digitRow: [Key] = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"].map { Key.symbol($0, alternates: superscripts[$0] ?? []) }

    static let punctuationRow: [Key] = [
        .symbol(".", id: "sym.", alternates: ["…"], width: punctuationWidth),
        .symbol(",", id: "sym,", alternates: [";"], width: punctuationWidth),
        .symbol("?", id: "sym?", alternates: ["¿"], width: punctuationWidth),
        .symbol("!", id: "sym!", alternates: ["¡"], width: punctuationWidth),
        .symbol("'", id: "sym'", alternates: ["‚", "‘", "’", "‹", "›", "`", "´"], width: punctuationWidth),
    ]

    static let extraRow1: [Key] = [
        .symbol("["), .symbol("]"), .symbol("{"), .symbol("}"), .symbol("#"), .symbol("%", alternates: ["‰"]), .symbol("^"),
        .symbol("*"), .symbol("+"), .symbol("=", alternates: ["≠", "≈"]),
    ]

    /// The space bar. Shows the language's name while several languages are enabled, so people
    /// see what they are typing in – like the system keyboard does.
    static func space(options: LayoutOptions) -> Key {
        let label = options.showsLanguageName ? options.language.title : options.language.spaceLabel
        return Key(id: "space", action: .space, label: label, width: 1)
    }

    // MARK: Numeric pads

    static func numberPad(kind: KeyboardLayer, needsGlobeKey: Bool, decimalSeparator: String) -> KeyboardLayout {
        func d(_ s: String) -> Key { Key(action: .character(s), label: s, width: 1) }
        var bottomLeft: Key
        switch kind {
        case .decimalPad: bottomLeft = Key(id: "decimal", action: .character(decimalSeparator), label: decimalSeparator, width: 1)
        case .phonePad: bottomLeft = Key(id: "plus", action: .character("+"), label: "+ * #", alternates: ["*", "#", ";", ","], width: 1)
        default: bottomLeft = needsGlobeKey
            ? Key(id: "globe", action: .globe, label: "🌐", width: 1, isFunction: true, symbolName: "globe")
            : Key(id: "pad-dismiss", action: .dismiss, label: "", width: 1, isFunction: true, symbolName: "keyboard.chevron.compact.down")
        }
        let rows = [
            KeyRow([d("1"), d("2"), d("3")]),
            KeyRow([d("4"), d("5"), d("6")]),
            KeyRow([d("7"), d("8"), d("9")]),
            KeyRow([bottomLeft, d("0"), Key(id: "backspace", action: .backspace, label: "⌫", width: 1, isFunction: true, symbolName: "delete.left")]),
        ]
        return KeyboardLayout(layer: kind, rows: rows, columns: 3)
    }

    // MARK: Bottom row

    static func bottomRow(options: LayoutOptions, layerSwitch: Key) -> KeyRow {
        var keys: [Key] = [layerSwitch]
        let showsComma = options.showsCommaKey && !options.isEmailOrURL
        // With the emoji key folded into the comma key there is no separate emoji key; without a
        // comma key (or in e-mail fields, where "@" replaces it) the separate key comes back.
        let emojiOnComma = options.showsEmojiKey && options.emojiOnCommaKey && showsComma
        if options.needsGlobeKey { keys.append(globe) }
        if options.showsEmojiKey && !options.needsGlobeKey && !emojiOnComma { keys.append(emoji) }
        if options.isEmailOrURL {
            keys.append(Key(id: "at", action: .character("@"), label: "@", width: 1))
        } else if showsComma {
            keys.append(emojiOnComma ? commaEmoji : comma)
        }
        keys.append(space(options: options))
        if options.isEmailOrURL {
            let domains = options.language == .german ? ["de", "com", "net", "org", "eu"] : ["com", "net", "org", "edu", "co.uk"]
            keys.append(Key(id: "dot", action: .character("."), label: ".", alternates: domains, width: 1))
        } else {
            keys.append(period)
        }
        keys.append(newline)
        return KeyRow(keys)
    }
}

/// The German QWERTZ layout family, matching what German iPhone users expect
/// (ü/ö/ä as first-class keys, ß via long-press on s, y and z swapped vs. QWERTY).
public enum GermanLayouts {

    // MARK: Letters

    public static let letterRows: [[Key]] = [
        [
            .letter("q"), .letter("w"), .letter("e", alternates: ["è", "é", "ê", "ë", "ę", "ė", "ē", "€"]),
            .letter("r"), .letter("t", alternates: ["ţ", "ť", "ŧ"]), .letter("z", alternates: ["ž", "ź", "ż"]),
            .letter("u", alternates: ["ù", "ú", "û", "ū", "ů", "ű"]), .letter("i", alternates: ["ì", "í", "î", "ï", "ī", "ı"]),
            .letter("o", alternates: ["ò", "ó", "ô", "õ", "ø", "œ", "ō"]), .letter("p"), .letter("ü", alternates: ["ù", "ú", "û", "ū"]),
        ],
        [
            .letter("a", alternates: ["à", "á", "â", "ã", "å", "æ", "ā", "ą"]), .letter("s", alternates: ["ß", "ś", "š", "ş", "$"]),
            .letter("d", alternates: ["ď", "đ"]), .letter("f"), .letter("g", alternates: ["ğ", "ģ"]), .letter("h"),
            .letter("j"), .letter("k", alternates: ["ķ"]), .letter("l", alternates: ["ł", "ľ", "ļ"]),
            .letter("ö", alternates: ["ò", "ó", "ô", "ø", "œ"]), .letter("ä", alternates: ["à", "á", "â", "å", "æ"]),
        ],
        [
            .letter("y", alternates: ["ý", "ÿ"]), .letter("x"), .letter("c", alternates: ["ç", "ć", "č"]),
            .letter("v"), .letter("b"), .letter("n", alternates: ["ñ", "ń", "ň"]), .letter("m"),
        ],
    ]

    // Shared keys, kept here under their long-standing names.
    public static let shift = LayoutParts.shift
    public static let backspace = LayoutParts.backspace
    public static let space = Key(id: "space", action: .space, label: KeyboardLanguage.german.spaceLabel, width: 1)
    public static let newline = LayoutParts.newline
    public static let globe = LayoutParts.globe
    public static let emoji = LayoutParts.emoji
    public static let toSymbols = LayoutParts.toSymbols
    public static let toLetters = LayoutParts.toLetters
    public static let toExtra = LayoutParts.toExtra
    public static let period = LayoutParts.period
    public static let comma = LayoutParts.comma
    public static let commaEmoji = LayoutParts.commaEmoji

    /// Letters layer. Row 3 is centred with shift/backspace on the flanks like Apple's German keyboard.
    public static func letters(options: LayoutOptions = LayoutOptions()) -> KeyboardLayout {
        let row3 = KeyRow([shift] + letterRows[2] + [backspace], expandsFlankGaps: true)
        return KeyboardLayout(
            layer: .letters,
            rows: [KeyRow(letterRows[0]), KeyRow(letterRows[1]), row3, LayoutParts.bottomRow(options: options, layerSwitch: toSymbols)],
            columns: 11
        )
    }

    // MARK: Symbols

    static let symbolRows1: [[Key]] = [
        LayoutParts.digitRow,
        [.symbol("-", alternates: ["–", "—", "•"]), .symbol("/", alternates: ["\\"]), .symbol(":"), .symbol(";"), .symbol("("), .symbol(")"),
         .symbol("€", alternates: ["$", "£", "¥", "₩", "₽"]), .symbol("&", alternates: ["§"]), .symbol("@"), .symbol("\"", alternates: ["„", "“", "”", "«", "»"])],
        LayoutParts.punctuationRow,
    ]

    static let symbolRows2: [[Key]] = [
        LayoutParts.extraRow1,
        [.symbol("_"), .symbol("\\"), .symbol("|"), .symbol("~"), .symbol("<", alternates: ["≤"]), .symbol(">", alternates: ["≥"]), .symbol("$"), .symbol("£"), .symbol("¥"), .symbol("•", alternates: ["◦", "·"])],
    ]

    public static func symbols(options: LayoutOptions = LayoutOptions()) -> KeyboardLayout {
        KeyboardLayout(
            layer: .symbols,
            rows: [KeyRow(symbolRows1[0]), KeyRow(symbolRows1[1]),
                   KeyRow([toExtra] + symbolRows1[2] + [LayoutParts.symbolBackspace], expandsFlankGaps: true),
                   LayoutParts.bottomRow(options: options, layerSwitch: toLetters)],
            columns: 10
        )
    }

    public static func extraSymbols(options: LayoutOptions = LayoutOptions()) -> KeyboardLayout {
        KeyboardLayout(
            layer: .extraSymbols,
            rows: [KeyRow(symbolRows2[0]), KeyRow(symbolRows2[1]),
                   KeyRow([LayoutParts.toSymbolsFromExtra] + symbolRows1[2] + [LayoutParts.symbolBackspace], expandsFlankGaps: true),
                   LayoutParts.bottomRow(options: options, layerSwitch: toLetters)],
            columns: 10
        )
    }

    // MARK: Numeric pads

    public static func numberPad(kind: KeyboardLayer, needsGlobeKey: Bool) -> KeyboardLayout {
        LayoutParts.numberPad(kind: kind, needsGlobeKey: needsGlobeKey, decimalSeparator: ",")
    }

    public static func layout(for layer: KeyboardLayer, options: LayoutOptions = LayoutOptions()) -> KeyboardLayout {
        switch layer {
        case .letters: return letters(options: options)
        case .symbols: return symbols(options: options)
        case .extraSymbols: return extraSymbols(options: options)
        case .numberPad, .decimalPad, .phonePad: return numberPad(kind: layer, needsGlobeKey: options.needsGlobeKey)
        }
    }
}

extension Key {
    func renamed(_ newID: String) -> Key {
        Key(id: newID, action: action, label: label, alternates: alternates, width: width,
            isLetter: isLetter, isFunction: isFunction, symbolName: symbolName, longPressAction: longPressAction)
    }
}
