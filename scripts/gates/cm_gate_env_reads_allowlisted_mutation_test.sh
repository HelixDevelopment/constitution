#!/usr/bin/env bash
# cm_gate_env_reads_allowlisted_mutation_test.sh -- 11.4.1.1 paired-mutation meta-test for CM-GATE-ENV-READS-ALLOWLISTED.
#
# Golden: the real tree PASSES; the golden-good fixture root PASSES (golden-FALSE per 11.4.201(1): a guarded read and an
# allowlisted read must not fire the gate). Discriminators (fixed rc): golden-bad (raw unallowlisted read) FAIL 1, a stale
# allowlist row FAIL 1, a row whose glob names another file FAIL 1, a malformed allowlist (bad kind / 3 fields) BLIND 2,
# a gate tree with zero reads BLIND 2, a blind needle (one form removed) BLIND 2, a needle negative hit BLIND 2.
# Mutants of the gate and of the census instrument (scratch copies in mktemp; the real files are never touched) MUST
# each make at least one discriminator flip:
#   M1 uncovered reads ignored         M2 stale rows ignored             M3 control-needle check removed
#   M4 zero-read BLIND removed         M5 closed kind set not enforced   M6 glob not matched (variable name only)
#   M7 census stops reporting plain ambient reads (the needle must catch the instrument going blind)
#   M8 unresolved source statements ignored (round 8 F2)   M9 bare export/declare -x/readonly treated as an assignment (F3)
#   M10 source closure not followed (F2)                   M11 python os.environ INDIRECT reads dropped (F3)
#   M12 jq env INDIRECT reads dropped (F3)
# Out-of-gate mutants (round 8): F1 = execution_record.sh trusts the ambient XR_SELF_PATH again (the dash test must fail);
# F4 = cm_jev_detection.sh goes GREEN when the llmctl cross-check cannot run (the BLIND test must fail).
# Census region-owner mutants (review census_safe rounds 1-2, F5/F6): the unmutated closure test and the unmutated
# jq-region test are run first as baselines (each must exit 3: only its tracked CON-047 KNOWN-FAIL cases outstanding);
# a mutant is killed only by rc 1. R1 whitespace-prefixed NAME= not an owner (RN1), R2 `+=` not an owner (RN7),
# R3 no separator between the quoted regions of a line (F7).
# Usage: cm_gate_env_reads_allowlisted_mutation_test.sh    Exit 0 every mutant killed | 1 survivor | 2 env error.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
gate="$here/cm_gate_env_reads_allowlisted.sh"; census="$here/lib/gate_env_census.py"; fx="$here/fixtures/gate_env_census"
[ -r "$gate" ] && [ -r "$census" ] && [ -d "$fx/needle" ] || { echo "META: gate, census or fixtures missing" >&2; exit 2; }
tmp="$(mktemp -d "${TMPDIR:-/tmp}/cm_envallow_meta.XXXXXX")" || exit 2
trap 'rm -rf -- "${tmp:?}"' EXIT
bad=0

mkroot() { # dir gate-template allowlist-file
  mkdir -p "$1/scripts/gates" "$1/config"; cp "$2" "$1/scripts/gates/cm_demo.sh"; cp "$3" "$1/config/gate_env_allowlist.tsv"
}
mkroot "$tmp/good" "$fx/golden_good/demo_gate.sh" "$fx/golden_good/allowlist.tsv"
mkroot "$tmp/bad" "$fx/golden_bad/demo_gate.sh" "$fx/golden_bad/allowlist.tsv"
mkroot "$tmp/stale" "$fx/golden_good/demo_gate.sh" "$fx/golden_good/allowlist.tsv"
printf 'scripts/gates/cm_*.sh\tDEMO_GONE\tdata-config\tno gate reads this any more\n' >>"$tmp/stale/config/gate_env_allowlist.tsv"
mkroot "$tmp/glob" "$fx/golden_bad/demo_gate.sh" "$fx/golden_bad/allowlist.tsv"
printf 'scripts/gates/cm_other.sh\tDEMO_ROOT\tdata-root\trow names a different file\n' >>"$tmp/glob/config/gate_env_allowlist.tsv"
mkroot "$tmp/kind" "$fx/golden_good/demo_gate.sh" "$fx/golden_good/allowlist.tsv"
printf 'scripts/gates/cm_*.sh\tDEMO_X\tbecause-i-said-so\tinvented kind\n' >>"$tmp/kind/config/gate_env_allowlist.tsv"
mkroot "$tmp/three" "$fx/golden_good/demo_gate.sh" "$fx/golden_good/allowlist.tsv"
printf 'scripts/gates/cm_*.sh\tDEMO_Y\tdata-config\n' >>"$tmp/three/config/gate_env_allowlist.tsv"
mkdir -p "$tmp/empty/scripts/gates" "$tmp/empty/config"; printf '#!/usr/bin/env bash\nx=1\n' >"$tmp/empty/scripts/gates/cm_demo.sh"
printf '# no rows\n' >"$tmp/empty/config/gate_env_allowlist.tsv"

mkdir -p "$tmp/unres/scripts/gates" "$tmp/unres/config"
printf '#!/usr/bin/env bash\n. "$(some_unknown_cmd)/lib.sh"\necho "$DEMO_ROOT"\n' >"$tmp/unres/scripts/gates/cm_demo.sh"
cp "$fx/golden_good/allowlist.tsv" "$tmp/unres/config/gate_env_allowlist.tsv"

# content-pinned eval rows (CON-113 F113-1): the row names <eval>#<sha12> of its own eval line; the hash is computed HERE
# with sha256sum, independently of the census, so the census and this oracle must agree. A second eval in the same file
# is a different statement and must stay UNCOVERED.
mkdir -p "$tmp/evalone/scripts/gates" "$tmp/evalone/config"
printf '#!/usr/bin/env bash\neval "A=\\$DEMO_E1"\n' >"$tmp/evalone/scripts/gates/cm_demo.sh"
ev1="$(sed -n 2p "$tmp/evalone/scripts/gates/cm_demo.sh" | tr -d '\n' | sha256sum | cut -c1-12)"
printf 'scripts/gates/cm_*.sh\t<eval>#%s\tindirect-mechanism\tthe one reviewed eval of the demo gate\n' "$ev1" >"$tmp/evalone/config/gate_env_allowlist.tsv"
cp -R "$tmp/evalone" "$tmp/evaltwo"; printf 'eval "B=\\$DEMO_E2"\n' >>"$tmp/evaltwo/scripts/gates/cm_demo.sh"

# a sandbox copy of the gate + instrument + needle (HERE resolves inside it)
GS=scripts/gates/cm_gate_env_reads_allowlisted.sh; CS=scripts/gates/lib/gate_env_census.py
mkgate() { # dir
  mkdir -p "$1/scripts/gates/lib" "$1/scripts/gates/fixtures/gate_env_census"
  cp "$gate" "$1/scripts/gates/cm_gate_env_reads_allowlisted.sh"; cp "$census" "$1/scripts/gates/lib/gate_env_census.py"
  cp -R "$fx/needle" "$1/scripts/gates/fixtures/gate_env_census/needle"
}
NF=scripts/gates/fixtures/gate_env_census/needle/scripts/gates/needle_gate.sh
sabotage() { # sandbox-dir: make <dir>.blind (one needle form removed) and <dir>.neg (a needle negative read)
  cp -R "$1" "$1.blind"; sed -i '/NEEDLE_PRINTENV/d' "$1.blind/$NF"
  cp -R "$1" "$1.neg"; printf 'echo "$NEEDLE_FABRICATED_ZQX"\n' >>"$1.neg/$NF"
}
mkgate "$tmp/g0"; sabotage "$tmp/g0"

run() { bash "$1" "${@:2}" >/dev/null 2>&1; echo $?; }
# discriminators: name want-rc gate-path args...
CASES=(
  "golden-FALSE good root|0|G|--root $tmp/good"
  "golden-bad raw read|1|G|--root $tmp/bad"
  "stale allowlist row|1|G|--root $tmp/stale"
  "row for another file|1|G|--root $tmp/glob"
  "invented kind|2|G|--root $tmp/kind"
  "three-field row|2|G|--root $tmp/three"
  "zero reads|2|G|--root $tmp/empty"
  "unresolvable source statement|2|G|--root $tmp/unres"
  "blind needle|2|BLIND|--root $tmp/good"
  "needle negative hit|2|NEG|--root $tmp/good"
  "pinned eval row covers its own eval|0|G|--root $tmp/evalone"
  "second eval in the same file is uncovered|1|G|--root $tmp/evaltwo"
)
gpath() { # sandbox-dir tag -> gate path (G: the sandbox, BLIND/NEG: its sabotaged-needle copies)
  case "$2" in G) echo "$1/$GS" ;; BLIND) echo "$1.blind/$GS" ;; NEG) echo "$1.neg/$GS" ;; esac
}
suite() { # sandbox-dir -> prints number of discriminators that did NOT hold
  local d="$1" miss=0 c n w gp a rc
  for c in "${CASES[@]}"; do
    IFS='|' read -r n w gp a <<<"$c"; gp="$(gpath "$d" "$gp")"
    # shellcheck disable=SC2086
    rc="$(run "$gp" $a)"; [ "$rc" = "$w" ] || miss=$((miss+1))
  done
  echo "$miss"
}
rc="$(run "$gate")"; if [ "$rc" = 0 ]; then echo "  ok   golden real tree PASS"; else echo "  FAIL golden real tree (rc=$rc)"; bad=$((bad+1)); fi
for c in "${CASES[@]}"; do
  IFS='|' read -r n w gp a <<<"$c"; gp="$(gpath "$tmp/g0" "$gp")"
  # shellcheck disable=SC2086
  rc="$(run "$gp" $a)"
  if [ "$rc" = "$w" ]; then echo "  ok   $n (rc=$rc)"; else echo "  FAIL $n (want rc=$w got $rc)"; bad=$((bad+1)); fi
done

mutant() { # id description file-in-sandbox sed-expr
  local id="$1" desc="$2" rel="$3" expr="$4" d="$tmp/m_$1"
  mkgate "$d"; sed -i "$expr" "$d/$rel"; sabotage "$d"
  if cmp -s "$d/$rel" "$tmp/g0/$rel"; then echo "  FAIL $id did not apply ($desc)"; bad=$((bad+1)); return; fi
  local miss; miss="$(suite "$d")"
  if [ "$miss" -gt 0 ]; then echo "  ok   $id killed: $desc ($miss discriminator(s) flipped)"; else echo "  FAIL $id SURVIVED: $desc"; bad=$((bad+1)); fi
}
mutant M1 "uncovered reads ignored" "$GS" 's/if (uncovered or stale) else/if (stale) else/'
mutant M2 "stale rows ignored" "$GS" 's/if (uncovered or stale) else/if (uncovered) else/'
mutant M3 "control-needle check removed" "$GS" 's/^if missing or negatives:/if False:/'
mutant M4 "zero-read BLIND removed" "$GS" 's/^if not cen:/if False:/'
mutant M5 "closed kind set not enforced" "$GS" 's/if p\[2\] not in KINDS:/if False:/'
mutant M6 "glob ignored" "$GS" 's/fnmatch.fnmatchcase(rel, a\[1\])/True/'
mutant M7 "census drops plain ambient reads" "$CS" 's/add(name, "ambient", ln)/pass/'
mutant M8 "unresolved source ignored" "$CS" 's/^    if unresolved:/    if False:/'
mutant M9 "bare export treated as assignment" "$CS" 's/if has_val or kw == "local" or/if True or kw == "local" or/'
mutant M10 "source closure not followed" "$CS" 's/^        todo.extend(found)/        pass/'
mutant M11 "python os.environ indirect dropped" "$CS" 's/add("os.environ", "indirect", ln)/pass/'
mutant M12 "jq env indirect dropped" "$CS" 's/add("jq-env", "indirect", ln)/pass/'
mutant M13 "eval rows pinned per file, not per statement" "$CS" 's/hashlib.sha256(src.encode("utf-8"))/hashlib.sha256(path.encode("utf-8"))/'

# out-of-gate mutants: sabotaged copies of the real files, driven by the real regression tests
root="$(cd "$here/../.." && pwd)"
oog() { # id desc test-script rel-file sed-expr env-var-name
  local id="$1" desc="$2" t="$3" rel="$4" expr="$5" ev="$6" d="$tmp/oog_$1"
  mkdir -p "$d/$(dirname "$rel")"; cp "$root/$rel" "$d/$rel"; sed -i "$expr" "$d/$rel"
  if cmp -s "$d/$rel" "$root/$rel"; then echo "  FAIL $id did not apply ($desc)"; bad=$((bad+1)); return; fi
  if env "$ev=$d/$rel" bash "$root/$t" >/dev/null 2>&1; then echo "  FAIL $id SURVIVED: $desc"; bad=$((bad+1)); else echo "  ok   $id killed: $desc"; fi
}
oog F1 "ambient XR_SELF_PATH trusted again" tests/gates/test_execution_record_selfpath.sh scripts/gates/lib/execution_record.sh '/^unset XR_SELF_PATH/d' XR_LIB_UNDER_TEST
oog N1 "ambient BASH_SOURCE trusted again (no sentinel check)" tests/gates/test_execution_record_selfpath.sh scripts/gates/lib/execution_record.sh 's/^if \[ -n "${BASH_SOURCE:-}" \] && _xr_is_self "${BASH_SOURCE}"; then/if [ -n "${BASH_SOURCE:-}" ]; then/' XR_LIB_UNDER_TEST
# F4: the detection gate with the BLIND branch removed (cross-check-unavailable becomes a plain NOTE again)
d="$tmp/oog_F4"; mkdir -p "$d/scripts/gates" "$d/scripts/jev" "$d/scripts/lib"
cp "$root/scripts/gates/cm_jev_detection.sh" "$d/scripts/gates/"; cp "$root/scripts/jev/"*.sh "$d/scripts/jev/" 2>/dev/null; cp "$root/scripts/lib/gate_env_override.sh" "$d/scripts/lib/"
[ -d "$root/scripts/gates/lib" ] && cp -R "$root/scripts/gates/lib" "$d/scripts/gates/lib"
sed -i 's/^blind_or_note() {.*/blind_or_note() { note "$*"; }/' "$d/scripts/gates/cm_jev_detection.sh"
if cmp -s "$d/scripts/gates/cm_jev_detection.sh" "$root/scripts/gates/cm_jev_detection.sh"; then echo "  FAIL F4 did not apply"; bad=$((bad+1))
elif JEV_GATE_UNDER_TEST="$d/scripts/gates/cm_jev_detection.sh" bash "$root/tests/jev/test_detection_gate_blind_without_llmctl.sh" >/dev/null 2>&1; then echo "  FAIL F4 SURVIVED: llmctl-absent still GREEN"; bad=$((bad+1)); else echo "  ok   F4 killed: llmctl-absent GREEN is caught"; fi

# N3/N6 mutants: the census with a closure/read-form recogniser removed must be caught by the closure test
cen() { # id desc sed-expr : sabotage a copy of the census, run the closure test against it
  local id="$1" desc="$2" expr="$3" d="$tmp/cen_$1"; mkdir -p "$d"; cp -R "$root/scripts" "$d/scripts"; mkdir -p "$d/config"; cp "$root/config/gate_env_allowlist.tsv" "$d/config/"
  sed -i "$expr" "$d/scripts/gates/lib/gate_env_census.py"
  if cmp -s "$d/scripts/gates/lib/gate_env_census.py" "$root/scripts/gates/lib/gate_env_census.py"; then echo "  FAIL $id did not apply ($desc)"; bad=$((bad+1)); return; fi
  mkdir -p "$d/tests/gates"; cp "$root/tests/gates/test_gate_env_census_closure.sh" "$d/tests/gates/"
  # killed only by a real FAIL (rc 1): rc 3 means only a KNOWN-FAIL case (tracked) is outstanding, which the unmutated tree
  # also shows, so it does not count as killing the mutant
  local crc=0; bash "$d/tests/gates/test_gate_env_census_closure.sh" >/dev/null 2>&1 || crc=$?
  if [ "$crc" != 1 ]; then echo "  FAIL $id SURVIVED (closure rc=$crc): $desc"; bad=$((bad+1)); else echo "  ok   $id killed: $desc"; fi
}
# F6: unmutated baseline for the cen kills (a closure test failing for an environmental reason would "kill" every mutant)
cbase="$tmp/cen_BASE"; mkdir -p "$cbase/config" "$cbase/tests/gates"; cp -R "$root/scripts" "$cbase/scripts"; cp "$root/config/gate_env_allowlist.tsv" "$cbase/config/"
cp "$root/tests/gates/test_gate_env_census_closure.sh" "$cbase/tests/gates/"
cbrc=0; bash "$cbase/tests/gates/test_gate_env_census_closure.sh" >/dev/null 2>&1 || cbrc=$?
if [ "$cbrc" = 3 ]; then echo "  ok   baseline closure test unmutated rc=3 (only the tracked KNOWN-FAIL outstanding)"
else echo "  FAIL baseline closure test unmutated rc=$cbrc (want 3): the cen kills below would not be evidence"; bad=$((bad+1)); fi
cen N3a "builtin/command prefix not recognised" 's/(?:(?:builtin|command)\\s+)?(?:\\.|source)\\s+(?=/(?:\\.|source)\\s+(?=/'
cen N3b "process-substitution source not reported" 's/if exp.startswith("<", st):/if False:/'
cen N3c "eval-of-source not reported" 's/if RE_SRC_EVAL.match(line, em.start()):/if False:/'
cen N6a "[ -v X ] not detected" '/# \[ -v NAME \]/d'
cen N6b "printenv \"\$n\" not flagged" 's/if RE_PRINTENV_VAR.search(l) or RE_PRINTENV_VAR.search(e):/if False:/'
# F5: region-owner mutants of the census, driven by tests/gates/test_gate_env_census_jq_regions.sh (baseline first)
jqr() { # id desc sed-expr ("-" = no mutation: the unmutated baseline, which must exit 3)
  local id="$1" desc="$2" expr="$3" d="$tmp/jqr_$1" jrc=0
  mkdir -p "$d/scripts/gates/lib" "$d/tests/gates"; cp "$census" "$d/scripts/gates/lib/gate_env_census.py"
  cp "$root/tests/gates/test_gate_env_census_jq_regions.sh" "$d/tests/gates/"
  if [ "$expr" != - ]; then
    sed -i "$expr" "$d/scripts/gates/lib/gate_env_census.py"
    if cmp -s "$d/scripts/gates/lib/gate_env_census.py" "$census"; then echo "  FAIL $id did not apply ($desc)"; bad=$((bad+1)); return; fi
  fi
  bash "$d/tests/gates/test_gate_env_census_jq_regions.sh" >/dev/null 2>&1 || jrc=$?
  if [ "$expr" = - ]; then
    if [ "$jrc" = 3 ]; then echo "  ok   $id jq-region test unmutated rc=3 (only tracked KNOWN-FAIL cases outstanding)"
    else echo "  FAIL $id jq-region test unmutated rc=$jrc (want 3): the R kills below would not be evidence"; bad=$((bad+1)); fi
  elif [ "$jrc" != 1 ]; then echo "  FAIL $id SURVIVED (jq-region rc=$jrc): $desc"; bad=$((bad+1)); else echo "  ok   $id killed: $desc"; fi
}
jqr R0 "baseline" -
jqr R1 "whitespace-prefixed NAME= not an assignment owner (RN1)" 's/^RE_OWNER_ASSIGN = re.compile(r"(?:^|\[\\s;/RE_OWNER_ASSIGN = re.compile(r"(?:^|[;/'
jqr R2 "+= not an assignment owner (RN7)" 's/^\(RE_OWNER_ASSIGN = .*\)\\+?=/\1=/'
jqr R3 "quoted regions of one line glued (no separator, F7)" 's/rl.append((owner, "\\n")); sq = None/sq = None/'
# N2 mutants: the detection gate with each new BLIND branch weakened must be caught by the blind-without-llmctl test
jevm() { local id="$1" desc="$2" expr="$3" d="$tmp/jev_$1"; mkdir -p "$d/scripts/gates" "$d/scripts/jev" "$d/scripts/lib"
  cp "$root/scripts/gates/cm_jev_detection.sh" "$d/scripts/gates/"; cp "$root/scripts/jev/"*.sh "$d/scripts/jev/"; cp "$root/scripts/lib/gate_env_override.sh" "$d/scripts/lib/"
  [ -d "$root/scripts/gates/lib" ] && cp -R "$root/scripts/gates/lib" "$d/scripts/gates/lib"
  sed -i "$expr" "$d/scripts/gates/cm_jev_detection.sh"; [ -z "${4:-}" ] || sed -i "$4" "$d/scripts/jev/lib_decide.sh"   # 4th arg: a second layer to remove too (defence in depth would otherwise make the mutant equivalent)
  if cmp -s "$d/scripts/gates/cm_jev_detection.sh" "$root/scripts/gates/cm_jev_detection.sh"; then echo "  FAIL $id did not apply"; bad=$((bad+1))
  elif JEV_GATE_UNDER_TEST="$d/scripts/gates/cm_jev_detection.sh" ROOT_OVERRIDE=1 bash "$root/tests/jev/test_detection_gate_blind_without_llmctl.sh" >/dev/null 2>&1; then echo "  FAIL $id SURVIVED: $desc"; bad=$((bad+1)); else echo "  ok   $id killed: $desc"; fi; }
jevm N2a "non-zero llmctl exit with JSON accepted" 's/elif \[ "$_src" -ne 0 \]; then/elif false; then/'
jevm N2b "wrong-shape status accepted (gate AND lib shape guards removed)" 's/^    elif ! printf .%s. "$st" | jq -e .type == "object".*$/    elif false; then/' 's/ || return 3$//; s/^  printf .%s. "$1" | jq -e .type == "object".*$//'
jevm N2c "missing lib not BLIND (declare -F check AND rc check removed)" 's/if ! declare -F jev_usable_live >\/dev\/null 2>&1; then/if false; then/; s/if \[ "$_lrc" -ne 0 \]; then/if false; then/'
[ "$bad" = 0 ] && echo "META PASS: CM-GATE-ENV-READS-ALLOWLISTED kills every mutant" || echo "META FAIL: $bad case(s)"
[ "$bad" = 0 ]
