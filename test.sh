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

echo "== phase 1: entity-brush editing =="
P1="$LOCALAPPDATA/PootisBuilder/decompiled/cp_process_final.vmf"
[ -f "$P1" ] || P1="$ROOT/assets/templates/turbine_lookalike.vmf"
"$RUN" "$P1" --phase1-test --screenshot /dev/null --width 32 --height 32 2>&1 \
  | grep -q 'phase1-test.*: 4 passed, 0 failed' && ok || bad "phase1-test"

echo "== phase 2: modal G/R/S transform =="
"$RUN" --mx-test --screenshot /dev/null --width 32 --height 32 2>&1 \
  | grep -q 'mx-test: 4 passed, 0 failed' && ok || bad "mx-test"

echo "== phase 3: displacements =="
"$RUN" --disp-test --screenshot /dev/null --width 32 --height 32 2>&1 \
  | grep -q 'disp-test: 7 passed, 0 failed' && ok || bad "disp-test (make + sculpt + round-trip)"
DISP="$LOCALAPPDATA/PootisBuilder/decompiled/cp_badlands.vmf"
[ -f "$DISP" ] || DISP="$LOCALAPPDATA/PootisBuilder/decompiled/cp_process_final.vmf"
if [ -f "$DISP" ]; then
  o="$TMP/disp_rt.vmf"; rm -f "$o"
  "$RUN" "$DISP" --save-vmf "$o" --screenshot /dev/null --width 32 --height 32 >/dev/null 2>&1
  a=$(grep -c 'dispinfo' "$DISP"); b=$(grep -c 'dispinfo' "$o" 2>/dev/null || echo 0)
  if [ "$a" -gt 0 ] && [ "$a" = "$b" ]; then ok; else bad "disp round-trip ($a in, $b out)"; fi
else
  echo "  (no decompiled disp map cached — skipped)"
fi

echo "== phase 5: leak pointfile =="
"$RUN" --leak-test --screenshot /dev/null --width 32 --height 32 2>&1 \
  | grep -q 'leak-test: 1 passed, 0 failed' && ok || bad "leak-test (pointfile parse)"

echo "== net: json round-trip + http stack =="
"$RUN" --net-test --screenshot /dev/null --width 32 --height 32 2>&1 | grep -q 'net-test: 8 passed, 0 failed' && ok || bad "net-test (json/http)"

echo "== picking: props use their model bounds =="
"$RUN" --pick-test --screenshot /dev/null --width 32 --height 32 2>&1 | grep -q 'pick-test: 4 passed, 0 failed' && ok || bad "pick-test (prop click box)"

echo "== phase 5: asset pack scan =="
"$RUN" "$ROOT/assets/templates/turbine_lookalike.vmf" --pack-scan \
  --screenshot /dev/null --width 32 --height 32 2>&1 \
  | grep -q 'pack-scan: 0 custom asset(s), 0 missing' && ok \
  || bad "pack-scan (kit output should reference no custom/missing assets)"

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
