#!/usr/bin/env bash
# test_bootstrap_summary_mode_default.sh — the bootstrap summary line must print `mode=shadow` when JEV_MODE is absent
# from the env file (review round 1, F6: the v72 `jev_env_get` form exits 0 with EMPTY output, so an `|| echo shadow`
# fallback never ran and the line read `mode=`).
#   M1 the summary line is produced for (a) an env file without JEV_MODE, (b) a missing env file  -> mode=shadow
#   M2 control: JEV_MODE=enforce in the file -> mode=enforce (and not shadow)
#   M3 control: `export JEV_MODE="observe"` (quoted, export form) -> mode=observe
#   M4 the OLD form, extracted from git history text below, is detected as RED (paired mutation)
# BOOTSTRAP_UNDER_TEST overrides the script path (RED on the pre-fix file).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="${BOOTSTRAP_UNDER_TEST:-$HERE/../../scripts/jev/bootstrap.sh}"
LIB="$HERE/../../scripts/jev/lib_decide.sh"
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "ok - $1"; }
bad() { fail=$((fail+1)); echo "FAIL - $1"; }
[ -r "$S" ] && [ -r "$LIB" ] || { echo "FATAL: cannot read $S or $LIB" >&2; exit 2; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
# Evaluate the summary-mode logic exactly as written in the script under test: every line from the first line that
# mentions JEV_MODE inside the summary block up to and including the `summary:` log line, with `log` printing.
BLK="$(awk '/jev_env_get "\$ENV_FILE" JEV_MODE/ && !/stored|S5_STORED/ {p=1} p {print} p && /summary: state=/ {exit}' "$S" | grep -v '^[[:space:]]*#')"
[ -n "$BLK" ] || { echo "FATAL: summary block not found in $S" >&2; exit 2; }
case "$BLK" in *"summary: state="*) ok "control needle: the summary line is visible to the extractor";; *) bad "control needle: summary line not extracted";; esac
run() { # <env-file> -> prints the summary line's mode= token
  ( set -euo pipefail; . "$LIB"; ENV_FILE="$1"; JEV_STATE_DIR=s; JEV_EVIDENCE_DIR=e
    log() { printf '%s\n' "$2"; }
    eval "$BLK" ) 2>&1 | sed -n 's/.*\(mode=[^ ]*\).*/\1/p' | head -1
}
: > "$T/empty.env"; printf 'FOO=1\n' > "$T/nomode.env"
r="$(run "$T/nomode.env")";   [ "$r" = "mode=shadow" ] && ok "M1a env file without JEV_MODE -> mode=shadow" || bad "M1a got [$r]"
r="$(run "$T/missing.env")";  [ "$r" = "mode=shadow" ] && ok "M1b missing env file -> mode=shadow" || bad "M1b got [$r]"
printf 'JEV_MODE=enforce\n' > "$T/enf.env"
r="$(run "$T/enf.env")";      [ "$r" = "mode=enforce" ] && ok "M2 JEV_MODE=enforce -> mode=enforce" || bad "M2 got [$r]"
printf 'export JEV_MODE="observe"\n' > "$T/obs.env"
r="$(run "$T/obs.env")";      [ "$r" = "mode=observe" ] && ok "M3 quoted export form -> mode=observe" || bad "M3 got [$r]"
# M4 paired mutation: the pre-fix expression must be RED under the same harness
OLD='log "" "  summary: state=$JEV_STATE_DIR evidence=$JEV_EVIDENCE_DIR mode=$(jev_env_get "$ENV_FILE" JEV_MODE || echo shadow)"'
r="$( ( set -euo pipefail; . "$LIB"; ENV_FILE="$T/nomode.env"; JEV_STATE_DIR=s; JEV_EVIDENCE_DIR=e; log() { printf '%s\n' "$2"; }; eval "$OLD" ) 2>&1 | sed -n 's/.*\(mode=[^ ]*\).*/\1/p' | head -1)"
[ "$r" = "mode=" ] && ok "M4 mutation: the old '|| echo shadow' form yields '$r' (RED reproduced, so M1 discriminates)" || bad "M4 old form gave [$r], expected the empty mode"
echo "== RESULT: $pass passed, $fail failed =="; [ "$fail" -eq 0 ]
