#!/usr/bin/env bash
# test_parse_mutation.sh -- behaviour + paired-mutation test of scripts/catalog-engine/lib/parse_mutation.py (CON-083)
#
# Purpose
#   parse_mutation.py turns a section 1.1 meta-test file into one catalog record per mutation block
#   (`— CM-<ID> mutation: <what> —`). Until this test no test exercised it: its full-suite manifest row said
#   "imported by parse_gate.py; tested by scripts/catalog-engine/tests", but parse_gate.py only mentions it in a
#   comment (the importer is scan.py) and the only test there covers parse_gate.py. This test runs the parser
#   through its real import path on golden fixtures (one record per distinct gate, first block wins, the
#   expect_prebuild_fail window of 12 lines, ATM id extraction, gate-header description inheritance, an
#   unreadable path), and then runs the same checks against deliberately broken copies of the parser, each of
#   which must make a check fail (paired mutants, Constitution 1.1; oracle: SPECIFIED by the parser's header).
# Usage
#   bash scripts/catalog-engine/tests/test_parse_mutation.sh
# Exit codes
#   0 every check passed and every mutant was killed | 1 a check failed or a mutant survived | 2 environment error
# Dependencies
#   bash, python3. Writes only under a mktemp directory removed on exit.
# Classification: universal (Constitution 11.4.17) -- no project literal.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$HERE/../lib/parse_mutation.py"
[ -f "$TOOL" ] || { echo "ENV: parser not found: $TOOL" >&2; exit 2; }
command -v python3 >/dev/null || { echo "ENV: python3 missing" >&2; exit 2; }
# shellcheck source=../../lib/safe_rm.sh
. "$HERE/../../lib/safe_rm.sh" || { echo "ENV: scripts/lib/safe_rm.sh not loadable" >&2; exit 2; }
WORK="$(mktemp -d)" || exit 2
: "${WORK:?}"
trap 'safe_rm_rf "${WORK:?}"' EXIT

pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  PASS  $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL  $1"; }

# ---- golden fixture ------------------------------------------------------------------------------------------------
cat >"$WORK/meta.sh" <<'FIX'
#!/usr/bin/env bash
# ---- Gate CM-PM-ONE: first gate description ----
echo; echo "— CM-PM-ONE mutation: strip the ONE literal (ATM-1234) —"
mutate_x
expect_prebuild_fail "CM-PM-ONE"
restore_x
echo; echo "— CM-PM-ONE mutation: a second block for the same gate must not make a second record —"
echo; echo "— CM-PM-FAR mutation: the assertion is past the 12-line window —"
l1
l2
l3
l4
l5
l6
l7
l8
l9
l10
l11
l12
expect_prebuild_fail "CM-PM-FAR"
echo; echo "— CM-PM-EDGE mutation: the assertion is exactly on the 12th line after the banner —"
e1
e2
e3
e4
e5
e6
e7
e8
e9
e10
e11
expect_prebuild_fail_count 1 "CM-PM-EDGE"
# a cross-reference comment (no em-dash banner) must not register: CM-PM-NOTHERE mutation: no banner
echo "— CM-PM-BARE mutation: —"
FIX

cat >"$WORK/dump.py" <<'PY'
import importlib.util, json, sys
tool, fixture = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("pm_under_test", tool)
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
recs = m.parse_mutation_file(fixture, "meta-test-mutation")
missing = m.parse_mutation_file(fixture + ".does-not-exist", "meta-test-mutation")
print(json.dumps({"recs": recs, "missing": missing}, ensure_ascii=False))
PY

cat >"$WORK/check.py" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
recs = {r["pairs_gate"]: r for r in d["recs"]}
fails = []
def need(name, cond):
    if not cond:
        fails.append(name)
need("ids-exact", sorted(recs) == ["CM-PM-BARE", "CM-PM-EDGE", "CM-PM-FAR", "CM-PM-ONE"])
need("one-record-per-gate", len(d["recs"]) == 4)
need("order-by-line", [r["pairs_gate"] for r in d["recs"]] == ["CM-PM-ONE", "CM-PM-FAR", "CM-PM-EDGE", "CM-PM-BARE"])
one = recs.get("CM-PM-ONE", {})
need("first-block-wins", one.get("description") == "strip the ONE literal (ATM-1234)")
need("one-source-line", one.get("source_line") == 3)
need("one-proves-fail", one.get("bluff_proofed") is True and one.get("derivation_gaps") == [])
need("one-atm", one.get("atm_id") == "ATM-1234")
need("one-gate-desc", one.get("gate_description") == "first gate description")
need("one-type", one.get("type") == "meta-test-mutation" and one.get("id") == "CM-PM-ONE-mutation")
need("one-file", one.get("source_file") == "meta.sh" and one.get("source_path") is None)
need("one-step", one.get("step_by_step", [{}])[0].get("result") == "FAIL-asserted")
far = recs.get("CM-PM-FAR", {})
need("far-window-12", far.get("bluff_proofed") is False
     and far.get("derivation_gaps") == ["expect_prebuild_fail-not-found-in-window"])
need("far-no-atm", far.get("atm_id") is None and far.get("gate_description") == "")
edge = recs.get("CM-PM-EDGE", {})
need("edge-in-window-count-form", edge.get("bluff_proofed") is True)
bare = recs.get("CM-PM-BARE", {})
need("bare-no-description", bare.get("description") == ""
     and "no-mutation-description" in bare.get("derivation_gaps", [])
     and bare.get("name") == "CM-PM-BARE mutation"
     and bare.get("description_quality") == "header-only")
need("missing-file-empty", d["missing"] == [])
need("not-physical-evidence", all(r.get("physical_evidence") is False for r in d["recs"]))
print("FAILED:" + ",".join(fails) if fails else "ALL-OK")
sys.exit(1 if fails else 0)
PY

run_checks() { # run_checks <parser.py> <outdir> ; rc 0 = all checks hold
  local tool="$1" d="$2"
  mkdir -p "$d"
  python3 -I "$WORK/dump.py" "$tool" "$WORK/meta.sh" >"$d/out.json" 2>"$d/err" || { echo "LOAD-FAILED" >"$d/verdict"; return 1; }
  python3 -I "$WORK/check.py" "$d/out.json" >"$d/verdict" 2>&1
}

echo "== real parser"
if run_checks "$TOOL" "$WORK/real"; then ok "real parser: $(cat "$WORK/real/verdict")"; else bad "real parser: $(cat "$WORK/real/verdict")"; fi

# ---- paired mutants: each must break at least one check -------------------------------------------------------------
mutant() { # mutant <name> <python expression transforming source text s>
  local name="$1" expr="$2" mfile="$WORK/m_$1.py"
  python3 -I - "$TOOL" "$mfile" "$expr" <<'PY' || { bad "mutant $name: could not be built"; return; }
import sys
src = open(sys.argv[1], encoding="utf-8").read()
s = src
# eval is safe here: the expression is a string literal written in this test file (the mutant
# table below), never input from outside; it only rewrites the parser source text s.
s = eval(sys.argv[3])
if s == src:
    sys.exit(3)
open(sys.argv[2], "w", encoding="utf-8").write(s)
PY
  if run_checks "$mfile" "$WORK/mut_$name"; then
    bad "mutant $name SURVIVED"
  else
    ok "mutant $name killed ($(cat "$WORK/mut_$name/verdict"))"
  fi
}
echo "== paired mutants"
mutant window11      's.replace("lines[lineno:lineno + 12]", "lines[lineno:lineno + 11]")'
mutant window13      's.replace("lines[lineno:lineno + 12]", "lines[lineno:lineno + 13]")'
mutant no_dedup      's.replace("        if gate_id in seen:\n            continue\n", "")'
mutant no_atm        's.replace("atm_id = \"ATM-%s\" % matm.group(1) if matm else None", "atm_id = None")'
mutant no_hdr        's.replace("gate_hdr_desc.setdefault(mh.group(1), mh.group(2).strip())", "pass")'
mutant no_count_form 's.replace("(?:_count)?", "")'
mutant gap_flip      's.replace("if not proves_fail:\n            # ", "if proves_fail:\n            # ")'
mutant crash_missing 's.replace("    except OSError:\n        return []", "    except ValueError:\n        return []")'
mutant line0         's.replace("enumerate(lines, start=1)", "enumerate(lines, start=0)")'

echo
echo "RESULT: passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
