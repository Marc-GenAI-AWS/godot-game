#!/bin/bash
# Every check this project has, in one command. Run it before you publish.
#
#   tools/selftest.sh              all of it, about a minute
#   tools/selftest.sh --quick      skip the two simulations (saves about ten seconds)
#
# A minute of traffic and a minute of town life are simulated at a fixed timestep, so they cost a
# second of compute each; nearly all of the runtime is Godot starting up eleven times.
#
# There is no CI here, so this is the gate. It exists because three separate bugs shipped in one
# week that a test would have caught if the test had been run - and two more shipped because the
# test asserted that a variable had been set rather than that anything had happened. So every
# check below asserts an effect, and every run is additionally failed by a single SCRIPT ERROR,
# which is what turned a dropped reference into a frozen browser tab.

set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
GODOT=${GODOT_BIN:-$HOME/opt/godot/Godot_v4.7.2-stable_linux.arm64}
QUICK=0
[ "${1:-}" = "--quick" ] && QUICK=1

# GPU capture wants the desktop session; nothing here does, but the worlds still look for it
export DISPLAY=${DISPLAY:-:0}
export XAUTHORITY=${XAUTHORITY:-/run/user/1000/gdm/Xauthority}

pass=0
fail=0
started=$(date +%s)

# check <name> <marker that must appear> <timeout> <godot args...>
check() {
	local name=$1 marker=$2 secs=$3
	shift 3
	local out
	out=$(timeout "$secs" "$GODOT" --headless --path "$ROOT/game" "$@" 2>&1)
	local code=$?
	local errors
	errors=$(printf '%s\n' "$out" | grep -c "SCRIPT ERROR")
	if [ "$code" -ne 0 ] && [ "$code" -ne 124 ]; then
		printf '  FAIL  %-34s godot exited %d\n' "$name" "$code"
		printf '%s\n' "$out" | grep -E "SCRIPT ERROR|Parse Error" | head -3 | sed 's/^/          /'
		fail=$((fail + 1)); return
	fi
	if [ "$code" -eq 124 ]; then
		printf '  FAIL  %-34s timed out after %ss\n' "$name" "$secs"
		fail=$((fail + 1)); return
	fi
	if [ "$errors" -gt 0 ]; then
		printf '  FAIL  %-34s %d script errors\n' "$name" "$errors"
		printf '%s\n' "$out" | grep "SCRIPT ERROR" | sort | uniq -c | sort -rn | head -3 | sed 's/^/          /'
		fail=$((fail + 1)); return
	fi
	if ! printf '%s\n' "$out" | grep -q "$marker"; then
		printf '  FAIL  %-34s never printed "%s"\n' "$name" "$marker"
		printf '%s\n' "$out" | tail -3 | sed 's/^/          /'
		fail=$((fail + 1)); return
	fi
	printf '  pass  %s\n' "$name"
	pass=$((pass + 1))
}

echo "Worlds build, and their validators agree"
for w in beach street coast; do
	check "$w builds" "world ready: $w" 120 --quit-after 12 -- --world=$w
done

echo "The right-click menu swaps layers, dresses the player and resets"
for w in beach street coast; do
	check "$w menu" "MENUTEST DONE" 180 -- --world=$w --menutest
done

echo "The coast world is one place you can cross, and its agents behave"
check "coast route and roadways" "COASTTEST DONE" 180 -- --world=coast --coasttest
check "commandeering a moving car" "HIJACKTEST DONE" 180 -- --world=coast --hijacktest
if [ "$QUICK" -eq 0 ]; then
	check "traffic over a minute" "TRAFFICTEST DONE" 400 -- --world=coast --traffictest
	check "townspeople over a minute" "CROWDTEST DONE" 600 -- --world=coast --crowdtest
else
	echo "  skip  the two minute-long simulations (--quick)"
fi

echo "Every committed layer passes the static gate the verifier uses"
if "$ROOT/pipeline/.venv/bin/python" -c "
import sys
sys.path.insert(0, '$ROOT/pipeline')
from gdcheck import check
from pathlib import Path
bad = [p.name for p in Path('$ROOT/game/segments').glob('*/generated/*.gd') if check(p.read_text())]
print('flagged:', bad)
sys.exit(1 if bad else 0)" 2>&1 | sed 's/^/  /'; then
	pass=$((pass + 1))
else
	fail=$((fail + 1))
fi

# The harness has to be able to fail, or a green run means nothing: --coasttest in the beach
# world is a check that cannot pass, and this run is expected to report FAIL above it.
echo "The harness itself reports failure (this one is meant to fail)"
before=$fail
check "deliberate failure" "COASTTEST DONE" 120 -- --world=beach --coasttest
if [ "$fail" -gt "$before" ]; then
	fail=$before
	pass=$((pass + 1))
	echo "        ^ expected: the harness noticed"
else
	echo "  FAIL  the harness passed a check that cannot pass"
	fail=$((fail + 1))
fi

printf '\n%d passed, %d failed, %ds\n' "$pass" "$fail" "$(($(date +%s) - started))"
exit $((fail > 0 ? 1 : 0))
