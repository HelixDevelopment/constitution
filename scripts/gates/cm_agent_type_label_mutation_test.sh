#!/usr/bin/env bash
# cm_agent_type_label_mutation_test.sh — §1.1 paired-mutation meta-test for
# CM-AGENT-TYPE-LABEL (§11.4.182 / §11.4.231(F)).
#
# Purpose : prove the gate is NOT a bluff — it PASSes the real toolchain and
#   FAILs every planted regression of the generator / installer / hook:
#     M0  clean copy                                   -> PASS (golden-FALSE)
#     M1  non-idempotent generator ($RANDOM in body)    -> FAIL
#     M2  generator overwrites hand-made files          -> FAIL
#     M3  --check always exits 0 (blind drift check)    -> FAIL
#     M4  frontmatter effort disagrees with the name    -> FAIL
#     M5  colour outside the supported set (data file)  -> FAIL
#     M6  hook skips the agent-type check               -> FAIL
#     M7  hook ignores AGENT_TYPE_LABEL_ENFORCE         -> FAIL
#     M8  hook also flags specialist/plugin types       -> FAIL
#     M9  hook counts hand-made (unmarked) types        -> FAIL
#     M10 installer prunes hand-made files              -> FAIL
#     M11 generator silently drops the `max` effort     -> FAIL
#     M12 hook forgets the audited bypass reason        -> FAIL
#   plus gate-level cases on the dispatch-log audit (warn vs enforce) and a
#   removed-doc / removed-script case.
# Usage   : bash scripts/gates/cm_agent_type_label_mutation_test.sh
# Side-effects: temp tree under ${TMPDIR:-/tmp}, removed on exit; the real
#   scripts are only READ (copied), never modified.
# Exit    : 0 every case had the expected verdict · 1 otherwise · 2 env error.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CONST="$(cd "$HERE/../.." && pwd -P)"
GATE="$HERE/cm_agent_type_label.sh"
[ -f "$GATE" ] || { echo "META: gate missing: $GATE" >&2; exit 2; }
T="$(mktemp -d "${TMPDIR:-/tmp}/cm_atl_mut.XXXXXX")"
trap 'rm -rf "$T"' EXIT
rc=0
note() { echo "$@"; }
expect() { # want(pass|fail) desc cmd...
  local want="$1" desc="$2"; shift 2
  if "$@" >"$T/last.out" 2>&1; then got=pass; else got=fail; fi
  if [ "$got" = "$want" ]; then note "OK    $desc (gate ${got}ed as required)"; else note "META FAIL: $desc — gate ${got}ed, wanted $want"; sed 's/^/        | /' "$T/last.out" | tail -8; rc=1; fi
}

fresh_tree() { # name -> $T/name/scripts/{multitrack,hooks,gates}
  local d="$T/$1"; mkdir -p "$d/scripts/gates" "$d/docs/scripts"
  cp -r "$CONST/scripts/multitrack" "$d/scripts/multitrack"
  cp -r "$CONST/scripts/hooks" "$d/scripts/hooks"
  cp "$GATE" "$d/scripts/gates/"
  cp "$CONST/docs/scripts/gen_agent_label_defs.md" "$CONST/docs/scripts/install_agent_label_defs.md" "$CONST/docs/scripts/guard-track-branch-label.md" "$d/docs/scripts/" 2>/dev/null
  echo "$d"
}
gate_in() { # tree -> runs the gate copy living inside that tree
  bash "$1/scripts/gates/cm_agent_type_label.sh" --quiet
}
mutate() { # tree file python-snippet-old python-snippet-new
  python3 -I - "$1" "$2" "$3" "$4" <<'PY'
import sys
path, old, new = sys.argv[2], sys.argv[3].encode().decode('unicode_escape'), sys.argv[4].encode().decode('unicode_escape')
s = open(path).read()
if old not in s:
    sys.stderr.write("MUTANT-NOT-APPLIED: %r not found in %s\n" % (old, path)); sys.exit(3)
open(path, "w").write(s.replace(old, new, 1))
PY
}

echo "======================================================================"
echo "§1.1 paired-mutation meta-test for CM-AGENT-TYPE-LABEL"

D=$(fresh_tree m0);  expect pass "M0 clean copy of the real toolchain" gate_in "$D"

D=$(fresh_tree m1); mutate "$D" "$D/scripts/multitrack/gen_agent_label_defs.sh" '  hash="$({' '  body="$body #$RANDOM"\n  hash="$({' || rc=1
expect fail "M1 non-idempotent generator" gate_in "$D"

D=$(fresh_tree m2); mutate "$D" "$D/scripts/multitrack/gen_agent_label_defs.sh" 'if [ "$nhand" -gt 0 ] || [ "$nedit" -gt 0 ]; then' 'if false; then' || rc=1
expect fail "M2 generator overwrites hand-made files" gate_in "$D"

D=$(fresh_tree m3); mutate "$D" "$D/scripts/multitrack/gen_agent_label_defs.sh" '[ "$ndrift" -eq 0 ] && exit 0 || exit 1' 'exit 0' || rc=1
expect fail "M3 --check is blind to drift" gate_in "$D"

D=$(fresh_tree m4); mutate "$D" "$D/scripts/multitrack/gen_agent_label_defs.sh" '"$m" "$e" "$color")"' '"$m" "medium" "$color")"' || rc=1
expect fail "M4 frontmatter effort disagrees with the type name" gate_in "$D"

D=$(fresh_tree m5); sed -i 's/^1\tblue$/1\tmagenta/;s/^\*\tyellow$/*\tmagenta/' "$D/scripts/multitrack/agent_label_colors.tsv"
expect fail "M5 colour outside the supported set" gate_in "$D"

D=$(fresh_tree m6); mutate "$D" "$D/scripts/hooks/guard-track-branch-label.sh" '    _type_check\n    exit $?' '    exit 0' || rc=1
expect fail "M6 hook skips the agent-type check" gate_in "$D"

D=$(fresh_tree m7); mutate "$D" "$D/scripts/hooks/guard-track-branch-label.sh" '"${AGENT_TYPE_LABEL_ENFORCE:-0}" == "1"' '"0" == "1"' || rc=1
expect fail "M7 hook ignores AGENT_TYPE_LABEL_ENFORCE" gate_in "$D"

D=$(fresh_tree m8); mutate "$D" "$D/scripts/hooks/guard-track-branch-label.sh" '    *) return 0 ;;\n  esac\n  if [[ -n "${AGENT_TYPE_LABEL_BYPASS' '    *) reason="specialist" ;;\n  esac\n  if [[ -n "${AGENT_TYPE_LABEL_BYPASS' || rc=1
expect fail "M8 hook flags specialist/plugin types" gate_in "$D"

D=$(fresh_tree m9); mutate "$D" "$D/scripts/hooks/guard-track-branch-label.sh" "    grep -q '^<!-- generated-by: gen_agent_label_defs\\\\.sh v1 ' \"\$f\" 2>/dev/null || continue\n" '' || rc=1
expect fail "M9 hook counts hand-made types as generated" gate_in "$D"

D=$(fresh_tree m10); mutate "$D" "$D/scripts/multitrack/install_agent_label_defs.sh" '      genuine)\n' '      genuine|handmade)\n' || rc=1
expect fail "M10 installer prunes hand-made files" gate_in "$D"

D=$(fresh_tree m11); mutate "$D" "$D/scripts/multitrack/gen_agent_label_defs.sh" '  for e in "${EFFORT_LIST[@]}"; do\n    f=' '  for e in "${EFFORT_LIST[@]}"; do\n    [ "$e" = max ] && continue\n    f=' || rc=1
expect fail "M11 generator silently drops the max effort" gate_in "$D"

D=$(fresh_tree m12); mutate "$D" "$D/scripts/hooks/guard-track-branch-label.sh" '  if [[ -n "${AGENT_TYPE_LABEL_BYPASS:-}" ]]; then' '  if [[ -n "${AGENT_TYPE_LABEL_BYPASS+x}" ]]; then' || rc=1
expect fail "M12 empty bypass reason bypasses" gate_in "$D"

D=$(fresh_tree m13); rm "$D/docs/scripts/gen_agent_label_defs.md"
expect fail "M13 missing generator doc" gate_in "$D"
D=$(fresh_tree m14); rm "$D/scripts/multitrack/install_agent_label_defs.sh"
expect fail "M14 missing installer" gate_in "$D"

# dispatch-log audit (gate-level)
D=$(fresh_tree m0b)
mkdir -p "$T/aud/agents"; bash "$D/scripts/multitrack/gen_agent_label_defs.sh" --track 1 --branch main --out-dir "$T/aud/agents" >/dev/null
printf '%s\n' '{"subagent_type":"general-purpose","description":"(T1/main - claude1 - opus - high) ATM-1 x"}' '{"subagent_type":"Explore","description":"(T1/main - claude1 - sonnet - low) y"}' >"$T/aud/bad.jsonl"
printf '%s\n' '{"subagent_type":"T1-main-sonnet-low","description":"(T1/main - claude1 - sonnet - low) y"}' '{"subagent_type":"plugin-dev:agent-creator","description":"(T1/main - claude1 - sonnet - low) z"}' '{"subagent_type":"general-purpose","description":"(T9/other - claude1 - sonnet - low) no types for T9"}' >"$T/aud/good.jsonl"
expect pass "A1 dispatch-log with a general-purpose dispatch, warn mode -> WARN only" bash "$D/scripts/gates/cm_agent_type_label.sh" --quiet --dispatch-log "$T/aud/bad.jsonl" --agents-dir "$T/aud/agents"
expect fail "A2 same log, enforce mode -> FAIL" bash "$D/scripts/gates/cm_agent_type_label.sh" --quiet --dispatch-log "$T/aud/bad.jsonl" --agents-dir "$T/aud/agents" --mode enforce
expect pass "A3 golden-FALSE log (labelled types, specialists, track without types), enforce -> PASS" bash "$D/scripts/gates/cm_agent_type_label.sh" --quiet --dispatch-log "$T/aud/good.jsonl" --agents-dir "$T/aud/agents" --mode enforce
grep -q 'WARN' <(bash "$D/scripts/gates/cm_agent_type_label.sh" --dispatch-log "$T/aud/bad.jsonl" --agents-dir "$T/aud/agents" 2>&1) && note "OK    A1b warn mode prints a WARN line" || { note "META FAIL: A1b warn mode prints a WARN line"; rc=1; }
expect fail "A4 unknown mode -> bad arg (nonzero)" bash "$D/scripts/gates/cm_agent_type_label.sh" --mode bogus
echo "----------------------------------------------------------------------"
[ "$rc" -eq 0 ] && { echo "META: PASS — CM-AGENT-TYPE-LABEL is not a bluff gate"; exit 0; } || { echo "META: FAIL — see above"; exit 1; }
