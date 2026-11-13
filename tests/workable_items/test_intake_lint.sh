#!/usr/bin/env bash
# tests/workable_items/test_intake_lint.sh -- hermetic test of scripts/workable-items/intake_lint.py.
#
# Documentation (section 11.4.18): docs/guides/intake_lint_guide.md.
#
# WHAT  (1) golden-good and golden-bad fixture databases: at least one golden-bad per finding code,
#       one positive and one negative control needle per SECRET pattern, the mktemp shapes, both
#       BODY-SYNC directions, the UNDECIDED path; (2) the usage (2) and BLIND (3) exits, the prefix
#       auto-detection and the operator_decisions/ branch of PATH-MISSING; (3) the --embeddings TSV
#       namespaces, including the interior of a range; (4) the reviewer's data mutants of rounds 1
#       and 2 (M2, M3, M7, M9, M10, M11; D1, D1b, D2, D3, D3b, D5, D6, D7a, D7b, D8) and replays of
#       findings I1, I2 and R2-1, each applied to a scratch COPY of docs/workable_items.db (the real
#       database is opened read-only and never written); (5) a refused cleanup makes the suite fail.
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

# ---- fixture database: a minimal items + obsolete_details schema (the columns the lint reads) ----
# The body is rendered here the way the engine renders it (heading, header block, description), by
# this suite's own code, so that a defect in the lint's checker cannot hide behind a shared renderer.
mkfixture() { # mkfixture <db> <python-mutation-snippet>
  python3 -I - "$1" "$2" <<'PY'
import sqlite3, sys
db, snippet = sys.argv[1], sys.argv[2]
G = ("**What:** a fixture item.\n\n**Affected scope / file-scope manifest:**\nscripts/fixture_only_tool.sh\n\n"
     "**Reproduction / context:**\nnone\n\n**Acceptance criteria:**\nnone\n\n"
     "Parent / links: umbrella FX-001 (fixture umbrella)\n"
     "Duplicate check (section 11.4.214): DISTINCT\n"
     "Context: FX-900 of another tracker; evidence docs/qa/fx_present/e.txt; bundle b.bundle (ephemeral: a scratch file)\n"
     "Foreign ids (another tracker): FX-900\n"
     "Origin: fixture batch")
rows = {
    "FX-001": dict(title="Fixture umbrella", description="umbrella of the fixture batch", status="Queued", loc="Issues", rs=None, ivs=None),
    "FX-002": dict(title="Fixture good item", description=G, status="Queued", loc="Issues", rs=None, ivs=None),
    "FX-003": dict(title="Unrelated open item", description="nothing shared here", status="Queued", loc="Issues", rs=None, ivs=None),
}
od = {}
def render(i, r):
    h = ["**Status:** " + r["status"], "**Type:** Task"]
    if r["rs"] not in (None, "UNSET"):
        h.append("**Reproduction:** " + ("none — UNREPRODUCED" if r["rs"] == "UNREPRODUCED" else r["rs"] + " — REPRODUCED"))
    if r["ivs"] not in (None, "UNSET"):
        h.append("**Investigation:** " + r["ivs"] + " — fixture")
    if r["status"].startswith("Obsolete") and i in od:
        h.append("**Obsolete-Details:** Reason: " + od[i][0])
    return "## %s — %s\n\n%s\n\n%s\n\n" % (i, r["title"], "\n".join(h), r["description"])
exec(snippet, {"rows": rows, "od": od, "G": G, "render": render})
c = sqlite3.connect(db)
c.execute("create table items (atm_id text, title text, description text, body_md text, status text,"
          " current_location text, reproduction_state text, investigation_state text)")
c.execute("create table obsolete_details (atm_id text, since text, reason text, superseding_item text, triple_check_evidence text)")
for i, r in rows.items():
    c.execute("insert into items values (?,?,?,?,?,?,?,?)", (i, r["title"], r["description"],
              r["body"] if "body" in r else render(i, r), r["status"], r["loc"], r["rs"], r["ivs"]))
for i, (reason, sup) in od.items():
    c.execute("insert into obsolete_details values (?,?,?,?,?)", (i, "2026-11-13", reason, sup, "e"))
c.commit(); c.close()
PY
}
mkdir -p "$tmp/repo/docs/qa/fx_present" "$tmp/repo/docs/operator_decisions" && : >"$tmp/repo/docs/qa/fx_present/e.txt" \
  && : >"$tmp/repo/docs/operator_decisions/fx_decisions.md" || exit 2
F=(--origin "Origin: fixture batch" --prefix FX --require-dup-check --repo-root "$tmp/repo")

mkfixture "$tmp/good.db" "pass" || exit 2
expect "golden-good fixture" 0 '^RESULT: PASS selected=1 findings=0 prefix=FX$' --db "$tmp/good.db" "${F[@]}"

# shared snippets
OBS2='rows["FX-002"]["status"] = "Obsolete"; rows["FX-002"]["loc"] = "Fixed"'
UND='rows["FX-002"]["description"] = G.replace(": DISTINCT", ": UNDECIDED; candidate duplicates FX-001 and FX-003")'

# golden-bad, at least one per finding code: <name>|<python snippet>; the code is the part before "/"
cases=(
  'XREF-DANGLING|rows["FX-002"]["description"] = G.replace("FX-001 (fixture umbrella)", "FX-099")'
  'XREF-DANGLING/title|rows["FX-002"]["title"] = "Fixture good item, see FX-098"'
  'XREF-DANGLING/foreign-declared-only|rows["FX-002"]["description"] = G.replace("Foreign ids (another tracker): FX-900", "Foreign ids (another tracker): FX-901")'
  'XREF-DANGLING/range-interior|rows["FX-002"]["description"] = G.replace("Context: FX-900", "Context: FX-001..FX-004")'
  'XREF-LABEL|rows["FX-002"]["description"] = G.replace("(fixture umbrella)", "(GitHub issues sync)")'
  'XREF-LABEL/one-shared-word|rows["FX-002"]["description"] = G.replace("(fixture umbrella)", "(umbrella of the github runners)")'
  'XREF-UNLABELLED|rows["FX-002"]["description"] = G.replace("umbrella FX-001 (fixture umbrella)", "related FX-003, not a parent")'
  'FOREIGN-STALE|rows["FX-002"]["description"] = G.replace("tracker): FX-900", "tracker): FX-900, FX-901")'
  'STATE-PROSE|rows["FX-002"]["description"] = G + "\nReproduction: reproduced-live (written in prose)"'
  'STATE-PROSE/unreproduced-family|rows["FX-002"]["rs"] = "reproduced-live"; rows["FX-002"]["description"] = G + "\nstate: UNREPRODUCED"'
  'STATE-PROSE/investigation|rows["FX-002"]["description"] = G + "\nInvestigation: in-progress"'
  'STATE-PROSE/structured|rows["FX-002"]["description"] = G + "\n**Reproduction:** reproduced-live — REPRODUCED"'
  'SECTIONS|rows["FX-002"]["description"] = G.replace("**Acceptance criteria:**", "Acceptance:")'
  'BODY-SYNC|rows["FX-002"]["body"] = "a body that diverged"'
  'BODY-SYNC/empty|rows["FX-002"]["body"] = ""'
  'BODY-SYNC/extra-paragraph|rows["FX-002"]["body"] = render("FX-002", rows["FX-002"]) + "Update: already fixed on main; no work owed.\n"'
  'BODY-SYNC/text-before|rows["FX-002"]["body"] = render("FX-002", rows["FX-002"]).replace("**Type:** Task\n", "**Type:** Task\nNote: closed upstream.\n")'
  'BODY-SYNC/heading|rows["FX-002"]["body"] = render("FX-002", rows["FX-002"]).replace("Fixture good item", "Another title", 1)'
  'BODY-SYNC/status-line|rows["FX-002"]["body"] = render("FX-002", rows["FX-002"]).replace("**Status:** Queued", "**Status:** Done")'
  'BODY-SYNC/unknown-key|rows["FX-002"]["body"] = render("FX-002", rows["FX-002"]).replace("**Type:** Task\n", "**Type:** Task\n**Verdict:** fixed\n")'
  'BODY-SYNC/header-line-separator|rows["FX-002"]["body"] = render("FX-002", rows["FX-002"]).replace("**Type:** Task\n", "**Type:** Task\u2028note: closed upstream\n")'
  'BODY-SYNC/reproduction-line|rows["FX-002"]["rs"] = "reproduced-live"; rows["FX-002"]["body"] = render("FX-002", dict(rows["FX-002"], rs="UNSET"))'
  'SECRET|rows["FX-002"]["description"] = G + "\nkey AKIA" + "QQQQRRRRSSSSTTTT"'
  'SECRET/title|rows["FX-002"]["title"] = "leak AKIA" + "QQQQRRRRSSSSTTTT"'
  'EPHEMERAL|rows["FX-002"]["description"] = G + "\nsee review_fixture_r1.md"'
  'EPHEMERAL/note-covers-own-line-only|rows["FX-002"]["description"] = G + "\nsecond bundle c.bundle with no note"'
  'EPHEMERAL/mktemp-default|rows["FX-002"]["description"] = G + "\nlog at /tmp/tmp." + "k3Jx9QvT2a" + "/out.txt"'
  'EPHEMERAL/mktemp-default-bare|rows["FX-002"]["description"] = G + "\nwork dir tmp." + "k3Jx9QvT2a" + " kept"'
  'EPHEMERAL/mktemp-default-lowercase|rows["FX-002"]["description"] = G + "\nwork dir tmp." + "qwertyuiop" + " kept"'
  'EPHEMERAL/lowercase-dir|rows["FX-002"]["description"] = G + "\nsee trackintake." + "zobh" + "/c"'
  'EPHEMERAL/four-char-mixed|rows["FX-002"]["description"] = G + "\nsee review_dir." + "Ab3d" + " for it"'
  'EPHEMERAL/tmp-path|rows["FX-002"]["description"] = G + "\nwritten to /var/tmp/" + "fx_out.txt"'
  'SHARED-PATH|rows["FX-003"]["description"] = "this open item also edits scripts/fixture_only_tool.sh"'
  'DUP-CHECK|rows["FX-002"]["description"] = G.replace(": DISTINCT", ": PROBABLY")'
  'DUP-CHECK/missing|rows["FX-002"]["description"] = G.replace("Duplicate check (section 11.4.214): DISTINCT\n", "")'
  'DUP-CHECK/same-defect-no-id|rows["FX-002"]["description"] = G.replace(": DISTINCT", ": SAME-DEFECT (see above)"); '"$OBS2"'; od["FX-002"] = ("duplicate-of", "FX-003")'
  'DUP-SAME-OPEN|rows["FX-002"]["description"] = G.replace(": DISTINCT", ": SAME-DEFECT of FX-003")'
  'DUP-SAME-OPEN/wrong-head|rows["FX-002"]["description"] = G.replace(": DISTINCT", ": SAME-DEFECT of FX-003"); '"$OBS2"'; od["FX-002"] = ("duplicate-of", "FX-001")'
  'DUP-SAME-OPEN/head-is-first-id|rows["FX-002"]["description"] = G.replace(": DISTINCT", ": SAME-DEFECT of FX-003 (see also FX-001)"); '"$OBS2"'; od["FX-002"] = ("duplicate-of", "FX-001")'
  'DUP-SAME-OPEN/dangling-superseding|rows["FX-002"]["description"] = G.replace(": DISTINCT", ": SAME-DEFECT of FX-003"); '"$OBS2"'; od["FX-002"] = ("duplicate-of", "FX-999")'
  'DUP-HEAD/target-obsolete|rows["FX-002"]["description"] = G.replace(": DISTINCT", ": SAME-DEFECT of FX-003"); '"$OBS2"'; od["FX-002"] = ("duplicate-of", "FX-003"); rows["FX-003"]["status"] = "Obsolete"; rows["FX-003"]["loc"] = "Fixed"; od["FX-003"] = ("duplicate-of", "FX-001")'
  'DUP-HEAD/two-open-heads|rows["FX-002"]["description"] = G.replace(": DISTINCT", ": SAME-DEFECT of FX-003"); '"$OBS2"'; od["FX-002"] = ("duplicate-of", "FX-003"); rows["FX-003"]["description"] = "nothing shared here. Candidate duplicate: FX-001 (fixture umbrella); merge UNDECIDED."'
  'DUP-UNDECIDED|rows["FX-002"]["description"] = G.replace(": DISTINCT", ": UNDECIDED")'
  'DUP-UNDECIDED/closed|'"$UND"'; '"$OBS2"'; od["FX-002"] = ("not-reproducible", "none")'
  'DUP-STATUS|'"$UND"'; '"$OBS2"'; od["FX-002"] = ("duplicate-of", "FX-003")'
  'OBSOLETE-STALE|rows["FX-002"]["status"] = "Reopened"; od["FX-002"] = ("duplicate-of", "FX-003")'
  'OBSOLETE-STALE/note-names-closed-item|rows["FX-002"]["status"] = "Reopened"; od["FX-002"] = ("duplicate-of", "FX-003"); rows["FX-003"]["status"] = "Done"; rows["FX-003"]["loc"] = "Fixed"; rows["FX-002"]["description"] = G + "\nStale obsolete_details row (engine gap FX-003): kept"'
  'PATH-MISSING|rows["FX-002"]["description"] = G.replace("fx_present", "fx_absent")'
  'PATH-MISSING/decisions|rows["FX-002"]["description"] = G.replace("docs/qa/fx_present/e.txt", "docs/operator_decisions/fx_absent.md")'
)
n=0
for c in "${cases[@]}"; do
  n=$((n + 1)); name=${c%%|*}; snip=${c#*|}; code=${name%%/*}
  mkfixture "$tmp/bad$n.db" "$snip" || { bad "golden-bad $name" "fixture build failed"; continue; }
  expect "golden-bad $name" 1 "^FINDING $code FX-002 " --db "$tmp/bad$n.db" "${F[@]}"
done

# one positive and one negative control needle per SECRET pattern (section 11.4.201(7)(b), 11.4.273(f));
# the strings are assembled from fragments, so this file carries no credential-shaped literal
secrets=(
  'aws-access-key-id|"AK" + "IA" + "Q" * 16|"AK" + "IA" + "Q" * 15'
  'aws-secret-assign|"aws_secret_" + "access_key = " + "a" * 40|"aws_secret_" + "access_key = " + "a" * 39'
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
  'url-userinfo-password|"git+ssh://bob:" + "w" * 6 + "@host"|"git+ssh://bob:" + "w" * 5 + "@host"'
  'bearer-token|"Authorization: " + "Bearer " + "a" * 20|"Authorization: " + "Bearer " + "a" * 19'
  'password-assign|"api_" + "key: \"" + "x" * 8 + "\""|"api_" + "key: \"" + "x" * 7 + "\""'
  'stripe-key|"r" + "k_" + "test_" + "a" * 20|"r" + "k_" + "test_" + "a" * 19'
  'npm-token|"np" + "m_" + "a" * 36|"np" + "m_" + "a" * 35'
  'telegram-bot-token|"12345678" + ":AA" + "a" * 33|"12345678" + ":AA" + "a" * 32'
)
for s in "${secrets[@]}"; do
  pname=${s%%|*}; rest=${s#*|}; pos=${rest%%|*}; neg=${rest#*|}
  n=$((n + 1))
  mkfixture "$tmp/sp$n.db" "rows[\"FX-002\"][\"description\"] = G + \"\\nvalue \" + ($pos) + \" end\"" || { bad "SECRET positive $pname" "fixture build failed"; continue; }
  expect "SECRET positive needle $pname" 1 "^FINDING SECRET FX-002 $pname\$" --db "$tmp/sp$n.db" "${F[@]}"
  mkfixture "$tmp/sn$n.db" "rows[\"FX-002\"][\"description\"] = G + \"\\nvalue \" + ($neg) + \" end\"" || { bad "SECRET negative $pname" "fixture build failed"; continue; }
  expect_silent "SECRET negative needle $pname" SECRET --db "$tmp/sn$n.db" "${F[@]}"
done

# golden-good variants that must stay silent (false-positive guards, section 11.4.201(1))
goods=(
  'shared path named by the Duplicate check line|rows["FX-003"]["description"] = "this open item also edits scripts/fixture_only_tool.sh"; rows["FX-002"]["description"] = G.replace(": DISTINCT", ": DISTINCT-but-similar of FX-003")'
  'SAME-DEFECT closed Obsolete duplicate-of the named id|rows["FX-002"]["description"] = G.replace(": DISTINCT", ": SAME-DEFECT of FX-003"); '"$OBS2"'; od["FX-002"] = ("duplicate-of", "FX-003")'
  'SAME-DEFECT head whose UNDECIDED candidate is closed|rows["FX-002"]["description"] = G.replace(": DISTINCT", ": SAME-DEFECT of FX-003"); '"$OBS2"'; od["FX-002"] = ("duplicate-of", "FX-003"); rows["FX-003"]["description"] = "nothing shared here. Candidate duplicate: FX-001 (fixture umbrella); merge UNDECIDED."; rows["FX-001"]["status"] = "Done"; rows["FX-001"]["loc"] = "Fixed"'
  'UNDECIDED with open candidates on an open item|'"$UND"
  'stale obsolete_details row noted with an open engine item|rows["FX-002"]["status"] = "Reopened"; od["FX-002"] = ("duplicate-of", "FX-003"); rows["FX-002"]["description"] = G + "\nStale obsolete_details row (engine gap FX-003): kept by the engine"'
  'structured line agrees with the column|rows["FX-002"]["rs"] = "UNREPRODUCED"; rows["FX-002"]["description"] = G + "\n**Reproduction:** none — UNREPRODUCED"'
  'shared path named by a closed item only|rows["FX-003"]["description"] = "edits scripts/fixture_only_tool.sh"; rows["FX-003"]["loc"] = "Fixed"; rows["FX-003"]["status"] = "Done"'
  'existing operator_decisions path|rows["FX-002"]["description"] = G.replace("docs/qa/fx_present/e.txt", "docs/operator_decisions/fx_decisions.md")'
  'declared foreign range|rows["FX-002"]["description"] = G.replace("FX-900 of another", "FX-900..FX-903 of another").replace("tracker): FX-900", "tracker): FX-900..FX-903")'
  'label whose extra words are stopwords|rows["FX-002"]["description"] = G.replace("(fixture umbrella)", "(the fixture umbrella, the parent of this one)")'
  'unlabelled id in a clause that shares a title word|rows["FX-002"]["description"] = G.replace("umbrella FX-001 (fixture umbrella)", "see FX-003 for the unrelated part")'
  'mktemp template string|rows["FX-002"]["description"] = G + "\nthe mktemp template tmp." + "X" * 10 + " is named here"'
  'Reopened header lines in the body|rows["FX-002"]["body"] = render("FX-002", rows["FX-002"]).replace("**Type:** Task\n", "**Type:** Task\n**Reopened-Details:** By:AI\n**Evidence:** e\n")'
)
for c in "${goods[@]}"; do
  n=$((n + 1)); name=${c%%|*}; snip=${c#*|}
  mkfixture "$tmp/good$n.db" "$snip" || { bad "golden-good $name" "fixture build failed"; continue; }
  expect "golden-good $name" 0 '^RESULT: PASS ' --db "$tmp/good$n.db" "${F[@]}"
done

# a SECRET finding prints the pattern name, never the matched string (section 11.4.10)
mkfixture "$tmp/sec.db" 'rows["FX-002"]["description"] = G + "\nkey AKIA" + "QQQQRRRRSSSSTTTT"' || exit 2
run_lint "$tmp/out" --db "$tmp/sec.db" "${F[@]}"
if grep -q 'QQQQRRRRSSSSTTTT' "$tmp/out"; then bad "secret value never printed" "the matched string is in the output"
elif grep -q '^FINDING SECRET FX-002 aws-access-key-id$' "$tmp/out"; then ok "secret value never printed"
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
expect "BLIND: database unreadable" 3 'database unreadable' --db "$tmp/junk.db" --ids FX-002
mkfixture "$tmp/empty.db" 'rows.clear()' || exit 2
expect "BLIND: database holds no items" 3 'holds no items' --db "$tmp/empty.db" --ids FX-002
mkfixture "$tmp/null.db" 'rows["FX-002"]["description"] = None; rows["FX-002"]["body"] = ""' || exit 2
expect "BLIND: a NULL description names the item" 3 'NULL title, description, status or location: FX-002' --db "$tmp/null.db" --ids FX-002
# a BLOB state value (the fixture schema has no CHECK) makes the lint raise a TypeError
mkfixture "$tmp/crash.db" 'rows["FX-002"]["body"] = render("FX-002", dict(rows["FX-002"], rs="UNREPRODUCED")); rows["FX-002"]["rs"] = b"x"' || exit 2
expect "BLIND: a crash is BLIND, never a traceback" 3 '^BLIND: the lint crashed \(TypeError' --db "$tmp/crash.db" --ids FX-002
expect "BLIND: unknown id" 3 'not in the database: FX-777' --db "$tmp/good.db" --ids FX-777
expect "BLIND: empty origin selection" 3 'selection is empty' --db "$tmp/good.db" --origin "no such origin text"
expect "BLIND: --prefix that no item carries" 3 'no item in the database carries the prefix ZZ' --db "$tmp/good.db" --ids FX-002 --prefix ZZ
mkfixture "$tmp/pfx.db" 'rows["AA-001"] = dict(title="Alphabetically first prefix", description="an item of another tracker", status="Queued", loc="Issues", rs=None, ivs=None)' || exit 2
expect "prefix auto-detection takes the most common prefix" 0 '^RESULT: PASS selected=1 findings=0 prefix=FX$' --db "$tmp/pfx.db" --origin "Origin: fixture batch" --require-dup-check --repo-root "$tmp/repo"
mkfixture "$tmp/pfx2.db" 'rows["AA-001"] = dict(title="Alphabetically first prefix", description="an item of another tracker", status="Queued", loc="Issues", rs=None, ivs=None); rows["FX-002"]["description"] = G.replace("FX-001 (fixture umbrella)", "FX-099")' || exit 2
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

# ---- the real database: intake batch is clean; reviewer data mutants and replays on COPIES ----
if [ ! -f "$realdb" ]; then
  bad "real database present" "$realdb missing"
else
  O=(--origin "tracker-intake vehicle 2026-11-12" --require-dup-check --repo-root "$root")
  expect "real DB: intake batch clean" 0 '^RESULT: PASS selected=[0-9]+ findings=0 prefix=CON$' --db "$realdb" "${O[@]}"
  # mutate_real <name> <code> <python snippet using con>; setdesc rewrites the description and the
  # copy of it inside body_md (as the engine would); setdesc(..., body=False) leaves body_md alone
  mutate_real() {
    local name=$1 code=$2 snip=$3
    python3 -I - "$realdb" "$tmp/real.db" "$snip" <<'PY' || { bad "$name" "mutation failed"; return; }
import sqlite3, sys
src, dst, snip = sys.argv[1:4]
s = sqlite3.connect("file:%s?mode=ro" % src, uri=True); d = sqlite3.connect(dst)
s.backup(d); s.close()
def desc(i): return d.execute("select description from items where atm_id=?", (i,)).fetchone()[0]
def body(i): return d.execute("select body_md from items where atm_id=?", (i,)).fetchone()[0]
def setdesc(i, t, body=True):
    old = desc(i)
    d.execute("update items set description=? where atm_id=?", (t, i))
    if body:
        b = d.execute("select body_md from items where atm_id=?", (i,)).fetchone()[0]
        assert b.count(old) == 1, "body does not hold the description once"
        d.execute("update items set body_md=? where atm_id=?", (b.replace(old, t), i))
def setbody(i, b): d.execute("update items set body_md=? where atm_id=?", (b, i))
def must(t, a): assert t.count(a) == 1, (a, t.count(a)); return t
def close_dup(i, sup):
    d.execute("update items set status=?, current_location=? where atm_id=?", ("Obsolete (→ Fixed.md)", "Fixed", i))
    d.execute("update items set body_md=replace(body_md, ?, ?) where atm_id=?", ("**Status:** Reopened", "**Status:** Obsolete (→ Fixed.md)", i))
    d.execute("update obsolete_details set reason=?, superseding_item=? where atm_id=?", ("duplicate-of", sup, i))
def reopen(i):
    # back to the open state the engine's reopen gives (the obsolete_details row stays, CON-340)
    d.execute("update items set status=?, current_location=? where atm_id=?", ("Reopened", "Issues", i))
    d.execute("update items set body_md=replace(body_md, ?, ?) where atm_id=?", ("**Status:** Obsolete (→ Fixed.md)", "**Status:** Reopened", i))
R21 = ("Duplicate check (section 11.4.214): SAME-DEFECT of CON-262 (its acceptance criterion already says run_all.sh reports a 77 as SKIP); this item is closed Obsolete, reason duplicate-of, superseding CON-262, and its context is appended to CON-262. CON-243 names the same run_all.sh behaviour (plus tier awareness) and is a second open head; that CON-243 / CON-262 overlap is pre-existing and its merge stays UNDECIDED for the lander or the operator (section 11.4.214(3)). CON-145 and CON-261 name run_all.sh for other defects. Method: every open item compared by title and description word overlap and by shared file names (docs/qa/tracker_intake_2026_11_12_v2/inventory/).")  # the round-2 line of CON-308, verbatim from the round-2 database
def dupline(i, new):
    t = desc(i); ls = [l for l in t.split("\n") if l.startswith("Duplicate check (section 11.4.214):")]
    assert len(ls) == 1; setdesc(i, t.replace(ls[0], new))
exec(snip, {"d": d, "desc": desc, "body": body, "setdesc": setdesc, "setbody": setbody, "must": must,
            "close_dup": close_dup, "dupline": dupline, "R21": R21, "reopen": reopen})
d.commit(); d.close()
PY
    expect "$name" 1 "^FINDING $code " --db "$tmp/real.db" "${O[@]}"
    safe_rm_rf "${tmp:?}/real.db"
  }
  mutate_real "reviewer M2: description diverges from body_md" BODY-SYNC \
    't = desc("CON-313"); setdesc("CON-313", t + "\nan invented path scripts/invented.sh", body=False)'
  mutate_real "reviewer M3: umbrella CON-299 changed to CON-999" XREF-DANGLING \
    't = desc("CON-313"); setdesc("CON-313", must(t, "umbrella CON-299").replace("umbrella CON-299", "umbrella CON-999"))'
  mutate_real "reviewer M7: delete a referenced row" XREF-DANGLING \
    'd.execute("delete from items where atm_id=?", ("CON-262",))'
  mutate_real "reviewer M9: AWS-key-shaped string in CON-333" SECRET \
    't = desc("CON-333"); setdesc("CON-333", t + "\nkey AKIA" + "QQQQRRRRSSSSTTTT")'
  mutate_real "reviewer M10: Acceptance criteria header removed" SECTIONS \
    't = desc("CON-311"); setdesc("CON-311", must(t, "**Acceptance criteria:**").replace("**Acceptance criteria:**", "Acceptance:"))'
  mutate_real "reviewer M11: structured reproduction line vs column" STATE-PROSE \
    't = desc("CON-301"); setdesc("CON-301", t + "\n**Reproduction:** reproduced-live — REPRODUCED")'
  mutate_real "round-2 D1: default mktemp dir in CON-315" EPHEMERAL \
    't = desc("CON-315"); setdesc("CON-315", t + "\nlog /tmp/tmp." + "k3Jx9" + "QvT2a" + "/out.txt")'
  mutate_real "round-2 D1b: all-lowercase 4-character suffix" EPHEMERAL \
    't = desc("CON-315"); setdesc("CON-315", t + "\nsee trackintake." + "zobh" + "/c")'
  mutate_real "round-2 D2: GitLab PAT-shaped string in CON-315" SECRET \
    't = desc("CON-315"); setdesc("CON-315", t + "\ntoken " + "gl" + "pat-" + "Ab3dE" + "f6hIj" + "K9mNo" + "pQrSt")'
  mutate_real "round-2 D3: CON-332 in its round-1 form, no label" XREF-UNLABELLED \
    't = desc("CON-332"); a = "related: anchor section 11.4.296 (an anchor, not a tracker item), not a parent"; setdesc("CON-332", must(t, a).replace(a, "related CON-296, not a parent"))'
  mutate_real "round-2 D3b: a wrong label sharing one title word" XREF-LABEL \
    't = desc("CON-332"); a = "related: anchor section 11.4.296 (an anchor, not a tracker item), not a parent"; setdesc("CON-332", must(t, a).replace(a, "related CON-296 (runner for GitHub issues), not a parent"))'
  mutate_real "round-2 D5: empty body_md on CON-310" BODY-SYNC \
    'setbody("CON-310", "")'
  mutate_real "round-2 D6: contradiction in body_md only" BODY-SYNC \
    'setbody("CON-310", body("CON-310") + "\n\nUpdate: already fixed on main; no work owed.\n")'
  mutate_real "round-2 D7a: CON-308 closed duplicate-of an id that does not exist" DUP-SAME-OPEN \
    'dupline("CON-308", R21); close_dup("CON-308", "CON-999")'
  mutate_real "round-2 D7b: CON-308 superseding swapped to CON-243" DUP-SAME-OPEN \
    'dupline("CON-308", R21); close_dup("CON-308", "CON-243")'
  # CON-243, CON-262, CON-308: since operator decision 8 (2026-11-13) CON-262 is the single open head
  # and CON-243 and CON-308 are Obsolete duplicate-of it; each case below puts back one wrong state
  mutate_real "round-2 D8: Obsolete duplicate-of with the verdict UNDECIDED" DUP-STATUS \
    'dupline("CON-308", "Duplicate check (section 11.4.214): UNDECIDED; candidate duplicates CON-262 (wider SKIP class, run_all.sh labels exit 77 FAIL).")'
  mutate_real "replay R2-1: CON-243 back as a second open head (an UNDECIDED candidate of CON-262)" DUP-HEAD \
    'reopen("CON-243"); t = desc("CON-262"); setdesc("CON-262", t + " Candidate duplicate: CON-243 (the same run_all.sh behaviour plus tier awareness); merge UNDECIDED (section 11.4.214(3)).", body=False)'
  mutate_real "replay R2-1 with the round-2 line of CON-308 verbatim" DUP-HEAD \
    'dupline("CON-308", R21); reopen("CON-243"); t = desc("CON-262"); setdesc("CON-262", t + " Candidate duplicate: CON-243 (the same run_all.sh behaviour plus tier awareness); merge UNDECIDED (section 11.4.214(3)).", body=False)'
  mutate_real "replay I1: CON-308 open while SAME-DEFECT of open CON-262" DUP-SAME-OPEN \
    'reopen("CON-308")'
  mutate_real "UNDECIDED verdict without a candidate on CON-308" DUP-UNDECIDED \
    'dupline("CON-308", "Duplicate check (section 11.4.214): UNDECIDED (no candidate named).")'
  mutate_real "CON-308 reopened with its obsolete_details row and no stale note" OBSOLETE-STALE \
    'reopen("CON-308")'
  mutate_real "replay I2: anchor 296 cited as an item" XREF-LABEL \
    't = desc("CON-332"); i = t.index("section 11.4.296"); setdesc("CON-332", t[:i] + "CON-296 (GitHub issues sync)" + t[i + len("section 11.4.296"):])'
fi

echo "RESULT: pass=$pass fail=$fail"
[ "$fail" = 0 ]
