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
#   the replay and verify guards; X2, X9, X39 and X41 mapped onto the round-5 code). RV-mutants: the
#   round-4 reviewer's mutants (RV1..RV7b), mapped onto the round-5 per-unit merge. N-mutants: every
#   check round 5 added (the per-unit merge and its convergence rules, the stamp refusal of
#   --resolve vehicle, the loose and between range forms, the tight hyphen, non-ASCII digits, the -wal
#   sidecar and URI quoting, verify's landing units, its conflict reports and its own text rules; N38..N47:
#   the defects the branch sweep found, i.e. every value passed as written refused when it names a moved
#   id, the always-passed time stamp and the merge line only for an item both sides changed; RC5, RC6,
#   N4 and N5 mapped onto that code; N48..N71: the survivors of the final branch sweep, i.e. the path
#   rule on a moved range, verify's plan guard and its reading of the own set, each branch of verify's
#   shared-item loop and its obsolete_details checks, replay's stop at a failing step, verify's two
#   self-checks and its text rules; N72..N88: the rest of that run's survivors, i.e. verify's segment
#   check and its control of untouched items, check_od, check_history, the referent condition, and the
#   planner's refusal of a removed obsolete_details row; N89..N91: three survivors of the sixth sweep
#   run, i.e. FAST-FORWARD verify's id-set and table checks and the CON-339 note on a created_at
#   MISMATCH, which run 5 had counted killed only through a flaky case). ROV-mutants: the round-5
#   reviewer's mutants (ROV1..ROV10) verbatim, except ROV3 (the clause without its line continuation), and
#   ROVFIX, the round-5 defect R5-1 put back (a field-only update passes the target's description).
#   RM-mutants: the round-6 reviewer's mutants (RM1..RM8) verbatim; RM2, RM3, RM6 and RM8 are killed by the
#   round-7 cases of section (11) of the suite. S-mutants: the suite's own fixture instrument (fx_sql).
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
  'RM1 verify re-render branch: landed body compared with the vehicle body itself|T|unslotted(r["body_md"], i, True)), fset)|||unslotted(v["body_md"], i, True)), fset)'
  'RM2 slots: the reopen Evidence bullet is not a slot|T|(?:By|On|Reason|Evidence):|||(?:By|On|Reason):'
  'RM3 slots: Obsolete-Details is not a slot|T|"**Reopened-Details:**",\n                 "**Obsolete-Details:**")|||"**Reopened-Details:**",)'
  'RM4 planner: every map pair goes to the rewriter (R5-2 reverted)|T|rewr = Rewriter({o: n for o, n in m.items() if o != n}, prefix)|||rewr = Rewriter(dict(m), prefix)'
  'RM5 cmd_plan: a refused plan carries no refusal|T|"refusals": [str(e)]|||"refusals": []'
  'RM6 planner: body conflict test ignores template meta lines|T|if rerender and res is None and unslotted(t["body_md"], i) != unslotted(b["body_md"], i):|||if rerender and res is None and unslotted(t["body_md"], i, True) != unslotted(b["body_md"], i, True):'
  'RM7 verify: a landed body without a heading line is not checked|T|if heads and heads[0] not in|||if len(heads) > 1 and heads[0] not in'
  'RM8 verify no-re-render branch ignores template meta lines|T|if unslotted(r["body_md"], i) != unslotted(t["body_md"], i):|||if unslotted(r["body_md"], i, True) != unslotted(t["body_md"], i, True):'
  'RC1 verify: obsolete_details values not compared|T|        if norm(want[c]) != norm(got[c]):\n            bad.append("%s obsolete_details.%s|||        if False:\n            bad.append("%s obsolete_details.%s'
  'RC2 verify: own status not compared|T|"body_md", "atm_id", "created_at", "last_modified"]]|||"body_md", "atm_id", "created_at", "last_modified", "status"]]'
  'RC3 verify: Opened history row not required|T|    if own_item and not any(h["event_type"] == "Opened" for h in r_new):|||    if False:'
  'RC4 rewrite: each file written before the next is checked|T|        results.append((f, n, new, text))|||        results.append((f, n, new, text))\n        if a.write and new != text:\n            open(f, "w", encoding="utf-8").write(new)'
  'RC5 replay: states updated_at dropped|T|    argv.append("--states-updated-at=" + rewr.keep(at, foreign, "%s %s_updated_at" % (label, prefix_name)))|||    pass'
  'RC6 replay: assigned_to dropped|T|            if kv["assigned_to"]:|||            if False:'
  'RC7 map: two old ids may share one new id|T|if len(set(m.values())) != len(m):|||if False:'
  'RC8 plan: first new id = max(target) (collides)|T|            start = max(num(i) for i in T if rx.fullmatch(i)) + 1|||            start = max(num(i) for i in T if rx.fullmatch(i))'
  'X1 base item: update step not replayed|T|        if ucols:|||        if False:'
  'X2 base item: state block not replayed|T|            if n in v_blocks and "the %s block" % n not in same:|||            if False:'
  'X3 base item: lifecycle not replayed|T|        if life_v:|||        if False:'
  'X4 conflicts not detected|T|        if clash or (dt and life_v) or (dv and life_t):|||        if False:'
  'X5 plan foreign set from the title only (R3-2 shape)|T|        for col in TEXT_REWRITE + ["body_md"]:|||        for col in ["title"]:'
  'X6 verify foreign set from the title only (R3-2 shape)|T|for r in rows for c in TEXT_REWRITE + ["body_md"]], prefix,|||for r in rows for c in ["title"]], prefix,'
  'X7 plan always FAST-FORWARD|T|    fast_forward = all(table_rows(con["target"], t) == table_rows(con["base"], t) for t in KNOWN_TABLES)|||    fast_forward = True'
  'X8 replay: target sha256 not checked|T|    if got != plan["sha256"]["target"]:|||    if False:'
  'X9 replay: -wal sidecar not checked|T|    wal = a.db + "-wal"\n    if os.path.isfile(wal) and os.path.getsize(wal) > 0:|||    wal = a.db + "-wal"\n    if False:'
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
  'X39 rewrite: non-contiguous range not refused|T|        if new != list(range(new[0], new[0] + len(new))):\n            raise Refusal(|||        if False:\n            raise Refusal('
  'X40 rewrite: a .db file accepted|T|    if f.endswith(".db") or f.endswith(".bundle"):|||    if f.endswith(".bundle"):'
  'X41 verify: a vehicle-side non-text column not compared|T|                elif norm(v[c]) != norm(r[c]):\n                    bad.append("%s %s: landed %r, vehicle %r"|||                elif False:\n                    bad.append("%s %s: landed %r, vehicle %r"'
  'X42 rewrite: an id inside a path rewritten|T|    if before == "/" or after[:1] == "/" or re.match(r"\.\w", after):|||    if False:'
  'RV1 verify: target-side units not compared with the target (round-4 reviewer)|T|            elif norm(t[c]) != norm(r[c]):\n                bad.append("%s %s: landed %r, target %r (%s)"|||            elif False:\n                bad.append("%s %s: landed %r, target %r (%s)"'
  'RV2 plan: merged base item always takes the vehicle description (round-4 reviewer; remapped to the round-6 update argv)|T|            argv = ["update", "--id=" + i, "--db", "{DB}", "--location=" + loc]|||            argv = ["update", "--id=" + i, "--db", "{DB}", "--location=" + loc, "--description=" + vland("description")]'
  'RV3 plan/rewrite: en dash ranges no longer recognised (round-4 reviewer)|T|-([0-9]+))(\.\.|–)(" + p|||-([0-9]+))(\.\.)(" + p'
  'RV4 verify: own-item created_at drift not reported as KNOWN (round-4 reviewer)|T|            known.append("%s created_at: replay time %s (vehicle %s), not carried" % (new, r["created_at"], v["created_at"]))|||            pass'
  'RV5 verify: base-item created_at drift without a closure is KNOWN (round-4 reviewer)|T|            (known if closed else bad).append(|||            known.append('
  'RV6 verify: base-item body_md not compared (round-4 reviewer; remapped to the round-6 check_body call)|T|        check_body(i, v, b, t, r, tdiff, rv, fset, plan["steps"], same_text, bad)|||        pass'
  'RV7a plan: vehicle lifecycle + target change no longer a conflict (round-4 reviewer)|T|        if clash or (dt and life_v) or (dv and life_t):|||        if clash or (dv and life_t):'
  'RV7b plan: target lifecycle + vehicle change no longer a conflict (round-4 reviewer)|T|        if clash or (dt and life_v) or (dv and life_t):|||        if clash or (dt and life_v):'
  'N1 plan: a target stamp-only change of a block is not a target change|T|            if not changed(t, b, cols):\n                dt += changed(t, b, STAMPS[n])|||            if False:\n                dt += changed(t, b, STAMPS[n])'
  'N2 plan: block convergence ignores the stamps|T| and not changed(v, t, STAMPS[n])|||'
  'N3 plan: a block clash is downgraded to the same change|T|                (same if converged else clash).append("the %s block" % n)|||                same.append("the %s block" % n)'
  'N4 plan: a column clash is downgraded to the same change|T|                (same if vland(c) == norm(t[c]) else clash).append(c)|||                same.append(c)'
  'N5 plan: column convergence compares the unmapped vehicle text|T|(same if vland(c) == norm(t[c]) else clash)|||(same if norm(v[c]) == norm(t[c]) else clash)'
  'N6 plan: a converged block is written anyway|T|            if n in v_blocks and "the %s block" % n not in same:|||            if n in v_blocks:'
  'N7 plan: the target description runs through the map (R4-1a reverted; remapped to the round-6 update argv)|T|            argv = ["update", "--id=" + i, "--db", "{DB}", "--location=" + loc]|||            argv = ["update", "--id=" + i, "--db", "{DB}", "--location=" + loc] + ([] if "description" in ucols else ["--description=" + rewr.text(norm(t["description"]), foreign, label)[0]])'
  'N8 plan: a target stamp change does not mark its block changed|T|changed(t, b, cols + STAMPS[n])]|||changed(t, b, cols)]'
  'N9 plan: columns the vehicle did not change are written|T|        ucols = [c for c in UPDATE_COLS if c in dv and vland(c) != norm(t[c])]|||        ucols = [c for c in UPDATE_COLS if vland(c) != norm(t[c])]'
  'N10 plan: an unlandable --resolve vehicle of stamps is not refused|T|            for n in stuck:\n                refuse(|||            for n in []:\n                refuse('
  'N11 plan: every --resolve vehicle of a block clash is refused|T|"the %s block" % n in clash and all(vland(c) == norm(t[c]) for c in cols)]|||"the %s block" % n in clash]'
  'N12 plan: a non-ASCII new id gets the wrong refusal|T|% i if rx_uni.fullmatch(i)|||% i if False'
  'N13 plan/verify: a non-empty -wal sidecar read|T|    if os.path.isfile(wal) and os.path.getsize(wal) > 0:\n        raise Refusal("%s has a non-empty -wal sidecar; checkpoint it first (its sha256|||    if False:\n        raise Refusal("%s has a non-empty -wal sidecar; checkpoint it first (its sha256'
  'N14 plan/verify: the database path read as URI syntax|T|"file:%s?mode=ro" % urllib.parse.quote(os.path.abspath(path))|||"file:%s?mode=ro" % os.path.abspath(path)'
  'N15 rewrite: no loose or between range checked|T|        for rx in (self.loose, self.between):|||        for rx in ():'
  'N16 rewrite: between ... and not checked|T|        for rx in (self.loose, self.between):|||        for rx in (self.loose,):'
  'N17 rewrite: ids joined by a tight hyphen accepted|T|                    if self.moved_in(min(lo, hi), max(lo, hi), foreign):\n                        raise Refusal("%s: range %s joins|||                    if False:\n                        raise Refusal("%s: range %s joins'
  'N18 rewrite: a moved id in non-ASCII digits accepted|T|            if n in self.by_num and not foreign.has(n):\n                raise Refusal("%s: %s writes moved|||            if False:\n                raise Refusal("%s: %s writes moved'
  'N19 rewrite: a chained range read pair by pair without overlap|T|                pos = r.end(3)  # the second id can start the next range|||                pos = r.end()'
  'N20 verify: the refused columns dropped from the landing units|T|V_UNITS = (["atm_id"] + UPDATE_COLS + REFUSED_COLS + LIFECYCLE|||V_UNITS = (["atm_id"] + UPDATE_COLS + LIFECYCLE'
  'N21 verify: an unresolved column conflict not reported|T|            elif c in tch and not rv:\n                bad.append(|||            elif False:\n                bad.append('
  'N22 verify: an unresolved block conflict not reported|T|            elif t_ch and not rv:\n                bad.append(|||            elif False:\n                bad.append('
  'N23 verify: an unresolved lifecycle conflict not reported|T|        if not rv and ((life_v and (tch or t_od)) or (life_t and (dv or od_changed))):|||        if False:'
  'N24 verify: block convergence ignores the stamps|T| and all(norm(v[c]) == norm(t[c]) for c in STAMPS[n]):|||:'
  'N25 verify: a vehicle-side block compared with the target|T|                for c in unit:\n                    land(c, "vehicle", "")|||                for c in unit:\n                    land(c, "target", "")'
  'N26 verify: the same text change compared exactly (no map)|T|            if c in TEXT_REWRITE:\n                return v_compare(norm(v[c]), norm(t[c]), m, fset, prefix) is None|||            if False:\n                return v_compare(norm(v[c]), norm(t[c]), m, fset, prefix) is None'
  'N27 verify: the lifecycle always compared with the target|T|            land(c, "vehicle" if life_v else "target", "a lifecycle the vehicle did not change")|||            land(c, "target", "a lifecycle the vehicle did not change")'
  'N28 verify: an obsolete_details row the vehicle did not write not caught|T|        if not od_changed and OR.get(i) != OT.get(i):|||        if False:'
  'N29 verify: the text rules not applied|T|    if rule:\n        return rule\n    sk_w, tk_w|||    sk_w, tk_w'
  'N30 verify: a partly moved range accepted|T|        if len(inside) != b - a + 1:|||        if False:'
  'N31 verify: a moved id in non-ASCII digits accepted|T|        if not u.group(1).isascii() and int(u.group(1)) in moved|||        if False and int(u.group(1)) in moved'
  'N32 verify: between ... and read as a list|T|        if conn == "and" and not r.group(1):|||        if conn == "and":'
  'N33 verify: ids joined by a hyphen accepted|T|        if r.group(3) == "-":\n            return "range %r joins ids with a hyphen"|||        if False:\n            return "range %r joins ids with a hyphen"'
  'N34 verify: a short-form range accepted|T|        if r.group(4) is None:\n            return "range %r is a short form"|||        if False:\n            return "range %r is a short form"'
  'N35 verify: a reverse range accepted|T|        if lo > hi:\n            return "range %r is reverse"|||        if False:\n            return "range %r is reverse"'
  'N36 verify: a range that lands apart accepted|T|        if new != list(range(new[0], new[0] + len(new))):\n            return "range %r maps|||        if False:\n            return "range %r maps'
  'N37 plan: the merge line hides the same change on both sides|T|"the same change on both sides: " + ",".join(same) if same else "disjoint columns"|||"disjoint columns"'
  'N38 keep: a moved id in a value passed as written accepted|T|        _, n = self.text(text, foreign, where)\n        if n:|||        _, n = self.text(text, foreign, where)\n        if False:'
  'N39 replay: a block non-text column not kept|T|            else:\n                val = rewr.keep(val, foreign, "%s %s" % (label, c))|||            else:\n                pass'
  'N40 replay: the closure evidence not kept|T|        ev = rewr.keep(ev, foreign, "%s closure evidence" % label)|||        pass'
  'N41 replay: the obsolete_details fields not kept|T|rewr.keep(norm(v_od[c]), foreign, "%s obsolete_details.%s" % (label, c))|||norm(v_od[c])'
  'N42 replay: the Reopened row not kept|T|rewr.keep(norm(ro_rows[-1][c]), foreign, "%s Reopened row %s" % (label, c))|||norm(ro_rows[-1][c])'
  'N43 replay: a base non-text column not kept|T|            return rewr.keep(norm(v[c]), foreign, "%s %s" % (label, c))|||            return norm(v[c])'
  'N44 replay: an own item column not kept|T|            kv = {c: rewr.keep(norm(v[c]), foreign, "%s %s" % (label, c))|||            kv = {c: norm(v[c])'
  'N45 replay: the block author not kept|T|(rewr.keep(by, foreign, "%s %s_updated_by" % (label, prefix_name)) or "remint_ids.py")|||(by or "remint_ids.py")'
  'N46 replay: an empty time stamp dropped (lands as the replay time)|T|    argv.append("--states-updated-at=" + rewr.keep(at, foreign, "%s %s_updated_at" % (label, prefix_name)))|||    if at:\n        argv.append("--states-updated-at=" + at)'
  'N47 plan: a merge line for an item only the vehicle changed|T|        elif dt:\n            merges.append(|||        elif True:\n            merges.append('
  'N48 rewrite: a moved range inside a path rewritten (T1)|T|                if n and in_path(line, r.start(), r.end()):|||                if False:'
  'N49 verify: a plan the planner did not call landable is verified (T2)|T|    if plan["conflicts"] or plan["refusals"]:\n        raise Refusal("the plan has %d conflict(s) and %d refusal(s): it was never|||    if False:\n        raise Refusal("the plan has %d conflict(s) and %d refusal(s): it was never'
  'N50 verify: a new vehicle id outside the prefix not flagged (T3)|T|        if not idrx.fullmatch(i):|||        if False:'
  'N51 verify: the own set counts a new id outside the prefix|T|    own = sorted((i for i in set(V) - set(B) if idrx.fullmatch(i)), key=num)|||    own = sorted((i for i in set(V) - set(B) if True), key=num)'
  'N52 verify: the referent of a rewritten id not checked|T|            if x != y and "." not in x and "–" not in x:|||            if False:'
  'N53 verify: a vehicle or base item with two rows not flagged|T|        if len(V[i]) != 1 or len(B[i]) != 1:|||        if False:'
  'N54 verify: an item nobody changed checked as replayed (the planner skips it)|T|        if vb_same:\n            continue|||        if False:\n            continue'
  'N55 verify: an item whose only change is a time stamp checked as replayed|T|        if not dv and not od_changed:|||        if False:'
  'N56 verify: a replayed item that landed as two rows not flagged|T|        if i not in R or len(R[i]) != 1:|||        if False:'
  'N57 verify: a column outside the rewrite set compared under the map|T|            if c in TEXT_REWRITE:\n                return v_compare|||            if True:\n                return v_compare'
  'N58 verify: a plan map entry that is not a pair is read|T|        if not (isinstance(pair, list) and len(pair) == 2):|||        if False:'
  'N59 replay: a failing engine step does not stop the replay|T|        if r.returncode != 0:|||        if False:'
  'N60 verify: its control needle result ignored|T|    if needle:|||    if False:'
  'N61 verify: its landing-unit partition not checked|T|    if sorted(V_UNITS) != sorted(ITEM_COLUMNS) or len(set(V_UNITS)) != len(V_UNITS):|||    if False:'
  'N62 verify: a range of ids that do not move held to the moved-range rules|T|        if not inside:|||        if False:'
  'N63 verify: a range mixing foreign and moved ids accepted|T|        if any(a <= n <= b for n in nums) or any(not (h < a or l > b) for l, h in spans):|||        if False:'
  'N64 verify: every skeleton piece reported as the differing one|T|            if x != y:|||            if True:'
  'N65 verify: the differing skeleton piece never named|T|            if x != y:|||            if False:'
  'N66 verify: the piece count of a longer skeleton not reported|T|        return "text differs outside the ids (piece count %d vs %d)" % (len(sk_w), len(sk_g))|||        return "text differs outside the ids"'
  'N67 verify: a target obsolete_details change not named when body_md is left uncompared|T|        tdiff = sorted(tch) + (["obsolete_details"] if t_od else [])|||        tdiff = sorted(tch) + (["obsolete_details"] if False else [])'
  'N68 verify: a base item obsolete_details held to the vehicle when the vehicle did not change it|T|        if od_changed:\n            check_od(|||        if True:\n            check_od('
  'N69 verify: a base item obsolete_details the vehicle changed not compared|T|        if od_changed:\n            check_od(|||        if False:\n            check_od('
  'N70 verify: an untouched item obsolete_details row not compared with the target|T|        if OR.get(i) != OT.get(i):\n            bad.append("%s: obsolete_details differs from the target on an untouched item"|||        if False:\n            bad.append("%s: obsolete_details differs from the target on an untouched item"'
  'N71 verify: every own item reported with a created_at KNOWN line|T|        if norm(r["created_at"]) != norm(v["created_at"]):\n            known.append(|||        if True:\n            known.append('
  'N72 verify: doc_segments checked without --require-segments|T|    if a.require_segments:|||    if True:'
  'N73 verify: a landing that touched every target item not BLIND|T|    if not [i for i in T if i not in replayed]:|||    if False:'
  'N74 verify: every target item counted as untouched|T|    if not [i for i in T if i not in replayed]:|||    if not [i for i in T if True]:'
  'N75 check_od: a one-sided row always named as the vehicle side|T|"the vehicle" if want else "the landed database"|||"the vehicle" if True else "the landed database"'
  'N76 check_od: a one-sided row always named as the landed side|T|"the vehicle" if want else "the landed database"|||"the vehicle" if False else "the landed database"'
  'N77 check_od: no row on either side read as a row|T|    if want is None:\n        return|||    if False:\n        return'
  'N78 plan: a removed obsolete_details row not refused (B10)|T|        if bb_od is not None and vb_od is None:|||        if False:'
  'N79 check_history: every vehicle row counts as a cited closure|T|if h["event_type"] in CLOSURE_EVENTS and norm(h["evidence_path"])}|||if True}'
  'N80 check_history: the last landed row of any kind read as the Reopened row|T|r_ro = [h for h in r_new if h["event_type"] == "Reopened"]|||r_ro = [h for h in r_new if True]'
  'N81 check_history: a missing landed closure row not reported|T|    elif v_last and not r_cl:|||    elif False:'
  'N82 check_history: every vehicle history row counted as a lifecycle row|T|life_v = sum(1 for h in v_new if h["event_type"] in CLOSURE_EVENTS | {"Reopened"})|||life_v = sum(1 for h in v_new if True)'
  'N83 check_history: no vehicle history row counted as a lifecycle row|T|life_v = sum(1 for h in v_new if h["event_type"] in CLOSURE_EVENTS | {"Reopened"})|||life_v = sum(1 for h in v_new if False)'
  'N84 check_history: every landed history row counted as a lifecycle row|T|life_r = sum(1 for h in r_new if h["event_type"] in CLOSURE_EVENTS | {"Reopened"})|||life_r = sum(1 for h in r_new if True)'
  'N85 check_history: no landed history row counted as a lifecycle row|T|life_r = sum(1 for h in r_new if h["event_type"] in CLOSURE_EVENTS | {"Reopened"})|||life_r = sum(1 for h in r_new if False)'
  'N86 check_history: a lifecycle-count KNOWN line for every item|T|    if life_v != life_r:|||    if True:'
  'N87 check_history: no lifecycle-count KNOWN line|T|    if life_v != life_r:|||    if False:'
  'N88 verify: a rewritten id naming another item not reported (the referent condition)|T|                    bad.append("%s %s: %s now names %s, which is not the item %s named in the vehicle" % (i, col, x, y, x))|||                    pass'
  'N89 verify FAST-FORWARD: landed ids that are not the vehicle ids not reported|T|        if set(R) != set(V):|||        if False:'
  'N90 verify FAST-FORWARD: a table that differs from the vehicle not reported|T|            if table_rows(cr, t) != table_rows(cv, t):|||            if False:'
  'N91 verify: a created_at MISMATCH carries the CON-339 note of a KNOWN line|T|" (KNOWN engine defect CON-339: close rewrites it)" if closed else ""|||" (KNOWN engine defect CON-339: close rewrites it)" if True else ""'
  'ROV1 verify FAST-FORWARD: item_history not compared|T|for t in OTHER_TABLES + ["obsolete_details", "item_history"]:|||for t in OTHER_TABLES + ["obsolete_details"]:'
  'ROV2 verify: a new vehicle id in non-ASCII digits read into the own set|T|idrx = re.compile(re.escape(prefix) + r"-[0-9]+")|||idrx = re.compile(re.escape(prefix) + r"-\d+")'
  'ROV3 verify: the referent check ignores the item type|T|or vr[0]["type"] != rr[0]["type"] or norm(vr[0]["created_by"])|||or norm(vr[0]["created_by"])'
  'ROV4 planner: the close step replays the latest closure row, not the plain close|T|    pick = (plain or cl)\n|||    pick = cl\n'
  'ROV5 planner: a base item foreign set read from the vehicle row only|T|        foreign = item_foreign([v, b], prefix, a.foreign)\n|||        foreign = item_foreign([v], prefix, a.foreign)\n'
  'ROV6 verify: obsolete_details triple_check_evidence not compared|T|for c in ("since", "reason", "triple_check_evidence"):|||for c in ("since", "reason"):'
  'ROV7 Rewriter: ids of at most three digits|T|tok = re.compile(r"(?<![\w-])" + p + r"-([0-9]+)\b(?!-)")|||tok = re.compile(r"(?<![\w-])" + p + r"-([0-9]{1,3})\b(?!-)")'
  'ROV8 verify: foreign-id declarations of one digit only|T|idp = re.compile(re.escape(prefix) + r"-([0-9]+)")|||idp = re.compile(re.escape(prefix) + r"-([0-9])")'
  'ROV9 verify: the referent check ignores created_by|T| or norm(vr[0]["created_by"]) != norm(rr[0]["created_by"]):|||:'
  'ROV10 verify: the referent check ignores the title|T|if not vr or not rr or v_split(norm(vr[0]["title"])|||if not vr or not rr or False and v_split(norm(vr[0]["title"])'
  'ROVFIX planner: a field-only update re-renders the body through a forced --description (the round-5 defect R5-1)|T|"--db", "{DB}", "--location=" + loc]\n            for c in ucols:|||"--db", "{DB}", "--location=" + loc, "--description=" + norm(t["description"])]\n            for c in ucols:'
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
