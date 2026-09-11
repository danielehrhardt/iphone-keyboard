# Umlaut – die deutsche Swipe-Tastatur für iOS

Native iOS keyboard extension (UIKit) with Gboard-style glide typing, German-aware autocorrect,
next-word prediction and a SwiftUI host app for onboarding and settings.

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

## How the engine works

**Layout** – `GermanLayouts` defines the QWERTZ layers (letters with ü/ö/ä keys, ß on long-press s,
symbols, #+=, number pads). `KeyboardGeometry` places keys for any size; `KeyMap` exposes letter
centres to the engines.

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

## Dictionary

`scripts/fetch_corpora.sh` downloads the public sources, `scripts/build_dictionary.py` builds
`de_words.txt` (word, frequency; sorted by lowercase spelling) and `de_bigrams.txt`:

| Source | Used for |
| --- | --- |
| hermitdave/FrequencyWords (OpenSubtitles 2018, de) | conversational word frequencies |
| Leipzig Corpora Collection (deu_news_2023, deu_mixed-typical_2011, 300K sentences each) | casing (mid-sentence counts), bigrams, extra frequencies |
| davidak/wortliste, LibreOffice de_DE_frami (Hunspell) | validity filter, casing tie-breaks |

Words with two legitimate casings ship twice (`Sie`/`sie`, `Essen`/`essen`, `Dank`/`dank`).

## Memory budget

Keyboard extensions are killed around 60–70 MB. Measured on the iOS 26 simulator (Release):
17.6 MB before the engine, 31.6 MB with the 137k-word lexicon loaded, about 43 MB while typing
and swiping. The lexicon is flat arrays only (no string-keyed dictionaries), the loader works on raw
UTF-8 bytes, and the emoji panel is created on first use. The extension logs these numbers under the
`de.codext.umlaut.keyboard` subsystem (`log stream --predicate 'subsystem == "de.codext.umlaut.keyboard"'`).

## Privacy

Everything runs on device. "Voller Zugriff" is only needed for haptics and to share settings and the
personal dictionary between the app and the keyboard; nothing is sent anywhere.
