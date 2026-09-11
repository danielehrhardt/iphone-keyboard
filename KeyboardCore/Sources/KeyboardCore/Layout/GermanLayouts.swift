import Foundation
import CoreGraphics

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

    public static let shift = Key(id: "shift", action: .shift, label: "⇧", width: 1.5, isFunction: true, symbolName: "shift")
    public static let backspace = Key(id: "backspace", action: .backspace, label: "⌫", width: 1.5, isFunction: true, symbolName: "delete.left")
    public static let space = Key(id: "space", action: .space, label: "Leerzeichen", width: 1)
    public static let newline = Key(id: "return", action: .newline, label: "Return", width: 2.2, isFunction: true, symbolName: "return")
    public static let globe = Key(id: "globe", action: .globe, label: "🌐", width: 1.25, isFunction: true, symbolName: "globe")
    public static let emoji = Key(id: "emoji", action: .emoji, label: "☺", width: 1.25, isFunction: true, symbolName: "face.smiling")
    public static let toSymbols = Key(id: "123", action: .switchLayer(.symbols), label: "123", width: 1.5, isFunction: true)
    public static let toLetters = Key(id: "ABC", action: .switchLayer(.letters), label: "ABC", width: 1.5, isFunction: true)
    public static let toExtra = Key(id: "#+=", action: .switchLayer(.extraSymbols), label: "#+=", width: 1.5, isFunction: true)
    public static let period = Key.symbol(".", alternates: ["…", ",", "?", "!", ";", ":"])
    public static let comma = Key.symbol(",", alternates: [";", ":"])

    /// Letters layer. Row 3 is centred with shift/backspace on the flanks like Apple's German keyboard.
    public static func letters(options: LayoutOptions = LayoutOptions()) -> KeyboardLayout {
        let row3 = KeyRow([shift] + letterRows[2] + [backspace], leadingInset: 0, trailingInset: 0)
        return KeyboardLayout(
            layer: .letters,
            rows: [KeyRow(letterRows[0]), KeyRow(letterRows[1]), row3, bottomRow(options: options, layerSwitch: toSymbols)],
            columns: 11
        )
    }

    // MARK: Symbols

    static let symbolRows1: [[Key]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"].map { Key.symbol($0, alternates: superscripts[$0] ?? []) },
        [.symbol("-", alternates: ["–", "—", "•"]), .symbol("/", alternates: ["\\"]), .symbol(":"), .symbol(";"), .symbol("("), .symbol(")"),
         .symbol("€", alternates: ["$", "£", "¥", "₩", "₽"]), .symbol("&", alternates: ["§"]), .symbol("@"), .symbol("\"", alternates: ["„", "“", "”", "«", "»"])],
        [.symbol(".", alternates: ["…"]), .symbol(",", alternates: [";"]), .symbol("?", alternates: ["¿"]), .symbol("!", alternates: ["¡"]),
         .symbol("'", alternates: ["‚", "‘", "’", "‹", "›", "`", "´"])],
    ]

    static let symbolRows2: [[Key]] = [
        [.symbol("["), .symbol("]"), .symbol("{"), .symbol("}"), .symbol("#"), .symbol("%", alternates: ["‰"]), .symbol("^"), .symbol("*"), .symbol("+"), .symbol("=", alternates: ["≠", "≈"])],
        [.symbol("_"), .symbol("\\"), .symbol("|"), .symbol("~"), .symbol("<", alternates: ["≤"]), .symbol(">", alternates: ["≥"]), .symbol("$"), .symbol("£"), .symbol("¥"), .symbol("•", alternates: ["◦", "·"])],
        [.symbol("."), .symbol(",", alternates: [";"]), .symbol("?"), .symbol("!"), .symbol("'"), .symbol("§"), .symbol("°")],
    ]

    static let superscripts: [String: [String]] = [
        "1": ["¹", "½", "⅓", "¼"], "2": ["²", "⅔"], "3": ["³", "¾"], "0": ["°", "⁰"], "5": ["⁵"], "7": ["⁷"],
    ]

    public static func symbols(options: LayoutOptions = LayoutOptions()) -> KeyboardLayout {
        KeyboardLayout(
            layer: .symbols,
            rows: [KeyRow(symbolRows1[0]), KeyRow(symbolRows1[1]),
                   KeyRow([toExtra] + symbolRows1[2] + [backspace]),
                   bottomRow(options: options, layerSwitch: toLetters)],
            columns: 10
        )
    }

    public static func extraSymbols(options: LayoutOptions = LayoutOptions()) -> KeyboardLayout {
        KeyboardLayout(
            layer: .extraSymbols,
            rows: [KeyRow(symbolRows2[0]), KeyRow(symbolRows2[1]),
                   KeyRow([Key(id: "123b", action: .switchLayer(.symbols), label: "123", width: 1.5, isFunction: true)] + symbolRows2[2] + [backspace]),
                   bottomRow(options: options, layerSwitch: toLetters)],
            columns: 10
        )
    }

    // MARK: Numeric pads

    public static func numberPad(kind: KeyboardLayer, needsGlobeKey: Bool) -> KeyboardLayout {
        func d(_ s: String) -> Key { Key(action: .character(s), label: s, width: 1) }
        var bottomLeft: Key
        switch kind {
        case .decimalPad: bottomLeft = Key(id: "decimal", action: .character(","), label: ",", width: 1)
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
        if options.needsGlobeKey { keys.append(globe) }
        if options.showsEmojiKey && !options.needsGlobeKey { keys.append(emoji) }
        if options.isEmailOrURL {
            keys.append(Key(id: "at", action: .character("@"), label: "@", width: 1))
        }
        keys.append(space)
        if options.isEmailOrURL {
            keys.append(Key(id: "dot", action: .character("."), label: ".", alternates: ["de", "com", "net", "org", "eu"], width: 1))
        } else {
            keys.append(period)
        }
        keys.append(newline)
        return KeyRow(keys)
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
            isLetter: isLetter, isFunction: isFunction, symbolName: symbolName)
    }
}
