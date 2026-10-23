#!/bin/bash
# Contrôle d'oreille de 2 minutes : vérifier à l'oreille que la ligne en blanc change quand le morceau chante la phrase (écart visé ≤ 1 s).
# Seule preuve possible : aucun programme n'a de référence indépendante de ce que tu entends.
# Ce que fait le script : s'assure que l'app (bundle construit par scripts/bundle.sh, tes réglages réels) tourne, envoie « play » à Spotify
# (volume inchangé), attend, puis met Spotify en pause. Aucune parole n'est écrite ni journalisée.
# Une seule instance : si Lyra Lyrics (CE bundle) tourne déjà, le script la réutilise et la laisse ouverte ; sinon il la lance
# (sans `open -n`) et la quitte à la fin. Il ne ferme jamais une autre application.
# Usage : scripts/ear-check.sh [secondes=120]
set -u
cd "$(dirname "$0")/.."
SECS="${1:-120}"
case "$SECS" in ''|*[!0-9]*) echo "usage : $0 [secondes]" >&2; exit 64 ;; esac
APP="$PWD/.build/bundle/LyraLyrics.app"
BIN="$APP/Contents/MacOS/LyraLyrics"
[ -d "$APP" ] || scripts/bundle.sh >/dev/null 2>&1 || { echo "bundle.sh a échoué" >&2; exit 1; }

our_pid() { pgrep -fx "$BIN" 2>/dev/null | head -1; }   # correspondance EXACTE sur le chemin de notre binaire
STARTED_BY_US=0
if [ -n "$(our_pid)" ]; then
  echo "Lyra Lyrics tourne déjà (pid $(our_pid)) : je la réutilise et la laisse ouverte."
else
  open -g "$APP"                       # sans -n : jamais une deuxième instance
  STARTED_BY_US=1
  sleep 4
  [ -n "$(our_pid)" ] || echo "attention : l'app ne semble pas lancée (pid introuvable)" >&2
fi

pgrep -f "/Spotify.app/Contents/MacOS/" >/dev/null || open -g -a Spotify
sleep 2
osascript -e 'tell application id "com.spotify.client" to play' >/dev/null 2>&1
cat <<'TXT'
Contrôle d'oreille : écoute le morceau et regarde la ligne en BLANC de la fenêtre.
 - Elle doit passer à la phrase suivante au moment où tu l'entends chanter, à ± 1 s près.
 - Fais le test sur 3 morceaux : appuie sur « suivant » dans Spotify après ~40 s.
 - En retard ou en avance de façon constante : ⚙ > « Décalage » (−0,1 / +0,1) ; note la valeur qui te convient.
 - Résultat à noter : « synchro OK à ± 1 s », « décalage constant de N s » ou « pas synchro ».
TXT
sleep "$SECS"
osascript -e 'tell application id "com.spotify.client" to pause' >/dev/null 2>&1
echo "Spotify en pause."
if [ "$STARTED_BY_US" = "1" ]; then
  PID="$(our_pid)"
  [ -n "$PID" ] && kill "$PID" && echo "Lyra Lyrics (lancée par ce script, pid $PID) fermée."
fi
