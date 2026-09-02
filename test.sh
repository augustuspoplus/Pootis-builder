#!/bin/bash
# Headless regression sweep for Pootis Builder.
#   ./test.sh                 — full sweep (stock maps + kit + templates + compile)
#   ./test.sh quick           — skip the stock-map load pass
#
# Needs: build/PootisBuilder.exe, and a TF2 install (auto-detected, or set TF2DIR).
set +e
ROOT="$(cd "$(dirname "$0")" && pwd)"
EXE="$ROOT/build/PootisBuilder.exe"
[ -x "$EXE" ] || { echo "build first: no $EXE"; exit 1; }
# Use a copy so a rebuild during the run doesn't fight the lock.
RUN="$ROOT/build/_test_run.exe"; cp "$EXE" "$RUN" 2>/dev/null || RUN="$EXE"

TF2DIR="${TF2DIR:-/c/Program Files (x86)/Steam/steamapps/common/Team Fortress 2}"
MAPS="$TF2DIR/tf/maps"
VBSP="$TF2DIR/bin/vbsp.exe"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
QUICK=0; [ "$1" = "quick" ] && QUICK=1

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "  !! FAIL: $1"; }

if [ "$QUICK" = 0 ] && [ -d "$MAPS" ]; then
  echo "== stock maps (raw) =="
  for f in "$MAPS"/*.bsp; do
    m=$(basename "$f" .bsp)
    case "$m" in _*|background*) continue;; esac
    L=$(timeout 60 "$RUN" "$f" --no-decompile --view persp --screenshot /dev/null --width 320 --height 240 2>&1)
    if echo "$L" | grep -q 'World mesh:' && ! echo "$L" | grep -iqE '\[error\]|assert|abort'; then ok
    else bad "raw $m"; fi
  done
  echo "  ($PASS raw maps ok)"
fi

echo "== kit pieces =="
PIECES=(Floor Wall Ceiling Pillar Room Ramp Route Hill Stairs Cylinder Dome Arch \
  Wedge Doorway Window Platform Cover "Crate stack" Fence "Spiral stairs" "Skybox seal" \
  "Clip wall" Water "Trigger box" Ladder "Working door" "Spawn door" Button Lever \
  Elevator "Moving platform" "Fan / rotating" "Teleport pair" "Breakable crate" \
  "KOTH point" "CTF setup" "Capture point" "Round timer" "Arena logic" "Death pit" \
  "No-build zone" "One spawn point" "RED spawn" "BLU spawn" "Payload track" Resupply \
  "Health / ammo" "Point light" "Spot light" "Sun / sky" "Pillar (round)" Mountain)
for p in "${PIECES[@]}"; do
  o="$TMP/k.vmf"; rm -f "$o"
  "$RUN" --place-kit "$p" --save-vmf "$o" --screenshot /dev/null --width 32 --height 32 >/dev/null 2>&1
  if [ -s "$o" ] && grep -qE $'\tsolid|^entity' "$o"; then ok; else bad "kit '$p'"; fi
done
echo "  (${#PIECES[@]} pieces checked)"

echo "== undo / redo =="
"$RUN" --undo-test --screenshot /dev/null --width 32 --height 32 2>&1 | grep -q 'undo-test: 5 passed, 0 failed' && ok || bad "undo-test"

echo "== templates =="
for f in "$ROOT"/assets/templates/*.vmf; do
  [ -e "$f" ] || continue
  n=$(basename "$f" .vmf)
  "$RUN" "$f" --screenshot /dev/null --width 32 --height 32 2>&1 | grep -q "VMF loaded: $n" && ok || bad "template $n"
  if [ -x "$VBSP" ]; then
    cp "$f" "$TMP/"
    R=$("$VBSP" -game "$TF2DIR/tf" "$(cygpath -w "$TMP/$n.vmf" 2>/dev/null || echo "$TMP/$n.vmf")" 2>&1)
    echo "$R" | grep -q 'leaked!' && bad "template $n LEAKS" || ok
  fi
done

echo ""
echo "== RESULT: $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
