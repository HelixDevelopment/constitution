#!/usr/bin/env bash
# tests/workable_items/test_intake_lint.sh -- hermetic test of scripts/workable-items/intake_lint.py.
#
# Documentation (section 11.4.18): docs/guides/intake_lint_guide.md.
#
# WHAT  (1) golden-good and golden-bad fixture databases, one golden-bad per finding code;
#       (2) the usage (2) and BLIND (3) exits; (3) the --embeddings TSV namespaces; (4) the
#       reviewer's data mutants M2, M3, M7, M9, M10 and M11 and replays of findings I1 and I2 of the
#       2026-11-12 tracker-intake review, each applied to a scratch COPY of docs/workable_items.db.
#       The real database is opened read-only and never written.
# ENV   INTAKE_LINT       path of the lint to test (default: the repository copy); the mutation
#                         suite points it at a mutated copy
#       INTAKE_LINT_EXTRA extra arguments for every lint call (the mutation suite passes
#                         --no-selfcheck so that these cases, not the built-in needles, must kill)
# EXIT  0 all cases pass; 1 a case failed; 2 setup error.
# EVIDENCE CLASS  gate-logic only (section 11.4.289): it proves the lint's decisions on given text.
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 2
root=$(cd "$here/../.." && pwd) || exit 2
lint=${INTAKE_LINT:-$root/scripts/workable-items/intake_lint.py}
read -r -a extra <<<"${INTAKE_LINT_EXTRA:-}"
realdb=$root/docs/workable_items.db
[ -f "$lint" ] || { echo "setup: lint not found: $lint" >&2; exit 2; }
# shellcheck source=../../scripts/lib/safe_rm.sh
. "$root/scripts/lib/safe_rm.sh" || exit 2
tmp=$(mktemp -d) || exit 2
case "$tmp" in /tmp/*|"${TMPDIR:-/tmp}"/*) ;; *) echo "setup: unexpected mktemp root: $tmp" >&2; exit 2 ;; esac
trap 'safe_rm_rf "${tmp:?}"' EXIT

pass=0 fail=0
ok() { pass=$((pass + 1)); echo "PASS $1"; }
bad() { fail=$((fail + 1)); echo "FAIL $1: $2"; }

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

# ---- fixture database: a minimal items + obsolete_details schema (the columns the lint reads) ----
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
exec(snippet, {"rows": rows, "od": od, "G": G})
c = sqlite3.connect(db)
c.execute("create table items (atm_id text, title text, description text, body_md text, status text,"
          " current_location text, reproduction_state text, investigation_state text)")
c.execute("create table obsolete_details (atm_id text, since text, reason text, superseding_item text, triple_check_evidence text)")
for i, r in rows.items():
    c.execute("insert into items values (?,?,?,?,?,?,?,?)", (i, r["title"], r["description"],
              r.get("body", r["description"] + "\n"), r["status"], r["loc"], r["rs"], r["ivs"]))
for i, (reason, sup) in od.items():
    c.execute("insert into obsolete_details values (?,?,?,?,?)", (i, "2026-11-13", reason, sup, "e"))
c.commit(); c.close()
PY
}
mkdir -p "$tmp/repo/docs/qa/fx_present" && : >"$tmp/repo/docs/qa/fx_present/e.txt"
F=(--origin "Origin: fixture batch" --prefix FX --require-dup-check --repo-root "$tmp/repo")

mkfixture "$tmp/good.db" "pass" || exit 2
expect "golden-good fixture" 0 '^RESULT: PASS selected=1 findings=0 prefix=FX$' --db "$tmp/good.db" "${F[@]}"

# golden-bad, one per finding code: <code> <python snippet>
cases=(
  'XREF-DANGLING|rows["FX-002"]["description"] = G.replace("FX-001 (fixture umbrella)", "FX-099")'
  'XREF-DANGLING/title|rows["FX-002"]["title"] = "Fixture good item, see FX-098"'
  'XREF-DANGLING/foreign-declared-only|rows["FX-002"]["description"] = G.replace("Foreign ids (another tracker): FX-900", "Foreign ids (another tracker): FX-901")'
  'XREF-LABEL|rows["FX-002"]["description"] = G.replace("(fixture umbrella)", "(GitHub issues sync)")'
  'FOREIGN-STALE|rows["FX-002"]["description"] = G.replace("tracker): FX-900", "tracker): FX-900, FX-901")'
  'STATE-PROSE|rows["FX-002"]["description"] = G + "\nReproduction: reproduced-live (written in prose)"'
  'STATE-PROSE/unreproduced-family|rows["FX-002"]["rs"] = "reproduced-live"; rows["FX-002"]["description"] = G + "\nstate: UNREPRODUCED"'
  'STATE-PROSE/investigation|rows["FX-002"]["description"] = G + "\nInvestigation: in-progress"'
  'STATE-PROSE/structured|rows["FX-002"]["description"] = G + "\n**Reproduction:** reproduced-live — REPRODUCED"'
  'SECTIONS|rows["FX-002"]["description"] = G.replace("**Acceptance criteria:**", "Acceptance:")'
  'BODY-SYNC|rows["FX-002"]["body"] = "a body that diverged"'
  'SECRET|rows["FX-002"]["description"] = G + "\nkey AKIA" + "QQQQRRRRSSSSTTTT"'
  'SECRET/title|rows["FX-002"]["title"] = "leak AKIA" + "QQQQRRRRSSSSTTTT"'
  'EPHEMERAL|rows["FX-002"]["description"] = G + "\nsee review_fixture_r1.md"'
  'EPHEMERAL/note-covers-own-line-only|rows["FX-002"]["description"] = G + "\nsecond bundle c.bundle with no note"'
  'SHARED-PATH|rows["FX-003"]["description"] = "this open item also edits scripts/fixture_only_tool.sh"'
  'DUP-CHECK|rows["FX-002"]["description"] = G.replace(": DISTINCT", ": PROBABLY")'
  'DUP-CHECK/missing|rows["FX-002"]["description"] = G.replace("Duplicate check (section 11.4.214): DISTINCT\n", "")'
  'DUP-SAME-OPEN|rows["FX-002"]["description"] = G.replace(": DISTINCT", ": SAME-DEFECT of FX-003")'
  'DUP-SAME-OPEN/wrong-head|rows["FX-002"]["description"] = G.replace(": DISTINCT", ": SAME-DEFECT of FX-003"); rows["FX-002"]["status"] = "Obsolete"; od["FX-002"] = ("duplicate-of", "FX-001")'
  'PATH-MISSING|rows["FX-002"]["description"] = G.replace("fx_present", "fx_absent")'
)
n=0
for c in "${cases[@]}"; do
  n=$((n + 1)); name=${c%%|*}; snip=${c#*|}; code=${name%%/*}
  mkfixture "$tmp/bad$n.db" "$snip" || { bad "golden-bad $name" "fixture build failed"; continue; }
  expect "golden-bad $name" 1 "^FINDING $code FX-002 " --db "$tmp/bad$n.db" "${F[@]}"
done

# golden-good variants that must stay silent (false-positive guards, section 11.4.201(1))
goods=(
  'shared path named by the Duplicate check line|rows["FX-003"]["description"] = "this open item also edits scripts/fixture_only_tool.sh"; rows["FX-002"]["description"] = G.replace(": DISTINCT", ": DISTINCT-but-similar of FX-003")'
  'SAME-DEFECT closed Obsolete duplicate-of the named id|rows["FX-002"]["description"] = G.replace(": DISTINCT", ": SAME-DEFECT of FX-003"); rows["FX-002"]["status"] = "Obsolete"; rows["FX-002"]["loc"] = "Fixed"; od["FX-002"] = ("duplicate-of", "FX-003")'
  'structured line agrees with the column|rows["FX-002"]["rs"] = "UNREPRODUCED"; rows["FX-002"]["description"] = G + "\n**Reproduction:** none — UNREPRODUCED"'
  'shared path named by a closed item only|rows["FX-003"]["description"] = "edits scripts/fixture_only_tool.sh"; rows["FX-003"]["loc"] = "Fixed"; rows["FX-003"]["status"] = "Done"'
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

# ---- usage (2) and BLIND (3) exits ----
expect "usage: no selection" 2 'give --origin or --ids' --db "$tmp/good.db"
expect "usage: unknown --skip-check code" 2 'unknown --skip-check' --db "$tmp/good.db" --ids FX-002 --skip-check NOPE
expect "usage: --repo-root not a directory" 2 'not a directory' --db "$tmp/good.db" --ids FX-002 --repo-root "$tmp/none"
expect "BLIND: database missing" 3 'database not found' --db "$tmp/none.db" --ids FX-002
printf 'not a database\n' >"$tmp/junk.db"
expect "BLIND: database unreadable" 3 'database unreadable' --db "$tmp/junk.db" --ids FX-002
mkfixture "$tmp/empty.db" 'rows.clear()' || exit 2
expect "BLIND: database holds no items" 3 'holds no items' --db "$tmp/empty.db" --ids FX-002
expect "BLIND: unknown id" 3 'not in the database: FX-777' --db "$tmp/good.db" --ids FX-777
expect "BLIND: empty origin selection" 3 'selection is empty' --db "$tmp/good.db" --origin "no such origin text"

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

# ---- the real database: intake batch is clean; reviewer data mutants and I1/I2 replays on COPIES ----
if [ ! -f "$realdb" ]; then
  bad "real database present" "$realdb missing"
else
  O=(--origin "tracker-intake vehicle 2026-11-12" --require-dup-check --repo-root "$root")
  expect "real DB: intake batch clean" 0 '^RESULT: PASS selected=[0-9]+ findings=0 prefix=CON$' --db "$realdb" "${O[@]}"
  # mutate_real <name> <code> <python snippet using con>
  mutate_real() {
    local name=$1 code=$2 snip=$3
    python3 -I - "$realdb" "$tmp/real.db" "$snip" <<'PY' || { bad "$name" "mutation failed"; return; }
import sqlite3, sys
src, dst, snip = sys.argv[1:4]
s = sqlite3.connect("file:%s?mode=ro" % src, uri=True); d = sqlite3.connect(dst)
s.backup(d); s.close()
def desc(i): return d.execute("select description from items where atm_id=?", (i,)).fetchone()[0]
def setdesc(i, t, body=True):
    d.execute("update items set description=? where atm_id=?", (t, i))
    if body: d.execute("update items set body_md=? where atm_id=?", (t + "\n", i))
def must(t, a): assert t.count(a) == 1, (a, t.count(a)); return t
exec(snip, {"d": d, "desc": desc, "setdesc": setdesc, "must": must})
d.commit(); d.close()
PY
    expect "$name" 1 "^FINDING $code " --db "$tmp/real.db" "${O[@]}"
    safe_rm_rf "${tmp:?}/real.db"
  }
  mutate_real "reviewer M2: description diverges from body_md" BODY-SYNC \
    't = desc("CON-313"); d.execute("update items set description=? where atm_id=?", (t + "\nan invented path scripts/invented.sh", "CON-313"))'
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
  mutate_real "replay I1: CON-308 reopened while SAME-DEFECT of open CON-262" DUP-SAME-OPEN \
    'd.execute("update items set status=?, current_location=? where atm_id=?", ("Queued", "Issues", "CON-308")); d.execute("delete from obsolete_details where atm_id=?", ("CON-308",))'
  mutate_real "replay I2: anchor 296 cited as an item" XREF-LABEL \
    't = desc("CON-332"); i = t.index("section 11.4.296"); setdesc("CON-332", t[:i] + "CON-296 (GitHub issues sync)" + t[i + len("section 11.4.296"):])'
fi

echo "RESULT: pass=$pass fail=$fail"
[ "$fail" = 0 ]
