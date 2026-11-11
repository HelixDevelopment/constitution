#!/usr/bin/env bash
# tests/constitution_cmd/test_wiring_cmd.sh — ownership redesign WAVE 2, item L03: the shell-callable
# `constitution_cmd.sh wiring --inventory | --check` over the real scripts/constitution_ext/wiring_ledger.py.
# Real dispatcher, real ledger module, real files and flock (no stubs, §11.4.289). Test-first (§11.4.224).
# One mktemp sandbox, removed with safe_rm_rf; HOME is never reassigned. Paired mutations:
# tests/constitution_cmd/test_wiring_cmd_mutations.sh. Env: WIRING_CMD_SRC = tree under test (default this repo).
# Exit 0 all pass.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL="$(cd "$HERE/../.." && pwd)"
SRC="${WIRING_CMD_SRC:-$REAL}"
# shellcheck source=/dev/null
. "$REAL/scripts/lib/safe_rm.sh"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_TERMINAL_PROMPT=0
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
unset CONSTITUTION_DIR PROJECT_ROOT CLAUDE_PROJECT_DIR GIT_DIR GIT_WORK_TREE 2>/dev/null || true
SB="$(mktemp -d)" || exit 1
[ -n "$SB" ] && [ -d "$SB" ] || exit 1
SB="$(realpath -e "$SB")"
export SAFE_RM_ALLOWED_ROOTS="$SB"
trap 'safe_rm_rf "${SB:?}"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }
check() { local name="$1"; shift; if "$@"; then ok; else bad "$name"; fi; }
eqv() { if [ "$2" = "$3" ]; then ok; else bad "$1 (expected [$2] got [$3])"; fi; }
has() { case "$1" in *"$2"*) return 0;; esac; return 1; }
hasnt() { case "$1" in *"$2"*) return 1;; esac; return 0; }
tfp() { ( cd "$1" && { find . -path ./.git -prune -o -type l -printf 'L %p -> %l\n' -o -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum 2>/dev/null; find . -path ./.git -prune -o -type d -print; } | LC_ALL=C sort | sha256sum | cut -c1-64 ); }

# project = git repo; constitution = a PLAIN vendored copy inside it (owner = the project, per cl_owner_project_of)
P="$SB/proj"; C="$P/constitution"; mkdir -p "$P" "$C/scripts/constitution_cmd" "$C/scripts/lib" "$C/scripts/constitution_ext" "$C/skills/alpha"
( cd "$P" && git init -q -b main . && printf '# demo\n' >README.md && git add README.md && git commit -qm init ) >/dev/null 2>&1
cp "$SRC/scripts/constitution_cmd/constitution_cmd.sh" "$SRC/scripts/constitution_cmd/args_file_read.py" "$C/scripts/constitution_cmd/"
cp "$REAL/scripts/lib/constitution_layout.sh" "$REAL/scripts/lib/safe_rm.sh" "$REAL/scripts/lib/protected_paths.list" "$C/scripts/lib/"
[ -f "$SRC/scripts/constitution_ext/wiring_ledger.py" ] && cp "$SRC/scripts/constitution_ext/wiring_ledger.py" "$C/scripts/constitution_ext/"
printf '# Constitution\n' >"$C/Constitution.md"; printf 'a\n' >"$C/skills/alpha/SKILL.md"
mkdir -p "$SB/home"
CMD="$C/scripts/constitution_cmd/constitution_cmd.sh"
run() { OUT="$(env HOME="$SB/home" CONSTITUTION_CMD_USER_HOME="$SB/home" SOURCE_DATE_EPOCH=1700000000 bash "$CMD" "$@" </dev/null 2>"$SB/err")"; RC=$?; ERR="$(cat "$SB/err")"; }
led() { env HOME="$SB/home" python3 -I "$C/scripts/constitution_ext/wiring_ledger.py" --project "$P" --root "$C" "$@" </dev/null; }
jf() { python3 -I -c 'import json,sys; v=json.loads(sys.argv[1]); print(json.dumps(v[sys.argv[2]]) if not isinstance(v[sys.argv[2]],str) else v[sys.argv[2]])' "$1" "$2"; }

# ── dispatch + argument policy ──
run wiring --bogus;            eqv "unknown wiring option rc 2" 2 "$RC"
run wiring;                    eqv "wiring with no subcommand rc 2" 2 "$RC"; check "no-subcommand message is the dispatcher's own" has "$ERR" "wiring needs one of"
run wiring --inventory extra;  eqv "extra argument rc 2" 2 "$RC"
run wiring --inventory --check; eqv "two subcommands rc 2" 2 "$RC"
run wiring --record;           eqv "mutating subcommands are not exposed (rc 2)" 2 "$RC"
run wiring --check 'a;b';      eqv "injection characters rc 2" 2 "$RC"
run wiring rollback;           eqv "rollback is not exposed here (rc 2)" 2 "$RC"
check "help lists wiring" has "$(bash "$CMD" help 2>&1)" "wiring"

# ── inventory (read-only) ──
mkdir -p "$P/.claude/skills"; ln -s "../../constitution/skills/alpha" "$P/.claude/skills/alpha"
mkdir -p "$P/.claude/skills"; ln -s "$SB/elsewhere" "$P/.claude/skills/userlink"
T0="$(tfp "$P")"
run wiring --inventory
eqv "inventory rc 0" 0 "$RC"
check "inventory finds the constitution link" has "$OUT" ".claude/skills/alpha"
check "inventory ignores the user's own link" hasnt "$OUT" "userlink"
eqv "inventory is read-only: project tree checksum unchanged" "$T0" "$(tfp "$P")"
check "inventory created no .constitution dir" test ! -e "$P/.constitution"
run wiring inventory; eqv "bare word form works too" 0 "$RC"

# ── check ──
run wiring --check;            eqv "check with an empty ledger rc 0" 0 "$RC"
check "check reports ok true" has "$OUT" '"ok": true'
led record --id sk-alpha --producer installer --agent claude --path .claude/skills/alpha --kind symlink >/dev/null
run wiring --check;            eqv "check with an ours row rc 0" 0 "$RC"
rm "$P/.claude/skills/alpha"; ln -s "../../README.md" "$P/.claude/skills/alpha"
run wiring --check;            eqv "check with a diverged row rc 1" 1 "$RC"
check "check names the diverged row" has "$OUT" "diverged"
check "check reports ok false" has "$OUT" '"ok": false'
rm "$P/.claude/skills/alpha"; ln -s "../../constitution/skills/alpha" "$P/.claude/skills/alpha"
run wiring --check;            eqv "restored link: rc 0 again" 0 "$RC"
rm "$P/.constitution/extensions.state/wiring.local.json"
run wiring --check;            eqv "row with no local signature (another checkout): rc 1" 1 "$RC"
check "check names other-checkout" has "$OUT" "other-checkout"
# review F3: a deleted tracked ledger while this checkout still signs a row is NOT "nothing wired"
rm -f "$P/.constitution/wiring.json"; led record --id sk-alpha --producer installer --agent claude --path .claude/skills/alpha --kind symlink >/dev/null
rm "$P/.constitution/wiring.json"
run wiring --check;            eqv "tracked ledger lost, local signature kept: rc 1" 1 "$RC"
check "check names the missing tracked row" has "$OUT" "tracked-row-missing"
# a corrupted ledger is a refusal, not a pass
printf 'not json\n' >"$P/.constitution/wiring.json"
run wiring --check;            check "corrupted ledger: nonzero, never ok" test "$RC" -ne 0
check "corrupted ledger: no ok:true" hasnt "$OUT" '"ok": true'

# ── determinism ──
rm -f "$P/.constitution/wiring.json"; led record --id sk-alpha --producer installer --agent claude --path .claude/skills/alpha --kind symlink >/dev/null
run wiring --check; A="$OUT"; run wiring --check; B="$OUT"; run wiring --check; D="$OUT"
eqv "three check runs are byte-identical (1=2)" "$A" "$B"; eqv "three check runs are byte-identical (2=3)" "$B" "$D"

# ── missing engine ──
mv "$C/scripts/constitution_ext/wiring_ledger.py" "$SB/wl.keep"
run wiring --check;            eqv "missing ledger module rc 3" 3 "$RC"
check "missing module message" has "$ERR$OUT" "not found"
mv "$SB/wl.keep" "$C/scripts/constitution_ext/wiring_ledger.py"

# ── locking: read-only subcommands wait for a held exclusive project lock, then succeed ──
python3 -I - "$P" "$SB/held" <<'PY' &
import fcntl, os, sys, time
fd = os.open(sys.argv[1], os.O_RDONLY | os.O_DIRECTORY)
fcntl.flock(fd, fcntl.LOCK_EX)
open(sys.argv[2], "w").write("1")
time.sleep(3)
PY
HOLDER=$!
for _ in $(seq 1 50); do [ -e "$SB/held" ] && break; sleep 0.1; done
T1=$(date +%s.%N); run wiring --check; T2=$(date +%s.%N)
wait "$HOLDER" 2>/dev/null
eqv "check under a held exclusive lock still succeeds" 0 "$RC"
check "check waited for the lock (>= 1.5s)" python3 -I -c 'import sys; sys.exit(0 if float(sys.argv[2])-float(sys.argv[1]) >= 1.5 else 1)' "$T1" "$T2"
# concurrent read-only runs do not block each other and never change the ledger
H0="$(sha256sum "$P/.constitution/wiring.json" | cut -c1-64)"
for i in $(seq 1 12); do ( env HOME="$SB/home" bash "$CMD" wiring --check >"$SB/c$i.out" 2>&1; echo $? >"$SB/c$i.rc" ) & done
wait
BADRC=0; for i in $(seq 1 12); do [ "$(cat "$SB/c$i.rc")" = 0 ] || BADRC=$((BADRC+1)); done
eqv "12 concurrent check runs all rc 0" 0 "$BADRC"
eqv "concurrent checks left the ledger byte-identical" "$H0" "$(sha256sum "$P/.constitution/wiring.json" | cut -c1-64)"

printf 'wiring-cmd: PASS %d FAIL %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
