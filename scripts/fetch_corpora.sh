#!/bin/sh
# Downloads the public corpora used by build_dictionary.py into $CORPUS_DIR (default /tmp).
# Usage: fetch_corpora.sh [de|en]   (default: both)
set -e
DIR="${CORPUS_DIR:-/tmp}"
LANGS="${1:-de en}"
mkdir -p "$DIR"

for lang in $LANGS; do
  case "$lang" in
    de)
      curl -sSL -o "$DIR/de_full.txt" https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/de/de_full.txt
      curl -sSL -o "$DIR/wortliste.txt" https://raw.githubusercontent.com/davidak/wortliste/master/wortliste.txt
      curl -sSL -o "$DIR/de_DE_frami.dic" https://raw.githubusercontent.com/LibreOffice/dictionaries/master/de/de_DE_frami.dic
      iconv -f ISO-8859-1 -t UTF-8 "$DIR/de_DE_frami.dic" > "$DIR/de_DE.dic.utf8"
      for corpus in deu_news_2023_300K deu_mixed-typical_2011_300K; do
        curl -sSL -o "$DIR/$corpus.tar.gz" "https://downloads.wortschatz-leipzig.de/corpora/$corpus.tar.gz"
        tar xzf "$DIR/$corpus.tar.gz" -C "$DIR"
      done
      ;;
    en)
      curl -sSL -o "$DIR/en_full.txt" https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/en/en_full.txt
      curl -sSL -o "$DIR/words_alpha.txt" https://raw.githubusercontent.com/dwyl/english-words/master/words_alpha.txt
      curl -sSL -o "$DIR/en_US.dic" https://raw.githubusercontent.com/LibreOffice/dictionaries/master/en/en_US.dic
      curl -sSL -o "$DIR/eng_news_2023_300K.tar.gz" https://downloads.wortschatz-leipzig.de/corpora/eng_news_2023_300K.tar.gz
      tar xzf "$DIR/eng_news_2023_300K.tar.gz" -C "$DIR"
      ;;
    *) echo "unknown language: $lang" >&2; exit 1 ;;
  esac
done
echo "corpora ready in $DIR"
