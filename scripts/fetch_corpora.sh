#!/bin/sh
# Downloads the public corpora used by build_dictionary.py into /tmp.
set -e
curl -sSL -o /tmp/de_full.txt https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/de/de_full.txt
curl -sSL -o /tmp/wortliste.txt https://raw.githubusercontent.com/davidak/wortliste/master/wortliste.txt
echo "corpora ready in /tmp"
curl -sSL -o /tmp/de_DE_frami.dic https://raw.githubusercontent.com/LibreOffice/dictionaries/master/de/de_DE_frami.dic
iconv -f ISO-8859-1 -t UTF-8 /tmp/de_DE_frami.dic > /tmp/de_DE.dic.utf8
