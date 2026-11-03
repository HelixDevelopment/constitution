#!/usr/bin/env bash
# scripts/gates/cm_gate_env_reads_allowlisted.sh -- CM-GATE-ENV-READS-ALLOWLISTED (11.4.201(6)-(8), 11.4.273, 11.4.276 round 8).
#
# A gate verdict must not be changeable by an ambient environment variable. Every variable a verdict-bearing gate
# (scripts/gates/cm_*.sh, minus *_mutation_test.sh and *_selftest.sh, plus every library they source) reads from the
# environment must be EITHER routed through scripts/lib/gate_env_override.sh (cm_gate_env_set: honoured only under
# HELIX_TEST_MODE=1 / a temp-root path / a trusted production path) OR listed, with a kind from a closed set and a
# justification, in config/gate_env_allowlist.tsv.
#
# Instrument: scripts/gates/lib/gate_env_census.py (static, text-level; see its header for the forms it reads).
# Before the census of the real gates is believed, the SAME instrument is run on a control-needle file
# (scripts/gates/fixtures/gate_env_census/needle/scripts/gates/needle_gate.sh) that carries one read of every form; every
# expected needle row must be found (positive control) and the assigned-then-read and fabricated names must NOT be
# found (negative controls). A blind needle, or zero census rows over the real gates, is BLIND (rc 2), never PASS.
#
# Usage: cm_gate_env_reads_allowlisted.sh [--root DIR] [--allowlist FILE] [-h]
#   --root       tree to census (default: the repository this gate lives in)
#   --allowlist  allowlist file (default: <root>/config/gate_env_allowlist.tsv)
# Exit: 0 PASS | 1 FAIL (an uncovered read, or a stale allowlist row) | 2 BLIND / config error.
# Every run prints one line "VERDICT: <PASS|FAIL|BLIND> ...".
# BEST-EFFORT TRIPWIRE, NOT A PROOF (precedent: the 11.4.287 guard honest boundary). Residual, NOT detected: `declare -n` namerefs,
# bare `declare | grep` dumps beyond the listed forms, `bash -c '...$X'` strings, python getattr(os,"environ")/posix.environ,
# ruby ENV[], child-process inheritance, PATH/HOME (exempt), gates in nested dirs (scripts/gates/*/cm_*.sh are not enumerated),
# JEV_GATE_TIMEOUT=0 (disables a timeout). Full list: the gate_env_census.py header. `[ -v X ]`, `test -v X`, `printenv "$n"` ARE detected.
# Boundary (11.4.6): static text census. It does not follow a child process (an environment variable inherited by a
# tool the gate runs is that tool's read, not the gate's), it does not resolve ${!x} beyond reporting it as indirect,
# and an allowlist row records a decision; it does not prove the decision right (11.4.142 review does).
set -u
GATE=CM-GATE-ENV-READS-ALLOWLISTED
HERE="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root=""; allow=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || { echo "VERDICT: BLIND $GATE: --root needs a value" ; exit 2; }; root="$2"; shift 2 ;;
    --allowlist) [ $# -ge 2 ] || { echo "VERDICT: BLIND $GATE: --allowlist needs a value"; exit 2; }; allow="$2"; shift 2 ;;
    -h|--help) sed -n '2,24p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "VERDICT: BLIND $GATE: unknown argument: $1"; exit 2 ;;
  esac
done
[ -n "$root" ] || root="$(CDPATH= cd -- "$HERE/../.." && pwd)"
root="$(readlink -f -- "$root" 2>/dev/null)" || root=""
[ -n "$root" ] && [ -d "$root/scripts/gates" ] || { echo "VERDICT: BLIND $GATE: root has no scripts/gates directory"; exit 2; }
[ -n "$allow" ] || allow="$root/config/gate_env_allowlist.tsv"
[ -r "$allow" ] || { echo "VERDICT: BLIND $GATE: allowlist not readable: $allow"; exit 2; }
CENSUS="$HERE/lib/gate_env_census.py"
NEEDLE_ROOT="$HERE/fixtures/gate_env_census/needle"
[ -r "$CENSUS" ] || { echo "VERDICT: BLIND $GATE: census instrument missing: $CENSUS"; exit 2; }
[ -r "$NEEDLE_ROOT/scripts/gates/needle_gate.sh" ] || { echo "VERDICT: BLIND $GATE: control-needle file missing"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "VERDICT: BLIND $GATE: python3 not found"; exit 2; }

# 1. control needle through the same instrument and the same invocation shape
needle_out="$(cd / && python3 -I "$CENSUS" --root "$NEEDLE_ROOT" --closure "$NEEDLE_ROOT/scripts/gates/needle_gate.sh")"; rc=$?
[ "$rc" = 0 ] || { echo "VERDICT: BLIND $GATE: census instrument failed on the control needle (rc $rc)"; exit 2; }

# 2. census of the real gates
mapfile -t gates < <(cd "$root" && for f in scripts/gates/cm_*.sh; do case "$f" in *_mutation_test.sh|*_selftest.sh) ;; *) [ -f "$f" ] && printf '%s\n' "$root/$f" ;; esac; done)
[ "${#gates[@]}" -gt 0 ] || { echo "VERDICT: BLIND $GATE: no gate files under $root/scripts/gates"; exit 2; }
cerr="$(mktemp "${TMPDIR:-/tmp}/cm_envcensus_err.XXXXXX")" || { echo "VERDICT: BLIND $GATE: cannot create a scratch file"; exit 2; }
census_out="$(cd / && python3 -I "$CENSUS" --root "$root" --closure "${gates[@]}" 2>"$cerr")"; rc=$?
if [ "$rc" != 0 ]; then
  sed -n '1,20p' "$cerr" >&2; nunres="$(grep -c '^UNRESOLVED-SOURCE' "$cerr")"; rm -f -- "${cerr:?}"
  if [ "$rc" = 2 ] && [ "$nunres" -gt 0 ]; then echo "VERDICT: BLIND $GATE: $nunres source statement(s) cannot be resolved to a file (UNRESOLVED-SOURCE above): the closure would silently omit them"; exit 2; fi
  echo "VERDICT: BLIND $GATE: census instrument failed (rc $rc)"; exit 2
fi
rm -f -- "${cerr:?}"

python3 -I - "$GATE" "$allow" "${#gates[@]}" 3<<<"$needle_out" 4<<<"$census_out" <<'PYGATE'
import fnmatch, os, sys
gate, allow_path, ngates = sys.argv[1], sys.argv[2], int(sys.argv[3])
def rows(fd):
    out = []
    with os.fdopen(fd, encoding="utf-8") as f:
        for line in f:
            p = line.rstrip("\n").split("\t")
            if len(p) == 4:
                out.append(tuple(p))
    return out
needle, cen = rows(3), rows(4)
# --- control needle: every form must be seen, the negatives must not be ---
expect = {("NEEDLE_PLAIN", "ambient"), ("NEEDLE_BRACE", "ambient"), ("NEEDLE_DEFAULT", "ambient"),
          ("NEEDLE_ALT", "ambient"), ("NEEDLE_LEN", "ambient"), ("NEEDLE_TEST", "ambient"),
          ("NEEDLE_CMDSUB", "ambient"), ("NEEDLE_SELFDEFAULT", "ambient-default"),
          ("NEEDLE_PRINTENV", "env-api"), ("NEEDLE_PYENV", "env-api"), ("NEEDLE_AWKENV", "env-api"),
          ("NEEDLE_GUARDED", "guarded"), ("NEEDLE_LIBREAD", "ambient"),
          # source closure: script-relative `..`, root-relative tail after an expansion, variable-valued source (review round 8 F2)
          ("NEEDLE_UPLIB", "ambient"), ("NEEDLE_ROOTLIB", "ambient"), ("NEEDLE_VARLIB", "ambient"),
          # read forms (review round 8 F3): bare export/declare -x/readonly, env-prefix, perl, python alias + whole env, env dump,
          # jq, node, declare -p, eval
          ("NEEDLE_BAREEXP", "ambient"), ("NEEDLE_DECLX", "ambient"), ("NEEDLE_RDONLY", "ambient"), ("NEEDLE_PREFIX", "ambient"),
          ("NEEDLE_PERL", "env-api"), ("NEEDLE_PYALIAS", "env-api"), ("os.environ", "indirect"), ("<env-dump>", "indirect"),
          ("NEEDLE_ENVGREP", "env-api"), ("NEEDLE_JQENV", "env-api"), ("NEEDLE_JQENV2", "env-api"), ("jq-env", "indirect"),
          ("NEEDLE_NODE", "env-api"), ("process.env", "indirect"), ("NEEDLE_DECLP", "env-api"), ("<declare-dump>", "indirect"),
          ("NEEDLE_EVALCMD", "ambient"), ("<eval>", "indirect")}
seen = {(r[1], r[2]) for r in needle}
missing = sorted(expect - seen)
negatives = sorted(v for v, _ in seen if v in ("NEEDLE_ASSIGNED", "NEEDLE_FABRICATED_ZQX", "NEEDLE_EXPVAL"))
if missing or negatives:
    print(f"VERDICT: BLIND {gate}: control needle failed (missing={missing} false-hits={negatives}); the census zero would say nothing")
    sys.exit(2)
if not cen:
    print(f"VERDICT: BLIND {gate}: census extracted zero reads over {ngates} gates (the positive needle passed; the real scan is empty)")
    sys.exit(2)
# --- allowlist ---
KINDS = {"data-root", "data-config", "strictness-only", "output-only", "internal-channel", "guard-barrier",
         "indirect-mechanism", "not-ambient", "inert-text", "product-runtime", "inline-guarded"}
allow, bad, keys = [], [], set()
with open(allow_path, encoding="utf-8") as f:
    for n, line in enumerate(f, 1):
        s = line.rstrip("\n")
        if not s.strip() or s.lstrip().startswith("#"):
            continue
        p = s.split("\t")
        if len(p) != 4 or not all(x.strip() for x in p):
            bad.append(f"line {n}: needs 4 non-empty TAB fields"); continue
        if p[2] not in KINDS:
            bad.append(f"line {n}: kind {p[2]!r} not in the closed set"); continue
        if (p[0], p[1]) in keys:
            bad.append(f"line {n}: duplicate row {p[0]} {p[1]}"); continue
        keys.add((p[0], p[1])); allow.append((n, p[0], p[1], p[2]))
if bad:
    for b in bad:
        print(f"{gate}: allowlist config error: {b}", file=sys.stderr)
    print(f"VERDICT: BLIND {gate}: allowlist malformed ({len(bad)} rows): {allow_path}")
    sys.exit(2)
guarded = [r for r in cen if r[2] == "guarded"]
open_rows = [r for r in cen if r[2] != "guarded"]
used, uncovered = set(), []
for rel, var, kind, ln in open_rows:
    hit = [a for a in allow if a[2] == var and fnmatch.fnmatchcase(rel, a[1])]
    if not hit:
        uncovered.append((rel, var, kind, ln))
    for a in hit:
        used.add(a[0])
stale = [a for a in allow if a[0] not in used]
for rel, var, kind, ln in uncovered:
    print(f"{gate}: UNCOVERED {rel}:{ln} {var} ({kind}): route it through cm_gate_env_set or add an allowlist row", file=sys.stderr)
for n, g, v, k in stale:
    print(f"{gate}: STALE allowlist line {n}: {g} {v} ({k}) matches no census read", file=sys.stderr)
verdict = "FAIL" if (uncovered or stale) else "PASS"
print(f"VERDICT: {verdict} {gate}: gates={ngates} reads={len(cen)} guarded={len(guarded)} allowlisted={len(open_rows) - len(uncovered)} "
      f"uncovered={len(uncovered)} stale={len(stale)} needle=ok")
sys.exit(1 if verdict == "FAIL" else 0)
PYGATE
