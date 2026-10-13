#!/usr/bin/env bash
# Paired §1.1 mutation proof for the index_watch.py cold-start-grace fix.
# Golden must PASS; each mutant must be KILLED (test_watch_startup_race.py
# must exit non-zero against it) -- otherwise the RED-test is a tautology
# that only agrees with the code it was written against (§11.4.115(F)).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/../index_watch.py"
TEST="$HERE/test_watch_startup_race.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export PYTHONDONTWRITEBYTECODE=1

# Every variant is loaded from its OWN never-reused filename. An earlier
# version of this harness copied every variant onto one shared path
# ($TMP/index_watch.py) and every mutant SURVIVED (printed the golden
# module's own GREEN output) even though a direct, isolated invocation of
# the identical mutant source correctly produced RED -- found live while
# building this harness. Root cause not fully isolated (candidates: the
# path+mtime-keyed __pycache__ bytecode cache reusing a stale compile
# across the same-second overwrite, or some other artifact of reusing one
# path for successive loads within one process tree); rather than assert
# an unconfirmed mechanism, the fix applied is the one independently
# verified to work: never write two different variants to the same path.
# PYTHONDONTWRITEBYTECODE=1 is kept as defense-in-depth regardless of which
# mechanism was actually at fault.
run_against() {
    local variant_path="$1"
    python3 - "$variant_path" "$TEST" <<'PY'
import importlib.util, sys, os
variant_path, test_path = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("index_watch_under_test", variant_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
sys.modules["index_watch_under_test"] = mod
import importlib.util as iu
tspec = iu.spec_from_file_location("t_watch_startup_race", test_path)
t = iu.module_from_spec(tspec)
sys.path.insert(0, os.path.dirname(test_path))
tspec.loader.exec_module(t)
# t.load_module() reads MODULE_PATH itself -- monkeypatch it to point at
# the variant instead of the real file, then rerun main().
t.load_module = lambda: mod
sys.exit(t.main())
PY
}

echo "GOLDEN (unmodified fix):"
if run_against "$SRC"; then echo "  PASS"; else echo "  FAIL (golden must pass) -- ABORT"; exit 1; fi

fail_if_not_killed() {
    local name="$1" path="$2"
    if run_against "$path"; then
        echo "MUTANT $name SURVIVED (test did not catch the regression) -- BUG"
        return 1
    else
        echo "MUTANT $name KILLED"
        return 0
    fi
}

# M1: drop the grace window entirely (STARTUP_GRACE_SAMPLES = 0) -- restores
# the original bug: first not-alive sample is immediately terminal.
sed 's/STARTUP_GRACE_SAMPLES = 3/STARTUP_GRACE_SAMPLES = 0/' "$SRC" > "$TMP/mutant_m1.py"
fail_if_not_killed "M1 grace-window-zeroed" "$TMP/mutant_m1.py"

# M2: make the grace unconditional (ignore ever_alive) -- a genuine stop
# after a real run would wrongly get a fresh grace period instead of being
# terminal immediately (CASE3).
sed 's/if not ever_alive and not_alive_streak <= STARTUP_GRACE_SAMPLES:/if not_alive_streak <= STARTUP_GRACE_SAMPLES:/' "$SRC" > "$TMP/mutant_m2.py"
fail_if_not_killed "M2 grace-ignores-ever_alive" "$TMP/mutant_m2.py"

# M3: grace window absurdly large (never gives up) -- CASE2 (genuine,
# permanent absence) must still resolve NOT_RUNNING within the test's 20
# samples; an unbounded grace masks a truly-dead indexer forever.
sed 's/STARTUP_GRACE_SAMPLES = 3/STARTUP_GRACE_SAMPLES = 1000000/' "$SRC" > "$TMP/mutant_m3.py"
fail_if_not_killed "M3 grace-unbounded" "$TMP/mutant_m3.py"

echo "ALL MUTANTS KILLED — test_watch_startup_race.py is load-bearing"
