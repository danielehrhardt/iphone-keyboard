# Umlaut – die deutsche Swipe-Tastatur für iOS

Native iOS keyboard extension (UIKit) with Gboard-style glide typing, language-aware autocorrect,
next-word prediction and a SwiftUI host app for onboarding and settings. Types German (QWERTZ) and
English (QWERTY); more languages plug in the same way.

```
Umlaut/            SwiftUI host app (onboarding, Ausprobieren, Einstellungen, gelernte Wörter)
UmlautKeyboard/    Keyboard extension (UIInputViewController, key grid, gestures, suggestion bar, emoji)
KeyboardCore/      Swift package: layouts, lexicon, swipe decoder, autocorrect, predictor, settings
scripts/           Dictionary build pipeline
project.yml        xcodegen project definition
```

## Build

```sh
brew install xcodegen
xcodegen generate
open Umlaut.xcodeproj            # scheme "Umlaut" → run on device, then enable the keyboard in Settings
```

Simulator from the command line:

```sh
xcodebuild -project Umlaut.xcodeproj -scheme Umlaut \
  -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO build
```

Engine tests (pure Swift, run on macOS):

```sh
cd KeyboardCore && swift test -c release -Xswiftc -enable-testing
```

Keyboard behaviour tests (`InputController` against an in-memory document) and UI tests that drive
the in-app demo keyboard and save screenshots to `/tmp/umlaut-ui`:

```sh
xcodebuild -project Umlaut.xcodeproj -scheme Umlaut -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO -only-testing:UmlautKeyboardTests test
xcodebuild -project Umlaut.xcodeproj -scheme Umlaut -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO -only-testing:UmlautUITests/DemoKeyboardUITests test
```

To try the real extension on a simulator without going through Settings:

```sh
xcrun simctl spawn booted defaults write -g AppleKeyboards -array \
  "de.codext.umlaut.keyboard" "de_DE@sw=QWERTZ-German;hw=Automatic" "emoji@sw=Emoji"
```

## In-app demo keyboard

The app's „Ausprobieren“ screen hosts the *same* keyboard UI (`KeyboardCoordinator` + `DemoKeyboardView`)
as a `UITextView.inputView`, so swipe typing can be tried before the extension is enabled. The keyboard
sources under `UmlautKeyboard/` are compiled into both targets; only `KeyboardViewController.swift`
(extension) and `UmlautKeyboard/InApp/` (app) are target-specific.

## Clipboard history

The keyboard remembers what was copied – text and images – and offers it again behind the „⋯“
button at the leading edge of the suggestion strip (the *action menu*, which also holds emoji,
the language switch and hide-keyboard). `ClipboardHistory` (KeyboardCore) keeps the entries as
`clipboard/index.json` plus image files in the app group; `ClipboardMonitor` (keyboard target,
also compiled into the app) feeds it from `UIPasteboard.general`. The pasteboard is only *read*
when its `changeCount` moved since the last capture (the count of the last clip is stored in
the shared settings, so app and extension never read the same clip twice) – reading shows the
system paste banner and, on iOS 16+, asks once whether Umlaut may paste from other apps. Images
are downscaled through ImageIO's thumbnail path (never decoded at full size in the extension)
and stored at ≤ 1280 px plus a 200 px preview. Picking a text entry types it; picking an image
puts it back on the pasteboard, from where the system's Paste command inserts it (a keyboard
cannot insert images). „Einstellungen › Zwischenablage“ switches the history off, sets the
retention (1 hour … forever, pruned on every keyboard appearance) and lists the entries.
Reading the pasteboard needs „Vollen Zugriff“ like everything else the extension shares.

## How the engine works

**Languages** – `KeyboardLanguage` (`.german`, `.english`) is the one switch everything hangs off:
the layout family, the bundled dictionary (`<lang>_words.txt`, `<lang>_bigrams.txt`), the orthography
(`LanguageRules`: abbreviations that don't end a sentence, digraph spellings such as `ue → ü`, cold-start
suggestions) and the personal dictionary file (`user-lexicon.json` for German, `user-lexicon-en.json`
for English). `KeyboardSettings.enabledLanguages` lists the languages the keyboard cycles through and
`currentLanguage` the one being typed; the app's „Sprachen“ section toggles them (the last one cannot be
switched off). With two or more enabled, the space bar shows the language name and a badge (`DE`/`EN`)
next to the hide-keyboard button switches to the next one. The extension keeps only the active
language's engine in memory (a second lexicon would cost another ~14 MB) and reloads on switch; typing
keeps working meanwhile, suggestions return once the engine is there. Adding a language: a case in
`KeyboardLanguage`, a layout family, a `LanguageRules` value, and `scripts/build_dictionary.py <lang>`.

**Layout** – `GermanLayouts` defines the QWERTZ layers (letters with ü/ö/ä keys, ß on long-press s;
with `KeyboardSettings.germanUmlautKeys` off – „Umlaut-Tasten“ in the app – the letters layer is
10/9/7 wide like QWERTY and ü/ö/ä sit first in the hold bubble of u/o/a),
`EnglishLayouts` the QWERTY layers (10/9/7 letters, umlauts on long-press, `$` on the symbol layer);
`LayoutParts` holds what they share (function keys, digit and punctuation rows, number pads, bottom
row). `KeyboardGeometry` places keys for any size; `KeyMap` exposes letter centres to the engines. The
letter code space (`KeyAlphabet`, a–z + äöü) is shared: on QWERTY the umlaut codes fold onto a/o/u so
one swipe decoder, autocorrect and tap map serve every layout.

**Swipe decoding** (`SwipeDecoder`) – a SHARK²-style two-channel matcher with a language-model prior:

1. The finger path is smoothed and resampled to 32 equidistant points.
2. Candidate words come from (first key, last key) buckets around the start/end points (up to 4×5 keys).
3. Each candidate's ideal path through its key centres is resampled the same way and compared in a
   *location* channel (banded DTW in key widths) and a *shape* channel (normalised outline),
   plus endpoint and "every key visited" penalties.
4. Scores are Gaussian log-likelihoods summed with `languageWeight · log P(word | previous)`.

A decode takes about 2 ms on a Mac for a 137k-word lexicon.

**Autocorrect** (`Autocorrect`) – Damerau–Levenshtein with keyboard-aware costs (adjacent keys are
cheap substitutions), free-ish fixes for casing (`haus → Haus`) and digraphs (`schoen → schön`,
`strasse → Straße`), and conservative auto-apply rules so real words are never replaced.

**Prediction** (`Predictor`) – bigram successors (static corpus + personal), prefix completions with
context boost, sentence-start capitalisation.

**Personal dictionary** (`UserLexicon`) – learns words after two uses, learns bigrams, remembers rejected
corrections, stored as JSON in the app group.

**Dynamic hit targets** (`LetterPrior`, `KeyboardGeometry.keyFrame(at:prior:)`) – the invisible touch
areas move with the text, the drawn keys never do. After every keystroke the predictor turns the
dictionary completions of the current prefix and the bigram successors of the previous word into a
next-letter distribution, plus the chance that the word ends here (`P(word == prefix) / P(word starts
with prefix)`). Each tap is then decided by `priorWeight · log P(key) − ½ · (distance / σ)²` over the
neighbouring letter keys, so a likely letter owns the gaps around it and up to a quarter of its
neighbours' caps (after `kno`, w takes the edge of e), while every key keeps the central half of its
cap whatever the prediction. Once the word looks complete the space bar grows into the bottom row;
while it clearly goes on (`kön` → n) the likely letter reaches over the bar's top edge. Other function
keys are never affected, and a tap map offset, when learned, moves the centre a key is judged from.
Toggle: „Dynamische Tastenflächen“.

**Tap map** (`TapMap`) – SwiftKey-style adaptive hit targets. For every letter key the keyboard keeps
the running mean of where this user's finger lands relative to the printed centre (in units of the
key pitch, so one map serves every key size). It learns from committed words: a word left as typed
confirms every tap, a same-length autocorrection (`hakko → hallo`) re-attributes the wrong tap to
the neighbouring key that was meant, and reverting the correction with backspace takes the lesson
back. The hit test (`KeyboardGeometry.keyFrame(at:prior:offsets:)`) then judges every tap from the
learned centres, combined with the next-letter prior; function keys are never affected. One layer per
keyboard width and letter arrangement (portrait/landscape, QWERTZ/QWERTY), stored as JSON in the app
group; the host app shows it under „Deine Tap Map“ with a reset. Toggle: „Tippverhalten lernen“.

## Dictionary

`scripts/fetch_corpora.sh [de|en]` downloads the public sources (into `$CORPUS_DIR`, default `/tmp`),
`scripts/build_dictionary.py <de|en>` builds `<lang>_words.txt` (word, frequency; sorted by lowercase
spelling) and `<lang>_bigrams.txt`:

| Source | Used for |
| --- | --- |
| hermitdave/FrequencyWords (OpenSubtitles 2018, de / en) | conversational word frequencies |
| Leipzig Corpora Collection (de: deu_news_2023, deu_mixed-typical_2011; en: eng_news_2023; 300K sentences each) | casing (mid-sentence counts), bigrams, extra frequencies |
| de: davidak/wortliste, LibreOffice de_DE_frami (Hunspell) | validity filter, casing tie-breaks |
| en: dwyl/english-words, LibreOffice en_US (Hunspell) | validity filter, casing tie-breaks |

Words with two legitimate casings ship twice (`Sie`/`sie`, `Essen`/`essen`, `Dank`/`dank`). The
German list has 150k words, the English one 100k. English keeps contractions (`don't`, `that's`;
the news corpus is their only witness, OpenSubtitles splits them) and drops their apostrophe-less
typo forms (`dont`, `thats`) so autocorrect can fix them.

## Memory budget

Keyboard extensions are killed around 60–70 MB. Measured on the iOS 26 simulator (Release):
17.6 MB before the engine, 31.6 MB with the 137k-word lexicon loaded, about 43 MB while typing
and swiping. The lexicon is flat arrays only (no string-keyed dictionaries), the loader works on raw
UTF-8 bytes, and the emoji panel is created on first use. Only one language's lexicon is resident
at a time; switching languages swaps it. The extension logs these numbers under the
`de.codext.umlaut.keyboard` subsystem (`log stream --predicate 'subsystem == "de.codext.umlaut.keyboard"'`).

## Privacy

Everything runs on device. "Voller Zugriff" is only needed for haptics and to share settings and the
personal dictionary between the app and the keyboard; nothing is sent anywhere.
