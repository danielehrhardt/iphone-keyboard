#!/usr/bin/env python3
"""Build the German lexicon + bigram model shipped inside KeyboardCore.

Inputs (downloaded by scripts/fetch_corpora.sh into /tmp):
  de_full.txt                     hermitdave/FrequencyWords (OpenSubtitles 2018), lowercase "word count"
  wortliste.txt                   davidak/wortliste, cased German word forms
  de_DE.dic.utf8                  LibreOffice de_DE_frami Hunspell dictionary (UTF-8)
  deu_news_2023_300K/             Leipzig Corpora Collection sample (cased words + sentences)
  deu_mixed-typical_2011_300K/    Leipzig Corpora Collection sample (cased words + sentences)

Outputs:
  KeyboardCore/Sources/KeyboardCore/Resources/de_words.txt     "word<TAB>freq", by freq desc
  KeyboardCore/Sources/KeyboardCore/Resources/de_bigrams.txt   "w1<TAB>w2<TAB>count"

Casing comes from the cased Leipzig counts (sentence-initial capitals are a minority for
non-nouns, so a capitalised majority reliably marks nouns/names). Words missing from Leipzig
fall back to wortliste/Hunspell casing. Validity = known to wortliste or Hunspell, or frequent
enough in Leipzig to be a real word (also removes OpenSubtitles transcription noise).
"""
import re, sys, collections, unicodedata, glob, math

MAX_WORDS = int(sys.argv[1]) if len(sys.argv) > 1 else 150000
ROOT = __file__.rsplit('/scripts/', 1)[0]
RES = f"{ROOT}/KeyboardCore/Sources/KeyboardCore/Resources"

WORD = re.compile(r"^[a-zäöüßA-ZÄÖÜ]+(-[a-zäöüßA-ZÄÖÜ]+)*$")
nfc = lambda s: unicodedata.normalize('NFC', s)

# ---- cased signals -------------------------------------------------------------------
# Casing is counted from sentence-internal positions only, so sentence-initial capitals
# ("Die", "Ich") don't masquerade as legitimate capitalised forms.
BOUNDARY = set('.!?:;"„“”‚‘’»«›‹()')
TOKEN = re.compile(r"[a-zäöüßA-ZÄÖÜ]+(?:-[a-zäöüßA-ZÄÖÜ]+)*|[.!?:;\"„“”‚‘’»«›‹()]")
leipzig = collections.defaultdict(collections.Counter)   # lower -> Counter(casedForm), mid-sentence
leipzig_any = collections.Counter()                        # lower -> total incl. sentence-initial
sentences = []
for path in glob.glob('/tmp/deu_*/*-sentences.txt'):
    with open(path, encoding='utf-8') as f:
        for line in f:
            sent = nfc(line.split('\t', 1)[-1])
            toks = TOKEN.findall(sent)
            sentences.append(toks)
            initial = True
            for tok in toks:
                if tok in BOUNDARY:
                    initial = True
                    continue
                low = tok.lower()
                leipzig_any[low] += 1
                if not initial:
                    leipzig[low][tok] += 1
                initial = False

wortliste = collections.defaultdict(set)
with open('/tmp/wortliste.txt', encoding='utf-8') as f:
    for line in f:
        w = nfc(line.strip())
        if w and WORD.match(w):
            wortliste[w.lower()].add(w)

hunspell = collections.defaultdict(set)
with open('/tmp/de_DE.dic.utf8', encoding='utf-8', errors='replace') as f:
    for line in f:
        w = nfc(line.split('/')[0].strip())
        if w and WORD.match(w):
            hunspell[w.lower()].add(w)

SECONDARY_SHARE = 0.25   # "Sie"/"sie", "Essen"/"essen", "Dank"/"dank" both ship

# Conversational words that news text capitalises (quotes, nominalised "das Nein") but that
# people type lowercase mid-sentence in messages. Primary lowercase, capital kept as secondary.
CHAT_LOWER = {"hallo", "nein", "ja", "danke", "bitte", "tschüss", "okay", "moin", "servus", "super",
              "sorry", "cool", "hi", "hey", "genau", "klar", "gut", "schade", "prima", "toll", "gern", "gerne"}

def pick_casing(lower):
    """Returns [(form, share), ...] — primary first. share sums to 1."""
    cap = lower[0].upper() + lower[1:]
    if lower in CHAT_LOWER:
        return [(lower, 0.75), (cap, 0.25)]
    lc = leipzig.get(lower)
    if lc and sum(lc.values()) >= 5:
        # sentence-initial capitals inflate the capitalised count; require a clear majority
        total = sum(lc.values())
        best = lc.most_common(1)[0][0]
        primary = lower if lc[lower] >= 0.35 * total else best
        hs0 = hunspell.get(lower, set())
        # Interjections ("hallo", "nein") are capitalised after quotes in news text, but the
        # dictionary only knows them lowercase: trust the dictionary unless it's clearly a name.
        if primary != lower and lower in hs0 and cap not in hs0 and lc[lower] >= 0.08 * total:
            primary = lower
        other = cap if primary == lower else lower
        known = other in wortliste.get(lower, ()) or other in hunspell.get(lower, ())
        hs = hunspell.get(lower, set())
        both_stems = lower in hs and cap in hs
        share = lc[other] / total
        if primary != other and known and (share >= SECONDARY_SHARE or (both_stems and share >= 0.03)):
            share = max(share, 0.2) if both_stems else share
            return [(primary, 1 - share), (other, share)]
        return [(primary, 1.0)]
    forms = wortliste.get(lower) or hunspell.get(lower)
    if not forms:
        return None
    if len(forms) == 1:
        return [(next(iter(forms)), 1.0)]
    hs = hunspell.get(lower, set())
    if cap in hs and lower not in hs:
        return [(cap, 1.0)]
    return [(lower if lower in forms else (cap if cap in forms else sorted(forms)[0]), 1.0)]

def is_valid(lower, subs_freq):
    ltotal = leipzig_any.get(lower, 0)
    if lower in hunspell:
        return subs_freq >= 3 or ltotal >= 3
    if lower in wortliste:
        # wortliste carries some proper-noun noise ("Suu"); very short entries need real usage.
        if len(lower) <= 3:
            return subs_freq >= 1000 or ltotal >= 300
        return subs_freq >= 3 or ltotal >= 3
    # Unknown to both dictionaries: mostly names/noise ("Suu"); short ones need strong evidence.
    if len(lower) <= 4:
        return ltotal >= 200 and subs_freq >= 200
    return ltotal >= 25 and subs_freq >= 10

# ---- frequencies ---------------------------------------------------------------------
subs = {}
with open('/tmp/de_full.txt', encoding='utf-8') as f:
    for line in f:
        parts = line.split()
        if len(parts) == 2 and WORD.match(parts[0]):
            subs[nfc(parts[0])] = int(parts[1])

subs_total = sum(subs.values())
leip_total = sum(leipzig_any.values())
scale = 0.5 * subs_total / leip_total   # news weighs half of conversational usage

scored = {}
for lower in set(subs) | set(leipzig_any):
    if len(lower) > 30 or (len(lower) == 1 and lower not in ('a', 'o')):
        continue
    s = subs.get(lower, 0)
    l = leipzig_any.get(lower, 0)
    if not is_valid(lower, s):
        continue
    forms = pick_casing(lower)
    if forms is None:
        continue
    for form, share in forms:
        # Short all-caps tokens ("DZ", "Aa") are mostly abbreviations that make poor suggestions.
        if len(form) <= 3 and form.isupper() and s < 2000 and l < 300:
            continue
        if len(form) <= 2 and form[0].isupper() and form[1:].islower() and s < 5000 and l < 500:
            continue
        scored[form] = int((s + l * scale) * share) or 1

words = sorted(scored.items(), key=lambda kv: (-kv[1], kv[0]))[:MAX_WORDS]
lexicon = {w: n for w, n in words}
by_lower = {}
for w, _ in sorted(words, key=lambda kv: kv[1]):
    by_lower[w.lower()] = w          # ends with the most frequent casing

# Shipped sorted by lowercase spelling (code-point order, identical to Swift's String ordering
# for NFC text) so the runtime can binary-search prefixes without sorting at launch.
with open(f"{RES}/de_words.txt", 'w', encoding='utf-8') as f:
    for w, n in sorted(words, key=lambda kv: (kv[0].lower(), -kv[1])):
        f.write(f"{w}\t{n}\n")
print(f"words: {len(words)}  capitalised: {sum(1 for w,_ in words if w[0].isupper())}")

# ---- bigrams from Leipzig sentences ---------------------------------------------------
bigrams = collections.defaultdict(collections.Counter)
for toks in sentences:
    prev = None
    for tok in toks:
        if tok in BOUNDARY:
            prev = None
            continue
        w = tok if tok in lexicon else by_lower.get(tok.lower())
        if w is None:
            prev = None
            continue
        if prev is not None:
            bigrams[prev][w] += 1
        prev = w

MAX_NEXT, MIN_COUNT = 8, 3
n_out = 0
with open(f"{RES}/de_bigrams.txt", 'w', encoding='utf-8') as f:
    for w1 in sorted(bigrams, key=lambda w: -lexicon[w]):
        for w2, c in bigrams[w1].most_common(MAX_NEXT):
            if c < MIN_COUNT:
                break
            f.write(f"{w1}\t{w2}\t{c}\n")
            n_out += 1
print(f"bigrams: {n_out}")
