#!/bin/bash
# Fabrique windows/LyraLyrics.App/AppIcon.ico (16, 24, 32, 48, 64, 128, 256 px) depuis Resources/AppIcon.icns.
# Outils présents sur macOS seulement : iconutil, sips, python3 (aucun téléchargement, aucun réseau). Travail sous /tmp/ll-ico.
# Usage : bash scripts/make-ico.sh
set -euo pipefail
cd "$(dirname "$0")/.."
WORK=/tmp/ll-ico
rm -rf "$WORK"; mkdir -p "$WORK/png"
iconutil -c iconset Resources/AppIcon.icns -o "$WORK/src.iconset"
SRC="$WORK/src.iconset/icon_512x512.png"     # 512 px : la plus grande taille « @1x » de l'icns
[ -f "$SRC" ] || { echo "icon_512x512.png absent de l'icns" >&2; exit 1; }
for s in 16 24 32 48 64 128 256; do
  sips -z $s $s "$SRC" --out "$WORK/png/$s.png" >/dev/null
done
python3 -I scripts/make-ico.py windows/LyraLyrics.App/AppIcon.ico "$WORK"/png/{16,24,32,48,64,128,256}.png
