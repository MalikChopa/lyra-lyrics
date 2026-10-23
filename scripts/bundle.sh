#!/bin/bash
# Construit le .app à la main (sans Xcode) : swift build + Info.plist + signature, runtime durci + entitlements.
# Usage : scripts/bundle.sh [release|debug]   (défaut : release)
# Le build « debug » contient les drapeaux de diagnostic (--exit-after, #if DEBUG) ; « release » non (D12).
# Sortie : .build/bundle/LyraLyrics.app (dossier ignoré par git). Le nom affiché vient de
# Sources/LyricsCore/AppIdentity.swift (unique source, voir ce fichier) et remplace @APP_NAME@ dans Resources/Info.plist.
# Signature : première identité de signature de code trouvée dans le trousseau (security find-identity -p codesigning, SANS -v :
# une auto-signée est marquée CSSMERR_TP_NOT_TRUSTED) parmi, dans l'ordre : PF_SIGN_IDENTITY si définie, « Lyra Lyrics Code »,
# puis un ancien nom local ; signée par son empreinte SHA-1 ; sinon ad hoc (suffisant pour construire et lancer chez soi).
# Aucune variable d'environnement n'est nécessaire. Dit LAQUELLE sur la dernière ligne « SIGNATURE=… ».
# Pourquoi un certificat local plutôt qu'ad hoc : une signature ad hoc change à chaque compilation, et macOS redemande alors l'autorisation
# Automatisation ; un certificat local (Trousseaux d'accès > Assistant de certification > Créer un certificat, type « Signature de code »)
# garde une identité stable.
# PF_SIGN_ADHOC=1 : force la signature ad hoc (si l'utilisation de la clé du trousseau est bloquée par une invite « codesign veut utiliser la clé »).
# PF_SIGN_DRY_RUN=1 : choisit l'identité, l'affiche, ne construit ni ne signe rien (test du choix).
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
case "$CONFIG" in release|debug) ;; *) echo "usage : $0 [release|debug]" >&2; exit 64 ;; esac
CANDIDATES=()
[ -z "${PF_SIGN_IDENTITY:-}" ] || CANDIDATES+=("$PF_SIGN_IDENTITY")
CANDIDATES+=("Lyra Lyrics Code")
IDENTITY_NAME="${CANDIDATES[0]}"

# Nom affiché : la ligne `public static let displayName = "…"` de AppIdentity.swift.
APP_NAME="$(sed -n 's/^[[:space:]]*public static let displayName = "\(.*\)"$/\1/p' Sources/LyricsCore/AppIdentity.swift | head -1)"
[ -n "$APP_NAME" ] || { echo "nom affiché introuvable dans Sources/LyricsCore/AppIdentity.swift" >&2; exit 65; }

# Imprime « <nom>|<SHA-1> » de la première identité présente, ou « -| » (ad hoc).
choose_identity() {
  local name hash
  for name in "${CANDIDATES[@]}"; do
    # Ligne type :  1) <SHA-1 de 40 hexadécimaux> "Nom" (CSSMERR_TP_NOT_TRUSTED) ; on signe par l'empreinte (le nom peut être ambigu).
    hash="$(security find-identity -p codesigning 2>/dev/null | grep -F "\"$name\"" | grep -Eo '[0-9A-F]{40}' | head -1 || true)"
    if [ -n "$hash" ]; then echo "$name|$hash"; return; fi
  done
  echo "-|"
}
if [ "${PF_SIGN_ADHOC:-0}" = "1" ]; then CHOSEN="-|"; else CHOSEN="$(choose_identity)"; fi
SIGN_ID="${CHOSEN#*|}"; IDENTITY_NAME="${CHOSEN%%|*}"
if [ -z "$SIGN_ID" ]; then SIGN_ID="-"; SIGN_LABEL="ad hoc (aucune des identités cherchées n'existe : $(printf '« %s » ' "${CANDIDATES[@]}" | sed 's/ $//'))"; else SIGN_LABEL="identité « $IDENTITY_NAME » (SHA-1 $SIGN_ID)"; fi
if [ "${PF_SIGN_DRY_RUN:-0}" = "1" ]; then echo "SIGNATURE=$SIGN_LABEL (dry run, rien signé)"; exit 0; fi

swift build -c "$CONFIG" --product LyraLyrics 2>&1 | grep -v "ld: warning: search path" | tail -3
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

APP=".build/bundle/LyraLyrics.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/LyraLyrics" "$APP/Contents/MacOS/LyraLyrics"
sed "s/@APP_NAME@/$APP_NAME/g" Resources/Info.plist > "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
plutil -lint "$APP/Contents/Info.plist" >/dev/null
printf 'APPL????' > "$APP/Contents/PkgInfo"

codesign --force --sign "$SIGN_ID" --options runtime --entitlements Resources/entitlements.plist "$APP"
codesign --verify --strict --verbose=2 "$APP"
echo "APP=$APP (config=$CONFIG, nom=$APP_NAME)"
echo "SIGNATURE=$SIGN_LABEL"
