#!/bin/bash
# Purpose : paired section 1.1 mutations for fc_require_items in lib/consumer_required.sh (review round 2
#           CR-1/CR-2/CR-3 of the full-suite fix vehicle). Copies the helper into a mktemp tree, applies ONE
#           mutant (an exact string replacement whose anchor must occur exactly once), and runs
#           test_consumer_required_helper.sh against the copy (FC_HELPER_UNDER_TEST; Part 4, which runs the
#           real suites, is skipped for a copy). The unmutated copy must pass first (baseline). A mutant is
#           KILLED only when the helper test exits 1 AND prints at least one "NOT ok" line.
# Mutants :
#   MG1  a register with no known id column SKIPs (the CR-1 shape: an unanswerable query read as "absent")
#   MG1b a database the pragma cannot read SKIPs (not a database, unreadable file)
#   MG2  the "no item with the named prefix" condition dropped (CR-3: a register that LOST an item SKIPs)
#   MG3  ticket_id dropped from the id-column candidates (the section 11.4.54 rename)
#   MG5  the prefix character check dropped (ids are interpolated into SQL: A'X-1 would reach the query)
#   MG6  the "table holds at least one item" condition dropped (an empty table SKIPs)
#   MG7  the data query's error returns SKIP (CR3-1, reviewer mutant RMG-A: the pragma answered, the count errors)
#   MG8  no sqlite3 returns SKIP (CR3-1, reviewer mutant RMG-B)
#   MG9  only the first id column found is examined (CR3-2, a register with both columns)
#   Round 5, structural (section 11.4.276(E), review round 4 CR4-1): one mutant per decision leg of the helper; the
#   leg table is in Part 3 of test_consumer_required_helper.sh. RED first: MG10, MG11, MG13, MG14, MG15 SURVIVED the
#   round-4 suite (97/0); MG12 was already killed by other_atm.db (evidence of the round-5 fix vehicle).
#   MG10 (reviewer R4-C, verbatim) the prefix count C3 reads the first id column only (both_lost shape)
#   MG11 (reviewer R4-H, verbatim) only the last id column found is examined (ticket_null shape)
#   MG12 atm_id dropped from the id-column candidates
#   MG13 C3 reads the last id column only
#   MG14 C3 counts the first named prefix only (ids with two prefixes)
#   MG15 C3 counts the last named prefix only
#   Round 6 (review round 5 CR5-1..CR5-4; the operator authorised round 6 for CON-169/CON-174/CON-031 under section
#   11.4.276(G), 2026-11-10): one mutant per remaining input axis, legs L11..L17 in Part 3. RED first: every one
#   below except MG17 SURVIVED the round-5 suite (158/0); MG17 was killed there only through m2_half.
#   MG16 (reviewer RV5-1, verbatim) each id column is read from its first row only (L11 rows; the CR-3 false SKIP)
#   MG17 (reviewer RV5-1b, verbatim) C3 over a two-row sample (L11)
#   MG18 (reviewer RV5-3, verbatim; round-3 RMG-G) the dash dropped from the prefix test (L12)
#   MG19 (reviewer RV5-4, verbatim) id column matched by substring (L13)
#   MG20 (reviewer RV5-5, verbatim) -readonly dropped from the pragma call: an absent path gets a 0-byte file (L14)
#   MG21 (reviewer R4-G) LIKE to GLOB, case-sensitive prefix (L15)
#   MG22 id column matched case-insensitively (L13)
#   MG23 (reviewer R4-I) items counted as non-NULL keys (L16; pins current behaviour, the direction is CON-178's)
#   MG24 trim(k) in the prefix count C3 (L17 whitespace)
#   MG25 the pragma reads the first table of the schema instead of items (L17 other tables)
#   Round 7 (review round 6 CR6-1..CR6-6, N6-1; the last round section 11.4.276(G) allows under the operator decision
#   recorded in CON-031): the twelve reviewer mutants verbatim. RED first: on the round-6 suite RV6-2..RV6-8, RV6-10
#   and RV6-12 SURVIVED (195/0 each); RV6-1, RV6-9 and RV6-11 were already killed. A literal backslash-n in an anchor
#   or a replacement is a newline (RV6-11 spans two lines).
#   RV6-1  C3 over a three-row sample (L11b row count)      RV6-2  C3 over a 1000-row sample (L11b row count; CR6-1)
#   RV6-3  the SKIP line written to stderr (L22 stdout)      RV6-4  the path unquoted in the data query (L18)
#   RV6-5  the pragma read only when items is a table (L19)  RV6-6  items counted as non-empty keys (L20)
#   RV6-7  trim(k) IN in C2 (L17b; the round-6 "equivalent", CR6-2)
#   RV6-8  2>/dev/null dropped from the data query (L23 stderr silence; N6-1)
#   RV6-9  a data-query error read as SKIP (L4 viewfail)     RV6-10 C3 over TEXT keys only (L21 BLOB ids; CR6-6)
#   RV6-11 the SKIP returns 77 instead of exiting (m2 matrix)
#   RV6-12 -readonly dropped from the data query (L14 shim log; the round-6 "equivalent" RV5-5b, CR6-3)
#   Round 8 (review round 7 CR7-1..CR7-4; the operator authorised round 8 for this item on 2026-11-11, section
#   11.4.276(E)(3)/(G), scoped to the round-7 findings): reviewer mutants verbatim. RED first: on the round-7 suite
#   (309/0) RV7-4, RV7-7, RV7-10 and CR7-2 SURVIVED; RV7-11 was already killed (L14 side files). A row may carry
#   several anchor/replacement pairs (TAB separated); every anchor must occur exactly once when it is applied.
#   RV7-4  the data query opens file:<db>?immutable=1 (-readonly kept): committed WAL content is not read (L26)
#   RV7-7  both calls read the path through "$(printf '%s' ...)", which strips a trailing newline (L28)
#   RV7-10 the prefix classes [![:upper:]] / [![:upper:][:digit:]] instead of [A-Z] (L29, UTF-8 locales, bash)
#   RV7-11 the data query opens file:<db>?nolock=1 (L14 side files)
#   CR7-2  the column subquery filtered on k (WHERE k IS NOT ''), the former registry row from-items-sample.2 (L27)
# Systematic sweep (round 7, closes the class, section 11.4.274): `--sweep [JOBS]` generates EVERY single-edit
#   mutant of the helper's SQL clauses, shell tests and connectives, greps, redirections and exit codes (the
#   operator catalogue OPS in the embedded sweep below), checks with independent site enumerators that every such
#   site of the helper is touched by at least one mutant, runs the unmutated copy through the same path first (the
#   control), runs every mutant through the helper test and requires the survivors to be EXACTLY the registered
#   equivalents in consumer_required_equivalents.tsv (each with its proof). Every run of this file (with or without
#   mutant ids) also runs the cheap `check`: no uncovered site and no stale registry key, so an edit of the helper
#   that the sweep has not seen fails here.
# Equivalents: the reasoned-equivalent notes of rounds 4 to 6 are replaced by the registry
#   consumer_required_equivalents.tsv, one row per sweep mutant that cannot be killed, each with its proof, checked
#   on every run. Round 8 adds the param class (parameter expansions, shift and argument count, the relative-path
#   root, the SQL quoting of an id, the quoting of the db path, unset) and a per-run timeout (FC_SWEEP_TIMEOUT,
#   default 1800 s; a TIMEOUT mutant fails the verdict, review round 7 N7-2). The sweep enumerates single edits of
#   those classes only; command substitutions, word splitting of the path, locale classes and multi-edit mutants are
#   pinned by the hand table below (RV7-7, RV7-10), not claimed closed by the sweep (CR7-4). --sweep is run on demand
#   (about an hour at JOBS 8): the manifest runs this file without it, so routinely only the cheap check runs.
#   Corrected in round 7 (review round 6, CR6-2 and CR6-3): `trim(k) IN` in C2 and `-readonly`
#   dropped from the data query are NOT equivalent; both are now killed (RV6-7 by l17b_lead953, RV6-12 by the L14
#   read-only shim). R4-D (C2 over one column), R4-E (UNION) and R4-J (the C2 clause dropped) are covered by the
#   registry's Lemma L rows; R4-F (`-n "$_fci_key"`) is not a single-edit sweep mutant and stays a reasoned note:
#   _fci_src and _fci_key are appended in the same branch, so both are set or both are empty.
# Round 5 pinned R4-G and R4-I to CON-178; round 6 adopted them as MG21 and MG23 with fixtures (see above).
# Usage   : bash scripts/fastcycle/tests/test_consumer_required_mutations.sh [MUTANT_ID...]
#           bash scripts/fastcycle/tests/test_consumer_required_mutations.sh --sweep [JOBS]   (default JOBS 4)
# Exit    : 0 baseline passes and every selected mutant is killed (with --sweep: the sweep verdict holds); 1 otherwise; 77 (reason=topology_unsupported)
#           when sqlite3 is absent (the fixtures cannot be built, so no mutant could be killed).
# Safety  : one mktemp -d root, removed with safe_rm_rf restricted to it; $HOME is never reassigned.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
CANON="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=../../../scripts/lib/safe_rm.sh
. "$CANON/scripts/lib/safe_rm.sh"
command -v sqlite3 >/dev/null 2>&1 || { echo "SKIP: sqlite3 is not installed, the fixture DBs cannot be built reason=topology_unsupported"; exit 77; }
W="$(mktemp -d "${TMPDIR:-/tmp}/consumer_required_mut.XXXXXX")" || { echo "mktemp failed" >&2; exit 2; }
export SAFE_RM_ALLOWED_ROOTS="$W"
trap 'safe_rm_rf "${W:?}"' EXIT
REG="$HERE/consumer_required_equivalents.tsv"
SWEEP=0; JOBS=4
if [ "${1:-}" = "--sweep" ]; then
  SWEEP=1; shift
  if [ $# -gt 0 ]; then
    case $1 in ''|*[!0-9]*|0) echo "usage: --sweep [JOBS], JOBS a positive integer" >&2; exit 2 ;; esac
    JOBS=$1; shift
  fi
  [ $# -eq 0 ] || { echo "usage: --sweep [JOBS] takes no mutant ids" >&2; exit 2; }
fi
cat >"$W/sweep.py" <<'SWEEPPY'
import hashlib, os, re, subprocess, sys, concurrent.futures as cf
# usage: sweep.py gen HELPER OUTDIR            -> writes OUTDIR/<key>.sh, OUTDIR/index.tsv, OUTDIR/uncovered.txt, prints the site census
#        sweep.py run HELPER OUTDIR TEST JOBS  -> baseline control, then TEST with FC_HELPER_UNDER_TEST=<mutant>; OUTDIR/results.tsv
#        sweep.py check OUTDIR REGISTRY        -> exit 1 on an uncovered site or a stale registry key (cheap, no test run)
#        sweep.py verdict OUTDIR REGISTRY      -> exit 1 unless the survivors are exactly the registered equivalents
# Operators: (category, id, regex, replacement list). Each regex is applied at EVERY match in every code line (a line
# that is not a comment), one match per mutant, so every SQL clause, shell test, grep, redirection and exit code of the
# helper gets its single-edit mutants. Keys are stable across unrelated edits: op|sha8(original line)|occurrence.
OPS = [
 # SQL
 ("sql", "count-star-to-k",   r"COUNT\(\*\)", ["COUNT(k)"]),
 ("sql", "distinct-dropped",  r"COUNT\(DISTINCT k\)", ["COUNT(k)"]),
 ("sql", "union-all",         r"UNION ALL", ["UNION"]),
 ("sql", "in-negated",        r" IN \(", [" NOT IN ("]),
 ("sql", "in-trim",           r"WHERE k IN", ["WHERE trim(k) IN", "WHERE lower(k) IN", "WHERE upper(k) IN"]),
 ("sql", "like-to-glob",      r"k LIKE '\$_fci_p-%'", ["k GLOB '$_fci_p-*'", "trim(k) LIKE '$_fci_p-%'", "k LIKE '$_fci_p%'",
                                                        "k LIKE '$_fci_p-_%'", "k LIKE '%$_fci_p-%'", "k NOT LIKE '$_fci_p-%'"]),
 ("sql", "or-to-and",         r" OR \}", [" AND }"]),
 ("sql", "from-items-sample", r"AS k FROM items\"", ["AS k FROM items LIMIT 1\"", "AS k FROM items WHERE rowid > 1\"",
                                                    "AS k FROM items WHERE k IS NOT ''\""]),
 ("sql", "c3-sample",         r"FROM \(\$_fci_src\) WHERE \$_fci_like", ["FROM ($_fci_src LIMIT 1000) WHERE $_fci_like",
                                                                       "FROM ($_fci_src LIMIT 10000) WHERE $_fci_like",
                                                                       "FROM ($_fci_src) WHERE typeof(k)='text' AND ($_fci_like)"]),
 ("sql", "c1-source",         r"SELECT \(SELECT COUNT\(\*\) FROM items\)", ["SELECT (SELECT COUNT(*) FROM items WHERE rowid > 1)",
                                                                           "SELECT (SELECT 1)", "SELECT (SELECT COUNT(*) FROM items LIMIT 0)"]),
 ("sql", "pragma-table",      r"pragma_table_info\('items'\)", ["pragma_table_info('item')", "pragma_table_info('ITEMS')"]),
 ("sql", "pragma-column",     r"SELECT name FROM pragma", ["SELECT lower(name) FROM pragma", "SELECT type FROM pragma"]),
 ("sql", "readonly-flag",     r"-readonly ", [""]),
 ("sql", "separator",         r"-separator ' '", ["-separator ','", ""]),
 ("sql", "candidate-cols",    r"for _fci_c in atm_id ticket_id;", ["for _fci_c in atm_id;", "for _fci_c in ticket_id;",
                                                                    "for _fci_c in ticket_id atm_id;"]),
 # shell tests and connectives
 ("test", "gt",   r"-gt ", ["-ge ", "-lt ", "-ne "]),
 ("test", "lt",   r"-lt ", ["-le ", "-gt ", "-ne "]),
 ("test", "eq",   r"-eq ", ["-ne ", "-le ", "-ge "]),
 ("test", "z",    r"\[ -z ", ["[ -n "]),
 ("test", "n",    r"\[ -n ", ["[ -z "]),
 ("test", "e",    r"\[ -e ", ["[ ! -e ", "[ -f "]),
 ("test", "neq",  r" != ", [" = "]),
 ("test", "and",  r" && ", [" || "]),
 ("test", "or",   r" \|\| ", [" && "]),
 ("test", "argc", r"\[ \$# -eq 3 \]", ["[ $# -ge 1 ]", "true"]),
 ("test", "case-alt", r"''\|", [""]),
 ("test", "case-pfx", r"\[!A-Z\]\*\|", [""]),
 ("test", "case-cls", r"\*\[!A-Z0-9\]\*", ["*[!A-Z]*"]),
 ("test", "case-num", r"\*\[!0-9\]\*", ["*[!0-9a-z]*"]),
 ("test", "pfx-dedup", r'\*" \$_fci_p "\*\) ;;', ['*"$_fci_p"*) ;;']),
 # greps
 ("grep", "grep-x",   r"grep -qx ", ["grep -q ", "grep -qix ", "grep -x ", "grep -qxF "]),
 ("grep", "grep-q",   r"grep -q ", ["grep "]),
 # redirections
 ("redir", "devnull-err", r" 2>/dev/null", [""]),
 ("redir", "devnull-all", r" >/dev/null 2>&1", [" 2>&1", ""]),
 ("redir", "skip-to-err", r'reason=topology_unsupported"$', ['reason=topology_unsupported" >&2']),
 ("redir", "err-dropped", r'" >&2;', ['";']),
 # exit codes
 ("exit", "exit77", r"exit 77", ["exit 0", "exit 1", "return 77"]),
 ("exit", "exit2",  r"exit 2", ["exit 0", "exit 77", "return 2"]),
 ("exit", "ret0",   r"return 0", ["return 1", '{ echo "SKIP: m reason=topology_unsupported"; exit 77; }']),
 ("sql", "c2-sample", r"COUNT\(DISTINCT k\) FROM \(\$_fci_src\)", ["COUNT(DISTINCT k) FROM (SELECT * FROM ($_fci_src) LIMIT 1)"]),
 ("sql", "c2-const",  r"\(SELECT COUNT\(DISTINCT k\)", ["(SELECT 0*COUNT(DISTINCT k)", "(SELECT 1+COUNT(DISTINCT k)"]),
 ("sql", "c3-const",  r"\(SELECT COUNT\(\*\) FROM \(\$_fci_src\)", ["(SELECT 1+COUNT(*) FROM ($_fci_src)", "(SELECT 0*COUNT(*) FROM ($_fci_src)"]),
 ("sql", "src-select", r"SELECT \$_fci_c AS k", ["SELECT DISTINCT $_fci_c AS k", "SELECT upper($_fci_c) AS k", "SELECT NULL AS k"]),
 ("test", "case-subject", r"case \$\w+ in", ["case x in"]),
 # word splitting of the three counts
 ("test", "split", r"set -- \$_fci_q", ['set -- "$_fci_q"']),
 # parameter expansions, arguments and statements (round 8, review round 7 CR7-4): the helper lines that had no
 # sweep mutant (relative-path root, shift and argument count, id split, IN list, key list, unset)
 ("param", "alt",       r":\+", [":-", "+"]),
 ("param", "pfx-strip", r"%%-\*", ["%-*"]),
 ("param", "num-strip", r"#\*-\}", ["##*-}"]),
 ("param", "shift",     r"; shift$", [""]),
 ("param", "arg1",      r"=\$1;", ["=$2;"]),
 ("param", "argc-need", r"=\$#;", ["=1;", "=0;"]),
 ("param", "root",      r"\$_fcr_root/", [""]),
 ("param", "sql-quote", r"'\$_fci_id'", ["$_fci_id"]),
 ("param", "db-quote",  r'"\$_fci_db"', ["$_fci_db"]),
 ("param", "unset",     r"^\s*unset \S.*$", ["  :"]),
]
# Independent site enumerators: every site of each class must be touched by at least one generated mutant.
SITES = [
 ("sql",   r"\bSELECT\b|\bFROM\b|\bWHERE\b|COUNT\(|UNION ALL|\bIN \(|\bLIKE\b|\bOR\b|pragma_table_info|-readonly|-separator"),
 ("test",  r"\[ [^]]* \]|&&|\|\||case \$\S+ in"),
 ("grep",  r"\bgrep -\w+"),
 ("redir", r"[0-9]?>/dev/null|>&2|2>&1"),
 ("exit",  r"\bexit [0-9]+|\breturn [0-9]+"),
 ("param", r"\$\{[^}]*\}|\bunset\b|\bshift\b|=\$#;|=\$1;|\$_fcr_root/|'\$_fci_id'|\"\$_fci_db\""),
]

def code_lines(src):
    for i, l in enumerate(src.split("\n")):
        if l.lstrip().startswith("#") or not l.strip():
            continue
        yield i, l

def gen(helper, out):
    src = open(helper).read()
    lines = src.split("\n")
    os.makedirs(out, exist_ok=True)
    idx, sites, seen = [], {}, set()
    dup = {}
    for i, l in code_lines(src):
        h = hashlib.sha256(l.encode()).hexdigest()[:8]
        dup[h] = dup.get(h, -1) + 1
        if dup[h]:
            h = "%s~%d" % (h, dup[h])   # the k-th identical code line (for example the three `    exit 77` lines)
        for cat, op, rx, reps in OPS:
            for occ, m in enumerate(re.finditer(rx, l)):
                sites.setdefault(cat, set()).add((i + 1, m.start()))
                for ri, rep in enumerate(reps):
                    nl = l[:m.start()] + rep + l[m.end():]
                    if nl == l:
                        continue
                    key = "%s.%d|%s|%d" % (op, ri, h, occ)
                    if key in seen:
                        continue
                    seen.add(key)
                    ml = list(lines); ml[i] = nl
                    fn = re.sub(r"[^A-Za-z0-9_.-]", "_", key) + ".sh"
                    open(os.path.join(out, fn), "w").write("\n".join(ml))
                    idx.append((key, fn, cat, str(i + 1), l.strip()[:60], nl.strip()[:60]))
    with open(os.path.join(out, "index.tsv"), "w") as f:
        for r in idx:
            f.write("\t".join(r) + "\n")
    spans = {}
    for i, l in code_lines(src):
        for cat, op, rx, reps in OPS:
            for m in re.finditer(rx, l):
                spans.setdefault(i, []).append((m.start(), m.end()))
    unc = []
    for cat, rx in SITES:
        tot = 0
        for i, l in code_lines(src):
            for m in re.finditer(rx, l):
                tot += 1
                if not any(a < m.end() and m.start() < b for a, b in spans.get(i, [])):
                    unc.append("%s line %d col %d [%s] in: %s" % (cat, i + 1, m.start(), m.group(0), l.strip()[:70]))
        print("sites %s=%d" % (cat, tot))
    with open(os.path.join(out, "uncovered.txt"), "w") as f:
        f.write("".join(u + "\n" for u in unc))
    print("uncovered_sites=%d" % len(unc))
    print("mutants=%d" % len(idx))

TIMEOUT = int(os.environ.get("FC_SWEEP_TIMEOUT", "1800"))   # seconds per helper-test run (N7-2: a hanging mutant)

def run_one(test, path):
    if subprocess.run(["sh", "-n", path], capture_output=True).returncode != 0:
        return "invalid", 0
    env = dict(os.environ, FC_HELPER_UNDER_TEST=os.path.abspath(path))   # the test links it: a relative path dangles
    try:
        r = subprocess.run(["bash", test], capture_output=True, text=True, env=env, timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        return "timeout", 0   # neither killed nor survived: the verdict fails on it
    n = sum(1 for x in r.stdout.splitlines() if x.startswith("NOT ok"))
    return ("killed" if r.returncode == 1 and n > 0 else "survived"), n

def run(helper, out, test, jobs):
    idx = [l.rstrip("\n").split("\t") for l in open(os.path.join(out, "index.tsv"))]
    # control: the unmutated helper must pass through the same path first, else every "kill" says nothing
    base = os.path.join(out, "baseline_copy.sh")
    open(base, "w").write(open(helper).read())
    v, n = run_one(test, base)
    if v != "survived" or n != 0:   # a baseline timeout aborts here too
        sys.exit("BASELINE FAIL: the unmutated helper copy does not pass through the sweep's own path (%s, %d NOT ok)" % (v, n))
    print("baseline: the unmutated helper copy passes through the sweep path")
    res = {}
    with cf.ThreadPoolExecutor(max_workers=int(jobs)) as ex:
        futs = {ex.submit(run_one, test, os.path.join(out, r[1])): r for r in idx}
        for f in cf.as_completed(futs):
            r = futs[f]; res[r[0]] = f.result()
    with open(os.path.join(out, "results.tsv"), "w") as f:
        for r in idx:
            v, n = res[r[0]]
            f.write("\t".join([r[0], v, str(n), r[3], r[4], r[5]]) + "\n")
    print("results killed=%d survived=%d invalid=%d timeout=%d" % tuple(sum(1 for v in res.values() if v[0] == k) for k in ("killed", "survived", "invalid", "timeout")))

def registry(path):
    reg = {}
    for l in open(path):
        if l.startswith("#") or not l.strip():
            continue
        k, proof = l.rstrip("\n").split("\t", 1)
        if not proof.strip():
            sys.exit("registry row %s has no proof" % k)
        reg[k] = proof
    return reg

def check(out, reg_path):
    """cheap: every registered equivalent is still a generated mutant, and no site is uncovered"""
    keys = {l.split("\t", 1)[0] for l in open(os.path.join(out, "index.tsv"))}
    reg = registry(reg_path)
    stale = sorted(set(reg) - keys)
    unc = open(os.path.join(out, "uncovered.txt")).read().split("\n")
    unc = [u for u in unc if u]
    print("check generated=%d registered=%d stale=%d uncovered=%d" % (len(keys), len(reg), len(stale), len(unc)))
    for k in stale:
        print("STALE registry key (no such mutant; the helper line changed): %s" % k)
    for u in unc:
        print("UNCOVERED site: %s" % u)
    return 0 if not stale and not unc else 1

def verdict(out, reg_path):
    """after run: the survivors are exactly the registered equivalents"""
    reg = registry(reg_path)
    res = [l.rstrip("\n").split("\t") for l in open(os.path.join(out, "results.tsv"))]
    surv = {r[0] for r in res if r[1] == "survived"}
    inval = [r[0] for r in res if r[1] == "invalid"]
    bad = 0
    for k in sorted(surv - set(reg)):
        r = [x for x in res if x[0] == k][0]
        print("SURVIVOR not registered: %s line %s: [%s] -> [%s]" % (k, r[3], r[4], r[5])); bad += 1
    for k in sorted(set(reg) - surv):
        print("REGISTERED equivalent is not a survivor (killed or not generated; drop it): %s" % k); bad += 1
    for k in inval:
        print("INVALID mutant (does not parse; the operator needs a fix): %s" % k); bad += 1
    for k in [r[0] for r in res if r[1] == "timeout"]:
        print("TIMEOUT mutant (the helper test did not finish within FC_SWEEP_TIMEOUT): %s" % k); bad += 1
    print("verdict mutants=%d killed=%d equivalent=%d unregistered_survivors=%d stale=%d invalid=%d" % (
        len(res), sum(1 for r in res if r[1] == "killed"), len(surv & set(reg)), len(surv - set(reg)),
        len(set(reg) - surv), len(inval)))
    return 1 if bad else 0

if __name__ == "__main__":
    if sys.argv[1] == "gen":
        gen(sys.argv[2], sys.argv[3])
    elif sys.argv[1] == "run":
        run(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5])
    elif sys.argv[1] == "check":
        sys.exit(check(sys.argv[2], sys.argv[3]))
    elif sys.argv[1] == "verdict":
        sys.exit(verdict(sys.argv[2], sys.argv[3]))
SWEEPPY
# the cheap check, on every run: every site of the helper is touched by a generated mutant, and every registered
# equivalent still names a generated mutant (an edit of the helper that the sweep has not seen fails here)
if python3 -I "$W/sweep.py" gen "$HERE/lib/consumer_required.sh" "$W/sweep" >"$W/sweep_gen.log" 2>&1 \
   && python3 -I "$W/sweep.py" check "$W/sweep" "$REG" >"$W/sweep_check.log" 2>&1; then
  echo "ok   sweep check: $(grep '^mutants=' "$W/sweep_gen.log"), $(cat "$W/sweep_check.log" | head -1)"
else
  echo "FAIL sweep check:"; cat "$W/sweep_gen.log" "$W/sweep_check.log" 2>/dev/null; exit 1
fi
if [ "$SWEEP" = 1 ]; then
  python3 -I "$W/sweep.py" run "$HERE/lib/consumer_required.sh" "$W/sweep" "$HERE/test_consumer_required_helper.sh" "$JOBS" || exit 1
  python3 -I "$W/sweep.py" verdict "$W/sweep" "$REG"; rc=$?
  awk -F'\t' '{print $2"\t"$1"\tline "$4"\t"$3" NOT ok"}' "$W/sweep/results.tsv" | sort
  exit "$rc"
fi

MUTANTS=$(cat <<'EOF'
MG1	  [ -n "$_fci_src" ] || return 0	  [ -n "$_fci_src" ] || { echo "SKIP: m reason=topology_unsupported"; exit 77; }
MG1b	"SELECT name FROM pragma_table_info('items');" 2>/dev/null) || return 0	"SELECT name FROM pragma_table_info('items');" 2>/dev/null) || { echo "SKIP: m reason=topology_unsupported"; exit 77; }
MG2	[ "$2" -lt "$_fci_need" ] && [ "$3" -eq 0 ]; then	[ "$2" -lt "$_fci_need" ]; then
MG3	  for _fci_c in atm_id ticket_id; do	  for _fci_c in atm_id; do
MG5	    case $_fci_p in ''|[!A-Z]*|*[!A-Z0-9]*) echo	    case $_fci_p in ''|[!A-Z]*) echo
MG6	  if [ "$1" -gt 0 ] && [ "$2" -lt "$_fci_need" ]	  if [ "$2" -lt "$_fci_need" ]
MG7	FROM ($_fci_src) WHERE $_fci_like);" 2>/dev/null) || return 0	FROM ($_fci_src) WHERE $_fci_like);" 2>/dev/null) || { echo "SKIP: m reason=topology_unsupported"; exit 77; }
MG8	  command -v sqlite3 >/dev/null 2>&1 || return 0	  command -v sqlite3 >/dev/null 2>&1 || { echo "SKIP: m reason=topology_unsupported"; exit 77; }
MG9	      _fci_key="$_fci_key${_fci_key:+,}$_fci_c"	      _fci_key="$_fci_key${_fci_key:+,}$_fci_c"; break
MG10	(SELECT COUNT(*) FROM ($_fci_src) WHERE $_fci_like)	(SELECT COUNT(*) FROM (${_fci_src%% UNION ALL*}) WHERE $_fci_like)
MG11	_fci_src="$_fci_src${_fci_src:+ UNION ALL }SELECT $_fci_c AS k FROM items"	_fci_src="SELECT $_fci_c AS k FROM items"
MG12	  for _fci_c in atm_id ticket_id; do	  for _fci_c in ticket_id; do
MG13	(SELECT COUNT(*) FROM ($_fci_src) WHERE $_fci_like)	(SELECT COUNT(*) FROM (${_fci_src##* UNION ALL }) WHERE $_fci_like)
MG14	for _fci_p in $_fci_pfx; do _fci_like="$_fci_like${_fci_like:+ OR }k LIKE '$_fci_p-%'"; done	for _fci_p in $_fci_pfx; do _fci_like="k LIKE '$_fci_p-%'"; break; done
MG15	for _fci_p in $_fci_pfx; do _fci_like="$_fci_like${_fci_like:+ OR }k LIKE '$_fci_p-%'"; done	for _fci_p in $_fci_pfx; do _fci_like="k LIKE '$_fci_p-%'"; done
MG16	SELECT $_fci_c AS k FROM items"	SELECT $_fci_c AS k FROM items WHERE rowid = (SELECT MIN(rowid) FROM items)"
MG17	(SELECT COUNT(*) FROM ($_fci_src) WHERE $_fci_like)	(SELECT COUNT(*) FROM (SELECT * FROM ($_fci_src) LIMIT 2) WHERE $_fci_like)
MG18	k LIKE '$_fci_p-%'"	k LIKE '$_fci_p%'"
MG19	grep -qx "$_fci_c"	grep -q "$_fci_c"
MG20	_fci_cols=$(sqlite3 -readonly "$_fci_db"	_fci_cols=$(sqlite3 "$_fci_db"
MG21	k LIKE '$_fci_p-%'"	k GLOB '$_fci_p-*'"
MG22	grep -qx "$_fci_c"	grep -qix "$_fci_c"
MG23	SELECT (SELECT COUNT(*) FROM items), 	SELECT (SELECT COUNT(k) FROM ($_fci_src)), 
MG24	}k LIKE '$_fci_p-%'"	}trim(k) LIKE '$_fci_p-%'"
MG25	pragma_table_info('items')	pragma_table_info((SELECT name FROM sqlite_master WHERE type='table' ORDER BY rowid LIMIT 1))
RV6-1	(SELECT COUNT(*) FROM ($_fci_src) WHERE $_fci_like)	(SELECT COUNT(*) FROM (SELECT * FROM ($_fci_src) LIMIT 3) WHERE $_fci_like)
RV6-2	(SELECT COUNT(*) FROM ($_fci_src) WHERE $_fci_like)	(SELECT COUNT(*) FROM (SELECT * FROM ($_fci_src) LIMIT 1000) WHERE $_fci_like)
RV6-3	found $2 of $_fci_need) reason=topology_unsupported"	found $2 of $_fci_need) reason=topology_unsupported" >&2
RV6-4	sqlite3 -readonly -separator ' ' "$_fci_db"	sqlite3 -readonly -separator ' ' $_fci_db
RV6-5	pragma_table_info('items');	pragma_table_info('items') WHERE (SELECT type FROM sqlite_master WHERE name='items')='table';
RV6-6	SELECT (SELECT COUNT(*) FROM items), 	SELECT (SELECT COUNT(*) FROM ($_fci_src) WHERE k IS NOT ''), 
RV6-7	WHERE k IN ($_fci_in)	WHERE trim(k) IN ($_fci_in)
RV6-8	WHERE $_fci_like);" 2>/dev/null) || return 0	WHERE $_fci_like);") || return 0
RV6-9	WHERE $_fci_like);" 2>/dev/null) || return 0	WHERE $_fci_like);" 2>/dev/null) || { echo "SKIP: x reason=topology_unsupported"; exit 77; }
RV6-10	FROM ($_fci_src) WHERE $_fci_like)	FROM ($_fci_src) WHERE typeof(k)='text' AND ($_fci_like))
RV6-11	found $2 of $_fci_need) reason=topology_unsupported"\n    exit 77	found $2 of $_fci_need) reason=topology_unsupported"\n    return 77
RV6-12	sqlite3 -readonly -separator	sqlite3 -separator
RV7-4	sqlite3 -readonly -separator ' ' "$_fci_db"	sqlite3 -readonly -separator ' ' "file:$_fci_db?immutable=1"
RV7-7	sqlite3 -readonly "$_fci_db"	sqlite3 -readonly "$(printf '%s' "$_fci_db")"	-separator ' ' "$_fci_db"	-separator ' ' "$(printf '%s' "$_fci_db")"
RV7-10	''|[!A-Z]*|*[!A-Z0-9]*)	''|[![:upper:]]*|*[![:upper:][:digit:]]*)
RV7-11	sqlite3 -readonly -separator ' ' "$_fci_db"	sqlite3 -readonly -separator ' ' "file:$_fci_db?nolock=1"
CR7-2	AS k FROM items"	AS k FROM items WHERE k IS NOT ''"
CON184-M3	|*[!A-Z0-9]*)	|*[![:alnum:]]*)
EOF
)

run_helper() { # $1 helper copy -> rc of the helper test; log in $1.log
  FC_HELPER_UNDER_TEST="$1" bash "$HERE/test_consumer_required_helper.sh" >"$1.log" 2>&1
}
cp "$HERE/lib/consumer_required.sh" "$W/base.sh"
run_helper "$W/base.sh"; rc=$?
if [ "$rc" = 0 ] || [ "$rc" = 77 ] && ! grep -q '^NOT ok' "$W/base.sh.log"; then
  echo "ok   baseline: the unmutated helper copy passes ($(grep '^SUMMARY' "$W/base.sh.log"))"
else
  echo "FAIL baseline: the unmutated helper copy fails (rc $rc): $(grep -m3 '^NOT ok' "$W/base.sh.log" | tr '\n' ' '); nothing concluded"
  exit 1
fi
killed=0; survived=0; bad=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  id=${line%%$'\t'*}; rest=${line#*$'\t'}
  if [ $# -gt 0 ]; then case " $* " in *" $id "*) ;; *) continue;; esac; fi
  m="$W/$id.sh"
  if ! python3 -I - "$HERE/lib/consumer_required.sh" "$m" "$rest" <<'PY'
import sys
src, dst, rest = sys.argv[1:4]
f = rest.split("\t")   # anchor TAB replacement, repeated for a multi-edit mutant (RV7-7 edits two calls)
if len(f) % 2:
    sys.exit("odd number of fields: anchor/replacement pairs expected")
s = open(src).read()
for old, new in zip(f[0::2], f[1::2]):
    old, new = old.replace("\\n", "\n"), new.replace("\\n", "\n")   # a literal backslash-n in the table is a newline
    if s.count(old) != 1:
        sys.exit("anchor occurs %d times: %s" % (s.count(old), old[:60]))
    s = s.replace(old, new)
open(dst, "w").write(s)
PY
  then echo "BAD  $id: mutation not applicable"; bad=$((bad+1)); continue; fi
  sh -n "$m" || { echo "BAD  $id: the mutant does not parse"; bad=$((bad+1)); continue; }
  run_helper "$m"; rc=$?
  n=$(grep -c '^NOT ok' "$m.log")
  if [ "$rc" = 1 ] && [ "$n" -gt 0 ]; then
    echo "killed $id ($n failing check(s): $(grep -m2 '^NOT ok' "$m.log" | cut -c8-100 | tr '\n' ';'))"; killed=$((killed+1))
  else echo "SURVIVED $id (rc $rc, $n NOT ok lines)"; survived=$((survived+1)); fi
done <<< "$MUTANTS"
echo "SUMMARY mutants=$((killed+survived+bad)) killed=$killed survivors=$survived not_applicable=$bad"
[ "$survived" -eq 0 ] && [ "$bad" -eq 0 ]
