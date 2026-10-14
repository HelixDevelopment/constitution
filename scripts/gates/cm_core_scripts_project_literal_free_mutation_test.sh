#!/usr/bin/env bash
# cm_core_scripts_project_literal_free_mutation_test.sh -- regression guard for the constitution-side half of
# CM-OWNED-SUBMODULE-DECOUPLING (§11.4.28(B)/§11.4.35) and CM-CRED-SCAN-LIB-SELF-VALIDATED invariant 4.
# Constitution logic is consumed by every project, so no consumer project literal may appear in it.
#
# Scope: the GUARD SET below = every constitution script the 2026-10-14 pre-build remedy batch genericised.
# It is not a whole-tree sweep (the wider constitution tree still carries members of the class; that backlog is
# the consumer's CM-OWNED-SUBMODULE-DECOUPLING gate's, §11.4.6 honest boundary).
#
# ── The literal class (WIDE_RE, matched case-INSENSITIVELY on every line of every guard-set file) ─────────
# WIDE_RE is BUILT at run time as   (C1)|(C2)|...|EXTRAS
#   C1, C2, ... = the consumer's own literal regexes, READ at test time (see "Consumer regexes" below);
#   EXTRAS      = members the consumer regexes miss: project / vendor / SoC names in any case and inside any
#                 path, the reference-device serials, consumer-only paths, and the tracker prefixes as a WORD
#                 in any form -- `PFX-123`, `PFX-[0-9]`, `PFX-\d+`, `pfx-[[:digit:]]`, `(PFX|PFX2)-\d+`,
#                 `PFX_12` -- bounded by a non-alphanumeric character (round-3 review N3: `(A|B|C)-\d+` and
#                 `A-\d+` escaped the old hand-written class).
# Because every Ci is a member of the alternation, WIDE_RE matches every line any Ci matches (and more:
# it is applied with -i). That is the superset, by construction; S2 checks the construction, S1 checks it
# empirically with needles GENERATED from each Ci (one per top-level alternative), each first verified
# against Ci itself, so a needle the generator got wrong is reported as BLIND, never as a pass.
#
# ── Consumer regexes (§11.4.35: the consumer supplies them as DATA) ────────────────────────────────────
# Sources, all of which are read: `--consumer-source FILE:VAR` (repeatable), the environment variable
# CORE_LITERAL_CONSUMER_SOURCES (space-separated FILE:VAR), and the consumer data file
# <ROOT>/../config/core_literal_consumer_sources.tsv (rows `<path relative to ROOT/..>\t<VAR>`). VAR names a
# single-quoted shell assignment `VAR='<ERE>'`; it must occur exactly once in FILE, else the run FAILs as
# BLIND. With NO source at all (the constitution checked out on its own) the built-in mirror below is used
# and the output says so; when a source IS read, the mirror is compared with it and drift is reported.
#
# Paired §1.1 mutation: each M case re-injects one literal into a copy (built from fragments so THIS file never
# matches itself; the name ends _mutation_test.sh, which the consumer gates exclude) and requires the scan to FAIL;
# each MC case injects a needle generated from a consumer regex.
# Control needles (§11.4.273): G0 (a known-present literal IS seen) and N0 (a genericised look-alike is NOT).
# Wired: run by scripts/hooks/test_credential_scan_lib.sh (the suite the consumer's CSLV gate invariant (5) runs).
# Usage: cm_core_scripts_project_literal_free_mutation_test.sh [--root DIR] [--consumer-source FILE:VAR]...
# Exit 0 all PASS, 1 any FAIL.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SOURCES=()
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ -n "${2:-}" ] && ROOT="$2"; shift 2 ;;
    --consumer-source) [ -n "${2:-}" ] && SOURCES+=("$2"); shift 2 ;;
    *) echo "usage: $0 [--root DIR] [--consumer-source FILE:VAR]..." >&2; exit 2 ;;
  esac
done
for _s in ${CORE_LITERAL_CONSUMER_SOURCES:-}; do SOURCES+=("$_s"); done
_cdir="$(cd "$ROOT/.." 2>/dev/null && pwd)"
if [ -n "$_cdir" ] && [ -f "$_cdir/config/core_literal_consumer_sources.tsv" ]; then
  while IFS=$'\t' read -r _p _v; do
    case "${_p:-}" in ''|'#'*) continue ;; esac
    SOURCES+=("$_cdir/$_p:$_v")
  done < "$_cdir/config/core_literal_consumer_sources.tsv"
fi
# literal fragments (this file must not contain a contiguous literal of the class)
P1="at""mos""phere"; O1="ATM""OS""phere1234321"; S1N="rk""3588"; V1="rock""chip"; RK="RK""3588"
SER1="998fd366""15e99484"; SER2="66ff9c4f""51f00ee7"; T1="AT""M"; T2="SP""K"; T3="BO""B"
# built-in mirror of the consumer regexes (used only when no source is read): the owned-submodule
# decoupling regex and the credential-scan-lib invariant-4 regex, rebuilt from fragments.
MIRROR=(
"com\\.${P1}|/mnt/track[0-9]+/${P1}|${RK}|kernel-5\\.10/|hardware/${V1}|${SER1}|${SER2}|ru\\.kino""poisk|ru\\.ok\\.and""roid|${P1}-register-google\\.sh|${P1}-app-permissions\\.sh|\\(${T1}\\|${T2}\\|${T3}\\)|\"${T1}-\\[0-9|\"${T2}-\\[0-9|\"${T3}-\\[0-9"
"${P1}|${S1N}|${V1}|orange""pi|${SER1}|${SER2}"
)
EXTRAS="${P1}|${S1N}|${V1}|orange ?pi|${SER1}|${SER2}|(^|[^[:alnum:]])(${T1}|${T2}|${T3})([^[:alnum:]]|\$)|/mnt/track[0-9]|kino""poisk|ok\\.and""roid|kernel-5\\.10"
FILES="scripts/hooks/credential_scan_lib.sh scripts/fastcycle/tokens/transcript_ingest.py scripts/fastcycle/gates/lib/io_trace_build_map.py scripts/gates/lib/covenant_propagation_engine.sh scripts/gates/cm_version_increment_on_deploy_mutation_test.sh"
pass=0; fail=0
ok()  { echo "PASS: $1"; pass=$((pass+1)); }
bad() { echo "FAIL: $1"; fail=$((fail+1)); }
T="$(mktemp -d "${TMPDIR:-/tmp}/core_literal.XXXXXX")"; trap 'rm -rf "$T"' EXIT

# ---- read the consumer regexes ------------------------------------------------------------------------------
CONSUMER=(); SRC_DESC=""
extract_var() { # $1 file $2 var -> prints the single-quoted value; rc 1 unless exactly one assignment
  local n
  n="$(grep -cE "^[[:space:]]*$2='" "$1" 2>/dev/null)"
  [ "$n" = 1 ] || return 1
  grep -E "^[[:space:]]*$2='" "$1" | sed -E "s/^[[:space:]]*$2='(.*)'[[:space:]]*(#.*)?\$/\\1/"
}
for _src in ${SOURCES[@]+"${SOURCES[@]}"}; do
  _f="${_src%:*}"; _v="${_src##*:}"
  if _re="$(extract_var "$_f" "$_v")" && [ -n "$_re" ] && [ "${_re#*\'}" = "$_re" ]; then
    CONSUMER+=("$_re"); SRC_DESC="$SRC_DESC ${_f##*/}:$_v"
  else
    bad "C0 consumer regex source BLIND: $_v not found exactly once as VAR='...' in $_f"
  fi
done
if [ "${#CONSUMER[@]}" -eq 0 ] && [ "$fail" -eq 0 ]; then
  CONSUMER=("${MIRROR[@]}"); SRC_DESC=" built-in mirror (no consumer source given; see header)"
  echo "INFO: consumer regexes: built-in mirror"
else
  echo "INFO: consumer regexes read from:$SRC_DESC"
  for _m in "${MIRROR[@]}"; do
    _hit=0; for _c in ${CONSUMER[@]+"${CONSUMER[@]}"}; do [ "$_c" = "$_m" ] && _hit=1; done
    [ "$_hit" = 1 ] || echo "INFO: built-in mirror member differs from every read consumer regex (mirror drift, not a failure): ${_m:0:60}..."
  done
fi
WIDE_RE=""
for _c in ${CONSUMER[@]+"${CONSUMER[@]}"}; do WIDE_RE="${WIDE_RE}(${_c})|"; done
WIDE_RE="${WIDE_RE}${EXTRAS}"

scan() { # $1 root ; prints "<file>:<n>:<line>" hits (or BLIND:<file>); rc0 always
  local r="$1" f
  for f in $FILES; do
    [ -f "$r/$f" ] || { echo "BLIND:$f"; continue; }
    grep -niE -- "$WIDE_RE" "$r/$f" | sed "s|^|$f:|"
  done
}
copy_set() { # $1 dest
  local g; for g in $FILES; do mkdir -p "$1/$(dirname "$g")"; cp "$ROOT/$g" "$1/$g" 2>/dev/null; done
}

# ---- S2: superset by construction ---------------------------------------------------------------------------
s2=1
for _c in ${CONSUMER[@]+"${CONSUMER[@]}"}; do case "$WIDE_RE" in *"(${_c})|"*) ;; *) s2=0 ;; esac; done
if [ "$s2" = 1 ] && [ "${#CONSUMER[@]}" -ge 1 ]; then
  ok "S2 WIDE_RE contains each of the ${#CONSUMER[@]} consumer regex(es) as a whole alternation member (superset by construction)"
else bad "S2 WIDE_RE does not contain every consumer regex as a member -- the superset claim does not hold"; fi

# ---- S1: needles generated from each consumer regex ---------------------------------------------------------
NEEDLES="$T/needles.tsv"; : > "$NEEDLES"
gen_ok=1
for _i in "${!CONSUMER[@]}"; do
  if ! python3 - "${CONSUMER[$_i]}" "$_i" >> "$NEEDLES" 2>"$T/gen.err" <<'PY'
import sys
try:
    import re._parser as sp, re._constants as sc
except ImportError:  # Python < 3.11
    import sre_parse as sp, sre_constants as sc
pat, idx = sys.argv[1], sys.argv[2]
for posix, rng in (('[:digit:]', '0-9'), ('[:alnum:]', 'a-zA-Z0-9'), ('[:alpha:]', 'a-zA-Z'),
                   ('[:upper:]', 'A-Z'), ('[:lower:]', 'a-z'), ('[:space:]', ' \t')):
    pat = pat.replace(posix, rng)
def gen(items):
    out = []
    for op, av in items:
        if op is sc.LITERAL: out.append(chr(av))
        elif op is sc.NOT_LITERAL: out.append('x' if av != ord('x') else 'y')
        elif op is sc.ANY: out.append('x')
        elif op is sc.AT: pass
        elif op is sc.IN:
            first = av[0]
            if first[0] is sc.NEGATE: out.append('#')
            elif first[0] is sc.LITERAL: out.append(chr(first[1]))
            elif first[0] is sc.RANGE: out.append(chr(first[1][0]))
            elif first[0] is sc.CATEGORY:
                out.append({sc.CATEGORY_DIGIT: '0', sc.CATEGORY_WORD: 'a', sc.CATEGORY_SPACE: ' '}.get(first[1], 'a'))
            else: raise ValueError('class item %r' % (first,))
        elif op in (sc.MAX_REPEAT, sc.MIN_REPEAT):
            lo, hi, sub = av
            out.append(gen(sub) * max(lo, 1))
        elif op is sc.SUBPATTERN: out.append(gen(av[-1]))
        elif op is sc.BRANCH: out.append(gen(av[1][0]))
        else: raise ValueError('unsupported op %r' % (op,))
    return ''.join(out)
tree = list(sp.parse(pat))
if len(tree) == 1 and tree[0][0] is sc.BRANCH:
    alts = [list(a) for a in tree[0][1][1]]
else:
    alts = [tree]
for a in alts:
    n = gen(a)
    if not n or '\n' in n or '\t' in n:
        raise ValueError('empty/unprintable needle')
    print('%s\t%s' % (idx, n))
PY
  then gen_ok=0; echo "  S1 needle generator could not parse consumer regex #$_i: $(tail -1 "$T/gen.err")"; fi
done
s1_n=0; s1_bad=0
while IFS=$'\t' read -r _i _n; do
  s1_n=$((s1_n+1))
  grep -qE -- "${CONSUMER[$_i]}" <<<"$_n" || { s1_bad=$((s1_bad+1)); echo "  S1 BLIND: generated needle is not matched by its own consumer regex #$_i: $_n"; continue; }
  grep -qiE -- "$WIDE_RE" <<<"$_n" || { s1_bad=$((s1_bad+1)); echo "  S1 needle from consumer regex #$_i NOT matched by WIDE_RE: $_n"; }
done < "$NEEDLES"
if [ "$gen_ok" = 1 ] && [ "$s1_n" -ge "${#CONSUMER[@]}" ] && [ "$s1_bad" -eq 0 ]; then
  ok "S1 $s1_n needles generated from the consumer regex(es), each matched by its source regex AND by WIDE_RE"
else bad "S1 consumer-needle superset check failed ($s1_bad of $s1_n bad, generator ok=$gen_ok)"; fi
# extra-member needles (the members the consumer regexes miss; round-3 review N3 forms included)
ex_bad=0; ex_n=0
for n in "com.${P1}.app" "${RK} board" "${SER1}" "${SER2}" "/mnt/track1/${P1}" "${V1}" "orange""pi" "Orange Pi 5" \
         "ITEM_RE = re.compile(r\"(${T1}|${T2}|${T3})-\\d+\")" "ITEM_RE = re.compile(r\"${T1}-\\d+\")" \
         "x = '${T1,,}-' + str(n)" "PAT='${T2}-[[:digit:]]+'" "${T3}_12" "item ${T1}-1188 done"; do
  ex_n=$((ex_n+1))
  grep -qiE -- "$WIDE_RE" <<<"$n" || { ex_bad=$((ex_bad+1)); echo "  S1x needle not matched: $n"; }
done
[ "$ex_bad" -eq 0 ] && ok "S1x WIDE_RE matches every extra-member needle ($ex_n, including the round-3 N3 forms)" || bad "S1x $ex_bad of $ex_n extra-member needle(s) not matched"

# ---- G0 / N0 control needles -----------------------------------------------------------------------------------
copy_set "$T/ctl"
printf '# %s here\n' "$O1" >> "$T/ctl/scripts/hooks/credential_scan_lib.sh"
ctl="$(scan "$T/ctl")"   # capture first: `scan | grep -q` under pipefail is a SIGPIPE false-negative
grep -q 'credential_scan_lib.sh:' <<<"$ctl" && ok "G0 control needle: injected org literal is seen by the scan" || bad "G0 control needle NOT seen -- scan is blind"
copy_set "$T/neg"
printf '# items like item=MYP-12 in a myproject checkout; <vendor>/<soc> board; batman spkr bobcat\n' >> "$T/neg/scripts/fastcycle/tokens/transcript_ingest.py"
neg_n="$(scan "$T/neg" | grep -c '^scripts/fastcycle/tokens/transcript_ingest.py:')"
real_n="$(scan "$ROOT" | grep -c '^scripts/fastcycle/tokens/transcript_ingest.py:')"
[ "$neg_n" = "$real_n" ] && ok "N0 negative control: genericised look-alikes are not matched (hits $neg_n == $real_n)" || bad "N0 negative control matched a genericised line -- over-broad scan (hits $neg_n != $real_n)"
# ---- G*: the real tree is literal-free -------------------------------------------------------------------------
hits="$(scan "$ROOT")"
blind="$(grep '^BLIND' <<<"$hits")"
if [ -n "$blind" ]; then bad "G BLIND: a scanned file is missing: ${blind%%$'\n'*}"
else
  for f in $FILES; do
    fh="$(grep "^$f:" <<<"$hits")"
    if [ -n "$fh" ]; then bad "G* $f carries a project literal: ${fh%%$'\n'*}"; else ok "G* $f is project-literal-free"; fi
  done
fi
# ---- M1..M11 mutations: re-inject one literal per case into a copy; the scan MUST fail on it ---------------------
i=0
for spec in "scripts/hooks/credential_scan_lib.sh|# ssh://git@github.com/$O1/repo.git" \
            "scripts/fastcycle/tokens/transcript_ingest.py|#      \"${T1}-[0-9]+|${T2}-[0-9]+\"" \
            "scripts/fastcycle/gates/lib/io_trace_build_map.py|# physical $RK board" \
            "scripts/fastcycle/tokens/transcript_ingest.py|ITEM_RE = '${T1}-[0-9]+|${T2}-[0-9]+'" \
            "scripts/fastcycle/gates/lib/io_trace_build_map.py|# default device/${V1}/${S1N}/tests/" \
            "scripts/gates/lib/covenant_propagation_engine.sh|# tracked as ${T1}-989" \
            "scripts/gates/cm_version_increment_on_deploy_mutation_test.sh|# fixture ${P1}-1.2.1-dev-0.12.0" \
            "scripts/fastcycle/tokens/transcript_ingest.py|ITEM_RE = re.compile(r\"(${T1}|${T2}|${T3})-\\d+\")" \
            "scripts/fastcycle/tokens/transcript_ingest.py|ITEM_RE = re.compile(r\"${T1}-\\d+\")" \
            "scripts/fastcycle/gates/lib/io_trace_build_map.py|ITEM_RE = re.compile(r'${T1,,}-[[:digit:]]{1,6}')" \
            "scripts/gates/lib/covenant_propagation_engine.sh|# remedy batch ${T1,,}-prebuild-remedy-const"; do
  i=$((i+1)); f="${spec%%|*}"; line="${spec#*|}"
  rm -rf "$T/m$i"; copy_set "$T/m$i"
  printf '%s\n' "$line" >> "$T/m$i/$f"
  mh="$(scan "$T/m$i")"
  grep -q "^$f:" <<<"$mh" && ok "M$i mutation caught in $f" || bad "M$i mutation SURVIVED in $f"
done
# ---- MC: each needle generated from a consumer regex, injected into a guard-set copy, is caught ----------------
mc_n=0; mc_bad=0
while IFS=$'\t' read -r _i _n; do
  mc_n=$((mc_n+1)); rm -rf "$T/mc"; copy_set "$T/mc"
  printf '# %s\n' "$_n" >> "$T/mc/scripts/fastcycle/tokens/transcript_ingest.py"
  mh="$(scan "$T/mc")"
  [ "$(grep -c '^scripts/fastcycle/tokens/transcript_ingest.py:' <<<"$mh")" -gt "$real_n" ] || { mc_bad=$((mc_bad+1)); echo "  MC consumer needle SURVIVED: $_n"; }
done < "$NEEDLES"
if [ "$mc_n" -ge 1 ] && [ "$mc_bad" -eq 0 ]; then ok "MC $mc_n consumer-regex needles, each injected into a guard-set copy, are caught by the scan"
else bad "MC $mc_bad of $mc_n consumer-regex needle(s) survived injection"; fi
echo "SUMMARY pass=$pass fail=$fail"
[ "$fail" -eq 0 ] && { echo "CORE-SCRIPTS-LITERAL-FREE: PASS"; exit 0; }
echo "CORE-SCRIPTS-LITERAL-FREE: FAIL"; exit 1
