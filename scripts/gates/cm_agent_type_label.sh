#!/usr/bin/env bash
# cm_agent_type_label.sh — CM-AGENT-TYPE-LABEL gate (§11.4.182 / §11.4.231(F)).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# §11.4.182/§11.4.231(F) bake the work-stream label into GENERATED agent types
# named T<N>-<branch>-<model>-<effort> (model + effort SET by the definition's
# frontmatter; an Agent call's own model/effort parameters override it, which
# the hook flags). This gate proves the toolchain really does that, by BEHAVIOUR
# (drives the real generator, installer and hook in a throwaway fixture):
#   1 PRESENCE+EXEC+PARSE  generator, installer, hook, frontmatter checker, colour
#                          data file and the three convention docs exist; shell
#                          files parse (bash -n), the python checker compiles.
#   2 GENERATION           a fixture track/branch yields exactly models x efforts
#                          files, each named T<N>-<san-branch>-<model>-<effort>,
#                          each passing the strict independent frontmatter parser;
#                          the §11.4.209/§11.4.211 reviewer text is in the
#                          opus-xhigh body ONLY (not opus-max, not sonnet-xhigh).
#   3 IDEMPOTENCE          a second run is byte-identical and reports written=0.
#   4 CHECK                --check: clean=0; a deleted file=1; a hand-edited
#                          generated file=1.
#   5 REFUSAL              a hand-made file with a colliding name is NEVER
#                          overwritten (exit 3, bytes unchanged).
#   6 INSTALLER            installs into a fixture project's .claude/agents,
#                          keeps hand-made agents, prunes only stale GENERATED
#                          files; a partial --models run keeps the other model's
#                          files; refuses (exit 6) a project whose .claude is the
#                          user-level CLAUDE_CONFIG_DIR.
#   7 HOOK                 general-purpose dispatch with generated types present:
#                          WARN + exit 0 by default, exit 2 under
#                          AGENT_TYPE_LABEL_ENFORCE=1; label types, specialist and
#                          plugin types are never touched; empty bypass reason
#                          does not bypass; a T<N> type of ANOTHER track warns /
#                          blocks; a call whose model or effort parameter differs
#                          from the type name blocks under ENFORCE (matching ones
#                          do not); the WARN payload is valid JSON for a
#                          subagent_type carrying a quote and a backslash.
#   8 DISPATCH-LOG (optional, --dispatch-log F --agents-dir D [--mode M])
#                          audit a JSONL of {subagent_type,description} dispatches:
#                          each general-purpose/empty dispatch whose label track
#                          has generated types is a finding — WARN in `warn` mode
#                          (exit 0), FAIL in `enforce` mode (exit 1).
# ── What this gate does NOT protect (honest scope, §11.4.6; review 2026-11-03 F5) ─
#   It drives the generator, installer and hook with a fixed set of probes; it does
#   NOT run the three unit suites (test_gen_agent_label_defs.sh,
#   test_install_agent_label_defs.sh, test_guard_agent_type_label.sh), which cover
#   more cases: the post_update_hook.sh STEP 4f consent modes (dry-run default /
#   apply / off), the HOME / ancestor-of-HOME refusals, the sanitise collision, the
#   track-number normalisation (T007 == T7), the no-jq fallback and the checker's
#   golden-bad fixtures. A regression only those suites see survives this gate.
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
HP=""   # hook fixture project override; never read from the ambient environment (F3)
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
if grep -q '11.4.209' "$G/T7-gate-branch-x-opus-xhigh.md" 2>/dev/null && grep -q '11.4.211' "$G/T7-gate-branch-x-opus-xhigh.md" 2>/dev/null; then
  if grep -lq '11.4.209\|11.4.211' "$G/T7-gate-branch-x-opus-max.md" "$G/T7-gate-branch-x-sonnet-xhigh.md" 2>/dev/null; then ko "GENERATION: the reviewer/merge-conflict text also appears outside opus-xhigh"
  else say "✅ GENERATION: the §11.4.209/§11.4.211 reviewer text is in the opus-xhigh body only"; fi
else ko "GENERATION: the opus-xhigh body does not name §11.4.209 and §11.4.211"; fi
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
mkdir -p "$W/cfg"
cat >"$W/cfg/cmatl-host.yaml" <<YAML
schema_version: 1
host:
  hostname: cmatl-host
protected_drives:
  - serial: "PROT"
tracks:
  - id: track-1
    role: main
    branch: main
    drive_serial: "A"
    mount: $P
  - id: track-2
    role: feature
    branch_pattern: "feature/*"
    drive_serial: "B"
    mount: $W/track2-absent
YAML
instc() { MT_HOST=cmatl-host MT_CONFIG_DIR="$W/cfg" bash "$inst" --project-root "$P" "$@"; }
printf -- '---\nname: mine\ndescription: "mine"\n---\nhand\n' >"$P/.claude/agents/mine.md"
printf -- '---\nname: T9-handmade\ndescription: "h"\n---\nhand\n' >"$P/.claude/agents/T9-handmade.md"
printf -- '---\nname: T9-legacy-opus-high\ndescription: "hand made, generator-shaped name"\nmodel: opus\neffort: high\ncolor: red\n---\nhand\n' >"$P/.claude/agents/T9-legacy-opus-high.md"
bash "$gen" --track 9 --branch gone --out-dir "$P/.claude/agents" --models sonnet --efforts low >/dev/null 2>&1
m1="$(sha256sum "$P/.claude/agents/mine.md" "$P/.claude/agents/T9-handmade.md" "$P/.claude/agents/T9-legacy-opus-high.md")"
bash "$gen" --track 2 --branch feature/live --out-dir "$P/.claude/agents" --models sonnet --efforts low >/dev/null 2>&1
instc >"$W/i.out" 2>"$W/i.err"; r_i=$?
n_t1="$(find "$P/.claude/agents" -maxdepth 1 -name 'T1-main-*' | wc -l)"
if [ "$r_i" -eq 0 ] && [ "$n_t1" -eq 10 ]; then say "✅ INSTALLER: current checkout T1/main installed (10 files)"; else ko "INSTALLER: exit $r_i, T1-main files=$n_t1 (want 0/10): $(head -c 200 "$W/i.err")"; fi
[ "$m1" = "$(sha256sum "$P/.claude/agents/mine.md" "$P/.claude/agents/T9-handmade.md" "$P/.claude/agents/T9-legacy-opus-high.md")" ] && say "✅ INSTALLER: hand-made agents untouched" || ko "INSTALLER: a hand-made agent file was modified or deleted"
[ ! -e "$P/.claude/agents/T9-gone-sonnet-low.md" ] && say "✅ INSTALLER: stale GENERATED file pruned" || ko "INSTALLER: stale generated file not pruned"
# partial --models run must not prune the other model's files of a declared track (F4)
instc --models sonnet >"$W/i2.out" 2>"$W/i2.err"; r_i2=$?
n_op="$(find "$P/.claude/agents" -maxdepth 1 -name 'T1-main-opus-*' | wc -l)"
if [ "$r_i2" -eq 0 ] && [ "$n_op" -eq 5 ]; then say "✅ INSTALLER: a --models sonnet run keeps the 5 opus files"; else ko "INSTALLER: --models sonnet run exit $r_i2, opus files left=$n_op (want 0/5)"; fi
# an UNDECLARED track's file outside the run's --models/--efforts filter is kept (partial-run prune, R2-3)
bash "$gen" --track 9 --branch gone --out-dir "$P/.claude/agents" --models opus --efforts low >/dev/null 2>&1
instc --models sonnet >/dev/null 2>&1
[ -e "$P/.claude/agents/T9-gone-opus-low.md" ] && say "✅ INSTALLER: an undeclared file outside the --models filter is kept" || ko "INSTALLER: a --models sonnet run pruned an opus file outside its filter"
instc >/dev/null 2>&1
# a declared track whose mount is absent (branch unresolvable) keeps its files; no config prunes nothing (R2-2)
[ -e "$P/.claude/agents/T2-feature-live-sonnet-low.md" ] && say "✅ INSTALLER: declared-but-unresolvable track T2 NOT pruned" || ko "INSTALLER: declared-but-unresolvable track file was pruned"
bash "$gen" --track 9 --branch gone --out-dir "$P/.claude/agents" --models sonnet --efforts low >/dev/null 2>&1
MT_HOST=cmatl-nohost MT_CONFIG_DIR="$W/noconfig" bash "$inst" --project-root "$P" >/dev/null 2>&1
[ -e "$P/.claude/agents/T9-gone-sonnet-low.md" ] && say "✅ INSTALLER: with no usable config nothing is pruned" || ko "INSTALLER: pruned with no usable config"
instc >/dev/null 2>&1
# user-level refusals with a symlinked ~/.claude, an empty HOME, and an out-dir containing a user dir (R2-1, R2-3)
SH="$W/fh"; mkdir -p "$SH/dotreal/agents" "$SH/plain"; ln -s "$SH/dotreal" "$SH/.claude"
rfs() { env -u CLAUDE_CONFIG_DIR HOME="$1" MT_HOST=cmatl-nohost MT_CONFIG_DIR="$W/noconfig" bash "$inst" --dry-run "${@:2}" >/dev/null 2>&1; echo $?; }
r_s1="$(rfs "$SH" --project-root "$P" --out-dir "$SH/.claude/agents")"; r_s2="$(rfs "$SH" --project-root "$SH/dotreal")"
UD="$W/ud"; mkdir -p "$UD/proj/.claude"
r_s3="$(env CLAUDE_CONFIG_DIR="$UD/proj/.claude" HOME="$SH/plain" MT_HOST=cmatl-nohost MT_CONFIG_DIR="$W/noconfig" bash "$inst" --dry-run --project-root "$P" --out-dir "$UD/proj" >/dev/null 2>&1; echo $?)"; r_s7="$(rfs "" --project-root "$P")"; r_s5="$(rfs "$SH" --project-root "$SH")"; r_s6="$(rfs "$SH" --project-root "$W")"; r_s4="$(rfs "" --project-root "$(getent passwd "$(id -u)" | cut -d: -f6)")"
r_r1="$(rfs "$SH" --project-root "$P" --out-dir /)"; r_r2="$(rfs "$SH" --project-root "$P" --out-dir //)"; r_r3="$(rfs "$SH" --project-root "$P" --out-dir /etc/agents)"; r_r4="$(rfs "$SH" --project-root "$P" --out-dir "$SH/.claude")"
ln -s "$W/nonexistent-target" "$SH/.claude-dangling"; STUB="$W/stubbin"; mkdir -p "$STUB"; printf '#!/bin/sh\nexit 2\n' >"$STUB/getent"; chmod +x "$STUB/getent"
r_x3="$(rfs "$SH" --project-root "$P" --out-dir "$SH/.claude-dangling/agents")"; mkdir -p "$W/x5/real/home" "$W/x5/links"; ln -s "$W/x5/real/home" "$W/x5/links/homelink"; git -C "$W/x5/real" init -q -b main 2>/dev/null
r_x5="$(rfs "$W/x5/links/homelink" --project-root "$W/x5/real")"
r_x7="$(env -u CLAUDE_CONFIG_DIR PATH="$STUB:$PATH" HOME="" MT_HOST=cmatl-nohost MT_CONFIG_DIR="$W/noconfig" bash "$inst" --dry-run --project-root "$P" >/dev/null 2>&1; echo $?)"
P4="$W/p4"; mkdir -p "$P4/cfg"; git -C "$P4" init -q -b main 2>/dev/null; git -C "$P4" -c user.email=g@g -c user.name=g commit -q --allow-empty -m i 2>/dev/null
printf 'schema_version: 1\nhost:\n  hostname: cmatl-p4\nprotected_drives:\n  - serial: "PROT"\ntracks:\n  - id: track-007\n    role: feature\n    branch_pattern: "feature/*"\n    drive_serial: "C"\n    mount: %s/absent\n' "$P4" >"$P4/cfg/cmatl-p4.yaml"
bash "$gen" --track 7 --branch feature/seven --out-dir "$P4/.claude/agents" --models sonnet --efforts low >/dev/null 2>&1
MT_HOST=cmatl-p4 MT_CONFIG_DIR="$P4/cfg" bash "$inst" --project-root "$P4" >/dev/null 2>&1; [ -e "$P4/.claude/agents/T7-feature-seven-sonnet-low.md" ] && r_x4=kept || r_x4=pruned
if [ "$r_x3" = 6 ] && [ "$r_x5" = 6 ] && [ "$r_x7" = 6 ] && [ "$r_x4" = kept ]; then say "✅ INSTALLER: refuses a dangling ~/.claude-* symlink, a symlinked HOME's real target, an unresolvable home; keeps track-007 files when its mount is absent"; else ko "INSTALLER: probe failed (dangling $r_x3, symlinked-HOME target $r_x5, no-home $r_x7 want 6; track-007 files $r_x4 want kept)"; fi
if [ "$r_r1" = 6 ] && [ "$r_r2" = 6 ] && [ "$r_r3" = 6 ] && [ "$r_r4" = 6 ]; then say "✅ INSTALLER: refuses --out-dir / and // , a system directory, and an out-dir equal to a user config dir"; else ko "INSTALLER: root/system/equal refusal bypassed (/ $r_r1, // $r_r2, /etc/agents $r_r3, equal-to-config-dir $r_r4; want 6)"; fi
# R4-1: no dependence on GNU 'realpath -m' (a failing realpath first on PATH) and fail closed on an unreadable link
RPS="$W/stub_rp"; mkdir -p "$RPS"; printf '#!/bin/sh\nexit 1\n' >"$RPS/realpath"; chmod +x "$RPS/realpath"
RLS="$W/stub_rl"; mkdir -p "$RLS"; cp "$RPS/realpath" "$RLS/"; printf '#!/bin/sh\nexit 1\n' >"$RLS/readlink"; chmod +x "$RLS/readlink"
rfp() { env -u CLAUDE_CONFIG_DIR PATH="$1:$PATH" HOME="$2" MT_HOST=cmatl-nohost MT_CONFIG_DIR="$W/noconfig" bash "$inst" --dry-run "${@:3}" >/dev/null 2>&1; echo $?; }
mkdir -p "$SH/x" "$W/ph"
r_p1="$(rfp "$RPS" "$SH" --project-root "$P" --out-dir "$SH/x/../.claude/agents")"; r_p2="$(rfp "$RPS" "$SH" --project-root "$P" --out-dir /..)"; r_p3="$(rfp "$RPS" "$SH" --project-root "$P" --out-dir "$SH/x/..")"
r_p4="$(rfp "$RLS" "$SH" --project-root "$P")"; r_p5="$(rfp "$RPS" "$SH" --project-root "$P" --out-dir "$W/ord/./a/../agents")"; r_p6="$(rfp "$RLS" "$W/ph" --project-root "$P")"
if [ "$r_p1" = 6 ] && [ "$r_p2" = 6 ] && [ "$r_p3" = 6 ] && [ "$r_p4" = 6 ] && [ "$r_p5" = 0 ] && [ "$r_p6" = 0 ]; then say "✅ INSTALLER: refusal holds without GNU realpath ('..', '/..'), fails closed on an unreadable link; ordinary paths still accepted"; else ko "INSTALLER: realpath-free canonicalisation broken (~/x/../.claude/agents $r_p1, /.. $r_p2, ~/x/.. $r_p3, unreadable link $r_p4 want 6; ordinary $r_p5, no-link home $r_p6 want 0)"; fi
# R4-2..R4-4: /tmp itself refused, a child of a strict dir refused, prefix siblings and a child of /tmp accepted
r_q1="$(rfs "$SH" --project-root "$P" --out-dir /tmp)"; r_q2="$(rfs "$SH" --project-root "$P" --out-dir /srv/agentlabel-probe)"
r_q3="$(rfs "$SH" --project-root "$P" --out-dir /usrx/agents)"; r_q4="$(rfs "$SH" --project-root "$P" --out-dir "$SH/.claudeless/agents")"; r_q5="$(rfs "$SH" --project-root "$P" --out-dir /tmp/agentlabel-probe/agents)"
if [ "$r_q1" = 6 ] && [ "$r_q2" = 6 ] && [ "$r_q3" = 0 ] && [ "$r_q4" = 0 ] && [ "$r_q5" = 0 ]; then say "✅ INSTALLER: /tmp and /srv/<child> refused; /usrx, ~/.claudeless and /tmp/<child> accepted"; else ko "INSTALLER: strict/exact/prefix probes wrong (/tmp $r_q1, /srv/x $r_q2 want 6; /usrx $r_q3, ~/.claudeless $r_q4, /tmp/x $r_q5 want 0)"; fi
# R5-1..R5-3: per-process links (/proc/self, /dev/fd) refused; a symlink followed before a following '..';
# the kernel cross-check and the canon failure each refuse on their own (unit probes source the installer's
# own functions); an un-enterable project root stops with exit 2. No /proc or running as root: SKIP-with-reason.
mkdir -p "$SH/a/b" "$W/ordm/a"; ln -sfn "$SH/a/b" "$SH/deep"; ln -sfn "$W/ordm/a" "$W/ordmlink"; SHB="$(basename "$SH")"; SHP="$(cd -P -- "$SH" && pwd -P)"
FN="$W/canon_fns.sh"; { sed -n '/^exact_out() {/,/^}/p' "$inst"; grep '^cdpwd() {' "$inst"; sed -n '/^canon() {/,/^}/p' "$inst"; sed -n '/^canon_kcheck() {/,/^}/p' "$inst"; sed -n '/^canon_to() {/,/^}/p' "$inst"; grep '^refuse6() {' "$inst"; } >"$FN"
if [ -L /proc/self ]; then
  r_m1="$(cd "$SH/a/b" && rfs "$SH" --project-root "$P" --out-dir "/proc/self/cwd/../../../$SHB/.claude/agents")"; r_m2="$(rfs "$SH" --project-root "$P" --out-dir /dev/fd/../../agents)"
  r_u2="$(bash -c '. "$1"; canon /proc/self/cwd/..' _ "$FN" >/dev/null 2>&1; echo $?)"
else r_m1=6; r_m2=6; r_u2=2; say "ℹ️  INSTALLER: /proc/self absent: magic-link probes SKIP-with-reason (topology_unsupported)"; fi
r_m3="$(rfs "$SH" --project-root "$P" --out-dir "$SH/deep/../../.claude/agents")"; r_g1="$(rfs "$SH" --project-root "$P" --out-dir "$W/ordmlink/../agents")"
r_u1="$(bash -c '. "$1"; canon "$2"' _ "$FN" "$SH/deep/../../x" 2>/dev/null)"
r_u3="$(bash -c '. "$1"; canon() { printf "%s\n" "$1"; }; canon_to v "$2"' _ "$FN" "$SH/deep/../../x" >/dev/null 2>&1; echo $?)"
r_u4="$(bash -c '. "$1"; T="$2"; canon() { [ "$1" = "$T" ] && return 1; printf "%s\n" "$1"; }; canon_to v "$T"' _ "$FN" "$SHP/nonexist/x" >/dev/null 2>&1; echo $?)"
r_u5="$(bash -c '. "$1"; canon_to v "$2"' _ "$FN" "$SH/deep/.." >/dev/null 2>&1; echo $?)"
if [ "$(id -u)" != 0 ]; then NE="$W/noenter"; mkdir -p "$NE"; chmod 000 "$NE"; r_n1="$(rfs "$SH" --project-root "$NE")"; chmod 755 "$NE"; else r_n1=2; say "ℹ️  INSTALLER: running as root: un-enterable-root probe SKIP-with-reason"; fi
if [ "$r_m1" = 6 ] && [ "$r_m2" = 6 ] && [ "$r_m3" = 6 ] && [ "$r_g1" = 0 ] && [ "$r_u1" = "$SHP/x" ] && [ "$r_u2" = 2 ] && [ "$r_u3" = 6 ] && [ "$r_u4" = 6 ] && [ "$r_u5" = 0 ] && [ "$r_n1" = 2 ]; then say "✅ INSTALLER: per-process links refused, symlink resolved before '..', kernel cross-check and canon failure each refuse, un-enterable root exits 2; an ordinary symlink-then-'..' accepted"; else ko "INSTALLER: R5 probes wrong (/proc/self/cwd/.. $r_m1, /dev/fd/.. $r_m2, ~/deep/../.. $r_m3, lexical-canon $r_u3, canon-fails $r_u4 want 6; canon /proc/self rc $r_u2 want 2; canon ~/deep/../../x '$r_u1' want '$SHP/x'; ordinary $r_g1, real canon_to $r_u5 want 0; un-enterable root $r_n1 want 2)"; fi
# R6-1..R6-3: a path string whose meaning depends on process state (OLDPWD via a bare '-', CDPATH, a cwd or path
# of PATH_MAX or more, an undecidable lstat) never changes the verdict: each canon layer refuses on its own, the
# kernel cross-check also checks a PARTIAL prefix, relative names are entered as ./<name>, writers get the
# checked canonical path. Running as root: the EACCES probe SKIP-with-reason.
R6="$W/r6"; mkdir -p "$R6/-" "$R6/nx" "$W/r6decoy/scripts/multitrack"; : >"$R6/afile"; R6P="$(cd -P -- "$R6" && pwd -P)"
r6seg="$(printf 'q%.0s' $(seq 1 200))"; r6long="$R6P"; for _i in $(seq 1 25); do r6long="$r6long/$r6seg"; done
r_w1="$(bash -c '. "$1"; canon() { printf "%s\n" "$1"; }; canon_to v "$2"' _ "$FN" "$SH/deep/../../.claude/nonexist6/x" >/dev/null 2>&1; echo $?)"
r_w2="$(cd -- "$R6" && OLDPWD="$SH" bash -c '. "$1"; canon_to v "$2"' _ "$FN" "-/nx/y" >/dev/null 2>&1; echo $?)"
r_w3="$(bash -c '. "$1"; canon "$2" >/dev/null' _ "$FN" "$r6long/x" 2>/dev/null; echo $?)"
r_w5="$(bash -c '. "$1"; canon "$2" >/dev/null' _ "$FN" "$R6/afile/../x" 2>/dev/null; echo $?)"
r_w6="$(bash -c '. "$1"; canon "$2" >/dev/null' _ "$FN" "$R6/$r6seg$r6seg/x" 2>/dev/null; echo $?)"
r_w7="$(bash -c '. "$1"; canon "$2" >/dev/null' _ "$FN" "$R6/a"$'\n'"b" 2>/dev/null; echo $?)"
r_w10="$(bash -c '. "$1"; canon "$2"' _ "$FN" "$R6/nx/y/../z" 2>/dev/null)"
if [ "$(id -u)" != 0 ]; then mkdir -p "$R6/nox"; chmod 000 "$R6/nox"; r_w4="$(bash -c '. "$1"; canon "$2" >/dev/null' _ "$FN" "$R6/nox/x" 2>/dev/null; echo $?)"; chmod 755 "$R6/nox"; else r_w4=1; say "ℹ️  INSTALLER: running as root: EACCES probe SKIP-with-reason"; fi
r_w8="$(cd -- "$R6" && env -u CLAUDE_CONFIG_DIR -u CDPATH OLDPWD="$SH/.claude" HOME="$SH" MT_HOST=cmatl-nohost MT_CONFIG_DIR="$W/noconfig" bash "$inst" --project-root "$P" --out-dir nxr6/../-/agents >/dev/null 2>&1; echo $?):$([ -n "$(ls -A "$R6/-/agents" 2>/dev/null)" ] && echo 1 || echo 0):$(find "$R6" -maxdepth 1 -name nxr6 | wc -l)"
r_w9="$(cd -- "$ROOT" && env -u CLAUDE_CONFIG_DIR CDPATH="$W/r6decoy" HOME="$SH" MT_HOST=cmatl-nohost MT_CONFIG_DIR="$W/noconfig" bash scripts/multitrack/install_agent_label_defs.sh --project-root "$P" --dry-run >/dev/null 2>&1; echo $?)"
r_w11="$(cd -- "$R6" && env -u CDPATH OLDPWD="$SH" bash "$gen" --track 1 --branch main --out-dir -- --models sonnet --efforts low >/dev/null 2>&1; echo $?):$(find "$R6/--" -maxdepth 1 -name 'T1-main-sonnet-low.md' 2>/dev/null | wc -l):$(cd -- "$R6" && env -u CDPATH bash "$gen" --track 1 --branch main --out-dir -- --models sonnet --efforts low 2>/dev/null | grep -c '^UNCHANGED')"
r_w12="$(cd -- "$R6" && env -u CLAUDE_CONFIG_DIR -u CDPATH OLDPWD="$SH" HOME="$SH" MT_HOST=cmatl-nohost MT_CONFIG_DIR="$W/noconfig" bash "$inst" --project-root - --dry-run >/dev/null 2>&1; echo $?)"
if [ "$r_w1" = 6 ] && [ "$r_w2" = 0 ] && [ "$r_w3" = 1 ] && [ "$r_w4" = 1 ] && [ "$r_w5" = 1 ] && [ "$r_w6" = 1 ] && [ "$r_w7" = 1 ] && [ "$r_w8" = "0:1:0" ] && [ "$r_w9" = 0 ] && [ "$r_w10" = "$R6P/nx/z" ] && [ "$r_w11" = "0:1:1" ] && [ "$r_w12" = 0 ]; then say "✅ INSTALLER: partial-prefix kernel cross-check, '-' never OLDPWD, CDPATH ignored, PATH_MAX / NAME_MAX / ENOTDIR / EACCES / newline refused, ENOENT lexical, writers get the canonical path"; else ko "INSTALLER: R6 probes wrong (partial-prefix lexical canon $r_w1 want 6; relative '-' $r_w2 want 0; PATH_MAX $r_w3, EACCES $r_w4, ENOTDIR $r_w5, NAME_MAX $r_w6, newline $r_w7 want 1; -/agents via nxr6/.. '$r_w8' want 0:1:0; CDPATH decoy $r_w9 want 0; ENOENT '$r_w10'; generator --out-dir -- write+rerun '$r_w11' want 0:1:1 (rerun UNCHANGED); --project-root - $r_w12 want 0)"; fi
# R7-1..R7-5: every captured path (readlink target, pwd -P, canon's output, project root, own directory) is
# byte-exact and refused when it holds a newline; PATH_MAX / NAME_MAX / EACCES / multibyte boundaries hold in both
# directions; --classify reads an option-like name as a file; a failing sha256 tool never writes an empty hash.
nl=$'\n'; R7="$W/r7"; mkdir -p "$R7/tgt" "$R7/c$nl" "$R7/d" "$R7/rp/p$nl" "$R7/rp/other"; R7P="$(cd -P -- "$R7" && pwd -P)"
ln -s "tgt$nl" "$R7/lnl"; ln -s tgt "$R7/lok"; ln -s "$SH/.claude/agents" "$R7/d/foo"; mkdir "$R7/d/foo$nl"; ln -s "d/foo$nl/" "$R7/L"
r7c() { bash -c '. "$1"; v="$(canon "$2")"; r=$?; printf "%s:%s" "$r" "$v"' _ "$FN" "$1" 2>/dev/null; }
r_y1="$(r7c "$R7/lnl/x")"; r_y1="${r_y1%%:*}"
r_y2="$(cd -- "$R7/c$nl" && bash -c '. "$1"; canon x >/dev/null' _ "$FN" 2>/dev/null; echo $?)"
r_y3="$(cd -- "$R7" && bash -c '. "$1"; B="$2"; canon() { case "$1" in .) printf "%s\n" "$B" ;; *) printf "%s\n" "$B/c" ;; esac; }; canon_kcheck "$3" x' _ "$FN" "$R7P" "c$nl/x" 2>/dev/null; echo $?)"
r_y4="$(bash -c '. "$1"; canon() { printf "%s\n\n" "$1"; }; canon_kcheck() { return 0; }; canon_to v "$2"' _ "$FN" "$R7P/tgt" >/dev/null 2>&1; echo $?)"
r_y9="$(bash -c '. "$1"; canon_to v "$2" && printf "%s" "$v"' _ "$FN" "$R7/lok/x" 2>/dev/null)"
agn() { find "$SH/dotreal/agents" -maxdepth 1 -name 'T*' 2>/dev/null | wc -l; }
r_y5="$(env -u CLAUDE_CONFIG_DIR -u CDPATH HOME="$SH" MT_HOST=cmatl-nohost MT_CONFIG_DIR="$W/noconfig" bash "$inst" --project-root "$P" --out-dir "$R7/L" >/dev/null 2>&1; echo $?):$(agn)"
for d in "$R7/rp/p$nl" "$R7/rp/other"; do git -C "$d" init -q -b main 2>/dev/null; git -C "$d" -c user.email=g@g -c user.name=g commit -q --allow-empty -m i 2>/dev/null; done; ln -s "$R7/rp/other" "$R7/rp/p"
r_y6="$(env -u CLAUDE_CONFIG_DIR -u CDPATH HOME="$SH" MT_HOST=cmatl-nohost MT_CONFIG_DIR="$W/noconfig" bash "$inst" --project-root "$R7/rp/p$nl" >/dev/null 2>&1; echo $?):$(find "$R7/rp" -name 'T*.md' | wc -l)"
r_y11="$(cd -- "$R7/rp/p$nl" && env -u CLAUDE_CONFIG_DIR -u CDPATH -u PROJECT_ROOT HOME="$SH" MT_HOST=cmatl-nohost MT_CONFIG_DIR="$W/noconfig" bash "$inst" >/dev/null 2>&1; echo $?):$(find "$R7/rp" -name 'T*.md' | wc -l)"
cp -r "$ROOT/scripts/multitrack" "$R7/idecoy"; cp -r "$ROOT/scripts/multitrack" "$R7/i$nl"; ln -s "$R7/idecoy" "$R7/i"
printf '#!/usr/bin/env bash\n: >"%s"\n' "$R7/imarker" >"$R7/idecoy/gen_agent_label_defs.sh"
r_y8="$(env -u CLAUDE_CONFIG_DIR -u CDPATH HOME="$SH" MT_HOST=cmatl-nohost MT_CONFIG_DIR="$W/noconfig" bash "$R7/i$nl/install_agent_label_defs.sh" --project-root "$P" --dry-run >/dev/null 2>&1; echo $?):$([ -e "$R7/imarker" ] && echo 1 || echo 0)"
rm -f "$R7/idecoy/agent_label_colors.tsv"
r_y10="$(bash "$R7/i$nl/gen_agent_label_defs.sh" --track 1 --branch main --out-dir "$R7/gout" --models sonnet --efforts low >/dev/null 2>&1; echo $?)"
mkdir -p "$R7/cl"; bash "$gen" --track 1 --branch main --out-dir "$R7/cl" --models sonnet --efforts low >/dev/null 2>&1; cp -- "$R7/cl/T1-main-sonnet-low.md" "$R7/cl/-y.md"
r_y7="$(cd -- "$R7/cl" && bash "$gen" --classify -y.md 2>/dev/null)"
mkdir -p "$R7/shabin"; printf '#!/bin/sh\nexit 1\n' >"$R7/shabin/sha256sum"; chmod +x "$R7/shabin/sha256sum"
r_x6="$(PATH="$R7/shabin:$PATH" bash "$gen" --track 1 --branch main --out-dir "$R7/x6" --models sonnet --efforts low >/dev/null 2>&1; echo $?):$(find "$R7/x6" -name 'T1-*' 2>/dev/null | wc -l)"
pm7="$(getconf PATH_MAX / 2>/dev/null)"; case "$pm7" in ''|*[!0-9]*) pm7=1024 ;; esac
nm7="$(getconf NAME_MAX / 2>/dev/null)"; case "$nm7" in ''|*[!0-9]*) nm7=255 ;; esac
s7="$R7P/nxb"; while [ $((${#s7} + 201)) -lt $((pm7 - 1)) ]; do s7="$s7/$r6seg"; done
k7=$((pm7 - ${#s7} - 1)); l7="$(printf 'r%.0s' $(seq 1 "$k7"))"
r_x1="$(r7c "$s7/$l7")"; r_x1="${r_x1%%:*}"; r_x1g="$(r7c "$s7/${l7%r}")"; r_x1g="${r_x1g%%:*}"
n7="$(printf 'n%.0s' $(seq 1 "$nm7"))"; r_x2="$(r7c "$R7/$n7/x")"; r_x2="${r_x2%%:*}"
if [ "$(id -u)" != 0 ]; then
  mkdir -p "$R7/m644" "$R7/m111"; ln -s "$SH/.claude/agents" "$R7/m644/lnk"; chmod 0644 "$R7/m644"; chmod 0111 "$R7/m111"
  r_x3a="$(r7c "$R7/m644/lnk")"; r_x3a="${r_x3a%%:*}"; r_x3b="$(r7c "$R7/m111/miss/y")"; r_x3b="${r_x3b%%:*}"; chmod 755 "$R7/m644" "$R7/m111"
else r_x3a=1; r_x3b=0; say "ℹ️  INSTALLER: running as root: EACCES-direction probes SKIP-with-reason"; fi
u8=""; for lc in C.UTF-8 C.utf8 en_US.UTF-8 en_US.utf8; do [ "$(LC_ALL=$lc bash -c 'x=é; echo ${#x}' 2>/dev/null)" = 1 ] && { u8="$lc"; break; }; done
if [ -n "$u8" ]; then e128="$(printf 'é%.0s' $(seq 1 128))"; r_x4="$(LC_ALL=$u8 bash -c '. "$1"; canon "$2" >/dev/null' _ "$FN" "$R7/$e128/x" 2>/dev/null; echo $?)"; else r_x4=1; say "ℹ️  INSTALLER: no UTF-8 locale: multibyte probe SKIP-with-reason"; fi
if [ "$r_y1" = 1 ] && [ "$r_y2" = 1 ] && [ "$r_y3" = 1 ] && [ "$r_y4" = 6 ] && [ "$r_y5" = "6:0" ] && [ "$r_y6" = "6:0" ] && [ "$r_y7" = genuine ] && [ "$r_y8" = "5:0" ] && [ "$r_y9" = "$R7P/tgt/x" ] && [ "$r_y10" = 5 ] && [ "$r_y11" = "6:0" ] && [ "$r_x1" = 1 ] && [ "$r_x1g" = 0 ] && [ "$r_x2" = 0 ] && [ "$r_x3a" = 1 ] && [ "$r_x3b" = 0 ] && [ "$r_x4" = 1 ] && [ "$r_x6" = "5:0" ]; then say "✅ INSTALLER: byte-exact captures (newline in a link target / cwd / kernel answer / canon output / project root / own directory refused), PATH_MAX / NAME_MAX / EACCES / multibyte boundaries in both directions, option-like --classify name, failing sha256 never writes"; else ko "INSTALLER: R7 probes wrong (link target 'tgt\\n' $r_y1, cwd 'c\\n' $r_y2, kernel answer $r_y3 want 1; canon output $r_y4 want 6; P/L->'d/foo\\n/' '$r_y5' want 6:0; root 'p\\n' '$r_y6', default root '$r_y11' want 6:0; --classify -y.md '$r_y7' want genuine; own dir installer '$r_y8' want 5:0, generator $r_y10 want 5; ordinary link '$r_y9'; PATH_MAX $r_x1 want 1, PATH_MAX-1 $r_x1g want 0; NAME_MAX $r_x2 want 0; 0644 $r_x3a want 1, 0111 $r_x3b want 0; multibyte $r_x4 want 1; failing sha256 '$r_x6' want 5:0)"; fi
rm -f "$SH/dotreal/agents/T"*
if [ "$r_s1" = 6 ] && [ "$r_s2" = 6 ] && [ "$r_s3" = 6 ] && [ "$r_s4" = 6 ] && [ "$r_s5" = 6 ] && [ "$r_s6" = 6 ] && [ "$r_s7" = 0 ]; then say "✅ INSTALLER: refuses a symlinked ~/.claude (out-dir and target), an out-dir containing it, an empty-HOME passwd home, HOME itself and an ancestor of HOME"; else ko "INSTALLER: user-level refusal bypassed (symlink out-dir $r_s1, symlink target $r_s2, out-dir contains $r_s3, empty HOME $r_s4, HOME $r_s5, HOME ancestor $r_s6; want 6; empty-HOME ordinary project $r_s7 want 0)"; fi
# a project whose .claude IS the user-level agent config dir is refused (F1)
UC="$W/ucfg"; mkdir -p "$UC/.claude"; git -C "$UC" init -q -b main 2>/dev/null; git -C "$UC" -c user.email=g@g -c user.name=g commit -q --allow-empty -m i 2>/dev/null
CLAUDE_CONFIG_DIR="$UC/.claude" MT_HOST=cmatl-nohost MT_CONFIG_DIR="$W/noconfig" bash "$inst" --project-root "$UC" >/dev/null 2>&1; r_uc=$?
if [ "$r_uc" -eq 6 ] && [ ! -e "$UC/.claude/agents" ]; then say "✅ INSTALLER: refuses the user-level config dir (exit 6, nothing written)"; else ko "INSTALLER: user-level config dir not refused (exit $r_uc)"; fi
# ── 7 HOOK ───────────────────────────────────────────────────────────────────────
CFG="/nonexistent/.claude-cmatl"
LBL="(T1/main - cmatl - sonnet - low) probe"
hk() { # enforce subagent_type [bypass-empty] [extra-json-members] -> exit code ; stdout/stderr in $W/h.out/$W/h.err ; project in $HP
  local enf="$1" st="$2" extra="${3-}" xm="${4-}" pl P="${HP:-$P}"
  if [ -n "$st" ]; then pl='{"tool_name":"Agent","tool_input":{"description":"'"$LBL"'","subagent_type":"'"$st"'","prompt":"p"'"$xm"'}}'
  else pl='{"tool_name":"Agent","tool_input":{"description":"'"$LBL"'","prompt":"p"'"$xm"'}}'; fi
  if [ -n "$extra" ]; then
    printf '%s' "$pl" | env -u AGENT_TYPE_LABEL_AGENTS_DIR CLAUDE_PROJECT_DIR="$P" CLAUDE_CONFIG_DIR="$CFG" AGENT_TYPE_LABEL_ENFORCE="$enf" AGENT_TYPE_LABEL_BYPASS="" bash "$hook" >"$W/h.out" 2>"$W/h.err"
  else
    printf '%s' "$pl" | env -u AGENT_TYPE_LABEL_AGENTS_DIR -u AGENT_TYPE_LABEL_BYPASS CLAUDE_PROJECT_DIR="$P" CLAUDE_CONFIG_DIR="$CFG" AGENT_TYPE_LABEL_ENFORCE="$enf" bash "$hook" >"$W/h.out" 2>"$W/h.err"
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
hk 0 T2-other-sonnet-low; r9=$?; w9="$(grep -ci 'agent type' "$W/h.out" "$W/h.err" | awk -F: '{s+=$NF} END{print s+0}')"
hk 1 T2-other-sonnet-low; r10=$?
if [ "$r9" -eq 0 ] && [ "$w9" -gt 0 ] && [ "$r10" -eq 2 ]; then say "✅ HOOK: a type of ANOTHER track warns (exit 0) and blocks under ENFORCE (exit 2)"; else ko "HOOK: cross-track type not detected (warn exit $r9 lines $w9, enforce exit $r10)"; fi
hk 1 T1-main-sonnet-low "" ',"model":"opus"'; r11=$?
hk 1 T1-main-sonnet-low "" ',"effort":"high"'; r12=$?
hk 1 T1-main-sonnet-low "" ',"model":"sonnet","effort":"low"'; r13=$?
if [ "$r11" -eq 2 ] && [ "$r12" -eq 2 ] && [ "$r13" -eq 0 ]; then say "✅ HOOK: a model/effort parameter that overrides the type blocks under ENFORCE; matching parameters pass"; else ko "HOOK: model/effort override check wrong (model $r11, effort $r12 want 2/2; matching $r13 want 0)"; fi
hk 0 'T2-q\"b\\s-sonnet-low'; r14=$?
if [ "$r14" -eq 0 ] && python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["hookSpecificOutput"]["additionalContext"]' "$W/h.out" 2>/dev/null; then say "✅ HOOK: WARN payload is valid JSON for a subagent_type with a quote and a backslash"; else ko "HOOK: WARN payload is not valid JSON (exit $r14: $(head -c 160 "$W/h.out"))"; fi
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
