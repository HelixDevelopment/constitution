#!/usr/bin/env bash
# tests/workable_items/test_intake_lint.sh -- hermetic test of scripts/workable-items/intake_lint.py.
#
# Documentation (section 11.4.18): docs/guides/intake_lint_guide.md.
#
# WHAT  (1) golden-good and golden-bad fixture databases with the engine's four tables (items with
#       every engine column, obsolete_details, operator_block_details, item_history) and a fixture
#       repository with rendered Issues.md and Issues_Summary.md: at least one golden-bad per finding
#       code, every BODY-SYNC header key in both directions, every STATE-EVIDENCE branch, SECRET on every
#       surface kind (title, description, body_md, an items column, obsolete_details,
#       operator_block_details, item_history, a rendered document), EPHEMERAL and CONTROL-CHAR on several
#       surfaces, one positive and one negative control needle per SECRET pattern, the DUP-HEAD branches
#       (link both ways, a stale row, a closed head) and their false-positive guards; (2) the usage (2)
#       and BLIND (3) exits: a missing table, a BLOB, a non-text column, a crash, a rendered document
#       missing, unreadable or without the item; (3) the --embeddings TSV namespaces; (4) on scratch
#       COPIES of docs/workable_items.db (the real database is opened read-only and never written): the
#       reviewer data mutants of rounds 1 to 3 (M2..M11; D1..D8; DM1..DM16, DMC, DMN) and the replays of
#       findings I1, I2 and R2-1; (5) a refused cleanup makes the suite fail.
#       The round-3 reviewer's lint mutants LC1..LC11 are killed here: LC8 by the FX-150 range interior,
#       LC9 by the trailing-dot golden-good, LC10 by the heading-id case, LC11 by the "an ephemeral copy"
#       case, LC4 by the structured Investigation line, LC5..LC7 by the secret and tmp-path needles.
# ENV   INTAKE_LINT       path of the lint to test (default: the repository copy); the mutation
#                         suite points it at a mutated copy
#       INTAKE_LINT_EXTRA extra arguments for every lint call (the mutation suite passes
#                         --no-selfcheck so that these cases, not the built-in needles, must kill)
#       INTAKE_LINT_ROOT  repository root (default: two levels above this file); the mutation suite
#                         sets it when it runs a mutated copy of this file from a temp dir
#       INTAKE_LINT_FAILFAST=1  stop at the first failing case (the mutation suite: a kill is a kill)
#       INTAKE_LINT_SUITE_CLEANUP_ONLY=1  internal: run no case, only the cleanup (used by case (5))
# EXIT  0 all cases pass; 1 a case failed; 2 setup error, or the cleanup of the temp dir was refused.
# EVIDENCE CLASS  gate-logic only (section 11.4.289): it proves the lint's decisions on given text.
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 2
self=$here/$(basename "${BASH_SOURCE[0]}")
root=$(cd "${INTAKE_LINT_ROOT:-$here/../..}" && pwd) || exit 2
lint=${INTAKE_LINT:-$root/scripts/workable-items/intake_lint.py}
read -r -a extra <<<"${INTAKE_LINT_EXTRA:-}"
realdb=$root/docs/workable_items.db
[ -f "$lint" ] || { echo "setup: lint not found: $lint" >&2; exit 2; }
# shellcheck source=../../scripts/lib/safe_rm.sh
. "$root/scripts/lib/safe_rm.sh" || exit 2
tmp=$(mktemp -d) || exit 2
case "$tmp" in /tmp/*|"${TMPDIR:-/tmp}"/*) ;; *) echo "setup: unexpected mktemp root: $tmp" >&2; exit 2 ;; esac
# A refused cleanup is a failure of the run (round-2 review R2-10): the suite exits 2 and names the dir.
cleanup() {
  local st=$?
  if ! safe_rm_rf "${tmp:?}"; then
    echo "CLEANUP REFUSED: temp dir left behind: $tmp" >&2
    exit 2
  fi
  exit "$st"
}
trap cleanup EXIT
if [ "${INTAKE_LINT_SUITE_CLEANUP_ONLY:-}" = 1 ]; then echo "cleanup-only probe: $tmp"; exit 0; fi

pass=0 fail=0
ok() { pass=$((pass + 1)); echo "PASS $1"; }
bad() {
  fail=$((fail + 1)); echo "FAIL $1: $2"
  if [ "${INTAKE_LINT_FAILFAST:-}" = 1 ]; then echo "RESULT: pass=$pass fail=$fail (stopped at the first failure)"; exit 1; fi
}

# (0) round 8 (review N1 to N3): the shared-fixture oracle of the credential rules, run first because it
# is fast and drives the lint's own functions over every fixture row (the reviewer's 51 shapes, 52
# lookalikes and 6 backslash values, and the fixer's rows); its output carries labels only
shape_out=$tmp/shapes.txt
python3 -I "$root/tests/workable_items/test_secret_shapes.py" "$lint" >"$shape_out" 2>&1
shape_rc=$?
if [ "$shape_rc" = 0 ]; then
  ok "SECRET shape oracle: $(tail -n 1 "$shape_out")"
else
  bad "SECRET shape oracle" "rc=$shape_rc: $(grep -E '^(FAIL|BLIND|setup)' "$shape_out" | head -n 8 | tr '\n' '|')"
fi

# run_lint <out-file> <args...>  -> sets rc
run_lint() {
  local out=$1; shift
  python3 -I "$lint" "${extra[@]}" "$@" >"$out" 2>&1
  rc=$?
}

# expect <name> <want-rc> <grep-pattern-or-empty> <args...>
expect() {
  local name=$1 want=$2 pat=$3; shift 3
  run_lint "$tmp/out" "$@"
  if [ "$rc" != "$want" ]; then bad "$name" "rc=$rc want=$want: $(tr '\n' '|' <"$tmp/out" | cut -c1-300)"; return; fi
  if [ -n "$pat" ] && ! grep -Eq -- "$pat" "$tmp/out"; then bad "$name" "pattern /$pat/ not in: $(tr '\n' '|' <"$tmp/out" | cut -c1-300)"; return; fi
  ok "$name"
}

# expect_silent <name> <code> <args...>: rc 0 or 1, and no finding of <code>
expect_silent() {
  local name=$1 code=$2; shift 2
  run_lint "$tmp/out" "$@"
  if [ "$rc" -gt 1 ] || grep -q "^FINDING $code " "$tmp/out"; then bad "$name" "rc=$rc $(tr '\n' '|' <"$tmp/out" | cut -c1-300)"; return; fi
  ok "$name"
}

# ---- fixture database: the engine's four tables, every items column ----
# body_md is rendered here the way the engine renders it (heading, header block, description), by this
# suite's own code, so that a defect in the lint's checker cannot hide behind a shared renderer.
# Snippet names: rows (id -> column dict), od / obd (id -> row dict), hist (list of row dicts),
# body (id -> body_md override, str or bytes), G (the good description), SHA_E (sha256 of the empty
# evidence file), render(i[, row]), close_obsolete(i, reason, sup), reopen(i), drop (table names to
# drop), nohistid (True: item_history without its id column), extra (more item rows: a second location
# row of an id; its body_md is rendered from the row itself).
mkfixture() { # mkfixture <db> <python-mutation-snippet>
  python3 -I - "$1" "$2" <<'PY'
import hashlib, sqlite3, sys
db, snippet = sys.argv[1], sys.argv[2]
COLS = ["atm_id", "type", "status", "severity", "title", "description", "forensic_anchor", "closure_criteria",
        "composes_with", "destination", "logic_group", "created_by", "assigned_to", "current_location", "body_md",
        "representation", "closure_date", "round", "commit_ref", "parent_atm_id", "session_ref",
        "reproduction_state", "reproduction_surface", "reproduction_evidence", "reproduction_red_cmd",
        "reproduction_green_cmd", "reproduction_env", "reproduction_signature", "reproduction_blocker",
        "reproduction_updated_at", "reproduction_updated_by", "investigation_state", "investigation_root_cause",
        "investigation_evidence", "investigation_updated_at", "investigation_updated_by", "created_at", "last_modified"]
SHA_E = hashlib.sha256(b"").hexdigest()
EV = "docs/qa/fx_present/e.txt"
G = ("**What:** a fixture item.\n\n**Affected scope / file-scope manifest:**\nscripts/fixture_only_tool.sh\n\n"
     "**Reproduction / context:**\nnone\n\n**Acceptance criteria:**\nnone\n\n"
     "Parent / links: umbrella FX-001 (fixture umbrella)\n"
     "Duplicate check (section 11.4.214): DISTINCT\n"
     "Context: FX-900 of another tracker; evidence " + EV + "; bundle b.bundle (ephemeral: a scratch file)\n"
     "Foreign ids (another tracker): FX-900\n"
     "Origin: fixture batch")
def item(i, title, desc, **kw):
    r = {c: None for c in COLS}
    r.update(atm_id=i, title=title, description=desc, status="Queued", current_location="Issues", type="Task",
             representation="section", created_at="2026-11-13T00:00:00Z", last_modified="2026-11-13T00:00:00Z")
    r.update(kw)
    return r
rows = {
    "FX-001": item("FX-001", "Fixture umbrella", "umbrella of the fixture batch"),
    "FX-002": item("FX-002", "Fixture good item", G, severity="Low", created_by="Conductor",
                   reproduction_state="reproduced-host-fixture", reproduction_surface="host-only",
                   reproduction_evidence=EV, reproduction_red_cmd="bash scripts/fixture_only_tool.sh --probe",
                   reproduction_env="fixture host; evidence sha256 " + SHA_E,
                   reproduction_signature="exit 1 on the probe", reproduction_updated_at="2026-11-13T00:00:00Z",
                   reproduction_updated_by="Conductor", investigation_state="in-progress",
                   investigation_updated_at="2026-11-13T00:00:00Z", investigation_updated_by="Conductor"),
    "FX-003": item("FX-003", "Unrelated open item", "nothing shared here"),
}
od, obd, hist, body, drop, extra = {}, {}, [], {}, [], []
nohistid = [False]
SEP = " — "
CLOSING = ("Fixed", "Implemented", "Completed", "Obsolete")
def span(v):
    run = best = 0
    for ch in v:
        run = run + 1 if ch == "`" else 0
        best = max(best, run)
    f = "`" * (best + 1)
    return (f + " " + v + " " + f) if (v[:1] == "`" or v[-1:] == "`") else (f + v + f)
def det(pairs):
    return "".join(SEP + k + " " + (v if k in ("surface", "updated") else span(v)) for k, v in pairs if v)
def repro(r):
    st = r["reproduction_state"]
    if st in (None, "", "UNSET"):
        return None
    keys = [("surface", "reproduction_surface"), ("evidence", "reproduction_evidence"),
            ("red-command", "reproduction_red_cmd"), ("green-command", "reproduction_green_cmd"),
            ("env", "reproduction_env"), ("signature", "reproduction_signature"),
            ("blocker", "reproduction_blocker"), ("updated", "reproduction_updated_at"),
            ("by", "reproduction_updated_by")]
    pairs = [(k, r[c] or "") for k, c in keys]
    d = dict(pairs)
    good = (st in ("reproduced-live", "reproduced-host-fixture")
            and all(d[k] for k in ("surface", "evidence", "red-command", "env", "signature"))
            and not (st == "reproduced-host-fixture" and d["surface"] == "live-target")
            and not any(v.startswith("UNCONFIRMED") for v in d.values()))
    head = ("none" + SEP + "UNREPRODUCED") if st == "UNREPRODUCED" else (st + SEP + ("REPRODUCED" if good else "UNREPRODUCED"))
    return "**Reproduction:** " + head + det(pairs)
def inv(r):
    st = r["investigation_state"]
    if st in (None, "", "UNSET"):
        return None
    return "**Investigation:** " + st + det([("root-cause", r["investigation_root_cause"] or ""),
                                            ("evidence", r["investigation_evidence"] or ""),
                                            ("updated", r["investigation_updated_at"] or ""),
                                            ("by", r["investigation_updated_by"] or "")])
def render(i, r=None):
    r = r or rows[i]
    h = ["**Status:** " + r["status"], "**Type:** " + r["type"]]
    ev = [x["evidence_path"] for x in hist if x["atm_id"] == i and x["event_type"] in CLOSING and x.get("evidence_path")]
    if ev:
        h.append("**Evidence:** " + ev[-1])
    for key, c in (("Severity", "severity"), ("Created-By", "created_by"), ("Assigned-To", "assigned_to")):
        if r[c] and r[c].strip():
            h.append("**%s:** %s" % (key, r[c]))
    h += [x for x in (repro(r), inv(r)) if x]
    if str(r["status"]).startswith("Obsolete") and i in od:
        o = od[i]
        h.append("**Obsolete-Details:** Since: %s; Reason: %s; Superseding-item: %s; Triple-check evidence: %s"
                 % (o["since"], o["reason"], o["superseding_item"], o["triple_check_evidence"]))
    ro = [x for x in hist if x["atm_id"] == i and x["event_type"] == "Reopened"]
    if ro:
        x = ro[-1]
        h.append("**Reopened-Details:** By: %s On: %s Reason: %s Evidence: %s" % (x["by"], x["on_date"], x["reason"], x["evidence_path"]))
    if i in obd:
        h.append("**Operator-Block-Details:** WHAT: %s; WHY: %s" % (obd[i]["what"], obd[i]["why_exhausted_alternatives"]))
    return "## %s — %s\n\n%s\n\n%s\n\n" % (i, r["title"], "\n".join(h), r["description"])
def mkod(reason, sup, ev=EV):
    return dict(since="2026-11-13", reason=reason, superseding_item=sup, triple_check_evidence=ev)
def close_obsolete(i, reason, sup):
    rows[i]["status"], rows[i]["current_location"] = "Obsolete", "Fixed"
    od[i] = mkod(reason, sup)
    hist.append(dict(atm_id=i, event_type="Obsolete", by="AI", on_date="2026-11-13", reason=reason, evidence_path=EV))
def reopen(i):
    rows[i]["status"], rows[i]["current_location"] = "Reopened", "Issues"
    hist.append(dict(atm_id=i, event_type="Reopened", by="AI", on_date="2026-11-13", reason="design-reconsidered", evidence_path=EV))
exec(snippet, {"rows": rows, "od": od, "obd": obd, "hist": hist, "body": body, "G": G, "EV": EV, "SHA_E": SHA_E,
               "render": render, "item": item, "mkod": mkod, "close_obsolete": close_obsolete, "reopen": reopen,
               "drop": drop, "nohistid": nohistid, "extra": extra})
c = sqlite3.connect(db)
c.execute("create table items (%s, primary key (atm_id, current_location))" % ", ".join(x + " text" for x in COLS))
c.execute("create table obsolete_details (atm_id text primary key, since text, reason text, superseding_item text, triple_check_evidence text)")
c.execute("create table operator_block_details (atm_id text primary key, what text, why_exhausted_alternatives text, unblock_condition text, who text)")
if nohistid[0]:
    c.execute("create table item_history (atm_id text, event_type text, by text, on_date text, reason text, evidence_path text)")
else:
    c.execute("create table item_history (id integer primary key autoincrement, atm_id text, event_type text, by text, on_date text, reason text, evidence_path text)")
for i, r in rows.items():
    r = dict(r)
    r["body_md"] = body[i] if i in body else render(i)
    c.execute("insert into items (%s) values (%s)" % (",".join(COLS), ",".join("?" * len(COLS))), [r[x] for x in COLS])
for r in extra:
    r = dict(r)
    r["body_md"] = render(r["atm_id"], r)
    c.execute("insert into items (%s) values (%s)" % (",".join(COLS), ",".join("?" * len(COLS))), [r[x] for x in COLS])
for i, o in od.items():
    c.execute("insert into obsolete_details values (?,?,?,?,?)", (i, o["since"], o["reason"], o["superseding_item"], o["triple_check_evidence"]))
for i, o in obd.items():
    c.execute("insert into operator_block_details values (?,?,?,?,?)", (i, o["what"], o["why_exhausted_alternatives"], o["unblock_condition"], o["who"]))
for h in hist:
    if nohistid[0]:
        c.execute("insert into item_history values (?,?,?,?,?,?)", (h["atm_id"], h["event_type"], h["by"], h["on_date"], h["reason"], h["evidence_path"]))
    else:
        c.execute("insert into item_history (atm_id, event_type, by, on_date, reason, evidence_path) values (?,?,?,?,?,?)",
                  (h["atm_id"], h["event_type"], h["by"], h["on_date"], h["reason"], h["evidence_path"]))
for t in drop:
    c.execute("drop table " + t)
c.commit(); c.close()
PY
}
# the fixture repository: the evidence file (empty, so its sha256 is SHA_E), a decision record and the
# rendered documents (the default --rendered dir is <repo-root>/docs)
mkrendered() { # mkrendered <dir> [<extra line in the FX-002 section>] [<extra summary cell>] [<extra line in the FX-003 section>]
  mkdir -p "$1" || return 1
  printf '# Issues\n\n## FX-001 — Fixture umbrella\n\numbrella\n\n## FX-002 — Fixture good item\n\n**Status:** Queued\n%s\n\n## FX-003 — Unrelated open item\n\nnothing\n%s\n' \
    "${2:-}" "${4:-}" >"$1/Issues.md" || return 1
  printf '# Issues summary\n\n| id | type | status | note |\n|---|---|---|---|\n| FX-001 | Task | Queued | |\n| FX-002 | Task | Queued | %s |\n| FX-003 | Task | Queued | |\n' \
    "${3:-}" >"$1/Issues_Summary.md"
}
mkdir -p "$tmp/repo/docs/qa/fx_present" "$tmp/repo/docs/operator_decisions" && : >"$tmp/repo/docs/qa/fx_present/e.txt" \
  && : >"$tmp/repo/docs/operator_decisions/fx_decisions.md" && mkrendered "$tmp/repo/docs" || exit 2
F=(--origin "Origin: fixture batch" --prefix FX --require-dup-check --repo-root "$tmp/repo")
RES_OK='^RESULT: PASS selected=1 findings=0 prefix=FX rendered=Issues.md,Issues_Summary.md$'

mkfixture "$tmp/good.db" "pass" || exit 2
expect "golden-good fixture" 0 "$RES_OK" --db "$tmp/good.db" "${F[@]}"

# shared snippets
SAME3='rows["FX-002"]["description"] = G.replace(": DISTINCT", ": SAME-DEFECT of FX-003"); close_obsolete("FX-002", "duplicate-of", "FX-003"); '
UND='rows["FX-002"]["description"] = G.replace(": DISTINCT", ": UNDECIDED; candidate duplicates FX-001 and FX-003"); '
HB='body["FX-002"] = render("FX-002").replace('   # a header-block edit of FX-002's body: HB + '"old", "new")'
KEY='"AK" + "IA" + "QQQQRRRRSSSSTTTT"'      # an AWS-key-shaped canary built from fragments (fake)

# golden-bad, at least one per finding code: <name>|<python snippet>[@@<detail regex>]. The code is the
# part of the name before "/"; the finding line must match "^FINDING <code> FX-002 <detail regex>".
cases=(
  'XREF-DANGLING|rows["FX-002"]["description"] = G.replace("FX-001 (fixture umbrella)", "FX-099")@@FX-099$'
  'XREF-DANGLING/title|rows["FX-002"]["title"] = "Fixture good item, see FX-098"@@FX-098$'
  'XREF-DANGLING/foreign-declared-only|rows["FX-002"]["description"] = G.replace("Foreign ids (another tracker): FX-900", "Foreign ids (another tracker): FX-901")@@FX-900$'
  'XREF-DANGLING/range-endpoint|rows["FX-002"]["description"] = G.replace("Context: FX-900", "Context: FX-001..FX-004")@@FX-004$'
  'XREF-DANGLING/range-interior|rows["FX-005"] = item("FX-005", "Range end", "end"); rows["FX-002"]["description"] = G.replace("Context: FX-900", "Context: FX-001..FX-005")@@FX-004$'
  'XREF-DANGLING/range-interior-150|rows["FX-160"] = item("FX-160", "Range end", "end"); rows["FX-002"]["description"] = G.replace("Context: FX-900", "Context: FX-001..FX-160")@@FX-150$'
  'XREF-DANGLING/state-column|rows["FX-002"]["reproduction_signature"] = "exit 1 as in FX-077"@@FX-077$'
  'XREF-LABEL|rows["FX-002"]["description"] = G.replace("(fixture umbrella)", "(GitHub issues sync)")'
  'XREF-LABEL/one-shared-word|rows["FX-002"]["description"] = G.replace("(fixture umbrella)", "(umbrella of the github runners)")'
  'XREF-UNLABELLED|rows["FX-002"]["description"] = G.replace("umbrella FX-001 (fixture umbrella)", "related FX-003, not a parent")'
  'FOREIGN-STALE|rows["FX-002"]["description"] = G.replace("tracker): FX-900", "tracker): FX-900, FX-901")@@FX-901$'
  'STATE-PROSE|rows["FX-002"]["description"] = G + "\nReproduction: reproduced-live (written in prose)"@@prose says reproduced-live'
  'STATE-PROSE/unreproduced-family|rows["FX-002"]["description"] = G + "\nstate: UNREPRODUCED"@@prose says UNREPRODUCED'
  'STATE-PROSE/investigation-token|rows["FX-002"]["description"] = G + "\nthe cause is root-cause-unconfirmed so far"@@prose says root-cause-unconfirmed'
  'STATE-PROSE/investigation-label|rows["FX-002"]["description"] = G + "\nInvestigation: not-started"@@prose says Investigation: not-started'
  'STATE-PROSE/structured|rows["FX-002"]["description"] = G + "\n**Reproduction:** reproduced-live — REPRODUCED"@@structured line says reproduced-live'
  'STATE-PROSE/structured-investigation|rows["FX-002"]["description"] = G + "\n**Investigation:** root-cause-unconfirmed — by `x`"@@structured line says root-cause-unconfirmed'
  'STATE-EVIDENCE/no-sha|rows["FX-002"]["reproduction_env"] = "fixture host"@@reproduction_state reproduced-host-fixture carries no evidence sha256$'
  'STATE-EVIDENCE/no-path|rows["FX-002"]["reproduction_evidence"] = None@@reproduction_state reproduced-host-fixture without an evidence path$'
  'STATE-EVIDENCE/missing-file|rows["FX-002"]["reproduction_evidence"] = "docs/qa/fx_absent/e.txt"@@reproduction evidence docs/qa/fx_absent/e.txt does not exist$'
  'STATE-EVIDENCE/sha-mismatch|rows["FX-002"]["reproduction_env"] = "fixture host; evidence sha256 " + "ab" * 32@@reproduction evidence sha256 differs from the file docs/qa/fx_present/e.txt$'
  'STATE-EVIDENCE/not-reproducible|rows["FX-002"]["reproduction_state"] = "not-reproducible-with-evidence"; rows["FX-002"]["reproduction_env"] = "fixture host"@@reproduction_state not-reproducible-with-evidence carries no evidence sha256$'
  'STATE-EVIDENCE/blocker|rows["FX-002"]["reproduction_state"] = "blocked-no-device-with-recorded-blocker"@@reproduction_state blocked-no-device-with-recorded-blocker without a reproduction_blocker$'
  'STATE-EVIDENCE/investigation|rows["FX-002"]["investigation_state"] = "root-cause-found-with-evidence"; rows["FX-002"]["investigation_root_cause"] = "fixture cause"@@investigation_state root-cause-found-with-evidence without an evidence path$'
  'STATE-EVIDENCE/investigation-sha|rows["FX-002"]["investigation_state"] = "closed-no-defect"; rows["FX-002"]["investigation_evidence"] = EV; rows["FX-002"]["investigation_root_cause"] = "no defect; sha256 " + "cd" * 32@@investigation evidence sha256 differs from the file'
  'SECTIONS|rows["FX-002"]["description"] = G.replace("**Acceptance criteria:**", "Acceptance:")@@missing: Acceptance criteria$'
  'BODY-SYNC|body["FX-002"] = "a body that diverged"'
  'BODY-SYNC/empty|body["FX-002"] = ""@@body_md is empty$'
  'BODY-SYNC/description-missing|body["FX-002"] = render("FX-002").replace("Origin: fixture batch", "Origin: another batch")@@description is not contained in body_md$'
  'BODY-SYNC/extra-paragraph|body["FX-002"] = render("FX-002") + "Update: already fixed on main; no work owed.\n"@@body_md carries text after the description'
  'BODY-SYNC/text-before|'"$HB"'"**Type:** Task\n", "**Type:** Task\nNote: closed upstream.\n")@@body_md carries text before the description'
  'BODY-SYNC/prose-before-description|body["FX-002"] = render("FX-002").replace("\n\n" + G, "\n\nNote: closed upstream.\n\n" + G, 1)@@body_md carries text before the description'
  'BODY-SYNC/heading-title|body["FX-002"] = render("FX-002").replace("Fixture good item", "Another title", 1)@@body_md heading disagrees with the id or title column$'
  'BODY-SYNC/heading-id|body["FX-002"] = render("FX-002").replace("## FX-002 ", "## FX-003 ", 1)@@body_md heading disagrees with the id or title column$'
  'BODY-SYNC/status-value|'"$HB"'"**Status:** Queued", "**Status:** Done")@@body_md Status line differs'
  'BODY-SYNC/status-twice|'"$HB"'"**Status:** Queued\n", "**Status:** Queued\n**Status:** Fixed\n")@@body_md header key Status is written twice$'
  'BODY-SYNC/type|'"$HB"'"**Type:** Task", "**Type:** Bug")@@body_md Type line differs'
  'BODY-SYNC/severity|'"$HB"'"**Severity:** Low", "**Severity:** Critical")@@body_md Severity line differs'
  'BODY-SYNC/severity-missing|'"$HB"'"**Severity:** Low\n", "")@@body_md lacks the Severity line its source gives$'
  'BODY-SYNC/created-by|'"$HB"'"**Created-By:** Conductor", "**Created-By:** User")@@body_md Created-By line differs'
  'BODY-SYNC/assigned-to-extra|'"$HB"'"**Type:** Task\n", "**Type:** Task\n**Assigned-To:** someone\n")@@body_md has an Assigned-To line while its source gives none$'
  'BODY-SYNC/assigned-to-differs|rows["FX-002"]["assigned_to"] = "Conductor"; '"$HB"'"**Assigned-To:** Conductor", "**Assigned-To:** User")@@body_md Assigned-To line differs'
  'BODY-SYNC/reproduction-missing|body["FX-002"] = render("FX-002", dict(rows["FX-002"], reproduction_state=None))@@body_md lacks the Reproduction line its source gives$'
  'BODY-SYNC/reproduction-detail|body["FX-002"] = render("FX-002", dict(rows["FX-002"], reproduction_env="fixture host; evidence sha256 " + SHA_E + "; another note"))@@body_md Reproduction line differs'
  'BODY-SYNC/investigation-differs|'"$HB"'"**Investigation:** in-progress", "**Investigation:** root-cause-found-with-evidence")@@body_md Investigation line differs'
  'BODY-SYNC/investigation-extra|rows["FX-002"]["investigation_state"] = None; body["FX-002"] = render("FX-002", dict(rows["FX-002"], investigation_state="in-progress"))@@body_md has an Investigation line while its source gives none$'
  'BODY-SYNC/obsolete-missing|'"$SAME3"'body["FX-002"] = "\n".join(l for l in render("FX-002").split("\n") if not l.startswith("**Obsolete-Details:**"))@@body_md lacks the Obsolete-Details line its source gives$'
  'BODY-SYNC/obsolete-content|'"$SAME3"'body["FX-002"] = render("FX-002").replace("Superseding-item: FX-003", "Superseding-item: FX-001")@@body_md Obsolete-Details line differs from its source$'
  'BODY-SYNC/obsolete-on-open|'"$HB"'"**Type:** Task\n", "**Type:** Task\n**Obsolete-Details:** duplicate-of FX-001\n")@@body_md has an Obsolete-Details line while its source gives none$'
  'BODY-SYNC/evidence-not-closure|'"$HB"'"**Type:** Task\n", "**Type:** Task\n**Evidence:** docs/qa/fx_present/e.txt\n")@@body_md Evidence line names no closure evidence of the item$'
  'BODY-SYNC/reopened-without-row|'"$HB"'"**Type:** Task\n", "**Type:** Task\n**Reopened-Details:** By: AI On: 2026-11-13 Reason: x Evidence: e\n")@@body_md has a Reopened-Details line but the item has no Reopened history row$'
  'BODY-SYNC/reopened-differs|reopen("FX-002"); '"$HB"'"Reason: design-reconsidered", "Reason: invented")@@body_md Reopened-Details line differs from the last Reopened history row$'
  'BODY-SYNC/block-without-row|'"$HB"'"**Type:** Task\n", "**Type:** Task\n**Operator-Block-Details:** WHAT: x\n")@@body_md has an Operator-Block-Details line but the item has no operator_block_details row$'
  'BODY-SYNC/block-differs|rows["FX-002"]["status"] = "Operator-blocked"; obd["FX-002"] = dict(what="wait for the board", why_exhausted_alternatives="w", unblock_condition="u", who="operator"); '"$HB"'"WHAT: wait for the board", "WHAT: nothing")@@body_md Operator-Block-Details line differs from the item.s row$'
  'BODY-SYNC/reopens-count|'"$HB"'"**Type:** Task\n", "**Type:** Task\n**Reopens-count:** 2\n")@@body_md Reopens-count line differs from the number of Reopened history rows$'
  'BODY-SYNC/unknown-key|'"$HB"'"**Type:** Task\n", "**Type:** Task\n**Verdict:** fixed\n")@@body_md header key Verdict is not an engine key$'
  'BODY-SYNC/header-line-separator|'"$HB"'"**Type:** Task\n", "**Type:** Task note: closed upstream\n")@@body_md header line carries a line separator other than a newline'
  'SECRET|rows["FX-002"]["description"] = G + "\nkey " + '"$KEY"'@@aws-access-key-id on description,body_md$'
  'SECRET/title|rows["FX-002"]["title"] = "leak " + '"$KEY"'@@aws-access-key-id on title,body_md$'
  'SECRET/body-only|body["FX-002"] = render("FX-002").replace("**Type:** Task", "**Type:** Task " + '"$KEY"')@@aws-access-key-id on body_md$'
  'SECRET/items-column|rows["FX-002"]["closure_criteria"] = "key " + '"$KEY"'@@aws-access-key-id on items.closure_criteria$'
  'SECRET/state-column|rows["FX-002"]["reproduction_signature"] = "exit 1 " + '"$KEY"'@@aws-access-key-id on body_md,items.reproduction_signature$'
  'SECRET/obsolete-details|rows["FX-002"]["status"] = "Reopened"; od["FX-002"] = mkod("duplicate-of", "FX-003", "ev " + '"$KEY"')@@aws-access-key-id on obsolete_details.triple_check_evidence$'
  'SECRET/operator-block-details|rows["FX-002"]["status"] = "Operator-blocked"; obd["FX-002"] = dict(what="w", why_exhausted_alternatives="w", unblock_condition="u " + '"$KEY"', who="o")@@aws-access-key-id on operator_block_details.unblock_condition$'
  'SECRET/item-history|hist.append(dict(atm_id="FX-002", event_type="Updated", by="AI", on_date="2026-11-13", reason="r " + '"$KEY"', evidence_path=None))@@aws-access-key-id on item_history\[1\]\.reason$'
  'EPHEMERAL|rows["FX-002"]["description"] = G + "\nsee review_fixture_r1.md"@@bare-review-file: review_fixture_r1.md on description,body_md$'
  'EPHEMERAL/note-covers-own-line-only|rows["FX-002"]["description"] = G + "\nsecond bundle c.bundle with no note"@@bundle-file: c.bundle'
  'EPHEMERAL/word-without-note|rows["FX-002"]["description"] = G + "\nan ephemeral copy at /tmp/fx/x"@@tmp-path: /tmp/fx/x on'
  'EPHEMERAL/mktemp-default|rows["FX-002"]["description"] = G + "\nlog at /tmp/tmp." + "k3Jx9QvT2a" + "/out.txt"@@mktemp-default: tmp.k3Jx9QvT2a'
  'EPHEMERAL/mktemp-default-bare|rows["FX-002"]["description"] = G + "\nwork dir tmp." + "k3Jx9QvT2a" + " kept"@@mktemp-default'
  'EPHEMERAL/mktemp-default-lowercase|rows["FX-002"]["description"] = G + "\nwork dir tmp." + "qwertyuiop" + " kept"@@mktemp-default'
  'EPHEMERAL/lowercase-dir|rows["FX-002"]["description"] = G + "\nsee trackintake." + "zobh" + "/c"@@mktemp-dir: trackintake.zobh'
  'EPHEMERAL/four-char-mixed|rows["FX-002"]["description"] = G + "\nsee review_dir." + "Ab3d" + " for it"@@mktemp-dir: review_dir.Ab3d'
  'EPHEMERAL/var-tmp|rows["FX-002"]["description"] = G + "\nwritten to /var/tmp/" + "fx_out.txt"@@tmp-path: /var/tmp/fx_out.txt on description,body_md$'
  'EPHEMERAL/scratchpad|rows["FX-002"]["description"] = G + "\nfrom the session scratch" + "pad"@@scratchpad'
  'EPHEMERAL/home-path|rows["FX-002"]["description"] = G + "\nfile /ho" + "me/fixtureuser/x.txt"@@home-path: /home/fixtureuser/'
  'EPHEMERAL/home-dotdir|rows["FX-002"]["description"] = G + "\nfile ~/.fixture" + "tool/x.txt"@@home-path: ~/.fixturetool/'
  'EPHEMERAL/session-store|rows["FX-002"]["description"] = G + "\nfile .claude-fx/" + "projects/abc/x.jsonl"@@session-store: .claude-fx/projects/'
  'EPHEMERAL/state-column|rows["FX-002"]["reproduction_red_cmd"] = "bash /tmp/" + "fx/x.sh"@@tmp-path: /tmp/fx/x.sh on body_md,items.reproduction_red_cmd$'
  'EPHEMERAL/item-history|hist.append(dict(atm_id="FX-002", event_type="Updated", by="AI", on_date="2026-11-13", reason="see /tmp/" + "fx/h", evidence_path=None))@@tmp-path: /tmp/fx/h on item_history\[1\]\.reason$'
  'CONTROL-CHAR/nul|rows["FX-002"]["description"] = G + "\nnul\x00here"@@U\+0000 on description,body_md$'
  'CONTROL-CHAR/u2028-description|rows["FX-002"]["description"] = G.replace("\n**Reproduction / context:**", " **Reproduction / context:**")@@U\+2028 on description,body_md$'
  'CONTROL-CHAR/u2029-title|rows["FX-002"]["title"] = "Fixture good item second line"@@U\+2029 on title,body_md$'
  'CONTROL-CHAR/c1|rows["FX-002"]["description"] = G + "\nnext\x85line"@@U\+0085 on description,body_md$'
  'CONTROL-CHAR/del|rows["FX-002"]["description"] = G + "\nrub\x7fout"@@U\+007F on description,body_md$'
  'CONTROL-CHAR/title-tab|rows["FX-002"]["title"] = "Fixture\tgood item"@@newline or tab in the title on title$'
  'CONTROL-CHAR/obsolete-details|rows["FX-002"]["status"] = "Reopened"; od["FX-002"] = mkod("duplicate-of", "FX-003", "ev\x07bell")@@U\+0007 on obsolete_details.triple_check_evidence$'
  'CONTROL-CHAR/bidi-override|rows["FX-002"]["description"] = G + "\nshown \u202e reversed"@@U\+202E on description,body_md$'
  'CONTROL-CHAR/bidi-isolate|rows["FX-002"]["description"] = G + "\nisolate \u2066x\u2069 here"@@U\+2066 on description,body_md$'
  'CONTROL-CHAR/bidi-title|rows["FX-002"]["title"] = "Fixture \u202agood item"@@U\+202A on title,body_md$'
  'CONTROL-CHAR/bidi-state-column|rows["FX-002"]["reproduction_signature"] = "exit 1 \u202e"@@U\+202E on body_md,items.reproduction_signature$'
  'CONTROL-CHAR/bom|rows["FX-002"]["description"] = G + "\nmark\ufeffhere"@@U\+FEFF on description,body_md$'
  'CONTROL-CHAR/soft-hyphen|rows["FX-002"]["description"] = G + "\nsoft\u00adhyphen"@@U\+00AD on description,body_md$'
  'CONTROL-CHAR/zero-width-space|rows["FX-002"]["description"] = G + "\nzero\u200bwidth"@@U\+200B on description,body_md$'
  'CONTROL-CHAR/tag-character|rows["FX-002"]["description"] = G + "\ntag\U000e0041here"@@U\+E0041 on description,body_md$'
  'CONTROL-CHAR/earliest-reported|rows["FX-002"]["description"] = G + "\nfirst\u200b then\x07"@@U\+200B on description,body_md$'
  'XREF-DANGLING/non-ascii-digits|rows["FX-002"]["description"] = G + "\nsee FX-\u0663"@@FX-\S+ \(non-ASCII digits\)$'
  'EPHEMERAL/second-location-row|extra.append(dict(rows["FX-002"], current_location="Fixed")); rows["FX-002"]["description"] = G + "\nsee /tmp/" + "fx/lv6"@@tmp-path: /tmp/fx/lv6 on description,body_md \[Issues row\]$'
  'SHARED-PATH|rows["FX-003"]["description"] = "this open item also edits scripts/fixture_only_tool.sh"@@fixture_only_tool.sh also named by open FX-003$'
  'DUP-CHECK|rows["FX-002"]["description"] = G.replace(": DISTINCT", ": PROBABLY")'
  'DUP-CHECK/missing|rows["FX-002"]["description"] = G.replace("Duplicate check (section 11.4.214): DISTINCT\n", "")'
  'DUP-CHECK/same-defect-no-id|rows["FX-002"]["description"] = G.replace(": DISTINCT", ": SAME-DEFECT (see above)"); close_obsolete("FX-002", "duplicate-of", "FX-003")@@SAME-DEFECT names no id'
  'DUP-SAME-OPEN|rows["FX-002"]["description"] = G.replace(": DISTINCT", ": SAME-DEFECT of FX-003")'
  'DUP-SAME-OPEN/wrong-head|rows["FX-002"]["description"] = G.replace(": DISTINCT", ": SAME-DEFECT of FX-003"); close_obsolete("FX-002", "duplicate-of", "FX-001")'
  'DUP-SAME-OPEN/head-is-first-id|rows["FX-002"]["description"] = G.replace(": DISTINCT", ": SAME-DEFECT of FX-003 (see also FX-001)"); close_obsolete("FX-002", "duplicate-of", "FX-001")'
  'DUP-SAME-OPEN/dangling-superseding|rows["FX-002"]["description"] = G.replace(": DISTINCT", ": SAME-DEFECT of FX-003"); close_obsolete("FX-002", "duplicate-of", "FX-999")'
  'DUP-HEAD/target-obsolete|'"$SAME3"'close_obsolete("FX-003", "duplicate-of", "FX-001")@@FX-003 is not an open head'
  'DUP-HEAD/other-names-head|'"$SAME3"'rows["FX-001"]["description"] = "umbrella of the fixture batch. Candidate duplicate: FX-003 (unrelated open item); merge UNDECIDED."@@more than one head .*: FX-001 names FX-003 as a duplicate$'
  'DUP-HEAD/other-dup-line|'"$SAME3"'rows["FX-001"]["description"] = "umbrella of the fixture batch\nDuplicate check (section 11.4.214): undecided; candidate FX-003"@@more than one head \(section 11\.4\.214\(0\)\): FX-001 names FX-003 as a duplicate$'
  'DUP-HEAD/reverse|'"$SAME3"'rows["FX-003"]["description"] = "nothing shared here; FX-001 may be a second head of this defect"@@more than one head \(section 11\.4\.214\(0\)\): FX-003 names FX-001 as a duplicate$'
  'DUP-HEAD/stale-row|'"$SAME3"'od["FX-001"] = mkod("duplicate-of", "FX-003"); rows["FX-001"]["status"] = "Reopened"@@more than one head \(section 11\.4\.214\(0\)\): FX-001 is open with an obsolete_details row duplicate-of FX-003$'
  'DUP-UNDECIDED|rows["FX-002"]["description"] = G.replace(": DISTINCT", ": UNDECIDED")@@UNDECIDED names no candidate id$'
  'DUP-UNDECIDED/closed|'"$UND"'close_obsolete("FX-002", "not-reproducible", "none")@@UNDECIDED but the item is closed'
  'DUP-STATUS|'"$UND"'close_obsolete("FX-002", "duplicate-of", "FX-003")'
  'OBSOLETE-STALE|rows["FX-002"]["status"] = "Reopened"; od["FX-002"] = mkod("duplicate-of", "FX-003")'
  'OBSOLETE-STALE/note-names-closed-item|rows["FX-002"]["status"] = "Reopened"; od["FX-002"] = mkod("duplicate-of", "FX-003"); rows["FX-003"]["status"] = "Done"; rows["FX-003"]["current_location"] = "Fixed"; rows["FX-002"]["description"] = G + "\nStale obsolete_details row (engine gap FX-003): kept"'
  'PATH-MISSING|rows["FX-002"]["description"] = G.replace("fx_present", "fx_absent")@@docs/qa/fx_absent/e.txt$'
  'PATH-MISSING/decisions|rows["FX-002"]["description"] = G.replace("docs/qa/fx_present/e.txt", "docs/operator_decisions/fx_absent.md")@@docs/operator_decisions/fx_absent.md$'
)
n=0
for c in "${cases[@]}"; do
  n=$((n + 1)); detail=""
  case "$c" in *@@*) detail=${c##*@@}; c=${c%@@*} ;; esac
  name=${c%%|*}; snip=${c#*|}; code=${name%%/*}
  mkfixture "$tmp/bad$n.db" "$snip" || { bad "golden-bad $name" "fixture build failed"; continue; }
  expect "golden-bad $name" 1 "^FINDING $code FX-002 $detail" --db "$tmp/bad$n.db" "${F[@]}"
done

# one positive and one negative control needle per SECRET pattern (section 11.4.201(7)(b), 11.4.273(f));
# the strings are assembled from fragments, so this file carries no credential-shaped literal
secrets=(
  'aws-access-key-id|"AK" + "IA" + "Q" * 16|"AK" + "IA" + "Q" * 15'
  'aws-secret-assign|"aws_secret_" + "access_key = " + "a" * 40|"aws_secret_" + "access_key = " + "a" * 7'
  'github-token|"gh" + "p_" + "a" * 30|"gh" + "p_" + "a" * 29'
  'github-fine-grained-pat|"github" + "_pat_" + "a" * 30|"github" + "_pat_" + "a" * 29'
  'gitlab-pat|"gl" + "pat-" + "a" * 20|"gl" + "pat-" + "a" * 19'
  'gitlab-other-token|"gl" + "dt-" + "a" * 20|"gl" + "dt-" + "a" * 19'
  'gcp-api-key|"AI" + "za" + "a" * 35|"AI" + "za" + "a" * 34'
  'private-key-block|"-----BEGIN " + "OPENSSH PRIVATE" + " KEY-----"|"-----BEGIN " + "CERTIFICATE" + "-----"'
  'huggingface-token|"hf" + "_" + "a" * 30|"hf" + "_" + "a" * 29'
  'jwt|"ey" + "J" + "b" * 8 + ".ey" + "J" + "c" * 8 + ".d"|"ey" + "J" + "b" * 7 + ".ey" + "J" + "c" * 7 + ".d"'
  'slack-token|"xo" + "xp-" + "1" * 10|"xo" + "xp-" + "1" * 9'
  'openai-anthropic-key|"s" + "k-ant-" + "a" * 32|"s" + "k-" + "a" * 31'
  'url-userinfo-password|"git+ssh://bob:" + "w" + "@host"|"git+ssh://bob:" + "$" + "{PW}@host"'
  'bearer-token|"Authorization: " + "Bearer " + "a" * 20|"Authorization: " + "Bearer " + "a" * 19'
  'password-assign|"api_" + "key: \"" + "Zq7Zq7Zq" + "\""|"api_" + "key: \"" + "Zq7Zq7Z" + "\""'
  'stripe-key|"r" + "k_" + "test_" + "a" * 20|"r" + "k_" + "test_" + "a" * 19'
  'npm-token|"np" + "m_" + "a" * 36|"np" + "m_" + "a" * 35'
  'telegram-bot-token|"12345678" + ":AA" + "a" * 33|"12345678" + ":AA" + "a" * 32'
  'password-assign-unquoted|"DB_PASS" + "WORD=" + "Zq7Zq7Zq"|"DB_PASS" + "WORD=" + "Zq7Zq7Z"'
  'password-colon-unquoted|"pass" + "word: " + "Zq7Zq7Zq"|"pass" + "word: " + "Zq7Zq7Z"'
  'secret-colon-unquoted|"tok" + "en: " + "Zq7Zq7Zq"|"tok" + "en: " + "Zqzqzqzq"'
  'basic-auth|"Authorization: " + "Basic " + "a" * 8|"Authorization: " + "Basic " + "a" * 7'
  'password-assign-spaced|"pass" + "word = \"" + "ab cd ef" + "\""|"pass" + "word = \"" + "ab cd e" + "\""'
  'short-key-assign|"DB_PA" + "SS=" + "Zq7Zq7Zq"|"DB_PA" + "SS=" + "Zq7Zq7Z"'
  'password-flag-space|"--pass" + "word " + "Zq7Zq7Zq"|"--pass" + "word " + "Zq7Zq7Z"'
  'password-space|"DB_PASS" + "WORD " + "Zq7Zq7Zq"|"DB_PASS" + "WORD " + "Zq7Zq7Z"'
  'password-netrc|"login u pass" + "word " + "abcdefgh"|"login u pass" + "word " + "abcdefg"'
  'xml-credential-element|"<pass" + "word>" + "Zq7Zq7Zq" + "</pass" + "word>"|"<pass" + "word>" + "Zq7Zq7Z" + "</pass" + "word>"'
  'argument-pair|"define(" + chr(39) + "DB_PASS" + "WORD" + chr(39) + ", " + chr(39) + "Zq7Zq7Zq" + chr(39) + ")"|"define(" + chr(39) + "DB_PASS" + "WORD" + chr(39) + ", " + chr(39) + "Zq7Zq7Z" + chr(39) + ")"'
  'setter-call|"ds.setPass" + "word(\"" + "Zq7Zq7Zq" + "\")"|"ds.setPass" + "word(\"" + "Zq7Zq7Z" + "\")"'
  'short-flag-value|"mysql -uroot -p" + "Zq7Zq7Zq" + " db"|"mysql -uroot -p" + "Zq7Zq7Z" + " db"'
  'xml-attribute-pair|"<add key=\"Pass" + "word\" value=\"" + "Zq7Zq7Zq" + "\"/>"|"<add key=\"Pass" + "word\" value=\"" + "Zq7Zq7Z" + "\"/>"'
  'yaml-block-scalar|"pass" + "word: " + chr(124) + "\n  " + "Zq7Zq7Zq"|"pass" + "word: " + chr(124) + "\n  " + "Zq7Zq7Z"'
  'pgpass-line|"\nh:5432:db:u:" + "Zq7Zq7Zq" + "\n"|"\nh:5432:db:u:" + "Zq7Zq7Z" + "\n"'
)
for s in "${secrets[@]}"; do
  pname=${s%%|*}; rest=${s#*|}; pos=${rest%%|*}; neg=${rest#*|}
  n=$((n + 1))
  mkfixture "$tmp/sp$n.db" "rows[\"FX-002\"][\"description\"] = G + \"\\nvalue \" + ($pos) + \" end\"" || { bad "SECRET positive $pname" "fixture build failed"; continue; }
  expect "SECRET positive needle $pname" 1 "^FINDING SECRET FX-002 $pname on description,body_md\$" --db "$tmp/sp$n.db" "${F[@]}"
  mkfixture "$tmp/sn$n.db" "rows[\"FX-002\"][\"description\"] = G + \"\\nvalue \" + ($neg) + \" end\"" || { bad "SECRET negative $pname" "fixture build failed"; continue; }
  expect_silent "SECRET negative needle $pname" SECRET --db "$tmp/sn$n.db" "${F[@]}"
done
# round 6 (R5-3) and round 7 (F1): the keyed-credential shape class, one fabricated positive per member (key name x
# key quoting x separator x value quoting, headers, URL query and user-info); the expected pattern is named
shapes=(
  'json-quoted-key|password-assign|"{\"pass" + "word\": \"" + "Zq7Zq7Zq" + "\"}"'
  'python-dict|password-assign|"{" + chr(39) + "client_" + "secret" + chr(39) + ": " + chr(39) + "Zq7Zq7Zq" + chr(39) + "}"'
  'yaml-unquoted-password|password-colon-unquoted|"pass" + "word: " + "hunterhunter"'
  'yaml-unquoted-api-key|password-colon-unquoted|"api_" + "key: " + "Zq7Zq7Zq"'
  'yaml-quoted-key|password-colon-unquoted|"\"api" + "key\": " + "Zq7Zq7Zq"'
  'x-api-key-header|password-colon-unquoted|"X-Api" + "-Key: " + "Zq7Zq7Zq"'
  'x-auth-token-header|password-colon-unquoted|"X-Auth" + "-Token: " + "Zq7Zq7Zq"'
  'access-key-colon|password-colon-unquoted|"access_" + "key: " + "Zq7Zq7Zq"'
  'private-key-colon|password-colon-unquoted|"private" + "-key: " + "Zq7Zq7Zq"'
  'passphrase-walrus|password-assign-unquoted|"pass" + "phrase := " + "Zq7Zq7Zq"'
  'apikey-fat-arrow|password-assign|"api" + "key => " + chr(39) + "Zq7Zq7Zq" + chr(39)'
  'refresh-token-env|password-assign-unquoted|"REFRESH_" + "TOKEN=" + "Zq7Zq7Zq"'
  'url-query-token|password-assign-unquoted|"https://h/x?access_" + "token=" + "Zq7Zq7Zq" + "&y=1"'
  'url-short-password|url-userinfo-password|"https://u:" + "pw@h/r"'
  'authorization-token|bearer-token|"Authorization: " + "Token " + "a" * 20'
  'secret-key-colon|password-colon-unquoted|"SECRET" + "_KEY: " + "Zq7Zq7Zq"'
  'pg-joined-prefix|password-assign-unquoted|"PG" + "PASS" + "WORD=" + "Zq7Zq7Zq"'
  'export-joined-quoted|password-assign|"export PG" + "PASS" + "WORD=" + chr(39) + "Zq7Zq7Zq" + chr(39)'
  'mysql-pwd|short-key-assign|"MYSQL_" + "PWD=" + "Zq7Zq7Zq"'
  'db-pass|short-key-assign|"DB_" + "PASS=" + "Zq7Zq7Zq"'
  'redis-auth|short-key-assign|"REDIS_" + "AUTH=" + "Zq7Zq7Zq"'
  'docker-auth-json|short-key-assign|"{\"au" + "th\": \"" + "Zq7Zq7Zq" + "\"}"'
  'cli-flag-space|password-flag-space|"mysql --pass" + "word " + "corrhorsebat" + " -h db"'
  'cli-flag-token|password-flag-space|"tool --tok" + "en " + "Zq7Zq7Zq"'
  'fish-set-space|password-space|"set -x DB_PASS" + "WORD " + "Zq7Zq7Zq"'
  'netrc-letters|password-netrc|"machine h1 login u1 pass" + "word " + "corrhorsebat"'
  'xml-element|xml-credential-element|"<pass" + "word>" + "corrhorsebat" + "</pass" + "word>"'
  'xml-attr-generic|xml-credential-element|"<db_tok" + "en type=\"x\">" + "Zq7Zq7Zq" + "</db_tok" + "en>"'
  'xml-short|xml-credential-element|"<pw" + "d>" + "Zq7Zq7Zq" + "</pw" + "d>"'
  'quoted-with-space|password-assign-spaced|"pass" + "word = \"" + "correct horse 7bat" + "\""'
  'url-slash-password|url-userinfo-password|"https://u1:" + "ab/" + "Zq7Zq7Zq" + "@h/x"'
  'url-empty-user|url-userinfo-password|"redis://" + ":" + "Zq7Zq7Zq" + "@h:6379/0"'
  'fullwidth-colon|password-colon-unquoted|"pass" + "word\uff1a" + "Zq7Zq7Zq"'
  'fullwidth-letters|password-assign-unquoted|"\uff30\uff21\uff33\uff33" + "WORD=" + "Zq7Zq7Zq"'
  'backtick-value|password-assign|"pass" + "word = `" + "Zq7Zq7Zq" + "`"'
  'escaped-json|password-assign|"{\\\"pass" + "word\\\": \\\"" + "Zq7Zq7Zq" + "\\\"}"'
  'api-key-dot|password-assign-unquoted|"api" + ".key=" + "Zq7Zq7Zq"'
  'oauth-token|password-colon-unquoted|"oauth_" + "token: " + "corrhorsebat"'
  'credentials-key|password-colon-unquoted|"credent" + "ials: " + "corrhorsebat"'
)
for s in "${shapes[@]}"; do
  sname=${s%%|*}; rest=${s#*|}; pname=${rest%%|*}; pos=${rest#*|}
  n=$((n + 1))
  mkfixture "$tmp/sh$n.db" "rows[\"FX-002\"][\"description\"] = G + \"\\nvalue \" + ($pos) + \" end\"" || { bad "SECRET shape $sname" "fixture build failed"; continue; }
  expect "SECRET shape $sname" 1 "^FINDING SECRET FX-002 $pname on description,body_md\$" --db "$tmp/sh$n.db" "${F[@]}"
done
# and the negatives of that class: prose, references, masks and a key that is not a credential key; round 7
# (F1): words that end in a short key, a test-report label, a placeholder, a port, the halves of "=>"
nshapes=(
  'prose-token|"Tok" + "en: obtained from the host at run time"'
  'prose-password|"Pass" + "word: none"'
  'reference-env|"pass" + "word: $" + "{DB_PASSWORD}"'
  'reference-angle|"api_" + "key: <" + "your-key-here>"'
  'mask-stars|"pass" + "word: " + "*" * 12'
  'mask-x|"\"api_" + "key\": \"" + "x" * 12 + "\""'
  'not-a-key|"api_" + "key_file: /etc/app/k.pem"'
  'passwordless|"pass" + "wordless: enabled_for_all"'
  'url-masked-userinfo|"https://u:" + "****@h/r"'
  'bypass-word|"by" + "pass=" + "Zq7Zq7Zq"'
  'oauth-word|"o" + "auth=" + "Zq7Zq7Zq"'
  'pass-test-label|"PA" + "SS: case_one_" + "a1b2"'
  'auth-letters|"au" + "th=" + "requiredx"'
  'pwd-path|"pw" + "d=/srv/" + "u1/app"'
  'flag-placeholder|"mysql --pass" + "word " + "PASS" + "WORD_X"'
  'fat-arrow-short|"pass" + "word=>" + "Zq7Zq7Z"'
  'fat-arrow-reference|"pass" + "word => $" + "{DB_PW}"'
  'url-port-path|"https://" + "h:8080/" + "a/@b"'
  'xml-reference|"<pass" + "word>$" + "{DB_PW}</pass" + "word>"'
  'space-letters|"the pass" + "word manager stores it"'
  'token-space-generic|"tok" + "en " + "Zq7Zq7Zq"'
)
for s in "${nshapes[@]}"; do
  sname=${s%%|*}; neg=${s#*|}
  n=$((n + 1))
  mkfixture "$tmp/nsh$n.db" "rows[\"FX-002\"][\"description\"] = G + \"\\nvalue \" + ($neg) + \" end\"" || { bad "SECRET non-shape $sname" "fixture build failed"; continue; }
  expect_silent "SECRET non-shape $sname" SECRET --db "$tmp/nsh$n.db" "${F[@]}"
done

# golden-good variants that must stay silent (false-positive guards, section 11.4.201(1))
goods=(
  'shared path named by the Duplicate check line|rows["FX-003"]["description"] = "this open item also edits scripts/fixture_only_tool.sh"; rows["FX-002"]["description"] = G.replace(": DISTINCT", ": DISTINCT-but-similar of FX-003")'
  'shared path named by a closed item only|rows["FX-003"]["description"] = "edits scripts/fixture_only_tool.sh"; rows["FX-003"]["current_location"] = "Fixed"; rows["FX-003"]["status"] = "Done"'
  'SAME-DEFECT closed Obsolete duplicate-of the named open head|'"$SAME3"
  'SAME-DEFECT head whose candidate is closed|'"$SAME3"'rows["FX-001"]["description"] = "umbrella. Candidate duplicate: FX-003 (unrelated open item); merge UNDECIDED."; rows["FX-001"]["status"] = "Done"; rows["FX-001"]["current_location"] = "Fixed"'
  'SAME-DEFECT head named by another item without a duplicate word|'"$SAME3"'rows["FX-001"]["description"] = "umbrella; see FX-003 for the unrelated part"'
  'SAME-DEFECT head named by a DISTINCT Duplicate check line|'"$SAME3"'rows["FX-001"]["description"] = "umbrella\nDuplicate check (section 11.4.214): DISTINCT (FX-003 is a different defect)"'
  'SAME-DEFECT head with a noted stale row on another item|'"$SAME3"'od["FX-001"] = mkod("duplicate-of", "FX-003"); rows["FX-001"]["status"] = "Reopened"; rows["FX-001"]["description"] = "umbrella\nStale obsolete_details row (engine gap FX-003): kept by the engine"'
  'UNDECIDED with open candidates on an open item|'"$UND"
  'stale obsolete_details row noted with an open engine item|close_obsolete("FX-002", "duplicate-of", "FX-003"); reopen("FX-002"); rows["FX-002"]["description"] = G + "\nStale obsolete_details row (engine gap FX-003): kept by the engine"'
  'structured reproduction line agrees with the column|rows["FX-002"]["reproduction_state"] = "UNREPRODUCED"; rows["FX-002"]["description"] = G + "\n**Reproduction:** none — UNREPRODUCED"'
  'structured investigation line agrees with the column|rows["FX-002"]["description"] = G + "\n**Investigation:** in-progress — by `Conductor`"'
  'investigation with its evidence and sha256|rows["FX-002"]["investigation_state"] = "root-cause-found-with-evidence"; rows["FX-002"]["investigation_root_cause"] = "fixture cause; sha256 " + SHA_E; rows["FX-002"]["investigation_evidence"] = EV'
  'blocked state with its blocker|rows["FX-002"]["reproduction_state"] = "blocked-no-device-with-recorded-blocker"; rows["FX-002"]["reproduction_blocker"] = "no board attached"'
  'not-reproducible with evidence and sha256|rows["FX-002"]["reproduction_state"] = "not-reproducible-with-evidence"'
  'operator-blocked item with its block row|rows["FX-002"]["status"] = "Operator-blocked"; obd["FX-002"] = dict(what="wait for the board", why_exhausted_alternatives="w", unblock_condition="u", who="operator")'
  'assigned item|rows["FX-002"]["assigned_to"] = "Conductor"'
  'existing operator_decisions path|rows["FX-002"]["description"] = G.replace("docs/qa/fx_present/e.txt", "docs/operator_decisions/fx_decisions.md")'
  'existing path followed by a sentence dot|rows["FX-002"]["description"] = G.replace("evidence docs/qa/fx_present/e.txt;", "evidence docs/qa/fx_present/e.txt. Also (docs/qa/fx_present/e.txt), docs/qa/fx_present/e.txt:")'
  'declared foreign range|rows["FX-002"]["description"] = G.replace("FX-900 of another", "FX-900..FX-903 of another").replace("tracker): FX-900", "tracker): FX-900..FX-903")'
  'range whose interior exists|rows["FX-002"]["description"] = G.replace("Context: FX-900", "Context: the fixture umbrella to the unrelated open item, FX-001..FX-003, FX-900")'
  'label whose extra words are stopwords|rows["FX-002"]["description"] = G.replace("(fixture umbrella)", "(the fixture umbrella, the parent of this one)")'
  'unlabelled id in a clause that shares a title word|rows["FX-002"]["description"] = G.replace("umbrella FX-001 (fixture umbrella)", "see FX-003 for the unrelated part")'
  'mktemp template string|rows["FX-002"]["description"] = G + "\nthe mktemp template tmp." + "X" * 10 + " is named here"'
  'ephemeral note in parentheses exempts its line|rows["FX-002"]["description"] = G + "\na copy at /tmp/fx/x (ephemeral: removed after the run)"'
  'the words home and tmp in prose|rows["FX-002"]["description"] = G + "\nthe home page and the tmp folder are named in prose only"'
  'a password assignment from a variable|rows["FX-002"]["description"] = G + "\nset DB_PASS" + "WORD=$DB_PASS" + "WORD in the env file"'
  'a password assignment from a placeholder|rows["FX-002"]["description"] = G + "\nset DB_PASS" + "WORD=<from the vault> and API_" + "KEY={value}"'
  'a no-break space, an en dash and an em dash are not control characters|rows["FX-002"]["description"] = G + "\na\u00a0b \u2013 c \u2014 d"'
  'a second location row that is clean|extra.append(dict(rows["FX-002"], current_location="Fixed"))'
)
for c in "${goods[@]}"; do
  n=$((n + 1)); name=${c%%|*}; snip=${c#*|}
  mkfixture "$tmp/good$n.db" "$snip" || { bad "golden-good $name" "fixture build failed"; continue; }
  expect "golden-good $name" 0 '^RESULT: PASS ' --db "$tmp/good$n.db" "${F[@]}"
done

# ---- rendered documents: a surface of their own, scoped to the item's section and summary rows ----
k='AK''IA''QQQQRRRRSSSSTTTT'
mkrendered "$tmp/rnd1" "" "key $k" && expect "rendered: SECRET in the summary row" 1 '^FINDING SECRET FX-002 aws-access-key-id on rendered:Issues_Summary.md$' --db "$tmp/good.db" "${F[@]}" --rendered "$tmp/rnd1"
mkrendered "$tmp/rnd2" "see /tmp/fx/r.txt" && expect "rendered: EPHEMERAL in the item section" 1 '^FINDING EPHEMERAL FX-002 tmp-path: /tmp/fx/r.txt on rendered:Issues.md$' --db "$tmp/good.db" "${F[@]}" --rendered "$tmp/rnd2"
mkrendered "$tmp/rnd3" "bell"$'\x07'"here" && expect "rendered: CONTROL-CHAR in the item section" 1 '^FINDING CONTROL-CHAR FX-002 U\+0007 on rendered:Issues.md$' --db "$tmp/good.db" "${F[@]}" --rendered "$tmp/rnd3"
mkrendered "$tmp/rnd4" "" "" "key $k" && expect "rendered: another item's section is not this item's surface" 0 "$RES_OK" --db "$tmp/good.db" "${F[@]}" --rendered "$tmp/rnd4"
mkrendered "$tmp/rnd8" $'\n## Reviewer notes\n\nsee /tmp/fx/lv4' && expect "rendered: lines after a non-item heading are not the item's (LV4)" 0 "$RES_OK" --db "$tmp/good.db" "${F[@]}" --rendered "$tmp/rnd8"
mkrendered "$tmp/rnd9" $'see /tmp/fx/lv4\n## Reviewer notes' && expect "rendered: lines before a non-item heading are the item's (LV4 control)" 1 '^FINDING EPHEMERAL FX-002 tmp-path: /tmp/fx/lv4 on rendered:Issues.md$' --db "$tmp/good.db" "${F[@]}" --rendered "$tmp/rnd9"
mkdir -p "$tmp/rnd5" && printf '# Issues\n\n## FX-001 — Fixture umbrella\n' >"$tmp/rnd5/Issues.md"
expect "BLIND: selected item absent from every rendered document" 3 'absent from every rendered document: FX-002' --db "$tmp/good.db" "${F[@]}" --rendered "$tmp/rnd5"
mkdir -p "$tmp/rnd6"
expect "BLIND: no rendered document" 3 'no rendered document in' --db "$tmp/good.db" "${F[@]}" --rendered "$tmp/rnd6"
mkrendered "$tmp/rnd7" && printf '\xff\xfe not utf-8\n' >>"$tmp/rnd7/Issues_Summary.md"
expect "BLIND: unreadable rendered document" 3 'rendered document unreadable: Issues_Summary.md' --db "$tmp/good.db" "${F[@]}" --rendered "$tmp/rnd7"
expect "usage: --rendered with --no-rendered" 2 'exclude each other' --db "$tmp/good.db" "${F[@]}" --rendered "$tmp/rnd1" --no-rendered
expect "--no-rendered scans no rendered document" 0 '^RESULT: PASS selected=1 findings=0 prefix=FX rendered=none$' --db "$tmp/good.db" "${F[@]}" --no-rendered
expect "no --repo-root: no rendered document by default" 0 '^RESULT: PASS .* rendered=none$' --db "$tmp/good.db" --origin "Origin: fixture batch" --prefix FX --require-dup-check

# a SECRET finding prints the pattern name and the surfaces, never the matched string (section 11.4.10)
mkfixture "$tmp/sec.db" 'rows["FX-002"]["description"] = G + "\nkey " + '"$KEY" || exit 2
run_lint "$tmp/out" --db "$tmp/sec.db" "${F[@]}"
if grep -q 'QQQQRRRRSSSSTTTT' "$tmp/out"; then bad "secret value never printed" "the matched string is in the output"
elif grep -q '^FINDING SECRET FX-002 aws-access-key-id on description,body_md$' "$tmp/out"; then ok "secret value never printed"
else bad "secret value never printed" "no SECRET finding (control)"; fi

# --skip-check drops only the named code
mkfixture "$tmp/two.db" 'rows["FX-002"]["description"] = G.replace("**Acceptance criteria:**", "Acceptance:") + "\nsee review_fixture_r1.md"' || exit 2
run_lint "$tmp/out" --db "$tmp/two.db" "${F[@]}" --skip-check SECTIONS
if [ "$rc" = 1 ] && ! grep -q '^FINDING SECTIONS' "$tmp/out" && grep -q '^FINDING EPHEMERAL' "$tmp/out"; then ok "--skip-check drops only the named code"
else bad "--skip-check drops only the named code" "rc=$rc $(tr '\n' '|' <"$tmp/out")"; fi

# ---- usage (2) and BLIND (3) exits; prefix auto-detection ----
expect "usage: no selection" 2 'give --origin or --ids' --db "$tmp/good.db"
expect "usage: unknown --skip-check code" 2 'unknown --skip-check' --db "$tmp/good.db" --ids FX-002 --skip-check NOPE
expect "usage: unknown --skip-check code with --embeddings" 2 'unknown --skip-check' --db "$tmp/good.db" --ids FX-002 --embeddings --skip-check NOPE
expect "usage: --repo-root not a directory" 2 'not a directory' --db "$tmp/good.db" --ids FX-002 --repo-root "$tmp/none"
expect "BLIND: database missing" 3 'database not found' --db "$tmp/none.db" --ids FX-002
printf 'not a database\n' >"$tmp/junk.db"
expect "BLIND: database unreadable" 3 '^BLIND: ' --db "$tmp/junk.db" --ids FX-002
# round 5 (R4-9): a non-empty -wal sidecar is BLIND (its pages are not in the file the sha256 names), and
# a database path holding `?` and `#` is quoted (unquoted, sqlite reads them as URI syntax and opens,
# read-write, a file named by the text before the `?`)
cp "$tmp/good.db" "$tmp/wal.db" && printf 'x' >"$tmp/wal.db-wal" || exit 2
expect "BLIND: a non-empty -wal sidecar (R4-9)" 3 'wal\.db has a non-empty -wal sidecar' --db "$tmp/wal.db" "${F[@]}"
: >"$tmp/wal.db-wal" || exit 2
expect "an empty -wal sidecar is not BLIND (R4-9 control)" 0 "$RES_OK" --db "$tmp/wal.db" "${F[@]}"
mkdir -p "$tmp/qd" && cp "$tmp/good.db" "$tmp/qd/a?b#c.db" || exit 2
expect "a database path with ? and # is read as a path (R4-9)" 0 "$RES_OK" --db "$tmp/qd/a?b#c.db" "${F[@]}"
if [ ! -e "$tmp/qd/a" ]; then ok "a database path with ? and # creates no stray file (R4-9)"; else bad "a database path with ? and # creates no stray file (R4-9)" "$tmp/qd/a exists"; fi
# a finding both location rows carry is reported once, from the first row (round 5)
mkfixture "$tmp/dup2.db" 'rows["FX-002"]["description"] = G + "\nsee /tmp/" + "fx/twice"; extra.append(dict(rows["FX-002"], current_location="Fixed"))' || exit 2
expect "a finding of both location rows: rc 1" 1 '^FINDING EPHEMERAL FX-002 tmp-path: /tmp/fx/twice on description,body_md$' --db "$tmp/dup2.db" "${F[@]}"
n2=$(grep -c 'tmp-path: /tmp/fx/twice' "$tmp/out")
if [ "$n2" = 1 ]; then ok "a finding of both location rows is reported once"; else bad "a finding of both location rows is reported once" "$n2 lines: $(grep 'fx/twice' "$tmp/out" | tr '\n' '|')"; fi
blind=(
  'database holds no items|rows.clear()|holds no items'
  'required table operator_block_details missing|drop.append("operator_block_details")|required table\(s\) missing: operator_block_details'
  'required tables item_history and obsolete_details missing|drop.extend(["item_history", "obsolete_details"])|required table\(s\) missing: obsolete_details,item_history'
  'NULL description|rows["FX-002"]["description"] = None; body["FX-002"] = ""|item FX-002 has a NULL or non-text description'
  'NULL title|rows["FX-002"]["title"] = None|item FX-002 has a NULL or non-text title'
  'BLOB body_md|body["FX-002"] = render("FX-002").encode()|a BLOB value in items.body_md \(row FX-002\)'
  'BLOB description|rows["FX-002"]["description"] = G.encode(); body["FX-002"] = render("FX-002", dict(rows["FX-002"], description=G))|a BLOB value in items.description \(row FX-002\)'
  'BLOB in obsolete_details|od["FX-001"] = mkod(b"duplicate-of", "FX-003")|a BLOB value in obsolete_details.reason'
  'BLOB in a state column|rows["FX-002"]["reproduction_state"] = b"x"; body["FX-002"] = render("FX-002", dict(rows["FX-002"], reproduction_state="UNREPRODUCED"))|a BLOB value in items.reproduction_state'
  'a crash is BLIND, never a traceback|nohistid[0] = True|^BLIND: the lint crashed \(OperationalError'
)
for c in "${blind[@]}"; do
  n=$((n + 1)); name=${c%%|*}; rest=${c#*|}; snip=${rest%%|*}; pat=${rest#*|}
  mkfixture "$tmp/blind$n.db" "$snip" || { bad "BLIND: $name" "fixture build failed"; continue; }
  expect "BLIND: $name" 3 "$pat" --db "$tmp/blind$n.db" --ids FX-002 --prefix FX
done
expect "BLIND: unknown id" 3 'not in the database: FX-777' --db "$tmp/good.db" --ids FX-777
expect "BLIND: empty origin selection" 3 'selection is empty' --db "$tmp/good.db" --origin "no such origin text"
expect "BLIND: --prefix that no item carries" 3 'no item in the database carries the prefix ZZ' --db "$tmp/good.db" --ids FX-002 --prefix ZZ
mkfixture "$tmp/pfx.db" 'rows["AA-001"] = item("AA-001", "Alphabetically first prefix", "an item of another tracker")' || exit 2
expect "prefix auto-detection takes the most common prefix" 0 "$RES_OK" --db "$tmp/pfx.db" --origin "Origin: fixture batch" --require-dup-check --repo-root "$tmp/repo"
mkfixture "$tmp/pfx2.db" 'rows["AA-001"] = item("AA-001", "Alphabetically first prefix", "an item of another tracker"); rows["FX-002"]["description"] = G.replace("FX-001 (fixture umbrella)", "FX-099")' || exit 2
expect "prefix auto-detection sees the dangling FX id" 1 '^FINDING XREF-DANGLING FX-002 FX-099$' --db "$tmp/pfx2.db" --origin "Origin: fixture batch" --require-dup-check --repo-root "$tmp/repo"

# ---- --embeddings ----
run_lint "$tmp/out" --db "$tmp/good.db" --origin "Origin: fixture batch" --prefix FX --embeddings
if [ "$rc" = 0 ] && grep -qx $'item\tembedded_id\tnamespace\tcount' "$tmp/out" \
   && grep -qx $'FX-002\tFX-001\tmain\t1' "$tmp/out" && grep -qx $'FX-002\tFX-900\tforeign\t2' "$tmp/out"; then
  ok "--embeddings namespaces main and foreign"
else bad "--embeddings namespaces main and foreign" "rc=$rc $(tr '\n' '|' <"$tmp/out")"; fi
mkfixture "$tmp/emb.db" 'rows["FX-002"]["title"] = "about FX-002 and FX-555"' || exit 2
run_lint "$tmp/out" --db "$tmp/emb.db" --origin "Origin: fixture batch" --prefix FX --embeddings
if grep -qx $'FX-002\tFX-002\town\t1' "$tmp/out" && grep -qx $'FX-002\tFX-555\tunknown\t1' "$tmp/out"; then
  ok "--embeddings namespaces own and unknown (title included)"
else bad "--embeddings namespaces own and unknown (title included)" "$(tr '\n' '|' <"$tmp/out")"; fi
mkfixture "$tmp/embr.db" 'rows["FX-002"]["description"] = G.replace("FX-900 of another", "FX-900..FX-903 of another").replace("tracker): FX-900", "tracker): FX-900..FX-903")' || exit 2
run_lint "$tmp/out" --db "$tmp/embr.db" --origin "Origin: fixture batch" --prefix FX --embeddings
if grep -qx $'FX-002\tFX-901\tforeign\t2' "$tmp/out" && grep -qx $'FX-002\tFX-902\tforeign\t2' "$tmp/out"; then
  ok "--embeddings lists the interior ids of a range"
else bad "--embeddings lists the interior ids of a range" "$(tr '\n' '|' <"$tmp/out")"; fi

# ---- a refused cleanup fails the run (R2-10); the probe child leaves its dir, which is removed here ----
probe_out=$(env -u HOME INTAKE_LINT_SUITE_CLEANUP_ONLY=1 bash "$self" 2>&1); probe_rc=$?
probe_dir=$(printf '%s\n' "$probe_out" | sed -n 's/^CLEANUP REFUSED: temp dir left behind: //p' | head -n 1)
# remove the dir the child left before judging, so a failing case (and fail-fast) leaves nothing behind
case "$probe_dir" in
  /tmp/tmp.*|"${TMPDIR:-/tmp}"/tmp.*) [ -d "$probe_dir" ] && safe_rm_rf "${probe_dir:?}" ;;
esac
if [ "$probe_rc" = 2 ] && [ -n "$probe_dir" ]; then ok "refused cleanup exits 2 and names the dir"
else bad "refused cleanup exits 2 and names the dir" "rc=$probe_rc $(printf '%s' "$probe_out" | tr '\n' '|' | cut -c1-200)"; fi
probe_out=$(INTAKE_LINT_SUITE_CLEANUP_ONLY=1 bash "$self" 2>&1); probe_rc=$?
if [ "$probe_rc" = 0 ]; then ok "cleanup with HOME set exits 0 (control)"
else bad "cleanup with HOME set exits 0 (control)" "rc=$probe_rc $(printf '%s' "$probe_out" | tr '\n' '|' | cut -c1-200)"; fi

# ---- the built-in needles bind each golden-bad case to its own check (round 4) ----
# A copy of the lint under test with one check switched off must fail its own golden-bad needle, even
# when a second check under the same code catches the same text. These run with the built-in needles
# on, whatever INTAKE_LINT_EXTRA says.
# needle_copy <name> <old> <new>: writes $tmp/<name>.py, the lint under test with <old> replaced once
needle_copy() {
  python3 -I - "$lint" "$tmp/$1.py" "$2" "$3" <<'PY'
import sys
s = open(sys.argv[1], encoding="utf-8").read()
if sys.argv[3] and s.count(sys.argv[3]) != 1:  # an empty <old> is the unchanged control copy
    sys.exit("the check text is not in the lint exactly once")
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(sys.argv[3], sys.argv[4]))
PY
}
needle_case() { # needle_case <name> <copy> <want-pattern>
  python3 -I "$tmp/$2.py" --db "$tmp/none.db" --ids FX-002 >"$tmp/out" 2>&1; rc=$?
  if [ "$rc" = 3 ] && grep -Eq -- "$3" "$tmp/out"; then ok "$1"
  else bad "$1" "rc=$rc: $(tr '\n' '|' <"$tmp/out" | cut -c1-300)"; fi
}
if needle_copy needle_ctl '' ''; then
  needle_case "needle control: the unchanged copy passes its needles" needle_ctl '^BLIND: database not found'
else bad "needle control: the unchanged copy passes its needles" "copy failed"; fi
if needle_copy needle_sep '        if LINE_SEPARATORS.search(line):' '        if False:'; then
  needle_case "needle: the header line-separator check off is named, though the Status compare also fires" needle_sep \
    '^BLIND: control needle failed: BODY-SYNC/header-line-separator$'
else bad "needle: the header line-separator check off is named, though the Status compare also fires" "the check text is missing"; fi
if needle_copy needle_mkt 'tmp\.(?!X{10})[A-Za-z0-9]{10}' 'tmp\.(?!X{10})[A-Za-z0-9]{11}'; then
  needle_case "needle: the mktemp-default pattern off is named, though the tmp-path pattern also fires" needle_mkt \
    '^BLIND: control needle failed: (.*,)?EPHEMERAL/mktemp-default(,|$)'
else bad "needle: the mktemp-default pattern off is named, though the tmp-path pattern also fires" "the check text is missing"; fi

# ---- the real database: intake batch is clean; reviewer data mutants and replays on COPIES ----
if [ ! -f "$realdb" ]; then
  bad "real database present" "$realdb missing"
else
  O=(--origin "tracker-intake vehicle 2026-11-12" --require-dup-check --repo-root "$root")
  expect "real DB: intake batch clean (46 items, rendered documents read)" 0 \
    '^RESULT: PASS selected=46 findings=0 prefix=CON rendered=Issues.md,Fixed.md,Issues_Summary.md,Fixed_Summary.md$' --db "$realdb" "${O[@]}"
  # mutate_real <name> <want-rc> <python snippet> <pattern>...: every pattern must be in the output.
  # setdesc rewrites the description and the copy of it inside body_md (as the engine would);
  # setdesc(..., body=False) leaves body_md alone. setcol writes one column (body_md untouched).
  mutate_real() {
    local name=$1 want=$2 snip=$3 p; shift 3
    python3 -I - "$realdb" "$tmp/real.db" "$snip" <<'PY' || { bad "$name" "mutation failed"; return; }
import re, sqlite3, sys
src, dst, snip = sys.argv[1:4]
s = sqlite3.connect("file:%s?mode=ro" % src, uri=True); d = sqlite3.connect(dst)
s.backup(d); s.close()
def get(i, c): return d.execute("select %s from items where atm_id=? order by current_location desc limit 1" % c, (i,)).fetchone()[0]
def desc(i): return get(i, "description")
def body(i): return get(i, "body_md")
def setcol(i, c, v): d.execute("update items set %s=? where atm_id=?" % c, (v, i))
def setbody(i, b): setcol(i, "body_md", b)
def must(t, a): assert t.count(a) == 1, (a, t.count(a)); return t
def setdesc(i, t, body=True):
    old = desc(i)
    setcol(i, "description", t)
    if body:
        b = get(i, "body_md")
        assert b.count(old) == 1, "body does not hold the description once"
        setbody(i, b.replace(old, t))
def close_dup(i, sup):
    d.execute("update items set status=?, current_location=? where atm_id=?", ("Obsolete (→ Fixed.md)", "Fixed", i))
    d.execute("update items set body_md=replace(body_md, ?, ?) where atm_id=?", ("**Status:** Reopened", "**Status:** Obsolete (→ Fixed.md)", i))
    d.execute("update obsolete_details set reason=?, superseding_item=? where atm_id=?", ("duplicate-of", sup, i))
def reopen(i, drop_od=False):
    # back to the open state the engine's reopen gives (the obsolete_details row stays, CON-340);
    # drop_od=True also removes the row (the reviewer's DM9/DM10 shape)
    d.execute("update items set status=?, current_location=? where atm_id=?", ("Reopened", "Issues", i))
    d.execute("update items set body_md=replace(body_md, ?, ?) where atm_id=?", ("**Status:** Obsolete (→ Fixed.md)", "**Status:** Reopened", i))
    if drop_od:
        d.execute("delete from obsolete_details where atm_id=?", (i,))
R21 = ("Duplicate check (section 11.4.214): SAME-DEFECT of CON-262 (its acceptance criterion already says run_all.sh reports a 77 as SKIP); this item is closed Obsolete, reason duplicate-of, superseding CON-262, and its context is appended to CON-262. CON-243 names the same run_all.sh behaviour (plus tier awareness) and is a second open head; that CON-243 / CON-262 overlap is pre-existing and its merge stays UNDECIDED for the lander or the operator (section 11.4.214(3)). CON-145 and CON-261 name run_all.sh for other defects. Method: every open item compared by title and description word overlap and by shared file names (docs/qa/tracker_intake_2026_11_12_v2/inventory/).")  # the round-2 line of CON-308, verbatim from the round-2 database
def dupline(i, new):
    t = desc(i); ls = [l for l in t.split("\n") if l.startswith("Duplicate check (section 11.4.214):")]
    assert len(ls) == 1; setdesc(i, t.replace(ls[0], new))
KEY = "AK" + "IA" + "QQQQRRRRSSSSTTTT"  # a fake canary, built from fragments
exec(snip, {"d": d, "re": re, "desc": desc, "body": body, "get": get, "setcol": setcol, "setdesc": setdesc,
            "setbody": setbody, "must": must, "close_dup": close_dup, "dupline": dupline, "R21": R21,
            "reopen": reopen, "KEY": KEY})
d.commit(); d.close()
PY
    run_lint "$tmp/out" --db "$tmp/real.db" "${O[@]}"
    safe_rm_rf "${tmp:?}/real.db"
    if [ "$rc" != "$want" ]; then bad "$name" "rc=$rc want=$want: $(tr '\n' '|' <"$tmp/out" | cut -c1-300)"; return; fi
    for p in "$@"; do
      grep -Eq -- "$p" "$tmp/out" || { bad "$name" "pattern /$p/ not in: $(tr '\n' '|' <"$tmp/out" | cut -c1-300)"; return; }
    done
    ok "$name"
  }
  HEADS='^FINDING DUP-HEAD CON-308 more than one head \(section 11\.4\.214\(0\)\): CON-243 names CON-262 as a duplicate$'
  # rounds 1 and 2
  mutate_real "reviewer M2: description diverges from body_md" 1 \
    't = desc("CON-313"); setdesc("CON-313", t + "\nan invented path scripts/invented.sh", body=False)' '^FINDING BODY-SYNC CON-313 '
  mutate_real "reviewer M3: umbrella CON-299 changed to CON-999" 1 \
    't = desc("CON-313"); setdesc("CON-313", must(t, "umbrella CON-299").replace("umbrella CON-299", "umbrella CON-999"))' '^FINDING XREF-DANGLING CON-313 CON-999$'
  mutate_real "reviewer M7: delete a referenced row" 1 \
    'd.execute("delete from items where atm_id=?", ("CON-262",))' '^FINDING XREF-DANGLING CON-[0-9]+ CON-262$'
  mutate_real "reviewer M9: AWS-key-shaped string in CON-333" 1 \
    't = desc("CON-333"); setdesc("CON-333", t + "\nkey " + KEY)' '^FINDING SECRET CON-333 aws-access-key-id on description,body_md$'
  mutate_real "reviewer M10: Acceptance criteria header removed" 1 \
    't = desc("CON-311"); setdesc("CON-311", must(t, "**Acceptance criteria:**").replace("**Acceptance criteria:**", "Acceptance:"))' '^FINDING SECTIONS CON-311 missing: Acceptance criteria$'
  mutate_real "reviewer M11: structured reproduction line vs column" 1 \
    't = desc("CON-301"); setdesc("CON-301", t + "\n**Reproduction:** reproduced-live — REPRODUCED")' '^FINDING STATE-PROSE CON-301 structured line says reproduced-live'
  mutate_real "round-2 D1: default mktemp dir in CON-315" 1 \
    't = desc("CON-315"); setdesc("CON-315", t + "\nlog /tmp/tmp." + "k3Jx9" + "QvT2a" + "/out.txt")' '^FINDING EPHEMERAL CON-315 mktemp-default'
  mutate_real "round-2 D1b: all-lowercase 4-character suffix" 1 \
    't = desc("CON-315"); setdesc("CON-315", t + "\nsee trackintake." + "zobh" + "/c")' '^FINDING EPHEMERAL CON-315 mktemp-dir'
  mutate_real "round-2 D2: GitLab PAT-shaped string in CON-315" 1 \
    't = desc("CON-315"); setdesc("CON-315", t + "\ntoken " + "gl" + "pat-" + "Ab3dE" + "f6hIj" + "K9mNo" + "pQrSt")' '^FINDING SECRET CON-315 gitlab-pat '
  mutate_real "round-2 D3: CON-332 in its round-1 form, no label" 1 \
    't = desc("CON-332"); a = "related: anchor section 11.4.296 (an anchor, not a tracker item), not a parent"; setdesc("CON-332", must(t, a).replace(a, "related CON-296, not a parent"))' '^FINDING XREF-UNLABELLED CON-332 CON-296 '
  mutate_real "round-2 D3b: a wrong label sharing one title word" 1 \
    't = desc("CON-332"); a = "related: anchor section 11.4.296 (an anchor, not a tracker item), not a parent"; setdesc("CON-332", must(t, a).replace(a, "related CON-296 (runner for GitHub issues), not a parent"))' '^FINDING XREF-LABEL CON-332 CON-296 '
  mutate_real "round-2 D5: empty body_md on CON-310" 1 'setbody("CON-310", "")' '^FINDING BODY-SYNC CON-310 body_md is empty$'
  mutate_real "round-2 D6: contradiction in body_md only" 1 \
    'setbody("CON-310", body("CON-310") + "\n\nUpdate: already fixed on main; no work owed.\n")' '^FINDING BODY-SYNC CON-310 body_md carries text after the description'
  mutate_real "round-2 D7a: CON-308 closed duplicate-of an id that does not exist" 1 \
    'dupline("CON-308", R21); close_dup("CON-308", "CON-999")' '^FINDING DUP-SAME-OPEN CON-308 '
  mutate_real "round-2 D7b: CON-308 superseding swapped to CON-243" 1 \
    'dupline("CON-308", R21); close_dup("CON-308", "CON-243")' '^FINDING DUP-SAME-OPEN CON-308 '
  # CON-243, CON-262, CON-308: since operator decision 8 (2026-11-13) CON-262 is the single open head
  # and CON-243 and CON-308 are Obsolete duplicate-of it; each case below puts back one wrong state
  mutate_real "round-2 D8: Obsolete duplicate-of with the verdict UNDECIDED" 1 \
    'dupline("CON-308", "Duplicate check (section 11.4.214): UNDECIDED; candidate duplicates CON-262 (wider SKIP class, run_all.sh labels exit 77 FAIL).")' '^FINDING DUP-STATUS CON-308 '
  mutate_real "replay R2-1: CON-243 back as a second open head (an UNDECIDED candidate of CON-262)" 1 \
    'reopen("CON-243"); t = desc("CON-262"); setdesc("CON-262", t + " Candidate duplicate: CON-243 (the same run_all.sh behaviour plus tier awareness); merge UNDECIDED (section 11.4.214(3)).", body=False)' '^FINDING DUP-HEAD CON-308 '
  mutate_real "replay R2-1 with the round-2 line of CON-308 verbatim" 1 \
    'dupline("CON-308", R21); reopen("CON-243"); t = desc("CON-262"); setdesc("CON-262", t + " Candidate duplicate: CON-243 (the same run_all.sh behaviour plus tier awareness); merge UNDECIDED (section 11.4.214(3)).", body=False)' '^FINDING DUP-HEAD CON-308 '
  mutate_real "replay I1: CON-308 open while SAME-DEFECT of open CON-262" 1 'reopen("CON-308")' '^FINDING DUP-SAME-OPEN CON-308 '
  mutate_real "UNDECIDED verdict without a candidate on CON-308" 1 \
    'dupline("CON-308", "Duplicate check (section 11.4.214): UNDECIDED (no candidate named).")' '^FINDING DUP-UNDECIDED CON-308 UNDECIDED names no candidate id$'
  mutate_real "CON-308 reopened with its obsolete_details row and no stale note" 1 'reopen("CON-308")' '^FINDING OBSOLETE-STALE CON-308 '
  mutate_real "replay I2: anchor 296 cited as an item" 1 \
    't = desc("CON-332"); i = t.index("section 11.4.296"); setdesc("CON-332", t[:i] + "CON-296 (GitHub issues sync)" + t[i + len("section 11.4.296"):])' '^FINDING XREF-LABEL CON-332 CON-296 '
  # round 3: the reviewer's data mutants DM1..DM16, DMC and DMN, rebuilt as snippets on the current
  # database (docs/qa/tracker_intake_2026_11_12_v4/README.md maps each one to the reviewer's DB diff)
  mutate_real "round-3 DM1: a second Status line in the CON-310 body" 1 \
    'b = must(body("CON-310"), "**Status:** Queued\n"); setbody("CON-310", b.replace("**Status:** Queued\n", "**Status:** Queued\n**Status:** Fixed (→ Fixed.md)\n"))' \
    '^FINDING BODY-SYNC CON-310 body_md header key Status is written twice$'
  mutate_real "round-3 DM2: Severity Low to Critical in the CON-310 body" 1 \
    'b = must(body("CON-310"), "**Severity:** Low\n"); setbody("CON-310", b.replace("**Severity:** Low\n", "**Severity:** Critical\n"))' \
    '^FINDING BODY-SYNC CON-310 body_md Severity line differs from its source$'
  mutate_real "round-3 DM3: Type Task to Bug in the CON-310 body" 1 \
    'b = must(body("CON-310"), "**Type:** Task\n"); setbody("CON-310", b.replace("**Type:** Task\n", "**Type:** Bug\n"))' \
    '^FINDING BODY-SYNC CON-310 body_md Type line differs from its source$'
  mutate_real "round-3 DM4: a key in the CON-336 reproduction_env column only" 1 \
    'setcol("CON-336", "reproduction_env", get("CON-336", "reproduction_env") + " key " + KEY)' \
    '^FINDING SECRET CON-336 aws-access-key-id on items\.reproduction_env$' '^FINDING BODY-SYNC CON-336 body_md Reproduction line differs from its source$'
  mutate_real "round-3 DM4b: URL userinfo in the CON-336 red command, column and body (an engine update)" 1 \
    'old = get("CON-336", "reproduction_red_cmd"); new = "git clone https://ci-user:" + "Zq9Lm4" + "Xp7Rt2Vb" + "@git.example.invalid/r.git"; setcol("CON-336", "reproduction_red_cmd", new); setbody("CON-336", must(body("CON-336"), old).replace(old, new))' \
    '^FINDING SECRET CON-336 url-userinfo-password on body_md,items\.reproduction_red_cmd$'
  mutate_real "round-3 DM5: a key on the CON-310 Created-By line (body only)" 1 \
    'b = body("CON-310"); m = re.search(r"(?m)^\*\*Created-By:\*\* [^\n]*$", b); setbody("CON-310", b[:m.end()] + " " + KEY + b[m.end():])' \
    '^FINDING BODY-SYNC CON-310 body_md Created-By line differs from its source$' '^FINDING SECRET CON-310 aws-access-key-id on body_md$'
  mutate_real "round-3 DM6: a mktemp /tmp path in the CON-336 red command column only" 1 \
    'setcol("CON-336", "reproduction_red_cmd", get("CON-336", "reproduction_red_cmd") + " > /tmp/tmp." + "k3Jx9QvT2a" + "/o.txt")' \
    '^FINDING EPHEMERAL CON-336 tmp-path: /tmp/tmp\.k3Jx9QvT2a/o\.txt on items\.reproduction_red_cmd$' '^FINDING BODY-SYNC CON-336 body_md Reproduction line differs'
  mutate_real "round-3 DM7: the CON-308 Obsolete-Details line removed" 1 \
    'b = body("CON-308"); setbody("CON-308", re.sub(r"(?m)^\*\*Obsolete-Details:\*\*[^\n]*\n", "", b, count=1))' \
    '^FINDING BODY-SYNC CON-308 body_md lacks the Obsolete-Details line its source gives$'
  mutate_real "round-3 DM8: the CON-308 Obsolete-Details superseding id swapped" 1 \
    'b = must(body("CON-308"), "Superseding-item: CON-262"); setbody("CON-308", b.replace("Superseding-item: CON-262", "Superseding-item: CON-243"))' \
    '^FINDING BODY-SYNC CON-308 body_md Obsolete-Details line differs from its source$'
  mutate_real "round-3 DM9: CON-243 reopened (row removed) with an UNDECIDED Duplicate check line" 1 \
    'reopen("CON-243", drop_od=True); setdesc("CON-243", desc("CON-243") + "\nDuplicate check (section 11.4.214): UNDECIDED; candidate duplicates CON-262 (run_all.sh exit 77).")' "$HEADS"
  mutate_real "round-3 DM10: CON-243 reopened; CON-262 names it a candidate (lower-case undecided)" 1 \
    'reopen("CON-243", drop_od=True); setdesc("CON-262", desc("CON-262") + " Candidate duplicate: CON-243 (the same run_all.sh behaviour plus tier awareness); merge undecided (section 11.4.214(3)).", body=False)' "$HEADS"
  mutate_real "round-3 DM10b: CON-243 reopened; CON-262 calls it a possible second head" 1 \
    'reopen("CON-243", drop_od=True); setdesc("CON-262", desc("CON-262") + " CON-243 (the same run_all.sh behaviour plus tier awareness) may be a second head of this defect; open question for the operator.", body=False)' "$HEADS"
  mutate_real "round-3 DM10c: CON-243 reopened, nothing else" 1 'reopen("CON-243", drop_od=True)' "$HEADS"
  mutate_real "round-3 DMC: CON-243 reopened; CON-262 names it with merge UNDECIDED" 1 \
    'reopen("CON-243", drop_od=True); setdesc("CON-262", desc("CON-262") + " Candidate duplicate: CON-243 (the same run_all.sh behaviour plus tier awareness); merge UNDECIDED (section 11.4.214(3)).", body=False)' "$HEADS"
  mutate_real "round-3 DM11: U+2028 in the CON-310 title and heading" 1 \
    't = get("CON-310", "title"); n2 = t + " injected second line"; setcol("CON-310", "title", n2); setbody("CON-310", must(body("CON-310"), "— " + t + "\n").replace("— " + t + "\n", "— " + n2 + "\n"))' \
    '^FINDING CONTROL-CHAR CON-310 U\+2028 on title,body_md$'
  mutate_real "round-3 DM11b: U+2028 instead of a newline in the CON-310 description" 1 \
    't = desc("CON-310"); a = must(t, "classify or scope it.\n"); setdesc("CON-310", t.replace("classify or scope it.\n", "classify or scope it. "))' \
    '^FINDING CONTROL-CHAR CON-310 U\+2028 on description,body_md$'
  mutate_real "round-3 DM12: a NUL in the CON-310 description" 1 \
    'setdesc("CON-310", desc("CON-310") + "\x00hidden")' '^FINDING CONTROL-CHAR CON-310 U\+0000 on description,body_md$'
  mutate_real "round-3 DM13: the CON-310 body_md stored as a BLOB" 3 \
    'setbody("CON-310", body("CON-310").encode())' '^BLIND: a BLOB value in items\.body_md \(row CON-310\)$'
  mutate_real "round-3 DM13b: the CON-310 description stored as a BLOB" 3 \
    'setcol("CON-310", "description", desc("CON-310").encode())' '^BLIND: a BLOB value in items\.description \(row CON-310\)$'
  mutate_real "round-3 DM14: the CON-336 Investigation line names another state" 1 \
    'b = must(body("CON-336"), "**Investigation:** in-progress"); setbody("CON-336", b.replace("**Investigation:** in-progress", "**Investigation:** root-cause-found-with-evidence"))' \
    '^FINDING BODY-SYNC CON-336 body_md Investigation line differs from its source$'
  mutate_real "round-3 DM15: an Obsolete-Details line in the body of open CON-321" 1 \
    'b = body("CON-321"); m = re.search(r"(?m)^\*\*Created-By:\*\* [^\n]*\n", b); setbody("CON-321", b[:m.end()] + "**Obsolete-Details:** duplicate-of CON-001\n" + b[m.end():])' \
    '^FINDING BODY-SYNC CON-321 body_md has an Obsolete-Details line while its source gives none$'
  mutate_real "round-3 DM16: the CON-321 heading names CON-320" 1 \
    'setbody("CON-321", must(body("CON-321"), "## CON-321 — ").replace("## CON-321 — ", "## CON-320 — "))' \
    '^FINDING BODY-SYNC CON-321 body_md heading disagrees with the id or title column$'
  mutate_real "round-3 DMN: a key appended to the CON-333 description (control of DM5)" 1 \
    'setdesc("CON-333", desc("CON-333") + "\nkey " + KEY)' '^FINDING SECRET CON-333 aws-access-key-id on description,body_md$'
fi

echo "RESULT: pass=$pass fail=$fail"
[ "$fail" = 0 ]
