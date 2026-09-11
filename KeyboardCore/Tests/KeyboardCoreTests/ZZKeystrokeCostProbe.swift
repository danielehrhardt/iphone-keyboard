import XCTest
@testable import KeyboardCore

/// Temporary probe: cost of what InputController.refresh() runs per keystroke.
final class ZZKeystrokeCostProbe: XCTestCase {
    func testPerKeystrokeCost() throws {
        let lexicon = try Lexicon.loadBundled()
        let engine = KeyboardEngine(lexicon: lexicon, user: UserLexicon(fileURL: nil))
        let km = KeyMap.reference()
        let ac = engine.autocorrect(for: km)
        let words = ["wahrscheinlich", "morgen", "schnell", "keyboard", "die", "und"]
        for word in words {
            var prefix = ""
            for c in word {
                prefix.append(c)
                let t0 = CFAbsoluteTimeGetCurrent()
                _ = ac.corrections(for: prefix, previousWord: "ist", isSentenceStart: false)
                let t1 = CFAbsoluteTimeGetCurrent()
                _ = engine.predictor.completions(prefix: prefix, previous: "ist", isSentenceStart: false, limit: 4)
                let t2 = CFAbsoluteTimeGetCurrent()
                _ = engine.predictor.letterPrior(prefix: prefix, previous: "ist")
                let t3 = CFAbsoluteTimeGetCurrent()
                print(String(format: "%-16@ corrections %6.2f ms  completions %6.2f ms  prior %6.2f ms", prefix as NSString, (t1-t0)*1000, (t2-t1)*1000, (t3-t2)*1000))
            }
        }
    }
}
