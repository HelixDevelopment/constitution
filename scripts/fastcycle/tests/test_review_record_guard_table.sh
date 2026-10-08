#!/bin/bash
# test_review_record_guard_table.sh
#
# T048 restart, V3 round 3, structural item (3) (constitution 11.4.276(D),
# 11.4.194(6)(d)): the defect class "a guard claimed by the fix with no
# isolating case" recurred (R2-F6, R3-F3). This file makes that class
# MECHANICALLY impossible to ship again: a GUARD TABLE binds every guard in
# review/review_record.py to (a) an isolating test case and (b) a paired
# mutation, and a meta-check FAILS when any binding is missing or false.
#
# What the meta-check proves (all against the REAL files, nothing assumed):
#   M1  CLASSIFIER -- every `if` inside a guarded function whose own body
#       refuses (a `return` -- in cmd_record only `return 1` -- or an
#       append to blockers/failures/conflicts/orphans) carries, on the line
#       directly above it, either "# guard: <ID>" or "# not-a-guard: <why>".
#       Found with Python's ast over the real source, so a new refusal
#       branch cannot slip in untagged. Every function in GUARDED must still
#       exist (renaming one cannot hide its guards).
#   M2  every tagged ID has exactly one table row, and every row's ID is a
#       real tag in the source (no stale rows, no unlisted guards).
#   M3  every row names >= 1 case label, and each label appears as the
#       label of a real check (ok "LABEL..., chk "LABEL..., expect LABEL) in
#       one of the review_record suites.
#   M4  every row names >= 1 mutation id that exists in the runner's TSV
#       (test_review_record_gate_authority_mutations.sh), whose old text
#       occurs EXACTLY once in the source and lands on that guard's own
#       lines (from 2 lines above the tag to the end of the guarded `if`) --
#       a mutation aimed elsewhere does not count -- OR the literal
#       EQUIVALENT(<id>): <reason>, which is reported, never silent.
# The dynamic half -- every listed mutation is KILLED by the suites -- is
# the runner itself; this file proves the table is complete and honest.
#
# Usage : bash test_review_record_guard_table.sh
#   GB1..GB7 golden-bad self-validation: each perturbed copy (untagged guard,
#       missing row, fake case, misaimed / unknown mutation, reasonless
#       EQUIVALENT, renamed guarded function) MUST make the meta-check fail.
# Exit  : 0 table complete and consistent AND every golden-bad case caught;
#         1 otherwise; 2 scratch dir unusable.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
TOOL="$FC/review/review_record.py"
RUNNER="$HERE/test_review_record_gate_authority_mutations.sh"

# GUARD TABLE: ID <TAB> blocks <TAB> case labels (comma) <TAB> mutation ids (comma) | EQUIVALENT(...)
TABLE=$(cat <<'EOF'
G-T-ROOT	a root principal is treated as able to write anything	R3-U-ROOT	G-T-ROOT-off
G-T-OWNER-BIT	the owner write bit grants write	R3-U-OWNER-BIT	G-T-OWNER-BIT-off
G-T-GROUP-BIT	the group write bit (unknown membership: conservative)	R3-U-GROUP-BIT,R3-T9,R3-T12	G-T-GROUP-BIT-off,R3-M5-unknown-groups-not-conservative
G-T-OTHER-BIT	the other write bit grants write	R3-U-OTHER-BIT,T	G-T-OTHER-BIT-off
G-T-SUPP-GROUPS	supplementary group membership counts	R3-T12	R3-M4-primary-group-only
G-T-LEAF-OWNER	owning the evidence file defeats capability	R3-U-LEAF-OWNER	O16-leaf-owner
G-T-LEAF-WRITABLE	a writable evidence file defeats capability	R3-U-LEAF-WRITABLE,T	V3-N2-tier-leaf-writable
G-T-DIR-OWNER	owning a chain directory defeats capability	R3-U-DIR-OWNER	G-T-DIR-OWNER-off
G-T-DIR-WRITABLE	a writable non-sticky chain directory defeats capability	R3-U-DIR-WRITABLE,R3-U-STICKY-CTL,T	V3-N1-tier-dir-writable,R2-T1-tier-sticky-exemption
G-T-LINK-EDGE	the directory holding a symlink is checked	R3-T10	G-T-LINK-EDGE-off
G-T-PRODUCER-DECLARED	no/invalid producer uid -> instance	T	G-T-PRODUCER-DECLARED-off
G-T-PRODUCER-IS-RUNNER	producer uid == runner uid -> instance	R3-T6	G-T-PRODUCER-IS-RUNNER-off
G-T-PRODUCER-KNOWN	unknown producer uid -> instance	R3-T3	G-T-PRODUCER-KNOWN-off
G-T-RUNNER-PRINCIPAL	the uid running gate is checked too (single-uid -> instance)	R3-T1,R3-T4,T-CLI	R2-T3-tier-runner-principal
G-T-PATH-PRESENT	a missing evidence path -> instance	R3-U-NONE-PATH	G-T-PATH-PRESENT-off
G-T-PRINCIPAL-CAN-REPLACE	any principal able to replace any path -> instance	R3-T1,R3-T4,R3-T5	G-T-PRINCIPAL-CAN-REPLACE-off
G-AG-WEAKEST	COVERED reports the weakest achieved tier	R3-M8	R3-M8-tier-report-any
G-C-CONTAINED	a record outside --records is refused	R3-SYM	G-C-CONTAINED-off
G-C-PARSE	an unparseable record is refused	R3-C1	G-C-PARSE-off
G-C-OBJECT	a non-object record is refused	R3-C2	G-C-OBJECT-off
G-C-REQUIRED	a record missing required fields is refused	R3-C3	G-C-REQUIRED-off
G-C-INT-ROUND	a non-integer (incl. bool) round is refused	R3-M10	R3-M10-collect-bool-round
G-A-BODY-HASH	an edited live record is inadmissible	R3-E1,B1-C	O2-body-hash
G-A-EVIDENCE-VERIFIED	a live record without verifiable evidence is inadmissible	R3r,7: content-hash binding	G-A-EVIDENCE-VERIFIED-off
G-A-EVIDENCE-WELLFORMED	evidence without a well-formed verdict is inadmissible	R3-A1	G-A-EVIDENCE-WELLFORMED-off
G-A-EVIDENCE-OBJECT	evidence that is not a JSON object is inadmissible	R3-A3	G-A-EVIDENCE-OBJECT-off
G-A-BINDING-PRESENT	evidence without a review binding is inadmissible	m1b,R3b	R2-B4-gate-binding-required
G-A-REVIEWER-WELLFORMED	evidence with a malformed reviewer is inadmissible	R3-A2	G-A-REVIEWER-WELLFORMED-off
G-A-BINDING-EQUAL	record batch/changes/commits must equal the binding	P1c,P1d,P1h,P1g3,P1g4,R3-E5	R2-B5-gate-binding-batch,R2-B6-gate-binding-changes,R2-B7-gate-binding-head,R2-B8-gate-binding-base
G-A-ROUND-EQUAL	record round must equal the binding round	B1-E,R3-E6	O19-evidence-round
G-A-FIELDS-EQUAL	verdict/layers/reviewer/model/effort must equal the evidence	N6,N12,B1-C	O15-record-vs-evidence,V3-N6-record-layers,V3-N12-record-model-effort
G-A-SOURCE	an unrecognised source is inadmissible	R7 (closed-set source guard)	G-A-SOURCE-off
G-B-BODY-HASH	an edited backfill row is inadmissible	R3-B1	G-B-BODY-HASH-off
G-B-NO-LIVE-FIELDS	a relabelled live record is inadmissible	R3-E7,BF2	G-B-NO-LIVE-FIELDS-off
G-B-CHANGES-SHAPE	a malformed backfill change_ids is inadmissible	R3-B2	G-B-CHANGES-SHAPE-off
G-O-ORPHAN	an archived verdict no record points at is refused	R3-E8,R3-E9	G-O-ORPHAN-off
G-S-CONFLICT	two different records for one batch+round	I1	O6-same-round-conflict
G-S-MERGE	identical copies decided independently of filename	R3-M12a,R3-M12b	EQUIVALENT(R3-M12): copies merge into one unit carrying every path and each copy is admitted first, so the representative cannot change a decision
G-K-BATCH-KEY	1 and "1" are different batches everywhere	R3-M3	R3-M3-batchkey-str
G-L-PRESENT	no ledger -> no reviewer authenticates	B1-A4b	G-L-PRESENT-off
G-L-EVENT-NONE	a ledger row without an event never authenticates	R3-M7	R3-M7-missing-event-is-complete
G-L-HAS-ROWS	a dispatch with no ledger row	R3-L1	G-L-HAS-ROWS-off
G-L-EVENTS-CLOSED	crashed/failed/respawned never authenticate	m4: dispatch ledger events	R2-L1-ledger-bad-events
G-L-DISPATCHED	a dispatch needs a dispatched row	m4: dispatch ledger events	R2-L2-ledger-dispatched-row
G-L-LATEST-COMPLETE	the LATEST row must be complete	R3-M11,m4: dispatch ledger events	R2-L3-ledger-latest-complete,R3-M11-complete-anywhere
G-L-ONE-LABEL	exactly one 11.4.182 label per row	m4: a ledger row carrying more than one	R2-L4-ledger-one-label
G-L-ALL-ROWS	every row of the dispatch is label-checked	m4: a dispatch whose dispatched row names opus-high	R3-M6-label-last-row-only
G-L-LABEL-MATCH	the label must name the designated model/effort	B1-A5	O1-ledger-label
G-Q-ROUND-BUDGET	a round beyond the budget is not coverage	I3a4	O20-gate-round-budget
G-Q-REVIEWER	a reviewer-less verdict is not coverage	B1-A	O14-reviewer-required
G-Q-ZERO-FINDING-GO	only a zero-finding GO covers	B2-M1,B2-M2	R7-M1,R7-M2
G-Q-DESIGNATED-TIER	only opus/xhigh covers	B1-H	O24-designated-tier
G-Q-PRODUCER-NAMED	a record naming no producer is not coverage	B1-A6b	O21-producer-required
G-Q-PRODUCER-NOT-REVIEWER	producer == reviewer dispatch is not coverage	N11	V3-N11-gate-producer-is-reviewer
G-Q-LEDGER-READABLE	an unreadable/absent ledger is not coverage	B1-A4b	G-Q-LEDGER-READABLE-off
G-Q-LEDGER-AUTH	an unauthenticated dispatch is not coverage	B1-A4	G-Q-LEDGER-AUTH-off
G-Q-DISPATCH-REUSE	one dispatch backs one verdict	B1-B	O3-dispatch-reuse
G-Q-PRECHECK-USED	no precheck consulted is not coverage	R6 (R3-I4	G-Q-PRECHECK-USED-off
G-Q-PRECHECK-VERIFIED	a missing precheck archive is not coverage	R3-Q1	G-Q-PRECHECK-VERIFIED-off
G-Q-PRECHECK-SCHEMA	precheck must be precheck/v1	B1-A3	O5-precheck-schema
G-Q-PRECHECK-ALL-PASS	precheck all_pass must be true	B1-A2	O4-precheck-all-pass
G-Q-PRECHECK-BATCH	precheck must belong to the batch	N4	V3-N4-precheck-batch
G-Q-SLICES	a multi-slice batch needs every slice GO	I3b	O13-slice-coverage
G-Q-SEAM-TIER	high-blast seams need capability	B1-D,R3-T1	O10-seam-tier
G-V-BACKFILL-HISTORY	backfill rows are history, never coverage	BF,P3h	O12-backfill-history
G-V-BACKFILL-BLOCKS	a backfilled NO-GO blocks	P3g	R2-C4-backfill-nogo-blocks
G-V-LATEST-COVERS	only a batch's LATEST round covers	P3f	R2-C3-dropped-is-not-coverage,R3-M2-latest-always
G-V-REFUSAL-BLOCKS	an open NO-GO in any batch blocks	P3,R3-CTL	R2-C1-open-nogo-in-any-batch-blocks
G-V-LATEST-ROUND	rounds are ordered ascending	B2-M4	R7-M4
G-V-LAST-LISTING	the last round listing the change decides	B2-M4	R3-M1-earliest-listing
G-G-CHANGE-NAMED	--change must name a change	R3-G1	G-G-CHANGE-NAMED-off
G-G-BUDGET-RANGE	gate --round-budget within 5..7	R3-G2	G-G-BUDGET-RANGE-off
G-G-RECORDS-DIR	a missing --records is BLIND	R3-G3	G-G-RECORDS-DIR-off
G-G-ADMISSION	any inadmissible record blinds the run	R3-E1,R3-E12	G-G-ADMISSION-off
G-G-ORPHANS	any orphaned archive blinds the run	R3-E9	G-G-ORPHANS-off
G-G-CONFLICTS	a same-round conflict blinds the run	I1	G-G-CONFLICTS-off
G-G-UNCOVERED	no covering batch -> UNCOVERED	R3-G4	G-G-UNCOVERED-off
G-E-NAMED	an absent evidence citation never verifies	R3r	G-E-NAMED-off
G-E-PLACEHOLDER	an UNKNOWN/N/A/TBD citation never verifies	R3-A4	G-E-PLACEHOLDER-off
G-E-HASH-SHAPE	a non-sha256 pin never verifies	R3r	EQUIVALENT(hash-shape): a value that is not 64 lowercase hex can never equal a sha256 hexdigest, so G-E-HASH-MATCH refuses the same inputs
G-E-CONTAINED	evidence resolving outside --records never verifies	1: a symlink inside --records,5: a '..' path escape	O18-containment
G-E-SELF-CITATION	a record citing itself never verifies	3: a record citing its own file	EQUIVALENT(V3-N9): a file cannot carry its own content hash, so G-E-HASH-MATCH refuses it
G-E-REGULAR	non-regular evidence never verifies	R3-A5	EQUIVALENT(regular): with O_NONBLOCK a directory read raises (caught) and a FIFO reads empty (refused by G-E-HASH-MATCH); device nodes need root to create
G-E-HASH-MATCH	content swapped after archiving never verifies	7: content-hash binding	O17-hash-compare
G-E-BASE-DIR	evidence resolves against the record's own dir	I2	O7-evidence-base-dir
G-E-NONBLOCK	a FIFO planted as evidence cannot hang gate	R3-A5	G-E-NONBLOCK-off
G-RV-OBJECT	a non-object reviewer block is refused	R3-RV1	G-RV-OBJECT-off
G-RV-FIELDS	blank reviewer fields are refused	R3-RV2	G-RV-FIELDS-off
G-BD-PRESENT	a binding missing a field is refused	R3-BD1	G-BD-PRESENT-off
G-BD-BATCH-SHAPE	a padded/blank binding batch_id is refused	R3-BD2	G-BD-BATCH-SHAPE-off
G-BD-CHANGES-SHAPE	an empty/malformed binding change_ids is refused	R3-BD3	G-BD-CHANGES-SHAPE-off
G-BD-CHANGES-DISTINCT	a binding listing a change twice is refused	R3-BD4	G-BD-CHANGES-DISTINCT-off
G-BD-ROUND	a non-integer binding round is refused	N8	V3-N8-binding-bool-round
G-BD-COMMIT-SHAPE	non-commit review_base/head are refused	P1g2	R2-B9-commit-shape
G-R-ROUND-BUDGET	record refuses a round beyond the budget	I3a	O8-record-round-budget
G-R-DESIGNATED-TIER	record refuses a non-designated tier/effort	rb_bad_wrong_tier: record refused	G-R-DESIGNATED-TIER-off
G-R-REVIEWER-MATCHES-CLI	the reviewer's model/effort must match the CLI	B1-G	O23-reviewer-matches-cli
G-R-PRODUCER-NOT-REVIEWER	record refuses producer == reviewer	B1-A6	O11-producer-is-reviewer
G-R-BINDING-BATCH	record refuses a verdict bound to another batch/changes	P1,P1i,P1f,R3-BD5	R2-B1a-record-binding-batch,R2-B1b-record-binding-changes
G-R-BINDING-COMMITS	record refuses a commit range the batch declares differently	P1g,R3-M9	R2-B2-record-binding-commits,R3-M9-record-base-unchecked
EOF
)

# check TOOL RUNNER TABLE_TEXT -> prints the report, returns 0 consistent / 1 not.
check() {
TABLE="$3" python3 - "$1" "$2" "$HERE" <<'PY'
import ast, glob, os, re, sys

tool, runner, here = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(tool, encoding="utf-8").read()
lines = src.splitlines()
fails, notes = [], []

GUARDED = ["_writable_by", "_principal_can_replace", "_independence_tier", "_gate_collect_records",
           "_admit_live", "_admit_backfill", "_admit_record", "_orphaned_evidence",
           "_gate_same_round_conflicts", "_load_ledger", "_ledger_authenticates", "_verified_evidence_doc",
           "_gate_batch_qualifies", "_gate_change_verdict", "cmd_gate", "_evidence_bytes_verified",
           "cmd_record", "_validated_binding", "_validated_reviewer"]
APPENDERS = {"blockers", "failures", "conflicts", "orphans"}
TAG_RE = re.compile(r"^\s*# guard: (G-[A-Z0-9-]+)")
NOT_RE = re.compile(r"^\s*# not-a-guard: \S")

# --- tag sites: every "# guard: ID" line, with the span it protects --------
tree = ast.parse(src)
if_nodes = {n.lineno: n for n in ast.walk(tree) if isinstance(n, ast.If)}
stmt_starts = sorted({n.lineno for n in ast.walk(tree) if isinstance(n, ast.stmt)})
sites = {}  # id -> [(tag_line, end_line)]  (1-based)
for idx, line in enumerate(lines, 1):
    m = TAG_RE.match(line)
    if not m:
        continue
    nxt = idx + 1
    node = if_nodes.get(nxt)
    end = node.end_lineno if node is not None else next((s for s in stmt_starts if s > nxt), nxt + 1) - 1
    sites.setdefault(m.group(1), []).append((idx, max(end, nxt)))

# --- M1 classifier ----------------------------------------------------------
def refuses(stmt, fn):
    if isinstance(stmt, ast.Return):
        if fn == "cmd_record":
            return isinstance(stmt.value, ast.Constant) and stmt.value.value == 1
        return True
    return (isinstance(stmt, ast.Expr) and isinstance(stmt.value, ast.Call)
            and isinstance(stmt.value.func, ast.Attribute) and stmt.value.func.attr == "append"
            and isinstance(stmt.value.func.value, ast.Name) and stmt.value.func.value.id in APPENDERS)

funcs = {n.name: n for n in ast.walk(tree) if isinstance(n, ast.FunctionDef)}
classified = 0
for fn in GUARDED:
    if fn not in funcs:
        fails.append("M1: guarded function %s no longer exists (renamed? its guards would escape the table)" % fn)
        continue
    for n in ast.walk(funcs[fn]):
        if isinstance(n, ast.If) and any(refuses(b, fn) for b in n.body):
            classified += 1
            above = lines[n.lineno - 2]
            if not (TAG_RE.match(above) or NOT_RE.match(above)):
                fails.append("M1: %s line %d refuses but carries no '# guard:'/'# not-a-guard:' tag: %s"
                             % (fn, n.lineno, lines[n.lineno - 1].strip()))
            elif TAG_RE.match(above) and n.lineno - 1 not in [s[0] for v in sites.values() for s in v]:
                fails.append("M1: tag above line %d not registered" % n.lineno)

# --- table ------------------------------------------------------------------
rows = {}
for raw in os.environ["TABLE"].splitlines():
    if not raw.strip():
        continue
    parts = raw.split("\t")
    if len(parts) != 4:
        fails.append("table: malformed row %r" % raw)
        continue
    gid, blocks, cases, muts = parts
    if gid in rows:
        fails.append("M2: duplicate table row %s" % gid)
    rows[gid] = (blocks, [c for c in cases.split(",") if c], muts)

# --- M2 ---------------------------------------------------------------------
for gid in sorted(set(sites) - set(rows)):
    fails.append("M2: guard %s is tagged in the source but has no table row" % gid)
for gid in sorted(set(rows) - set(sites)):
    fails.append("M2: table row %s names no '# guard:' tag in the source (stale row)" % gid)

# --- M3 ---------------------------------------------------------------------
suite_text = ""
for path in sorted(glob.glob(os.path.join(here, "test_review_record_*.sh"))):
    if path == runner or path.endswith("test_review_record_guard_table.sh"):
        continue
    suite_text += open(path, encoding="utf-8").read() + "\n"
for gid, (_b, cases, _m) in sorted(rows.items()):
    if not cases:
        fails.append("M3: %s names no isolating case" % gid)
    for label in cases:
        pat = r'(?:ok|chk) "' + re.escape(label) + r'|expect ' + re.escape(label) + r' '
        if not re.search(pat, suite_text):
            fails.append("M3: %s case label %r is not the label of any check in the suites" % (gid, label))

# --- M4 ---------------------------------------------------------------------
rtext = open(runner, encoding="utf-8").read()
tsv = rtext[rtext.index("<<'EOF'\n") + 8: rtext.index("\nEOF\n", rtext.index("<<'EOF'\n"))]
muts = {}
for line in tsv.splitlines():
    mid, old, _new = line.split("\t")
    muts[mid] = ast.literal_eval(old)
equivalents = []
for gid, (_b, _c, mspec) in sorted(rows.items()):
    if mspec.startswith("EQUIVALENT("):
        if ": " not in mspec or len(mspec.split(": ", 1)[1]) < 20:
            fails.append("M4: %s EQUIVALENT claim carries no real reason" % gid)
        equivalents.append("%s %s" % (gid, mspec))
        continue
    ids = [x for x in mspec.split(",") if x]
    if not ids:
        fails.append("M4: %s names no mutation" % gid)
    for mid in ids:
        if mid not in muts:
            fails.append("M4: %s mutation %s is not in the runner TSV" % (gid, mid))
            continue
        old = muts[mid]
        if src.count(old) != 1:
            fails.append("M4: %s mutation %s old text occurs %d times (need exactly 1)" % (gid, mid, src.count(old)))
            continue
        start = src[:src.index(old)].count("\n") + 1
        end = start + old.count("\n")
        if not any(start <= e and end >= t - 2 for t, e in sites.get(gid, [])):
            fails.append("M4: %s mutation %s (lines %d-%d) does not land on the guard's lines %s"
                         % (gid, mid, start, end, sites.get(gid)))

print("guard sites tagged: %d ids / %d tag lines; refusing ifs classified: %d; table rows: %d"
      % (len(sites), sum(len(v) for v in sites.values()), classified, len(rows)))
for e in equivalents:
    print("EQUIVALENT (reported, not silent): " + e)
for f in fails:
    print("NOT ok " + f)
print("guard table check: %s" % ("FAILED (%d)" % len(fails) if fails else "complete and consistent"))
sys.exit(1 if fails else 0)
PY
}

FAIL=0
echo "== guard table meta-check against the REAL source, runner and suites =="
if check "$TOOL" "$RUNNER" "$TABLE"; then echo "ok GT-REAL: guard table complete and consistent"
else echo "NOT ok GT-REAL: guard table incomplete or inconsistent (see NOT ok lines)"; FAIL=1; fi

# Self-validation (11.4.107(10)): each golden-bad perturbation below must make
# the meta-check FAIL for the right reason -- a checker that cannot fail is a
# bluff gate. The real files are never modified (copies under a temp dir).
S=$(mktemp -d) || { echo "cannot create temp dir" >&2; exit 2; }
trap 'rm -rf "$S"' EXIT INT TERM
golden_bad() { # golden_bad NAME EXPECTED_SUBSTRING TOOL RUNNER TABLE
  local out
  local rc=0
  out=$(check "$3" "$4" "$5" 2>&1) || rc=$?
  if [ "$rc" -ne 0 ] && printf '%s\n' "$out" | grep -qF -- "$2"; then echo "ok $1: meta-check FAILS ($2)"
  else echo "NOT ok $1: meta-check did not fail with '$2':"; printf '%s\n' "$out" | tail -5; FAIL=1; fi
}
# GB1: a refusing `if` with its tag removed (a new untested guard).
python3 - "$TOOL" "$S/untagged.py" <<'PY'
import sys
s = open(sys.argv[1]).read()
tag = "\n    # guard: G-Q-PRODUCER-NAMED\n"
assert s.count(tag) == 1
open(sys.argv[2], "w").write(s.replace(tag, "\n", 1))
PY
golden_bad GB1-untagged-guard "carries no '# guard:'" "$S/untagged.py" "$RUNNER" "$TABLE"
# GB2: a tagged guard with no table row.
golden_bad GB2-row-missing "has no table row" "$TOOL" "$RUNNER" "$(printf '%s\n' "$TABLE" | grep -v '^G-Q-SLICES	')"
# GB3: a row whose case label is not a real check.
golden_bad GB3-fake-case "is not the label of any check" "$TOOL" "$RUNNER" \
  "$(printf '%s\n' "$TABLE" | sed 's/^\(G-Q-SLICES	[^	]*	\)I3b	/\1NO-SUCH-CASE	/')"
# GB4: a row whose mutation lands on ANOTHER guard's lines.
golden_bad GB4-misaimed-mutation "does not land on the guard's lines" "$TOOL" "$RUNNER" \
  "$(printf '%s\n' "$TABLE" | sed 's/	O13-slice-coverage$/	O4-precheck-all-pass/')"
# GB5: a row naming a mutation the runner does not have.
golden_bad GB5-unknown-mutation "is not in the runner TSV" "$TOOL" "$RUNNER" \
  "$(printf '%s\n' "$TABLE" | sed 's/	O13-slice-coverage$/	NO-SUCH-MUTATION/')"
# GB6: an EQUIVALENT claim with no reason.
golden_bad GB6-bare-equivalent "carries no real reason" "$TOOL" "$RUNNER" \
  "$(printf '%s\n' "$TABLE" | sed 's/	EQUIVALENT(R3-M12): .*$/	EQUIVALENT(R3-M12): x/')"
# GB7: a guarded function renamed away.
sed 's/def _ledger_authenticates(/def _ledger_ok(/; s/_ledger_authenticates(ctx/_ledger_ok(ctx/' "$TOOL" > "$S/renamed.py"
golden_bad GB7-renamed-function "no longer exists" "$S/renamed.py" "$RUNNER" "$TABLE"

echo ""
[ "$FAIL" -eq 0 ] && { echo "== guard table: ok =="; exit 0; }
echo "== guard table: FAILED =="; exit 1
