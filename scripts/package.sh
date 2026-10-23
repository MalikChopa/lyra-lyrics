#!/bin/bash
# Archive zip du .app pour un usage LOCAL (pas de notarisation : téléchargée ailleurs, elle serait bloquée par Gatekeeper,
# voir le README). Usage : scripts/package.sh   (construit d'abord en release via scripts/bundle.sh)
# PF_SKIP_BUNDLE=1 : réutilise .build/bundle/LyraLyrics.app tel quel.
# Sortie : .build/dist/<Nom affiché>-<version>-macOS.zip (le dossier dans l'archive s'appelle <Nom affiché>.app) + SHA-256.
set -euo pipefail
cd "$(dirname "$0")/.."
[ "${PF_SKIP_BUNDLE:-0}" = "1" ] || scripts/bundle.sh release
SRC=".build/bundle/LyraLyrics.app"
[ -d "$SRC" ] || { echo "$SRC absent : lancer scripts/bundle.sh" >&2; exit 66; }
NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$SRC/Contents/Info.plist")"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SRC/Contents/Info.plist")"
STAGE=".build/dist/stage"
OUT=".build/dist/${NAME// /-}-$VERSION-macOS.zip"
rm -rf "$STAGE" "$OUT"
mkdir -p "$STAGE"
ditto "$SRC" "$STAGE/$NAME.app"           # la signature ne couvre pas le nom du dossier : renommer ne l'invalide pas
codesign --verify --strict "$STAGE/$NAME.app"
ditto -c -k --keepParent "$STAGE/$NAME.app" "$OUT"
rm -rf "$STAGE"
echo "ZIP=$OUT"
echo "TAILLE=$(stat -f %z "$OUT") octets"
echo "SHA256=$(shasum -a 256 "$OUT" | cut -d' ' -f1)"
