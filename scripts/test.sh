#!/bin/bash
# Lance les tests (Swift Testing) :
#  1) `swift test` simple ; 2) si « plugin ... TestingMacros ... not found », relance avec -plugin-path ;
#  3) seulement si les deux échouent : repli `pf-checks` (créé seulement dans ce cas).
# Affiche le résumé de CHAQUE exécution de tests (une par cible : « Test run with N tests in M suites passed/failed »),
# les tests en échec s'il y en a, la ligne GOLDEN_MATCHING (table dorée), puis en dernière ligne le chemin utilisé :
# PATH_USED=plain | plugin-path | pf-checks | none
set -u
cd "$(dirname "$0")/.."
LOG1="$(mktemp -t pf-test1)"
LOG2="$(mktemp -t pf-test2)"
trap 'rm -f "$LOG1" "$LOG2"' EXIT

summarize() {
  # Toutes les lignes de résumé (une par exécution), pas seulement la dernière .
  grep -E "Test run with|✘|GOLDEN_MATCHING|Issue recorded|recorded an issue" "$1" | sed 's/^[^A-Za-z✔✘]*//' | sort -u
  echo "RUNS=$(grep -c "Test run with" "$1") TESTS_TOTAL=$(grep -oE "Test run with [0-9]+ test" "$1" | grep -oE "[0-9]+" | paste -sd+ - | bc)"
}

echo "== swift test (simple) =="
swift test "$@" >"$LOG1" 2>&1
RC=$?
if [ $RC -eq 0 ]; then
  summarize "$LOG1"
  echo "PATH_USED=plain"
  exit 0
fi

if grep -q "TestingMacros" "$LOG1" && grep -qi "not found" "$LOG1"; then
  PLUGIN_PATH="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
  echo "== échec simple (TestingMacros introuvable) ; relance avec -plugin-path $PLUGIN_PATH =="
  swift test "$@" -Xswiftc -plugin-path -Xswiftc "$PLUGIN_PATH" >"$LOG2" 2>&1
  RC2=$?
  if [ $RC2 -eq 0 ]; then
    summarize "$LOG2"
    echo "PATH_USED=plugin-path"
    exit 0
  fi
  echo "== échec aussi avec -plugin-path (code $RC2) =="
  summarize "$LOG2"
  grep -E "error:|✘" "$LOG2" | head -40
else
  echo "== échec de swift test (code $RC), pas une erreur TestingMacros =="
  summarize "$LOG1"
  grep -E "error:|✘" "$LOG1" | head -40
fi

if [ -d Sources/pf-checks ]; then
  echo "== repli pf-checks =="
  swift run pf-checks && { echo "PATH_USED=pf-checks"; exit 0; }
fi
echo "PATH_USED=none"
exit 1
