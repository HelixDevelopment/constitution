#!/usr/bin/env bash
# test_post_update_index_freshness.sh -- R4-01 wiring: the §11.4.164 post-update seam
# (scripts/post_update_hook.sh) must check constitution_index.yaml freshness on EVERY run (not only
# when skills/hooks changed), fail loudly with the regeneration command when the index is stale, and
# regenerate it when the operator opts in with CONST_INDEX_REGENERATE=1.
#
# Drives the REAL post_update_hook.sh against a scratch constitution root (a git repo holding the real
# Constitution.md, a fresh real generation, and a `scripts` link to the real scripts directory).
#   P1 fresh index                       -> exit 0, reports the index fresh, nothing written
#   P2 stale index                       -> exit 1, names it stale + the regenerate command, nothing written
#   P3 stale + CONST_INDEX_REGENERATE=1  -> exit 0, the index is regenerated (sha == source sha)
#   P4 stale index + a REAL propagation run (a commit adds skills/zz/SKILL.md AND amends Constitution.md, so
#      detect_changes finds a changed skill and the hook leaves the 'No relevant changes' early return)
#                                       -> exit 1, 'constitution index STALE' reported, never 'completed successfully'
#   P5 the cause is reported per rc: checker absent / generator absent (rc=4 BLIND) are NOT reported as a blanket STALE
# V5 N1 -- every non-STALE STEP-0 branch on the REAL propagation path (a skills/zz commit, so the hook leaves
# the 'No relevant changes' early return and its exit code comes ONLY from the ERRORS record; HOME, CONST_DIR
# and PROJECT_ROOT live in scratch; the scripts dir is a dir of links to the real entries, anchors/ likewise,
# with exactly one entry replaced per case). Each asserts rc=1 + the cause text of its ERRORS record + no
# 'completed successfully':
#   P6  generator absent       -> regenerate_if_stale.sh --check exits 4 (BLIND)
#   P7  lock not acquired      -> rc=75 (a stub checker: the real --check never takes the lock, so the branch is
#                                 defensive and only a stub can reach it)
#   P8  unexpected rc          -> rc=9 (stub checker)
#   P9  checker absent         -> 'could not be checked'
#   P10 regeneration fails     -> CONST_INDEX_REGENERATE=1, stale index, the REAL checker with an unrunnable generator
#   P10n the same on the 'No relevant changes' path -> exit 1 (there the exit code comes ONLY from INDEX_STALE)
# V5 N2 -- the drift check beyond the checksum (the seam's F5 check, now also in STEP 0):
#   P11n a hand-edited groups/*.md with a FRESH checksum, no propagation -> exit 1 'DRIFT', never 'index: fresh'
#   P11  the same on the propagation path -> exit 1, the DRIFT ERRORS record, never 'completed successfully'
#   P12  checker says fresh but the generator is absent -> exit 1 'drift check BLIND'
# Paired mutations (each one-place edit of a COPY of the hook must be caught by its NAMED case):
#   PU1 the freshness step removed from main() -> P2; RM-A the STALE ERRORS record dropped -> P4;
#   VG the BLIND ERRORS record dropped -> P6; VL the lock record -> P7; VU the unexpected-rc record -> P8;
#   VM the checker-absent record -> P9; VI the regeneration-failure record -> P10;
#   VH the regeneration-failure INDEX_STALE=1 dropped -> P10n; VD the drift branch disabled -> P11n;
#   VD2 the drift ERRORS record dropped -> P11; VB the drift generator-absent guard disabled -> P12;
#   PD1 sort_unique_inplace's append made a no-op -> P14.
# V5 F7: P13 static bash>=4 scan (with a control needle), P14 sort_unique_inplace behaviour.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CROOT="$(cd "$HERE/../../.." && pwd)"
HOOK="${POST_UPDATE_HOOK_UNDER_TEST:-$CROOT/scripts/post_update_hook.sh}"
GEN="$CROOT/scripts/anchors/constitution_generate.py"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }
for dep in git python3 sha256sum; do
  command -v "$dep" >/dev/null 2>&1 || { echo "BLIND: required dependency '$dep' not usable" >&2; exit 4; }
done
TMP=$(mktemp -d) || { echo "BLIND: mktemp failed" >&2; exit 4; }
trap 'rm -rf "$TMP"' EXIT

mkconst() { # mkconst <dir>: a scratch constitution root that is its own git repo
  mkdir -p "$1"
  cp "$CROOT/Constitution.md" "$1/Constitution.md"
  ln -s "$CROOT/scripts" "$1/scripts"
  python3 "$GEN" generate --source "$1/Constitution.md" --groups-dir "$1/groups" --index-out "$1/constitution_index.yaml" >/dev/null 2>&1 \
    || { echo "BLIND: generator failed for the scratch root" >&2; exit 4; }
  git -C "$1" init -q -b main
  git -C "$1" -c user.name=t -c user.email=t@example.invalid add Constitution.md constitution_index.yaml groups
  git -C "$1" -c user.name=t -c user.email=t@example.invalid commit -q -m init
}
idx_sha() { sed -n 's/^  source_sha256: *'"'"'\{0,1\}\([0-9a-f]\{64\}\).*/\1/p' "$1" | head -n 1; }
hook() { # hook <const dir> [ENV=VAL ...] -> RC, OUT
  local c=$1; shift
  mkdir -p "$TMP/project"
  OUT=$(cd "$TMP/project" && env CONST_DIR="$c" PROJECT_ROOT="$TMP/project" "$@" bash "$HOOK" 2>&1); RC=$?
}

C="$TMP/c_fresh"; mkconst "$C"
S0=$(sha256sum < "$C/constitution_index.yaml")
hook "$C"
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'constitution index: fresh' && [ "$(sha256sum < "$C/constitution_index.yaml")" = "$S0" ]; then
  ok "P1 fresh index: exit 0, reported fresh, index untouched"
else bad "P1 fresh: rc=$RC out=[$(printf '%s' "$OUT" | tail -n 8)]"; fi

C="$TMP/c_stale"; mkconst "$C"
printf '\nAn amendment appended after the index was generated.\n' >> "$C/Constitution.md"
S0=$(sha256sum < "$C/constitution_index.yaml")
hook "$C"
if [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q 'constitution index: STALE' \
   && printf '%s' "$OUT" | grep -q 'regenerate_if_stale.sh' && [ "$(sha256sum < "$C/constitution_index.yaml")" = "$S0" ]; then
  ok "P2 stale index: exit 1, named STALE with the regenerate command, index untouched"
else bad "P2 stale: rc=$RC out=[$(printf '%s' "$OUT" | tail -n 8)]"; fi

hook "$C" CONST_INDEX_REGENERATE=1
if [ "$RC" -eq 0 ] && [ "$(idx_sha "$C/constitution_index.yaml")" = "$(sha256sum < "$C/Constitution.md" | cut -c1-64)" ] \
   && printf '%s' "$OUT" | grep -q 'constitution index: regenerated'; then
  ok "P3 stale + CONST_INDEX_REGENERATE=1: exit 0, the index is regenerated"
else bad "P3 opt-in regeneration: rc=$RC out=[$(printf '%s' "$OUT" | tail -n 8)]"; fi

# P4: the full-propagation path. HOME / CONST_DIR / PROJECT_ROOT all live in scratch.
hook_prop() { # hook_prop <const dir> -> RC, OUT (HOME isolated; scratch project)
  local c=$1; shift
  rm -rf "$TMP/project4"; mkdir -p "$TMP/project4" "$TMP/home4"
  OUT=$(cd "$TMP/project4" && env HOME="$TMP/home4" CONST_DIR="$c" PROJECT_ROOT="$TMP/project4" "$@" bash "$HOOK" 2>&1); RC=$?
}
addskill() { # addskill <dir>
  mkdir -p "$1/skills/zz"
  printf -- '---\nname: zz\ndescription: scratch skill for P4\n---\nbody\n' > "$1/skills/zz/SKILL.md"
}
C="$TMP/c_prop"; mkconst "$C"; addskill "$C"
printf '\nAn amendment appended after the index was generated (P4).\n' >> "$C/Constitution.md"
git -C "$C" -c user.name=t -c user.email=t@example.invalid add skills Constitution.md
git -C "$C" -c user.name=t -c user.email=t@example.invalid commit -q -m "add skill + amend (index left stale)"
hook_prop "$C"
if [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q 'constitution index STALE' \
   && printf '%s' "$OUT" | grep -q 'Detected: 1 skill' && ! printf '%s' "$OUT" | grep -q 'completed successfully' \
   && ! printf '%s' "$OUT" | grep -q 'No relevant changes'; then
  ok "P4 stale index on the full propagation path: exit 1, 'constitution index STALE' recorded, never 'completed successfully'"
else bad "P4 propagation path: rc=$RC out=[$(printf '%s' "$OUT" | tail -n 14)]"; fi
# control: fresh index + a changed skill propagates and exits 0 (P4 must not fail merely because propagation ran)
C="$TMP/c_prop_ok"; mkconst "$C"; addskill "$C"
git -C "$C" -c user.name=t -c user.email=t@example.invalid add skills
git -C "$C" -c user.name=t -c user.email=t@example.invalid commit -q -m "add skill only"
hook_prop "$C"
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'Detected: 1 skill' && printf '%s' "$OUT" | grep -q 'completed successfully'; then
  ok "P4c control: fresh index + a changed skill propagates and exits 0"
else bad "P4c control: rc=$RC out=[$(printf '%s' "$OUT" | tail -n 14)]"; fi

# P5: the cause per rc.
C="$TMP/c_noreg"; mkconst "$C"; rm "$C/scripts"; mkdir -p "$C/scripts/anchors"
hook "$C"
if [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q 'cannot be checked' && ! printf '%s' "$OUT" | grep -q 'STALE against'; then
  ok "P5 checker absent: exit 1, reported as 'cannot be checked' (not a blanket STALE)"
else bad "P5 checker absent: rc=$RC out=[$(printf '%s' "$OUT" | tail -n 8)]"; fi
C="$TMP/c_blind"; mkconst "$C"; rm "$C/scripts"; mkdir -p "$C/scripts/anchors"
cp "$CROOT/scripts/anchors/regenerate_if_stale.sh" "$C/scripts/anchors/"
hook "$C"
if [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q 'BLIND (rc=4)' && ! printf '%s' "$OUT" | grep -q 'STALE against'; then
  ok "P5b generator absent: exit 1, reported as BLIND (rc=4), not STALE"
else bad "P5b rc=4: rc=$RC out=[$(printf '%s' "$OUT" | tail -n 8)]"; fi

# V5 N1/N2 fixtures. mkscripts replaces the scripts symlink with a dir of per-entry links to the real
# scripts (anchors/ likewise), so a case can swap exactly one entry; the propagation fixtures commit a new
# skill so the hook runs its full propagation path.
mkscripts() { # mkscripts <const dir>
  local d="$1/scripts" e
  rm -f "$d"; mkdir -p "$d/anchors"
  for e in "$CROOT"/scripts/* "$CROOT"/scripts/.[!.]*; do
    [ -e "$e" ] || continue
    [ "$(basename "$e")" = anchors ] && continue
    ln -s "$e" "$d/$(basename "$e")"
  done
  for e in "$CROOT"/scripts/anchors/*; do
    [ -e "$e" ] && ln -s "$e" "$d/anchors/$(basename "$e")"
  done
}
stubregen() { # stubregen <const dir> <rc> : replace the checker with a stub that exits <rc>
  rm -f "$1/scripts/anchors/regenerate_if_stale.sh"
  printf '%s\n' '#!/usr/bin/env bash' "echo 'STUB checker exiting $2' >&2" "exit $2" > "$1/scripts/anchors/regenerate_if_stale.sh"
}
badgen() { # badgen <const dir> : the generator becomes unrunnable (the checker itself stays the real script)
  rm -f "$1/scripts/anchors/constitution_generate.py"
  printf 'raise SystemExit("generator made unrunnable by the test")\n' > "$1/scripts/anchors/constitution_generate.py"
}
propcommit() { # propcommit <const dir> [amend] : commit a new skill (and optionally an amendment) on top of init
  addskill "$1"
  [ "${2:-}" = amend ] && printf '\nAn amendment appended after the index was generated (prop).\n' >> "$1/Constitution.md"
  git -C "$1" -c user.name=t -c user.email=t@example.invalid add -A skills Constitution.md groups
  git -C "$1" -c user.name=t -c user.email=t@example.invalid commit -q -m "prop fixture"
}
prop_fail() { # prop_fail <case> <ERRORS record text> : rc=1, the record in the summary, propagation ran, no success line
  if [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -qF -- "- $2" && printf '%s' "$OUT" | grep -q 'Detected: 1 skill' \
     && ! printf '%s' "$OUT" | grep -q 'completed successfully' && ! printf '%s' "$OUT" | grep -q 'No relevant changes'; then
    ok "$1 propagation path: exit 1, ERRORS record '$2', never 'completed successfully'"
  else bad "$1 propagation path: rc=$RC out=[$(printf '%s' "$OUT" | tail -n 14)]"; fi
}

C="$TMP/c_p6"; mkconst "$C"; mkscripts "$C"; rm -f "$C/scripts/anchors/constitution_generate.py"; propcommit "$C"
hook_prop "$C"; prop_fail P6 'constitution index freshness BLIND (rc=4: generator/source unreadable)'
C="$TMP/c_p7"; mkconst "$C"; mkscripts "$C"; stubregen "$C" 75; propcommit "$C"
hook_prop "$C"; prop_fail P7 'constitution index freshness check blocked by lock (rc=75)'
C="$TMP/c_p8"; mkconst "$C"; mkscripts "$C"; stubregen "$C" 9; propcommit "$C"
hook_prop "$C"; prop_fail P8 'constitution index freshness check failed (unexpected rc=9)'
C="$TMP/c_p9"; mkconst "$C"; mkscripts "$C"; rm -f "$C/scripts/anchors/regenerate_if_stale.sh"; propcommit "$C"
hook_prop "$C"; prop_fail P9 'constitution index freshness could not be checked'
C="$TMP/c_p10"; mkconst "$C"; mkscripts "$C"; badgen "$C"; propcommit "$C" amend
hook_prop "$C" CONST_INDEX_REGENERATE=1; prop_fail P10 'constitution index regeneration failed'
C="$TMP/c_p10n"; mkconst "$C"; mkscripts "$C"; badgen "$C"
printf '\nAn amendment appended after the index was generated (P10n).\n' >> "$C/Constitution.md"
hook "$C" CONST_INDEX_REGENERATE=1
if [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q 'regeneration FAILED' && printf '%s' "$OUT" | grep -q 'No relevant changes'; then
  ok "P10n regeneration failure without propagation: exit 1 (INDEX_STALE)"
else bad "P10n regeneration failure (no propagation): rc=$RC out=[$(printf '%s' "$OUT" | tail -n 8)]"; fi

# N2: a hand-edited generated group with a FRESH checksum (the checker alone says fresh).
C="$TMP/c_p11n"; mkconst "$C"; printf '\nhand edit\n' >> "$C/groups/testing-and-tdd.md"
hook "$C"
if [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q 'DRIFT' && ! printf '%s' "$OUT" | grep -q 'constitution index: fresh'; then
  ok "P11n hand-edited group, fresh checksum, no propagation: exit 1 'DRIFT', never 'index: fresh'"
else bad "P11n drift (no propagation): rc=$RC out=[$(printf '%s' "$OUT" | tail -n 8)]"; fi
C="$TMP/c_p11"; mkconst "$C"; printf '\nhand edit\n' >> "$C/groups/testing-and-tdd.md"; propcommit "$C"
hook_prop "$C"; prop_fail P11 'constitution index/groups DRIFT from a fresh generation of Constitution.md'
C="$TMP/c_p12"; mkconst "$C"; mkscripts "$C"; stubregen "$C" 0; rm -f "$C/scripts/anchors/constitution_generate.py"
hook "$C"
if [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q 'drift check BLIND' && ! printf '%s' "$OUT" | grep -q 'constitution index: fresh'; then
  ok "P12 checker fresh but generator absent: exit 1 'drift check BLIND'"
else bad "P12 drift generator absent: rc=$RC out=[$(printf '%s' "$OUT" | tail -n 8)]"; fi

mutant_home() { # mutant_home <mutant file> -> prints path of a scripts dir where post_update_hook.sh is the mutant
  # and every other entry is a symlink to the real scripts dir, so the mutant differs from the real hook ONLY by the edit.
  local m=$1 d e
  d="$TMP/mscripts_$(basename "$1" .sh)"
  mkdir -p "$d"
  for e in "$CROOT"/scripts/* "$CROOT"/scripts/.[!.]*; do
    [ -e "$e" ] || continue
    [ "$(basename "$e")" = post_update_hook.sh ] && continue
    ln -sfn "$e" "$d/$(basename "$e")"
  done
  cp "$m" "$d/post_update_hook.sh"
  printf '%s' "$d/post_update_hook.sh"
}

# mutate_hook <name> <named case> <mode> <needle>: modes -- line (the unique line containing <needle> becomes
# ':'), exact (the unique line EQUAL to <needle> becomes ':'), nextline (the line AFTER it becomes ':'), iffalse (the 'if <cond>; then' test on the unique line
# containing <needle> becomes 'if false; then'). The mutant must make its NAMED case FAIL.
mutate_hook() {
  local name=$1 case=$2 m="$TMP/mut_$1.sh"
  if ! python3 - "$HOOK" "$m" "$3" "$4" <<'PY'
import re, sys
src, dst, mode, needle = sys.argv[1:5]
lines = open(src, encoding="utf-8").read().split("\n")
hits = [i for i, l in enumerate(lines) if (l == needle if mode == "exact" else needle in l)]
if len(hits) != 1:
    print("needle occurs on %d lines: %r" % (len(hits), needle)); sys.exit(2)
i = hits[0] + (1 if mode == "nextline" else 0)
indent = re.match(r"\s*", lines[i]).group(0)
if mode in ("line", "nextline", "exact"):
    lines[i] = indent + ":"
elif mode == "barearray":
    new = re.sub(r'\$\{(\w+)\[@\]\+"\$\{\1\[@\]\}"\}', r'"${\1[@]}"', lines[i], count=1)
    if new == lines[i]:
        print("no guarded array expansion on the needle line"); sys.exit(2)
    lines[i] = new
elif mode == "iffalse":
    new = re.sub(r"\bif .*; then", "if false; then", lines[i], count=1)
    if new == lines[i]:
        print("no if-test on the needle line"); sys.exit(2)
    lines[i] = new
else:
    sys.exit(2)
open(dst, "w", encoding="utf-8").write("\n".join(lines))
PY
  then bad "mutation $name could not be applied"; return; fi
  if POST_UPDATE_HOOK_UNDER_TEST="$(mutant_home "$m")" bash "$0" > "$TMP/mut_$name.out" 2>&1; then
    bad "mutation $name SURVIVED"
  elif grep -q "^FAIL: $case " "$TMP/mut_$name.out"; then
    ok "mutation $name caught by $case ($(grep -m1 "^FAIL: $case " "$TMP/mut_$name.out" | cut -c1-90))"
  else bad "mutation $name failed the suite but NOT via $case ($(grep -m1 '^FAIL' "$TMP/mut_$name.out" | cut -c1-90))"; fi
}

# V5 F7 -- bash 3.2 portability (macOS /bin/bash). P13 is a static scan of the hook's CODE lines (comment lines
# removed) for builtins/expansions that need bash >= 4.0, with a positive control (the same scan must HIT a
# fixture carrying `mapfile`) so a zero is a measured zero (§11.4.273), not a blind instrument. P14 drives the
# hook's real sort_unique_inplace (extracted from the hook under test) on elements a word-splitting / globbing
# implementation would mangle. No bash 3.2 binary is installed on this host, so P13 is the portability evidence
# and P14 the behaviour evidence; neither is an execution under bash 3.2 (§11.4.6).
bash4_scan() { # bash4_scan <file>: prints offending code lines (comment-only lines skipped)
  python3 - "$1" <<'PY'
import re, sys
pat = re.compile(r"\b(mapfile|readarray|coproc)\b|\b(declare|local|typeset) +-[a-zA-Z]*A|\$\{[A-Za-z_][A-Za-z0-9_]*(,,|\^\^|,|\^)\}|;&|;;&")
for n, l in enumerate(open(sys.argv[1], encoding="utf-8").read().split("\n"), 1):
    if l.lstrip().startswith("#"):
        continue
    if pat.search(l):
        print("%d: %s" % (n, l.strip()))
PY
}
printf 'x() {\n  mapfile -t A < <(printf "a\\n")\n}\n' > "$TMP/bash4_needle.sh"
needle=$(bash4_scan "$TMP/bash4_needle.sh"); hits=$(bash4_scan "$HOOK")
if [ -n "$needle" ] && [ -z "$hits" ]; then ok "P13 the hook uses no bash>=4 builtin/expansion (control needle hit: $needle)"
else bad "P13 bash-3.2 portability: needle=[$needle] hits=[$hits]"; fi
sed -n '/^sort_unique_inplace() {/,/^}/p' "$HOOK" > "$TMP/su_fn.sh"
cat > "$TMP/su_drive.sh" <<'DRIVE'
set -euo pipefail
. "$1"
A=("b c" "*" "a" "b c" "")
IFS=$'\n'
sort_unique_inplace A
printf '[%s]' "${A[@]}"
printf ' n=%s' "${#A[@]}"
DRIVE
if [ ! -s "$TMP/su_fn.sh" ]; then bad "P14 sort_unique_inplace absent from the hook under test"
else
  got=$(bash "$TMP/su_drive.sh" "$TMP/su_fn.sh" 2>&1)
  if [ "$got" = "[*][a][b c] n=3" ]; then ok "P14 sort_unique_inplace keeps '*' and 'b c' intact, de-duplicates, drops empties ($got)"
  else bad "P14 sort_unique_inplace: got [$got]"; fi
fi

# V5 STRUCTURAL R7 -- `"${ARR[@]}"` on an EMPTY array aborts with "unbound variable" under `set -u` on bash < 4.4
# (the hook runs `set -euo pipefail`; its own arr_len comment records the hazard). P13 cannot see this construct, so
# P15 scans every CODE line for a bare `"${NAME[@]}"` / `"${NAME[*]}"` that is not the guarded
# `${NAME[@]+"${NAME[@]}"}` form; the control needle (a fixture with one bare and one guarded expansion) must hit
# exactly the bare line, so a zero is a measured zero. Static evidence only: no bash < 4.4 binary is installed on
# this host (§11.4.6).
bare_array_scan() { # bare_array_scan <file>: prints offending code lines
  python3 - "$1" <<'PY'
import re, sys
pat = re.compile(r'(?<!\[@\]\+)(?<!\[\*\]\+)"\$\{[A-Za-z_][A-Za-z0-9_]*\[[@*]\]\}"')
for n, l in enumerate(open(sys.argv[1], encoding="utf-8").read().split("\n"), 1):
    if l.lstrip().startswith("#"):
        continue
    if pat.search(l):
        print("%d: %s" % (n, l.strip()))
PY
}
printf 'A=()\nfor a in "${A[@]}"; do :; done\nfor b in ${A[@]+"${A[@]}"}; do :; done\n' > "$TMP/bare_needle.sh"
bneedle=$(bare_array_scan "$TMP/bare_needle.sh"); bhits=$(bare_array_scan "$HOOK")
if [ "$(printf '%s\n' "$bneedle" | grep -c .)" = 1 ] && printf '%s' "$bneedle" | grep -q '^2:' && [ -z "$bhits" ]; then
  ok "P15 R7: no bare \"\${ARR[@]}\" expansion in the hook (control needle: the bare line hits, the guarded line does not)"
else bad "P15 R7 bare array expansion: needle=[$bneedle] hits=[$(printf '%s' "$bhits" | head -n 5 | tr '\n' ' ')]"; fi

if [ -z "${POST_UPDATE_HOOK_UNDER_TEST:-}" ]; then
  mutate_hook PU1_no_index_check P2 exact '    check_constitution_index'
  mutate_hook RM-A_no_stale_record P4 line 'ERRORS+=("constitution index STALE against Constitution.md")'
  mutate_hook VG_no_blind_record P6 line 'ERRORS+=("constitution index freshness BLIND (rc=4'
  mutate_hook VL_no_lock_record P7 line 'ERRORS+=("constitution index freshness check blocked by lock'
  mutate_hook VU_no_unexpected_record P8 line 'ERRORS+=("constitution index freshness check failed (unexpected'
  mutate_hook VM_no_checker_absent_record P9 line 'ERRORS+=("constitution index freshness could not be checked'
  mutate_hook VI_no_regen_failure_record P10 line 'ERRORS+=("constitution index regeneration failed")'
  mutate_hook VH_regen_failure_not_stale P10n nextline 'ERRORS+=("constitution index regeneration failed")'
  mutate_hook VD_drift_branch_off P11n iffalse 'drc" -ne 0 ]; then'
  mutate_hook VD2_no_drift_record P11 line 'ERRORS+=("constitution index/groups DRIFT'
  mutate_hook VB_drift_gen_guard_off P12 iffalse 'drift-check generator guard'
  mutate_hook PD1_dedup_drops_elements P14 line '+=(\"'
  mutate_hook PD2_bare_array_restored P15 barearray 'for skill_name in ${CHANGED_SKILLS[@]+'
  mutate_hook PD3_bare_array_restored_summary P15 barearray 'for w in ${WARNINGS[@]+'
fi

echo "SUMMARY pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
