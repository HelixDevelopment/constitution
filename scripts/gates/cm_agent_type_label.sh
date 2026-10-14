#!/usr/bin/env bash
# cm_agent_type_label.sh — CM-AGENT-TYPE-LABEL gate (§11.4.182 / §11.4.231(F)).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# §11.4.182/§11.4.231(F) bake the work-stream label into GENERATED agent types
# named T<N>-<branch>-<model>-<effort> (model + effort enforced by the
# definition). This gate proves the toolchain really does that, by BEHAVIOUR
# (drives the real generator, installer and hook in a throwaway fixture):
#   1 PRESENCE+EXEC+PARSE  generator, installer, hook, frontmatter checker, colour
#                          data file and the three convention docs exist; shell
#                          files parse (bash -n), the python checker compiles.
#   2 GENERATION           a fixture track/branch yields exactly models x efforts
#                          files, each named T<N>-<san-branch>-<model>-<effort>,
#                          each passing the strict independent frontmatter parser.
#   3 IDEMPOTENCE          a second run is byte-identical and reports written=0.
#   4 CHECK                --check: clean=0; a deleted file=1; a hand-edited
#                          generated file=1.
#   5 REFUSAL              a hand-made file with a colliding name is NEVER
#                          overwritten (exit 3, bytes unchanged).
#   6 INSTALLER            installs into a fixture project's .claude/agents,
#                          keeps hand-made agents, prunes only stale GENERATED
#                          files.
#   7 HOOK                 general-purpose dispatch with generated types present:
#                          WARN + exit 0 by default, exit 2 under
#                          AGENT_TYPE_LABEL_ENFORCE=1; label types, specialist and
#                          plugin types are never touched; empty bypass reason
#                          does not bypass.
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
colors="$ROOT/scripts/multitrack/agent_label_colors.tsv"
docdir="$ROOT/docs/scripts"
dlog=""; adir=""; mode="warn"; quiet=""
while [ $# -gt 0 ]; do
  case "$1" in
    --gen) gen="$2"; shift 2 ;; --installer) inst="$2"; shift 2 ;; --hook) hook="$2"; shift 2 ;;
    --checker) chk="$2"; shift 2 ;; --colors) colors="$2"; shift 2 ;; --doc-dir) docdir="$2"; shift 2 ;;
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
for pair in "generator:$gen" "installer:$inst" "hook:$hook"; do
  n="${pair%%:*}"; p="${pair#*:}"
  if [ ! -r "$p" ]; then ko "PRESENCE: $n not found: $p"; continue; fi
  [ -x "$p" ] || ko "EXEC: $n not executable: $p"
  bash -n "$p" 2>/dev/null && say "✅ PRESENCE+PARSE: $n" || ko "PARSEABILITY: $n fails bash -n"
done
[ -r "$chk" ] && python3 -I -m py_compile "$chk" 2>/dev/null && say "✅ PRESENCE+PARSE: frontmatter checker" || ko "PRESENCE/PARSE: frontmatter checker missing or not compilable: $chk"
[ -s "$colors" ] && say "✅ PRESENCE: colour data" || ko "PRESENCE: colour data missing/empty: $colors"
for d in gen_agent_label_defs.md install_agent_label_defs.md guard-track-branch-label.md; do
  [ -s "$docdir/$d" ] && say "✅ DOC: $d" || ko "DOC: $docdir/$d missing/empty"
done
if [ "$fail" -ne 0 ]; then echo "${GATE}: FAIL (presence/parse)"; exit 1; fi

tree_hash() { (cd "$1" && find . -type f | LC_ALL=C sort | xargs sha256sum 2>/dev/null | sha256sum | cut -d' ' -f1); }

# ── 2 GENERATION ────────────────────────────────────────────────────────────────
G="$W/gen"
bash "$gen" --track 7 --branch 'Gate/Branch_X' --out-dir "$G" >"$W/g.out" 2>"$W/g.err"; rc=$?
if [ "$rc" -ne 0 ]; then ko "GENERATION: generator exited $rc ($(head -c 200 "$W/g.err"))"; fi
want="$(for m in opus sonnet; do for e in high low max medium xhigh; do echo "T7-gate-branch-x-$m-$e.md"; done; done | LC_ALL=C sort | tr '\n' ' ')"
got="$(ls "$G" 2>/dev/null | LC_ALL=C sort | tr '\n' ' ')"
if [ "$want" = "$got" ]; then say "✅ GENERATION: 10 files, exact T<N>-<branch>-<model>-<effort> names"; else ko "GENERATION: file set differs (want: $want | got: $got)"; fi
if ls "$G"/*.md >/dev/null 2>&1; then
  if python3 -I "$chk" "$G"/*.md >"$W/c.out" 2>&1; then say "✅ GENERATION: every file passes the strict independent frontmatter parse"; else ko "GENERATION: strict frontmatter parse failed: $(grep -m2 BAD "$W/c.out")"; fi
fi
# ── 3 IDEMPOTENCE ───────────────────────────────────────────────────────────────
h1="$(tree_hash "$G")"
bash "$gen" --track 7 --branch 'Gate/Branch_X' --out-dir "$G" >"$W/g2.out" 2>&1
if [ "$h1" = "$(tree_hash "$G")" ] && grep -q 'written=0' "$W/g2.out"; then say "✅ IDEMPOTENCE: rerun byte-identical, written=0"; else ko "IDEMPOTENCE: rerun changed bytes or wrote files"; fi
bash "$gen" --track 7 --branch 'Gate/Branch_X' --out-dir "$W/gen2" >/dev/null 2>&1
[ "$h1" = "$(tree_hash "$W/gen2")" ] && say "✅ DETERMINISM: same bytes in a second out-dir" || ko "DETERMINISM: bytes differ between out-dirs"
# ── 4 CHECK ───────────────────────────────────────────────────────────────────────
bash "$gen" --track 7 --branch 'Gate/Branch_X' --out-dir "$G" --check >/dev/null 2>&1; r_clean=$?
cp -r "$G" "$W/d1"; rm "$W/d1/T7-gate-branch-x-opus-low.md"
bash "$gen" --track 7 --branch 'Gate/Branch_X' --out-dir "$W/d1" --check >/dev/null 2>&1; r_miss=$?
cp -r "$G" "$W/d2"; sed -i 's/^color: .*/color: red/' "$W/d2/T7-gate-branch-x-opus-low.md"
bash "$gen" --track 7 --branch 'Gate/Branch_X' --out-dir "$W/d2" --check >/dev/null 2>&1; r_edit=$?
[ "$r_clean" -eq 0 ] && say "✅ CHECK: clean tree -> 0" || ko "CHECK: clean tree exited $r_clean (want 0)"
[ "$r_miss" -eq 1 ] && say "✅ CHECK: missing generated file -> 1" || ko "CHECK: missing file exited $r_miss (want 1) — drift check is blind"
[ "$r_edit" -eq 1 ] && say "✅ CHECK: hand-edited generated file -> 1" || ko "CHECK: hand-edit exited $r_edit (want 1) — drift check is blind"
# ── 5 REFUSAL ────────────────────────────────────────────────────────────────────
mkdir -p "$W/hm"; printf -- '---\nname: T7-gate-branch-x-sonnet-low\ndescription: "hand"\nmodel: sonnet\neffort: low\ncolor: red\n---\nHAND\n' >"$W/hm/T7-gate-branch-x-sonnet-low.md"
b1="$(sha256sum "$W/hm/T7-gate-branch-x-sonnet-low.md")"
bash "$gen" --track 7 --branch 'Gate/Branch_X' --out-dir "$W/hm" >/dev/null 2>&1; r_hm=$?
if [ "$r_hm" -eq 3 ] && [ "$b1" = "$(sha256sum "$W/hm/T7-gate-branch-x-sonnet-low.md")" ]; then say "✅ REFUSAL: hand-made colliding file refused (exit 3) and unchanged"; else ko "REFUSAL: hand-made file overwritten or wrong exit ($r_hm)"; fi
# ── 6 INSTALLER ──────────────────────────────────────────────────────────────────
P="$W/proj"; mkdir -p "$P/.claude/agents"
git -C "$P" init -q -b main 2>/dev/null; git -C "$P" -c user.email=g@g -c user.name=g commit -q --allow-empty -m i 2>/dev/null
printf -- '---\nname: mine\ndescription: "mine"\n---\nhand\n' >"$P/.claude/agents/mine.md"
printf -- '---\nname: T9-handmade\ndescription: "h"\n---\nhand\n' >"$P/.claude/agents/T9-handmade.md"
printf -- '---\nname: T9-legacy-opus-high\ndescription: "hand made, generator-shaped name"\nmodel: opus\neffort: high\ncolor: red\n---\nhand\n' >"$P/.claude/agents/T9-legacy-opus-high.md"
bash "$gen" --track 9 --branch gone --out-dir "$P/.claude/agents" --models sonnet --efforts low >/dev/null 2>&1
m1="$(sha256sum "$P/.claude/agents/mine.md" "$P/.claude/agents/T9-handmade.md" "$P/.claude/agents/T9-legacy-opus-high.md")"
MT_HOST=cmatl-nohost MT_CONFIG_DIR="$W/noconfig" bash "$inst" --project-root "$P" >"$W/i.out" 2>"$W/i.err"; r_i=$?
n_t1="$(find "$P/.claude/agents" -maxdepth 1 -name 'T1-main-*' | wc -l)"
if [ "$r_i" -eq 0 ] && [ "$n_t1" -eq 10 ]; then say "✅ INSTALLER: current checkout T1/main installed (10 files)"; else ko "INSTALLER: exit $r_i, T1-main files=$n_t1 (want 0/10): $(head -c 200 "$W/i.err")"; fi
[ "$m1" = "$(sha256sum "$P/.claude/agents/mine.md" "$P/.claude/agents/T9-handmade.md" "$P/.claude/agents/T9-legacy-opus-high.md")" ] && say "✅ INSTALLER: hand-made agents untouched" || ko "INSTALLER: a hand-made agent file was modified or deleted"
[ ! -e "$P/.claude/agents/T9-gone-sonnet-low.md" ] && say "✅ INSTALLER: stale GENERATED file pruned" || ko "INSTALLER: stale generated file not pruned"
# ── 7 HOOK ───────────────────────────────────────────────────────────────────────
CFG="/nonexistent/.claude-cmatl"
LBL="(T1/main - cmatl - sonnet - low) probe"
hk() { # enforce subagent_type [bypass-empty] -> exit code ; stdout/stderr in $W/h.out/$W/h.err ; project in $HP
  local enf="$1" st="$2" extra="${3-}" pl P="${HP:-$P}"
  if [ -n "$st" ]; then pl='{"tool_name":"Agent","tool_input":{"description":"'"$LBL"'","subagent_type":"'"$st"'","prompt":"p"}}'
  else pl='{"tool_name":"Agent","tool_input":{"description":"'"$LBL"'","prompt":"p"}}'; fi
  if [ -n "$extra" ]; then
    printf '%s' "$pl" | env CLAUDE_PROJECT_DIR="$P" CLAUDE_CONFIG_DIR="$CFG" AGENT_TYPE_LABEL_ENFORCE="$enf" AGENT_TYPE_LABEL_BYPASS="" bash "$hook" >"$W/h.out" 2>"$W/h.err"
  else
    printf '%s' "$pl" | env -u AGENT_TYPE_LABEL_BYPASS CLAUDE_PROJECT_DIR="$P" CLAUDE_CONFIG_DIR="$CFG" AGENT_TYPE_LABEL_ENFORCE="$enf" bash "$hook" >"$W/h.out" 2>"$W/h.err"
  fi
  return $?
}
hk 0 general-purpose; r1=$?
if [ "$r1" -eq 0 ] && grep -qi 'agent type' "$W/h.out" "$W/h.err"; then say "✅ HOOK: general-purpose + generated types -> WARN, exit 0"; else ko "HOOK: warn mode wrong (exit $r1, warn text present: $(grep -ci 'agent type' "$W/h.out" "$W/h.err" | tr '\n' ' '))"; fi
hk 1 general-purpose; r2=$?
[ "$r2" -eq 2 ] && say "✅ HOOK: ENFORCE=1 blocks general-purpose (exit 2)" || ko "HOOK: ENFORCE=1 exited $r2 (want 2)"
hk 1 ""; r3=$?
[ "$r3" -eq 2 ] && say "✅ HOOK: ENFORCE=1 blocks an empty subagent_type (exit 2)" || ko "HOOK: ENFORCE=1 + empty type exited $r3 (want 2)"
hk 1 T1-main-sonnet-low; r4=$?
if [ "$r4" -eq 0 ] && ! grep -qi 'agent type' "$W/h.out" "$W/h.err"; then say "✅ HOOK: label type dispatches silently"; else ko "HOOK: label type warned or blocked (exit $r4)"; fi
hk 1 Explore; r5=$?; hk 1 plugin-dev:agent-creator; r6=$?
if [ "$r5" -eq 0 ] && [ "$r6" -eq 0 ] && ! grep -qi 'agent type' "$W/h.out" "$W/h.err"; then say "✅ HOOK: specialist/plugin types never touched (enforce)"; else ko "HOOK: specialist/plugin type flagged (exit $r5/$r6)"; fi
hk 1 general-purpose bypass-empty; r7=$?
[ "$r7" -eq 2 ] && say "✅ HOOK: empty bypass reason does not bypass" || ko "HOOK: empty bypass reason bypassed (exit $r7)"
# a project whose only T1 type is HAND-MADE (no generator marker) must not trigger anything
HP="$W/projh"; mkdir -p "$HP/.claude/agents"
printf -- '---\nname: T1-main-sonnet-low\ndescription: "hand"\nmodel: sonnet\neffort: low\ncolor: red\n---\nH\n' >"$HP/.claude/agents/T1-main-sonnet-low.md"
hk 1 general-purpose; r8=$?
if [ "$r8" -eq 0 ] && ! grep -qi 'agent type' "$W/h.out" "$W/h.err"; then say "✅ HOOK: hand-made T<N> types do not count as generated (golden-FALSE)"; else ko "HOOK: hand-made T<N> type counted as generated (exit $r8)"; fi
HP=""
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
    if "<!-- generated-by: gen_agent_label_defs.sh v1 " in txt:
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
    if st in ("", "general-purpose") and m and m.group(1) in have:
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
if [ "$fail" -eq 0 ]; then echo "✅ ${GATE}: PASS — generator, installer and hook produce, protect and enforce the T<N>-<branch>-<model>-<effort> agent types"; exit 0; fi
echo "❌ ${GATE}: FAIL"; exit 1
