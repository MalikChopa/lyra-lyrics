#!/bin/bash
# Lance le build DEBUG de l'app avec une suite de préférences UNIQUE, puis la supprime (domaine + plist) : aucun `pf.*` ne reste.
# Usage : scripts/run-app-test.sh <nom> <arguments de l'app…>      ex. :
#   scripts/run-app-test.sh etats --fake-player etats --selftest Fixtures/selftests/etats.txt --diagnostics /tmp/ll/etats.log --exit-after 120
# Code de sortie = celui de l'app. Dernière ligne : nombre de fichiers ~/Library/Preferences/pf.* restants (0 attendu).
cd "$(dirname "$0")/.."
NAME="$1"; shift
SUITE="pf.j5.$NAME.$$"
APP=".build/debug/LyraLyrics"
[ -x "$APP" ] || { echo "$APP absent : swift build" >&2; exit 66; }
"$APP" --defaults-suite "$SUITE" --reset-defaults "$@"
RC=$?
defaults delete "$SUITE" >/dev/null 2>&1
rm -f "$HOME/Library/Preferences/$SUITE.plist"
echo "RC=$RC suite=$SUITE pf-restants=$(ls "$HOME/Library/Preferences" | grep -c '^pf\.')"
exit $RC
