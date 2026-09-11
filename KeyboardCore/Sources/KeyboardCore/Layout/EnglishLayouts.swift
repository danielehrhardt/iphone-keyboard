import Foundation
import CoreGraphics

/// The US-English QWERTY layout family, matching Apple's English keyboard: ten keys in the top
/// row, the home row inset by half a key, z on the bottom row, "$" on the symbol layer.
/// Umlauts and other accented letters are reached by holding the base letter.
public enum EnglishLayouts {

    // MARK: Letters

    public static let letterRows: [[Key]] = [
        [
            .letter("q"), .letter("w", alternates: ["ŵ"]), .letter("e", alternates: ["è", "é", "ê", "ë", "ē", "ė", "ę"]),
            .letter("r", alternates: ["ŕ", "ř"]), .letter("t", alternates: ["ţ", "ť", "ŧ"]), .letter("y", alternates: ["ÿ", "ý"]),
            .letter("u", alternates: ["û", "ü", "ù", "ú", "ū"]), .letter("i", alternates: ["î", "ï", "í", "ī", "į", "ì"]),
            .letter("o", alternates: ["ô", "ö", "ò", "ó", "œ", "ø", "ō", "õ"]), .letter("p"),
        ],
        [
            .letter("a", alternates: ["à", "á", "â", "ä", "æ", "ã", "å", "ā"]), .letter("s", alternates: ["ß", "ś", "š", "ş"]),
            .letter("d", alternates: ["ď", "đ"]), .letter("f"), .letter("g", alternates: ["ğ", "ģ"]), .letter("h"),
            .letter("j"), .letter("k", alternates: ["ķ"]), .letter("l", alternates: ["ł", "ľ", "ļ"]),
        ],
        [
            .letter("z", alternates: ["ž", "ź", "ż"]), .letter("x"), .letter("c", alternates: ["ç", "ć", "č"]),
            .letter("v"), .letter("b"), .letter("n", alternates: ["ñ", "ń", "ň"]), .letter("m"),
        ],
    ]

    /// Shift and backspace are a little narrower than on the German layout so that the row of
    /// seven letters leaves the wider gaps next to them that Apple's English keyboard has.
    static let flankWidth: CGFloat = 1.25
    public static let shift = Key(id: "shift", action: .shift, label: "⇧", width: flankWidth, isFunction: true, symbolName: "shift")
    public static let backspace = Key(id: "backspace", action: .backspace, label: "⌫", width: flankWidth, isFunction: true, symbolName: "delete.left")

    /// The family knows its language: the bottom row is built for English whatever `options` say.
    private static func english(_ options: LayoutOptions) -> LayoutOptions {
        var o = options
        o.language = .english
        return o
    }

    /// Letters layer: 10 / 9 / 7 letters, the home row inset by half a key.
    public static func letters(options: LayoutOptions = LayoutOptions()) -> KeyboardLayout {
        let options = english(options)
        let row3 = KeyRow([shift] + letterRows[2] + [backspace], expandsFlankGaps: true)
        return KeyboardLayout(
            layer: .letters,
            rows: [KeyRow(letterRows[0]),
                   KeyRow(letterRows[1], leadingInset: 0.5, trailingInset: 0.5),
                   row3,
                   LayoutParts.bottomRow(options: options, layerSwitch: LayoutParts.toSymbols)],
            columns: 10
        )
    }

    // MARK: Symbols

    /// Same as the German symbol layer except for the currency key ("$" first, "€" on hold) and
    /// the quote alternates.
    static let symbolRow2: [Key] = [
        .symbol("-", alternates: ["–", "—", "•"]), .symbol("/", alternates: ["\\"]), .symbol(":"), .symbol(";"), .symbol("("), .symbol(")"),
        .symbol("$", alternates: ["€", "£", "¥", "₩", "₽"]), .symbol("&", alternates: ["§"]), .symbol("@"),
        .symbol("\"", alternates: ["“", "”", "„", "«", "»"]),
    ]

    static let extraRow2: [Key] = [
        .symbol("_"), .symbol("\\"), .symbol("|"), .symbol("~"), .symbol("<", alternates: ["≤"]), .symbol(">", alternates: ["≥"]),
        .symbol("€"), .symbol("£"), .symbol("¥"), .symbol("•", alternates: ["◦", "·"]),
    ]

    public static func symbols(options: LayoutOptions = LayoutOptions()) -> KeyboardLayout {
        KeyboardLayout(
            layer: .symbols,
            rows: [KeyRow(LayoutParts.digitRow), KeyRow(symbolRow2),
                   KeyRow([LayoutParts.toExtra] + LayoutParts.punctuationRow + [LayoutParts.symbolBackspace], expandsFlankGaps: true),
                   LayoutParts.bottomRow(options: english(options), layerSwitch: LayoutParts.toLetters)],
            columns: 10
        )
    }

    public static func extraSymbols(options: LayoutOptions = LayoutOptions()) -> KeyboardLayout {
        KeyboardLayout(
            layer: .extraSymbols,
            rows: [KeyRow(LayoutParts.extraRow1), KeyRow(extraRow2),
                   KeyRow([LayoutParts.toSymbolsFromExtra] + LayoutParts.punctuationRow + [LayoutParts.symbolBackspace], expandsFlankGaps: true),
                   LayoutParts.bottomRow(options: english(options), layerSwitch: LayoutParts.toLetters)],
            columns: 10
        )
    }

    public static func layout(for layer: KeyboardLayer, options: LayoutOptions = LayoutOptions()) -> KeyboardLayout {
        switch layer {
        case .letters: return letters(options: options)
        case .symbols: return symbols(options: options)
        case .extraSymbols: return extraSymbols(options: options)
        case .numberPad, .decimalPad, .phonePad:
            return LayoutParts.numberPad(kind: layer, needsGlobeKey: options.needsGlobeKey, decimalSeparator: ".")
        }
    }
}
