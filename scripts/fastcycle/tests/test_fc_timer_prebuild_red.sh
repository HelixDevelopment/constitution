#!/bin/bash
# T015/T029 test: fc_timer wiring into pre_build_verification.sh
# (spec 004-fast-dev-cycles; plan.md T-A01; spec.md FR-001, SC-001; tasks.md T015, T028, T029)
#
# Purpose: prove pre_build_verification.sh writes ONE fc_timer row per section that RAN, by
#          reading a run's TSV and THAT SAME run's own stdout -- never two artifacts picked by
#          two independent sorts.
#
# T048 restart round-1 rewrite (2026-10-08, finding R1-B1 instance 1). The previous revision
# compared the lexically-last prebuild_full_run_*.log (one run) against the lexically-last
# qa-results/fastcycle/*/prebuild_sections.tsv (another run: a `zz_t015_final_confirm_*` copy
# always won that sort), so "row count == banner count" compared two unrelated runs (the
# log's own run actually had 183 rows vs 188 banners and would have FAILED); no newer run could
# ever be examined; FC_TIMER_RED_FULL_RUN=1 was ignored whenever any log existed; and the
# reviewer's mutation MD (every _fc_section_boundary call deleted) left it GREEN because no
# assertion ever executed pre_build_verification.sh's wiring. Every run below is now bound by
# a PINNED run id: the TSV is read at <tsv_root>/<that run id>/prebuild_sections.tsv, every
# row's run_id column must equal that id, and it is compared against that run's own stdout.
#
# Parts:
#   1. LIVE bounded run (default, always): runs the real pre_build_verification.sh for
#      FC_TIMER_RED_BOUND_S seconds (default 90) with FC_TIMER_RUN_ID pinned and a private
#      CAPTURE_TRIPLET_TSV_ROOT. Asserts: the TSV exists at the pinned path; >= 1 row; every row
#      carries the pinned run id; the ordered section codes of the TSV rows equal the first N
#      section banners of THIS run's stdout; and rows == banners or banners-1 (the section
#      running when the bound expired never closed -- pre_build has no exit flush; recorded,
#      not hidden). This is the part that catches a source regression (mutation MD).
#   2. FULL-depth evidence (when available): either FC_TIMER_RED_FULL_RUN=1 (runs the whole
#      suite now, ~17-24 min, same pinning as part 1) or, by default, the FC1 member of the
#      newest mode=real capture_fc_timer_triplet.sh manifest -- whose log and TSV are bound by
#      the manifest itself (log sha256 re-verified, every row's run_id must equal
#      <run>_<prefix>_FC1). Asserts rows == banners exactly, the ordered codes match, the
#      control-needle section has a row, and section-time-sum is within 2% of the span.
#      No manifest -> an honest SKIP, never a substitute file.
#
# Env: FC_TIMER_RED_BOUND_S (default 90), FC_TIMER_RED_FULL_RUN=1, FC_TIMER_RED_PREBUILD
#      (another pre_build copy -- used by the paired mutation runner; default the real one),
#      FC_TIMER_RED_EVIDENCE_DIR (default qa-results/fastcycle/us1/red/T015).
# Exit: 0 all pass/skip, 1 any FAIL, 2 setup error.
# Provenance of the banner shapes (6 decoration conventions, 188 runtime banners on the
# 2026-09-28/10-02 full runs): see git history of this file before 2026-10-08.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../../.." && pwd)"
PRE_BUILD="${FC_TIMER_RED_PREBUILD:-$ROOT/device/rockchip/rk3588/tests/pre_build_verification.sh}"
EVIDENCE_DIR="${FC_TIMER_RED_EVIDENCE_DIR:-$ROOT/qa-results/fastcycle/us1/red/T015}"
BOUND="${FC_TIMER_RED_BOUND_S:-90}"
NEEDLE_PRESENT="CM-COVENANT-114-182-PROPAGATION"
NEEDLE_FABRICATED="CM-FASTCYCLE-FABRICATED-NEEDLE-T015-DOES-NOT-EXIST"
BANNER_RE='^[^A-Za-z0-9]*[Ss][Ee][Cc][Tt][Ii][Oo][Nn][[:space:]]+[A-Za-z0-9][A-Za-z0-9-]*'

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

FAIL=0; N=0; SKIPPED=0
chk() { N=$((N + 1)); if [ "$2" = "1" ]; then echo "PASS[$N]: $1"; else echo "FAIL[$N]: $1"; FAIL=$((FAIL + 1)); fi; }
skip() { N=$((N + 1)); SKIPPED=$((SKIPPED + 1)); echo "SKIP[$N]: $1"; }

[ -f "$PRE_BUILD" ] || { echo "FATAL: pre_build_verification.sh not found at $PRE_BUILD"; exit 2; }
printf '%s' "$BOUND" | grep -qE '^[1-9][0-9]*$' || { echo "FATAL: FC_TIMER_RED_BOUND_S='$BOUND' is not a positive integer"; exit 2; }

# _codes: first "section <CODE>" token of each input line -> CODE (uppercased), one per line.
_codes() { awk '{ if (match($0, /[Ss][Ee][Cc][Tt][Ii][Oo][Nn][ \t]+[A-Za-z0-9][A-Za-z0-9-]*/)) { s=substr($0, RSTART, RLENGTH); sub(/^[Ss][Ee][Cc][Tt][Ii][Oo][Nn][ \t]+/, "", s); print toupper(s) } }'; }
# _banner_codes <stdout log>, _tsv_codes <tsv>
_banner_codes() { sed -E 's/\x1b\[[0-9;]*m//g' "$1" | grep -E "$BANNER_RE" | _codes; }
_tsv_codes() { awk -F'\t' 'NR>1 {print $3}' "$1" | _codes; }
_rows() { if [ -f "$1" ]; then tail -n +2 "$1" | grep -c . || true; else echo 0; fi; }
_all_runid() { awk -F'\t' -v v="$2" 'NR>1 {n++; if ($1 != v) bad=1} END {print (n>0 && !bad) ? 1 : 0}' "$1" 2>/dev/null || echo 0; }

# Control needle for the banner instrument itself (§11.4.273): a known banner shape and a
# known non-banner line through the SAME extractor.
printf '\033[0;36m  SECTION Q: probe\033[0m\n  ✓ CM-X: not a banner section y\n── Section CN-PROBE — z ──\n' > "$TMP/needle.log"
chk "control needle: the banner extractor yields exactly [Q, CN-PROBE] for a 2-banner probe ($(_banner_codes "$TMP/needle.log" | tr '\n' ' '))" \
  "$([ "$(_banner_codes "$TMP/needle.log" | tr '\n' ' ')" = "Q CN-PROBE " ] && echo 1 || echo 0)"
chk "control needle: '$NEEDLE_PRESENT' present in the pre-build source, fabricated needle absent" \
  "$(grep -qF -- "$NEEDLE_PRESENT" "$PRE_BUILD" && ! grep -qF -- "$NEEDLE_FABRICATED" "$PRE_BUILD" && echo 1 || echo 0)"

# run_pinned <run_id> <tsv_root> <log> [timeout_s] -- the real pre_build, pinned run id,
# private TSV root and TMPDIR. Prints the exit status.
run_pinned() {
  local rid="$1" root="$2" log="$3" bound="${4:-}"
  mkdir -p "$TMP/tmp.$rid"
  # cwd = the repo root, as build.sh / the capture harness run it: pre_build is cwd-DEPENDENT
  # (measured 2026-10-08: started from this tests/ dir it aborts rc=2 in Section BN after ~14 s;
  # recorded as a deferred pre_build finding, outside this file's scope).
  cd "$ROOT" || return 1
  if [ -n "$bound" ]; then
    TMPDIR="$TMP/tmp.$rid" FC_TIMER_RUN_ID="$rid" CAPTURE_TRIPLET_TSV_ROOT="$root" \
      timeout -k 5 "$bound" bash "$PRE_BUILD" >"$log" 2>&1 </dev/null
  else
    TMPDIR="$TMP/tmp.$rid" FC_TIMER_RUN_ID="$rid" CAPTURE_TRIPLET_TSV_ROOT="$root" \
      bash "$PRE_BUILD" >"$log" 2>&1 </dev/null
  fi
  echo "$?"
}

# full_depth_checks <label> <log> <tsv> <run_id>
full_depth_checks() {
  local label="$1" log="$2" tsv="$3" rid="$4" rows banners
  rows="$(_rows "$tsv")"
  _banner_codes "$log" > "$TMP/fb.codes"; _tsv_codes "$tsv" > "$TMP/ft.codes"
  banners="$(wc -l < "$TMP/fb.codes" | tr -d ' ')"
  chk "$label: every TSV row carries this run's id '$rid'" "$(_all_runid "$tsv" "$rid")"
  chk "$label: TSV rows ($rows) == this run's own section banners ($banners), and > 0" \
    "$([ "$rows" -gt 0 ] && [ "$rows" = "$banners" ] && echo 1 || echo 0)"
  chk "$label: the ordered section codes of the TSV rows equal the banner order of the SAME run" \
    "$(cmp -s "$TMP/fb.codes" "$TMP/ft.codes" && echo 1 || echo 0)"
  local sec
  sec="$(python3 - "$PRE_BUILD" "$NEEDLE_PRESENT" <<'PYEOF'
import re, sys
lines = open(sys.argv[1], encoding="utf-8", errors="replace").read().splitlines()
n = next((i for i, l in enumerate(lines) if sys.argv[2] in l), None)
last = None
if n is not None:
    for l in lines[: n + 1]:
        m = re.search(r"_fc_section_boundary\s+'([^']*)'", l) or re.search(r'log_section\s+"([^"]*)"', l)
        if m:
            last = m.group(1)
print(last or "")
PYEOF
)"
  chk "$label: the control-needle's enclosing section ('$sec') has a TSV row" \
    "$([ -n "$sec" ] && awk -F'\t' -v w="$sec" 'NR>1 && $3==w {f=1} END {exit !f}' "$tsv" && echo 1 || echo 0)"
  local ts
  ts="$(python3 - "$tsv" <<'PYEOF'
import sys
rows = [l.rstrip("\n").split("\t") for l in open(sys.argv[1], encoding="utf-8", errors="replace").readlines()[1:] if l.strip()]
try:
    s = [int(r[3]) for r in rows]; e = [int(r[4]) for r in rows]; d = [int(r[5]) for r in rows]
except (ValueError, IndexError):
    print("PARSE_ERROR 0"); sys.exit(0)
span = (max(e) - min(s)) / 1e6 if rows else 0
print("OK %.4f" % (abs(sum(d) - span) / span * 100.0) if span > 0 else "ZERO_SPAN 0")
PYEOF
)"
  chk "$label: section-time-sum within 2% of the wall-clock span (residue: $ts)" \
    "$(case "$ts" in OK\ *) python3 -c "import sys; sys.exit(0 if ${ts#OK } <= 2.0 else 1)" && echo 1 || echo 0 ;; *) echo 0 ;; esac)"
}

echo "=== Part 1: LIVE bounded run (${BOUND}s) of $PRE_BUILD, pinned run id ==="
RID1="t015_live_$$"
rc="$(run_pinned "$RID1" "$TMP/tsv" "$TMP/live.log" "$BOUND")"
T1="$TMP/tsv/$RID1/prebuild_sections.tsv"
R1="$(_rows "$T1")"
_banner_codes "$TMP/live.log" > "$TMP/lb.codes"; _tsv_codes "$T1" > "$TMP/lt.codes" 2>/dev/null || : > "$TMP/lt.codes"
B1="$(wc -l < "$TMP/lb.codes" | tr -d ' ')"
echo "INFO: live run rc=$rc (124 = bound reached), $B1 banner(s) in its stdout, $R1 TSV row(s) at $T1"
chk "live: the pinned TSV exists and has >= 1 row ($R1)" "$([ -f "$T1" ] && [ "$R1" -ge 1 ] && echo 1 || echo 0)"
chk "live: every row carries the pinned run id '$RID1'" "$(_all_runid "$T1" "$RID1")"
case "$rc" in
  0|1|124) : ;;
  *) echo "INFO: pre_build ended ABNORMALLY (rc=$rc) before the bound -- last lines of its own stdout:"
     sed -E 's/\x1b\[[0-9;]*m//g' "$TMP/live.log" | tail -n 6 | cut -c1-200 ;;
esac
# A run that completed (rc 0/1) closes its last section; a run cut by the bound (124) or
# ending abnormally leaves exactly the running section open (pre_build has no exit flush).
chk "live: rows ($R1) == banners ($B1) for a completed run, or banners-1 when the run was cut (rc=$rc)" \
  "$([ "$R1" -ge 1 ] && { [ "$R1" = "$B1" ] || { [ "$rc" != 0 ] && [ "$rc" != 1 ] && [ "$R1" = $((B1 - 1)) ]; }; } && echo 1 || echo 0)"
chk "live: the TSV's ordered section codes equal the first $R1 banner codes of the SAME run's stdout" \
  "$([ "$R1" -ge 1 ] && head -n "$R1" "$TMP/lb.codes" | cmp -s - "$TMP/lt.codes" && echo 1 || echo 0)"

echo "=== Part 2: FULL-depth evidence bound to one run ==="
if [ "${FC_TIMER_RED_FULL_RUN:-0}" = 1 ]; then
  RID2="t015_full_$$"
  echo "INFO: FC_TIMER_RED_FULL_RUN=1 -- running the whole suite now (~17-24 min)"
  rc2="$(run_pinned "$RID2" "$TMP/tsv" "$TMP/full.log")"
  echo "INFO: full run rc=$rc2"
  full_depth_checks "full run $RID2" "$TMP/full.log" "$TMP/tsv/$RID2/prebuild_sections.tsv" "$RID2"
else
  # Newest mode=real triplet manifest, chosen by its CONTENT run_id (a timestamp), ties refused.
  best=""; best_id=""; ties=0
  if [ -d "$EVIDENCE_DIR" ]; then
    while IFS= read -r -d '' mf; do
      [ "$(grep -c '^mode=real$' "$mf")" = 1 ] || continue
      id="$(sed -n 's/^run_id=//p' "$mf" | head -n1)"
      printf '%s' "$id" | grep -qE '^[0-9]{8}T[0-9]{6}Z$' || continue
      if [ -z "$best_id" ] || [ "$id" \> "$best_id" ]; then best="$mf"; best_id="$id"; ties=0
      elif [ "$id" = "$best_id" ]; then ties=$((ties + 1)); fi
    done < <(find "$EVIDENCE_DIR" -maxdepth 1 -name '*.triplet' -print0 2>/dev/null)
  fi
  if [ -z "$best" ]; then
    skip "full-depth checks: no mode=real triplet manifest in $EVIDENCE_DIR (run capture_fc_timer_triplet.sh, or FC_TIMER_RED_FULL_RUN=1) -- no substitute file is ever read"
  elif [ "$ties" != 0 ]; then
    chk "full-depth evidence: newest run id $best_id is shared by $((ties + 1)) manifests -- ambiguous, nothing compared" "0"
  else
    pfx="$(sed -n 's/^prefix=//p' "$best" | head -n1)"
    flog="$(dirname -- "$best")/$(sed -n 's/^member\.FC1\.log=//p' "$best" | head -n1)"
    fsha="$(sed -n 's/^member\.FC1\.log_sha256=//p' "$best" | head -n1)"
    ftsv="$(sed -n 's/^member\.FC1\.tsv=//p' "$best" | head -n1)"
    echo "INFO: evidence = FC1 member of $best ($flog + $ftsv)"
    if [ ! -f "$flog" ] || [ "$(sha256sum "$flog" | awk '{print $1}')" != "$fsha" ]; then
      chk "full-depth evidence: FC1 log $flog missing or its sha256 differs from the manifest" "0"
    elif [ ! -f "$ftsv" ]; then
      skip "full-depth checks: the manifest's FC1 TSV $ftsv is no longer on disk -- nothing to compare"
    else
      full_depth_checks "triplet $best_id FC1" "$flog" "$ftsv" "${best_id}_${pfx}_FC1"
    fi
  fi
fi

echo "SUMMARY: $((N - FAIL - SKIPPED)) pass / $FAIL fail / $SKIPPED skip of $N assertions"
[ "$FAIL" = 0 ]
