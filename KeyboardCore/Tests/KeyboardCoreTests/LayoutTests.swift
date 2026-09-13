import XCTest
@testable import KeyboardCore

final class LayoutTests: XCTestCase {
    func testGermanLettersLayoutHasAllLetters() {
        let layout = GermanLayouts.letters()
        let letters = Set(layout.letterKeys.compactMap(\.character))
        for c in KeyAlphabet.letters { XCTAssertTrue(letters.contains(c), "missing \(c)") }
        XCTAssertEqual(layout.rows[0].keys.map(\.label).joined(), "qwertzuiopü")
        XCTAssertEqual(layout.rows[1].keys.map(\.label).joined(), "asdfghjklöä")
        XCTAssertEqual(layout.rows[2].keys.filter(\.isLetter).map(\.label).joined(), "yxcvbnm")
    }

    /// „Umlaut-Tasten“ off: ten keys per row like QWERTY, y/z still swapped, ü/ö/ä first in the
    /// hold bubble of u/o/a, and the key map folds them onto those keys for swipe and autocorrect.
    func testGermanLayoutWithoutUmlautKeysIsTenColumnsWithUmlautsOnHold() {
        let layout = GermanLayouts.letters(options: LayoutOptions(germanUmlautKeys: false))
        XCTAssertEqual(layout.columns, 10)
        XCTAssertEqual(layout.rows[0].keys.map(\.label).joined(), "qwertzuiop")
        XCTAssertEqual(layout.rows[1].keys.map(\.label).joined(), "asdfghjkl")
        XCTAssertEqual(layout.rows[1].leadingInset, 0.5)
        XCTAssertEqual(layout.rows[1].trailingInset, 0.5)
        XCTAssertEqual(layout.rows[2].keys.filter(\.isLetter).map(\.label).joined(), "yxcvbnm")
        XCTAssertEqual(layout.rows[2].keys.first?.width, EnglishLayouts.shift.width)

        let letters = Set(layout.letterKeys.compactMap(\.character))
        for c in KeyAlphabet.letters.prefix(KeyAlphabet.baseCount) { XCTAssertTrue(letters.contains(c), "missing \(c)") }
        for c in ["ä", "ö", "ü"] as [Character] { XCTAssertFalse(letters.contains(c), "\(c) still has a key") }
        func alternates(_ c: Character) -> [String] { layout.letterKeys.first { $0.character == c }!.alternates }
        XCTAssertEqual(alternates("u").first, "ü")
        XCTAssertEqual(alternates("o").first, "ö")
        XCTAssertEqual(alternates("a").first, "ä")
        XCTAssertTrue(alternates("u").contains("ú"), "the accents stay behind the umlaut")
        XCTAssertTrue(alternates("s").contains("ß"))
        // Still the German keyboard: bottom row, space label and the other layers are unchanged.
        XCTAssertEqual(layout.rows[3].keys.first { $0.action == .space }?.label, "Leerzeichen")
        XCTAssertEqual(GermanLayouts.symbols(options: LayoutOptions(germanUmlautKeys: false)), GermanLayouts.symbols())
        let ids = layout.allKeys.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)

        let keyMap = KeyMap(geometry: KeyboardGeometry(layout: layout, size: CGSize(width: 390, height: 216)))!
        XCTAssertEqual(keyMap.foldedCodes, Set(["ä", "ö", "ü"].map { KeyAlphabet.code(for: $0)! }))
        XCTAssertEqual(keyMap.centers[Int(KeyAlphabet.code(for: "ü")!)], keyMap.centers[Int(KeyAlphabet.code(for: "u")!)])
        // Its own tap-map layer: the arrangement differs from both the 11-column German and the QWERTY one.
        XCTAssertNotEqual(TapMap.arrangement(of: keyMap), TapMap.arrangement(of: KeyMap.reference()))
        XCTAssertNotEqual(TapMap.arrangement(of: keyMap), TapMap.arrangement(of: KeyMap.reference(language: .english)))

        // Default and the English layout are untouched by the option.
        XCTAssertEqual(GermanLayouts.letters(options: LayoutOptions(germanUmlautKeys: true)), GermanLayouts.letters())
        XCTAssertEqual(GermanLayouts.letters().columns, 11)
        XCTAssertEqual(EnglishLayouts.letters(options: LayoutOptions(germanUmlautKeys: false)), EnglishLayouts.letters())
    }

    func testUmlautKeysSettingDefaultsToOn() {
        let settings = KeyboardSettings(defaults: UserDefaults(suiteName: "umlaut-keys-tests-\(UUID())")!)
        XCTAssertTrue(settings.germanUmlautKeys)
        settings.germanUmlautKeys = false
        XCTAssertFalse(settings.germanUmlautKeys)
    }

    func testGeometryFitsWidthAndSpaceBarStretches() {
        let g = KeyboardGeometry(layout: GermanLayouts.letters(), size: CGSize(width: 390, height: 216))
        for kf in g.keyFrames {
            XCTAssertGreaterThanOrEqual(kf.frame.minX, 0)
            XCTAssertLessThanOrEqual(kf.frame.maxX, 390.5)
        }
        let space = g.keyFrame(for: GermanLayouts.space)!
        XCTAssertGreaterThan(space.frame.width, g.unitWidth * 3)
        XCTAssertNotNil(g.keyFrame(at: CGPoint(x: 1, y: 1)))
        XCTAssertEqual(g.keyFrame(at: CGPoint(x: 20, y: 30))?.key.label, "q")
    }

    func testShiftAndBackspaceSitAtTheRowEdges() {
        let width: CGFloat = 390
        let metrics = KeyboardGeometry.Metrics.phonePortrait
        for layer in [KeyboardLayer.letters, .symbols, .extraSymbols] {
            let g = KeyboardGeometry(layout: GermanLayouts.layout(for: layer), size: CGSize(width: width, height: 216))
            let row = g.layout.rows[2]
            let first = g.keyFrame(for: row.keys.first!)!
            let last = g.keyFrame(for: row.keys.last!)!
            // Flush with the row edges, like the system keyboard.
            XCTAssertEqual(first.frame.minX, metrics.sideInset, accuracy: 0.5, "\(layer) leading key")
            XCTAssertEqual(last.frame.maxX, width - metrics.sideInset, accuracy: 0.5, "\(layer) trailing key")
            // The slack widens the two keys; the gaps next to them stay standard, with no empty space.
            let secondKey = g.keyFrame(for: row.keys[1])!
            XCTAssertEqual(secondKey.frame.minX - first.frame.maxX, g.horizontalGap, accuracy: 0.5, "\(layer) leading gap")
            let penultimate = g.keyFrame(for: row.keys[row.keys.count - 2])!
            XCTAssertEqual(last.frame.minX - penultimate.frame.maxX, g.horizontalGap, accuracy: 0.5, "\(layer) trailing gap")
            let nominal = row.keys.first!.width * g.unitWidth + (row.keys.first!.width - 1) * g.horizontalGap
            XCTAssertGreaterThan(first.frame.width, nominal + 1, "\(layer) leading key stretched")
            XCTAssertEqual(first.frame.width, last.frame.width, accuracy: 0.5, "\(layer) flank keys match")
            // Touches at the very edge still belong to them.
            XCTAssertEqual(g.keyFrame(at: CGPoint(x: 0, y: first.frame.midY))?.key.id, first.key.id)
            XCTAssertEqual(g.keyFrame(at: CGPoint(x: width - 1, y: last.frame.midY))?.key.id, last.key.id)
        }
    }

    func testCommaKeySitsLeftOfSpaceAndCanBeDisabled() {
        let bottom = GermanLayouts.letters().rows[3].keys
        let space = bottom.firstIndex { $0.action == .space }!
        XCTAssertEqual(bottom[space - 1].id, "comma")
        XCTAssertEqual(bottom[space - 1].action, .character(","))

        let without = GermanLayouts.letters(options: LayoutOptions(showsCommaKey: false)).rows[3].keys
        XCTAssertFalse(without.contains { $0.id == "comma" })

        // E-mail fields keep "@" left of the space bar instead.
        let email = GermanLayouts.letters(options: LayoutOptions(isEmailOrURL: true)).rows[3].keys
        XCTAssertFalse(email.contains { $0.id == "comma" })
        XCTAssertEqual(email[email.firstIndex { $0.action == .space }! - 1].id, "at")

        // The bottom row is shared, so the symbol layers get the key too.
        XCTAssertTrue(GermanLayouts.symbols().rows[3].keys.contains { $0.id == "comma" })
    }

    func testEmojiKeyFoldsIntoCommaKeyUnlessSeparated() {
        func bottom(_ options: LayoutOptions) -> [Key] { GermanLayouts.letters(options: options).rows[3].keys }
        func comma(in keys: [Key]) -> Key? { keys.first { $0.id == "comma" } }
        func hasEmojiKey(_ keys: [Key]) -> Bool { keys.contains { $0.action == .emoji } }

        // Default: one key. Tap types a comma, holding opens emoji; no separate emoji key, even without a globe.
        let one = bottom(LayoutOptions(needsGlobeKey: false))
        XCTAssertEqual(comma(in: one)?.action, .character(","))
        XCTAssertEqual(comma(in: one)?.longPressAction, .emoji)
        XCTAssertTrue(comma(in: one)?.alternates.isEmpty ?? false, "hold is taken by emoji, no ; : bubble")
        XCTAssertFalse(hasEmojiKey(one))
        // With a globe key the comma key still carries emoji (previously there was no emoji key at all).
        XCTAssertEqual(comma(in: bottom(LayoutOptions(needsGlobeKey: true)))?.longPressAction, .emoji)

        // Two keys: plain comma with its alternates, separate emoji key where there is no globe.
        let two = bottom(LayoutOptions(needsGlobeKey: false, emojiOnCommaKey: false))
        XCTAssertNil(comma(in: two)?.longPressAction)
        XCTAssertEqual(comma(in: two)?.alternates, [";", ":"])
        XCTAssertTrue(hasEmojiKey(two))
        XCTAssertFalse(hasEmojiKey(bottom(LayoutOptions(needsGlobeKey: true, emojiOnCommaKey: false))))

        // No comma key to carry it (setting off, or "@" in e-mail fields): the separate emoji key returns.
        XCTAssertTrue(hasEmojiKey(bottom(LayoutOptions(needsGlobeKey: false, showsCommaKey: false))))
        let email = bottom(LayoutOptions(needsGlobeKey: false, isEmailOrURL: true))
        XCTAssertTrue(hasEmojiKey(email))
        XCTAssertNil(comma(in: email))
    }

    func testKeyMapNearest() {
        let km = KeyMap.reference()
        let q = km.centers[Int(KeyAlphabet.code(for: "q")!)]
        let near = km.nearestCodes(to: q, radius: km.keyWidth * 1.5, limit: 4)
        XCTAssertEqual(near.first?.code, KeyAlphabet.code(for: "q"))
        XCTAssertTrue(km.areAdjacent(KeyAlphabet.code(for: "q")!, KeyAlphabet.code(for: "a")!))
        XCTAssertFalse(km.areAdjacent(KeyAlphabet.code(for: "q")!, KeyAlphabet.code(for: "p")!))
    }

    func testSwipeCodesCollapseDuplicatesAndFoldSharpS() {
        XCTAssertEqual(KeyAlphabet.swipeCodes("Hallo"), KeyAlphabet.codes("halo"))
        XCTAssertEqual(KeyAlphabet.codes("Straße"), KeyAlphabet.codes("strase"))
        XCTAssertEqual(KeyAlphabet.code(for: "é"), KeyAlphabet.code(for: "e"))
    }
    // MARK: Symbol layers

    func testSymbolPunctuationRowMatchesSystemKeyboard() {
        for layout in [GermanLayouts.symbols(), GermanLayouts.extraSymbols()] {
            let row = layout.rows[2]
            XCTAssertEqual(row.keys.map(\.label), ["#+=", ".", ",", "?", "!", "'"] .enumerated().map { $0.offset == 0 ? (layout.layer == .symbols ? "#+=" : "123") : $0.element } + ["⌫"])
            XCTAssertEqual(row.keys.first?.action, .switchLayer(layout.layer == .symbols ? .extraSymbols : .symbols))
            XCTAssertEqual(row.keys.last?.action, .backspace)

            let geometry = KeyboardGeometry(layout: layout, size: CGSize(width: 393, height: 216))
            let frames = geometry.keyFrames.filter { row.keys.contains($0.key) }
            // Layer switch on the left, backspace on the right, row spanning the full width like iOS.
            XCTAssertEqual(frames.first?.key.action, row.keys.first?.action)
            XCTAssertEqual(frames.last?.key.action, .backspace)
            XCTAssertEqual(frames.first!.frame.minX, geometry.keyFrames[0].frame.minX, accuracy: 0.5)
            XCTAssertEqual(frames.last!.frame.maxX, geometry.keyFrames[9].frame.maxX, accuracy: 0.5)
            // The punctuation keys are wider than a digit and evenly spaced.
            let punctuation = frames.dropFirst().dropLast()
            for kf in punctuation { XCTAssertGreaterThan(kf.frame.width, geometry.unitWidth) }
            let pitches = zip(punctuation, punctuation.dropFirst()).map { $1.frame.minX - $0.frame.minX }
            for pitch in pitches { XCTAssertEqual(pitch, pitches[0], accuracy: 0.5) }
        }
    }

    /// Key views are keyed by id, so a layout that repeats a character must not repeat an id.
    func testKeyIDsAreUniqueWithinEveryLayer() {
        for layer in KeyboardLayer.allCases {
            let ids = GermanLayouts.layout(for: layer).allKeys.map(\.id)
            XCTAssertEqual(ids.count, Set(ids).count, "duplicate key id in \(layer)")
        }
    }

    /// Every point inside the keyboard belongs to exactly one key, gaps included.
    func testNoDeadZonesBetweenKeys() {
        let layout = GermanLayouts.symbols()
        let geometry = KeyboardGeometry(layout: layout, size: CGSize(width: 393, height: 216))
        let y = geometry.keyFrames.first { $0.key.id == "sym." }!.frame.midY
        for x in stride(from: CGFloat(1), to: 392, by: 1) {
            XCTAssertNotNil(geometry.keyFrames.first { $0.hitFrame.contains(CGPoint(x: x, y: y)) }, "dead zone at x=\(x)")
        }
    }
}
