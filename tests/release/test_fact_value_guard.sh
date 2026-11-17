#!/usr/bin/env bash
# tests/release/test_fact_value_guard.sh — exhaustive test of the fact-value guard and the calendar-date check of
# scripts/release/derive_release_facts.sh (the block between "# >>> fact-guard" and "# <<< fact-guard", sourced
# here on its own). Review of f4c6e8ab: N4 (control characters in printed values) and N5 (dates as real calendar
# dates).
# Oracle: Python's unicodedata, independent of the bash code under test. REJECT set = every code point whose
# general category is Cc (C0, DEL, C1 incl. NEL), Cf (bidi controls, zero-width characters, BOM, tag characters,
# soft hyphen, ...), Zl (LINE SEPARATOR) or Zp (PARAGRAPH SEPARATOR), each embedded between two letters, plus
# byte strings that are not UTF-8 (a lone continuation byte, an overlong form, an encoded surrogate, a code
# point above U+10FFFF, a truncated sequence). ACCEPT set = every other ASSIGNED code point (all planes), fed in
# chunks of 500. Both sets are control needles of each other: the run fails if either is empty or if any
# member is misjudged. The calendar check is compared with Python's datetime over every day of 1999-2101 plus
# malformed strings. DRF_SCRIPT overrides the script under test. Evidence class: gate-logic (PROVISIONAL).
set -u
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
S="${DRF_SCRIPT:-$ROOT/scripts/release/derive_release_facts.sh}"
pass=0; fail=0
ok(){ pass=$((pass+1)); echo "PASS $*"; }; bad(){ fail=$((fail+1)); echo "FAIL $*"; }
W="$(mktemp -d "${TMPDIR:-/tmp}/fvg.XXXXXX")"; : "${W:?}"
cleanup(){ [ -n "${W:-}" ] && [ -d "$W" ] && . "$ROOT/scripts/lib/safe_rm.sh" 2>/dev/null && safe_rm_rf "$W" 2>/dev/null; }
trap cleanup EXIT; trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
# the guard block, exactly as it stands in the script (one block, both markers present)
nb="$(grep -c '^# >>> fact-guard$' "$S")"; ne="$(grep -c '^# <<< fact-guard$' "$S")"
[ "$nb" = 1 ] && [ "$ne" = 1 ] && ok "one fact-guard block in the script" || { bad "fact-guard block markers: begin=$nb end=$ne (want 1 1)"; echo "RESULT: pass=$pass fail=$fail"; exit 1; }
sed -n '/^# >>> fact-guard$/,/^# <<< fact-guard$/p' "$S" >"$W/guard.sh"
python3 -I - "$W/cases.bin" "$W/dates.txt" <<'PY' || { echo "FAIL case generation"; exit 1; }
import sys, unicodedata, datetime
F = {"Cc", "Cf", "Zl", "Zp"}
rej, acc = [], []
for cp in range(1, 0x110000):
    if 0xD800 <= cp <= 0xDFFF:
        continue
    c = unicodedata.category(chr(cp))
    if c in F:
        rej.append(cp)
    elif c != "Cn":
        acc.append(cp)
out = []
for cp in rej:
    out.append(b"N U+%04X " % cp + b"a" + chr(cp).encode() + b"b")
for i in range(0, len(acc), 500):
    out.append(b"P chunk%d " % i + "".join(map(chr, acc[i:i + 500])).encode())
for name, raw in [("lone-cont", b"\x85"), ("overlong", b"\xc0\x80"), ("surrogate", b"\xed\xa0\x80"),
                  ("above-10FFFF", b"\xf4\x90\x80\x80"), ("truncated", b"\xe2\x80"), ("ff", b"\xff"),
                  ("extra-cont", b"\xe2\x82\xac\x80"), ("lead-at-end", b"\xc3")]:
    out.append(b"N " + name.encode() + b" x" + raw + b"y")
open(sys.argv[1], "wb").write(b"\0".join(out) + b"\0")
sys.stderr.write("unicode %s: reject=%d accept=%d\n" % (unicodedata.unidata_version, len(rej), len(acc)))
d = datetime.date(1999, 1, 1); lines = []
while d <= datetime.date(2101, 12, 31):
    lines.append("Y " + d.isoformat()); d += datetime.timedelta(days=1)
for s in ["2026-02-29", "2100-02-29", "1900-02-29", "2026-13-01", "2026-00-10", "2026-01-00", "2026-01-32",
          "2026-04-31", "2026-06-31", "2026-09-31", "2026-11-31", "9999-99-99", "2026-1-5", "26-01-01", "0000-01-01",
          "2026-01-015", "2026/01/01", "", "x", "2026-01-0"]:
    lines.append("N " + s)
for s in ["2024-02-29", "2000-02-29", "2026-01-01T10:00:00", "2026-01-01 next", "2026-12-31x"]:
    lines.append("Y " + s)
open(sys.argv[2], "w").write("\n".join(lines) + "\n")
PY
cat >"$W/drive.sh" <<'EOF'
. "$1"
np=0 nn=0 bad=0
while IFS= read -r -d '' l; do
  e="${l:0:1}"; rest="${l#* }"; name="${rest%% *}"; v="${rest#* }"
  if fact_text_ok "$v"; then r=P; else r=N; fi
  if [ "$r" = "$e" ]; then [ "$e" = P ] && np=$((np+1)) || nn=$((nn+1)); else bad=$((bad+1)); [ "$bad" -le 5 ] && echo "MISJUDGED $e $name"; fi
done <"$2"
echo "TEXT accept=$np reject=$nn misjudged=$bad"
dy=0 dn=0 db=0
while IFS= read -r l; do
  e="${l:0:1}"; v="${l:2}"
  if cal_date "$v"; then r=Y; else r=N; fi
  if [ "$r" = "$e" ]; then [ "$e" = Y ] && dy=$((dy+1)) || dn=$((dn+1)); else db=$((db+1)); [ "$db" -le 5 ] && echo "MISJUDGED-DATE $e '$v'"; fi
done <"$3"
echo "DATE valid=$dy invalid=$dn misjudged=$db"
EOF
res="$(LC_ALL=C bash "$W/drive.sh" "$W/guard.sh" "$W/cases.bin" "$W/dates.txt" 2>&1)"
printf '%s\n' "$res" | grep MISJUDGED | head -10
t="$(printf '%s\n' "$res" | grep '^TEXT ')"; dl="$(printf '%s\n' "$res" | grep '^DATE ')"
[[ $t =~ accept=([0-9]+)\ reject=([0-9]+)\ misjudged=([0-9]+) ]] || { bad "guard driver output: $res"; echo "RESULT: pass=$pass fail=$fail"; exit 1; }
[ "${BASH_REMATCH[1]}" -gt 500 ] && ok "accept set: ${BASH_REMATCH[1]} chunks accepted (positive control: more than 500)" || bad "accept set: ${BASH_REMATCH[1]} chunks"
[ "${BASH_REMATCH[2]}" -gt 200 ] && ok "reject set: ${BASH_REMATCH[2]} cases rejected (negative control: more than 200)" || bad "reject set: ${BASH_REMATCH[2]} rejected"
[ "${BASH_REMATCH[3]}" = 0 ] && ok "no code point or byte string misjudged" || bad "${BASH_REMATCH[3]} cases misjudged"
[[ $dl =~ valid=([0-9]+)\ invalid=([0-9]+)\ misjudged=([0-9]+) ]] || { bad "date driver output: $res"; echo "RESULT: pass=$pass fail=$fail"; exit 1; }
[ "${BASH_REMATCH[1]}" -gt 37000 ] && ok "dates: ${BASH_REMATCH[1]} real days accepted (positive control)" || bad "dates: ${BASH_REMATCH[1]} accepted"
[ "${BASH_REMATCH[2]}" -ge 20 ] && ok "dates: ${BASH_REMATCH[2]} non-dates rejected (negative control)" || bad "dates: ${BASH_REMATCH[2]} rejected"
[ "${BASH_REMATCH[3]}" = 0 ] && ok "no date misjudged" || bad "${BASH_REMATCH[3]} dates misjudged"
# key shape: the bracket part of a key cannot hold [ ] or =, and a key is lower-case letters, digits, underscores
cat >"$W/keys.sh" <<'EOF'
. "$1"
for k in 'base' 'open_status[Ready for testing]' 'open_states[UNSET/reproduced-live]' 'unmerged_refs_count[o]' 'open_status[]'; do fact_key_ok "$k" && echo "Y $k" || echo "N $k"; done
for k in 'open_status[a]=9' 'open_status[a]b]' 'open_status[a[b]' 'Base' '' '=x' 'a b' 'open_status[a' '9x'; do fact_key_ok "$k" && echo "Y! $k" || echo "N! $k"; done
EOF
kr="$(LC_ALL=C bash "$W/keys.sh" "$W/guard.sh" 2>&1)"
[ "$(printf '%s\n' "$kr" | grep -c '^Y ')" = 5 ] && ok "key shape: the 5 well-formed keys are accepted" || bad "key shape accept: $kr"
[ "$(printf '%s\n' "$kr" | grep -c '^N! ')" = 9 ] && ok "key shape: the 9 malformed keys are refused" || bad "key shape refuse: $kr"
# closure_day: the calendar day of a closure_date, alone or followed by T or a space (a time); nothing else
cat >"$W/cd.sh" <<'EOF'
. "$1"
for v in '2026-03-01' '2026-03-01T08:00:00' '2026-03-01 08:00'; do closure_day "$v" && [ "$CDAY" = 2026-03-01 ] && echo "Y $v" || echo "N $v"; done
for v in '2026-03-01x' '2026-03-01/' '' '2026-02-30' '2026-1-5' '9999-99-99' '2026-03-011'; do closure_day "$v" || [ -n "$CDAY" ] && echo "Y! $v" || echo "N! $v"; done
EOF
cr="$(LC_ALL=C bash "$W/cd.sh" "$W/guard.sh" 2>&1)"
[ "$(printf '%s\n' "$cr" | grep -c '^Y ')" = 3 ] && ok "closure_day: a date alone, with T and with a space give the day" || bad "closure_day accept: $cr"
[ "$(printf '%s\n' "$cr" | grep -c '^N! ')" = 7 ] && ok "closure_day: 7 non-closures give no day" || bad "closure_day refuse: $cr"
echo "RESULT: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
