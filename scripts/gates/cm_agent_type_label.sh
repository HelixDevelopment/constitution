#!/usr/bin/env bash
# cm_agent_type_label.sh — CM-AGENT-TYPE-LABEL gate (§11.4.182 / §11.4.231(F)).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# §11.4.182/§11.4.231(F) bake the work-stream label into GENERATED agent types
# named T<N>-<branch>-<alias>-<model>-<effort> (model + effort set by the
# definition; the hook flags overrides: WARN, BLOCK under ENFORCE). This gate proves the toolchain really
# does that, by BEHAVIOUR (drives the real generator, installer and hook in a
# throwaway fixture):
#   1 PRESENCE+EXEC+PARSE  generator, installer, hook, naming library, frontmatter checker, colour
#                          data file and the three convention docs exist; shell
#                          files parse (bash -n), the python checker compiles.
#   2 GENERATION           a fixture track/branch/alias yields exactly the 4
#                          default files, each named T<N>-<branch>-<alias>-<model>-
#                          <effort>, each passing the strict independent parser;
#                          a '?' alias is refused.
#   3 IDEMPOTENCE          a second run is byte-identical and reports written=0.
#   4 CHECK                --check: clean=0; a deleted file=1; a hand-edited
#                          generated file=1.
#   5 REFUSAL              a hand-made colliding file (exit 3) and a hand-edited
#                          generated BODY (exit 4) are NEVER overwritten.
#   6 INSTALLER            unknown identity -> exit 6 with nothing touched (even
#                          with a malformed multitrack config present); installs
#                          the live identity; prunes only v1 files and THIS
#                          alias's superseded generated files, with their export
#                          siblings; keeps other aliases' generated types and
#                          hand-made / hand-edited files; --dry-run touches
#                          nothing; every generated file + sibling stays out of
#                          git status. Also: every shellcheck disable= in the
#                          toolchain carries a same-line reason.
#   7 HOOK                 catch-all dispatch (general-purpose / claude / empty)
#                          with generated types present: WARN (valid JSON) by
#                          default, exit 2 under AGENT_TYPE_LABEL_ENFORCE=1;
#                          other-track type, label/type mismatch, per-dispatch
#                          model/effort override and CLAUDE_CODE_EFFORT_LEVEL
#                          override blocked; specialists never touched; stale
#                          identity WARN-only; hostile input keeps JSON valid.
#   8 DISPATCH-LOG (optional, --dispatch-log F --agents-dir D [--mode M])
#                          audit a JSONL of {subagent_type,description} dispatches:
#                          each general-purpose/empty dispatch whose label track
#                          has generated types is a finding — WARN in `warn` mode
#                          (exit 0), FAIL in `enforce` mode (exit 1).
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_agent_type_label.sh [--gen P] [--installer P] [--hook P] [--checker P]
#       [--colors P] [--doc-dir D] [--dispatch-log F] [--agents-dir D]
#       [--mode warn|enforce] [--quiet]
#   Defaults resolve the sibling files of this script's constitution tree.
# ── Outputs / exit codes ─────────────────────────────────────────────────────
#   Per-check lines + summary. 0 = all hold · 1 = a check failed (or enforce-mode
#   dispatch finding) · 2 = bad argument.
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Temp fixture under ${TMPDIR:-/tmp}, removed on exit. Read-only on the tree.
# ── Cross-refs ───────────────────────────────────────────────────────────────
#   §11.4.182, §11.4.231(F), §11.4.201 (golden-FALSE: specialists and track
#   without types are never findings), §1.1 (paired mutation test:
#   cm_agent_type_label_mutation_test.sh), §11.4.18 (docs).
# Classification: universal (§11.4.17).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd -P)"
GATE="CM-AGENT-TYPE-LABEL"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
gen="$ROOT/scripts/multitrack/gen_agent_label_defs.sh"
inst="$ROOT/scripts/multitrack/install_agent_label_defs.sh"
hook="$ROOT/scripts/hooks/guard-track-branch-label.sh"
chk="$ROOT/scripts/multitrack/agent_label_frontmatter_check.py"
lib="$ROOT/scripts/multitrack/agent_label_lib.sh"
colors="$ROOT/scripts/multitrack/agent_label_colors.tsv"
docdir="$ROOT/docs/scripts"
dlog=""; adir=""; mode="warn"; quiet=""
while [ $# -gt 0 ]; do
  case "$1" in
    --gen) gen="$2"; shift 2 ;; --installer) inst="$2"; shift 2 ;; --hook) hook="$2"; shift 2 ;;
    --checker) chk="$2"; shift 2 ;; --lib) lib="$2"; shift 2 ;; --colors) colors="$2"; shift 2 ;; --doc-dir) docdir="$2"; shift 2 ;;
    --dispatch-log) dlog="$2"; shift 2 ;; --agents-dir) adir="$2"; shift 2 ;;
    --mode) mode="$2"; shift 2 ;; --quiet) quiet=1; shift ;;
    -h|--help) sed -n '2,60p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "${GATE}: unknown arg '$1'" >&2; exit 2 ;;
  esac
done
case "$mode" in warn|enforce) ;; *) echo "${GATE}: --mode must be warn|enforce" >&2; exit 2 ;; esac

fail=0
say() { [ -n "$quiet" ] || echo "$@"; }
ko() { echo "❌ $*"; fail=1; }
W="$(mktemp -d "${TMPDIR:-/tmp}/cm_atl.XXXXXX")"
trap 'rm -rf "$W"' EXIT

# ── 1 PRESENCE + EXEC + PARSE ────────────────────────────────────────────────
for pair in "generator:$gen" "installer:$inst" "hook:$hook" "naming library:$lib"; do
  n="${pair%%:*}"; p="${pair#*:}"
  if [ ! -r "$p" ]; then ko "PRESENCE: $n not found: $p"; continue; fi
  [ "$n" = "naming library" ] || [ -x "$p" ] || ko "EXEC: $n not executable: $p"
  bash -n "$p" 2>/dev/null && say "✅ PRESENCE+PARSE: $n" || ko "PARSEABILITY: $n fails bash -n"
done
[ -r "$chk" ] && python3 -I -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$chk" 2>/dev/null && say "✅ PRESENCE+PARSE: frontmatter checker" || ko "PRESENCE/PARSE: frontmatter checker missing or not compilable: $chk"
[ -s "$colors" ] && say "✅ PRESENCE: colour data" || ko "PRESENCE: colour data missing/empty: $colors"
for d in gen_agent_label_defs.md install_agent_label_defs.md guard-track-branch-label.md; do
  [ -s "$docdir/$d" ] && say "✅ DOC: $d" || ko "DOC: $docdir/$d missing/empty"
done
# the CHANGELOG lists every case id the paired-mutation meta-test runs (AL5-4: the list can never
# drift; ranges like M1-M14 or RV3-RV7 are expanded; the clean-copy controls M0* are exempt)
mut="$ROOT/scripts/gates/cm_agent_type_label_mutation_test.sh"; clog="$ROOT/CHANGELOG.md"
if [ -r "$mut" ] && [ -r "$clog" ]; then
  if miss="$(python3 -I - "$mut" "$clog" <<'PY2'
import re, sys
src = open(sys.argv[1]).read()
ids = set(re.findall(r'^(?:mg|ms) ([A-Z]+[0-9]+[a-z]?) ', src, re.M))
ids |= set(re.findall(r'expect (?:pass|fail) "([A-Z]+[0-9]+[a-z]?) ', src))
ids = {i for i in ids if not i.startswith('M0')}
line = next((l for l in open(sys.argv[2]) if 'cm_agent_type_label_mutation_test.sh' in l), '')
listed = set()
for m in re.finditer(r'\b([A-Z]+)([0-9]+)([a-z]?)(?:-(?:\1)?([0-9]+))?\b', line):
    p, a, suf, b = m.group(1), int(m.group(2)), m.group(3), m.group(4)
    if b is None:
        listed.add('%s%d%s' % (p, a, suf))
    else:
        listed.update('%s%d' % (p, k) for k in range(a, int(b) + 1))
if not ids:
    print('NO-IDS-FOUND'); sys.exit(1)
missing = sorted(ids - listed)
print(' '.join(missing)); sys.exit(1 if missing else 0)
PY2
)"; then say "✅ DOC: CHANGELOG lists every mutation case id the meta-test runs"
  else ko "DOC: CHANGELOG mutation-case list is missing: ${miss}"; fi
else ko "DOC: mutation meta-test or CHANGELOG missing ($mut, $clog)"; fi
# every shellcheck disable= directive in the toolchain carries a same-line justification
# (the review gate's D5 rule: the reason sits on the SAME line, after " # ")
nbare=0
for p in "$gen" "$inst" "$hook" "$lib"; do
  [ -r "$p" ] || continue
  while IFS= read -r ln; do
    printf '%s\n' "$ln" | grep -Eq 'disable=[^ ]+ +# +[A-Za-z][^#]{15,}' || { nbare=$((nbare+1)); echo "   bare directive in ${p##*/}: ${ln}" >&2; }
  done < <(grep -E '#[[:space:]]*shellcheck[[:space:]].*disable=' "$p")
done
[ "$nbare" -eq 0 ] && say "✅ DIRECTIVES: every shellcheck disable= carries a same-line justification" || ko "DIRECTIVES: ${nbare} shellcheck disable= directive(s) without a same-line justification"
if [ "$fail" -ne 0 ]; then echo "${GATE}: FAIL (presence/parse)"; exit 1; fi

tree_hash() { (cd "$1" && find . -type f | LC_ALL=C sort | xargs sha256sum 2>/dev/null | sha256sum | cut -d' ' -f1); }

# ── 2 GENERATION ────────────────────────────────────────────────────────────────
G="$W/gen"; GA=(--track 7 --branch 'Gate/Branch_X.1' --alias 'gatealias')
bash "$gen" "${GA[@]}" --out-dir "$G" >"$W/g.out" 2>"$W/g.err"; rc=$?
if [ "$rc" -ne 0 ]; then ko "GENERATION: generator exited $rc ($(head -c 200 "$W/g.err"))"; fi
want="T7-gate-branch-x-1-gatealias-opus-high.md T7-gate-branch-x-1-gatealias-opus-xhigh.md T7-gate-branch-x-1-gatealias-sonnet-high.md T7-gate-branch-x-1-gatealias-sonnet-medium.md "
got="$(ls "$G" 2>/dev/null | LC_ALL=C sort | tr '\n' ' ')"
if [ "$want" = "$got" ]; then say "✅ GENERATION: default 4 files, exact T<N>-<branch>-<alias>-<model>-<effort> names"; else ko "GENERATION: file set differs (want: $want | got: $got)"; fi
if ls "$G"/*.md >/dev/null 2>&1; then
  if python3 -I "$chk" "$G"/*.md >"$W/c.out" 2>&1; then say "✅ GENERATION: every file passes the strict independent frontmatter parse"; else ko "GENERATION: strict frontmatter parse failed: $(grep -m2 BAD "$W/c.out")"; fi
fi
bash "$gen" --track 7 --branch main --alias '?' --out-dir "$W/q" >/dev/null 2>&1; r_q=$?
[ "$r_q" -eq 2 ] && [ ! -e "$W/q" ] && say "✅ GENERATION: an unknown ('?') alias is refused, nothing written" || ko "GENERATION: '?' alias not refused (exit $r_q)"
# ── 3 IDEMPOTENCE ───────────────────────────────────────────────────────────────
h1="$(tree_hash "$G")"
bash "$gen" "${GA[@]}" --out-dir "$G" >"$W/g2.out" 2>&1
if [ "$h1" = "$(tree_hash "$G")" ] && grep -q 'written=0' "$W/g2.out"; then say "✅ IDEMPOTENCE: rerun byte-identical, written=0"; else ko "IDEMPOTENCE: rerun changed bytes or wrote files"; fi
bash "$gen" "${GA[@]}" --out-dir "$W/gen2" >/dev/null 2>&1
[ "$h1" = "$(tree_hash "$W/gen2")" ] && say "✅ DETERMINISM: same bytes in a second out-dir" || ko "DETERMINISM: bytes differ between out-dirs"
# ── 4 CHECK ───────────────────────────────────────────────────────────────────────
n1="T7-gate-branch-x-1-gatealias-opus-high.md"
bash "$gen" "${GA[@]}" --out-dir "$G" --check >/dev/null 2>&1; r_clean=$?
cp -r "$G" "$W/d1"; rm "$W/d1/$n1"
bash "$gen" "${GA[@]}" --out-dir "$W/d1" --check >/dev/null 2>&1; r_miss=$?
cp -r "$G" "$W/d2"; sed -i 's/^color: .*/color: red/' "$W/d2/$n1"
bash "$gen" "${GA[@]}" --out-dir "$W/d2" --check >/dev/null 2>&1; r_edit=$?
[ "$r_clean" -eq 0 ] && say "✅ CHECK: clean tree -> 0" || ko "CHECK: clean tree exited $r_clean (want 0)"
[ "$r_miss" -eq 1 ] && say "✅ CHECK: missing generated file -> 1" || ko "CHECK: missing file exited $r_miss (want 1) — drift check is blind"
[ "$r_edit" -eq 1 ] && say "✅ CHECK: hand-edited generated file -> 1" || ko "CHECK: hand-edit exited $r_edit (want 1) — drift check is blind"
# ── 5 REFUSAL ────────────────────────────────────────────────────────────────────
mkdir -p "$W/hm"; printf -- '---\nname: T7-gate-branch-x-1-gatealias-sonnet-high\ndescription: "hand"\nmodel: sonnet\neffort: high\ncolor: red\n---\nHAND\n' >"$W/hm/T7-gate-branch-x-1-gatealias-sonnet-high.md"
b1="$(sha256sum "$W/hm/T7-gate-branch-x-1-gatealias-sonnet-high.md")"
bash "$gen" "${GA[@]}" --out-dir "$W/hm" >/dev/null 2>&1; r_hm=$?
if [ "$r_hm" -eq 3 ] && [ "$b1" = "$(sha256sum "$W/hm/T7-gate-branch-x-1-gatealias-sonnet-high.md")" ]; then say "✅ REFUSAL: hand-made colliding file refused (exit 3) and unchanged"; else ko "REFUSAL: hand-made file overwritten or wrong exit ($r_hm)"; fi
cp -r "$G" "$W/hb"; sed -i 's/^You are /You really are /' "$W/hb/$n1"; b2="$(sha256sum "$W/hb/$n1")"
bash "$gen" "${GA[@]}" --out-dir "$W/hb" >/dev/null 2>&1; r_hb=$?
if [ "$r_hb" -eq 4 ] && [ "$b2" = "$(sha256sum "$W/hb/$n1")" ]; then say "✅ REFUSAL: hand-edited BODY refused (exit 4) and unchanged"; else ko "REFUSAL: hand-edited body overwritten or wrong exit ($r_hb)"; fi
# ── 6 INSTALLER ──────────────────────────────────────────────────────────────────
P="$W/proj"; AG="$P/.claude/agents"; mkdir -p "$AG" "$P/config/multitrack"
git -C "$P" init -q -b main 2>/dev/null; git -C "$P" -c user.email=g@g -c user.name=g commit -q --allow-empty -m i 2>/dev/null
printf 'tracks: [ {{{ broken\n' >"$P/config/multitrack/gatehost.yaml"
printf -- '---\nname: mine\ndescription: "mine"\n---\nhand\n' >"$AG/mine.md"
printf -- '---\nname: T1-main-oldalias-opus-max\ndescription: "hand made, generator-shaped name"\nmodel: opus\neffort: max\ncolor: red\n---\nhand\n' >"$AG/T1-main-oldalias-opus-max.md"
bash "$gen" --track 1 --branch main --alias oldalias --out-dir "$AG" >/dev/null 2>&1
bash "$gen" --track 2 --branch feature/z --alias other --out-dir "$AG" --types opus-low >/dev/null 2>&1
bash "$gen" --track 1 --branch main --alias gatealias --out-dir "$W/ed" --types sonnet-low >/dev/null 2>&1   # this alias's superseded file, hand-edited
sed -i 's/^You are /You really are /' "$W/ed/T1-main-gatealias-sonnet-low.md"; cp "$W/ed/T1-main-gatealias-sonnet-low.md" "$AG/"
bash "$gen" --track 1 --branch main --alias gatealias --out-dir "$AG" --types opus-low >/dev/null 2>&1   # this alias's superseded type
v1="$AG/T1-main-opus-low.md"; fm=$'---\nname: T1-main-opus-low\ndescription: "(T1/main - <alias> - opus - low) x"\nmodel: opus\neffort: low\ncolor: blue\n---'
hv=$( { printf '%s\n' "$fm"; printf 'old\n'; } | sha256sum | cut -d' ' -f1)
{ printf '%s\n' "$fm"; printf '<!-- generated-by: gen_agent_label_defs.sh v1 (x); content-sha256: %s; y -->\n' "$hv"; printf 'old\n'; } >"$v1"
for x in html pdf docx; do printf 'e\n' >"$AG/T1-main-opus-low.$x"; printf 'e\n' >"$AG/T1-main-oldalias-opus-high.$x"; done
inst_run() { # env-args... [bash "$inst" extra args] -> runs the installer in the fixture
  if [ "$#" -gt 0 ] && [ "${*: -1}" = "--dry-run" ]; then
    (cd "$P" && env -u AGENT_TYPE_LABEL_DEFS MT_HOST=gatehost MT_CONFIG_DIR="$P/config/multitrack" "$@" >"$W/i.out" 2>"$W/i.err")
  else
    (cd "$P" && env -u AGENT_TYPE_LABEL_DEFS MT_HOST=gatehost MT_CONFIG_DIR="$P/config/multitrack" "$@" bash "$inst" --project-root "$P" >"$W/i.out" 2>"$W/i.err")
  fi
}
s0="$(tree_hash "$AG")"
inst_run env -u CLAUDE_CONFIG_DIR; r_u=$?
if [ "$r_u" -eq 6 ] && [ "$s0" = "$(tree_hash "$AG")" ]; then say "✅ INSTALLER: unknown identity (malformed config present) -> exit 6, nothing written or pruned"; else ko "INSTALLER: unknown identity exited $r_u or changed files (fail-open, AL-1)"; fi
s1="$(tree_hash "$AG")"
inst_run env CLAUDE_CONFIG_DIR="$W/cfg/.claude-gatealias" bash "$inst" --project-root "$P" --dry-run >/dev/null 2>&1 || true
[ "$s1" = "$(tree_hash "$AG")" ] && say "✅ INSTALLER: --dry-run deletes and writes nothing" || ko "INSTALLER: --dry-run changed files"
inst_run env CLAUDE_CONFIG_DIR="$W/cfg/.claude-gatealias"; r_i=$?
[ "$r_i" -eq 0 ] || ko "INSTALLER: live-identity install exited $r_i: $(head -c 200 "$W/i.err")"
n_new="$(cd "$AG" && ls T1-main-gatealias-sonnet-medium.md T1-main-gatealias-sonnet-high.md T1-main-gatealias-opus-high.md T1-main-gatealias-opus-xhigh.md 2>/dev/null | wc -l)"
n_other="$(find "$AG" -maxdepth 1 \( -name 'T1-main-oldalias-*.md' -o -name 'T2-feature-z-*.md' \) | wc -l)"
if [ "$n_new" -eq 4 ] && [ "$n_other" -eq 6 ] && [ -e "$AG/mine.md" ] && [ -e "$AG/T1-main-gatealias-sonnet-low.md" ]; then
  say "✅ INSTALLER: live identity installed (4); other aliases' generated types (5) and hand-made / hand-edited files kept"
else ko "INSTALLER: new=$n_new (want 4), other-alias + hand-made=$n_other (want 6): other aliases' types must never be pruned (AL2-1) $(head -c 160 "$W/i.err")"; fi
n_gone="$(ls "$AG"/T1-main-opus-low.* "$AG"/T1-main-gatealias-opus-low.* 2>/dev/null | wc -l)"
n_sib="$(ls "$AG"/T1-main-oldalias-opus-high.* 2>/dev/null | wc -l)"
[ "$n_gone" -eq 0 ] && [ "$n_sib" -eq 4 ] && say "✅ INSTALLER: v1 + this alias's superseded files pruned WITH their export siblings; kept files keep theirs" || ko "INSTALLER: prune left $n_gone superseded file(s)/sibling(s) or touched kept siblings ($n_sib, want 4)"
st="$(git -C "$P" status --porcelain --untracked-files=all -- .claude/agents | sed 's/^?? //' | LC_ALL=C sort | tr '\n' ' ')"
[ "$st" = ".claude/agents/T1-main-oldalias-opus-max.md .claude/agents/mine.md " ] && say "✅ INSTALLER: every alias's generated files + export siblings kept out of git status (.git/info/exclude)" || ko "INSTALLER: git status shows generated files or siblings: $st"
# prefix-related aliases never cross-prune (RV6) and a linked worktree keeps the main one clean (AL3-1)
K="$W/kproj"; KA="$K/.claude/agents"; mkdir -p "$KA"
git -C "$K" init -q -b main 2>/dev/null; git -C "$K" -c user.email=g@g -c user.name=g commit -q --allow-empty -m i 2>/dev/null
bash "$gen" --track 1 --branch main --alias kimi --out-dir "$KA" >/dev/null 2>&1
(cd "$K" && env -u AGENT_TYPE_LABEL_DEFS bash "$inst" --project-root "$K" --identity '1:main:kimi-for-coding' >/dev/null 2>&1)
nk="$(find "$KA" -maxdepth 1 -name 'T1-main-kimi-*.md' ! -name 'T1-main-kimi-for-coding-*' | wc -l)"
(cd "$K" && env -u AGENT_TYPE_LABEL_DEFS bash "$inst" --project-root "$K" --identity '1:main:kimi' >/dev/null 2>&1)
nkf="$(find "$KA" -maxdepth 1 -name 'T1-main-kimi-for-coding-*.md' | wc -l)"
[ "$nk" -eq 4 ] && [ "$nkf" -eq 4 ] && say "✅ INSTALLER: prefix-related aliases (kimi / kimi-for-coding) never prune each other" || ko "INSTALLER: kimi=$nk kimi-for-coding=$nkf (want 4/4): ownership must be EXACT (RV6)"
git -C "$K" worktree add -q -b zz "$W/klinked" 2>/dev/null
(cd "$W/klinked" && env -u AGENT_TYPE_LABEL_DEFS bash "$inst" --project-root "$W/klinked" --identity '2:zz:other' >/dev/null 2>&1)
nl="$(git -C "$K" status --porcelain --untracked-files=all | grep -c 'T1-main-kimi' || true)"
[ "$nl" -eq 0 ] && say "✅ INSTALLER: a linked worktree's install keeps the main worktree's generated files excluded (shared info/exclude)" || ko "INSTALLER: $nl main-worktree generated file(s) visible after a linked-worktree install (AL3-1)"
# ── 7 HOOK ───────────────────────────────────────────────────────────────────────
HP="$W/hproj"; mkdir -p "$HP/.claude/agents"
bash "$gen" --track 1 --branch main --alias cmatl --out-dir "$HP/.claude/agents" --all-types >/dev/null 2>&1
CFG="/nonexistent/.claude-cmatl"
LBL="(T1/main - cmatl - sonnet - low) probe"
hk() { # enforce subagent_type [model] [effort] -> exit code ; stdout/stderr in $W/h.out/$W/h.err
  local enf="$1" pl
  pl="$(python3 -I -c 'import json,sys
a=sys.argv[1:]; ti={"description":a[0],"prompt":"p"}
if a[1]: ti["subagent_type"]=a[1]
if len(a)>2 and a[2]: ti["model"]=a[2]
if len(a)>3 and a[3]: ti["effort"]=a[3]
print(json.dumps({"tool_name":"Agent","tool_input":ti}))' "$LBL" "$2" "${3:-}" "${4:-}")"
  printf '%s' "$pl" | env -u AGENT_TYPE_LABEL_BYPASS -u CLAUDE_CODE_EFFORT_LEVEL -u CLAUDE_EFFORT -u CLAUDE_CODE_EFFORT -u AGENT_EFFORT -u CMA_EFFORT \
    CLAUDE_PROJECT_DIR="${HP2:-$HP}" CLAUDE_CONFIG_DIR="$CFG" AGENT_TYPE_LABEL_ENFORCE="$enf" ${HKX:+"$HKX"} bash "$hook" >"$W/h.out" 2>"$W/h.err"
}
hk 0 general-purpose; r1=$?
if [ "$r1" -eq 0 ] && grep -qi 'agent type' "$W/h.out" "$W/h.err" && python3 -I -c 'import json,sys; json.load(open(sys.argv[1]))' "$W/h.out" 2>/dev/null; then say "✅ HOOK: general-purpose + generated types -> WARN (valid JSON), exit 0"; else ko "HOOK: warn mode wrong (exit $r1)"; fi
hk 1 general-purpose; r2=$?; hk 1 claude; r2b=$?; hk 1 ""; r3=$?
[ "$r2" -eq 2 ] && [ "$r2b" -eq 2 ] && [ "$r3" -eq 2 ] && say "✅ HOOK: ENFORCE=1 blocks general-purpose / claude / empty type" || ko "HOOK: ENFORCE=1 exited $r2/$r2b/$r3 (want 2/2/2)"
hk 1 T1-main-cmatl-sonnet-low; r4=$?
if [ "$r4" -eq 0 ] && ! grep -qi 'agent type' "$W/h.out" "$W/h.err"; then say "✅ HOOK: matching label type dispatches silently"; else ko "HOOK: matching label type warned or blocked (exit $r4)"; fi
hk 1 T2-feature-x-cmatl-sonnet-low; r6t=$?; hk 1 T1-main-cmatl-opus-xhigh; r6m=$?; hk 1 T1-main-cmatl-sonnet-low opus xhigh; r6o=$?
[ "$r6t" -eq 2 ] && [ "$r6m" -eq 2 ] && [ "$r6o" -eq 2 ] && say "✅ HOOK: other-track type, label/type mismatch and model/effort override all blocked" || ko "HOOK: other-track/mismatch/override exited $r6t/$r6m/$r6o (want 2/2/2)"
HKX="CLAUDE_CODE_EFFORT_LEVEL=max" hk 1 T1-main-cmatl-sonnet-low; r6e=$?
[ "$r6e" -eq 2 ] && say "✅ HOOK: CLAUDE_CODE_EFFORT_LEVEL contradicting the type is blocked" || ko "HOOK: CLAUDE_CODE_EFFORT_LEVEL override exited $r6e (want 2)"
hk 1 Explore; r5=$?; hk 1 plugin-dev:agent-creator; r6=$?
if [ "$r5" -eq 0 ] && [ "$r6" -eq 0 ] && ! grep -qi 'agent type' "$W/h.out" "$W/h.err"; then say "✅ HOOK: specialist/plugin types never touched (enforce)"; else ko "HOOK: specialist/plugin type flagged (exit $r5/$r6)"; fi
hk 0 'T2-a"b\c-sonnet-max'; r7=$?
okj=0; python3 -I -c 'import json,sys; json.load(open(sys.argv[1]))' "$W/h.out" 2>/dev/null && [ "$r7" -eq 0 ] && okj=1
hk 0 $'T2-a\x01b-sonnet-max'; r7b=$?
[ -s "$W/h.out" ] && python3 -I -c 'import json,sys; json.load(open(sys.argv[1]))' "$W/h.out" 2>/dev/null && [ "$r7b" -eq 0 ] || okj=0
[ "$okj" -eq 1 ] && say "✅ HOOK: hostile subagent_type (quote, backslash, control character) still yields valid JSON" || ko "HOOK: hostile subagent_type broke the JSON payload"
hk 1 T1-main-cmatl-zz-sonnet-low; r7c=$?
[ "$r7c" -eq 2 ] && say "✅ HOOK: exact identity match (alias 'cmatl-zz' is not 'cmatl')" || ko "HOOK: prefix-extended type passed as the label's identity (exit $r7c, AL2-4)"
printf '%s' '{"tool_name":"Agent","tool_input":{"description":"(T1/main - cmatl - sonnet - low) probe","subagent_type":"general-purpose","prompt":"p"}}' \
  | env -u CLAUDE_EFFORT CLAUDE_PROJECT_DIR="$HP" CLAUDE_CONFIG_DIR="$CFG" AGENT_TYPE_LABEL_ENFORCE=1 AGENT_TYPE_LABEL_BYPASS="" bash "$hook" >/dev/null 2>&1; r8=$?
[ "$r8" -eq 2 ] && say "✅ HOOK: empty bypass reason does not bypass" || ko "HOOK: empty bypass reason bypassed (exit $r8)"
HP2="$W/projh"; mkdir -p "$HP2/.claude/agents"
printf -- '---\nname: T1-main-cmatl-sonnet-low\ndescription: "hand"\nmodel: sonnet\neffort: low\ncolor: red\n---\nH\n' >"$HP2/.claude/agents/T1-main-cmatl-sonnet-low.md"
hk 1 general-purpose; r9=$?
if [ "$r9" -eq 0 ] && ! grep -qi 'agent type' "$W/h.out" "$W/h.err"; then say "✅ HOOK: hand-made T<N> types do not count as generated (golden-FALSE)"; else ko "HOOK: hand-made T<N> type counted as generated (exit $r9)"; fi
HP2="$W/projs"; mkdir -p "$HP2/.claude/agents"; bash "$gen" --track 1 --branch main --alias stale --out-dir "$HP2/.claude/agents" >/dev/null 2>&1
hk 1 general-purpose; r10=$?
if [ "$r10" -eq 0 ] && grep -qi 'stale' "$W/h.err"; then say "✅ HOOK: types of a stale identity only -> WARN, never BLOCK"; else ko "HOOK: stale-identity types blocked or silent (exit $r10)"; fi
HP2="$W/proj2"; mkdir -p "$HP2/.claude/agents"; bash "$gen" --track 2 --branch feature/x --alias cmatl --out-dir "$HP2/.claude/agents" >/dev/null 2>&1
hk 1 general-purpose; r11=$?
if [ "$r11" -eq 0 ] && ! grep -qi 'agent type' "$W/h.out" "$W/h.err"; then say "✅ HOOK: types of another track only -> T1 dispatch untouched (golden-FALSE)"; else ko "HOOK: other-track types counted for a T1 dispatch (exit $r11)"; fi
HP2=""
# ── 8 DISPATCH-LOG ──────────────────────────────────────────────────────────────────
if [ -n "$dlog" ]; then
  if [ -z "$adir" ] || [ ! -d "$adir" ]; then ko "DISPATCH-LOG: --agents-dir missing or not a directory"
  elif [ ! -r "$dlog" ]; then ko "DISPATCH-LOG: unreadable $dlog"
  else
    nfind="$(python3 -I - "$dlog" "$adir" 2>"$W/dl.err" <<'PY'
import json, os, re, sys
log, adir = sys.argv[1], sys.argv[2]
have = set()
for f in os.listdir(adir):
    m = re.match(r"^T([0-9]+)-.+\.md$", f)
    if not m:
        continue
    try:
        txt = open(os.path.join(adir, f), encoding="utf-8").read()
    except OSError:
        continue
    if re.search(r"^<!-- generated-by: gen_agent_label_defs\.sh v[12] ", txt, re.M):
        have.add(m.group(1))
n = 0
for ln in open(log, encoding="utf-8"):
    ln = ln.strip()
    if not ln:
        continue
    try:
        d = json.loads(ln)
    except ValueError:
        continue
    st = d.get("subagent_type") or ""
    m = re.match(r"^\(T([0-9]+)/", d.get("description") or "")
    if st in ("", "general-purpose", "claude") and m and m.group(1) in have:
        n += 1
        sys.stderr.write("finding: %s dispatch labelled T%s\n" % (st or "<empty>", m.group(1)))
print(n)
PY
)"
    if [ "${nfind:-0}" -gt 0 ]; then
      if [ "$mode" = enforce ]; then ko "DISPATCH-LOG: ${nfind} unlabelled-type dispatch(es) while generated types exist ($(head -c 160 "$W/dl.err" | tr '\n' ' '))"
      else echo "⚠️  WARN DISPATCH-LOG: ${nfind} general-purpose/empty-type dispatch(es) while generated label types exist (warn mode: not failing)"; fi
    else say "✅ DISPATCH-LOG: no unlabelled-type dispatch for a track with generated types"; fi
  fi
fi
echo "----------------------------------------------------------------------"
if [ "$fail" -eq 0 ]; then echo "✅ ${GATE}: PASS — generator, installer and hook produce, protect and guard the T<N>-<branch>-<alias>-<model>-<effort> agent types"; exit 0; fi
echo "❌ ${GATE}: FAIL"; exit 1
