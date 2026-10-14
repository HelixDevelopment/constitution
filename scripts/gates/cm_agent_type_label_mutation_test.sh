#!/usr/bin/env bash
# cm_agent_type_label_mutation_test.sh — §1.1 paired-mutation meta-test for
# CM-AGENT-TYPE-LABEL (§11.4.182 (8) / §11.4.231 (F.5)).
#
# Purpose : prove the gate and the unit suites are NOT bluffs — the clean tree
#   PASSes and every planted regression of the generator / naming library /
#   installer / hook / post-update hook is caught. Each mutant is ONE edit to a
#   COPY of the real script; the gate (or, for suite-level mutants, the named
#   unit suite) is then run on the mutated tree and MUST fail. A mutant whose
#   text is not found aborts the case loudly (MUTANT-NOT-APPLIED), never a
#   silent pass.
#     M0  clean copy                                   -> gate PASS (golden-FALSE)
#     M1  non-idempotent generator ($RANDOM in body)   -> gate FAIL
#     M2  generator overwrites hand-made files          -> gate FAIL
#     M3  --check always exits 0 (blind drift check)    -> gate FAIL
#     M4  frontmatter effort disagrees with the name    -> gate FAIL
#     M5  colour outside the supported set (data file)  -> gate FAIL
#     M6  hook skips the agent-type check               -> gate FAIL
#     M7  hook ignores AGENT_TYPE_LABEL_ENFORCE         -> gate FAIL
#     M8  hook also flags specialist/plugin types       -> gate FAIL
#     M9  hook counts hand-made (unmarked) types        -> gate FAIL
#     M10 installer prunes hand-made files              -> gate FAIL
#     M11 generator silently drops the opus-xhigh type  -> gate FAIL
#     M12 hook accepts an empty bypass reason           -> gate FAIL
#     M13 missing generator doc / M14 missing installer -> gate FAIL
#   Reviewer-authored mutants of round 1 (adopted, re-targeted at the new code):
#     RM1 sanitiser keeps '.'                           -> gate FAIL
#     RM2 content hash covers the front matter only     -> gate FAIL
#     RM3 installer prunes hand-EDITED stale files      -> gate FAIL
#     RM4 installer --dry-run really deletes            -> gate FAIL
#     RM6 hook stops recognising label-shaped types (an other-track type then
#         passes as a "specialist") — the round-1 track-check mutant is now an
#         EQUIVALENT mutant (the identity-prefix check also rejects it), so the
#         stronger form is used                         -> gate FAIL
#     RM7 hook counts generated types of every track    -> gate FAIL
#     RM8 installer ignores the live identity (fixed alias) -> gate FAIL
#     RM10 marker accepted anywhere in the file         -> gen suite FAIL
#   Round-2 mutants:
#     N1  hook ignores a per-dispatch model/effort override -> gate FAIL
#     N2  hook ignores CLAUDE_CODE_EFFORT_LEVEL         -> gate FAIL
#     N3  hook stops JSON-escaping the WARN payload     -> gate FAIL
#     N4  installer fails open on an unknown identity   -> gate FAIL
#     N5  sanitiser locale-dependent ([:upper:], no LC_ALL=C) -> gen suite FAIL
#     N6  post-update hook back on mapfile              -> install suite FAIL
#     N7  installer stops excluding generated files from git -> gate FAIL
#     N8  a bare shellcheck disable= without a same-line reason -> gate FAIL
#     N9  installer prunes another alias's generated types   -> gate FAIL
#     N10 prune leaves export siblings behind               -> gate FAIL
#     N11 hook label/type check back to a prefix match       -> gate FAIL
#   Reviewer-authored mutants of round 2 (adopted):
#     RV1 sort_unique_into without sort -u                  -> install suite FAIL
#     RV2b exclude block lists only the .md (no siblings)   -> gate FAIL
#     RV3 al_json_escape keeps control characters           -> gate FAIL
#   Round-4 mutants (exclude-block identity class) and reviewer survivors of round 3:
#     N12 exclude block keyed per relative dir (linked-worktree collision) -> gate FAIL
#     N13 exclude begin line matched by prefix              -> install suite FAIL
#     N14 --remove-alias ignores ownership                 -> install suite FAIL
#     RV4 legacy end line matched without its T<N> suffix   -> install suite FAIL
#     RV5 ownership on the raw label alias                  -> install suite FAIL
#     RV6 ownership by prefix (kimi vs kimi-for-coding)     -> gate FAIL
#     RV7 '?'-alias identity match accepts any remainder    -> hook suite FAIL
#     X1-X8 exclude-block grammar, lock, CR, orphan end, stale collection,
#           --remove-alias flag matrix                       -> installer suite FAIL
#     HK1 label model differs from the type's model           -> hook suite FAIL
#     RV13 newline out-dir refusal removed                    -> installer suite FAIL
#     RV15 --remove-alias deletes hand-edited files           -> installer suite FAIL
#     R1b/R17/R6 (reviewer) unmounted worktree, stale end, dry-run exclude -> installer FAIL
#     Y1-Y7 path rule, value rule (installer, generator), flock requirement,
#           temp-file cleanup, doc count drift, CHANGELOG id list -> suite/gate FAIL
#   plus gate-level cases on the dispatch-log audit (warn vs enforce).
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
  if [ "$got" = "$want" ]; then note "OK    $desc (${got}ed as required)"; else note "META FAIL: $desc — ${got}ed, wanted $want"; sed 's/^/        | /' "$T/last.out" | tail -8; rc=1; fi
}
fresh_tree() { # name -> $T/name with scripts/{multitrack,hooks,gates} + post_update_hook + docs
  local d="$T/$1"; mkdir -p "$d/scripts/gates" "$d/docs/scripts"
  cp -r "$CONST/scripts/multitrack" "$d/scripts/multitrack"
  cp -r "$CONST/scripts/hooks" "$d/scripts/hooks"
  cp "$CONST/scripts/post_update_hook.sh" "$d/scripts/"
  cp "$CONST/scripts/gates/cm_agent_type_label_mutation_test.sh" "$d/scripts/gates/"
  cp "$CONST/CHANGELOG.md" "$d/"
  cp "$GATE" "$d/scripts/gates/"
  cp "$CONST/docs/scripts/gen_agent_label_defs.md" "$CONST/docs/scripts/install_agent_label_defs.md" "$CONST/docs/scripts/guard-track-branch-label.md" "$d/docs/scripts/" 2>/dev/null
  echo "$d"
}
gate_in() { bash "$1/scripts/gates/cm_agent_type_label.sh" --quiet; }
suite_in() { bash "$1/scripts/$2"; }   # tree relpath
MUTATED=""
mutate() { # tree file old new  (python literal replace, escapes allowed; aborts the case if not found)
  if python3 -I - "$1" "$2" "$3" "$4" <<'PY'
import sys
path, old, new = sys.argv[2], sys.argv[3].encode().decode('unicode_escape'), sys.argv[4].encode().decode('unicode_escape')
s = open(path).read()
if old not in s:
    sys.stderr.write("MUTANT-NOT-APPLIED: %r not found in %s\n" % (old, path)); sys.exit(3)
open(path, "w").write(s.replace(old, new, 1))
PY
  then MUTATED=1; else MUTATED=""; rc=1; fi
}
mg() { # id desc file old new -> mutate a fresh tree and expect the gate to FAIL
  local D; D=$(fresh_tree "$1"); mutate "$D" "$D/$3" "$4" "$5"
  if [ -n "$MUTATED" ]; then expect fail "$1 $2" gate_in "$D"; else note "META FAIL: $1 mutant not applied"; fi
}
ms() { # id desc suite file old new -> mutate a fresh tree and expect the named suite to FAIL
  local D; D=$(fresh_tree "$1"); mutate "$D" "$D/$4" "$5" "$6"
  if [ -n "$MUTATED" ]; then expect fail "$1 $2" suite_in "$D" "$3"; else note "META FAIL: $1 mutant not applied"; fi
}
G=scripts/multitrack/gen_agent_label_defs.sh; I=scripts/multitrack/install_agent_label_defs.sh
H=scripts/hooks/guard-track-branch-label.sh; L=scripts/multitrack/agent_label_lib.sh

echo "======================================================================"
echo "§1.1 paired-mutation meta-test for CM-AGENT-TYPE-LABEL"
D=$(fresh_tree m0); expect pass "M0 clean copy of the real toolchain (gate)" gate_in "$D"
expect pass "M0b clean copy: generator suite" suite_in "$D" multitrack/test_gen_agent_label_defs.sh
expect pass "M0c clean copy: installer suite" suite_in "$D" multitrack/test_install_agent_label_defs.sh
expect pass "M0d clean copy: hook suite" suite_in "$D" hooks/test_guard_agent_type_label.sh

mg M1 "non-idempotent generator" "$G" '  hash="$({' '  body="$body #$RANDOM"\n  hash="$({'
mg M2 "generator overwrites hand-made files" "$G" 'if [ "$nhand" -gt 0 ] || [ "$nedit" -gt 0 ]; then' 'if false; then'
mg M3 "--check is blind to drift" "$G" '[ "$ndrift" -eq 0 ] && exit 0 || exit 1' 'exit 0'
mg M4 "frontmatter effort disagrees with the type name" "$G" '"$m" "$e" "$color")"' '"$m" "medium" "$color")"'
D=$(fresh_tree M5); sed -i 's/^1\tblue$/1\tmagenta/;s/^7\t.*$//;s/^\*\tyellow$/*\tmagenta/' "$D/scripts/multitrack/agent_label_colors.tsv"; expect fail "M5 colour outside the supported set" gate_in "$D"
mg M6 "hook skips the agent-type check" "$H" '    _type_check\n    exit $?' '    exit 0'
mg M7 "hook ignores AGENT_TYPE_LABEL_ENFORCE" "$H" '"${AGENT_TYPE_LABEL_ENFORCE:-0}" == "1"' '"0" == "1"'
mg M8 "hook flags specialist/plugin types" "$H" '  else\n    return 0\n  fi\n  if [[ -n "${AGENT_TYPE_LABEL_BYPASS' '  else\n    reason="specialist"\n  fi\n  if [[ -n "${AGENT_TYPE_LABEL_BYPASS'
mg M9 "hook counts hand-made types as generated" "$H" "      grep -Eq '^<!-- generated-by: gen_agent_label_defs\\\\.sh v[12] ' \"\$f\" 2>/dev/null || continue\n" ''
mg M10 "installer prunes hand-made files" "$I" '    case "$cl" in genuine|edited) ;; *) continue ;; esac' '    case "$cl" in genuine|edited) ;; handmade) prune_one "$f"; continue ;; *) continue ;; esac'
mg M11 "generator silently drops opus-xhigh" "$G" '  m="${t%%-*}"; e="${t#*-}"\n' '  [ "$t" = opus-xhigh ] && continue\n  m="${t%%-*}"; e="${t#*-}"\n'
mg M12 "empty bypass reason bypasses" "$H" '  if [[ -n "${AGENT_TYPE_LABEL_BYPASS:-}" ]]; then' '  if [[ -n "${AGENT_TYPE_LABEL_BYPASS+x}" ]]; then'
D=$(fresh_tree M13); rm "$D/docs/scripts/gen_agent_label_defs.md"; expect fail "M13 missing generator doc" gate_in "$D"
D=$(fresh_tree M14); rm "$D/$I"; expect fail "M14 missing installer" gate_in "$D"
# reviewer-authored mutants (round 1), re-targeted
mg RM1 "sanitiser keeps '.'" "$L" "tr -c 'a-z0-9' '-'" "tr -c 'a-z0-9.' '-'"
D=$(fresh_tree RM2); mutate "$D" "$D/$G" "hash=\"\$({ printf '%s\\\\n' \"\$fm\"; printf '%s\\\\n' \"\$body\"; } |" "hash=\"\$({ printf '%s\\\\n' \"\$fm\"; } |"
[ -n "$MUTATED" ] && mutate "$D" "$D/$G" 'got="$({ sed -n "1,${k}p" "$f"; sed -n "$((k+2)),\\$p" "$f"; }' 'got="$({ sed -n "1,${k}p" "$f"; }'
if [ -n "$MUTATED" ]; then expect fail "RM2 content hash covers the front matter only" gate_in "$D"; else note "META FAIL: RM2 mutant not applied"; fi
mg RM3 "installer prunes hand-EDITED stale files" "$I" 'if [ "$cl" = edited ]; then echo "WARN' 'if [ "$cl" = edited ]; then prune_one "$f"; echo "WARN'
mg RM4 "installer --dry-run really deletes" "$I" 'elif [ "$dry" -eq 1 ]; then echo "PLAN     $b (prune' 'elif [ "$dry" -eq 1 ]; then rm -f -- "$f"; echo "PLAN     $b (prune'
mg RM6 "hook stops recognising label-shaped types" "$H" 'elif [[ "$stype" =~ ^T([0-9]+)-.+-(sonnet|opus)-(low|medium|high|xhigh|max)$ ]]; then' 'elif [[ "$stype" =~ ^NEVER$ ]]; then'
mg RM7 "hook counts generated types of every track" "$H" '    for f in "$adir"/T"${ltrack}"-*.md; do' '    for f in "$adir"/T*-*.md; do'
mg RM8 "installer ignores the live identity" "$I" "  al=\"\${rest%%' - '*}\"" '  al="fixedalias"'
ms RM10 "marker accepted anywhere in the file" multitrack/test_gen_agent_label_defs.sh "$G" '  mk="$(sed -n "$((k+1))p" "$f")"' '  mk="$(grep -m1 "generated-by" "$f")"'
# round-2 mutants
D=$(fresh_tree N1); mutate "$D" "$D/$H" '[[ -n "$dmodel" && "$dmodel" != "$tm" ]]' '[[ -n "$dmodel" && "$dmodel" != "$dmodel" ]]'
[ -n "$MUTATED" ] && mutate "$D" "$D/$H" '[[ -n "$deffort" && "$deffort" != "$te" ]]' '[[ -n "$deffort" && "$deffort" != "$deffort" ]]'
if [ -n "$MUTATED" ]; then expect fail "N1 hook ignores a per-dispatch model/effort override" gate_in "$D"; else note "META FAIL: N1 mutant not applied"; fi
mg N2 "hook ignores CLAUDE_CODE_EFFORT_LEVEL" "$H" '[[ -n "${CLAUDE_CODE_EFFORT_LEVEL:-}" && "${CLAUDE_CODE_EFFORT_LEVEL}" != "$te" ]]' '[[ -n "" ]]'
mg N3 "hook stops JSON-escaping the WARN payload" "$H" '"$(al_json_escape "$msg")"' '"$msg"'
mg N4 "installer fails open on an unknown identity" "$I" '  exit 6\nfi' '  :\nfi'
D=$(fresh_tree N5); mutate "$D" "$D/$L" "printf '%s' \"\$1\" | LC_ALL=C tr 'A-Z' 'a-z' | LC_ALL=C tr -c 'a-z0-9' '-'" "printf '%s' \"\$1\" | tr '[:upper:]' '[:lower:]' | tr -c '[:lower:][:digit:]' '-'"
if [ -n "$MUTATED" ]; then expect fail "N5 sanitiser locale-dependent" suite_in "$D" multitrack/test_gen_agent_label_defs.sh; else note "META FAIL: N5 mutant not applied"; fi
ms N6 "post-update hook back on mapfile" multitrack/test_install_agent_label_defs.sh scripts/post_update_hook.sh '|| sort_unique_into CHANGED_SKILLS  "${CHANGED_SKILLS[@]}"' '|| mapfile -t CHANGED_SKILLS < <(printf "%s\\n" "${CHANGED_SKILLS[@]}" | sort -u)'
mg N7 "installer stops excluding generated files from git" "$I" 'if [ "$git_exclude" -eq 1 ] && [ "$do_check" -eq 0 ] && [ "$dry" -eq 0 ]; then update_exclude; fi' ':'

mg N8 "a bare shellcheck disable= (no same-line reason) in the toolchain" "$L" '# shellcheck disable=SC2034 # read by the generator and installer that source this file' '# shellcheck disable=SC2034'

# round-3 mutants (review round 2: AL2-1, AL2-2, AL2-4) and reviewer-authored survivors RV1, RV2b, RV3
mg N9 "installer prunes another alias's generated types (AL2-1)" "$I" '        nkept_other=$((nkept_other+1)); continue      # another alias' '        :      # another alias'
mg N10 "prune leaves the export siblings behind (AL2-2)" "$I" '  for x in html pdf docx; do rm -f -- "$base.$x"; done' '  :'
mg N11 "hook back to a prefix match (AL2-4)" "$H" '      [[ "$r" =~ ^(sonnet|opus)-(low|medium|high|xhigh|max)$ ]]' '      [[ -n "$r" ]]'
ms RV1 "sort_unique_into without sort -u (reviewer)" multitrack/test_install_agent_label_defs.sh scripts/post_update_hook.sh "done < <(printf '%s\\\\n' \"\$@\" | sort -u)" "done < <(printf '%s\\\\n' \"\$@\")"
mg RV2b "exclude block drops the export siblings (reviewer)" "$I" "      for x in html pdf docx; do printf '/%s/%s.%s\\\\n' \"\$relq\" \"\$base\" \"\$x\"; done" '      : "$base"'
mg RV3 "al_json_escape keeps control characters (reviewer)" "$L" "printf '%s' \"\$s\" | LC_ALL=C tr -d '\\\\000-\\\\037'" "printf '%s' \"\$s\""

# round-4: exclude-block identity class (AL3-1) and reviewer-authored survivors RV4-RV7
mg N12 "exclude block keyed per relative dir again (shared by linked worktrees)" "$I" '  begin="# >>> agent-label-defs v2 ${od}"; end="# <<< agent-label-defs v2 ${od}"' '  begin="# >>> agent-label-defs v2 ${rel}"; end="# <<< agent-label-defs v2 ${rel}"'
ms N13 "exclude begin line matched by prefix again" multitrack/test_install_agent_label_defs.sh "$I" '    if (b == ENVIRON["B"]) return ENVIRON["E"]' '    if (index(b, ENVIRON["B"]) == 1) return ENVIRON["E"]'
ms N14 "--remove-alias ignores ownership (removes every alias's files)" multitrack/test_install_agent_label_defs.sh "$I" '      [ "$(al_sanitise "$(bash "$GEN" --owner-alias "$f")")" = "$ra" ] || continue' '      :'
ms RV4 "legacy end line matched without its T<N> suffix (reviewer)" multitrack/test_install_agent_label_defs.sh "$I" '      if (mid ~ /^T[0-9]+ $/) return "# <<< agent-label-defs " ENVIRON["R"] " " substr(mid, 1, length(mid) - 1)' '      if (mid ~ /^T[0-9]+ $/) return "# <<< agent-label-defs " ENVIRON["R"]'
ms RV5 "ownership compared on the raw label alias (reviewer)" multitrack/test_install_agent_label_defs.sh "$I" '      if [ "$(al_sanitise "$owner")" != "$my_alias" ]; then' '      if [ "$owner" != "$al" ]; then'
mg RV6 "ownership by prefix (reviewer)" "$I" '      if [ "$(al_sanitise "$owner")" != "$my_alias" ]; then' '      if [[ "$my_alias" != "$(al_sanitise "$owner")"* ]]; then'
ms RV7 "unknown-alias identity match accepts any remainder (reviewer)" hooks/test_guard_agent_type_label.sh "$H" '      [[ "$r" =~ ^[a-z0-9]+(-[a-z0-9]+)*-(sonnet|opus)-(low|medium|high|xhigh|max)$ ]]' '      true'

# round-5: exclude-block grammar (AL4-1, structural), --remove-alias flag matrix (AL4-2), and the
# reviewer-authored survivors HK1, RV13, RV15 (AL4-3)
TI=multitrack/test_install_agent_label_defs.sh
ms X1 "a begin pairs with an end past the next begin (lone begin swallows lines)" $TI "$I" '        if (index(C[j], "# >>> agent-label-defs ") == 1) { j = NR + 1; break }' '        if (0) { j = NR + 1; break }'
ms X2 "block keys escape-interpreted on the way into awk (the -v class)" $TI "$I" 'B="$begin" E="$end" R="$rel" S="$stale" awk' 'B="$(printf %b "$begin")" E="$(printf %b "$end")" R="$rel" S="$stale" awk'
ms X3 "read-modify-write of the shared exclude file without the lock" $TI "$I" '  excl_lock_take "$d" || {' '  true || {'
ms X4 "trailing CR not ignored when matching markers" $TI "$I" '  { L[NR] = $0; C[NR] = cr($0) }' '  { L[NR] = $0; C[NR] = $0 }'
ms X5 "orphan end marker of our key kept" $TI "$I" '    for (i = 1; i <= NR; i++) if (!drop[i] && C[i] == ENVIRON["E"]) drop[i] = 1' '    :'
ms X6 "stale-block collection drops blocks of directories that still exist" $TI "$I" '      [ -e "$k" ] && continue' '      :'
ms X7 "stale blocks never collected" $TI "$I" 'R="$rel" S="$stale" awk' 'R="$rel" S="" awk'
ms X8 "--remove-alias accepts any flag (e.g. --check deletes)" $TI "$I" '      *) die2 "flag' '      *) : "flag'
ms HK1 "hook ignores a label model that differs from the type's model (reviewer)" hooks/test_guard_agent_type_label.sh "$H" '    elif [[ -n "$lmodel" && "$lmodel" != "$tm" ]]; then' '    elif false; then'
# RV13: the entry refusal exists in the installer AND in the generator it calls; removing only one is
# an equivalent mutant (the other still refuses, nothing is written), so both sites are removed
D=$(fresh_tree RV13); mutate "$D" "$D/$I" 'al_path_ok "$out_dir" || die2 "out-dir contains a control character; refused (nothing written)"' ':'
[ -n "$MUTATED" ] && mutate "$D" "$D/scripts/multitrack/gen_agent_label_defs.sh" 'al_path_ok "$out_dir" || die2 "--out-dir contains a control character; refused (nothing written)"' ':'
if [ -n "$MUTATED" ]; then expect fail "RV13 control character (newline) in the out-dir no longer refused at entry (reviewer)" suite_in "$D" "$TI"; else note "META FAIL: RV13 mutant not applied"; fi
ms RV15 "--remove-alias deletes hand-edited files too (reviewer)" $TI "$I" '      [ "$(bash "$GEN" --classify "$f")" = genuine ] || continue' '      case "$(bash "$GEN" --classify "$f")" in genuine|edited) ;; *) continue ;; esac'

# round-6: flock required (AL5-1), one path rule (AL5-2), one value rule (AL5-5), doc drift (AL5-4),
# and the reviewer-authored survivors R1b, R17, R6 (AL5-3)
TG=multitrack/test_gen_agent_label_defs.sh
ms R1b "unmounted (still-listed) worktree's block collected (reviewer)" $TI "$I" '[ "$live" -eq 0 ] && stale=' '[ "$live" -ge 0 ] && stale='
ms R17 "stale block's end matched as our end (end + entries left behind) (reviewer)" $TI "$I" 'return "# <<< agent-label-defs v2 " substr(b, length(V2) + 1)' 'return ENVIRON["E"]'
ms R6 "--remove-alias --dry-run rewrites the exclude file (reviewer)" $TI "$I" '"$git_exclude" -eq 1 ] && [ "$dry" -eq 0 ]; then update_exclude' '"$git_exclude" -eq 1 ]; then update_exclude'
ms Y1 "path rule accepts control characters" $TI "$L" 'al_path_ok() { local LC_ALL=C; case "$1" in *[[:cntrl:]]*) return 1 ;; esac; return 0; }' 'al_path_ok() { return 0; }'
ms Y2 "installer takes the next flag (or nothing) as an option value" $TI "$I" 'need_val() { if [ "$1" -lt 2 ] || ! al_value_ok "$3"; then' 'need_val() { if [ "$1" -lt 1 ]; then'
ms Y3 "generator takes the next flag (or nothing) as an option value" $TG "$G" 'need_val() { if [ "$1" -lt 2 ] || ! al_value_ok "$3"; then' 'need_val() { if [ "$1" -lt 1 ]; then'
ms Y4 "installer writes without flock (requirement dropped)" $TI "$I" 'if [ "$need_lock" -eq 1 ] && ! command -v "$FLOCK"' 'if false && ! command -v "$FLOCK"'
ms Y5 "killed holder's temp file left behind" $TI "$I" '  rm -f -- "$excl".tmp.*' '  :'
ms Y6 "install doc case count drifts" $TI docs/scripts/install_agent_label_defs.md '`test_install_agent_label_defs.sh` (' '`test_install_agent_label_defs.sh` (1'
mg Y7 "CHANGELOG drops a mutation case id" CHANGELOG.md 'HK1' 'HKx'

# dispatch-log audit (gate-level)
D=$(fresh_tree a0)
mkdir -p "$T/aud/agents"; bash "$D/$G" --track 1 --branch main --alias claude1 --out-dir "$T/aud/agents" >/dev/null
printf '%s\n' '{"subagent_type":"general-purpose","description":"(T1/main - claude1 - opus - high) ATM-1 x"}' '{"subagent_type":"Explore","description":"(T1/main - claude1 - sonnet - low) y"}' >"$T/aud/bad.jsonl"
printf '%s\n' '{"subagent_type":"T1-main-claude1-sonnet-high","description":"(T1/main - claude1 - sonnet - high) y"}' '{"subagent_type":"plugin-dev:agent-creator","description":"(T1/main - claude1 - sonnet - low) z"}' '{"subagent_type":"general-purpose","description":"(T9/other - claude1 - sonnet - low) no types for T9"}' >"$T/aud/good.jsonl"
expect pass "A1 dispatch-log with a general-purpose dispatch, warn mode -> WARN only" bash "$D/scripts/gates/cm_agent_type_label.sh" --quiet --dispatch-log "$T/aud/bad.jsonl" --agents-dir "$T/aud/agents"
expect fail "A2 same log, enforce mode -> FAIL" bash "$D/scripts/gates/cm_agent_type_label.sh" --quiet --dispatch-log "$T/aud/bad.jsonl" --agents-dir "$T/aud/agents" --mode enforce
expect pass "A3 golden-FALSE log (labelled types, specialists, track without types), enforce -> PASS" bash "$D/scripts/gates/cm_agent_type_label.sh" --quiet --dispatch-log "$T/aud/good.jsonl" --agents-dir "$T/aud/agents" --mode enforce
grep -q 'WARN' <(bash "$D/scripts/gates/cm_agent_type_label.sh" --dispatch-log "$T/aud/bad.jsonl" --agents-dir "$T/aud/agents" 2>&1) && note "OK    A1b warn mode prints a WARN line" || { note "META FAIL: A1b warn mode prints a WARN line"; rc=1; }
expect fail "A4 unknown mode -> bad arg (nonzero)" bash "$D/scripts/gates/cm_agent_type_label.sh" --mode bogus
echo "----------------------------------------------------------------------"
[ "$rc" -eq 0 ] && { echo "META: PASS — CM-AGENT-TYPE-LABEL and its unit suites are not bluffs"; exit 0; } || { echo "META: FAIL — see above"; exit 1; }
