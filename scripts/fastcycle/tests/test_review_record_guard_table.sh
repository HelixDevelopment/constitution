#!/bin/bash
# test_review_record_guard_table.sh
#
# T048 restart, V3 round 4, structural item (3) (R4-F3; constitution
# 11.4.276(C)/(D), 11.4.194(6)(d)). The defect class "a guard claimed with no
# isolating case" recurred three times (R2-F6, R3-F3, R4-F3) because round 3's
# meta-check trusted a HAND-MAINTAINED list of 19 functions, saw only
# `if`+return/append, and bound one case to a whole compound condition. This
# file REPLACES that table with facts derived from the source and a measured
# kill ledger:
#
#   M1  GUARDED SET = the call graph of cmd_gate/cmd_record
#       (lib/review_record_guard_analyzer.py). EVERY decision construct in it
#       -- if/elif, while, assert, conditional expression, comprehension
#       filter, except handler, boolean-valued return/assignment -- carries
#       "# guard: <ID>" or "# not-a-guard: <reason of >= 15 chars>" directly
#       above its statement. A function added to the call graph is covered
#       the moment it is called; nothing is hand-listed.
#   M2  guard IDs are unique; no tag sits in a function outside the call
#       graph (a stale tag), and no not-a-guard tag lacks a reason.
#   M3  a "# guard:" tag on a statement that is NOT a decision construct (a
#       data-flow guard: a key composition, a merge, a path list, a strict
#       parser hook) is bound in DATA_GUARDS below to >= 1 mutation of the
#       paired runner whose old text occurs exactly once and lands on that
#       statement, or to EQUIVALENT(<id>): <reason>.
#   M4  the KILL LEDGER (fixtures/review_record_subclause_kills.tsv, written
#       by test_review_record_subclause_sweep.sh) is FRESH -- its sha256 of
#       review_record.py, the analyzer, the genuine helper and every suite
#       equal the current files -- and COMPLETE: its rows are exactly the
#       current sub-clauses (same id, same leaf, same flip), each KILLED with
#       >= 1 isolating case (a check that passes on the control and not on
#       that one-sub-clause mutant), or SURVIVED and listed in
#       fixtures/review_record_equivalent_subclauses.tsv with a reason of
#       >= 20 chars. An equivalence entry for a sub-clause that does not
#       exist or was killed is stale and fails too.
#
# Usage : bash test_review_record_guard_table.sh
#   GB1..GB11 golden-bad self-validation: each perturbed copy MUST make the
#   meta-check fail for its own reason (constitution 11.4.107(10)).
# Exit  : 0 consistent AND every golden-bad case caught; 1 otherwise;
#         2 scratch dir unusable.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
TOOL="$FC/review/review_record.py"
RUNNER="$HERE/test_review_record_gate_authority_mutations.sh"
ANALYZER="$HERE/lib/review_record_guard_analyzer.py"
LEDGER="$HERE/fixtures/review_record_subclause_kills.tsv"
EQUIV="$HERE/fixtures/review_record_equivalent_subclauses.tsv"

# DATA_GUARDS: ID <TAB> runner mutation id(s), comma-separated | EQUIVALENT(<id>): <reason>
DATA_GUARDS=$(cat <<'EOF'
G-T-LINK-EDGE	G-T-LINK-EDGE-off
G-T-STORE-ALL-ENTRIES	R4-C-store-tier-records-only
G-K-BATCH-KEY	R3-M3-batchkey-str
G-V-LATEST-ROUND	R7-M4
G-S-MERGE	EQUIVALENT(R3-M12): the merged unit carries EVERY copy's path (G-S-MERGE-PATHS, killed by R4-A) and every copy is admitted on its own first, so which copy is the representative cannot change a decision
G-S-MERGE-PATHS	R4-A-merge-paths-dropped
G-L-ALL-ROWS	R3-M6-label-last-row-only
G-D-REUSE-KEY	R4-H-dispatch-reuse-ignores-batch
G-A-EVIDENCE-STRICT	R4-E-evidence-dupkey-allowed
G-V-LAST-LISTING	R3-M1-earliest-listing
G-E-NONBLOCK	G-E-NONBLOCK-off
EOF
)

# check TOOL RUNNER LEDGER EQUIV DATA_GUARDS_TEXT -> report; 0 consistent / 1 not
check() {
DATA="$5" python3 - "$1" "$2" "$3" "$4" "$ANALYZER" "$HERE" <<'PY'
import ast, hashlib, importlib.util, os, re, sys

tool, runner, ledger, equiv, analyzer, here = sys.argv[1:7]
spec = importlib.util.spec_from_file_location("an", analyzer)
A = importlib.util.module_from_spec(spec); spec.loader.exec_module(A)
src = open(tool, encoding="utf-8").read()
lines = src.splitlines()
tree = ast.parse(src)
fails = []

# --- M1: every decision construct in the call graph is tagged --------------
fns = A.reachable(tree)
cons = A.constructs(tree, fns)
tg = A.tags(lines)
anchors = {}
for fn, kind, anchor, _n, _e in cons:
    anchors.setdefault(anchor, (fn, kind))
for anchor, (fn, kind) in sorted(anchors.items()):
    t = tg.get(anchor - 1)
    if t is None:
        fails.append("M1: %s line %d (%s) carries no '# guard:'/'# not-a-guard:' tag: %s"
                     % (fn, anchor, kind, lines[anchor - 1].strip()[:90]))

# --- M2: unique IDs, tags only inside the call graph, reasons present ------
funcs = {n.name: n for n in tree.body if isinstance(n, ast.FunctionDef)}
def fn_of(line):
    for name, node in funcs.items():
        if node.lineno <= line <= node.end_lineno:
            return name
    return None
seen = {}
for ln, (k, v) in sorted(tg.items()):
    if k == "bad":
        fails.append("M2: line %d '# not-a-guard:' carries no real reason (>= 15 chars): %s" % (ln, v))
        continue
    owner = fn_of(ln)
    if owner not in fns:
        fails.append("M2: line %d tag in %s, which is outside the cmd_gate/cmd_record call graph (stale tag)" % (ln, owner))
    if k == "guard":
        if v in seen:
            fails.append("M2: guard id %s is used twice (lines %d and %d)" % (v, seen[v], ln))
        seen[v] = ln

# --- M3: data-flow guards bound to a runner mutation -----------------------
data = {}
for raw in os.environ["DATA"].splitlines():
    if raw.strip():
        gid, spec_ = raw.split("\t", 1)
        data[gid] = spec_
rtext = open(runner, encoding="utf-8").read()
tsv = rtext[rtext.index("<<'EOF'\n") + 8: rtext.index("\nEOF\n", rtext.index("<<'EOF'\n"))]
muts = {}
for line in tsv.splitlines():
    mid, old, _new = line.split("\t")
    muts[mid] = ast.literal_eval(old)
stmt_end = {}
for n in ast.walk(tree):
    if isinstance(n, ast.stmt):
        stmt_end.setdefault(n.lineno, n.end_lineno if not hasattr(n, "body") else n.lineno)
data_tags = {v: ln for ln, (k, v) in tg.items() if k == "guard" and ln + 1 not in anchors}
for gid in sorted(set(data_tags) - set(data)):
    fails.append("M3: data-flow guard %s (line %d) is not bound in DATA_GUARDS" % (gid, data_tags[gid]))
for gid in sorted(set(data) - set(data_tags)):
    fails.append("M3: DATA_GUARDS row %s names no data-flow guard tag in the source (stale row)" % gid)
for gid, spec_ in sorted(data.items()):
    if gid not in data_tags:
        continue
    if spec_.startswith("EQUIVALENT("):
        if ": " not in spec_ or len(spec_.split(": ", 1)[1]) < 20:
            fails.append("M3: %s EQUIVALENT claim carries no real reason" % gid)
        continue
    target = data_tags[gid] + 1
    span = (target - 1, stmt_end.get(target, target))
    for mid in [x for x in spec_.split(",") if x]:
        if mid not in muts:
            fails.append("M3: %s mutation %s is not in the runner TSV" % (gid, mid)); continue
        old = muts[mid]
        if src.count(old) != 1:
            fails.append("M3: %s mutation %s old text occurs %d times (need 1)" % (gid, mid, src.count(old))); continue
        start = src[:src.index(old)].count("\n") + 1
        end = start + old.rstrip("\n").count("\n")
        if not (start <= span[1] and end >= span[0]):
            fails.append("M3: %s mutation %s (lines %d-%d) does not land on the guarded statement %s" % (gid, mid, start, end, span))

# --- M4: kill ledger fresh and complete ------------------------------------
def sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()
rows = A.subclauses(src)
want = {r["id"]: (r["leaf"], r["repl"]) for r in rows}
try:
    ltext = open(ledger, encoding="utf-8").read().splitlines()
except OSError as exc:
    ltext = None
    fails.append("M4: kill ledger unreadable (%s) -- run test_review_record_subclause_sweep.sh" % exc)
if ltext is not None:
    hdr = {}
    got = {}
    for line in ltext:
        if line.startswith("# tool_sha256="):
            hdr["tool"] = line.split("=", 1)[1]
        elif line.startswith("# analyzer_sha256="):
            hdr["analyzer"] = line.split("=", 1)[1]
        elif line.startswith("# genuine_sha256="):
            hdr["genuine"] = line.split("=", 1)[1]
        elif line.startswith("# suite "):
            name, h = line[len("# suite "):].split(" sha256=")
            hdr["suite:" + name] = h
        elif line and not line.startswith("#"):
            f = line.split("\t")
            if len(f) != 6:
                fails.append("M4: malformed ledger row %r" % line[:80]); continue
            got[f[0]] = f
    cur = {"tool": sha(tool), "analyzer": sha(analyzer),
           "genuine": sha(os.path.join(here, "lib", "review_record_genuine.sh"))}
    suites = [k[6:] for k in hdr if k.startswith("suite:")]
    if not suites:
        fails.append("M4: ledger names no suites")
    for name in suites:
        p = os.path.join(here, name)
        cur["suite:" + name] = sha(p) if os.path.exists(p) else "<missing>"
    for k, v in sorted(cur.items()):
        if hdr.get(k) != v:
            fails.append("M4: kill ledger is STALE: %s sha256 %s != current %s -- re-run the sweep" % (k, hdr.get(k), v))
    eq = {}
    try:
        for line in open(equiv, encoding="utf-8").read().splitlines():
            if line.strip() and not line.startswith("#"):
                f = line.split("\t")
                if len(f) != 3 or len(f[2]) < 20:
                    fails.append("M4: equivalence entry without a real reason: %r" % line[:80]); continue
                eq[f[0]] = f
    except OSError:
        pass
    for sid in sorted(set(want) - set(got)):
        fails.append("M4: sub-clause %s (%s) has no ledger row" % (sid, want[sid][0][:60]))
    for sid in sorted(set(got) - set(want)):
        fails.append("M4: ledger row %s names no current sub-clause (stale row)" % sid)
    for sid in sorted(set(want) & set(got)):
        f = got[sid]
        if (f[1], f[2]) != want[sid]:
            fails.append("M4: ledger row %s was measured on a different leaf/flip (%s -> %s)" % (sid, f[1][:40], f[2][:40]))
            continue
        if f[3] == "KILLED" and f[4].isdigit() and int(f[4]) >= 1:
            if sid in eq:
                fails.append("M4: %s is KILLED but listed EQUIVALENT (stale equivalence)" % sid)
            continue
        if f[3] == "SURVIVED" and sid in eq and eq[sid][1] == want[sid][0]:
            continue
        fails.append("M4: sub-clause %s is %s with %s isolating case(s) and no equivalence entry: %s -> %s"
                     % (sid, f[3], f[4], want[sid][0][:70], want[sid][1][:40]))
    for sid in sorted(set(eq) - set(want)):
        fails.append("M4: equivalence entry %s names no current sub-clause (stale)" % sid)

n_guard = len({v for k, v in tg.values() if k == "guard"})
print("call graph: %d functions; decision statements: %d; guard ids: %d (%d data-flow); sub-clauses: %d"
      % (len(fns), len(anchors), n_guard, len(data_tags), len(rows)))
for f in fails:
    print("NOT ok " + f)
print("guard meta-check: %s" % ("FAILED (%d)" % len(fails) if fails else "complete and consistent"))
sys.exit(1 if fails else 0)
PY
}

FAIL=0
echo "== guard meta-check against the REAL source, runner, analyzer and kill ledger =="
if check "$TOOL" "$RUNNER" "$LEDGER" "$EQUIV" "$DATA_GUARDS"; then echo "ok GT-REAL: every guard sub-clause has a measured isolating case (or a reasoned equivalence)"
else echo "NOT ok GT-REAL: guard meta-check failed (see NOT ok lines)"; FAIL=1; fi

# Self-validation: each golden-bad perturbation MUST fail for its own reason.
S=$(mktemp -d) || { echo "cannot create temp dir" >&2; exit 2; }
trap 'rm -rf "$S"' EXIT INT TERM
golden_bad() { # golden_bad NAME EXPECTED_SUBSTRING TOOL RUNNER LEDGER EQUIV DATA
  local out rc=0
  out=$(check "$3" "$4" "$5" "$6" "$7" 2>&1) || rc=$?
  if [ "$rc" -ne 0 ] && printf '%s\n' "$out" | grep -qF -- "$2"; then echo "ok $1: meta-check FAILS ($2)"
  else echo "NOT ok $1: meta-check did not fail with '$2':"; printf '%s\n' "$out" | tail -4; FAIL=1; fi
}
perturb() { # perturb OUT PY_STMT_ON_s : apply a python edit to a copy of the tool
  python3 - "$TOOL" "$1" "$2" <<'PY'
import sys
s = open(sys.argv[1]).read()
exec(sys.argv[3])
open(sys.argv[2], "w").write(s)
PY
}
# GB1: a refusing `if` loses its tag.
perturb "$S/gb1.py" 's = s.replace("    # guard: G-Q-PRODUCER-NAMED\n", "", 1)'
golden_bad GB1-untagged-if "carries no '# guard:'" "$S/gb1.py" "$RUNNER" "$LEDGER" "$EQUIV" "$DATA_GUARDS"
# GB2: a NEW function joins the call graph with an untagged refusal (no list to update).
perturb "$S/gb2.py" 's = s.replace("def cmd_gate(a):\n", "def _new_check(x):\n    if x:\n        raise ValueError(x)\n\n\ndef cmd_gate(a):\n    _new_check(None)\n", 1)'
golden_bad GB2-new-function "_new_check line" "$S/gb2.py" "$RUNNER" "$LEDGER" "$EQUIV" "$DATA_GUARDS"
# GB3: an `except` handler loses its tag.
perturb "$S/gb3.py" 's = s.replace("            # guard: G-L-DUPKEY-RAISE\n", "", 1)'
golden_bad GB3-untagged-except "(except) carries no" "$S/gb3.py" "$RUNNER" "$LEDGER" "$EQUIV" "$DATA_GUARDS"
# GB4: a comprehension filter loses its tag.
perturb "$S/gb4.py" 's = s.replace("        # guard: G-V-LISTING-SET\n", "", 1)'
golden_bad GB4-untagged-filter "(filter) carries no" "$S/gb4.py" "$RUNNER" "$LEDGER" "$EQUIV" "$DATA_GUARDS"
# GB5: the tool changed after the ledger was measured.
perturb "$S/gb5.py" 's = s + "\n# an edit after the sweep\n"'
golden_bad GB5-stale-ledger "kill ledger is STALE: tool" "$S/gb5.py" "$RUNNER" "$LEDGER" "$EQUIV" "$DATA_GUARDS"
# GB6: a ledger row turned SURVIVED with no equivalence entry.
awk -F'\t' 'BEGIN{OFS="\t"} !/^#/ && !d && $4=="KILLED" {$4="SURVIVED"; $5="0"; d=1} {print}' "$LEDGER" > "$S/gb6.tsv"
golden_bad GB6-survivor "SURVIVED with 0 isolating case(s) and no equivalence entry" "$TOOL" "$RUNNER" "$S/gb6.tsv" "$EQUIV" "$DATA_GUARDS"
# GB7: an equivalence entry with no real reason.
{ cat "$EQUIV" 2>/dev/null; printf 'G-Q-SEAM-TIER#1\tx\tshort\n'; } > "$S/gb7.tsv"
golden_bad GB7-bare-equivalence "equivalence entry without a real reason" "$TOOL" "$RUNNER" "$LEDGER" "$S/gb7.tsv" "$DATA_GUARDS"
# GB8: a data-flow guard with no bound mutation.
golden_bad GB8-unbound-data-guard "is not bound in DATA_GUARDS" "$TOOL" "$RUNNER" "$LEDGER" "$EQUIV" \
  "$(printf '%s\n' "$DATA_GUARDS" | grep -v '^G-D-REUSE-KEY	')"
# GB9: a not-a-guard tag with no reason.
perturb "$S/gb9.py" 's = s.replace("# not-a-guard: cleanup of the temp file on the error path only", "# not-a-guard: x", 1)'
golden_bad GB9-reasonless-not-a-guard "carries no real reason" "$S/gb9.py" "$RUNNER" "$LEDGER" "$EQUIV" "$DATA_GUARDS"
# GB10: a guard tag in a function outside the call graph.
perturb "$S/gb10.py" 's = s.replace("def _evidence_hash_verified(evidence, evidence_sha256, record_own_path, records_root, base_dir=None):\n", "def _evidence_hash_verified(evidence, evidence_sha256, record_own_path, records_root, base_dir=None):\n    # guard: G-ZZ-STALE\n    if evidence is None:\n        return False\n", 1)'
golden_bad GB10-stale-tag "outside the cmd_gate/cmd_record call graph" "$S/gb10.py" "$RUNNER" "$LEDGER" "$EQUIV" "$DATA_GUARDS"
# GB11: a sub-clause row deleted from the ledger.
awk -F'\t' '!/^#/ && !d {d=1; next} {print}' "$LEDGER" > "$S/gb11.tsv"
golden_bad GB11-missing-row "has no ledger row" "$TOOL" "$RUNNER" "$S/gb11.tsv" "$EQUIV" "$DATA_GUARDS"

echo ""
[ "$FAIL" -eq 0 ] && { echo "== guard table: ok =="; exit 0; }
echo "== guard table: FAILED =="; exit 1
