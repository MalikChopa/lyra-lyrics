#!/bin/bash
# Fabrique Resources/AppIcon.icns = icône FINALE (proposition C « la vitre », version retenue pour l'app),
# dessinée en CoreGraphics par scripts/make-icon-proposals.swift (aucun visuel copié ni téléchargé), puis déclinée par `sips`
# (16 à 1024 px, @1x et @2x) et assemblée par `iconutil`. Travail sous /tmp/ll-icon (le script refuse tout autre dossier /tmp-hors).
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="${1:-/tmp/ll-icon}"
case "$WORK" in /tmp/*) ;; *) echo "dossier de travail sous /tmp/ seulement" >&2; exit 64 ;; esac
rm -rf "$WORK"; mkdir -p "$WORK/AppIcon.iconset"
swift scripts/make-icon-proposals.swift "$WORK" >/dev/null
SRC="$WORK/icone-C-vitre.png"
for s in 16 32 128 256 512; do
  sips -z $s $s "$SRC" --out "$WORK/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) "$SRC" --out "$WORK/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$WORK/AppIcon.iconset" -o Resources/AppIcon.icns
echo "Resources/AppIcon.icns écrit (proposition C)"
