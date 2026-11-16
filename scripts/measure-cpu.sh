#!/bin/bash
# Critère CPU (ARCHITECTURE §4 « Énergie ») : `ps -o %cpu` toutes les 1 s pendant 60 s -> moyenne, p95, max ;
# en plus, temps CPU cumulé (`ps -o cputime`, plus fiable que %cpu qui est une moyenne glissante du système) sur la fenêtre.
# Usage : scripts/measure-cpu.sh playing|playing1|playing5|resize|hidden|unsynced|idle|closed [secondes=60]
#   playing : faux lecteur « demo » en lecture, fenêtre visible, retour à 0 s toutes les 50 s (Fixtures/selftests/cpu-playing.txt)
#   unsynced: paroles non synchronisées (bloc qui défile), fenêtre visible (cpu-unsynced.txt)
#   hidden  : idem, mais fenêtre masquée après 3 s (cpu-hidden.txt)
#   idle    : aucun lecteur (`--no-players`), fenêtre visible
#   closed  : vrais lecteurs branchés, présence forcée « fermés » ; compte aussi les Apple events (hub-stats, 0 attendu)
# APP=<binaire> remplace le build debug (ex. un build release compilé avec -DDEBUG sous /tmp/pf-j5b/build-reldbg).
# Suite de préférences unique, supprimée à la fin. Le processus lancé est tué à la fin (le sien seulement).
cd "$(dirname "$0")/.."
MODE="${1:-playing}"; SECS="${2:-60}"
case "$MODE" in
  playing) ARGS=(--fake-player demo --selftest Fixtures/selftests/cpu-playing.txt) ;;
  resize) ARGS=(--fake-player demo --selftest Fixtures/selftests/cpu-resize.txt) ;;
  playing1) ARGS=(--fake-player demo --selftest Fixtures/selftests/cpu-playing-1.txt) ;;
  playing5) ARGS=(--fake-player demo --selftest Fixtures/selftests/cpu-playing-5.txt) ;;
  unsynced) ARGS=(--fake-player demo --selftest Fixtures/selftests/cpu-unsynced.txt) ;;
  scene) ARGS=(--fake-player demo --selftest Fixtures/selftests/cpu-scene.txt) ;;
  scenegap) ARGS=(--fake-player demo --selftest Fixtures/selftests/cpu-scene-gap.txt) ;;
  s24) ARGS=(--fake-player demo --selftest Fixtures/selftests/cpu-s24.txt) ;;
  hidden) ARGS=(--fake-player demo --selftest Fixtures/selftests/cpu-hidden.txt) ;;
  idle) ARGS=(--no-players) ;;
  closed) ARGS=(--players-closed) ;;
  *) echo "usage : $0 playing|playing1|playing5|resize|hidden|unsynced|idle|closed|scene|scenegap|s24 [s]" >&2; exit 64 ;;
esac
OUT="${PF_OUT:-/tmp/pf-j5b}"; mkdir -p "$OUT"
LOG="$OUT/cpu-$MODE.log"; : > "$LOG"
SUITE="pf.j5b.cpu.$MODE.$$"
"${APP:-.build/debug/LyraLyrics}" --defaults-suite "$SUITE" --reset-defaults "${ARGS[@]}" --diagnostics "$OUT/cpu-$MODE.diag" --exit-after $((SECS + 30)) >/dev/null 2>&1 &
PID=$!
sleep 6                                   # démarrage, premier affichage et masquage hors mesure
cpu_seconds() { ps -o cputime= -p $PID | awk -F'[:.]' '{ printf "%.2f", $1 * 60 + $2 + $3 / 100 }'; }
T0=$(cpu_seconds); W0=$(date +%s)
for ((i = 0; i < SECS; i++)); do
  ps -o %cpu= -p $PID >> "$LOG" 2>/dev/null
  sleep 1
done
T1=$(cpu_seconds); W1=$(date +%s)
kill $PID 2>/dev/null; wait $PID 2>/dev/null
defaults delete "$SUITE" >/dev/null 2>&1; rm -f "$HOME/Library/Preferences/$SUITE.plist"
sort -n "$LOG" | awk -v m="$MODE" '{ v[NR] = $1; s += $1 } END { p = int(NR * 0.95 + 0.9999); if (p < 1) p = 1; printf "ps %%cpu %s : n=%d moyenne=%.2f %% p95=%.1f %% max=%.1f %%\n", m, NR, s / NR, v[p], v[NR] }'
awk -v a="$T0" -v b="$T1" -v w=$((W1 - W0)) 'BEGIN { printf "CPU cumulé (cputime) sur %d s : %.2f s de CPU = %.2f %%\n", w, b - a, 100 * (b - a) / w }'
[ "$MODE" = closed ] && grep hub-stats "$OUT/cpu-$MODE.diag" | tail -2
exit 0
