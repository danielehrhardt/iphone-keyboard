import Foundation
import CoreGraphics

/// What happens when a key is activated.
public enum KeyAction: Hashable, Sendable {
    case character(String)
    case backspace
    case shift
    case space
    case newline
    case switchLayer(KeyboardLayer)
    case globe
    case emoji
    case dismiss
}

/// A keyboard "layer" is a full set of rows (letters, symbols, …).
public enum KeyboardLayer: String, Hashable, Sendable, CaseIterable {
    case letters
    case symbols       // 123
    case extraSymbols  // #+=
    case numberPad
    case decimalPad
    case phonePad
}

public struct Key: Hashable, Identifiable, Sendable {
    public let id: String
    public let action: KeyAction
    /// Label shown on the cap. For letters this is the lowercase form.
    public let label: String
    /// Long-press variants (the base character is inserted by the popup automatically).
    public let alternates: [String]
    /// Width relative to a standard letter key.
    public let width: CGFloat
    /// True for a-z / umlauts: participates in swipe decoding and shift.
    public let isLetter: Bool
    /// Rendered with the darker "function key" style.
    public let isFunction: Bool
    /// SF Symbol name for function keys.
    public let symbolName: String?

    public init(id: String? = nil,
                action: KeyAction,
                label: String,
                alternates: [String] = [],
                width: CGFloat = 1,
                isLetter: Bool = false,
                isFunction: Bool = false,
                symbolName: String? = nil) {
        self.id = id ?? label
        self.action = action
        self.label = label
        self.alternates = alternates
        self.width = width
        self.isLetter = isLetter
        self.isFunction = isFunction
        self.symbolName = symbolName
    }

    /// The single character this key types, if any (lowercase for letters).
    public var character: Character? {
        if case .character(let s) = action, s.count == 1 { return s.first }
        return nil
    }

    static func letter(_ c: String, alternates: [String] = []) -> Key {
        Key(action: .character(c), label: c, alternates: alternates, isLetter: true)
    }

    static func symbol(_ c: String, alternates: [String] = [], width: CGFloat = 1) -> Key {
        Key(action: .character(c), label: c, alternates: alternates, width: width)
    }
}

public struct KeyRow: Hashable, Sendable {
    public var keys: [Key]
    /// Extra horizontal padding on each side, in units of a standard key width.
    public var leadingInset: CGFloat
    public var trailingInset: CGFloat

    public init(_ keys: [Key], leadingInset: CGFloat = 0, trailingInset: CGFloat = 0) {
        self.keys = keys
        self.leadingInset = leadingInset
        self.trailingInset = trailingInset
    }
}

public struct KeyboardLayout: Hashable, Sendable {
    public let layer: KeyboardLayer
    public let rows: [KeyRow]
    /// Number of standard key widths that must fit in one row (sets the unit width).
    public let columns: CGFloat

    public init(layer: KeyboardLayer, rows: [KeyRow], columns: CGFloat) {
        self.layer = layer
        self.rows = rows
        self.columns = columns
    }

    public var allKeys: [Key] { rows.flatMap(\.keys) }
    public var letterKeys: [Key] { allKeys.filter(\.isLetter) }
}

/// Options that shape the bottom row.
public struct LayoutOptions: Hashable, Sendable {
    public var needsGlobeKey: Bool
    public var showsEmojiKey: Bool
    /// Adds "@" and "." to the bottom row (e-mail / URL fields).
    public var isEmailOrURL: Bool
    /// Adds a comma key left of the space bar (not in e-mail / URL fields, where "@" sits there).
    public var showsCommaKey: Bool

    public init(needsGlobeKey: Bool = true, showsEmojiKey: Bool = true, isEmailOrURL: Bool = false, showsCommaKey: Bool = true) {
        self.needsGlobeKey = needsGlobeKey
        self.showsEmojiKey = showsEmojiKey
        self.isEmailOrURL = isEmailOrURL
        self.showsCommaKey = showsCommaKey
    }
}
