#!/usr/bin/env bash
# tests/workable_items/test_remint_ids_mutations.sh -- paired mutation test (section 1.1) for
# scripts/workable-items/remint_ids.py and its suite tests/workable_items/test_remint_ids.sh.
#
# Documentation (section 11.4.18): docs/guides/remint_ids_guide.md.
#
# WHAT  Each mutant is one exact text replacement in a COPY of the tool (target T) or of the suite
#   (target S); the replaced text must occur exactly once, otherwise the mutant is stale and the test
#   fails. For each mutant the suite runs (REMINT_IDS_FAILFAST=1, so it stops at its first failing
#   case) and must exit 1 with a FAIL line: a setup error (exit 2) is not a kill. An unmutated copy
#   must pass the full suite (the control).
#   RC-mutants: the round-3 reviewer's remint mutants, verbatim where the text still exists (RC4, RC7)
#   and mapped onto the round-4 code otherwise (RC1 obsolete_details values, RC2 status, RC3 Opened
#   row, RC5 states updated_at, RC6 assigned_to, RC8 first new id). X-mutants: every check the
#   round-4 planner, replay, verify and rewriter carry (base-item replay, conflicts, refusals, the
#   obsolete_details row on each lifecycle path, the item-wide foreign set on text and on scripts,
#   the replay and verify guards). S-mutants: the suite's own fixture instrument (fx_sql).
# ENV   WORKABLE_ITEMS        path of the workable-items engine binary (default: the tracked
#                             scripts/workable-items/bin/workable-items; exit 2 when not executable)
#       REMINT_IDS_MUT_JOBS   parallel mutants (default 3)
#       REMINT_IDS_MUT_ONLY   run only the mutants whose id is listed (comma separated)
# EXIT  0 every mutant killed and the control passes; 1 otherwise; 2 setup error, or the cleanup of
#       the temp dir was refused.
# EVIDENCE CLASS  gate-logic only (section 11.4.289).
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 2
root=$(cd "$here/../.." && pwd) || exit 2
src=$root/scripts/workable-items/remint_ids.py
suite=$here/test_remint_ids.sh
[ -f "$src" ] && [ -f "$suite" ] || { echo "setup: tool or suite missing" >&2; exit 2; }
export WORKABLE_ITEMS=${WORKABLE_ITEMS:-$root/scripts/workable-items/bin/workable-items}
[ -x "$WORKABLE_ITEMS" ] || { echo "setup: engine binary not executable: $WORKABLE_ITEMS (set WORKABLE_ITEMS)" >&2; exit 2; }
# shellcheck source=../../scripts/lib/safe_rm.sh
. "$root/scripts/lib/safe_rm.sh" || exit 2
tmp=$(mktemp -d) || exit 2
cleanup() {
  local st=$?
  if ! safe_rm_rf "${tmp:?}"; then echo "CLEANUP REFUSED: temp dir left behind: $tmp" >&2; exit 2; fi
  exit "$st"
}
trap cleanup EXIT
jobs=${REMINT_IDS_MUT_JOBS:-3}
case "$jobs" in ''|*[!0-9]*|0) echo "setup: REMINT_IDS_MUT_JOBS must be a positive integer" >&2; exit 2 ;; esac

# Escapes in old/new: \n is a newline, \\n is a literal backslash-n (as written in Python source).
# id | target (T tool, S suite) | old ||| new   (old and new are split at the first "|||")
mutants=(
  'RC1 verify: obsolete_details values not compared|T|        if norm(want[c]) != norm(got[c]):\n            bad.append("%s obsolete_details.%s|||        if False:\n            bad.append("%s obsolete_details.%s'
  'RC2 verify: own status not compared|T|"body_md", "atm_id", "created_at", "last_modified"]]|||"body_md", "atm_id", "created_at", "last_modified", "status"]]'
  'RC3 verify: Opened history row not required|T|    if own_item and not any(h["event_type"] == "Opened" for h in r_new):|||    if False:'
  'RC4 rewrite: each file written before the next is checked|T|        results.append((f, n, new, text))|||        results.append((f, n, new, text))\n        if a.write and new != text:\n            open(f, "w", encoding="utf-8").write(new)'
  'RC5 replay: states updated_at dropped|T|    if at:\n        argv.append("--states-updated-at=" + at)|||    if False:\n        argv.append("--states-updated-at=" + at)'
  'RC6 replay: assigned_to dropped|T|            if norm(v["assigned_to"]):|||            if False:'
  'RC7 map: two old ids may share one new id|T|if len(set(m.values())) != len(m):|||if False:'
  'RC8 plan: first new id = max(target) (collides)|T|            start = max(num(i) for i in T if rx.fullmatch(i)) + 1|||            start = max(num(i) for i in T if rx.fullmatch(i))'
  'X1 base item: update step not replayed|T|        if ucols:|||        if False:'
  'X2 base item: state block not replayed|T|            if any(c in dv for c in cols):\n                k, argv = block_steps(i, loc, v, cols, rewr, foreign, label, n)|||            if False:\n                k, argv = block_steps(i, loc, v, cols, rewr, foreign, label, n)'
  'X3 base item: lifecycle not replayed|T|        if life_v:|||        if False:'
  'X4 conflicts not detected|T|        if clash or (dt and life_v) or (dv and life_t):|||        if False:'
  'X5 plan foreign set from the title only (R3-2 shape)|T|        for col in TEXT_REWRITE + ["body_md"]:|||        for col in ["title"]:'
  'X6 verify foreign set from the title only (R3-2 shape)|T|for r in rows for c in TEXT_REWRITE + ["body_md"]], prefix,|||for r in rows for c in ["title"]], prefix,'
  'X7 plan always FAST-FORWARD|T|    fast_forward = all(table_rows(con["target"], t) == table_rows(con["base"], t) for t in KNOWN_TABLES)|||    fast_forward = True'
  'X8 replay: target sha256 not checked|T|    if got != plan["sha256"]["target"]:|||    if False:'
  'X9 replay: -wal sidecar not checked|T|    if os.path.isfile(wal) and os.path.getsize(wal) > 0:|||    if False:'
  'X10 verify: untouched target items not compared|T|        if R.get(i) != T[i]:|||        if False:'
  'X11 --resolve target ignored|T|        if res == "target":\n            continue|||        if False:\n            continue'
  'X12 stamp-only change not refused|T|        for n in stamp_only:|||        for n in []:'
  'X13 body_md-only change not refused|T|            if norm(v["body_md"]) != norm(b["body_md"]):|||            if False:'
  'X14 red/green scripts not scanned|T|                    for hit in scripts_naming_moved(row[col], a.repo_root, m, prefix, foreign):|||                    for hit in []:'
  'X15 another table changed by the vehicle not refused|T|        if tables["vehicle"][t] != tables["base"][t]:|||        if False:'
  'X16 own item with a column add cannot carry not refused|T|                if norm(v[c]) and c != "representation":|||                if False:'
  'X17 verify: closure row evidence not compared|T|        if norm(h["evidence_path"]) not in v_ev:|||        if False:'
  'X18 obsolete_details lost on close-then-reopen (round-4 fix reverted)|T|        obs(close())\n        reopen()|||        close()\n        reopen()'
  'X19 obsolete_details lost on close|T|        obs(ts if close() else None)|||        close()'
  'X20 obsolete_details lost when the lifecycle is unchanged|T|        obs(fs)  # the lifecycle is unchanged; a changed obsolete_details row is still replayed|||        pass'
  'X21 obsolete_details lost before a reopen of a closed item|T|        obs(fs)\n        reopen()|||        reopen()'
  'X22 obsolete_details on an open item not refused|T|        if status_word(status) != "Obsolete":|||        if False:'
  'X23 a script comment Foreign line not honoured|T|        fo.add_text("\\n".join(x.group(1) for x in SCRIPT_FOREIGN_LINE.finditer(text)), prefix)\n|||'
  'X24 the item foreign set not applied to its scripts|T| and not foreign.has(int(t.group(1)))]|||]'
  'X25 verify: database sha256 not checked against the plan|T|        if not os.path.isfile(p) or sha256_file(p) != plan["sha256"][k]:|||        if not os.path.isfile(p):'
  'X26 verify: Reopened row not compared|T|        if not r_ro or tuple(norm(r_ro[-1][k]) for k in key) != tuple(norm(v_last[k]) for k in key):|||        if False:'
  'X27 verify: target history rows not compared|T|        if HR.get(hid) != h:|||        if False:'
  'X28 verify: other tables not compared|T|        if table_rows(cr, t) != table_rows(ct, t):|||        if False:'
  'X29 verify: --require-segments not checked|T|            if i not in segs:|||            if False:'
  'X30 rewrite: Foreign line rewritten|T|            if FOREIGN_LINE.match(line):\n                out.append(line)|||            if False:\n                out.append(line)'
  'X31 verify: map keys not checked against the own set|T|    if sorted(m) != own:|||    if False:'
  'X32 verify: plan map prefix not checked|T|        if mp != prefix:|||        if False:'
  'X33 a deleted base item not refused|T|    for i in sorted(set(B) - set(V)):|||    for i in []:'
  'X34 a rewritten base history row not refused|T|        if hist["vehicle"].get(hid) != h:|||        if False:'
  'X35 a non-item doc segment not refused|T|    if [tuple(r) for r in con["vehicle"].execute(seg_non_item)] != [tuple(r) for r in con["base"].execute(seg_non_item)]:|||    if False:'
  'X36 an ambiguous base text not refused|T|                if int(t.group(1)) in rewr.by_num and not foreign.has(int(t.group(1))):|||                if False:'
  'X37 rewrite: partly moved range not refused|T|        if len(moved) != b - a + 1:|||        if False:'
  'X38 rewrite: tokens chained once|T|            return self.m[k]|||            return self.m.get(self.m[k], self.m[k])'
  'X39 rewrite: non-contiguous range not refused|T|        if new != list(range(new[0], new[0] + len(new))):|||        if False:'
  'X40 rewrite: a .db file accepted|T|    if f.endswith(".db") or f.endswith(".bundle"):|||    if f.endswith(".bundle"):'
  'X41 verify: base-change state stamps not compared|T|                    if norm(v[c]) != norm(r[c]):\n                        bad.append("%s %s: landed %r, vehicle %r"|||                    if False:\n                        bad.append("%s %s: landed %r, vehicle %r"'
  'X42 rewrite: an id inside a path rewritten|T|            if before == "/" or after[:1] == "/" or re.match(r"\.\w", after):|||            if False:'
  'S1 suite: a failing fixture edit is ignored|S|echo "setup: fx_sql failed: $2" >&2; exit 2;|||true;'
  'S2 suite: a fixture edit that matches no row is accepted|S|if n == 0:  # DML that matched no row; DDL reports -1|||if False:'
  'S3 suite: fx_sql may touch the real database|S|  [ "$a" != "$b" ] || { echo "setup: fx_sql refuses the real database" >&2; exit 2; }\n  case "$a" in "$tmp"/*) ;; *) echo "setup: fx_sql edits only scratch copies under the temp dir" >&2; exit 2 ;; esac|||  :'
)

mkcopy() { # mkcopy <src> <dest> <old> <new>  (\n in old/new is a newline)
  python3 -I - "$1" "$2" "$3" "$4" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
def unesc(t):  # "\\\\n" (two backslashes) is a literal backslash-n; "\\n" is a newline
    return t.replace("\\\\n", "\0").replace("\\n", "\n").replace("\0", "\\n")
old, new = unesc(old), unesc(new)
s = open(src).read()
n = s.count(old)
if old and n != 1:
    sys.stderr.write("stale mutant: %d matches for %r\n" % (n, old[:80])); sys.exit(1)
open(dst, "w").write(s.replace(old, new) if old else s)
PY
}

# one_mutant <index>: prints one verdict line; never touches files outside its own dir $tmp/m<index>
one_mutant() {
  local i=$1 m id rest target old new d a verdict
  m=${mutants[$i]}
  id=${m%%|*}; rest=${m#*|}; target=${rest%%|*}; rest=${rest#*|}
  old=${rest%%|||*}; new=${rest#*|||}
  d=$tmp/m$i; mkdir -p "$d" || { echo "FAIL $id: no work dir"; return; }
  if [ "$target" = S ]; then
    if ! mkcopy "$suite" "$d/test_remint_ids.sh" "$old" "$new" 2>"$d/err"; then echo "FAIL $id: stale mutant"; return; fi
    REMINT_IDS_ROOT=$root REMINT_IDS=$src REMINT_IDS_FAILFAST=1 bash "$d/test_remint_ids.sh" >"$d/log" 2>&1
    a=$?
  else
    if ! mkcopy "$src" "$d/m.py" "$old" "$new" 2>"$d/err"; then echo "FAIL $id: stale mutant"; return; fi
    REMINT_IDS=$d/m.py REMINT_IDS_FAILFAST=1 bash "$suite" >"$d/log" 2>&1
    a=$?
  fi
  verdict=FAIL
  [ "$a" = 1 ] && grep -q '^FAIL ' "$d/log" && verdict=PASS
  echo "$verdict $id: rc=$a first-failure=$(grep -m1 '^FAIL ' "$d/log" | cut -c6-90)"
}

fail=0
mkcopy "$src" "$tmp/ctl.py" "" "" || exit 2
REMINT_IDS=$tmp/ctl.py bash "$suite" >"$tmp/ctl.log" 2>&1; a=$?
if [ "$a" = 0 ] && grep -q '^RESULT: pass=[0-9]* fail=0$' "$tmp/ctl.log"; then echo "PASS control: unmutated copy passes the suite ($(tail -1 "$tmp/ctl.log"))"
else echo "FAIL control: suite rc=$a; $(grep -m3 '^FAIL\|setup' "$tmp/ctl.log" | tr '\n' '|')"; fail=1; fi

sel=()
for i in "${!mutants[@]}"; do
  id=${mutants[$i]%% *}
  if [ -n "${REMINT_IDS_MUT_ONLY:-}" ]; then case ",$REMINT_IDS_MUT_ONLY," in *",$id,"*) ;; *) continue ;; esac; fi
  sel+=("$i")
done
export -f one_mutant mkcopy
export tmp root src suite
# bash cannot export arrays: hand each worker the mutant list through a file
printf '%s\n' "${mutants[@]}" >"$tmp/mutants.txt"
printf '%s\n' "${sel[@]}" | xargs -P "$jobs" -I{} bash -c 'mapfile -t mutants <"$tmp/mutants.txt"; one_mutant "$1" >"$tmp/v$1"' _ {}
for i in "${sel[@]}"; do
  if [ -f "$tmp/v$i" ]; then cat "$tmp/v$i"; grep -q '^PASS' "$tmp/v$i" || fail=1
  else echo "FAIL ${mutants[$i]%%|*}: no verdict"; fail=1; fi
done
echo "RESULT: mutants=${#sel[@]} $([ "$fail" = 0 ] && echo 'all killed' || echo 'FAILED')"
[ "$fail" = 0 ]
