import Foundation
import KeyboardCore

/// Observable view of one language's personal dictionary shared with the keyboard extension.
@MainActor
final class LexiconStore: ObservableObject {

    @Published private(set) var entries: [UserLexicon.Entry] = []
    /// Which language's dictionary is shown; each language learns its own words.
    @Published var language: KeyboardLanguage {
        didSet { if language != oldValue { lexicon = UserLexicon.shared(appGroup: KeyboardSettings.appGroup, language: language); reload() } }
    }

    private var lexicon: UserLexicon

    init(language: KeyboardLanguage = KeyboardSettings.shared.currentLanguage) {
        self.language = language
        lexicon = UserLexicon.shared(appGroup: KeyboardSettings.appGroup, language: language)
        reload()
    }

    func reload() {
        lexicon.reloadIfChanged()      // the keyboard extension may have learned words meanwhile
        entries = lexicon.allWords
    }

    @discardableResult
    func add(word raw: String) -> Bool {
        let word = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return false }
        lexicon.add(word: word)
        lexicon.saveNow()
        reload()
        return true
    }

    func remove(word: String) {
        lexicon.remove(word: word)
        lexicon.saveNow()
        reload()
    }

    func remove(at offsets: IndexSet) {
        for word in offsets.map({ entries[$0].word }) {
            lexicon.remove(word: word)
        }
        lexicon.saveNow()
        reload()
    }

    func removeAll() {
        lexicon.removeAll()
        lexicon.saveNow()
        reload()
    }
}
