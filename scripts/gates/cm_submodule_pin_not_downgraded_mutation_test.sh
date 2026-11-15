#!/usr/bin/env bash
# cm_submodule_pin_not_downgraded_mutation_test.sh — §1.1 paired-mutation meta-test for CM-SUBMODULE-PIN-NOT-DOWNGRADED.
# Part 1: fixtures vs the gate (GATE_UNDER_TEST overrides the path, used to show RED on an older gate; then Part 2 is
#         skipped because the mutant seds are written against the current gate).
# Part 2: mutants of a scratch gate copy; each MUST change the verdict vector (be killed). Includes the round-2
#         reviewer mutants RM1-RM5, the round-3 reviewer mutants RV1, RV3-RV7, the round-4 reviewer mutants RM8-RM14
#         and their killer fixtures (K1-K14), the round-5 mutants for M-1, M-2 and N-4, the round-5 reviewer mutants
#         NM1-NM9 with their killers KNM1-KNM6, KNM9, and (round 6) one mutant per remaining guard of the gate's class
#         inventory (fixtures in inventory()). Mutants run in parallel, MUT_JOBS at a time (default 3), each in its own
#         temp dir. MUT_ONLY=<regex> restricts Part 2 to mutant names matching it (diagnosis only; a full proof runs all).
# Round 8 (CON-146, re-minted 2026-11-11 as CON-194 and again at the merge of main f25acdee as CON-280; later mentions keep CON-146): the four round-7 reviewer probes are adopted verbatim (cm_submodule_pin_not_downgraded_probes/,
#         members8), the "UNCONFIRMED-equivalent" category is retired (its three claims were false), the member mutants
#         below the inventory's granularity are GENERATED (cm_submodule_pin_not_downgraded_members.py, ledger
#         cm_submodule_pin_not_downgraded_members.tsv), every date fixture is computed inside the job that uses it and a
#         job on another date than the real vector is INCONCLUSIVE and re-run, never killed (a `date` skew self-test
#         proves it), a count or message change counts as `ch`, the dynamic lint has a control needle, and each job's
#         fixture tree is deleted once its result is written.
# Round 9 (CON-146, review of round 8 F1-F6): GNU date is pinned first on PATH and the host's other date (uutils) is the
#         alternative: the real vector and every equivalence claim must hold under both; four false claims are withdrawn
#         (their members are killed by the new fixtures ZSID, ZSAUTH, YEAR5); the reviewer mutants RV8-01/02 are adopted;
#         the generator covers tests whose body holds `]` and the `[[ ]]` compares (CMPS).
# Round 10 (CON-194, now CON-280, review of round 9 N1-N5, §11.4.276(E) structural pass): every date / number compare of the gate
#         gets a boundary pair from one table (members10: EXPBND, HORBND, DAYSBND, PFXBND, ITEMBND, LEVBND); the strip()
#         fixtures use every python isspace() character (29, enumerated; Zs is a sub-needle), not only Zs (WSID, WSAUTH),
#         plus the config's no-trim site (CONFWS); the reviewer mutants RV9-02, RV9-10, RV9-11 are adopted verbatim, and
#         three off-by-one mutants (lev-gt-1, days-min-2, prefix-min-3) pair the new boundaries. RV9-05 (base compared on
#         12 characters) survived the first round-10 run (review N4): every exact SHA equality of the gate now gets the
#         same generated near-miss set (SHANEAR, SPENTNEAR), with RV9-05 adopted verbatim and seven sibling mutants.
# Round 11 (CON-194, now CON-280, review of round 10 F1-F7, §11.4.276(E)(3) structural round): the fixtures are no longer chosen per
#         reported site. A SITE TABLE (cm_submodule_pin_not_downgraded_sites.tsv) has one row per exact-compare and
#         character-set site of the gate and the hook, found by a control-needled CENSUS
#         (cm_submodule_pin_not_downgraded_sites.py); the static site lint refuses a site without a row, a row without a
#         site, and a data row (sha, path, ident, date, num, text, charset) without a near-miss fixture key in want and a
#         mutant (or a stated "not constructible" / "equivalent" reason); the dynamic site lint refuses a data row whose
#         mutant was not killed. members11 runs the fixtures the table names. The gate's "today" is the UTC date now (F2),
#         so the whole suite runs with TZ=UTC and TZPAIR proves the pin; a NUL byte in waiver data is refused (F3).
# Round 11, screen-3 follow-up (2026-11-13): screen 3 failed 4 equivalence claims as "killed" at the end of a run that
#         crossed midnight. Measured cause: the session scope hit its pids.max (a foreign fork storm started 00:35:57),
#         a refused fork changed a job's vector (reproduced: BASEFORM=1,1/B became 0,0/X on one date, with "fork failed:
#         Resource temporarily unavailable"), and the job's stderr went to /dev/null. Two fixes: (1) a classify with a
#         resource-failure signature on stderr, or a growth of the cgroup pids `max` / `oom_kill` counters, is
#         INCONCLUSIVE and re-run, never killed (resclean, rsafe; self-test selftest-resource-failure, which reads
#         "killed" with resclean disabled); (2) every `date` the suite and the gate run is pinned to ONE injected instant
#         SUITE_NOW (default: noon UTC of the start day), with a needle that stops the run when the pin is blind.
# Round 12 (CON-046, review r11 F1): the authoriser normalisation f = NFC(casefold(NFC(s))) gets one killer per NFC
#         call (AUTHNORM fields 7 and 8), the seven reviewer mutants RVR11-01..07 are adopted verbatim (the reviewer's
#         add_rv_mutants.py applied unchanged), and the member generator has a NORM kind (each normalize call dropped on
#         its own, casefold -> lower, the normaliser dropped on each == operand). The gate itself is unchanged.
# The verdict vector includes the waiver LIFECYCLE class (round 4): every way a reviewed row could be reused by a
#         commit it was not reviewed for (snapshot, amend, merge, conflicted merge, squash, --no-commit merge,
#         cherry-pick, rebase, leftover worktree rows, base-field forms), each through `git commit` with the hook.
# Part 3: the hook end to end through `git commit`, with the hook COPIED next to the gate under test (so GATE_UNDER_TEST
#         reaches it too): plain repo, a linked worktree with a REAL submodule (gitdir under .git/worktrees/<wt>/modules),
#         the round-2 waiver-persistence replay, and the layout SKIP.
# Fixtures are throwaway repos under a mktemp dir; the real repo is never touched. HOME is a temp dir.
# Exit 0 proof holds · 1 misclassified/survivor/hook failure · 2 env error.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd -P)"; gate="${GATE_UNDER_TEST:-$here/cm_submodule_pin_not_downgraded.sh}"
hook="$here/../hooks/pre-commit-submodule-pin-not-downgraded"
[ -r "$gate" ] || { echo "META: gate missing" >&2; exit 2; }
[ -r "$hook" ] || { echo "META: hook missing" >&2; exit 2; }
tmp="$(mktemp -d)"; [ -n "$tmp" ] && [ -d "$tmp" ] || { echo "META: mktemp failed" >&2; exit 2; }
trap 'rm -rf "${tmp:?}"' EXIT; mkdir -p "$tmp/home"; export HOME="$tmp/home"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_NOSYSTEM=1
# round 11 (F2): the gate decides on the UTC date; every fixture date is computed in UTC too, so a run between local
# midnight and UTC midnight cannot disagree with the gate (TZPAIR runs the gate itself under other zones)
export TZ=UTC
unset EMAIL
git config --global protocol.file.allow always; git config --global init.defaultBranch main; git config --global advice.graftFileDeprecated false
# ── round 9 (CON-146, review F3): the date implementation is PINNED. The gate needs `date -d` (GNU coreutils). The suite
# finds GNU date (`date`, `gnudate` or `gdate`, the first whose --version says "GNU coreutils"), puts it first on PATH as
# `date` for everything it runs, and prints its version. When the host's default `date` is NOT GNU (uutils on the
# reference host), that is the ALTERNATIVE date: the real gate's whole vector and every equivalence claim (whole-suite
# survival and the targeted probe with its control) are run under it as well (review F2), and both must hold.
gnud=""; for c in date gnudate gdate; do p="$(command -v "$c" 2>/dev/null)" || continue
  "$p" --version 2>/dev/null | head -1 | grep -q 'GNU coreutils' && { gnud="$p"; break; }; done
[ -n "$gnud" ] || { echo "META: GNU date not found (date, gnudate, gdate); the gate needs GNU date" >&2; exit 2; }
suite_now="${SUITE_NOW:-$("$gnud" -u +%Y-%m-%dT12:00:00Z)}" # noon UTC of the day the screen starts, unless injected
[[ "$suite_now" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] && "$gnud" -d "$suite_now" +%F >/dev/null 2>&1 ||
  { echo "META: SUITE_NOW '$suite_now' is not an instant of the form YYYY-MM-DDTHH:MM:SSZ" >&2; exit 2; }
echo "clock (injected, one instant for the whole run): $suite_now"
# mkpin dir real: `date` in dir runs real with the clock pinned to $suite_now. The gate reads the clock once (a bare
# `date +%Y-%m-%d`) and only passes absolute dates to -d; the suite passes `+N days`, `yesterday` and absolute dates.
# So: no -d -> `-d $suite_now`; a relative -d value (+N..., -N..., yesterday, tomorrow, today, now) -> "$suite_now <value>";
# any other value (absolute, or text the gate must refuse) is passed through unchanged; --version/--help untouched.
mkpin() { mkdir -p "$1"; { printf '#!/bin/bash\nnow=%q; real=%q\n' "$suite_now" "$2"; cat <<'PIN'
rel() { case "$1" in [+-][0-9]*|yesterday|tomorrow|today|now) printf '%s %s' "$now" "$1" ;; *) printf '%s' "$1" ;; esac; }
a=(); d=0; nx=0
for x in "$@"; do
  if [ "$nx" = 1 ]; then nx=0; a+=("$(rel "$x")"); continue; fi
  case "$x" in -d|--date) d=1; nx=1; a+=("$x") ;; --date=*) d=1; a+=("--date=$(rel "${x#--date=}")") ;;
    -d?*) d=1; a+=("-d$(rel "${x#-d}")") ;; --version|--help) d=1; a+=("$x") ;; *) a+=("$x") ;; esac
done
[ "$d" = 1 ] || a=(-d "$now" "${a[@]}")
exec "$real" "${a[@]}"
PIN
  } >"$1/date"; chmod +x "$1/date"; }
hostd="$(command -v date)"; altd=""; mkpin "$tmp/dpin/gnu" "$gnud"
if ! "$hostd" --version 2>/dev/null | head -1 | grep -q 'GNU coreutils'; then altd="$hostd"; mkpin "$tmp/dpin/alt" "$altd"; fi
export PATH="$tmp/dpin/gnu:$PATH"; altp="$tmp/dpin/alt:$PATH"
echo "date (pinned, first on PATH): $gnud: $(date --version | head -1)"
if [ -n "$altd" ]; then echo "date (alternative, the host default): $altd: $(PATH="$altp" date --version 2>/dev/null | head -1)"
else echo "date (alternative): none, the host default date is GNU; the alternative-date runs are skipped"; fi
# needle for the clock pin (CON-046 round 11, screen-3 follow-up): every `date` the suite and the gate run reads ONE
# injected instant (SUITE_NOW), so no part of a screen can see another day. Under both dates: a bare read prints the
# injected day, a relative -d counts from it, an absolute -d is untouched; else the pin is blind and the run stops.
for dp in "$tmp/dpin/gnu" ${altd:+"$tmp/dpin/alt"}; do
  ck="$(PATH="$dp:$PATH" date +%F)/$(PATH="$dp:$PATH" date -d '+1 days' +%F)/$(PATH="$dp:$PATH" date -d yesterday +%F)/$(PATH="$dp:$PATH" date -d 2000-01-01 +%F)"
  wk="${suite_now%%T*}/$("$gnud" -d "$suite_now +1 days" +%F)/$("$gnud" -d "$suite_now yesterday" +%F)/2000-01-01"
  [ "$ck" = "$wk" ] || { echo "META: the clock pin in $dp is blind: got $ck, want $wk (SUITE_NOW $suite_now)" >&2; exit 2; }
done
# needle for the YEAR5 fixture (review F1/F2): the pinned date round-trips a five-digit year (GNU 9.7 does), else the
# fixture could not see the year member of the expiry regex and its zero would prove nothing
[ "$(date -d 20269-01-01 +%Y-%m-%d 2>/dev/null)" = 20269-01-01 ] || { echo "META: the pinned date does not round-trip a five-digit year (YEAR5 would be blind)" >&2; exit 2; }
# the Unicode Zs class (space separators), enumerated from python's unicodedata, NUL-separated (review F4, RV8-01/02)
mapfile -d '' zsl < <(python3 -I -c 'import sys,unicodedata
sys.stdout.buffer.write(b"".join(chr(c).encode()+b"\0" for c in range(0x110000) if unicodedata.category(chr(c))=="Zs"))')
[ "${#zsl[@]}" -ge 17 ] || { echo "META: the Unicode Zs enumeration found ${#zsl[@]} characters (expected 17 or more)" >&2; exit 2; }
zscat="$(printf '%s' "${zsl[@]}")"; echo "Unicode Zs: ${#zsl[@]} characters enumerated"
# round 10 (CON-194, review N2): the gate's whitespace semantics is python str.isspace() (strip() with no argument),
# which is WIDER than Zs: it adds the Cc whitespace (\t \n \v \f \r, U+001C..U+001F, U+0085) and Zl/Zp (U+2028,
# U+2029). The fixtures WSID / WSAUTH (members10) are built from this set, enumerated here, never typed by hand; Zs stays
# as a sub-needle: every Zs character must be in it, and so must the three characters the round-9 review found missing
# from the Zs fixtures (U+0085, U+2028, U+2029).
mapfile -d '' wsl < <(python3 -I -c 'import sys
sys.stdout.buffer.write(b"".join(chr(c).encode()+b"\0" for c in range(0x110000) if chr(c).isspace()))')
wsck="$(python3 -I -c 'import sys,unicodedata
w={chr(c) for c in range(0x110000) if chr(c).isspace()}; z={chr(c) for c in range(0x110000) if unicodedata.category(chr(c))=="Zs"}
print("ok" if z<=w and {"\x85","\u2028","\u2029"}<=w and len(w)>=29 else "bad %d"%len(w))')"
[ "$wsck" = ok ] && [ "${#wsl[@]}" -ge 29 ] || { echo "META: the isspace() enumeration is wrong (${#wsl[@]} characters, check $wsck)" >&2; exit 2; }
wscat="$(printf '%s' "${wsl[@]}")"; wsrow=(); for z in "${wsl[@]}"; do case "$z" in $'\t'|$'\n') ;; *) wsrow+=("$z") ;; esac; done
echo "Unicode isspace(): ${#wsl[@]} characters enumerated (Zs ${#zsl[@]} of them; ${#wsrow[@]} can sit inside a TSV field)"
# round 11 (review r10 F1): the identity fields reach the gate through `git var`, and git strips some whitespace from
# the ends of a name or email itself (bytes <= 0x20) and removes `<`, `>` and newline anywhere. A pad git strips can
# never reach the gate's strip(), so the identity fixture (WSID4) uses exactly the isspace() characters git KEEPS at
# the end of a name AND of an email, MEASURED here through `git var` (never typed). Needles: U+2028 must be kept (the
# character of the round-10 finding), the ASCII space must be stripped (git's own crud rule); else the measurement is blind.
mapfile -d '' gkl < <(for c in "${wsl[@]}"; do
  id="$(GIT_COMMITTER_NAME="t$c" GIT_COMMITTER_EMAIL="t@t$c" git var GIT_COMMITTER_IDENT 2>/dev/null)" || continue
  [ "${id%% <*}" = "t$c" ] && m="${id#*<}" && [ "${m%%>*}" = "t@t$c" ] && printf '%s\0' "$c"; done)
gkcat="$(printf '%s' "${gkl[@]}")"
case "$gkcat" in *$'\xe2\x80\xa8'*) ;; *) echo "META: git-kept whitespace measurement blind (U+2028 not kept)" >&2; exit 2 ;; esac
case "$gkcat" in *' '*) echo "META: git-kept whitespace measurement blind (ASCII space kept)" >&2; exit 2 ;; esac
echo "isspace() characters git keeps at the end of a name and an email: ${#gkl[@]} (measured through git var)"
setdates() { # R7-7 (round 8): every date fixture is computed at the start of the classify that uses it (inside its own
  # job), and the job's vector carries the date it started and ended on; a job whose dates differ is INCONCLUSIVE
  d10="$(date -d '+10 days' +%F)"; d30="$(date -d '+30 days' +%F)"; d31="$(date -d '+31 days' +%F)"
  d45="$(date -d '+45 days' +%F)"; today="$(date +%F)"; }
setdates
vec() { local v=" $1"; v="${v% DATE=*}"; echo "${v# }"; }   # a classify result without its date stamp
stamp() { case "$1" in *" DATE="*) echo "${1##* DATE=}" ;; *) echo none ;; esac; } # START~END of a classify result
jv() { # real-result job-result -> killed | survived | inconclusive (dates differ, or a job crossed midnight: never killed)
  local a b; a="$(stamp "$1")"; b="$(stamp "$2")"
  if [ "$a" = none ] || [ "$a" != "$b" ] || [ "${a%~*}" != "${a#*~}" ]; then echo inconclusive
  elif [ "$(vec "$1")" = "$(vec "$2")" ]; then echo survived; else echo killed; fi; }
# CON-046 round 11, screen-3 follow-up: a fork or memory failure inside a classify (the process cap of the session
# scope was hit: `fork failed: Resource temporarily unavailable`) changes the vector without any change of the gate, and
# was read as `killed`. A classify whose stderr shows a resource failure is therefore never a verdict: resclean takes a
# result file and its stderr file and drops the date stamp of the result when the stderr matches, so jv reads it as
# INCONCLUSIVE and the job is re-run (and stays BAD if it fails the same way again).
resre='fork: retry|fork failed|cannot fork|Resource temporarily unavailable|Cannot allocate memory|Too many processes'
resfail() { [ -s "$1" ] && grep -qE "$resre" "$1"; }
# Most gate runs send their stderr to a file or /dev/null, so the kernel's own counters are read too: cgev prints the
# sum of the `max` events (fork refused by pids.max) and `oom_kill` events of this process's cgroup and every ancestor.
# A classify during which the sum grew is INCONCLUSIVE as well, even when the refused fork was another process's (the
# conservative reading, §11.4.201(4)): the job cannot show that none of ITS forks was refused. Unreadable -> "none".
cgev() { local c s=0 f n k any=0; c="$(sed -n 's/^0:://p' /proc/self/cgroup 2>/dev/null)"; [ -n "$c" ] || { echo none; return; }
  # (memory.events also has a `max` line: it counts reclaim at memory.max, which fails nothing, so only its oom_kill
  # line is read; measured 2026-11-13: app.slice memory.events max 44367 against oom_kill 6)
  while :; do for f in "/sys/fs/cgroup$c/pids.events" "/sys/fs/cgroup$c/memory.events"; do [ -r "$f" ] || continue
      case "$f" in *pids.events) k=max ;; *) k=oom_kill ;; esac
      n="$(awk -v k="$k" '$1==k{t+=$2} END{print t+0}' "$f")"; s=$((s+n)); any=1; done
    [ "$c" = / ] || [ -z "$c" ] && break; c="$(dirname "$c")"; done
  [ "$any" = 1 ] && echo "$s" || echo none; }
resclean() { # result-file stderr-file events-before
  local e1; e1="$(cgev)"
  if resfail "$2" || { [ "$3" != none ] && [ "$e1" != none ] && [ "$e1" -gt "$3" ]; }; then
    sed -i 's/ DATE=[^ ]*$//' "$1"; echo "events $3->$e1 $(grep -m1 -E "$resre" "$2" 2>/dev/null)" >"$1.resfail"; else rm -f "$1.resfail"; fi; }
rsafe() { # cmd...: run in this shell with stdout captured; up to 3 tries while a resource failure is seen; sets RS
  # (the output; a classify result loses its date stamp when every try failed) and RSF (1 when the last try failed)
  local i e0 f="$tmp/rsafe.err"; for i in 1 2 3; do e0="$(cgev)"; RS="$("$@" 2>"$f")"; cat "$f" >&2; printf '%s\n' "$RS" >"$tmp/rsafe.out"
    resclean "$tmp/rsafe.out" "$f" "$e0"; [ -e "$tmp/rsafe.out.resfail" ] || { RSF=0; rm -f "$f"; return 0; }
    echo "note resource failure during '$1' (try $i of 3): $(cat "$tmp/rsafe.out.resfail")"; done
  RS="$(cat "$tmp/rsafe.out")"; RSF=1; rm -f "$f" "$tmp/rsafe.out.resfail"; }
cg0="$(cgev)"; echo "cgroup pids/oom event counter: $cg0 (none = unreadable: only stderr signatures are checked)"
bad=0; SUBN=sub; realgit="$(command -v git)"

mk() { # sets globals R A B S (no subshell); submodule dir name $SUBN; super pins B
  local d; d="$(mktemp -d "$tmp/fx.XXXXXX")"; mkdir -p "$d/super/$SUBN"; git -C "$d/super/$SUBN" init -q
  git -C "$d/super/$SUBN" commit -q --allow-empty -m A; A=$(git -C "$d/super/$SUBN" rev-parse HEAD)
  git -C "$d/super/$SUBN" commit -q --allow-empty -m B; B=$(git -C "$d/super/$SUBN" rev-parse HEAD)
  git -C "$d/super/$SUBN" checkout -q -b side "$A"; git -C "$d/super/$SUBN" commit -q --allow-empty -m S; S=$(git -C "$d/super/$SUBN" rev-parse HEAD)
  git -C "$d/super" init -q; git -C "$d/super" update-index --add --cacheinfo 160000,"$B","$SUBN"
  git -C "$d/super" commit -q -m base; R="$d/super"
}
mknopy() { mkdir -p "$tmp/nopy"; for n in git awk date env cat dirname bash tr wc; do ln -sf "$(command -v "$n")" "$tmp/nopy/$n"; done; } # a PATH without python3 (its date is the current PATH's)
mk2() { mk; cp -a "${R:?}/sub" "$R/sub2"; git -C "$R" update-index --add --cacheinfo 160000,"$B",sub2; git -C "$R" commit -q -m base2; }
stage() { git -C "$1" update-index --cacheinfo 160000,"$2","${3:-$SUBN}"; }
waive() { printf '%b' "$2" >"${1:?}/.submodule_pin_waivers"; git -C "$1" add .submodule_pin_waivers; }
conf() { printf '%b' "$2" >"${1:?}/.submodule_pin_gate.conf"; git -C "$1" add .submodule_pin_gate.conf; }
wf() { printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6" "${7:-$(git -C "${r:?}" rev-parse HEAD)}"; } # path old new authoriser expiry item [base, default HEAD of $r]
run() { # repo gate [env assignments / -u X ...] [-- gate args...]; output in $tmp/out
  local r="$1" g="$2"; shift 2; local e=()
  while [ $# -gt 0 ] && [ "$1" != -- ]; do e+=("$1"); shift; done; [ "${1:-}" = -- ] && shift
  env "${e[@]}" bash "$g" --root "$r" "$@" >"$tmp/out" 2>&1; local rc=$?
  resfail "$tmp/out" && echo "RESOURCE FAILURE in a gate run: $(grep -m1 -E "$resre" "$tmp/out")" >&2 # seen by resclean
  echo "$rc"; }
cnt() { grep -c -- "$1" "$tmp/out"; }
classify() { # gate-path -> one-line verdict vector, then ` DATE=<start>~<end>` (R7-7)
  local g="$1" out="" r i e w gd o c c2 c3 c4 c5 lnk ds
  setdates; ds="$today"
  mk;r=$R; stage "$r" "$A"; out+="DOWN=$(run "$r" "$g") "
  mk;r=$R; out+="NOCHANGE=$(run "$r" "$g") "
  mk;r=$R; stage "$r" "$S"; out+="DIVERGED=$(run "$r" "$g")/$(cnt '^CM-SUBMODULE-PIN-NOT-DOWNGRADED: WARN') "
  mk;r=$R; stage "$r" "$A"; git -C "$r" commit -q -m down; stage "$r" "$B"; out+="FORWARD=$(run "$r" "$g") "
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" me "$d10" CON-046)\n"; out+="WAIVED=$(run "$r" "$g") "
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" me 2000-01-01 CON-046)\n"; out+="EXPIRED=$(run "$r" "$g") "
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" me "$d10" '')\n"; out+="NOTRACK=$(run "$r" "$g") "
  mk;r=$R; stage "$r" "$A"; rm -rf "${r:?}/sub/.git"; out+="BLIND=$(run "$r" "$g") "
  mk;r=$R; echo x >"$r/other"; git -C "$r" add other; out+="UNRELATED=$(run "$r" "$g") "
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$S" me "$d10" CON-046)\n"; out+="WRONGSHA=$(run "$r" "$g") "
  # R2-I1 transition binding: a row for (S -> A) must not cover (B -> A)
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$S" "$A" me "$d10" CON-046)\n"; out+="OLDBIND=$(run "$r" "$g") "
  mk;r=$R; stage "$r" "1111111111111111111111111111111111111111"; out+="NEWOBJ=$(run "$r" "$g")/$(cnt 'new pin 1111111 not in') "
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" '' "$d10" CON-046)\n"; out+="NOAUTH=$(run "$r" "$g") "
  mk2;r=$R; stage "$r" "$A" sub; stage "$r" "$A" sub2; waive "$r" "$(wf sub "$B" "$A" me "$d10" CON-046)\n"; out+="TWOSUB=$(run "$r" "$g") "
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" me "$today" CON-046)\n"; out+="TODAY=$(run "$r" "$g") "
  mk2;r=$R; stage "$r" "$A" sub; stage "$r" "$A" sub2; rm -rf "${r:?}/sub2/.git"; out+="MIXED=$(run "$r" "$g") "
  # expiry form + R2-I1 horizon: far-future dates are refused now
  mk;r=$R; stage "$r" "$A"; e=""
  for i in never 9999 N/A 2026-13-45 2026-2-1 2999-01-01 "$(date +%Y-%m)-32"; do waive "$r" "$(wf sub "$B" "$A" me "$i" CON-046)\n"; e+="$(run "$r" "$g"),"; done; out+="BADEXP=$e "
  # R2-I1 horizon: default max 30 days (inclusive), 31 refused
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" me "$d30" CON-046)\n"; e="$(run "$r" "$g"),"
  waive "$r" "$(wf sub "$B" "$A" me "$d31" CON-046)\n"; e+="$(run "$r" "$g")"; out+="HORIZON=$e "
  # consumer DATA read from the BASE commit: committed max 60 honoured; the same config only in the index is not
  mk;r=$R; conf "$r" 'max_waiver_days=60\n'; git -C "$r" commit -q -m conf; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" me "$d45" CON-046)\n"; e="$(run "$r" "$g"),"
  mk;r=$R; conf "$r" 'max_waiver_days=60\n'; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" me "$d45" CON-046)\n"; e+="$(run "$r" "$g")"; out+="CONF=$e "
  # a bad config disables waivers (fail safe) but never blocks a forward bump (no deadlock)
  mk;r=$R; conf "$r" 'max_waiver_days=9999\n'; git -C "$r" commit -q -m conf; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" me "$d10" CON-046)\n"; e="$(run "$r" "$g"),"
  git -C "$r" rm -q --cached .submodule_pin_waivers; git -C "$r" commit -q -m down; stage "$r" "$B"; e+="$(run "$r" "$g")"; out+="BADCONF=$e "
  # R2-m4 item key is consumer DATA (declared prefix honoured; default stays CON)
  mk;r=$R; conf "$r" 'item_prefix=CAT\n'; git -C "$r" commit -q -m conf; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" me "$d10" CAT-046)\n"; e="$(run "$r" "$g"),"
  waive "$r" "$(wf sub "$B" "$A" me "$d10" CON-046)\n"; e+="$(run "$r" "$g"),"
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" me "$d10" CAT-046)\n"; e+="$(run "$r" "$g")"; out+="PREFIX=$e "
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" me "$d10" x)\n"; out+="BADITEM=$(run "$r" "$g") "
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" t "$d10" CON-046)\n"; e="$(run "$r" "$g"),"
  waive "$r" "$(wf sub "$B" "$A" T@T "$d10" CON-046)\n"; e+="$(run "$r" "$g")"; out+="SELFAUTH=$e "
  # R2-m3 authoriser: leading space, <..> form, author identity (name, email), Cyrillic case under LC_ALL=C, NFD vs
  # NFC; last: a distinct authoriser under LC_ALL=C with a Cyrillic committer is accepted (positive control)
  mk;r=$R; stage "$r" "$A"; e=""
  waive "$r" "$(wf sub "$B" "$A" ' me' "$d10" CON-046)\n"; e+="$(run "$r" "$g"),"
  waive "$r" "$(wf sub "$B" "$A" '<me@x>' "$d10" CON-046)\n"; e+="$(run "$r" "$g"),"
  waive "$r" "$(wf sub "$B" "$A" zz "$d10" CON-046)\n"; e+="$(run "$r" "$g" GIT_AUTHOR_NAME=zz GIT_AUTHOR_EMAIL=zz@z),"
  waive "$r" "$(wf sub "$B" "$A" ZZ@Z "$d10" CON-046)\n"; e+="$(run "$r" "$g" GIT_AUTHOR_NAME=zz GIT_AUTHOR_EMAIL=zz@z),"
  waive "$r" "$(wf sub "$B" "$A" 'МИЛОШ ВАСИЋ' "$d10" CON-046)\n"; e+="$(run "$r" "$g" LC_ALL=C GIT_COMMITTER_NAME='Милош Васић'),"
  waive "$r" "$(wf sub "$B" "$A" $'Milos\xcc\x8c' "$d10" CON-046)\n"; e+="$(run "$r" "$g" GIT_COMMITTER_NAME=$'Milo\xc5\xa1'),"
  # round 12 (review r11 F1): one killer per NFC call of f = NFC(casefold(NFC(s))). Field 7: committer U+0399 U+0308
  # U+0301 (decomposed capital iota, dialytika, tonos), authoriser U+0390: equal only when the OUTER NFC recomposes the
  # casefold result (RVR11-01 drops it). Field 8: committer U+03B1 U+0345 U+0301 (not in NFC: ypogegrammeni before
  # tonos), authoriser its NFC U+1FB4: equal only when the INNER NFC reorders before casefold (RVR11-02 drops it).
  waive "$r" "$(wf sub "$B" "$A" $'\xce\x90' "$d10" CON-046)\n"; e+="$(run "$r" "$g" GIT_COMMITTER_NAME=$'\xce\x99\xcc\x88\xcc\x81'),"
  waive "$r" "$(wf sub "$B" "$A" $'\xe1\xbe\xb4' "$d10" CON-046)\n"; e+="$(run "$r" "$g" GIT_COMMITTER_NAME=$'\xce\xb1\xcd\x85\xcc\x81'),"
  waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046)\n"; e+="$(run "$r" "$g" LC_ALL=C GIT_COMMITTER_NAME='Милош Васић')"; out+="AUTHNORM=$e "
  # RM1 killer: identity unresolvable -> waiver not honoured
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046)\n"; git -C "$r" config user.useConfigOnly true
  out+="IDENT=$(run "$r" "$g" -u GIT_COMMITTER_NAME -u GIT_COMMITTER_EMAIL -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL) "
  mk;r=$R; stage "$r" "$A"; wf sub "$B" "$A" me "$d10" CON-046 >"$r/.submodule_pin_waivers"; out+="UNTRACKED=$(run "$r" "$g") "
  # R2-I1 replay: a waiver committed with an earlier rollback must not cover a later downgrade (row stays in HEAD)
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046)\n"; e="$(run "$r" "$g"),"
  git -C "$r" commit -q -m rollback; stage "$r" "$B"; git -C "$r" commit -q -m fwd; stage "$r" "$A"; e+="$(run "$r" "$g")"; out+="PERSIST=$e "
  # --amend view (--base HEAD^): the rollback commit re-checked against its parent is waived; the default base sees no
  # change; a later rollback whose row was already in the parent is refused; an unresolvable --base is BLIND
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046)\n"; git -C "$r" commit -q -m rollback
  e="$(run "$r" "$g" -- --base HEAD^),$(run "$r" "$g"),"; stage "$r" "$B"; git -C "$r" commit -q -m fwd; stage "$r" "$A"; git -C "$r" commit -q -m again
  e+="$(run "$r" "$g" -- --base HEAD^),"; mk;r=$R; e+="$(run "$r" "$g" -- --base nosuchrev)"; out+="AMEND=$e "
  # RM2 killers: ignore=all from config or .gitmodules must not hide the gitlink change
  mk;r=$R; stage "$r" "$A"; git -C "$r" config diff.ignoreSubmodules all; e="$(run "$r" "$g"),"
  mk;r=$R; stage "$r" "$A"; printf '[submodule "sub"]\n\tpath = sub\n\turl = ./sub\n\tignore = all\n' >"$r/.gitmodules"; git -C "$r" add .gitmodules
  e+="$(run "$r" "$g")"; out+="IGNSUB=$e "
  # RM3 killer: a staged rename to a 4-word name that sorts before the gitlink
  mk;r=$R; printf 'one\ntwo\nthree\nfour\nfive\n' >"$r/file.txt"; git -C "$r" add file.txt; git -C "$r" commit -q -m f
  git -C "$r" mv file.txt "a b c d"; stage "$r" "$A"; out+="RENAME=$(run "$r" "$g") "
  # RM4 killer (8 fields) / the old 6-field form (no base) / RM5 killer (invalid row before a valid row) / CRLF row
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046 | tr -d '\n')\t\n"; out+="FIELDS8=$(run "$r" "$g") "
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046 | cut -f1-6)\n"; out+="FIELDS6=$(run "$r" "$g") "
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" '' "$d10" CON-046)\n$(wf sub "$B" "$A" ops "$d10" CON-046)\n"; out+="DUPROW=$(run "$r" "$g") "
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046 | tr -d '\n')\r\n"; out+="CRLF=$(run "$r" "$g")/$(cnt 'CR (CRLF') "
  # R2-m2: unreadable index -> BLIND; --root subdir with diff.relative=true still sees the gitlink
  mk;r=$R; stage "$r" "$A"; printf 'garbage' >"$tmp/badindex"; out+="UNREAD=$(run "$r" "$g" GIT_INDEX_FILE="$tmp/badindex") "
  mk;r=$R; mkdir -p "$r/d"; git -C "$r" config diff.relative true; stage "$r" "$A"; out+="RELATIVE=$(run "$r/d" "$g") "
  # hook-style env (linked worktree, embedded copy): forward ok, downgrade refused
  mk;r=$R; w="$tmp/wt.$RANDOM"; git -C "$r" worktree add -q -b wt "$w" 2>/dev/null
  rm -rf "${w:?}/sub"; cp -a "$r/sub" "$w/sub"; stage "$w" "$A"; git -C "$w" commit -q --no-verify -m down; stage "$w" "$B"
  gd="$(git -C "$w" rev-parse --absolute-git-dir)"
  out+="WT=$(run "$w" "$g" GIT_DIR="$gd" GIT_INDEX_FILE="$gd/index"),"; git -C "$w" commit -q --no-verify -m up; stage "$w" "$A"
  out+="$(run "$w" "$g" GIT_DIR="$gd" GIT_INDEX_FILE="$gd/index") "
  # shallow submodule: relation hidden -> BLIND; missing intermediate object -> BLIND
  mk;r=$R; o="$tmp/origin.$RANDOM"; mkdir "$o"; git -C "$o" init -q; for i in 1 2 3; do git -C "$o" commit -q --allow-empty -m "c$i"; done
  c3=$(git -C "$o" rev-parse HEAD); c2=$(git -C "$o" rev-parse HEAD~1)
  rm -rf "${r:?}/sub"; git clone -q --depth 1 "file://$o" "$r/sub"; git -C "$r/sub" fetch -q --depth 1 origin "$c2"
  git -C "$r" update-index --cacheinfo 160000,"$c3",sub; git -C "$r" commit -q -m p3; stage "$r" "$c2"; out+="SHALLOW=$(run "$r" "$g") "
  mk;r=$R; git -C "$r/sub" checkout -q "$B"; git -C "$r/sub" commit -q --allow-empty -m C; c="$(git -C "$r/sub" rev-parse HEAD)"
  git -C "$r" update-index --cacheinfo 160000,"$c",sub; git -C "$r" commit -q -m pc; rm -f "${r:?}/sub/.git/objects/${B:0:2}/${B:2}"
  stage "$r" "$A"; out+="MISSINGMID=$(run "$r" "$g") "
  # R2-m1: shallow submodule where both directions are provable: forward c4->c5 ok, downgrade c4->c3 FAIL
  mk;r=$R; o="$tmp/origin5.$RANDOM"; mkdir "$o"; git -C "$o" init -q; for i in 1 2 3 4 5; do git -C "$o" commit -q --allow-empty -m "c$i"; done
  c5=$(git -C "$o" rev-parse HEAD); c4=$(git -C "$o" rev-parse HEAD~1); c3=$(git -C "$o" rev-parse HEAD~2)
  rm -rf "${r:?}/sub"; git clone -q --depth 3 "file://$o" "$r/sub"
  git -C "$r" update-index --cacheinfo 160000,"$c4",sub; git -C "$r" commit -q -m p4; stage "$r" "$c5"; e="$(run "$r" "$g"),"
  stage "$r" "$c3"; e+="$(run "$r" "$g")"; out+="SHFWD=$e "
  # replace refs must not change ancestry: graft B to a root commit, then B -> A is still a downgrade (not DIVERGED)
  mk;r=$R; git -C "$r/sub" replace --graft "$B"; stage "$r" "$A"; out+="REPLACE=$(run "$r" "$g") "
  # a submodule checkout path that is a symlink to another clone -> BLIND, named (never read through the link)
  mk;r=$R; o="$tmp/elsewhere.$RANDOM"; git clone -q "$r/sub" "$o" 2>/dev/null; rm -rf "${r:?}/sub"; ln -s "$o" "$r/sub"
  stage "$r" "$A"; out+="SYMSUB=$(run "$r" "$g")/$(cnt 'checkout path is a symlink') "
  # -h prints the whole header (including NOT ENFORCED and Exit)
  out+="HELP=$(bash "$g" -h 2>/dev/null | grep -c -e '^NOT ENFORCED' -e '^Exit: ') "
  SUBN="süb"; mk;r=$R; stage "$r" "$A"; git -C "$r" commit -q --no-verify -m down; stage "$r" "$B"; out+="NONASCII=$(run "$r" "$g") "; SUBN=sub
  mk;r=$R; stage "$r" "$A"; git -C "$r" commit -q --no-verify -m down; stage "$r" "$B"; lnk="$tmp/lnk.$RANDOM"; ln -s "$r" "$lnk"
  out+="SYMROOT=$(run "$lnk" "$g") "
  # R3-m3 reviewer killers K1, K3-K5 (RV1, RV3-RV5). K1: base config is a tree (unreadable) -> waivers disabled
  mk;r=$R; mkdir "$r/.submodule_pin_gate.conf"; echo x >"$r/.submodule_pin_gate.conf/x"; git -C "$r" add .submodule_pin_gate.conf
  git -C "$r" commit -q -m cfgdir; git -C "$r" rm -rq --cached .submodule_pin_gate.conf; rm -rf "${r:?}/.submodule_pin_gate.conf"
  stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046)\n"; e="$(run "$r" "$g"),"
  # K3 duplicate key, K4 item_prefix with a regex metacharacter, K5 max_waiver_days=400 with a 45-day expiry
  mk;r=$R; conf "$r" 'max_waiver_days=30\nmax_waiver_days=30\n'; git -C "$r" commit -q -m conf; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046)\n"; e+="$(run "$r" "$g"),"
  mk;r=$R; conf "$r" 'item_prefix=C.N\n'; git -C "$r" commit -q -m conf; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046)\n"; e+="$(run "$r" "$g"),"
  mk;r=$R; conf "$r" 'max_waiver_days=400\n'; git -C "$r" commit -q -m conf; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d45" CON-046)\n"; e+="$(run "$r" "$g")"
  out+="KCONF=$e "
  # K6 (RV6): the submodule dir has no .git, the parent holds the submodule's commits, B -> S: BLIND, never read via the parent
  mk;r=$R; git -C "$r" fetch -q "$r/sub" "$B:refs/x/b" "side:refs/x/s" 2>/dev/null; stage "$r" "$S"; mv "$r/sub/.git" "$tmp/subgit.$RANDOM"
  out+="NOTOWN=$(run "$r" "$g")/$(cnt 'not its own repository') "
  # RV7: lazy fetch off. The submodule is a partial clone; the new pin exists only on its promisor remote -> BLIND, nothing fetched
  mk;r=$R; o="$tmp/lz.$RANDOM"; git init -q "$o"; git -C "$o" config uploadpack.allowfilter true; git -C "$o" config uploadpack.allowanysha1inwant true
  git -C "$o" commit -q --allow-empty -m l1; c="$(git -C "$o" rev-parse HEAD)"; rm -rf "${r:?}/sub"; git clone -q --filter=blob:none "file://$o" "$r/sub" 2>/dev/null
  git -C "$o" commit -q --allow-empty -m l2; c2="$(git -C "$o" rev-parse HEAD)"; git -C "$r" update-index --cacheinfo 160000,"$c",sub; git -C "$r" commit -q -m pl
  stage "$r" "$c2"; e="$(run "$r" "$g")"
  out+="LAZY=$e/$(git -C "$r/sub" config remote.origin.promisor)/$(GIT_NO_LAZY_FETCH=1 git -C "$r/sub" cat-file -e "$c2^{commit}" 2>/dev/null && echo fetched || echo absent) "
  # R3-m1: legacy info/grafts in the submodule must not hide ancestry (B made parentless: still a downgrade, not DIVERGED)
  mk;r=$R; printf '%s\n' "$B" >"$r/sub/.git/info/grafts"; stage "$r" "$A"; out+="GRAFT=$(run "$r" "$g") "
  # R3-n1: string comparison in awk: a row for path 10 must not waive the gitlink at path 1e1
  SUBN=1e1; mk;r=$R; stage "$r" "$A" 1e1; waive "$r" "$(wf 10 "$B" "$A" ops "$d10" CON-046)\n"; out+="NUMPATH=$(run "$r" "$g") "; SUBN=sub
  # R3-n4: a python3 that fails (exit 1) means "authoriser check failed", never "self-waive"
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046)\n"; mkdir -p "$tmp/fakepy"
  printf '#!/bin/sh\ncat >/dev/null\nexit 1\n' >"$tmp/fakepy/python3"; chmod +x "$tmp/fakepy/python3"
  e="$(run "$r" "$g" PATH="$tmp/fakepy:$PATH")"; out+="PYFAIL=$e/$(cnt 'authoriser check failed')/$(cnt 'cannot self-waive') "
  # spent check reads sibling commits: one on the same base whose waiver path is a tree cannot be read -> not waived
  mk;r=$R; git -C "$r" checkout -q -b y; mkdir "$r/.submodule_pin_waivers"; echo x >"$r/.submodule_pin_waivers/x"; git -C "$r" add .submodule_pin_waivers
  git -C "$r" commit -q -m y; git -C "$r" checkout -q main; rm -rf "${r:?}/.submodule_pin_waivers"; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046)\n"
  e="$(run "$r" "$g")"; out+="CHILDTREE=$e/$(cnt 'unreadable') "
  # a broken ref makes `rev-list --all` fail: the row cannot be proven unspent -> not waived
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046)\n"; mkdir -p "$r/.git/refs/heads"
  printf '%s\n' 1111111111111111111111111111111111111111 >"$r/.git/refs/heads/broken"; e="$(run "$r" "$g")"; out+="BADREF=$e/$(cnt 'rev-list --all failed') "
  # a sibling commit on the same parent carrying a row for the same transition but bound to ANOTHER base spends nothing
  mk;r=$R; git -C "$r" checkout -q -b y; wf sub "$B" "$A" ops "$d10" CON-046 2222222222222222222222222222222222222222 >"$r/.submodule_pin_waivers"
  git -C "$r" add .submodule_pin_waivers; git -C "$r" commit -q -m y; git -C "$r" checkout -q main; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046)\n"
  out+="SIBOTHER=$(run "$r" "$g") "
  out+="$(inventory "$g")"
  out+="$(lifecycle "$g")"
  out+="$(members "$g")"
  out+="$(members7 "$g")"
  out+="$(members8 "$g")"
  out+="$(members10 "$g")"
  out+="$(members11 "$g")"
  echo "${out}DATE=$ds~$(date +%F)"
}
# ── round 6: the class inventory (§11.4.276(C)). One fixture per guard of the gate that no earlier fixture falsifies;
# each guard's paired mutant is in Part 2. The inventory table is in the round-6 author report (con046_fix_r6_report.md)
inventory() { # gate path -> vector part
  local g="$1" o="" r u a c x n
  # usage errors exit 2 (round 6 found `--base`/`--waivers` without a value exited 1, the FAIL code); run where no
  # repository is above the cwd (GIT_CEILING_DIRECTORIES), so a mutant that falls through cannot read a real repo
  mkdir -p "$tmp/plain"; u=""
  for a in --root --base --waivers --bogus; do u+="$(cd "$tmp/plain" && GIT_CEILING_DIRECTORIES="$tmp" bash "$g" "$a" >/dev/null 2>&1; echo $?),"; done
  mk;r=$R; stage "$r" "$A"; u+="$(run "$r" "$g" -- --base ''),$(run "$r" "$g" -- --bogus)/$(cnt 'unknown argument'),"
  u+="$(cd "$tmp/plain" && GIT_CEILING_DIRECTORIES="$tmp" bash "$g" --root "$tmp/nonexist" >"$tmp/out" 2>&1; echo $?)/$(cnt 'not inside a git work tree'),"
  u+="$(cd "$tmp/plain" && GIT_CEILING_DIRECTORIES="$tmp" bash "$g" --root "$tmp/plain" >"$tmp/out" 2>&1; echo $?)/$(cnt 'not inside a git work tree')"
  o+="ARGS=$u "
  # `git rev-parse --local-env-vars` returns nothing (a git that prints nothing for it) -> BLIND, named
  mkdir -p "$tmp/fklev"; printf '#!/bin/bash\n[ "$1" = rev-parse ] && [ "$2" = --local-env-vars ] && exit 0\nexec %s "$@"\n' "$realgit" >"$tmp/fklev/git"; chmod +x "$tmp/fklev/git"
  mk;r=$R; o+="LEV=$(run "$r" "$g" PATH="$tmp/fklev:$PATH")/$(cnt 'local-env-vars returned nothing') "
  # unborn HEAD: base is the empty tree; a new gitlink is no downgrade -> PASS
  mk; u="$tmp/ub.$RANDOM"; git init -q "$u"; git -C "$u" update-index --add --cacheinfo 160000,"$B",sub; o+="UNBORN=$(run "$u" "$g")/$(cnt 'PASS (0 staged') "
  # --base that does not resolve, and --base that names a tree (not a commit) -> BLIND, named
  mk;r=$R; stage "$r" "$A"; o+="BASEBAD=$(run "$r" "$g" -- --base nosuchrev)/$(cnt 'does not resolve to a commit'),$(run "$r" "$g" -- --base 'HEAD^{tree}')/$(cnt 'does not resolve to a commit') "
  # config: comments and blank lines are skipped; a line without '=' is named; 0 days is refused; an unknown key is named
  mk;r=$R; conf "$r" '# gate data\n\nmax_waiver_days=60\n'; git -C "$r" commit -q -m conf; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d45" CON-046)\n"; o+="CONFCOMMENT=$(run "$r" "$g") "
  mk;r=$R; conf "$r" 'garbage\n'; git -C "$r" commit -q -m conf; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046)\n"; o+="CONFNOKV=$(run "$r" "$g")/$(cnt 'is not key=value') "
  mk;r=$R; conf "$r" 'max_waiver_days=0\n'; git -C "$r" commit -q -m conf; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$today" CON-046)\n"; o+="CONFZERO=$(run "$r" "$g") "
  mk;r=$R; conf "$r" 'foo=bar\n'; git -C "$r" commit -q -m conf; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046)\n"; o+="CONFUNK=$(run "$r" "$g")/$(cnt "key 'foo' unknown") "
  # --waivers FILE is read (no index row); the index-only "no waiver data" reason is named
  mk;r=$R; stage "$r" "$A"; x="$tmp/wfile.$RANDOM"; wf sub "$B" "$A" ops "$d10" CON-046 >"$x"; o+="WFILE=$(run "$r" "$g" -- --waivers "$x") "
  mk;r=$R; stage "$r" "$A"; o+="NODATA=$(run "$r" "$g")/$(cnt 'no waiver data') "
  # authoriser: a control character is refused; invalid UTF-8 is "check failed (rc 4)", never a crash; python3 missing is
  # named; an empty authoriser names the form reason
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" $'op\001s' "$d10" CON-046)\n"; o+="AUTHCTRL=$(run "$r" "$g") "
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" $'op\377s' "$d10" CON-046)\n"; o+="AUTHUTF8=$(run "$r" "$g")/$(cnt 'python3 rc 4') "
  mknopy
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046)\n"; o+="NOPY=$(run "$r" "$g" PATH="$tmp/nopy")/$(cnt 'python3 missing') "
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" '' "$d10" CON-046)\n"; o+="EMPTYAUTH=$(run "$r" "$g")/$(cnt 'empty or has surrounding') "
  # tracked item form: 2 digits refused, a suffix refused
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-46)\n"; u="$(run "$r" "$g"),"
  waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046x)\n"; u+="$(run "$r" "$g")"; o+="ITEMFORM=$u "
  # a waiver line whose first field starts with '#' is a comment, so it never waives (even a gitlink at path '#sub')
  SUBN='#sub'; mk;r=$R; stage "$r" "$A" '#sub'; waive "$r" "$(wf '#sub' "$B" "$A" ops "$d10" CON-046)\n"; o+="WCOMMENT=$(run "$r" "$g") "; SUBN=sub
  # spent check, string compare on the path: a sibling row for path 10 does not spend the row for gitlink 1e1
  SUBN=1e1; mk;r=$R; x=$(git -C "$r" rev-parse HEAD); git -C "$r" checkout -q -b y; wf 10 "$B" "$A" ops "$d10" CON-046 "$x" >"$r/.submodule_pin_waivers"
  git -C "$r" add .submodule_pin_waivers; git -C "$r" commit -q -m y; git -C "$r" checkout -q main; stage "$r" "$A" 1e1; waive "$r" "$(wf 1e1 "$B" "$A" ops "$d10" CON-046)\n"
  o+="SPENTNUM=$(run "$r" "$g") "; SUBN=sub
  # new and deleted gitlinks are no downgrade (PASS); the inspected count is reported
  mk;r=$R; git -C "$r" update-index --add --cacheinfo 160000,"$B",sub3; o+="NEWGL=$(run "$r" "$g") "
  mk;r=$R; git -C "$r" update-index --force-remove sub; o+="DELGL=$(run "$r" "$g") "
  mk;r=$R; stage "$r" "$A"; git -C "$r" commit -q -m down; stage "$r" "$B"; o+="COUNT=$(run "$r" "$g")/$(cnt 'PASS (1 staged') "
  # the submodule checkout is gone entirely -> BLIND "checkout missing" (not the symlink reason)
  mk;r=$R; stage "$r" "$A"; rm -rf "${r:?}/sub"; o+="SUBGONE=$(run "$r" "$g")/$(cnt 'checkout missing') "
  # shallow submodule: the fix names --unshallow; a complete one does not
  mk;r=$R; c=$(git -C "$r/sub" rev-parse "$B^{tree}"); stage "$r" "$c"; o+="NEWTREE=$(run "$r" "$g")/$(cnt 'new pin .* not in the submodule object store')/$(cnt 'fetch --unshallow') "
  # old pin missing from the submodule store, and old pin a tree id -> BLIND "old pin" (not "ancestry")
  mk;r=$R; git -C "$r" update-index --cacheinfo 160000,2222222222222222222222222222222222222222,sub; git -C "$r" commit -q -m p2; stage "$r" "$A"; u="$(run "$r" "$g")/$(cnt 'old pin'),"
  mk;r=$R; c=$(git -C "$r/sub" rev-parse "$B^{tree}"); git -C "$r" update-index --cacheinfo 160000,"$c",sub; git -C "$r" commit -q -m pt; stage "$r" "$A"; u+="$(run "$r" "$g")/$(cnt 'old pin')"
  o+="OLDOBJ=$u "
  echo "$o"
}
# ── the waiver LIFECYCLE class, through `git commit` with the hook (real submodule, one worktree) ─────────────
# Rule under test: one row = one transition (path, old, new) in one single-parent commit whose parent is the row's base;
# the first such commit on a ref spends it. Each member is a way a row could be reused by a commit it was not reviewed for.
lc_sup() { # sets SR uA uB: superproject with a REAL submodule `sub` at uB (upstream A <- B), file notes, hook $1
  local up; up="$(mktemp -d "$tmp/up.XXXXXX")"; git -C "$up" init -q; for i in A B; do git -C "$up" commit -q --allow-empty -m "$i"; done
  uA=$(git -C "$up" rev-parse HEAD~1); uB=$(git -C "$up" rev-parse HEAD); SR="$(mktemp -d "$tmp/sup.XXXXXX")"; git -C "$SR" init -q
  git -C "$SR" submodule add -q "file://$up" sub >/dev/null 2>&1; echo 0 >"$SR/notes"; git -C "$SR" add -A; git -C "$SR" commit -q --no-verify -m base
  ln -s "$1" "$SR/.git/hooks/pre-commit"; }
lrow() { printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' sub "$uB" "$uA" ops "$d10" CON-046 "$1"; } # <base>
lgc() { local r="$1"; shift; git -C "$r" commit -q "$@" >"$tmp/hout" 2>&1; echo $?; }
lpin() { case "$(git -C "$1" ls-tree "${2:-HEAD}" -- sub | awk '{print $3}')" in "$uA") echo A ;; "$uB") echo B ;; *) echo X ;; esac; }
lg() { bash "$LG" --root "$@" >"$tmp/gout" 2>&1; echo $?; }
lrb() { # in ${1:-$SR}: checkout to A (stale against pin B), row bound to HEAD, staged, commit -a = the reviewed rollback
  local r="${1:-$SR}"; git -C "$r/sub" checkout -q "$uA"; lrow "$(git -C "$r" rev-parse HEAD)" >"$r/.submodule_pin_waivers"
  git -C "$r" add .submodule_pin_waivers; lgc "$r" -a -m rollback; }
lc_veh() { # vehicle X at main's tip: reviewed rollback Rc, index-only forward; back on main (checkout stays at A)
  lc_sup "$LH"; git -C "$SR" checkout -q -b X; lrb >/dev/null; Rc=$(git -C "$SR" rev-parse HEAD)
  git -C "$SR" update-index --cacheinfo 160000,"$uB",sub; lgc "$SR" -m fwd >/dev/null; git -C "$SR" checkout -q main; }
lc_x() { # <moved|same> <conflict|-> : vehicle X at main's tip: reviewed rollback, [notes edit], index-only forward to B;
  # back on main (the checkout stays at A, as after any branch switch), main then moved or not
  lc_sup "$LH"; git -C "$SR" checkout -q -b X; LX1=$(lrb); if [ "$2" = conflict ]; then echo x >"$SR/notes"; lgc "$SR" -m xn -- notes >/dev/null; fi
  git -C "$SR" update-index --cacheinfo 160000,"$uB",sub; lgc "$SR" -m fwd >/dev/null; git -C "$SR" checkout -q main
  if [ "$1" = moved ]; then echo m >"$SR/notes"; lgc "$SR" -m mn -- notes >/dev/null; fi; }
k_sup2() { # lc_sup "$LH" plus a second REAL submodule sub2 at u2B (upstream B2 <- C2)
  lc_sup "$LH"; local up; up="$(mktemp -d "$tmp/up2.XXXXXX")"; git -C "$up" init -q; for i in B2 C2; do git -C "$up" commit -q --allow-empty -m "$i"; done
  u2B=$(git -C "$up" rev-parse HEAD~1); u2C=$(git -C "$up" rev-parse HEAD)
  git -C "$SR" submodule add -q "file://$up" sub2 >/dev/null 2>&1; git -C "$SR/sub2" checkout -q "$u2B"; git -C "$SR" add -A; git -C "$SR" commit -q --no-verify -m base2; }
krow() { printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' sub "$uB" "${3:-$uA}" "${2:-ops}" "$d10" CON-046 "$1"; } # <base> [authoriser] [new]
krb() { # reviewed rollback in ${1:-$SR} through the hook, authoriser ${2:-ops}
  local r="${1:-$SR}"; git -C "$r/sub" checkout -q "$uA"; krow "$(git -C "$r" rev-parse HEAD)" "${2:-ops}" >"$r/.submodule_pin_waivers"
  git -C "$r" add .submodule_pin_waivers; lgc "$r" -a -m rollback; }
ksib() { # sibling commit on branch Y at HEAD of $SR carrying waiver text $1 (no hook); back to main
  git -C "$SR" checkout -q -b Y; printf '%b' "$1" >"$SR/.submodule_pin_waivers"
  git -C "$SR" add .submodule_pin_waivers; git -C "$SR" commit -q --no-verify -m y; git -C "$SR" checkout -q main; rm -f "$SR/.submodule_pin_waivers"; }
lifecycle() { # gate path -> vector part
  local g="$1" o="" r a b c x lay; lay="$(mktemp -d "$tmp/lay.XXXXXX")"; mkdir -p "$lay/scripts/gates" "$lay/scripts/hooks"
  cp "$g" "$lay/scripts/gates/cm_submodule_pin_not_downgraded.sh"; cp "$hook" "$lay/scripts/hooks/pre-commit-submodule-pin-not-downgraded"
  LH="$lay/scripts/hooks/pre-commit-submodule-pin-not-downgraded"; LG="$lay/scripts/gates/cm_submodule_pin_not_downgraded.sh"
  # legit reviewed rollback; then the R2-I1 snapshot over the stale checkout; then the same snapshot as --amend -a
  lc_sup "$LH"; r=$SR; a=$(lrb); o+="LEGIT=$a/$(lpin "$r") "
  git -C "$r" update-index --cacheinfo 160000,"$uB",sub; b=$(lgc "$r" -m fwd); echo 1 >"$r/notes"; c=$(lgc "$r" -a -m snapshot)
  x=$(lgc "$r" --amend -a -m snapshot2); o+="SNAP=$b,$c/$(lpin "$r") AMENDSNAP=$x/$(lpin "$r") "
  # amend the message of the reviewed rollback, re-judge it against its parent (--base HEAD^), then reset --soft and redo
  lc_sup "$LH"; r=$SR; a=$(lrb); b=$(lgc "$r" --amend -m rollback2); c=$(lg "$r" --base HEAD^); git -C "$r" reset -q --soft HEAD^
  x=$(lgc "$r" -m redo); o+="AMENDMSG=$a,$b,$c REDO=$x/$(lpin "$r") "
  # integrate the vehicle into main: conflicted merge, squash, --no-commit merge; main moved or not
  lc_x moved conflict; r=$SR; git -C "$r" merge -q X >/dev/null 2>&1; echo r >"$r/notes"; a=$(lgc "$r" -a -m merge); o+="MERGECONF=$LX1,$a/$(lpin "$r") "
  lc_x moved -; r=$SR; git -C "$r" merge -q --squash X >/dev/null 2>&1; a=$(lgc "$r" -a -m sq); o+="SQUASHMOVED=$a/$(lpin "$r") "
  lc_x same -; r=$SR; git -C "$r" merge -q --squash X >/dev/null 2>&1; a=$(lgc "$r" -a -m sq); o+="SQUASHSAME=$a/$(lpin "$r")/$(grep -c 'already spent' "$tmp/hout") "
  lc_x moved -; r=$SR; git -C "$r" merge -q --no-commit --no-ff X >/dev/null 2>&1; a=$(lgc "$r" -a -m nc); o+="NOCOMMITMOVED=$a/$(lpin "$r") "
  lc_x same -; r=$SR; git -C "$r" merge -q --no-commit --no-ff X >/dev/null 2>&1; a=$(lgc "$r" -a -m nc); o+="NOCOMMITSAME=$a/$(lpin "$r") "
  # the one-parent clause alone: the vehicle (and so its rollback) is deleted while the merge is open
  lc_x same -; r=$SR; git -C "$r" merge -q --no-commit --no-ff X >/dev/null 2>&1; git -C "$r" branch -q -D X; a=$(lgc "$r" -a -m nc)
  o+="NOCOMMITDEL=$a/$(lpin "$r")/$(grep -c 'single-parent' "$tmp/hout") "
  # a superproject graft (written after the squash) must not hide the spent rollback (made parentless by the graft)
  lc_x same -; r=$SR; git -C "$r" merge -q --squash X >/dev/null 2>&1; b=$(git -C "$r" diff --cached --name-only | grep -c '^\.submodule_pin_waivers$')
  git -C "$r" rev-parse X~1 >"$r/.git/info/grafts"; a=$(lgc "$r" -a -m sq); o+="SQGRAFT=$a/$(lpin "$r")/$b "
  # cherry-pick and rebase run no pre-commit hook when clean (measured); the gate in --base mode judges the result
  lc_x moved -; r=$SR; a=$(git -C "$r" cherry-pick X~1 >/dev/null 2>&1; echo $?); b=$(lg "$r" --base HEAD^); o+="CHERRY=$a,$b "
  # (-x: a clean pick onto the same parent in the same second would otherwise be byte-identical, i.e. the reviewed commit)
  lc_x same -; r=$SR; a=$(git -C "$r" cherry-pick -x X~1 >/dev/null 2>&1; echo $?); b=$(lg "$r" --base HEAD^)
  c=$([ "$(git -C "$r" rev-parse HEAD)" != "$(git -C "$r" rev-parse X~1)" ] && echo distinct || echo same); o+="CHERRYSAME=$a,$b/$c "
  lc_x moved -; r=$SR; git -C "$r" checkout -q X; a=$(git -C "$r" rebase -q main >/dev/null 2>&1; echo $?); git -C "$r" checkout -q --detach X~1
  b=$(lg "$r" --base HEAD^); o+="REBASE=$a,$b "
  # leftover worktree rows: bound to the current HEAD (honoured: the documented residual) and to an older HEAD (refused)
  lc_sup "$LH"; r=$SR; lrow "$(git -C "$r" rev-parse HEAD)" >"$r/.submodule_pin_waivers"; git -C "$r/sub" checkout -q "$uA"; git -C "$r" add -A
  a=$(lgc "$r" -m snap); o+="LEFTSAME=$a/$(lpin "$r") "
  lc_sup "$LH"; r=$SR; lrow "$(git -C "$r" rev-parse HEAD)" >"$r/.submodule_pin_waivers"; echo 1 >"$r/notes"; lgc "$r" -m n -- notes >/dev/null
  git -C "$r/sub" checkout -q "$uA"; git -C "$r" add -A; a=$(lgc "$r" -m snap); o+="LEFTOLD=$a/$(lpin "$r")/$(grep -c 'bound to base' "$tmp/hout") "
  # base field forms: an abbreviated sha and the literal HEAD are refused
  lc_sup "$LH"; r=$SR; git -C "$r/sub" checkout -q "$uA"; lrow "$(git -C "$r" rev-parse --short HEAD)" >"$r/.submodule_pin_waivers"; git -C "$r" add .submodule_pin_waivers
  a=$(lgc "$r" -a -m rb); lrow HEAD >"$r/.submodule_pin_waivers"; git -C "$r" add .submodule_pin_waivers; b=$(lgc "$r" -a -m rb); o+="BASEFORM=$a,$b/$(lpin "$r") "
  # ── round-5: the round-4 reviewer's killer fixtures K8-K14 (probes/p7_killers.sh), adopted as written with the
  # lc_* helpers in place of the probe library's (sup=lc_sup, rb=lrb, gc=lgc, pin=lpin, row=lrow, vehicle=lc_veh) ──
  # K8: the spender is reachable only from a tag (vehicle branch deleted) -> refused
  lc_veh; r=$SR; git -C "$r" tag t "$Rc"; x=$(git -C "$r" rev-parse X); git -C "$r" branch -q -D X; git -C "$r" merge -q --squash "$x" >/dev/null 2>&1
  o+="K8TAG=$(lgc "$r" -a -m sq)/$(lpin "$r") "
  # K14: the spender is only the detached HEAD of another worktree -> refused (rev-list --all covers all worktrees)
  lc_sup "$LH"; r=$SR; w="$tmp/w.$RANDOM"; git -C "$r" worktree add -q --detach "$w" 2>/dev/null; git -C "$w" submodule update -q --init 2>/dev/null
  lrb "$w" >/dev/null; git -C "$w" update-index --cacheinfo 160000,"$uB",sub; lgc "$w" -m fwd >/dev/null
  git -C "$r" merge -q --squash "$(git -C "$w" rev-parse HEAD)" >/dev/null 2>&1; git -C "$r/sub" checkout -q "$uA"; o+="K14WT=$(lgc "$r" -a -m sq)/$(lpin "$r") "
  # K9: a superproject replace ref makes the spender parentless; replace refs must be ignored -> refused
  lc_veh; r=$SR; git -C "$r" merge -q --squash X >/dev/null 2>&1; git -C "$r" replace --graft "$Rc"; o+="K9REPL=$(lgc "$r" -a -m sq)/$(lpin "$r") "
  # K11 / K12: a sibling on the same parent whose row is for ANOTHER path / ANOTHER old sha is no spender -> waived
  lc_sup "$LH"; r=$SR; x=$(git -C "$r" rev-parse HEAD); git -C "$r" checkout -q -b Y
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' sub2 "$uB" "$uA" ops "$d10" CON-046 "$x" >"$r/.submodule_pin_waivers"; git -C "$r" add .submodule_pin_waivers; lgc "$r" -m y >/dev/null
  git -C "$r" checkout -q main; o+="K11PATH=$(lrb)/$(lpin "$r") "
  lc_sup "$LH"; r=$SR; x=$(git -C "$r" rev-parse HEAD); git -C "$r" checkout -q -b Y
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' sub 3333333333333333333333333333333333333333 "$uA" ops "$d10" CON-046 "$x" >"$r/.submodule_pin_waivers"; git -C "$r" add .submodule_pin_waivers; lgc "$r" -m y >/dev/null
  git -C "$r" checkout -q main; o+="K12OLD=$(lrb)/$(lpin "$r") "
  # K13: a sibling's waiver path is a tree (the spent check cannot tell) -> refused, through the hook
  lc_sup "$LH"; r=$SR; git -C "$r" checkout -q -b Y; mkdir "$r/.submodule_pin_waivers"; echo x >"$r/.submodule_pin_waivers/x"; git -C "$r" add .submodule_pin_waivers; lgc "$r" -m y >/dev/null
  git -C "$r" checkout -q main; rm -rf "${r:?}/.submodule_pin_waivers"; o+="K13TELL=$(lrb)/$(lpin "$r") "
  # K10: blob:none partial superproject, the spender's waiver blob only on the promisor -> refused as unreadable, nothing fetched
  lc_veh; r=$SR; git -C "$r/sub" checkout -q "$uB"; git -C "$r" config uploadpack.allowfilter true; git -C "$r" config uploadpack.allowanysha1inwant true
  b=$(git -C "$r" rev-parse "$Rc:.submodule_pin_waivers"); c="$tmp/bn.$RANDOM"; git clone -q --no-local --filter=blob:none "file://$r" "$c" 2>/dev/null
  git -C "$c" submodule update -q --init 2>/dev/null; ln -s "$LH" "$c/.git/hooks/pre-commit"
  lrow "$(git -C "$c" rev-parse HEAD)" | sed 's/\tops\t/\tops2\t/' >"$c/.submodule_pin_waivers"; git -C "$c" add .submodule_pin_waivers; git -C "$c/sub" checkout -q "$uA"
  x=$(GIT_NO_LAZY_FETCH=1 git -C "$c" cat-file -e "$b" 2>/dev/null && echo present || echo absent)
  a=$(lgc "$c" -a -m snap); y=$(GIT_NO_LAZY_FETCH=1 git -C "$c" cat-file -e "$b" 2>/dev/null && echo present || echo absent)
  o+="K10LAZY=$a/$x/$y/$(grep -c unreadable "$tmp/hout") "
  # ── round-5 M-1: the spender's TREE is missing (incomplete object store) -> unreadable, refused (never "absent") ──
  lc_sup "$LH"; r=$SR; git -C "$r" checkout -q -b X; lrb >/dev/null; x=$(git -C "$r" rev-parse HEAD); git -C "$r" checkout -q main; git -C "$r/sub" checkout -q "$uB"
  b=$(git -C "$r" rev-parse "$x^{tree}"); rm -f "${r:?}/.git/objects/${b:0:2}/${b:2}"
  lrow "$(git -C "$r" rev-parse HEAD)" | sed 's/\tops\t/\tops2\t/' >"$r/.submodule_pin_waivers"; git -C "$r" add .submodule_pin_waivers; git -C "$r/sub" checkout -q "$uA"
  a=$(lgc "$r" -a -m snap); o+="TREEMISS=$a/$(lpin "$r")/$(GIT_NO_LAZY_FETCH=1 git -C "$r" cat-file -e "$b" 2>/dev/null && echo present || echo missing)/$(grep -c unreadable "$tmp/hout") "
  # M-1: a shallow superproject hides the spender's parent (R is a shallow boundary) -> waivers refused
  lc_veh; r=$SR; git -C "$r/sub" checkout -q "$uB"; c="$tmp/sh.$RANDOM"; git clone -q --no-local --depth 1 --branch main "file://$r" "$c" 2>/dev/null
  git -C "$c" fetch -q --depth 2 origin X:refs/remotes/origin/X 2>/dev/null; git -C "$c" submodule update -q --init 2>/dev/null; ln -s "$LH" "$c/.git/hooks/pre-commit"
  git -C "$c" checkout -q origin/X -- .submodule_pin_waivers; git -C "$c/sub" checkout -q "$uA"; a=$(lgc "$c" -a -m snap)
  o+="SHALLOWSUP=$a/$(lpin "$c")/$(git -C "$c" rev-parse --is-shallow-repository)/$(grep -c 'superproject is shallow' "$tmp/hout") "
  # M-2: a stash of the staged reviewed rollback is no spender: stash push, stash apply --index, commit -a -> waived
  lc_sup "$LH"; r=$SR; git -C "$r/sub" checkout -q "$uA"; lrow "$(git -C "$r" rev-parse HEAD)" >"$r/.submodule_pin_waivers"; git -C "$r" add -A
  git -C "$r" stash push -q >/dev/null 2>&1; git -C "$r" stash apply -q --index >/dev/null 2>&1; git -C "$r/sub" checkout -q "$uA"
  a=$(lgc "$r" -a -m rollback); o+="STASH=$a/$(lpin "$r")/$(git -C "$r" rev-parse -q --verify refs/stash >/dev/null && echo kept || echo gone) "
  # N-4: --base mode, HEAD = the reviewed rollback R. An index equal to HEAD's tree is HEAD (R not counted: waived); an
  # index that differs from HEAD's tree is another commit, so R counts as a spender (refused)
  lc_sup "$LH"; r=$SR; x=$(git -C "$r" rev-parse HEAD); git -C "$r" checkout -q -b X; lrb >/dev/null; c=$(git -C "$r" rev-parse HEAD)
  git -C "$r" read-tree "$x"; git -C "$r" checkout "$c" -- .submodule_pin_waivers; git -C "$r" update-index --cacheinfo 160000,"$uA",sub
  a=$(lg "$r" --base "$x"); echo n4 >"$r/notes"; git -C "$r" add notes; b=$(lg "$r" --base "$x"); o+="N4INDEX=$a,$b "
  # M-3 documented residual (pinned): reviewed rollback + index-only forward, then `reset --soft HEAD~2 && commit -a` over
  # the stale checkout: the rollback is reflog-only, so the row waives again and A lands (header: Residual)
  lc_sup "$LH"; r=$SR; a=$(lrb); git -C "$r" update-index --cacheinfo 160000,"$uB",sub; b=$(lgc "$r" -m fwd); git -C "$r" reset -q --soft HEAD~2
  c=$(lgc "$r" -a -m squash); o+="RESETSQ=$a,$b,$c/$(lpin "$r") "
  # ── round 6: the round-5 reviewer's killer fixtures KNM1-KNM6, KNM9 (rv046r5 probes/killers.sh), adopted with the
  # lc_* helpers (sup=lc_sup, rb=krb, gc=lgc, pin=lpin, row=krow, gate=lg, sib=ksib); plus KNM1GM, KIDPARENT and the
  # behaviour probes A1-A3 (A1 and A2 are pinned residuals, A3 is the round-6 plumbing fix)
  k_sup2; r=$SR; P=$(git -C "$r" rev-parse HEAD); git -C "$r" checkout -q -b X; krb >/dev/null; git -C "$r/sub2" checkout -q "$u2C"; git -C "$r" add sub2
  git -C "$r" config diff.ignoreSubmodules all; a=$(lg "$r" --base "$P"); git -C "$r" config --unset diff.ignoreSubmodules; b=$(lg "$r" --base "$P")
  o+="KNM1=$a,$b "
  # KNM1GM: the plumbing N-4 diff ignores diff.ignoreSubmodules but honours submodule.<name>.ignore=all in .gitmodules,
  # so --ignore-submodules=none is load-bearing there: index = R's tree + a forward sub2 gitlink -> R counts -> refused
  k_sup2; r=$SR; git -C "$r" config -f .gitmodules submodule.sub2.ignore all; git -C "$r" add .gitmodules; git -C "$r" commit -q --no-verify -m ign
  P=$(git -C "$r" rev-parse HEAD); git -C "$r" checkout -q -b X; krb >/dev/null; git -C "$r" update-index --cacheinfo 160000,"$u2C",sub2; a=$(lg "$r" --base "$P")
  git -C "$r" update-index --cacheinfo 160000,"$u2B",sub2; b=$(lg "$r" --base "$P"); o+="KNM1GM=$a,$b "
  lc_sup "$LH"; r=$SR; git -C "$r/sub" checkout -q "$uA"; krow "$(git -C "$r" rev-parse HEAD)" >"$r/.submodule_pin_waivers"; git -C "$r" add -A
  mkdir -p "$tmp/fk"; printf '#!/bin/bash\nfor a in "$@"; do [ "$a" = --is-shallow-repository ] && { echo unknown; exit 0; }; done\nexec %s "$@"\n' "$realgit" >"$tmp/fk/git"; chmod +x "$tmp/fk/git"
  a=$(PATH="$tmp/fk:$PATH" lg "$r"); c=$(grep -c 'shallow state is unknown' "$tmp/gout"); b=$(lg "$r"); o+="KNM2=$a/$c,$b "
  x=""; for order in second first; do
    lc_sup "$LH"; r=$SR; P=$(git -C "$r" rev-parse HEAD); git -C "$r" checkout -q -b Q; echo q >"$r/notes"; git -C "$r" commit -q --no-verify -m q -- notes; c=$(git -C "$r" rev-parse HEAD)
    git -C "$r" checkout -q main; b=$(krow "$P" | git -C "$r" hash-object -w --stdin); a="$tmp/ix.$RANDOM"
    GIT_INDEX_FILE="$a" git -C "$r" read-tree "$c"; GIT_INDEX_FILE="$a" git -C "$r" update-index --add --cacheinfo 100644,"$b",.submodule_pin_waivers
    b=$(GIT_INDEX_FILE="$a" git -C "$r" write-tree)
    if [ "$order" = second ]; then a=$(git -C "$r" commit-tree "$b" -p "$c" -p "$P" -m m); else a=$(git -C "$r" commit-tree "$b" -p "$P" -p "$c" -m m); fi
    git -C "$r" update-ref refs/heads/M "$a"; a=$(krb); x+="$a/$(lpin "$r"),"
  done; o+="KNM3=$x "
  lc_sup "$LH"; ksib "$(krow "$(git -C "$SR" rev-parse HEAD)" ops 4444444444444444444444444444444444444444)\n"; a=$(krb)/$(lpin "$SR")
  lc_sup "$LH"; ksib "$(krow "$(git -C "$SR" rev-parse HEAD)")\n"; b=$(krb)/$(lpin "$SR"); o+="KNM4=$a,$b "
  x=""; for c in 'Ops Team' ops; do
    lc_sup "$LH"; r=$SR; git -C "$r" checkout -q -b X; krb "$r" "$c" >/dev/null; git -C "$r" update-index --cacheinfo 160000,"$uB",sub; lgc "$r" -m fwd >/dev/null
    git -C "$r" checkout -q main; git -C "$r" merge -q --squash X >/dev/null 2>&1; a=$(lgc "$r" -a -m sq); x+="$a/$(lpin "$r"),"
  done; o+="KNM5=$x "
  lc_sup "$LH"; r=$SR; P=$(git -C "$r" rev-parse HEAD); git -C "$r" checkout -q -b X; krb >/dev/null; echo z >"$r/notes"; a=$(lg "$r" --base "$P")
  echo n >"$r/notes"; git -C "$r" add notes; echo 0 >"$r/notes"; b=$(lg "$r" --base "$P"); o+="KNM6=$a,$b "
  lc_sup "$LH"; ksib "$(krow "$(git -C "$SR" rev-parse HEAD)" | tr -d '\n')\textra\n"; o+="KNM9=$(krb)/$(lpin "$SR") "
  # KIDPARENT: a commit carrying the row whose parent is NOT the base (Y2 on top of Y1 on P) spends nothing -> waived
  lc_sup "$LH"; r=$SR; P=$(git -C "$r" rev-parse HEAD); git -C "$r" checkout -q -b Y; echo y >"$r/notes"; git -C "$r" commit -q --no-verify -m y1 -- notes
  krow "$P" >"$r/.submodule_pin_waivers"; git -C "$r" add .submodule_pin_waivers; git -C "$r" commit -q --no-verify -m y2; git -C "$r" checkout -q main; rm -f "$r/.submodule_pin_waivers"
  o+="KIDPARENT=$(krb)/$(lpin "$r") "
  # A1 (pinned residual R5-5): the first rollback only behind another worktree's per-worktree ref -> the redo is WAIVED;
  # control refs/heads/keep -> refused
  x=""; for c in refs/worktree/keep refs/bisect/bad refs/heads/keep; do
    lc_sup "$LH"; r=$SR; P=$(git -C "$r" rev-parse HEAD); w="$tmp/w.$RANDOM"; git -C "$r" worktree add -q --detach "$w" 2>/dev/null; git -C "$w" submodule update -q --init 2>/dev/null
    krb "$w" >/dev/null; a=$(git -C "$w" rev-parse HEAD); git -C "$w" update-ref "$c" "$a"; git -C "$w" checkout -q --detach "$P"
    b=$(git -C "$r" rev-list --all | grep -c "^$a$"); a=$(krb); x+="$a/$(lpin "$r")/vis$b,"
  done; o+="A1WTREF=$x "
  # A2 (pinned residual R5-4): R reachable only as an ancestor of refs/stash -> the redo is WAIVED
  lc_sup "$LH"; r=$SR; a=$(krb); c=$(git -C "$r" rev-parse HEAD); echo s >"$r/notes"; git -C "$r" stash push -q >/dev/null 2>&1
  git -C "$r" reset -q --hard HEAD~1; x=$(git -C "$r" rev-list --exclude=refs/stash --all | grep -c "^$c$"); b=$(krb); o+="A2STASHANC=$a,$b/$(lpin "$r")/vis$x "
  # A3 (R5-3, fixed in round 6): a textconv driver that maps every version of notes to the same text no longer hides an
  # index that differs from HEAD (plumbing diff-index applies no textconv): R counts -> refused
  lc_sup "$LH"; r=$SR; P=$(git -C "$r" rev-parse HEAD); git -C "$r" checkout -q -b X; krb >/dev/null; echo 'notes diff=same' >"$r/.git/info/attributes"
  git -C "$r" config diff.same.textconv "sh -c 'echo same' --"; echo n >"$r/notes"; git -C "$r" add notes
  a=$(git -C "$r" diff --cached --quiet HEAD -- >/dev/null 2>&1; echo $?); b=$(lg "$r" --base "$P")
  git -C "$r" config diff.external /bin/true; c=$(lg "$r" --base "$P"); git -C "$r" config --unset diff.external
  rm -f "$r/.git/info/attributes"; x=$(lg "$r" --base "$P"); o+="A3TEXTCONV=$a/$b,$c,$x "
  echo "$o"
}
# ── structural round (CON-146): member- and site-level fixtures. (1) The round-6 reviewer's killing probes
# (rv046r6 probes/probes_r6.sh and probe_kv29b.sh), adopted with their helpers renamed v6* (sup=v6sup, row=v6row, gc=lgc,
# pin=lpin, gate=lg, rb=v6rb); each fixture's comment is the reviewer's. (2) One fixture per remaining guard SITE that a
# mutant can reach: every per-row `continue` site and every per-row python3 verdict gets an "invalid row first, valid row
# second" fixture (the row loop must try the next row), and every member of a multi-member condition its own fixture.
v6sup() { local up; up="$(mktemp -d "$tmp/up.XXXXXX")"; git -C "$up" init -q; for i in A B; do git -C "$up" commit -q --allow-empty -m "$i"; done
  git -C "$up" checkout -q -b side HEAD~1; git -C "$up" commit -q --allow-empty -m S; git -C "$up" checkout -q main
  uA=$(git -C "$up" rev-parse main~1); uB=$(git -C "$up" rev-parse main); uS=$(git -C "$up" rev-parse side); SR="$(mktemp -d "$tmp/sup.XXXXXX")"; git -C "$SR" init -q
  git -C "$SR" submodule add -q "file://$up" sub >/dev/null 2>&1; git -C "$SR/sub" fetch -q origin side 2>/dev/null; echo 0 >"$SR/notes"; git -C "$SR" add -A; git -C "$SR" commit -q --no-verify -m base
  ln -s "$LH" "$SR/.git/hooks/pre-commit"; }
v6row() { printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "${4:-sub}" "$uB" "$uA" "${2:-ops}" "${3:-$d10}" CON-046 "$1"; } # <base> [auth] [expiry] [path]
v6rb() { local r="${1:-$SR}"; git -C "$r/sub" checkout -q "$uA"; v6row "$(git -C "$r" rev-parse HEAD)" "${2:-ops}" >"$r/.submodule_pin_waivers"
  git -C "$r" add .submodule_pin_waivers; lgc "$r" -a -m rollback; }
v6first() { # <first row text> : stage the rollback in $SR with the given (invalid) row FIRST and a valid row second; commit
  local r="$SR"; git -C "$r/sub" checkout -q "$uA"; { printf '%b' "$1"; v6row "$(git -C "$r" rev-parse HEAD)"; } >"$r/.submodule_pin_waivers"
  git -C "$r" add .submodule_pin_waivers; lgc "$r" -a -m rb; }
members() { # gate path -> vector part (needs LH/LG from lifecycle)
  local g="$1" o="" r x ref P R1 o17 y up s a1 b1 a b c old pp d200 lay
  d200="$(date -d '+200 days' +%F)"
  lay="$(mktemp -d "$tmp/lay.XXXXXX")"; mkdir -p "$lay/scripts/gates" "$lay/scripts/hooks"
  cp "$g" "$lay/scripts/gates/cm_submodule_pin_not_downgraded.sh"; cp "$hook" "$lay/scripts/hooks/pre-commit-submodule-pin-not-downgraded"
  LH="$lay/scripts/hooks/pre-commit-submodule-pin-not-downgraded"; LG="$lay/scripts/gates/cm_submodule_pin_not_downgraded.sh"
  # KV07/KV08: committed config max_waiver_days=365 (the claimed upper bound, inclusive), expiry today+200 -> waived
  v6sup; r=$SR; printf 'max_waiver_days=365\n' >"$r/.submodule_pin_gate.conf"; git -C "$r" add .submodule_pin_gate.conf; git -C "$r" commit -q --no-verify -m conf
  git -C "$r/sub" checkout -q "$uA"; v6row "$(git -C "$r" rev-parse HEAD)" ops "$d200" >"$r/.submodule_pin_waivers"; git -C "$r" add .submodule_pin_waivers
  o+="KV365=$(lgc "$r" -a -m rb)/$(lpin "$r") "
  # KV12: authoriser with a zero-width space (category Cf) equal to the committer name after removing it -> refused (3)
  v6sup; r=$SR; o+="KV12ZWSP=$(GIT_COMMITTER_NAME=ops v6rb "$r" $'o​ps')/$(lpin "$r") "
  # KV13: committer 'Strauss', authoriser 'STRAUSS' written with sharp s -> casefold makes them equal -> refused (10)
  v6sup; r=$SR; o+="KV13SHARPS=$(GIT_COMMITTER_NAME=Strauss v6rb "$r" $'STRAUß')/$(lpin "$r") "
  # KV15/KV16/KVT: the first rollback R1 on P is reachable only from refs/remotes/origin/X, refs/notes/x, or a tag (control);
  # the redo of the same rollback on P must be refused (spent)
  x=""; for ref in refs/remotes/origin/X refs/notes/x refs/tags/t; do
    v6sup; r=$SR; P=$(git -C "$r" rev-parse HEAD); git -C "$r" checkout -q -b X; v6rb >/dev/null; R1=$(git -C "$r" rev-parse HEAD); git -C "$r" update-ref "$ref" "$R1"
    git -C "$r" checkout -q main; git -C "$r" branch -q -D X; x+="$(v6rb)/$(lpin "$r"),"; done; o+="KVREFS=$x "
  # KV17: two children of P: the spender R1 (older) and a newer child Y without a waiver file -> refused (spent)
  v6sup; r=$SR; git -C "$r" checkout -q -b X; GIT_COMMITTER_DATE='2020-01-01T00:00:00' v6rb >/dev/null; git -C "$r" checkout -q main; git -C "$r/sub" checkout -q "$uB"
  git -C "$r" checkout -q -b Y; echo y >"$r/notes"; GIT_COMMITTER_DATE='2030-01-01T00:00:00' git -C "$r" commit -q --no-verify -m y -- notes; git -C "$r" checkout -q main
  o17=$(git -C "$r" rev-list --all --parents | awk -v b="$(git -C "$r" rev-parse main)" '$2==b{print $1}' | head -1); y=$(git -C "$r" rev-parse Y)
  o+="KV17ORDER=$(v6rb)/$(lpin "$r")/$([ "$o17" = "$y" ] && echo yfirst || echo rfirst) "
  # KV18: a gitlink at path 'a#b' with a valid row -> waived (only a FIRST field starting with # is a comment)
  up="$(mktemp -d "$tmp/u18.XXXXXX")"; git -C "$up" init -q; git -C "$up" commit -q --allow-empty -m A; a1=$(git -C "$up" rev-parse HEAD); git -C "$up" commit -q --allow-empty -m B; b1=$(git -C "$up" rev-parse HEAD)
  s="$(mktemp -d "$tmp/s18.XXXXXX")"; git -C "$s" init -q; git clone -q "$up" "$s/a#b"; git -C "$s" update-index --add --cacheinfo 160000,"$b1",'a#b'; git -C "$s" commit -q --no-verify -m base
  git -C "$s" update-index --cacheinfo 160000,"$a1",'a#b'; printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 'a#b' "$b1" "$a1" ops "$d10" CON-046 "$(git -C "$s" rev-parse HEAD)" >"$s/.submodule_pin_waivers"; git -C "$s" add .submodule_pin_waivers
  o+="KV18HASHMID=$(lg "$s") "
  # KV19: a stale row for the same transition bound to an OLD base, then a valid row -> waived (every row is tried)
  v6sup; r=$SR; old=$(git -C "$r" rev-parse HEAD); echo 1 >"$r/notes"; git -C "$r" commit -q --no-verify -m n -- notes; git -C "$r/sub" checkout -q "$uA"
  { v6row "$old"; v6row "$(git -C "$r" rev-parse HEAD)"; } >"$r/.submodule_pin_waivers"; git -C "$r" add .submodule_pin_waivers; o+="KV19STALEFIRST=$(lgc "$r" -a -m rb)/$(lpin "$r") "
  # KV20: a row with a bad expiry, then a valid row -> waived
  v6sup; r=$SR; git -C "$r/sub" checkout -q "$uA"; { v6row "$(git -C "$r" rev-parse HEAD)" ops never; v6row "$(git -C "$r" rev-parse HEAD)"; } >"$r/.submodule_pin_waivers"; git -C "$r" add .submodule_pin_waivers
  o+="KV20BADEXPFIRST=$(lgc "$r" -a -m rb)/$(lpin "$r") "
  # KV22: diverged pins (B -> S, complete history) while the submodule's shallow state is UNKNOWN (a git that answers
  # `unknown`): the history is not proven complete -> BLIND (2), never WARN; control with the real git: WARN (0)
  v6sup; r=$SR; git -C "$r" update-index --cacheinfo 160000,"$uS",sub; mkdir -p "$tmp/fk22"
  printf '#!/bin/bash\nfor a in "$@"; do [ "$a" = --is-shallow-repository ] && { echo unknown; exit 0; }; done\nexec %s "$@"\n' "$realgit" >"$tmp/fk22/git"; chmod +x "$tmp/fk22/git"
  a=$(PATH="$tmp/fk22:$PATH" lg "$r"); c=$(grep -c 'cannot be decided' "$tmp/gout"); b=$(lg "$r"); o+="KV22SUBUNKNOWN=$a/$c,$b/$(grep -c WARN "$tmp/gout") "
  # KV29 (control): a planted unicodedata.py in the cwd must not change the authoriser check (sys and unicodedata are
  # builtin modules here, so this is no killer of V29; the start-up hook below is)
  v6sup; r=$SR; printf 'import itertools\n_c=itertools.count()\ndef normalize(f,s): return "u%%d" %% next(_c)\ndef category(c): return "Lu"\n' >"$r/unicodedata.py"
  git -C "$r/sub" checkout -q "$uA"; v6row "$(git -C "$r" rev-parse HEAD)" t >"$r/.submodule_pin_waivers"; git -C "$r" add .submodule_pin_waivers sub
  o+="KV29PLANT=$(cd "$r" && bash "$LG" --root "$r" >"$tmp/gout" 2>&1; echo $?)/$(grep -c 'self-waive' "$tmp/gout") "
  # KV29b: a sitecustomize.py on PYTHONPATH that replaces unicodedata.normalize; with -I it is ignored (self-waive
  # refused, rc 1), without -I it runs at interpreter start and the self-waive is honoured (rc 0)
  up="$tmp/u29.$RANDOM"; git init -q "$up"; git -C "$up" commit -q --allow-empty -m A; a=$(git -C "$up" rev-parse HEAD); git -C "$up" commit -q --allow-empty -m B; b=$(git -C "$up" rev-parse HEAD)
  s="$tmp/s29.$RANDOM"; git init -q "$s"; git -C "$s" submodule add -q "file://$up" sub >/dev/null 2>&1; git -C "$s" commit -q --no-verify -m base
  git -C "$s/sub" checkout -q "$a"; printf 'sub\t%s\t%s\tt\t%s\tCON-046\t%s\n' "$b" "$a" "$d10" "$(git -C "$s" rev-parse HEAD)" >"$s/.submodule_pin_waivers"
  git -C "$s" add sub .submodule_pin_waivers
  pp="$tmp/pp29"; mkdir -p "$pp"; printf 'import itertools,unicodedata\n_c=itertools.count()\nunicodedata.normalize=lambda f,s: "u%%d" %% next(_c)\n' >"$pp/sitecustomize.py"
  a=$(bash "$g" --root "$s" >"$tmp/o0" 2>&1; echo $?); b=$(PYTHONPATH="$pp" bash "$g" --root "$s" >"$tmp/o1" 2>&1; echo $?)
  o+="KV29B=$a/$(grep -c self-waive "$tmp/o0"),$b/$(grep -c self-waive "$tmp/o1") "
  # KV02: -h exit status
  o+="KV02HELP=$(bash "$g" -h >/dev/null 2>&1; echo $?) "
  # KV35: no row for the transition -> the reason names the missing row (not a base mismatch)
  v6sup; r=$SR; git -C "$r/sub" checkout -q "$uA"; v6row "$(git -C "$r" rev-parse HEAD)" ops "$d10" other >"$r/.submodule_pin_waivers"; git -C "$r" add .submodule_pin_waivers sub
  o+="KV35=$(lg "$r")/$(grep -c 'no waiver row for' "$tmp/gout") "
  # ── author, structural round: one fixture per per-row site of the row loop (invalid row FIRST, valid row second ->
  # WAIVED, pin A): CR, expired, beyond the horizon, bad item, self-authoriser (python rc 10), invalid UTF-8 (rc 4)
  hb() { git -C "$SR" rev-parse HEAD; }
  v6sup; x="$(v6row "$(hb)" | tr -d '\n')\r\n"; o+="SITECR=$(v6first "$x")/$(lpin "$SR") "
  v6sup; o+="SITEEXP=$(v6first "$(v6row "$(hb)" ops 2000-01-01)\n")/$(lpin "$SR") "
  v6sup; o+="SITEHOR=$(v6first "$(v6row "$(hb)" ops "$d200")\n")/$(lpin "$SR") "
  v6sup; o+="SITEITEM=$(v6first "$(v6row "$(hb)" | sed 's/\tCON-046\t/\tCON-46\t/')\n")/$(lpin "$SR") "
  v6sup; o+="SITESELF=$(v6first "$(v6row "$(hb)" t)\n")/$(lpin "$SR") "
  v6sup; o+="SITEUTF8=$(v6first "$(v6row "$(hb)" $'op\377s')\n")/$(lpin "$SR") "
  # the authoriser form: `<` alone and `>` alone are each refused (rc 3)
  v6sup; a=$(v6rb "$SR" 'a<b')/$(lpin "$SR"); v6sup; b=$(v6rb "$SR" 'a>b')/$(lpin "$SR"); o+="AUTHLTGT=$a,$b "
  # item_prefix members: one letter, a leading non-letter, a trailing metacharacter -> config error, waivers disabled (1)
  x=""; for c in C:C-046 1CON:1CON-046 CO.N:CO.N-046; do
    v6sup; r=$SR; printf 'item_prefix=%s\n' "${c%%:*}" >"$r/.submodule_pin_gate.conf"; git -C "$r" add .submodule_pin_gate.conf; git -C "$r" commit -q --no-verify -m conf
    git -C "$r/sub" checkout -q "$uA"; v6row "$(hb)" | sed "s/\tCON-046\t/\t${c#*:}\t/" >"$r/.submodule_pin_waivers"; git -C "$r" add .submodule_pin_waivers
    x+="$(lgc "$r" -a -m rb)/$(lpin "$r"),"; done; o+="PREFIXFORM=$x "
  # max_waiver_days: 100 (three digits, the regex upper member) honoured with a 99-day expiry; 366 refused (config error)
  v6sup; r=$SR; printf 'max_waiver_days=100\n' >"$r/.submodule_pin_gate.conf"; git -C "$r" add .submodule_pin_gate.conf; git -C "$r" commit -q --no-verify -m conf
  git -C "$r/sub" checkout -q "$uA"; v6row "$(hb)" ops "$(date -d '+99 days' +%F)" >"$r/.submodule_pin_waivers"; git -C "$r" add .submodule_pin_waivers; a=$(lgc "$r" -a -m rb)/$(lpin "$r")
  v6sup; r=$SR; printf 'max_waiver_days=366\n' >"$r/.submodule_pin_gate.conf"; git -C "$r" add .submodule_pin_gate.conf; git -C "$r" commit -q --no-verify -m conf
  git -C "$r/sub" checkout -q "$uA"; v6row "$(hb)" >"$r/.submodule_pin_waivers"; git -C "$r" add .submodule_pin_waivers; b=$(lgc "$r" -a -m rb)/$(lpin "$r"); o+="DAYS100=$a,$b "
  echo "$o"
}
members7() { # gate path -> vector part (round 7: killers for member/site mutants the screening showed alive)
  local g="$1" o="" r d
  # ROOTDEFAULT: no --root -> the root is the repository the gate file sits in (scripts/gates/ two levels down)
  mk;r=$R; mkdir -p "$r/scripts/gates"; cp "$g" "$r/scripts/gates/x.sh"; stage "$r" "$A"
  ( cd "$tmp" && bash "$r/scripts/gates/x.sh" >"$tmp/out" 2>&1 ); o+="ROOTDEFAULT=$?/$(cnt 'ANCESTOR') "
  # MSGNOROW: waiver data present, no row for this transition -> the reason names the missing row (not a later check)
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$S" ops "$d10" CON-046)\n"; o+="MSGNOROW=$(run "$r" "$g")/$(cnt 'no waiver row for (sub') "
  # HOOKSKIP: the hook copied where no gate sits beside it -> SKIP, exit 0 (never a silent block); HOOKNOREPO: the hook
  # (gate beside it) run outside any work tree -> exit 1 from its own root check (not the gate's usage error 2)
  d="$(mktemp -d "$tmp/hk.XXXXXX")"; mkdir -p "$d/lonely" "$d/l/scripts/gates" "$d/l/scripts/hooks" "$d/nowt"; cp "$hook" "$d/lonely/pre-commit"
  cp "$g" "$d/l/scripts/gates/cm_submodule_pin_not_downgraded.sh"; cp "$hook" "$d/l/scripts/hooks/pre-commit-submodule-pin-not-downgraded"
  mk;r=$R; ( cd "$r" && bash "$d/lonely/pre-commit" >"$tmp/out" 2>&1 ); o+="HOOKSKIP=$?/$(cnt 'SKIP') "
  ( cd "$d/nowt" && GIT_CEILING_DIRECTORIES="$d" bash "$d/l/scripts/hooks/pre-commit-submodule-pin-not-downgraded" >"$tmp/out" 2>&1 ); o+="HOOKNOREPO=$? "
  echo "$o"
}
members8() { # gate path -> vector part (round 8): the four round-7 reviewer probes, adopted VERBATIM (§11.4.194(6)(d);
  # sha256 in cm_submodule_pin_not_downgraded_probes/SHA256SUMS), each token prefixed S_/D_/F_/G_ so their keys cannot
  # collide; then killers for the fail-open (fo) needs the round-7 dynamic lint found unmet
  local g="$1" o="" r f d p t k w z
  for p in safedir:S decide_oneway:D rv7_fresh:F graph_missing:G; do
    t="$(TMPDIR="$tmp" bash "$here/cm_submodule_pin_not_downgraded_probes/p_${p%%:*}.sh" "$g" 2>/dev/null)"; t="${t#*: }"
    for k in $t; do o+="${p##*:}_$k "; done
  done
  # ARGSFWD: a FORWARD bump with `--base ''` / `--waivers ''` -> usage error 2 (an unchecked empty value passes it: 0)
  mk;r=$R; git -C "$r/sub" checkout -q "$B"; git -C "$r/sub" commit -q --allow-empty -m F; f=$(git -C "$r/sub" rev-parse HEAD); stage "$r" "$f"
  o+="ARGSFWD=$(run "$r" "$g" -- --base ''),$(run "$r" "$g" -- --waivers '') "
  # SYMSUBFWD: a FORWARD bump through a symlinked checkout -> BLIND, named (an unchecked symlink would pass it: 0)
  mk;r=$R; d="$tmp/elsewhere.$RANDOM"; git clone -q "$r/sub" "$d" 2>/dev/null; git -C "$d" checkout -q "$B"; git -C "$d" commit -q --allow-empty -m F
  f=$(git -C "$d" rev-parse HEAD); rm -rf "${r:?}/sub"; ln -s "$d" "$r/sub"; stage "$r" "$f"; o+="SYMSUBFWD=$(run "$r" "$g")/$(cnt 'checkout path is a symlink') "
  # killers for the generated members the round-8 screening showed alive (gen-rxq-*, gen-andor-*):
  # MAXD: max_waiver_days=9 with a +5-day row is honoured ({1,2} would refuse a 1-digit value); =010 and ='10 ' are
  # refused (a regex without ^ or $ lets `[ -le ]` read them as 10, so the row would be honoured)
  e="$(date -d '+5 days' +%F)"; mk;r=$R; conf "$r" 'max_waiver_days=9\n'; git -C "$r" commit -q -m conf; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$e" CON-046)\n"; f="$(run "$r" "$g"),"
  mk;r=$R; conf "$r" 'max_waiver_days=010\n'; git -C "$r" commit -q -m conf; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046)\n"; f+="$(run "$r" "$g")/$(cnt 'not an integer 1..365'),"
  mk;r=$R; conf "$r" 'max_waiver_days=10 \n'; git -C "$r" commit -q -m conf; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046)\n"; f+="$(run "$r" "$g")/$(cnt 'not an integer 1..365')"
  o+="MAXD=$f "
  # PFXDIGIT: item_prefix=C1T is legal (^[A-Z][A-Z0-9]+$) and its row is honoured; ITEMJUNK: item XCON-046 is refused
  mk;r=$R; conf "$r" 'item_prefix=C1T\n'; git -C "$r" commit -q -m conf; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" C1T-046)\n"; o+="PFXDIGIT=$(run "$r" "$g") "
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" XCON-046)\n"; o+="ITEMJUNK=$(run "$r" "$g")/$(cnt 'does not match CON-NNN') "
  # IDENTONE: only the committer (then only the author) identity is unresolvable -> the row is refused, named
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046)\n"; git -C "$r" config user.useConfigOnly true
  f="$(run "$r" "$g" -u GIT_COMMITTER_NAME -u GIT_COMMITTER_EMAIL)/$(cnt 'identity unresolvable'),"
  f+="$(run "$r" "$g" -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL)/$(cnt 'identity unresolvable')"; o+="IDENTONE=$f "
  # ROOTNEST (full run 1 of round 8: root-default-wrong survived ROOTDEFAULT, because the gate normalises its root to
  # --show-toplevel and scripts/ sat inside the same repository): scripts/ is its own repository, so one level up
  # (the mutant) finds that inner repository and two levels up (the gate) the superproject with the staged downgrade
  mk;r=$R; stage "$r" "$A"; mkdir -p "$r/scripts/gates"; git -C "$r/scripts" init -q; git -C "$r/scripts" commit -q --allow-empty -m n
  cp "$g" "$r/scripts/gates/x.sh"; ( cd "$tmp" && bash "$r/scripts/gates/x.sh" >"$tmp/out" 2>&1 ); o+="ROOTNEST=$?/$(cnt 'ANCESTOR') "
  # SUBBROKEN (full run 1: checkout-check-dropped survived): the checkout holds a .git file whose gitdir does not exist,
  # so git cannot open it at all; the git-dir member names it "checkout missing", without it the later toplevel member
  # refuses with "not its own repository" (same exit, other reason). An EMPTY directory does not separate them: git
  # discovers the superproject there, the git-dir member passes and the toplevel member refuses in both gates.
  mk;r=$R; stage "$r" "$A"; rm -rf "${r:?}/sub"; mkdir "$r/sub"; printf 'gitdir: %s\n' "$tmp/no-such-gitdir" >"$r/sub/.git"; o+="SUBBROKEN=$(run "$r" "$g")/$(cnt 'checkout missing')/$(cnt 'not its own repository') "
  # round 9 (review F4; reviewer mutants RV8-01, RV8-02 adopted below): git keeps a NON-ASCII space in an ident name
  # (it strips ASCII whitespace only), so the self-waive check must strip the whole Unicode Zs class (python strip()).
  # ZSID: committer and author name "t" + every Zs character (all 17 in one string), then every Zs character + "t", with
  # authoriser "t": both refused as self-waive. A strip that misses ANY Zs character (or one side) stops at it, so the
  # name no longer equals "t" and the row is honoured (0). Needles: the Zs count, and the pad "tx" (not a space) is honoured.
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" t "$d10" CON-046)\n"
  f="$(run "$r" "$g" GIT_COMMITTER_NAME="t$zscat" GIT_AUTHOR_NAME="t$zscat")/$(cnt 'self-waive'),"
  f+="$(run "$r" "$g" GIT_COMMITTER_NAME="${zscat}t" GIT_AUTHOR_NAME="${zscat}t")/$(cnt 'self-waive')"
  o+="ZSID=$f/${#zsl[@]}/$(run "$r" "$g" GIT_COMMITTER_NAME=tx GIT_AUTHOR_NAME=tx) "
  # ZSAUTH: one waiver row per Zs character and side, authoriser "me" + z and z + "me" (34 rows for the same transition):
  # every row is refused by the authoriser form check (exit 1, no row honoured); a check that strips only ASCII honours
  # the first non-ASCII row. Needle: a lone row with authoriser "mex" is honoured.
  mk;r=$R; stage "$r" "$A"; w=""; for z in "${zsl[@]}"; do w+="$(wf sub "$B" "$A" "me$z" "$d10" CON-046)\n$(wf sub "$B" "$A" "${z}me" "$d10" CON-046)\n"; done
  waive "$r" "$w"; f="$(run "$r" "$g")/$(cnt ': WAIVED')/$(grep -c '' "$r/.submodule_pin_waivers")"
  waive "$r" "$(wf sub "$B" "$A" mex "$d10" CON-046)\n"; o+="ZSAUTH=$f/$(run "$r" "$g") "
  # YEAR5 (review F1/F2): max_waiver_days=365 and expiry "<this year>9-01-01", a five-digit year that sorts after today and
  # before the horizon and that GNU date round-trips (needle at the top): only the {4} year of the regex refuses it
  mk;r=$R; conf "$r" 'max_waiver_days=365\n'; git -C "$r" commit -q -m conf; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "${today%%-*}9-01-01" CON-046)\n"
  o+="YEAR5=$(run "$r" "$g")/$(cnt 'not a real YYYY-MM-DD') "
  echo "$o"
}
near() { # <40-hex sha> -> the 7 near misses of members10 (SHANEAR, SPENTNEAR), one per line
  local s="$1" k c; for k in 0 11 12 39; do c="${s:k:1}"; [ "$c" = 0 ] && c=1 || c=0; printf '%s\n' "${s:0:k}$c${s:k+1}"; done
  printf '%s\n' "${s^^}" "${s}0" "${s:0:39}"; }
ysib() { # <repo> <parent> <waiver text>: refs/heads/y = one commit on <parent> whose tree is <parent>'s plus that waiver
  # file, built through a private index (the judged index is not touched); replaces the previous y
  local r="$1" p="$2" ix="$tmp/ysib.idx" h t; rm -f "$ix"
  GIT_INDEX_FILE="$ix" git -C "$r" read-tree "$p"; h=$(printf '%b' "$3" | git -C "$r" hash-object -w --stdin)
  GIT_INDEX_FILE="$ix" git -C "$r" update-index --add --cacheinfo 100644,"$h",.submodule_pin_waivers
  t=$(GIT_INDEX_FILE="$ix" git -C "$r" write-tree); git -C "$r" update-ref refs/heads/y "$(git -C "$r" commit-tree "$t" -p "$p" -m y)"; }
# META: near() must give 7 distinct values, none equal to its input (a sha with no letter would make the upper-case
# member equal; the check refuses rather than silently testing 6)
nck="$(near 0123456789abcdef0123456789abcdef01234567 | sort -u | grep -vxc 0123456789abcdef0123456789abcdef01234567)"
[ "$nck" = 7 ] || { echo "META near() gives $nck distinct near misses, want 7"; exit 2; }
members10() { # gate path -> vector part (round 10, review N1/N2, §11.4.276(E) structural pass)
  # ── N1: every date / number compare of the gate, each as a BOUNDARY PAIR (the last value on the accepting side and
  # the first on the refusing side), generated from one table, never point-fixed. The compares (gate line: compare):
  #   137 need(): argc -ge 2      -> equivalence proof eq-need-argc-redundant (argc < 2 implies an empty value)
  #   151 ${#lev[@]} -gt 0        -> LEVBND: 1 variable proceeds (a downgrade is FAIL 1), 0 is BLIND 2
  #   181 max_waiver_days regex ^[1-9][0-9]{0,2}$ and -le 365 -> DAYSBND: 0|1, 99|100, 365|366, 999|1000
  #   182 item_prefix ^[A-Z][A-Z0-9]+$ (two characters at least) -> PFXBND: C refused | CN honoured
  #   187 lim = today + maxd, 248 e > lim -> HORBND: for maxd 30 (default), 1, 365: today+maxd honoured | +1 refused
  #   247 e < today              -> EXPBND: today-1 refused ("waiver expired") | today honoured
  #   246 year {4}               -> YEAR5 (members8: a five-digit year refused); a three-digit year is before today and
  #                                 never reaches the compare as a valid row: not constructible, so no pair
  #   249 item -[0-9]{3,}        -> ITEMBND: CON-46 refused | CON-046 and CON-0046 honoured
  #   196 len(p)!=5              -> equivalence proof eq-idpy-len-dropped (printf always yields 5 fields)
  #   138 while [ $# -gt 0 ]     -> (round 11, review r10 F5: missing from this list in round 10) ARGNEAR (members11): a
  #                                 trailing near-miss flag is a usage error; RV10-04 (-gt 1) is killed
  # (Round 11: the line numbers above are those of the round-10 gate; the site table cm_submodule_pin_not_downgraded_
  # sites.tsv is now the complete, linted list of every compare, with its anchor instead of a line number. The SHA
  # equalities of the spent scan, round-10 lines 219 `$1""!=h""` / `$i""==b""` and 274 `!= "$nsha"`, have no near miss
  # that the scan can see: both sides are full SHAs that git printed, so a prefix or case near miss is not constructible
  # without a 12-character prefix collision; they stay out of SHANEAR by that argument, rows S0xx of the site table.)
  # The other compares of the gate are equalities on exit codes, flags or SHAs (fwd/back, irc, fail/blind, dstat, the
  # 160000 modes); they have no ordered boundary, and their members are in the inventory and the generated ledger.
  local g="$1" o="" r f v e m x
  mk;r=$R; stage "$r" "$A"; f=""
  for e in "$(date -d "$today -1 day" +%F)" "$today"; do waive "$r" "$(wf sub "$B" "$A" ops "$e" CON-046)\n"; f+="$(run "$r" "$g")/$(cnt 'waiver expired'),"; done
  o+="EXPBND=$f "
  f=""
  for m in 30 1 365; do mk;r=$R; [ "$m" = 30 ] || { conf "$r" "max_waiver_days=$m\n"; git -C "$r" commit -q -m conf; }; stage "$r" "$A"
    for x in 0 1; do waive "$r" "$(wf sub "$B" "$A" ops "$(date -d "$today +$((m+x)) days" +%F)" CON-046)\n"; f+="$(run "$r" "$g"),"; done; done
  o+="HORBND=$f "
  f=""
  for v in 0 1 99 100 365 366 999 1000; do mk;r=$R; conf "$r" "max_waiver_days=$v\n"; git -C "$r" commit -q -m conf; stage "$r" "$A"
    waive "$r" "$(wf sub "$B" "$A" ops "$today" CON-046)\n"; f+="$(run "$r" "$g")/$(cnt 'not an integer 1..365'),"; done
  o+="DAYSBND=$f "
  mk;r=$R; conf "$r" 'item_prefix=C\n'; git -C "$r" commit -q -m conf; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" C-046)\n"; f="$(run "$r" "$g")/$(cnt 'does not match'),"
  mk;r=$R; conf "$r" 'item_prefix=CN\n'; git -C "$r" commit -q -m conf; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" CN-046)\n"; f+="$(run "$r" "$g")"
  o+="PFXBND=$f "
  mk;r=$R; stage "$r" "$A"; f=""
  for e in CON-46 CON-046 CON-0046; do waive "$r" "$(wf sub "$B" "$A" ops "$d10" "$e")\n"; f+="$(run "$r" "$g"),"; done
  o+="ITEMBND=$f "
  # LEVBND: a git whose --local-env-vars prints exactly ONE variable; the gate must proceed (the staged downgrade is
  # FAIL 1), and with none it is BLIND (LEV, inventory); a test `-gt 1` would make the one-variable git BLIND too
  mkdir -p "$tmp/fklev1"; printf '#!/bin/bash\n[ "$1" = rev-parse ] && [ "$2" = --local-env-vars ] && { echo GIT_DIR; exit 0; }\nexec %s "$@"\n' "$realgit" >"$tmp/fklev1/git"; chmod +x "$tmp/fklev1/git"
  mk;r=$R; stage "$r" "$A"; o+="LEVBND=$(run "$r" "$g" PATH="$tmp/fklev1:$PATH")/$(cnt 'ANCESTOR') "
  # ── N2: the whitespace class of the gate's strip() sites is python isspace() (wsl, enumerated at the top), not Zs. The
  # whitespace sites of the gate: (a) IDPY `a!=a.strip()`: the authoriser's padding; (b) IDPY `i.strip() and`: the
  # truthiness of an identity field (equivalence proof eq-ident-strip-truthiness); (c) IDPY `f(i.strip())`: the
  # identity compared; (d) the config reader takes `key=value` lines verbatim (no trim: a padded key is unknown, a padded
  # value fails the regex, MAXD and CONFWS); (e) waiver rows are split on TAB (awk -F'\t') and newline, so TAB and LF
  # cannot sit inside a field (wsrow drops them); (f) idname/idmail split git's ident on " <" and ">". Sites (a) and (c)
  # get every isspace() character: WSID pads the committer and author name "t" with all of them on the right, then on
  # the left (one string each: a strip that misses ANY member stops there, so the name no longer equals "t" and the row
  # is honoured, 0); WSAUTH has one row per character and side ("me"+c, c+"me", for the wsrow characters): every row is
  # refused. Needles: the counts, and the pad "x" honoured (tx, mex). ZSID / ZSAUTH (members8) stay as the Zs sub-needle.
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" t "$d10" CON-046)\n"
  f="$(run "$r" "$g" GIT_COMMITTER_NAME="t$wscat" GIT_AUTHOR_NAME="t$wscat")/$(cnt 'self-waive'),"
  f+="$(run "$r" "$g" GIT_COMMITTER_NAME="${wscat}t" GIT_AUTHOR_NAME="${wscat}t")/$(cnt 'self-waive')"
  o+="WSID=$f/${#wsl[@]}/$(run "$r" "$g" GIT_COMMITTER_NAME=tx GIT_AUTHOR_NAME=tx) "
  mk;r=$R; stage "$r" "$A"; x=""; for v in "${wsrow[@]}"; do x+="$(wf sub "$B" "$A" "me$v" "$d10" CON-046)\n$(wf sub "$B" "$A" "${v}me" "$d10" CON-046)\n"; done
  waive "$r" "$x"; f="$(run "$r" "$g")/$(cnt ': WAIVED')/$(grep -c '' "$r/.submodule_pin_waivers")"
  waive "$r" "$(wf sub "$B" "$A" mex "$d10" CON-046)\n"; o+="WSAUTH=$f/$(run "$r" "$g") "
  # CONFWS (site d): a key padded with a space is unknown (waivers disabled); the same line unpadded is honoured
  f=""; for x in ' max_waiver_days=60' 'max_waiver_days =60' 'max_waiver_days=60'; do mk;r=$R; conf "$r" "$x\n"; git -C "$r" commit -q -m conf; stage "$r" "$A"
    waive "$r" "$(wf sub "$B" "$A" ops "$d45" CON-046)\n"; f+="$(run "$r" "$g"),"; done
  o+="CONFWS=$f "
  # ── SHA equalities (round 10, RV9-05 survived the first round-10 run: a base compared on its first 12 characters).
  # Class, not point: every exact SHA compare of the gate gets the same NEAR-MISS set (near(): first, 12th, 13th and last
  # character flipped, upper case, one character added, the last one dropped), so a prefix compare of any length, a
  # suffix compare, a case-folding compare and a length-blind compare all fail. The compares: line 240 (row old $2==o,
  # row new $3==n: SHANEAR fields 1, 2), line 245 (row base bs = basec: SHANEAR field 3; every near miss is refused, the
  # exact row is honoured), line 229 (spent: a sibling commit on the same parent whose row differs from the judged
  # transition by a near miss in old, new or base does NOT spend it, SPENTNEAR fields 1-3 all 0; the exact sibling row
  # spends it, 1, with the 'already spent' needle). The path compares are string compares too (SPENTNUM, NUMPATH).
  mk;r=$R; stage "$r" "$A"; x=$(git -C "$r" rev-parse HEAD); f=""
  for v in $(near "$B"); do waive "$r" "$(wf sub "$v" "$A" ops "$d10" CON-046)\n"; f+="$(run "$r" "$g")"; done; f+="/"
  for v in $(near "$A"); do waive "$r" "$(wf sub "$B" "$v" ops "$d10" CON-046)\n"; f+="$(run "$r" "$g")"; done; f+="/"
  for v in $(near "$x"); do waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046 "$v")\n"; f+="$(run "$r" "$g")"; done
  waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046 "$x")\n"; o+="SHANEAR=$f/$(run "$r" "$g") "
  f=""
  for v in $(near "$B"); do ysib "$r" "$x" "$(wf sub "$v" "$A" ops "$d10" CON-046 "$x")\n"; f+="$(run "$r" "$g")"; done; f+="/"
  for v in $(near "$A"); do ysib "$r" "$x" "$(wf sub "$B" "$v" ops "$d10" CON-046 "$x")\n"; f+="$(run "$r" "$g")"; done; f+="/"
  for v in $(near "$x"); do ysib "$r" "$x" "$(wf sub "$B" "$A" ops "$d10" CON-046 "$v")\n"; f+="$(run "$r" "$g")"; done
  ysib "$r" "$x" "$(wf sub "$B" "$A" ops "$d10" CON-046 "$x")\n"; o+="SPENTNEAR=$f/$(run "$r" "$g")/$(cnt 'already spent') "
  git -C "$r" update-ref -d refs/heads/y
  echo "$o"
}
# ── round 11 (CON-194, review r10 F1-F6, §11.4.276(E)(3) structural round): fixtures named by the SITE TABLE. Every
# exact-compare and character-set site of the gate and the hook has a row in cm_submodule_pin_not_downgraded_sites.tsv
# (found by the census in cm_submodule_pin_not_downgraded_sites.py, checked by the site lint below); a data row names
# the vector keys of its near-miss pair (the exact value on the accepting side, its near misses on the refusing side)
# and the mutant that each pair kills. members11 runs one generator per key the table names (s11keys); a key in the
# table without a generator, or a generator no row names, is a META error, so the table decides what runs.
s11tab="$here/cm_submodule_pin_not_downgraded_sites.tsv"; s11py="$here/cm_submodule_pin_not_downgraded_sites.py"
pnear() { # <path> -> the path near misses of PATHNEAR / SPENTPATHNEAR, one per line: case (upper, title), prefix,
  # suffix, a character before, a trailing slash, a ./ prefix, a space on either side
  local p="$1"; printf '%s\n' "${p^^}" "${p^}" "${p:0:${#p}-1}" "${p}x" "x${p}" "${p}/" "./${p}" " ${p}" "${p} "; }
g11_WSID4() { # F1: all FOUR identity fields (committer name, committer email, author name, author email), each padded
  # on the right, then on the left, with every isspace() character git keeps (gkl, measured); the three other fields
  # hold other values. The authoriser is the unpadded value, so the gate must strip the pad and refuse (self-waive, 1).
  # Needle: the same field padded with "x" is a different identity (0).
  local g="$1" r f k side v o="" n=0 x
  local -a F=(GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL) B=(t t@t t t@t)
  mk;r=$R; stage "$r" "$A"
  for k in 0 1 2 3; do
    waive "$r" "$(wf sub "$B" "$A" "${B[k]}" "$d10" CON-046)\n"
    for side in R L; do [ "$side" = R ] && v="${B[k]}$gkcat" || v="$gkcat${B[k]}"
      o+="$(run "$r" "$g" GIT_COMMITTER_NAME=cn GIT_COMMITTER_EMAIL=ce@x GIT_AUTHOR_NAME=an GIT_AUTHOR_EMAIL=ae@x "${F[k]}=$v")"
      n=$((n+$(cnt 'self-waive'))); done; done
  x="$(run "$r" "$g" GIT_COMMITTER_NAME=cn GIT_COMMITTER_EMAIL="t@tx" GIT_AUTHOR_NAME=an GIT_AUTHOR_EMAIL=ae@x)"
  echo "WSID4=$o/$n/${#gkl[@]}/$x "; }
g11_TZPAIR() { # F2: the gate's today is the UTC date. Kiritimati (UTC+14) is a day AHEAD of UTC when the UTC hour is
  # >= 10, Etc/GMT+12 (UTC-12) a day BEHIND when it is < 12, so at every hour at least one of the two differs from UTC:
  # expiry = UTC today under Kiritimati honoured (0), = UTC today-1 under GMT+12 refused (1), = UTC today+31 under
  # Kiritimati refused (1), = UTC today+30 under GMT+12 honoured (0). A gate using the local date flips one of them.
  local g="$1" r o=""
  mk;r=$R; stage "$r" "$A"
  waive "$r" "$(wf sub "$B" "$A" ops "$today" CON-046)\n"; o+="$(run "$r" "$g" TZ=Pacific/Kiritimati),"
  waive "$r" "$(wf sub "$B" "$A" ops "$(date -d "$today -1 day" +%F)" CON-046)\n"; o+="$(run "$r" "$g" TZ=Etc/GMT+12),"
  waive "$r" "$(wf sub "$B" "$A" ops "$(date -d "$today +31 days" +%F)" CON-046)\n"; o+="$(run "$r" "$g" TZ=Pacific/Kiritimati),"
  waive "$r" "$(wf sub "$B" "$A" ops "$(date -d "$today +30 days" +%F)" CON-046)\n"; o+="$(run "$r" "$g" TZ=Etc/GMT+12)"
  echo "TZPAIR=$o/$(TZ=Pacific/Kiritimati date +%z)/$(TZ=Etc/GMT+12 date +%z) "; }
g11_PATHNEAR() { # F4: the waiver row's path compare (`$1""==p""`, case-sensitive, whole string): the exact path is
  # honoured, every near miss of pnear() is refused
  local g="$1" r o v; mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046)\n"; o="$(run "$r" "$g")/"
  while IFS= read -r v; do waive "$r" "$(wf "$v" "$B" "$A" ops "$d10" CON-046)\n"; o+="$(run "$r" "$g")"; done < <(pnear sub)
  echo "PATHNEAR=$o "; }
g11_SPENTPATHNEAR() { # F4: the spent check's path compare: a same-parent sibling whose row differs only by a near-miss
  # path spends nothing (0 each); the exact row spends it (1)
  local g="$1" r x o="" v; mk;r=$R; stage "$r" "$A"; x=$(git -C "$r" rev-parse HEAD); waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046)\n"
  while IFS= read -r v; do ysib "$r" "$x" "$(wf "$v" "$B" "$A" ops "$d10" CON-046 "$x")\n"; o+="$(run "$r" "$g")"; done < <(pnear sub)
  ysib "$r" "$x" "$(wf sub "$B" "$A" ops "$d10" CON-046 "$x")\n"; o+="/$(run "$r" "$g")"; git -C "$r" update-ref -d refs/heads/y
  echo "SPENTPATHNEAR=$o "; }
g11_SPENTFIELDS() { # the spent check's field count (`NF==7`): a sibling row with 8 fields (one extra) or 6 spends nothing
  local g="$1" r x o=""; mk;r=$R; stage "$r" "$A"; x=$(git -C "$r" rev-parse HEAD); waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046)\n"
  ysib "$r" "$x" "$(wf sub "$B" "$A" ops "$d10" CON-046 "$x" | tr -d '\n')\tz\n"; o+="$(run "$r" "$g"),"
  ysib "$r" "$x" "$(wf sub "$B" "$A" ops "$d10" CON-046 "$x" | cut -f1-6)\n"; o+="$(run "$r" "$g"),"
  ysib "$r" "$x" "$(wf sub "$B" "$A" ops "$d10" CON-046 "$x")\n"; o+="$(run "$r" "$g")"; git -C "$r" update-ref -d refs/heads/y
  echo "SPENTFIELDS=$o "; }
g11_ARGNEAR() { # the argument parser's case arms: each flag exactly, with a valid value, is accepted (0); each near
  # miss (case, a character missing, one added), given the SAME valid value, is a usage error (2)
  local g="$1" r o="" v; mk;r=$R; : >"$tmp/emptyw"
  for v in "--root $r" "--base HEAD" "--waivers $tmp/emptyw" -h --help; do o+="$(bash "$g" --root "$r" $v >/dev/null 2>&1; echo $?)"; done; o+="/"
  for v in "--ROOT $r" "--Root $r" "--roo $r" "--rootx $r" "--BASE HEAD" "--bas HEAD" "--basex HEAD" "--WAIVERS $tmp/emptyw" \
      "--waiver $tmp/emptyw" "--waiversx $tmp/emptyw" -H --HELP --hel --helpx; do o+="$(bash "$g" --root "$r" $v >/dev/null 2>&1; echo $?)"; done
  echo "ARGNEAR=$o "; }
g11_CONFKEYNEAR() { # the config key arms: the exact key is honoured (max 60, a 45-day expiry, 0), every near miss is an
  # unknown key, which disables waivers (1). The item_prefix arm uses a 10-day expiry (inside the default 30), so its
  # exact key is honoured (0) and a near miss is refused ONLY because the key is unknown (round-11 run on the merged
  # head: with the 45-day expiry every item_prefix probe was refused by the horizon too, and itemkey-prefix survived)
  local g="$1" r o="" v e
  for v in max_waiver_days=60 Max_waiver_days=60 MAX_WAIVER_DAYS=60 max_waiver_day=60 max_waiver_daysx=60 xmax_waiver_days=60 \
      item_prefix=CON ITEM_PREFIX=CON item_prefi=CON item_prefixx=CON; do
    case "$v" in max*|Max*|MAX*|xmax*) e="$d45" ;; *) e="$d10" ;; esac
    mk;r=$R; conf "$r" "$v\n"; git -C "$r" commit -q -m conf; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$e" CON-046)\n"
    o+="$(run "$r" "$g")"; case "$v" in max_waiver_days=60|xmax_waiver_days=60|item_prefix=CON) o+="/" ;; esac; done
  echo "CONFKEYNEAR=$o "; }
g11_CONFHASH() { # the config comment arm `'#'*`: a line starting with # is a comment (0); " #c" (a space before the #)
  # and "x#c" are not comments: not key=value, waivers disabled (1)
  local g="$1" r o="" v
  for v in '#c' ' #c' 'x#c'; do mk;r=$R; conf "$r" "$v\n"; git -C "$r" commit -q -m conf; stage "$r" "$A"
    waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046)\n"; o+="$(run "$r" "$g"),"; done
  echo "CONFHASH=$o "; }
g11_DUPNEAR() { # the duplicate-key compare `*" $k "*`: a later key that is a SUBSTRING of an earlier one is unknown,
  # never "duplicated" (rc / unknown count / duplicated count)
  local g="$1" r; mk;r=$R; conf "$r" 'max_waiver_days=60\nwaiver_days=1\n'; git -C "$r" commit -q -m conf; stage "$r" "$A"
  waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046)\n"; echo "DUPNEAR=$(run "$r" "$g")/$(cnt 'unknown')/$(cnt 'duplicated') "; }
g11_CONFSPLIT() { # the key=value split `${line%%=*}` / `${line#*=}` (first =): item_prefix=A=B is a bad VALUE of a known
  # key, never an unknown key "item_prefix=A" (rc / value message / unknown-key message)
  local g="$1" r; mk;r=$R; conf "$r" 'item_prefix=A=B\n'; git -C "$r" commit -q -m conf; stage "$r" "$A"
  waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046)\n"; echo "CONFSPLIT=$(run "$r" "$g")/$(cnt "item_prefix='A=B'")/$(cnt 'unknown') "; }
g11_ITEMCASE() { # the tracked-item regex is case-sensitive: con-046 refused (1), CON-046 honoured (0)
  local g="$1" r o=""; mk;r=$R; stage "$r" "$A"
  for v in con-046 Con-046 CON-046; do waive "$r" "$(wf sub "$B" "$A" ops "$d10" "$v")\n"; o+="$(run "$r" "$g"),"; done
  echo "ITEMCASE=$o "; }
g11_SEPINJECT() { # the internal separators \036 / \037 and the 4-variable read: a row whose authoriser field carries
  # \037-separated copies of valid expiry, item and base values must NOT supply them (the last variable keeps the rest,
  # so the base never matches: 1); the sibling form for the spent site: a sibling whose row path field carries the
  # injected text spends nothing (0)
  local g="$1" r x o; mk;r=$R; stage "$r" "$A"; x=$(git -C "$r" rev-parse HEAD)
  waive "$r" "$(printf 'sub\t%s\t%s\tops\037%s\037CON-046\037%s\tz\tz\tz' "$B" "$A" "$d10" "$x")\n"; o="$(run "$r" "$g")/$(cnt 'bound to base')"
  echo "SEPINJECT=$o "; }
g11_CRMID() { # the CR site `*$'\r'*` catches a CR anywhere in the row, not only at the end (rc / CR message count)
  local g="$1" r; mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" $'CON-0\r46')\n"; echo "CRMID=$(run "$r" "$g")/$(cnt 'CR (CRLF') "; }
g11_TSVSPACE() { # the field separator is TAB only: a row whose fields are separated by spaces is one field (not
  # waived, 1); a same-parent sibling with that row spends nothing (0)
  local g="$1" r x; mk;r=$R; stage "$r" "$A"; x=$(git -C "$r" rev-parse HEAD)
  waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046 | tr '\t' ' ')\n"; local o="$(run "$r" "$g"),"
  waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046)\n"; ysib "$r" "$x" "$(wf sub "$B" "$A" ops "$d10" CON-046 "$x" | tr '\t' ' ')\n"
  o+="$(run "$r" "$g")"; git -C "$r" update-ref -d refs/heads/y; echo "TSVSPACE=$o "; }
g11_HASHMID() { # the comment test `$1!~/^#/` is anchored: a gitlink path with a # inside (a#b) is waivable (0)
  local g="$1" r; SUBN='a#b'; mk;r=$R; stage "$r" "$A" 'a#b'; waive "$r" "$(wf 'a#b' "$B" "$A" ops "$d10" CON-046)\n"
  echo "HASHMID=$(run "$r" "$g") "; SUBN=sub; }
g11_PATHWS() { # the -z diff reader keeps a path verbatim (IFS= read -d ''): a gitlink at " s" or "s " is judged at
  # that path (downgrade: FAIL 1, never BLIND for a stripped path)
  local g="$1" r o="" v; for v in ' s' 's '; do SUBN="$v"; mk;r=$R; stage "$r" "$A" "$v"; o+="$(run "$r" "$g"),"; done; SUBN=sub
  echo "PATHWS=$o "; }
g11_SYMNEAR() { # the symlink check `subp != root/path` is an exact string compare: a checkout path that is a symlink
  # to a sibling whose name EXTENDS the path (subx) or differs in case (SUB) is still a symlink (BLIND 2 / message 1)
  local g="$1" r o="" t
  for t in subx SUB; do mk;r=$R; git clone -q "$r/sub" "$r/$t" 2>/dev/null; rm -rf "${r:?}/sub"; ln -s "$r/$t" "$r/sub"; stage "$r" "$A"
    o+="$(run "$r" "$g")/$(cnt 'checkout path is a symlink'),"; done
  echo "SYMNEAR=$o "; }
g11_NULROW() { # F3: a NUL byte in waiver data is never dropped silently. (a) the index waiver file, a NUL inside the
  # path field (bash would read "sub"); (b) the same through --waivers; (c) a same-parent sibling whose waiver file holds
  # the exact row plus a NUL (the row cannot be proven unspent); (d) a base config with a NUL inside a valid line
  # (waivers disabled). Each: rc / NUL message count; needle (e): the same row without the NUL is honoured (0)
  local g="$1" r x o=""; mk;r=$R; stage "$r" "$A"; x=$(git -C "$r" rev-parse HEAD)
  printf 'su\0b\t%s\t%s\tops\t%s\tCON-046\t%s\n' "$B" "$A" "$d10" "$x" >"$r/.submodule_pin_waivers"; git -C "$r" add .submodule_pin_waivers
  o+="$(run "$r" "$g")/$(cnt 'NUL byte'),"
  cp "$r/.submodule_pin_waivers" "$tmp/nulw"; o+="$(run "$r" "$g" -- --waivers "$tmp/nulw")/$(cnt 'NUL byte'),"
  waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046)\n"; ysib "$r" "$x" "$(wf sub "$B" "$A" ops "$d10" CON-046 "$x")\\0\n"
  o+="$(run "$r" "$g")/$(cnt 'NUL byte'),"; git -C "$r" update-ref -d refs/heads/y
  mk;r=$R; { printf 'max_waiver_days=6'; printf '\0'; printf '0\n'; } >"$r/.submodule_pin_gate.conf"; git -C "$r" add .submodule_pin_gate.conf; git -C "$r" commit -q -m conf
  stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046)\n"; o+="$(run "$r" "$g")/$(cnt 'NUL byte'),"
  mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046)\n"; o+="$(run "$r" "$g")"
  echo "NULROW=$o "; }
g11_DOWN2() { # F6: the incident shape, a downgrade by MORE than one commit (C -> A over B): FAIL with the ANCESTOR text
  local g="$1" r c; mk;r=$R; git -C "$r/sub" checkout -q "$B"; git -C "$r/sub" commit -q --allow-empty -m C; c=$(git -C "$r/sub" rev-parse HEAD)
  git -C "$r" update-index --cacheinfo 160000,"$c",sub; git -C "$r" commit -q -m pc; stage "$r" "$A"
  echo "DOWN2=$(run "$r" "$g")/$(cnt 'ANCESTOR') "; }
g11_IDDELIM() { # the idname / idmail splits (` <`, `<`, `>`) have no constructible near miss: git removes < and > from
  # a name and an email itself (needle: an identity given with both still has exactly one < and one >)
  local id; id="$(GIT_COMMITTER_NAME='a <b>' GIT_COMMITTER_EMAIL='x<y>z@w' git var GIT_COMMITTER_IDENT 2>/dev/null)"
  echo "IDDELIM=$(tr -cd '<' <<<"$id" | wc -c)/$(tr -cd '>' <<<"$id" | wc -c) "; }
s11keys=(); while IFS=$'\t' read -r sid _ _ _ scls sgen _; do case "$sid" in ''|'#'*) continue ;; esac
  case "$scls" in sha|path|ident|date|num|text|charset) ;; *) continue ;; esac
  IFS=',' read -ra sk <<<"$sgen"; for k in "${sk[@]}"; do [ "$(type -t "g11_$k")" = function ] && s11keys+=("$k"); done
done <"$s11tab"
mapfile -t s11keys < <(printf '%s\n' "${s11keys[@]}" | LC_ALL=C sort -u)
for f in $(compgen -A function g11_); do printf '%s\n' "${s11keys[@]}" | grep -qx "${f#g11_}" || { echo "META: generator $f is named by no site-table row" >&2; exit 2; }; done
[ "${#s11keys[@]}" -ge 20 ] || { echo "META: the site table names ${#s11keys[@]} generators (expected 20 or more; table unread?)" >&2; exit 2; }
members11() { local g="$1" k o=""; for k in "${s11keys[@]}"; do o+="$("g11_$k" "$g")"; done; echo "$o"; }
want="DOWN=1 NOCHANGE=0 DIVERGED=0/1 FORWARD=0 WAIVED=0 EXPIRED=1 NOTRACK=1 BLIND=2 UNRELATED=0 WRONGSHA=1 OLDBIND=1 NEWOBJ=2/1 NOAUTH=1 TWOSUB=1 TODAY=0 MIXED=1 BADEXP=1,1,1,1,1,1,1, HORIZON=0,1 CONF=0,1 BADCONF=1,0 PREFIX=0,1,1 BADITEM=1 SELFAUTH=1,1 AUTHNORM=1,1,1,1,1,1,1,1,0 IDENT=1 UNTRACKED=1 PERSIST=0,1 AMEND=0,0,1,2 IGNSUB=1,1 RENAME=1 FIELDS8=1 FIELDS6=1 DUPROW=0 CRLF=1/1 UNREAD=2 RELATIVE=1 WT=0,1 SHALLOW=2 MISSINGMID=2 SHFWD=0,1 REPLACE=1 SYMSUB=2/1 HELP=2 NONASCII=0 SYMROOT=0 KCONF=1,1,1,1 NOTOWN=2/1 LAZY=2/true/absent GRAFT=1 NUMPATH=1 PYFAIL=1/1/0 CHILDTREE=1/1 BADREF=1/1 SIBOTHER=0 ARGS=2,2,2,2,2,2/1,2/0,2/1 LEV=2/1 UNBORN=0/1 BASEBAD=2/1,2/1 CONFCOMMENT=0 CONFNOKV=1/1 CONFZERO=1 CONFUNK=1/1 WFILE=0 NODATA=1/1 AUTHCTRL=1 AUTHUTF8=1/1 NOPY=1/1 EMPTYAUTH=1/1 ITEMFORM=1,1 WCOMMENT=1 SPENTNUM=0 NEWGL=0 DELGL=0 COUNT=0/1 SUBGONE=2/1 NEWTREE=2/1/0 OLDOBJ=2/1,2/1 LEGIT=0/A SNAP=0,1/B AMENDSNAP=1/B AMENDMSG=0,0,0 REDO=0/A MERGECONF=0,1/B SQUASHMOVED=1/B SQUASHSAME=1/B/1 NOCOMMITMOVED=1/B NOCOMMITSAME=1/B NOCOMMITDEL=1/B/1 SQGRAFT=1/B/1 CHERRY=0,1 CHERRYSAME=0,1/distinct REBASE=0,1 LEFTSAME=0/A LEFTOLD=1/B/1 BASEFORM=1,1/B K8TAG=1/B K14WT=1/B K9REPL=1/B K11PATH=0/A K12OLD=0/A K13TELL=1/B K10LAZY=1/absent/absent/1 TREEMISS=1/B/missing/1 SHALLOWSUP=1/B/true/1 STASH=0/A/kept N4INDEX=0,1 RESETSQ=0,0,0/A KNM1=1,1 KNM1GM=1,0 KNM2=1/1,0 KNM3=1/B,1/B, KNM4=0/A,1/B KNM5=1/B,1/B, KNM6=0,1 KNM9=0/A KIDPARENT=0/A A1WTREF=0/A/vis0,0/A/vis0,1/B/vis1, A2STASHANC=0,0/A/vis0 A3TEXTCONV=0/1,1,1 KV365=0/A KV12ZWSP=1/B KV13SHARPS=1/B KVREFS=1/B,1/B,1/B, KV17ORDER=1/B/yfirst KV18HASHMID=0 KV19STALEFIRST=0/A KV20BADEXPFIRST=0/A KV22SUBUNKNOWN=2/1,0/1 KV29PLANT=1/1 KV29B=1/1,1/1 KV02HELP=0 KV35=1/1 SITECR=0/A SITEEXP=0/A SITEHOR=0/A SITEITEM=0/A SITESELF=0/A SITEUTF8=0/A AUTHLTGT=1/B,1/B PREFIXFORM=1/B,1/B,1/B, DAYS100=0/A,1/B ROOTDEFAULT=1/1 MSGNOROW=1/1 HOOKSKIP=0/1 HOOKNOREPO=1 S_PARAMSFWD=0/0 S_PARAMSDOWN=1/0 S_COUNTFWD=0/0 S_COUNTDOWN=1/0 S_NONEFWD=2/0 S_NONEDOWN=2/0 D_DOWNKILLBACK=2/0/0/1 D_FWDKILLFWD=2/0/0/1 D_CTL=1/1/0/0 F_ITEM4=0/1 F_ITEM3=0/1 F_SELFTRAIL=1/0 F_SELFLEAD=1/0 F_HELPLONG=0/135 F_HELPSHORT=0/135 G_DOWNGRADE=2/0/0/1[mb:1/err1] G_CTL=1/1/0/0[mb:0/err0] G_NOGRAPH=2/0/0/1[mb:128/err1] ARGSFWD=2,2 SYMSUBFWD=2/1 MAXD=0,1/1,1/1 PFXDIGIT=0 ITEMJUNK=1/1 IDENTONE=1/1,1/1 ROOTNEST=1/1 SUBBROKEN=2/1/0 ZSID=1/1,1/1/17/0 ZSAUTH=1/0/34/0 YEAR5=1/1 EXPBND=1/1,0/0, HORBND=0,1,0,1,0,1, DAYSBND=1/1,0/0,0/0,0/0,0/0,1/1,1/1,1/1, PFXBND=1/1,0 ITEMBND=1,0,0, LEVBND=1/1 WSID=1/1,1/1/29/0 WSAUTH=1/0/54/0 CONFWS=1,1,0, SHANEAR=1111111/1111111/1111111/0 SPENTNEAR=0000000/0000000/0000000/1/1 ARGNEAR=00000/22222222222222 CONFHASH=0,1,1, CONFKEYNEAR=0/11111/0/111 CONFSPLIT=1/1/0 CRMID=1/1 DOWN2=1/1 DUPNEAR=1/1/0 HASHMID=0 IDDELIM=1/1 ITEMCASE=1,1,0, NULROW=1/1,1/1,1/1,1/1,0 PATHNEAR=0/111111111 PATHWS=1,1, SEPINJECT=1/1 SPENTFIELDS=0,0,1 SPENTPATHNEAR=000000000/1 SYMNEAR=2/1,2/1, TSVSPACE=1,0 TZPAIR=0,1,1,0/+1400/-1200 WSID4=11111111/8/19/0 "
# ── the inventory lint (round 7, CON-146): the guard inventory is checked, not trusted. static (Part 1): L1 every anchor
# occurs exactly once in the gate's code; L2 every code line that is not pure syntax is covered by an anchor; L3 every
# line has at least as many rows as members (1 + the && / || joins of a shell line, 1 + the `or` / `and` joins of a
# python line; double-quoted text and trailing comments do not count); L4 every named mutant / proof is registered in
# this file; L5 every registered mutant / proof is named by a row; L6 need is in {both fo fr ch none}, `none` needs a
# proof. Control needles (§11.4.201(7)(b)): the member count is printed for three known lines (diverged elif = 3, python
# form line = 5, base-binding line = 2) and for two fabricated lines (`a && b || c` = 3, `x "a && b"` = 1); a wrong
# needle fails the lint, so a blind counter cannot pass. dynamic (after Part 2): the fail directions each row's mutants
# showed (vdir) cover its need, and every proof named by a row passed. The lint is a FLOOR, not a proof of completeness:
# a guard the inventory does not name is invisible to it; the reviewer's own mutants stay required (§11.4.194(6)(d)).
inv="$here/cm_submodule_pin_not_downgraded_inventory.tsv"
lint() { # static | dynamic <dirs.tsv> <eqok>
  python3 -I - "$1" "$gate" "$inv" "${BASH_SOURCE[0]:-$0}" "${2:-}" "${3:-}" "$hook" <<'PY'
import re,sys
mode,gate,inv,test,dirs,eqok,hookf=sys.argv[1:8]
G=open(gate,encoding='utf-8').read().split('\n')
s=next(i for i,x in enumerate(G) if x=='set -uo pipefail')
code='\n'.join(G[s:])
STRUCT=re.compile(r'^\s*(esac|esac ;;|done|fi|\}|then|do|else|try:|local [a-z ]+|while \[ \$# -gt 0 \]; do|case "\$\w+" in|def main\(\):|\w+\(\) \{ #.*)\s*$')
def floor(x,py):
    if py: return 1+len(re.findall(r' or | and ',x))
    y=re.sub(r'"(?:[^"\\]|\\.)*"','""',x); y=re.sub(r'\s#\s[^\'"]*$','',y)
    return 1+len(re.findall(r'&&|\|\|',y))
lines=[]; py=False
for i in range(s,len(G)):
    x=G[i]
    if x.startswith("IDPY='"): lines.append((i,x,False)); py=True; continue
    if not x.strip() or x.lstrip().startswith('#'): continue
    lines.append((i,x,py))
    if py and x.startswith('sys.exit'): py=False
H=open(hookf,encoding='utf-8').read().split('\n')
hcode='\n'.join(H); hlines=[(i,x,False) for i,x in enumerate(H) if x.strip() and not x.lstrip().startswith('#')]
rows=[]
for ln in open(inv,encoding='utf-8'):
    ln=ln.rstrip('\n')
    if not ln or ln.startswith('#'): continue
    f=ln.split('\t'); rows.append(f)
T=open(test,encoding='utf-8').read()
reg=set(re.findall(r'^  (?:mutant|mutf|hkmutf|eqp) ([^ \n]+)',T,re.M))
eqreg=set(re.findall(r'^  eqp ([^ \n]+)',T,re.M))
bad=[]
need_ok={'both','fo','fr','ch','none'}
start={}; cov=set(); hstart={}; hcov=set()
for f in rows:
    if len(f)!=6: bad.append(f'L0 row {f[0]} has {len(f)} fields'); continue
    rid,anc,mut,eq,need,why=f; a=anc.replace('<NL>','\n')
    txt,base,st,cv=(hcode,0,hstart,hcov) if rid.startswith('H') else (code,s,start,cov)
    c=txt.count(a)
    if c!=1: bad.append(f'L1 {rid}: anchor occurs {c} times'); continue
    off=base+txt[:txt.index(a)].count('\n'); end=off+a.count('\n')
    st.setdefault(off,[]).append(rid); cv.update(range(off,end+1))
    ms=[m for m in mut.split(',') if m and m!='-']; es=[e for e in eq.split(',') if e and e!='-']
    for m in ms:
        if m not in reg: bad.append(f'L4 {rid}: mutant {m} not registered')
    for e in es:
        if e not in eqreg: bad.append(f'L4 {rid}: proof {e} not registered')
    if need not in need_ok: bad.append(f'L6 {rid}: need {need}')
    if need=='none' and not es: bad.append(f'L6 {rid}: need none without a proof')
    if need!='none' and not ms: bad.append(f'L6 {rid}: need {need} without a mutant')
named=set(m for f in rows if len(f)==6 for m in (f[2].split(',')+f[3].split(',')) if m and m!='-')
for m in sorted(reg-named): bad.append(f'L5 registered but in no row: {m}')
for i,x,py,start,cov,tag in [(i,x,py,start,cov,'gate') for i,x,py in lines]+[(i,x,py,hstart,hcov,'hook') for i,x,py in hlines]:
    if STRUCT.match(x): continue
    if i not in cov: bad.append(f'L2 {tag} line {i+1} not covered: {x.strip()[:70]}')
    k=len(start.get(i,[])); fl=floor(x,py)
    if i in cov and k<fl and i in start: bad.append(f'L3 {tag} line {i+1}: {k} rows < {fl} members: {x.strip()[:70]}')
    elif i in cov and i not in start and fl>1: bad.append(f'L3 {tag} line {i+1}: {fl} members, covered only by a multi-line anchor')
def needle(pat,py,want):
    hit=[x for i,x,p in lines if pat in x]
    v=floor(hit[0],py) if len(hit)==1 else -1
    if v!=want: bad.append(f'NEEDLE {pat!r}: {v} != {want}')
    return v
nv=[needle('elif [ "$fwd" = 1 ] && [ "$back" = 1 ]',False,3), needle('if not a or a!=a.strip()',True,5), needle('[ "$bs" = "$basec" ] ||',False,2)]
fa=floor('a && b || c',False); fb=floor('x "a && b"',False)
if (fa,fb)!=(3,1): bad.append(f'NEEDLE fabricated {fa},{fb} != 3,1')
if mode=='dynamic':
    D={}
    try:
        for ln in open(dirs): n,_,d=ln.rstrip('\n').partition('\t'); D[n]=set(d.split(','))-{'-'}
    except OSError: D={}
    if not D: bad.append('DYN BLIND: no mutant directions recorded')
    ok=set(open(eqok).read().split()) if eqok else set()
    for rid,anc,mut,eq,need,why in [f for f in rows if len(f)==6]:
        got=set().union(*[D.get(m,set()) for m in mut.split(',') if m and m!='-']) if mut!='-' else set()
        wantd={'both':{'fo','fr'},'fo':{'fo'},'fr':{'fr'},'ch':set(),'none':set()}[need]
        if need=='ch' and not got: bad.append(f'DYN {rid}: no mutant changed the vector')
        if not wantd<=got: bad.append(f'DYN {rid}: need {need}, observed {",".join(sorted(got)) or "-"}')
        for e in [e for e in eq.split(',') if e and e!='-']:
            if e not in ok: bad.append(f'DYN {rid}: proof {e} did not pass')
print(f'lint {mode}: rows {len(rows)}, code lines {len(lines)}, registered {len(reg)}, needles {nv}+({fa},{fb}), findings {len(bad)}')
for b in bad: print('BAD  lint '+b)
sys.exit(1 if bad else 0)
PY
}
want="${want% }"
altclassify() { PATH="$altp" classify "$@"; }
for _ in 1 2; do rsafe classify "$gate"; gotf="$RS"; [ "$(jv "$gotf" "$gotf")" != inconclusive ] && break; done # crossed midnight, or a resource failure: once more
got="$(vec "$gotf")"; echo "gate vector: $got"; echo "gate vector date: $(stamp "$gotf")"
[ "$(jv "$gotf" "$gotf")" = inconclusive ] && { echo "BAD  the real gate's vector crossed midnight or met a resource failure on every try"; bad=1; }
[ "$got" = "$want" ] || { echo "BAD  classification:"; echo "  want [$want]"; echo "  got  [$got]"; bad=1; }
if [ -n "$altd" ]; then # round 9 (F2/F3): the real gate's whole vector under the alternative date must equal want too
  for _ in 1 2; do rsafe altclassify "$gate"; gotaf="$RS"; [ "$(jv "$gotaf" "$gotaf")" != inconclusive ] && break; done
  [ "$(jv "$gotaf" "$gotaf")" = inconclusive ] && { echo "BAD  the real gate's vector under the alternative date crossed midnight or met a resource failure on every try"; bad=1; }
  gota="$(vec "$gotaf")"; echo "gate vector date under the alternative date: $(stamp "$gotaf")"
  if [ "$gota" = "$want" ]; then echo "ok   gate vector under the alternative date ($altd) equals want"
  else echo "BAD  classification under the alternative date ($altd):"; echo "  want [$want]"; echo "  got  [$gota]"; bad=1; fi
fi
if [ -z "${GATE_UNDER_TEST:-}" ]; then
  lint static || bad=1
  # control needle for the lint's own zero: an inventory with the 2nd member row of a 3-member line removed (I141b) and
  # one anchor made ambiguous must be refused with an L3 finding, an L5 orphan (deleted-gitlink-judged) and an L1 finding
  realinv="$inv"; inv="$tmp/inv.bad"; grep -v $'^I141b\t' "$realinv" | sed $'s/^I016\t[^\t]*/I016\texit 2/' >"$inv"
  lo="$(lint static 2>&1)"; lrc=$?; inv="$realinv"
  if [ "$lrc" = 1 ] && grep -q 'L3 gate line' <<<"$lo" && grep -q 'L5 registered but in no row: deleted-gitlink-judged' <<<"$lo" && grep -q 'L1 I016' <<<"$lo"; then
    echo "ok   lint control needle: a broken inventory is refused (L1, L3, L5)"
  else echo "BAD  lint control needle: broken inventory not refused (rc $lrc)"; echo "$lo" | head -5; bad=1; fi
  # ── round 11: the SITE lint (cm_submodule_pin_not_downgraded_sites.py; the census and the table rules are in its
  # header). Static: every exact-compare / character-set site of the gate and the hook has a row, every data row names a
  # fixture key of want and a registered mutant. Control needles for its zero (§11.4.201(7)(b)): (1) a gate copy with
  # one added compare line, (2) the table with its first path-compare row removed, (3) the table with one data
  # row's fixture keys emptied: each must be refused with its own finding (S1, S1, S3)
  s11lint() { python3 -I "$s11py" lint "$1" "${s11g:-$gate}" "$hook" "${s11t:-$s11tab}" "${BASH_SOURCE[0]:-$0}" "$inv" "${@:2}"; }
  s11lint static || bad=1
  awk '{print} /^ *\[ "\$bs" = "\$basec" \] \|\|/{print "    [ \"$bs\" = \"$basec\" ] || :"}' "$gate" >"$tmp/s11g.sh"
  awk -F'\t' -v OFS='\t' '$5=="path" && $3=="$1\"\"==p\"\"" && !d {d=1; next} {print}' "$s11tab" >"$tmp/s11t1.tsv"
  awk -F'\t' -v OFS='\t' '$5=="sha" && !d {$6="-"; d=1} {print}' "$s11tab" >"$tmp/s11t2.tsv"
  so1="$(s11g="$tmp/s11g.sh" s11lint static 2>&1)"; sr1=$?; so2="$(s11t="$tmp/s11t1.tsv" s11lint static 2>&1)"; sr2=$?; so3="$(s11t="$tmp/s11t2.tsv" s11lint static 2>&1)"; sr3=$?
  if [ "$sr1" = 1 ] && grep -q 'BAD  site lint S1 gate line' <<<"$so1" && [ "$sr2" = 1 ] && grep -q "BAD  site lint S1 gate line .* token '\$1\"\"==p\"\"'" <<<"$so2" \
      && [ "$sr3" = 1 ] && grep -q 'BAD  site lint S3 S[0-9]*: data row without a fixture key' <<<"$so3"; then
    echo "ok   site lint control needles: an added compare, a removed row and an emptied data row are refused (S1, S1, S3)"
  else echo "BAD  site lint control needles: rc $sr1/$sr2/$sr3"; printf '%s\n' "$so1" "$so2" "$so3" | grep BAD | head -5; bad=1; fi
fi
vdir() { # real-vector mutant-vector -> fail directions observed: fo (a refusal became exit 0), fr (an exit 0 became a
  # refusal), ch (another change, including a changed count or message field with the same exit code); per token
  # KEY=v1,v2/... the first '/'-field of each ','-item is the exit code
  python3 -I -c '
import sys
def items(v):
    d={}
    for tok in v.split():
        k,_,val=tok.partition("=")
        d[k]=val.split(",")
    return d
a,b=items(sys.argv[1]),items(sys.argv[2]); s=set()
for k in set(a)|set(b):
    x,y=a.get(k),b.get(k)
    if x==y: continue
    if x is None or y is None or len(x)!=len(y) or k=="HELP": s.add("ch"); continue
    for P,Q in zip(x,y):
        if P==Q: continue
        p,q=P.split("/")[0],Q.split("/")[0]
        if p==q: s.add("ch"); continue   # same exit code, another count / message field (round 8, R7-8)
        if p.isdigit() and q.isdigit():
            s.add("fo" if q=="0" and p!="0" else "fr" if p=="0" and q!="0" else "ch")
        else: s.add("ch")
print(",".join(sorted(s)) or "-")' "$1" "$2"; }
# ── Part 2: mutants (skipped under GATE_UNDER_TEST: the seds target the current gate text) ──
# Each mutant is classified in a background job with its own temp dir; MUT_JOBS jobs at a time (bounded, §12.8).
n=0; mj="${MUT_JOBS:-3}"; [[ "$mj" =~ ^[1-9][0-9]?$ ]] || { echo "META: MUT_JOBS must be 1..99" >&2; exit 2; }; mnames=()
mutant() { # name sed-expr
  if [ -n "${MUT_ONLY:-}" ] && ! [[ "$1" =~ $MUT_ONLY ]]; then return; fi
  local m="$tmp/m$((++n)).sh"; sed "$2" "$gate" >"$m"; mnames[n]="$1"
  if cmp -s "$m" "$gate"; then echo "BAD  mutant $1 did not change the gate"; bad=1; mnames[n]=""; return; fi
  launch "$n"
}
launch() { # k: classify job k in the background; its kind picks the subject. Only j<k>.res is kept: the job's fixture
  # tree is deleted as soon as the result is written (R7-9: one full run kept about 22 GiB before)
  local k="$1" o="$tmp"
  ( tmp="$o/j$k"; mkdir -p "$tmp"; local e0; e0="$(cgev)"
    case "${mkind[k]:-}" in
      hook) hook="$o/h$k"; classify "$gate" ;;
      dateskew) PATH="$o/skew:$PATH"; classify "$gate" ;;
      resfault) PATH="$o/resfk:$PATH" RESFK_DIR="$tmp" classify "$gate" ;;
      *) classify "$o/m$k.sh" ;;
    esac >"$tmp.res" 2>"$tmp.err"; resclean "$tmp.res" "$tmp.err" "$e0"; rm -f "$tmp.err"
    chmod -R u+rwx "$tmp" 2>/dev/null; rm -rf "${tmp:?}"
    # round 9 (F2): an equivalence claim must hold under the alternative date as well: a second classify, own temp dir
    case "${mkind[k]:-}" in eq|geneq) if [ -n "$altd" ]; then tmp="$o/j$k.a"; mkdir -p "$tmp"; e0="$(cgev)"
        PATH="$o/dpin/alt:$PATH" classify "$o/m$k.sh" >"$o/j$k.alt.res" 2>"$tmp.err"; resclean "$o/j$k.alt.res" "$tmp.err" "$e0"; rm -f "$tmp.err"
        chmod -R u+rwx "$tmp" 2>/dev/null; rm -rf "${tmp:?}"; fi ;; esac ) &
  while [ "$(jobs -rp | wc -l)" -ge "$mj" ]; do wait -n; done
}
mutpath() { # name file: a generated member mutant (the whole mutated gate is written by the generator)
  if [ -n "${MUT_ONLY:-}" ] && ! [[ "$1" =~ $MUT_ONLY ]]; then return; fi
  local m="$tmp/m$((++n)).sh" pf; cp "$2" "$m"; mnames[n]="$1"; mkind[n]=gen
  pf="$(awk -F'\t' -v k="$1" '$1==k {print $2}' "$here/cm_submodule_pin_not_downgraded_members_eq.tsv")"
  [ -n "$pf" ] && { mkind[n]=geneq; geneqp[n]="$pf"; }
  if cmp -s "$m" "$gate"; then echo "BAD  generated mutant $1 did not change the gate"; bad=1; mnames[n]=""; return; fi
  launch "$n"
}
mkind=(); eqk=(); geneqp=()
mutf() { mutant "$1" "$(cat)"; } # name; sed script on stdin (here-doc keeps reviewer text byte for byte)
hkmutf() { # name; sed script on stdin, applied to the HOOK; classify runs with the mutated hook
  local s; s="$(cat)"; if [ -n "${MUT_ONLY:-}" ] && ! [[ "$1" =~ $MUT_ONLY ]]; then return; fi
  local mh="$tmp/h$((++n))"; sed "$s" "$hook" >"$mh"; chmod +x "$mh"; mnames[n]="$1"; mkind[n]=hook
  if cmp -s "$mh" "$hook"; then echo "BAD  mutant $1 did not change the hook"; bad=1; mnames[n]=""; return; fi
  launch "$n"
}
eqn=0; eqnames=(); eqprobe=(); eqfile=(); eqctl=()
eqp() { # name probe-fn ; stdin: eq-sed, a line `--`, control-sed
  if [ -n "${MUT_ONLY:-}" ] && ! [[ "$1" =~ $MUT_ONLY ]]; then cat >/dev/null; return; fi
  local all es cs m c; all="$(cat)"; es="${all%%$'\n'--$'\n'*}"; cs="${all#*$'\n'--$'\n'}"
  m="$tmp/m$((++n)).sh"; c="$tmp/c$n.sh"; sed "$es" "$gate" >"$m"; sed "$cs" "$gate" >"$c"
  mnames[n]="$1"; mkind[n]=eq; eqnames[++eqn]="$1"; eqprobe[eqn]="$2"; eqfile[eqn]="$m"; eqctl[eqn]="$c"; eqk[eqn]=$n
  if cmp -s "$m" "$gate" || cmp -s "$c" "$gate" || cmp -s "$m" "$c"; then echo "BAD  eqproof $1: a sed did not change the gate"; bad=1; mnames[n]=""; return; fi
  launch "$n"
}
# probes: <gate> -> one line; each builds its own fixtures with mk/run (cheap, run after the mutant jobs)
pr_checkout_shapes() { local g="$1" x="" s; for s in absent file mode000 emptydir; do mk;r=$R; stage "$r" "$A"; rm -rf "${r:?}/sub"
    case $s in file) echo x >"$r/sub" ;; mode000) mkdir "$r/sub"; chmod 000 "$r/sub" ;; emptydir) mkdir "$r/sub" ;; esac
    x+="$s:$(run "$r" "$g")/$(cnt 'submodule checkout missing'),"; [ "$s" = mode000 ] && chmod 755 "$r/sub"; done; echo "$x"; }
pr_sibling() { local g="$1" x="" p; for s in nowaiver otherrow; do mk;r=$R; p=$(git -C "$r" rev-parse HEAD); git -C "$r" checkout -q -b Y
    if [ $s = otherrow ]; then wf sub "$B" "$S" ops "$d10" CON-046 "$p" >"$r/.submodule_pin_waivers"; else echo y >"$r/y"; fi
    git -C "$r" add -A; git -C "$r" commit -q -m y; git -C "$r" checkout -q main; rm -f "$r/.submodule_pin_waivers" "$r/y"
    stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046 "$p")\n"; x+="$s:$(run "$r" "$g"),"; done; echo "$x"; }
pr_conf() { local g="$1" x=""; mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046)\n"; x+="absent:$(run "$r" "$g"),"
  mk;r=$R; conf "$r" 'item_prefix=CAT\n'; git -C "$r" commit -q -m c; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" CAT-046)\n"; x+="cat:$(run "$r" "$g")"; echo "$x"; }
pr_auth() { local g="$1" x=""; mk;r=$R; stage "$r" "$A"
  waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046)\n"; x+="ok:$(run "$r" "$g"),noemail:$(run "$r" "$g" GIT_COMMITTER_EMAIL= GIT_AUTHOR_EMAIL=),"
  waive "$r" "$(wf sub "$B" "$A" t "$d10" CON-046)\n"; x+="self:$(run "$r" "$g"),"
  waive "$r" "$(wf sub "$B" "$A" $'o\xffps' "$d10" CON-046)\n"; x+="badutf8:$(run "$r" "$g")/$(cnt 'python3 rc 4')"; echo "$x"; }
pr_expiry() { local g="$1" x="" e; mk;r=$R; stage "$r" "$A"
  for e in "$d10" never 9999 "$(date -d '+5 days' +%Y-%-m-%-d)" tomorrow '+5 days' "$(date -d '+5 days' +%Y%m%d)" "$(date -d '+5 days' +%F)T00" \
      "$(date -d '+5 days' +%Y-0%m-%d)" "$(date -d '+5 days' +%Y-%m-0%d)" "$(date -d '+5 days' +%F)x"; do
    waive "$r" "$(wf sub "$B" "$A" ops "$e" CON-046)\n"; x+="$(run "$r" "$g")/$(cnt 'not a real YYYY-MM-DD'),"; done; echo "$x"; }
pr_paths() { local g="$1" x=""; mk;r=$R; stage "$r" "$A"; x+="down:$(run "$r" "$g"),"
  mk;r=$R; printf 'one\ntwo\n' >"$r/f"; git -C "$r" add f; git -C "$r" commit -q -m f; git -C "$r" mv f "a b c d"; stage "$r" "$A"; x+="ren:$(run "$r" "$g")/$(cnt 'ANCESTOR'),"
  mk;r=$R; mkdir -p "$r/x y"; echo z >"$r/x y/z"; git -C "$r" add -A; x+="plain:$(run "$r" "$g")/$(grep -o '([0-9]* staged' "$tmp/out")"; echo "$x"; }
pr_unchanged() { local g="$1" x=""; mk;r=$R; stage "$r" "$B"; x+="same:$(run "$r" "$g")/$(grep -o '([0-9]* staged' "$tmp/out"),"
  mk;r=$R; git -C "$r/sub" checkout -q "$A"; x+="wtonly:$(run "$r" "$g")/$(grep -o '([0-9]* staged' "$tmp/out"),"
  mk;r=$R; stage "$r" "$A"; x+="down:$(run "$r" "$g"),"
  # round 8 needle: only the OLD mode is a gitlink (gitlink -> file) or only the NEW one (file -> gitlink); the real gate
  # skips both, a gate that checks one mode only reads a blob as a pin (BLIND)
  mk;r=$R; git -C "$r" rm -q --cached sub; echo x >"$r/sub.f"; git -C "$r" add sub.f; git -C "$r" update-index --add --cacheinfo 100644,"$(git -C "$r" hash-object -w "$r/sub.f")",sub
  x+="gl2f:$(run "$r" "$g")/$(grep -o '([0-9]* staged' "$tmp/out"),"
  mk;r=$R; echo x >"$r/f2"; git -C "$r" add f2; git -C "$r" commit -q -m f2; git -C "$r" update-index --cacheinfo 160000,"$B",f2
  x+="f2gl:$(run "$r" "$g")/$(grep -o '([0-9]* staged' "$tmp/out")"; echo "$x"; }
pr_needargc() { local g="$1" x="" f; mk;r=$R; git -C "$r/sub" checkout -q "$B"; git -C "$r/sub" commit -q --allow-empty -m F
  f=$(git -C "$r/sub" rev-parse HEAD); stage "$r" "$f"
  x+="last:$(run "$r" "$g" -- --base),empty:$(run "$r" "$g" -- --base ''),lastw:$(run "$r" "$g" -- --waivers),emptyw:$(run "$r" "$g" -- --waivers '')"; echo "$x"; }
pr_maxdays() { local g="$1" x="" v; for v in 999 1000 365; do mk;r=$R; conf "$r" "max_waiver_days=$v\n"; git -C "$r" commit -q -m conf; stage "$r" "$A"
    waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046)\n"; x+="$v:$(run "$r" "$g"),"; done; echo "$x"; }
pr_identpad() { local g="$1" x=""; mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046)\n"
  x+="padname:$(run "$r" "$g" GIT_COMMITTER_NAME='  ops ' GIT_AUTHOR_NAME=$' ops\t')/$(cnt 'self-waive\|authoriser'),"
  x+="zsname:$(run "$r" "$g" GIT_COMMITTER_NAME="${zscat}ops$zscat" GIT_AUTHOR_NAME="ops${zsl[1]}")/$(cnt 'self-waive\|authoriser'),"
  waive "$r" "$(wf sub "$B" "$A" t@t "$d10" CON-046)\n"; x+="padmail:$(run "$r" "$g" GIT_COMMITTER_EMAIL=' t@t ')"; echo "$x"; }
pr_merge() { local g="$1" x=""; mk;r=$R; stage "$r" "$A"; git -C "$r" rev-parse HEAD >"$r/.git/MERGE_HEAD"
  waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046)\n$(wf sub "$B" "$A" ops2 "$d10" CON-047)\n"; x+="merge:$(run "$r" "$g")/$(cnt 'merge is in progress')"; echo "$x"; }
pr_ident() { local g="$1" x=""; mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046)\n$(wf sub "$B" "$A" ops2 "$d10" CON-047)\n"
  git -C "$r" config user.useConfigOnly true
  x+="ident:$(run "$r" "$g" -u GIT_COMMITTER_NAME -u GIT_COMMITTER_EMAIL -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL)/$(cnt 'identity unresolvable')"; echo "$x"; }
pr_nopy() { local g="$1" x=""; mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046)\n$(wf sub "$B" "$A" ops2 "$d10" CON-047)\n"
  mknopy; x+="nopy:$(run "$r" "$g" PATH="$tmp/nopy")/$(cnt 'python3 missing')"; echo "$x"; }
pr_spent() { local g="$1" x="" p; mk;r=$R; p=$(git -C "$r" rev-parse HEAD); git -C "$r" checkout -q -b Y
  wf sub "$B" "$A" ops "$d10" CON-046 "$p" >"$r/.submodule_pin_waivers"; git -C "$r" add -A; git -C "$r" commit -q -m y; git -C "$r" checkout -q main; rm -f "$r/.submodule_pin_waivers"
  stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046 "$p")\n$(wf sub "$B" "$A" ops2 "$d10" CON-047 "$p")\n"; x+="spent:$(run "$r" "$g")/$(cnt 'already spent')"; echo "$x"; }
pr_cannottell() { local g="$1" x=""; mk;r=$R; stage "$r" "$A"; waive "$r" "$(wf sub "$B" "$A" ops "$d10" CON-046)\n$(wf sub "$B" "$A" ops2 "$d10" CON-047)\n"
  printf '%s\n' 1111111111111111111111111111111111111111 >"$r/.git/refs/heads/broken"; x+="badref:$(run "$r" "$g")/$(cnt 'cannot prove the row is unspent')"; echo "$x"; }
if [ -z "${GATE_UNDER_TEST:-}" ]; then
  # decision table
  mutant downgrade-never-detected 's/ 2>\/dev\/null; back=\$?/ 2>\/dev\/null; back=1/'
  mutant always-ancestor 's/ 2>\/dev\/null; back=\$?/ 2>\/dev\/null; back=0/'
  mutant forward-not-checked-first 's/ 2>\/dev\/null; fwd=\$?/ 2>\/dev\/null; fwd=1/'
  mutant shallow-unchecked 's/ \&\& \[ "\$shallow" = false \]//'
  mutant undecided-is-ok 's/^    blindmsg "\$path" "ancestry of.*$/    :/'
  mutant diverged-silent 's/WARN \$path/ok $path/'
  mutant blind-is-pass 's/blind=1; }$/blind=0; }/'
  mutant fail-is-pass 's/^\[ "\$fail" = 1 \] \&\& exit 1/[ "$fail" = 1 ] \&\& exit 0/'
  mutant blind-outranks-fail 's/^\[ "\$fail" = 1 \] \&\& exit 1$/[ "$blind" = 1 ] \&\& exit 2/'
  mutant presence-checks-removed '/cat-file -e/{N;d}'
  mutant hook-env-inherited 's/^sg() { env .*git -c core.commitGraph=false "\$@"; }/sg() { git -c core.commitGraph=false "$@"; }/'
  mutant commit-graph-honoured '/^sg() /s/ -c core.commitGraph=false//'
  mutant replace-refs-honoured '/^sg() /s/ GIT_NO_REPLACE_OBJECTS=1//'
  mutant R3m1-grafts-honoured '/^sg() /s/ GIT_GRAFT_FILE=\/dev\/null//'
  mutant RV7-lazy-fetch '/^sg() /s/ GIT_NO_LAZY_FETCH=1//'
  mutant RV6-own-repo-unchecked 's/^    blindmsg "\$path" "path is not its own repository.*$/    :; fi/'
  # reading the index diff (R2-m2, RM2, RM3)
  mutant diff-status-ignored 's/^\[ "\${dstat\[0\]}" = 0 \] || .*$/:/'
  mutant root-not-normalised 's/^root="\$(cd "\$top" \&\& pwd -P)" || .*$/:/'
  mutant RM2-ignore-submodules 's/ --ignore-submodules=none//'
  mutant RM3-renames 's/ --no-renames//'
  mutant no-z-parsing 's/--raw -z/--raw/'
  mutant logical-paths 's/pwd -P/pwd/g'
  mutant base-ignored 's/ --ignore-submodules=none "\$basec"/ --ignore-submodules=none/'
  # waiver lifetime: ONE row = one transition, one commit, one parent (round 4)
  mutant base-unbound '/waiver row is bound to base/d'
  mutant merge-allowed '/a waiver is valid only in a single-parent commit/d'
  mutant spent-unchecked 's/      0) spent "\$1" "\$2" "\$3"; case \$? in/      0) case 1 in/'
  mutant spent-head-counted 's/        \$1""!=h"" {for/        {for/'
  mutant spent-base-ignored 's/ \&\& \$7""==b"" {f=0}/ {f=0}/'
  mutant spent-unreadable-ignored '/(same parent) is unreadable/d'
  mutant spent-history-error-ignored 's/^  \[ "\$kidsrc" = ok \] || .*$/  :/'
  mutant spent-grafts-honoured '/^pg() /s/ GIT_GRAFT_FILE=\/dev\/null//'
  # round-4 reviewer mutants RM8-RM14 (adopted, §11.4.276(D)). RM9-RM13 are the reviewer's seds unchanged; RM8 and RM14
  # target the round-5 text `--exclude=refs/stash --all` (RM14 keeps --single-worktree BEFORE --all, else it is equivalent)
  mutant RM8-scope-branches-only 's/pg rev-list --exclude=refs\/stash --all --parents/pg rev-list --branches --parents/'
  mutant RM9-super-replace-honoured '/^pg() /s/ GIT_NO_REPLACE_OBJECTS=1//'
  mutant RM10-super-lazy-fetch '/^pg() /s/GIT_NO_LAZY_FETCH=1 //'
  mutant RM11-spent-ignores-path 's/^      NF==7 \&\& \$1""==p"" \&\& \$2""==o""/      NF==7 \&\& $2""==o""/'
  mutant RM12-spent-ignores-old 's/^      NF==7 \&\& \$1""==p"" \&\& \$2""==o"" \&\& /      NF==7 \&\& $1""==p"" \&\& /'
  mutant RM13-spent-cannot-tell-is-unspent 's/^           \*) WHY="\$SPENT; cannot prove the row is unspent" ;;/           *) return 0 ;;/'
  mutant RM14-single-worktree 's/pg rev-list --exclude=refs\/stash --all --parents/pg rev-list --exclude=refs\/stash --single-worktree --all --parents/'
  # round-5: missing tree read as absent (M-1), shallow superproject unchecked (M-1), stash counted (M-2), HEAD always
  # excluded from spenders (N-4)
  mutant M1-tree-missing-is-absent '/^  pg cat-file -e "\$1^{tree}" 2>\/dev\/null || return 2$/d'
  mutant M1-shallow-superproject-unchecked 's/^    if \[ "\$(pg rev-parse --is-shallow-repository 2>\/dev\/null)" != false \]; then kidsrc=shallow$/    if false; then :/'
  mutant M2-stash-counted '/^    elif all=/s/ --exclude=refs\/stash//'
  mutant N4-head-always-excluded 's/ 2>\/dev\/null \&\& hx="\$headc"$/; hx="$headc"/'
  # waiver row form
  mutant waiver-ignores-old-sha 's/ \&\& \$2""==o""//'
  mutant waiver-ignores-new-sha 's/ \&\& \$3""==n""//'
  mutant waiver-ignores-path 's/ \&\& \$1""==p""//'
  mutant R3n1-numeric-compare 's/\$1""==p""/$1==p/'
  mutant RM4-extra-fields 's/    NF==7 \&\& \$1!~/    NF>=7 \&\& $1!~/'
  mutant six-field-rows 's/    NF==7 \&\& \$1!~/    NF>=6 \&\& $1!~/'
  mutant RM5-first-bad-row-aborts 's/3) WHY="\(.*\)" ;;/3) WHY="\1"; return 1 ;;/'
  mutant cr-not-named '/waiver row has a CR/d'
  mutant waiver-from-worktree 's/pg show :.submodule_pin_waivers/cat "$root\/.submodule_pin_waivers"/'
  mutant waiver-ignores-expiry '/\[\[ "\$e" < "\$today" \]\]/d'
  mutant expiry-boundary 's/\[\[ "\$e" < "\$today" \]\]/[[ ! "$e" > "$today" ]]/'
  mutant expiry-format-unchecked '/not a real YYYY-MM-DD date/d'
  mutant horizon-unchecked '/beyond today + max_waiver_days/d'
  mutant horizon-boundary 's/\[\[ "\$e" > "\$lim" \]\]/[[ ! "$e" < "$lim" ]]/'
  mutant item-format-unchecked '/does not match \${prefix}-NNN/d'
  mutant item-prefix-hardcoded 's/\^\${prefix}-/^CON-/'
  # consumer DATA (config from the base commit) and the reviewer killers K1, K3-K5
  mutant config-from-index 's/ctext="\$(blob "\$basec" .submodule_pin_gate.conf)"/ctext="$(git -C "$root" show :.submodule_pin_gate.conf 2>\/dev\/null)"/'
  mutant config-error-ignored 's/^  \[ -z "\$conferr" \] || .*$/  :/'
  mutant RV1-config-unreadable-as-absent 's/^elif \[ "\$crc" = 2 \]; then conferr=.*$/elif false; then :/'
  mutant RV3-duplicate-key-allowed 's/^    case "\$seen" in .*$/    :/'
  mutant RV4-prefix-unvalidated 's/item_prefix) \[\[ "\$v" =~ \^\[A-Z\]\[A-Z0-9\]+\$ \]\] || /item_prefix) true || /'
  mutant RV5-365-cap-removed 's/ \&\& \[ "\$v" -le 365 \]//'
  # authoriser (R2-m3, RM1, R3-n4)
  mutant RM1-ident-guard '/committer or author identity unresolvable/d'
  mutant self-authoriser-allowed 's/    return 10 if any(.*) else 0/    return 0/'
  mutant R3n4-failure-reported-as-self 's/^      10) WHY=/      1|10) WHY=/'
  mutant no-casefold-no-nfc 's/^    f=lambda s: .*/    f=lambda s: s/'
  mutant casefold-without-nfc 's/unicodedata.normalize("NFC", unicodedata.normalize("NFC", s).casefold())/s.casefold()/'
  # ---- round-11 independent reviewer mutants (not written by the author) ----
  mutant RVR11-01-outer-nfc-dropped 's/unicodedata.normalize("NFC", unicodedata.normalize("NFC", s).casefold())/unicodedata.normalize("NFC", s).casefold()/'
  mutant RVR11-02-inner-nfc-dropped 's/unicodedata.normalize("NFC", unicodedata.normalize("NFC", s).casefold())/unicodedata.normalize("NFC", s.casefold())/'
  mutant RVR11-03-kids-first-parent-skipped 's/for(i=2;i<=NF;i++) if(\$i""==b"")/for(i=3;i<=NF;i++) if($i""==b"")/'
  mutant RVR11-04-spent-base-field-unchecked 's/ \&\& \$3""==n"" \&\& \$7""==b"" {f=0}/ \&\& $3""==n"" {f=0}/'
  mutant RVR11-05-main-diff-renames-on 's/pg diff --cached --raw -z --no-abbrev --no-renames /pg diff --cached --raw -z --no-abbrev -M /'
  mutant RVR11-06-today-local-tz 's/^today="\$(TZ=UTC date +%Y-%m-%d)"/today="$(date +%Y-%m-%d)"/'
  mutant RVR11-07-stash-counted 's/rev-list --exclude=refs\/stash --all --parents/rev-list --all --parents/'
  mutant authoriser-form-unchecked 's/ or a!=a.strip() or "<" in a or ">" in a//'
  mutant empty-authoriser-allowed 's/if not a or /if /'
  mutant author-not-compared 's/"\$(idname "\$aident")" "\$(idmail "\$aident")"/"" ""/'
  mutant help-truncated 's/-h|--help) awk .*$/-h|--help) sed -n 2,40p "$self"; exit 0 ;;/'
  # ── round 6 (§11.4.276(D), §11.4.194(6)(d)): the round-5 reviewer's mutants NM1-NM9, adopted verbatim from
  # rv046r5.FRc3WD/nm/NM*.sed (here-docs keep the text byte for byte). NM6 is ADAPTED: its target text
  # `diff --cached --quiet` is now the plumbing `diff-index --cached --quiet` (the A3 fix), so the same mutation
  # (drop --cached: compare the worktree, not the index) is applied to the new text. NM6-NM8 were controls in round 5.
  mkdir -p "$tmp/nm"
  cat >"$tmp/nm/NM1" <<'NMEOF'
/hx="\$headc"$/s/ --ignore-submodules=none//
NMEOF
  cat >"$tmp/nm/NM2" <<'NMEOF'
s/2>\/dev\/null)" != false \]; then kidsrc=shallow/2>\/dev\/null)" = true ]; then kidsrc=shallow/
NMEOF
  cat >"$tmp/nm/NM3" <<'NMEOF'
s/\$1""!=h"" {for(i=2;i<=NF;i++)/$1""!=h"" {for(i=2;i<=2;i++)/
NMEOF
  cat >"$tmp/nm/NM4" <<'NMEOF'
/\$7""==b"" {f=0}/s/ && \$3""==n""//
NMEOF
  cat >"$tmp/nm/NM5" <<'NMEOF'
/printf '%s\\n' "\$t" | awk -F/s/ -F'\\t'//
NMEOF
  cat >"$tmp/nm/NM6" <<'NMEOF'
/hx="\$headc"$/s/diff-index --cached --quiet/diff-index --quiet/
NMEOF
  cat >"$tmp/nm/NM7" <<'NMEOF'
s/pg cat-file -e "\$1^{tree}"/pg cat-file -e "$1"/
NMEOF
  cat >"$tmp/nm/NM8" <<'NMEOF'
s/rev-list --exclude=refs\/stash --all --parents/rev-list --all --exclude=refs\/stash --parents/
NMEOF
  cat >"$tmp/nm/NM9" <<'NMEOF'
/\$7""==b"" {f=0}/s/NF==7 &&/NF>=7 \&\&/
NMEOF
  mutant NM1-n4-ignore-submodules-dropped "$(cat "$tmp/nm/NM1")"
  mutant NM2-shallow-unknown-is-deep "$(cat "$tmp/nm/NM2")"
  mutant NM3-first-parent-only "$(cat "$tmp/nm/NM3")"
  mutant NM4-spent-ignores-new "$(cat "$tmp/nm/NM4")"
  mutant NM5-spent-whitespace-split "$(cat "$tmp/nm/NM5")"
  mutant NM6-n4-worktree-not-index-ADAPTED "$(cat "$tmp/nm/NM6")"
  mutant NM7-tree-check-not-peeled "$(cat "$tmp/nm/NM7")"
  mutant NM8-stash-exclude-after-all "$(cat "$tmp/nm/NM8")"
  mutant NM9-spent-extra-fields "$(cat "$tmp/nm/NM9")"
  # ── round 6: the class inventory, one mutant per guard no earlier mutant falsified (author-written)
  mutant usage-value-unchecked 's/^need() { .*$/need() { :; }/'
  mutant usage-empty-value-accepted 's/ \&\& \[ -n "\$2" \] ||/ ||/'
  mutant unknown-arg-accepted 's/^    \*) echo "\$GATE: unknown argument \$1" >&2; exit 2 ;;$/    *) shift ;;/'
  mutant root-cd-fail-ignored 's/ \&\& pwd -P)" || exit 2; shift 2 ;;/ \&\& pwd -P)"; shift 2 ;;/'
  mutant not-a-worktree-unchecked 's/^top="\$(git -C "\$root" rev-parse --show-toplevel 2>\/dev\/null)" || blind0 .*$/top="$(git -C "$root" rev-parse --show-toplevel 2>\/dev\/null)"/'
  mutant local-env-vars-unchecked '/local-env-vars returned nothing/d'
  mutant unborn-base-fallback-dropped 's/; \[ -n "\$basec" \] || basec="\$(pg hash-object -t tree \/dev\/null)"//'
  mutant base-resolve-unchecked 's/ || blind0 "--base \$base does not resolve to a commit"//'
  mutant base-peel-dropped 's/"\$base^{commit}"/"$base"/'
  mutant blob-absent-is-unreadable 's/^  id="\$(pg rev-parse -q --verify "\$1:\$2" 2>\/dev\/null)" || return 1$/  id="$(pg rev-parse -q --verify "$1:$2" 2>\/dev\/null)" || return 2/'
  mutant blob-unreadable-is-absent 's/^  pg cat-file blob "\$id" 2>\/dev\/null || return 2$/  pg cat-file blob "$id" 2>\/dev\/null || return 1/'
  mutant conf-comments-not-skipped '/^    case "\$line" in /s/.*/    :/'
  mutant conf-non-kv-unnamed '/is not key=value/d'
  mutant conf-days-regex-loosened '/max_waiver_days) \[\[/s/\^\[1-9\]\[0-9\]{0,2}\$/^[0-9]+$/'
  mutant conf-unknown-key-accepted '/config key .\$k. unknown/s/.*/      *) ;;/'
  mutant waivers-file-not-read 's/wtext="\$(cat "\$waivers" 2>\/dev\/null)"/wtext=""/'
  mutant no-data-unnamed '/no waiver data (\$wsrc)/d'
  mutant idname-empty 's/^idname() { .*$/idname() { printf ""; }/'
  mutant idmail-empty 's/^idmail() { .*$/idmail() { printf ""; }/'
  mutant authoriser-control-chars-allowed 's/ or any(unicodedata.category(c).startswith("C") for c in a)//'
  mutant authoriser-crash-uncaught 's/^except BaseException:$/except KeyboardInterrupt:/'
  mutant python3-missing-unnamed '/python3 missing; cannot check authoriser/d'
  mutant form-reason-unnamed 's/^      3) WHY=/      33) WHY=/'
  mutant item-digits-loosened 's/-\[0-9\]{3,}\$ \]\]/-[0-9]+$ ]]/'
  mutant item-anchor-dropped 's/-\[0-9\]{3,}\$ \]\]/-[0-9]{3,} ]]/'
  mutant expiry-roundtrip-dropped 's/ \&\& \[ "\$(date -d "\$e" +%Y-%m-%d 2>\/dev\/null)" = "\$e" \]//'
  mutant waiver-comment-rows-honoured 's/NF==7 \&\& \$1!~\/\^#\/ \&\& /NF==7 \&\& /'
  mutant spent-numeric-path '/\$7""==b"" {f=0}/s/\$1""==p""/$1==p/'
  mutant spent-any-parent-is-base 's/if(\$i""==b""){print \$1; break}/if(1){print $1; break}/'
  mutant spent-no-parents 's/ --all --parents 2>/ --all 2>/'
  mutant N4-porcelain-diff '/hx="\$headc"$/s/diff-index --cached/diff --cached/'
  mutant N4-quiet-dropped '/hx="\$headc"$/s/ --quiet//'
  mutant N4-compares-base '/hx="\$headc"$/s/"\${headc:-\$basec}"/"$basec"/'
  mutant new-gitlink-judged 's/^  \[ "\$om" = 160000 \] \&\& \[ "\$nm" = 160000 \] || continue$/  [ "$nm" = 160000 ] || continue/'
  mutant deleted-gitlink-judged 's/^  \[ "\$om" = 160000 \] \&\& \[ "\$nm" = 160000 \] || continue$/  [ "$om" = 160000 ] || continue/'
  mutant count-not-incremented 's/checked=\$((checked+1)); //'
  mutant missing-checkout-unnamed 's/^    blindmsg "\$path" "submodule checkout missing.*$/    :; fi/'
  mutant symlink-unchecked 's/^    blindmsg "\$path" "checkout path is a symlink.*$/    :; fi/'
  mutant fetchfix-swapped 's/if \[ "\$shallow" = false \]; then fetchfix=/if [ "$shallow" != false ]; then fetchfix=/'
  mutant old-presence-unnamed 's/^    blindmsg "\$path" "old pin .*$/    :; fi/'
  mutant new-presence-unnamed 's/^    blindmsg "\$path" "new pin .*$/    :; fi/'
  mutant old-peel-dropped 's/cat-file -e "\${osha}^{commit}"/cat-file -e "${osha}"/'
  mutant new-peel-dropped 's/cat-file -e "\${nsha}^{commit}"/cat-file -e "${nsha}"/'
  mutant diverged-needs-no-rc1 's/elif \[ "\$fwd" = 1 \] \&\& \[ "\$back" = 1 \] \&\& /elif /'
  # ── round 7 (§11.4.276(D), §11.4.194(6)(d)): the round-6 reviewer's mutants V01-V29 (no V04, V23) and the hook
  # mutants HK30-HK32, verbatim from rv046r6.8sUslJ/vm/*.sed (here-docs). V28 is an equivalence claim (eqp below).
  mutf V01-unknown-arg-exits-1 <<'MEOF'
s/^    \*) echo "\$GATE: unknown argument \$1" >&2; exit 2 ;;$/    *) echo "$GATE: unknown argument $1" >\&2; exit 1 ;;/
MEOF
  mutf V02-help-exits-1 <<'MEOF'
s/NR>1 {exit}' "\$self"; exit 0 ;;/NR>1 {exit}' "$self"; exit 1 ;;/
MEOF
  mutf V03-env-keeps-GIT_DIR <<'MEOF'
s/GIT_CONFIG_PARAMETERS|GIT_CONFIG_COUNT) ;;/GIT_CONFIG_PARAMETERS|GIT_CONFIG_COUNT|GIT_DIR) ;;/
MEOF
  mutf V05-mergehead-wrong-ref <<'MEOF'
s/'MERGE_HEAD^{commit}'/'CHERRY_PICK_HEAD^{commit}'/
MEOF
  mutf V06-blob-cat-p <<'MEOF'
s/^  pg cat-file blob "\$id" 2>\/dev\/null || return 2$/  pg cat-file -p "$id" 2>\/dev\/null || return 2/
MEOF
  mutf V07-conf-days-max-99 <<'MEOF'
s/\^\[1-9\]\[0-9\]{0,2}\$/^[1-9][0-9]{0,1}$/
MEOF
  mutf V08-conf-days-365-exclusive <<'MEOF'
s/\[ "\$v" -le 365 \]/[ "$v" -lt 365 ]/
MEOF
  mutf V09-conf-seen-no-space <<'MEOF'
s/seen+="\$k "/seen+="$k"/
MEOF
  mutf V10-waivers-from-head <<'MEOF'
s/pg show :.submodule_pin_waivers/pg show HEAD:.submodule_pin_waivers/
MEOF
  mutf V11-author-is-committer <<'MEOF'
s/aident="\$(pg var GIT_AUTHOR_IDENT 2>\/dev\/null)"/aident="$cident"/
MEOF
  mutf V12-authoriser-only-Cc <<'MEOF'
s/unicodedata.category(c).startswith("C")/unicodedata.category(c)=="Cc"/
MEOF
  mutf V13-casefold-to-lower <<'MEOF'
s/s).casefold())/s).lower())/
MEOF
  mutf V14-n4-hx-is-base <<'MEOF'
s/ 2>\/dev\/null \&\& hx="\$headc"$/ 2>\/dev\/null \&\& hx="$basec"/
MEOF
  mutf V15-spent-hides-remotes <<'MEOF'
s/rev-list --exclude=refs\/stash --all --parents/rev-list --exclude=refs\/stash --exclude=refs\/remotes\/* --all --parents/
MEOF
  mutf V16-spent-hides-notes <<'MEOF'
s/rev-list --exclude=refs\/stash --all --parents/rev-list --exclude=refs\/stash --exclude=refs\/notes\/* --all --parents/
MEOF
  mutf V17-spent-fileless-kid-ends-scan <<'MEOF'
s/^    \[ "\$rc" = 0 \] || continue$/    [ "$rc" = 0 ] || return 1/
MEOF
  mutf V18-comment-hash-anywhere <<'MEOF'
s/\$1!~\/\^#\//$1!~\/#\//
MEOF
  mutf V19-base-mismatch-aborts-rows <<'MEOF'
/waiver row is bound to base/s/; continue; }$/; return 1; }/
MEOF
  mutf V20-bad-expiry-aborts-rows <<'MEOF'
/is not a real YYYY-MM-DD date/s/; continue; }$/; return 1; }/
MEOF
  mutf V21-horizon-minus-1 <<'MEOF'
s/+\$maxd days/+$((maxd-1)) days/
MEOF
  mutf V22-sub-shallow-unknown-is-complete <<'MEOF'
s/\[ "\$back" = 1 \] \&\& \[ "\$shallow" = false \]/[ "$back" = 1 ] \&\& [ "$shallow" != true ]/
MEOF
  mutf V24-forward-args-swapped <<'MEOF'
s/merge-base --is-ancestor "\$osha" "\$nsha" 2>\/dev\/null; fwd=/merge-base --is-ancestor "$nsha" "$osha" 2>\/dev\/null; fwd=/
MEOF
  mutf V25-meta-colon-kept <<'MEOF'
s/om="\${1#:}"/om="$1"/
MEOF
  mutf V26-blind-exits-1 <<'MEOF'
s/^\[ "\$blind" = 1 \] \&\& exit 2$/[ "$blind" = 1 ] \&\& exit 1/
MEOF
  mutf V27-dstat-wrong-index <<'MEOF'
s/\[ "\${dstat\[0\]}" = 0 \]/[ "${dstat[1]}" = 0 ]/
MEOF
  mutf V29-python-not-isolated <<'MEOF'
s/python3 -I -c/python3 -c/
MEOF
  hkmutf HK30-hook-ignores-gate-exit <<'MEOF'
s/^exec bash "\$gate" --root "\$root"$/bash "$gate" --root "$root"; exit 0/
MEOF
  hkmutf HK31-hook-no-readlink <<'MEOF'
s/self="\$(readlink -f "\${BASH_SOURCE\[0\]:-\$0}")"/self="${BASH_SOURCE[0]:-$0}"/
MEOF
  hkmutf HK32-hook-drops-GIT_INDEX_FILE <<'MEOF'
s/^exec bash "\$gate"/exec env -u GIT_INDEX_FILE bash "$gate"/
MEOF
  # ── round 7 (structural, CON-146): member- and site-level mutants, one per guard member and fail direction the
  # inventory (cm_submodule_pin_not_downgraded_inventory.tsv) names. fo = makes a refusal pass, fr = makes a pass refuse.
  mutf lastpipe-dropped <<'MEOF'
/^shopt -s lastpipe$/d
MEOF
  mutf root-default-wrong <<'MEOF'
s|^root="\$(cd "\$(dirname "\$self")/../.." \&\& pwd -P)"|root="$(cd "$(dirname "$self")/.." \&\& pwd -P)"|
MEOF
  mutf usage-argc-off-by-one <<'MEOF'
s/^need() { \[ "\$1" -ge 2 \]/need() { [ "$1" -ge 3 ]/
MEOF
  mutf base-arg-dropped <<'MEOF'
s/ base="\$2"; shift 2 ;;/ shift 2 ;;/
MEOF
  mutf waivers-arg-dropped <<'MEOF'
s/ waivers="\$2"; shift 2 ;;/ shift 2 ;;/
MEOF
  mutf blind0-exits-0 <<'MEOF'
s/^blind0() { echo "\$GATE: BLIND — \$1"; exit 2; }/blind0() { echo "$GATE: BLIND — $1"; exit 0; }/
MEOF
  mutf lev-check-always-blind <<'MEOF'
s/^\[ "\${#lev\[@\]}" -gt 0 \]/[ "${#lev[@]}" -gt 9999 ]/
MEOF
  mutf headc-empty <<'MEOF'
s/^headc="\$(pg rev-parse -q --verify 'HEAD^{commit}' 2>\/dev\/null)"$/headc=""/
MEOF
  mutf mergeh-always <<'MEOF'
s/^mergeh="\$(pg rev-parse -q --verify 'MERGE_HEAD^{commit}' 2>\/dev\/null)"$/mergeh=x/
MEOF
  mutf mergeh-never <<'MEOF'
s/^mergeh="\$(pg rev-parse -q --verify 'MERGE_HEAD^{commit}' 2>\/dev\/null)"$/mergeh=""/
MEOF
  mutf today-past <<'MEOF'
s/^today="\$(TZ=UTC date +%Y-%m-%d)"$/today=2000-01-01/
MEOF
  mutf today-future <<'MEOF'
s/^today="\$(TZ=UTC date +%Y-%m-%d)"$/today=2999-01-01/
MEOF
  mutf default-days-31 <<'MEOF'
s/^maxd=30; prefix=CON;/maxd=31; prefix=CON;/
MEOF
  mutf default-days-29 <<'MEOF'
s/^maxd=30; prefix=CON;/maxd=29; prefix=CON;/
MEOF
  mutf default-prefix-wrong <<'MEOF'
s/^maxd=30; prefix=CON;/maxd=30; prefix=COM;/
MEOF
  mutf conf-blank-not-skipped <<'MEOF'
s/case "\$line" in ''|'#'\*) continue ;; esac/case "$line" in '#'*) continue ;; esac/
MEOF
  mutf conf-hash-not-skipped <<'MEOF'
s/case "\$line" in ''|'#'\*) continue ;; esac/case "$line" in '') continue ;; esac/
MEOF
  mutf conf-kv-inverted <<'MEOF'
s/k="\${line%%=\*}"; v="\${line#\*=}"/v="${line%%=*}"; k="${line#*=}"/
MEOF
  mutf conf-kv-always-error <<'MEOF'
s/\[ "\$k" != "\$line" \] || { conferr=/false || { conferr=/
MEOF
  mutf conf-dup-always-error <<'MEOF'
s/case "\$seen" in \*" \$k "\*) conferr=/case "$seen" in *) conferr=/
MEOF
  mutf conf-days-366 <<'MEOF'
s/ \&\& \[ "\$v" -le 365 \] || /  \&\& [ "$v" -le 366 ] || /
MEOF
  mutf conf-days-always-error <<'MEOF'
s/max_waiver_days) \[\[ "\$v" =~/max_waiver_days) false \&\& [[ "$v" =~/
MEOF
  mutf days-assign-dropped <<'MEOF'
s/; maxd="\$v" ;;/ ;;/
MEOF
  mutf prefix-plus-to-star <<'MEOF'
s/item_prefix) \[\[ "\$v" =~ \^\[A-Z\]\[A-Z0-9\]+\$ \]\]/item_prefix) [[ "$v" =~ ^[A-Z][A-Z0-9]*$ ]]/
MEOF
  mutf prefix-anchor-start-dropped <<'MEOF'
s/item_prefix) \[\[ "\$v" =~ \^\[A-Z\]\[A-Z0-9\]+\$ \]\]/item_prefix) [[ "$v" =~ [A-Z][A-Z0-9]+$ ]]/
MEOF
  mutf prefix-anchor-end-dropped <<'MEOF'
s/item_prefix) \[\[ "\$v" =~ \^\[A-Z\]\[A-Z0-9\]+\$ \]\]/item_prefix) [[ "$v" =~ ^[A-Z][A-Z0-9]+ ]]/
MEOF
  mutf conf-prefix-always-error <<'MEOF'
s/item_prefix) \[\[ "\$v" =~/item_prefix) false \&\& [[ "$v" =~/
MEOF
  mutf prefix-assign-dropped <<'MEOF'
s/; prefix="\$v" ;;/ ;;/
MEOF
  mutf conf-unknown-key-always <<'MEOF'
s/^      max_waiver_days) \[\[/      max_waiver_daysX) [[/
MEOF
  mutf horizon-plus-1 <<'MEOF'
s/+\$maxd days/+$((maxd+1)) days/
MEOF
  mutf cident-empty <<'MEOF'
s/^cident="\$(pg var GIT_COMMITTER_IDENT 2>\/dev\/null)"/cident=""/
MEOF
  mutf idpy-split-wrong <<'MEOF'
s/split(b"\\0")/split(b"\\1")/
MEOF
  mutf auth-lt-dropped <<'MEOF'
s/ or "<" in a or ">" in a/ or ">" in a/
MEOF
  mutf auth-gt-dropped <<'MEOF'
s/ or "<" in a or ">" in a/ or "<" in a/
MEOF
  mutf auth-form-always <<'MEOF'
s/    if not a or a!=a.strip()/    if True or not a or a!=a.strip()/
MEOF
  mutf normalise-to-empty <<'MEOF'
s/^    f=lambda s: .*/    f=lambda s: ""/
MEOF
  mutf self-always <<'MEOF'
s/    return 10 if any(.*) else 0/    return 10/
MEOF
  mutf crash-is-ok <<'MEOF'
s/^    rc=4$/    rc=0/
MEOF
  mutf shallow-always <<'MEOF'
s/2>\/dev\/null)" != false \]; then kidsrc=shallow/2>\/dev\/null)" != nope ]; then kidsrc=shallow/
MEOF
  mutf kidsrc-err-is-ok <<'MEOF'
s/^    else kidsrc=err; fi$/    else kidsrc=ok; fi/
MEOF
  mutf spent-hides-tags <<'MEOF'
s/rev-list --exclude=refs\/stash --all --parents/rev-list --exclude=refs\/stash --exclude=refs\/tags\/* --all --parents/
MEOF
  mutf shallow-reason-dropped <<'MEOF'
s/^  \[ "\$kidsrc" = shallow \] \&\& { SPENT=.*$/  :/
MEOF
  mutf spent-absent-is-spent <<'MEOF'
s/^    \[ "\$rc" = 0 \] || continue$/    [ "$rc" = 0 ] || return 0/
MEOF
  mutf spent-unreadable-is-unspent <<'MEOF'
s/^    \[ "\$rc" = 2 \] \&\& { SPENT="the waiver file of commit .*$/    [ "$rc" = 2 ] \&\& continue/
MEOF
  mutf spent-awk-always-match <<'MEOF'
s/ {f=0} END{exit f}' "\$1" "\$2" "\$3" "\$basec"/ {f=0} END{exit 0}' "$1" "$2" "$3" "$basec"/
MEOF
  mutf spent-default-spent <<'MEOF'
/^  done$/{n;s/^  return 1$/  return 0/}
MEOF
  mutf spender-ignored <<'MEOF'
s/ \&\& { SPENT="\$k"; return 0; }/ \&\& { SPENT="$k"; continue; }/
MEOF
  mutf unspent-not-honoured <<'MEOF'
s/^           1) return 0 ;;$/           1) WHY=unspent ;;/
MEOF
  mutf auth-arg-is-committer <<'MEOF'
s/"\$a" "\$(idname "\$cident")"/"$(idname "$cident")" "$(idname "$cident")"/
MEOF
  mutf rows-exhausted-is-waived <<'MEOF'
/^  done <<<"\$cand"$/{n;s/^  return 1$/  return 0/}
MEOF
  mutf base-always-mismatch <<'MEOF'
s/^    \[ "\$bs" = "\$basec" \] ||/    [ "$bs" = x ] ||/
MEOF
  mutf cr-always <<'MEOF'
s/^    \[\[ "\$row" != \*\$'\\r'\* \]\] ||/    false ||/
MEOF
  mutf expiry-always-bad <<'MEOF'
s/^    \[\[ "\$e" =~ \^\[0-9\]{4}/    false \&\& [[ "$e" =~ ^[0-9]{4}/
MEOF
  mutf item-always-bad <<'MEOF'
s/^    \[\[ "\$i" =~ \^\${prefix}-/    false \&\& [[ "$i" =~ ^${prefix}-/
MEOF
  mutf python3-always-missing <<'MEOF'
s/command -v python3 >\/dev\/null 2>&1 ||/command -v nopython3xyz >\/dev\/null 2>\&1 ||/
MEOF
  mutf fail-init-1 <<'MEOF'
s/^fail=0; blind=0; checked=0$/fail=1; blind=0; checked=0/
MEOF
  mutf blind-init-1 <<'MEOF'
s/^fail=0; blind=0; checked=0$/fail=0; blind=1; checked=0/
MEOF
  mutf fail-not-set <<'MEOF'
s/ or stage a valid waiver"; fail=1; fi/ or stage a valid waiver"; fi/
MEOF
  mutf blind-exit-dropped <<'MEOF'
/^\[ "\$blind" = 1 \] \&\& exit 2$/d
MEOF
  mutf pass-exits-1 <<'MEOF'
s/ inspected)"; exit 0$/ inspected)"; exit 1/
MEOF
  mutf checkout-check-dropped <<'MEOF'
s/if \[ -z "\$subp" \] || ! sg -C "\$sub" rev-parse --git-dir >\/dev\/null 2>&1; then/if [ -z "$subp" ]; then/
MEOF
  mutf checkout-always-missing <<'MEOF'
s/if \[ -z "\$subp" \] || ! sg -C "\$sub"/if true || ! sg -C "$sub"/
MEOF
  mutf symlink-always <<'MEOF'
s/^  if \[ "\$subp" != "\$root\/\$path" \]; then/  if true; then/
MEOF
  mutf ownrepo-always <<'MEOF'
s/rev-parse --show-toplevel 2>\/dev\/null)" != "\$subp" \]; then/rev-parse --show-toplevel 2>\/dev\/null)" != nope ]; then/
MEOF
  mutf old-presence-always <<'MEOF'
s/^  if ! sg -C "\$sub" cat-file -e "\${osha}^{commit}"/  if true || ! sg -C "$sub" cat-file -e "${osha}^{commit}"/
MEOF
  mutf new-presence-always <<'MEOF'
s/^  if ! sg -C "\$sub" cat-file -e "\${nsha}^{commit}"/  if true || ! sg -C "$sub" cat-file -e "${nsha}^{commit}"/
MEOF
  mutf forward-is-refused <<'MEOF'
s/^  if \[ "\$fwd" = 0 \]; then echo "\$GATE: ok \$path/  if [ "$fwd" = 9 ]; then echo "$GATE: ok $path/
MEOF
  mutf diverged-is-blind <<'MEOF'
s/^  elif \[ "\$fwd" = 1 \] \&\& \[ "\$back" = 1 \] \&\& \[ "\$shallow" = false \]; then/  elif false; then/
MEOF
  mutf waived-always-refused <<'MEOF'
s/^    if waived "\$path" "\$osha" "\$nsha"; then/    if false; then/
MEOF
  mutf gitlink-filter-inverted <<'MEOF'
s/^  \[ "\$om" = 160000 \] \&\& \[ "\$nm" = 160000 \] || continue$/  [ "$om" != 160000 ] \&\& [ "$nm" != 160000 ] || continue/
MEOF
  mutf diff-status-always-blind <<'MEOF'
s/^\[ "\${dstat\[0\]}" = 0 \] ||/[ "${dstat[0]}" = 99 ] ||/
MEOF
  mutf no-data-always <<'MEOF'
s/^  \[ -n "\$wtext" \] ||/  false ||/
MEOF
  mutf conferr-always <<'MEOF'
s/^  \[ -z "\$conferr" \] ||/  false ||/
MEOF
  mutf cand-always-empty <<'MEOF'
s/^  \[ -n "\$cand" \] || return 1$/  return 1/
MEOF
  mutf horizon-always <<'MEOF'
s/^    \[\[ "\$e" > "\$lim" \]\] \&\&/    true \&\&/
MEOF
  mutf expired-always <<'MEOF'
s/^    \[\[ "\$e" < "\$today" \]\] \&\&/    true \&\&/
MEOF
  mutf ident-always <<'MEOF'
s/^    \[ -n "\$cident" \] \&\& \[ -n "\$aident" \] ||/    false ||/
MEOF
  mutf crc-unreadable-always <<'MEOF'
s/^elif \[ "\$crc" = 2 \]; then conferr=/elif true; then conferr=/
MEOF
  mutf blob-tree-always-missing <<'MEOF'
s/^  pg cat-file -e "\$1^{tree}" 2>\/dev\/null || return 2$/  return 2/
MEOF
  mutf kids-awk-never-matches <<'MEOF'
s/if(\$i""==b""){print \$1; break}/if(0){print $1; break}/
MEOF
  # sites: the same refusal reached through `return 1` (abort) instead of `continue` (next row); each is killed only by a
  # fixture whose FIRST matching row fails that check and a LATER row is valid (the SITE* fixtures in members())
  mutf site-cr-aborts <<'MEOF'
s/save it with LF"; continue; }/save it with LF"; return 1; }/
MEOF
  mutf site-expired-aborts <<'MEOF'
s/WHY="waiver expired \$e"; continue; }/WHY="waiver expired $e"; return 1; }/
MEOF
  mutf site-horizon-aborts <<'MEOF'
s/max_waiver_days=\$maxd (\$lim)"; continue; }/max_waiver_days=$maxd ($lim)"; return 1; }/
MEOF
  mutf site-item-aborts <<'MEOF'
s/does not match \${prefix}-NNN"; continue; }/does not match ${prefix}-NNN"; return 1; }/
MEOF
  mutf site-self-aborts <<'MEOF'
s/(producer cannot self-waive)" ;;/(producer cannot self-waive)"; return 1 ;;/
MEOF
  mutf site-pyfail-aborts <<'MEOF'
s/WHY="authoriser check failed (python3 rc \$irc)" ;;/WHY="authoriser check failed (python3 rc $irc)"; return 1 ;;/
MEOF
  # the TEST member and the REACTION member of each `test || reaction` line get their own mutant (inventory L3)
  mutf not-a-worktree-always <<'MEOF'
s/^top="\$(git -C "\$root" rev-parse --show-toplevel/top="$(git -C "$root" rev-parse --show-nope/
MEOF
  mutf root-cd-top-fails <<'MEOF'
s|^root="\$(cd "\$top" \&\& pwd -P)"|root="$(cd "/nonexistent$top" \&\& pwd -P)"|
MEOF
  mutf blob-always-absent <<'MEOF'
s/verify "\$1:\$2" 2>\/dev\/null)" || return 1$/verify "$1:nope\/$2" 2>\/dev\/null)" || return 1/
MEOF
  mutf shallow-test-never <<'MEOF'
s/^  \[ "\$kidsrc" = shallow \] \&\&/  [ "$kidsrc" = nope ] \&\&/
MEOF
  mutf shallow-says-spent <<'MEOF'
s/git fetch --unshallow)"; return 2; }/git fetch --unshallow)"; return 0; }/
MEOF
  mutf history-test-always <<'MEOF'
s/^  \[ "\$kidsrc" = ok \] ||/  [ "$kidsrc" = nope ] ||/
MEOF
  mutf spent-absent-is-unreadable <<'MEOF'
s/^    \[ "\$rc" = 2 \] \&\& { SPENT=/    [ "$rc" != 0 ] \&\& { SPENT=/
MEOF
  mutf spent-kids-all-skipped <<'MEOF'
s/^    \[ "\$rc" = 0 \] || continue$/    [ "$rc" = 9 ] || continue/
MEOF
  mutf conferr-waives <<'MEOF'
s/(waivers disabled)"; return 1; }/(waivers disabled)"; return 0; }/
MEOF
  mutf no-data-waives <<'MEOF'
s/no waiver data (\$wsrc)"; return 1; }/no waiver data ($wsrc)"; return 0; }/
MEOF
  mutf no-row-waives <<'MEOF'
s/^  \[ -n "\$cand" \] || return 1$/  [ -n "$cand" ] || return 0/
MEOF
  mutf path-read-not-nul <<'MEOF'
s/IFS= read -r -d '' path; do/IFS= read -r path; do/
MEOF
  mutf path-test-inverted <<'MEOF'
s/^  \[ -n "\$path" \] || continue$/  [ -z "$path" ] || continue/
MEOF
  mutf gitlink-filter-continue-dropped <<'MEOF'
s/^  \[ "\$om" = 160000 \] \&\& \[ "\$nm" = 160000 \] || continue$/  [ "$om" = 160000 ] \&\& [ "$nm" = 160000 ] || :/
MEOF
  mutf unchanged-test-inverted <<'MEOF'
s/^  \[ "\$osha" != "\$nsha" \] || continue$/  [ "$osha" = "$nsha" ] || continue/
MEOF
  mutf diff-status-exit-0 <<'MEOF'
s/index unreadable?)"; exit 2; }/index unreadable?)"; exit 0; }/
MEOF
  mutf fail-test-never <<'MEOF'
s/^\[ "\$fail" = 1 \] \&\& exit 1$/[ "$fail" = 9 ] \&\& exit 1/
MEOF
  mutf blind-test-never <<'MEOF'
s/^\[ "\$blind" = 1 \] \&\& exit 2$/[ "$blind" = 9 ] \&\& exit 2/
MEOF
  hkmutf hook-skip-always <<'MEOF'
s/^if \[ ! -r "\$gate" \]; then$/if true; then/
MEOF
  hkmutf hook-root-wrong <<'MEOF'
s/--show-toplevel)" || exit 1/--show-cdup)" || exit 1/
MEOF
  hkmutf hook-skip-exits-1 <<'MEOF'
s/NOT GUARDED." >&2; exit 0; fi/NOT GUARDED." >\&2; exit 1; fi/
MEOF
  hkmutf hook-root-fail-ignored <<'MEOF'
s/--show-toplevel)" || exit 1/--show-toplevel)" || :/
MEOF
  mutf cand-empty-unchecked <<'MEOF'
/^  \[ -n "\$cand" \] || return 1$/d
MEOF
  # ── round 8: the three round-7 "UNCONFIRMED-equivalent" claims were false (review R7-2); they are mutants now,
  # killed by the adopted probes (S_ p_safedir, D_ p_decide_oneway). The category is retired: an equivalence claim
  # needs a stated argument for why no input reaches the member, and a probe that sees the member (control needle)
  mutf config-params-all-unset <<'MEOF'
s/case "\$v" in GIT_CONFIG_PARAMETERS|GIT_CONFIG_COUNT) ;; \*) unsets+=(-u "\$v") ;; esac/unsets+=(-u "$v")/
MEOF
  mutf diverged-fwd-member-dropped <<'MEOF'
s/elif \[ "\$fwd" = 1 \] \&\& \[ "\$back" = 1 \] \&\& /elif [ "$back" = 1 ] \&\& /
MEOF
  mutf diverged-back-member-dropped <<'MEOF'
s/elif \[ "\$fwd" = 1 \] \&\& \[ "\$back" = 1 \] \&\& /elif [ "$fwd" = 1 ] \&\& /
MEOF
  # round-7 reviewer mutants RV7-01..RV7-05 (review_con046_r7.md section 7), byte for byte against the round-8 gate
  mutf RV7-01-keep-drops-COUNT <<'MEOF'
s/case "\$v" in GIT_CONFIG_PARAMETERS|GIT_CONFIG_COUNT) ;;/case "$v" in GIT_CONFIG_PARAMETERS) ;;/
MEOF
  mutf RV7-02-keep-drops-PARAMETERS <<'MEOF'
s/case "\$v" in GIT_CONFIG_PARAMETERS|GIT_CONFIG_COUNT) ;;/case "$v" in GIT_CONFIG_COUNT) ;;/
MEOF
  mutf RV7-03-item-exactly-3-digits <<'MEOF'
s/-\[0-9\]{3,}\$ \]\]/-[0-9]{3}$ ]]/
MEOF
  mutf RV7-04-authoriser-lstrip-only <<'MEOF'
s/a!=a\.strip() or "<"/a!=a.lstrip() or "<"/
MEOF
  mutf RV7-05-help-long-dropped <<'MEOF'
s/^    -h|--help) awk/    -h) awk/
MEOF
  # round-8 reviewer mutants RV8-01, RV8-02 (review_con046_r8.md section 3; rv8/mut/RV8-0[12].sh): the seds give the
  # reviewer's mutated gate byte for byte (checked with cmp against rv8/mut/RV8-0[12].sh when adopted)
  mutf RV8-01-ident-compare-unstripped <<'MEOF'
s/i.strip() and f(i.strip())==f(a)/i.strip() and f(i)==f(a)/
MEOF
  mutf RV8-02-authoriser-ascii-strip <<'MEOF'
s/a!=a\.strip() or "<"/a!=a.strip(" \\t\\n") or "<"/
MEOF
  # round-9 reviewer mutants RV9-02, RV9-10, RV9-11 (review_con046_r9.md section 4; rev_con046_r9/mut/RV9-02*.sh,
  # mut2/RV9-1[01]*.sh): the seds give the reviewer's mutated gate byte for byte (checked with cmp when adopted).
  # RV9-02 survived round 9 (no fixture at today-1): killed by EXPBND (members10). RV9-10 / RV9-11 strip only Zs and
  # ASCII; a U+2028 / U+2029 (RV9-10, RV9-11) or U+0085 (RV9-11) pad lets the producer self-waive: killed by WSAUTH / WSID
  mutf RV9-02-expired-yesterday-ok <<'MEOF'
s/^    \[\[ "\$e" < "\$today" \]\] \&\&/    [[ "$e" < "$(date -d "$today -1 day" +%Y-%m-%d)" ]] \&\&/
MEOF
  mutf RV9-10-auth-zs-only-pad <<'MEOF'
s/if not a or a!=a\.strip() or "<"/if not a or any(unicodedata.category(c)=="Zs" or c in " \\t\\n\\r" for c in a[:1]+a[-1:]) or "<"/
MEOF
  mutf RV9-11-ident-zs-only-strip <<'MEOF'
s/^\(    if not a or a!=a\.strip() or .*\)$/\1\n    W="".join(chr(c) for c in range(0x110000) if unicodedata.category(chr(c))=="Zs")+" \\t\\n\\r\\x0b\\x0c"/
s/return 10 if any(i\.strip() and f(i\.strip())==f(a) for i in p\[1:\]) else 0/return 10 if any(i.strip(W) and f(i.strip(W))==f(a) for i in p[1:]) else 0/
MEOF
  # round 10 (review N1, structural pass): off-by-one mutants for the boundary pairs of members10 that no earlier mutant
  # had: the lev count needs one variable, not two (LEVBND); max_waiver_days=1 is legal (DAYSBND); a two-character
  # item_prefix is legal (PFXBND)
  mutf lev-gt-1 <<'MEOF'
s/\[ "\${#lev\[@\]}" -gt 0 \]/[ "${#lev[@]}" -gt 1 ]/
MEOF
  mutf days-min-2 <<'MEOF'
s/=~ \^\[1-9\]\[0-9\]{0,2}\$ \]\]/=~ ^[2-9][0-9]{0,2}$ ]]/
MEOF
  mutf prefix-min-3 <<'MEOF'
s/=~ \^\[A-Z\]\[A-Z0-9\]+\$ \]\]/=~ ^[A-Z][A-Z0-9]{2,}$ ]]/
MEOF
  # round 10, RV9-05 (reviewer file mut/RV9-05-base-prefix-bind.sh; the sed gives it byte for byte, checked with cmp):
  # the base compared on its first 12 characters survived the first round-10 run. The class: every exact SHA equality
  # (lines 229, 240, 245) compared on a prefix, a suffix or case-folded; killed by SHANEAR / SPENTNEAR (members10)
  mutf RV9-05-base-prefix-bind <<'MEOF'
s/^    \[ "\$bs" = "\$basec" \] ||/    [ "${bs:0:12}" = "${basec:0:12}" ] ||/
MEOF
  mutf base-suffix12 <<'MEOF'
s/^    \[ "\$bs" = "\$basec" \] ||/    [ "${bs: -12}" = "${basec: -12}" ] ||/
MEOF
  mutf base-nocase <<'MEOF'
s/^    \[ "\$bs" = "\$basec" \] ||/    [ "${bs,,}" = "${basec,,}" ] ||/
MEOF
  mutf waiver-old-prefix12 <<'MEOF'
/{print \$0/s/\$2""==o""/substr($2,1,12)==substr(o,1,12)/
MEOF
  mutf waiver-new-prefix12 <<'MEOF'
/{print \$0/s/\$3""==n""/substr($3,1,12)==substr(n,1,12)/
MEOF
  mutf spent-old-prefix12 <<'MEOF'
/\$7""==b""/s/\$2""==o""/substr($2,1,12)==substr(o,1,12)/
MEOF
  mutf spent-new-prefix12 <<'MEOF'
/\$7""==b""/s/\$3""==n""/substr($3,1,12)==substr(n,1,12)/
MEOF
  mutf spent-base-prefix12 <<'MEOF'
s/\$7""==b""/substr($7,1,12)==substr(b,1,12)/
MEOF
  # ── round 11 (CON-194, review r10, §11.4.276(E)(3) structural round). Reviewer mutants RV10-01, -03, -04, -05, -07,
  # -08 and -11 adopted VERBATIM (review_con046_r10.md section 4; rev_con046_r10/mut*/RV10-*.sh; each sed gives the
  # reviewer's file byte for byte on the round-10 gate, checked with cmp when adopted). RV10-02 (today in UTC) is now
  # the gate itself, so its inverse today-local is the mutant (TZPAIR). RV10-06 (the expiry round trip replaced by a
  # parse check) is equivalent (the reviewer's measurement: 2310 strings x 3 zones; eq-expiry-tail-by-roundtrip already
  # proves the regex tail is redundant to the round trip, not the converse) and RV10-10 is HK31-hook-no-readlink. The
  # other mutants of this block are named by rows of the site table (cm_submodule_pin_not_downgraded_sites.tsv): one
  # per data site whose near-miss pair no earlier mutant attacked.
  mutf RV10-01-downgrade-one-step <<'MEOF'
s/^  sg -C "\$sub" merge-base --is-ancestor "\$nsha" "\$osha" 2>\/dev\/null; back=\$?$/  [ "$(sg -C "$sub" rev-parse "${osha}^" 2>\/dev\/null)" = "$nsha" ]; back=$?/
MEOF
  mutf RV10-03-spent-first-parent-only <<'MEOF'
s/for(i=2;i<=NF;i++)/for(i=2;i<=2;i++)/
MEOF
  mutf RV10-04-argloop-gt1 <<'MEOF'
s/^while \[ \$# -gt 0 \]; do$/while [ $# -gt 1 ]; do/
MEOF
  mutf RV10-05-email-space-strip <<'MEOF'
s/return 10 if any(i\.strip() and f(i\.strip())==f(a) for i in p\[1:\]) else 0/return 10 if any(i.strip() and f(i.strip())==f(a) for i in (p[1],p[3])) or any(i.strip(" ") and f(i.strip(" "))==f(a) for i in (p[2],p[4])) else 0/
MEOF
  mutf RV10-07-spent-path-ignored <<'MEOF'
s/NF==7 \&\& \$1""==p"" \&\& \$2""==o"" \&\& \$3""==n"" \&\& \$7""==b""/NF==7 \&\& $2""==o"" \&\& $3""==n"" \&\& $7""==b""/
MEOF
  mutf RV10-08-spent-exclude-head-always <<'MEOF'
s/^    hx=""$/    hx="$headc"/
MEOF
  mutf RV10-11-waiver-path-nocase <<'MEOF'
s/NF==7 \&\& \$1!~\/\^#\/ \&\& \$1""==p""/NF==7 \&\& $1!~\/^#\/ \&\& tolower($1)==tolower(p)/
MEOF
  mutf today-local <<'MEOF'
s/^today="\$(TZ=UTC date +%Y-%m-%d)"$/today="$(date +%Y-%m-%d)"/
MEOF
  mutf ident-names-ascii-strip <<'MEOF'
s/return 10 if any(i\.strip() and f(i\.strip())==f(a) for i in p\[1:\]) else 0/return 10 if any(i.strip() and f(i.strip())==f(a) for i in (p[2],p[4])) or any(i.strip(" ") and f(i.strip(" "))==f(a) for i in (p[1],p[3])) else 0/
MEOF
  mutf arg-nocasematch <<'MEOF'
s/^shopt -s lastpipe$/shopt -s lastpipe; shopt -s nocasematch/
MEOF
  mutf argflag-prefix <<'MEOF'
s/^    --root) need/    --root*) need/
MEOF
  mutf confkey-prefix <<'MEOF'
s/^      max_waiver_days) \[\[/      max_waiver_days*) [[/
MEOF
  mutf itemkey-prefix <<'MEOF'
s/^      item_prefix) \[\[/      item_prefix*) [[/
MEOF
  mutf conf-read-ifs-dropped <<'MEOF'
s/^  while IFS= read -r line; do$/  while read -r line; do/
MEOF
  mutf conf-hash-anywhere <<'MEOF'
s/case "\$line" in ''|'#'\*) continue/case "$line" in ''|*'#'*) continue/
MEOF
  mutf dupkey-nospace <<'MEOF'
s/case "\$seen" in \*" \$k "\*)/case "$seen" in *"$k "*)/
MEOF
  mutf confsplit-last <<'MEOF'
s/k="\${line%%=\*}"/k="${line%=*}"/
MEOF
  mutf blob-nul-unchecked <<'MEOF'
s/^  \[ "\${nul\/\/ \/}" = 0 \] || return 3$/  :/
MEOF
  mutf waiver-nul-unchecked <<'MEOF'
s/^  \[ "\${wnul\/\/ \/}" = 0 \] || {/  : || {/
MEOF
  mutf wnul-file-zero <<'MEOF'
s/wnul="\$(tr -cd '\\000' <"\$waivers" 2>\/dev\/null | wc -c)"/wnul=0/
MEOF
  mutf wnul-index-zero <<'MEOF'
s/wnul="\$(pg show :\.submodule_pin_waivers 2>\/dev\/null | tr -cd '\\000' | wc -c)"/wnul=0/
MEOF
  mutf spent-nul-unchecked <<'MEOF'
/same parent) contains a NUL byte"; return 2; }$/d
MEOF
  mutf conf-nul-unchecked <<'MEOF'
s/^if \[ "\$crc" = 3 \]; then conferr=.*$/if false; then :/
MEOF
  mutf spent-nf-ge7 <<'MEOF'
/\$7""==b""/s/NF==7 \&\&/NF>=7 \&\&/
MEOF
  mutf spent-path-nocase <<'MEOF'
/\$7""==b""/s/\$1""==p""/tolower($1)==tolower(p)/
MEOF
  mutf spent-path-prefix <<'MEOF'
/\$7""==b""/s/\$1""==p""/index(p,$1)==1/
MEOF
  mutf spent-fs-whitespace <<'MEOF'
/^    printf '%s\\n' "\$t" | awk/s/-F'\\t'/-F'[\\t ]'/
MEOF
  mutf waiver-fs-whitespace <<'MEOF'
/^  cand="\$(printf/s/-F'\\t'/-F'[\\t ]'/
MEOF
  mutf waiver-hash-anywhere <<'MEOF'
s/\$1!~\/\^#\//$1!~\/#\//
MEOF
  mutf waiver-path-prefix <<'MEOF'
/{print \$0/s/\$1""==p""/index(p,$1)==1/
MEOF
  mutf waiver-path-trim <<'MEOF'
/{print \$0/s/\$1""==p""/gensub(\/^ +| +$\/,"","g",$1)==p/
MEOF
  mutf waiver-path-slash <<'MEOF'
/{print \$0/s/\$1""==p""/($1""==p"" || $1""==p"\/" || $1""=="\.\/"p)/
MEOF
  mutf read-drop-remainder <<'MEOF'
s/IFS=\$'\\037' read -r a e i bs <<</IFS=$'\\037' read -r a e i bs _ <<</
MEOF
  mutf ifs036-tab <<'MEOF'
s/while IFS=\$'\\036' read -r row rest; do/while IFS=$'\\t' read -r row rest; do/
MEOF
  mutf crlf-endonly <<'MEOF'
s/\[\[ "\$row" != \*\$'\\r'\* \]\]/[[ "$row" != *$'\\r' ]]/
MEOF
  mutf item-nocase <<'MEOF'
s/\[\[ "\$i" =~ \^\${prefix}-\[0-9\]{3,}\$ \]\]/[[ "${i^^}" =~ ^${prefix}-[0-9]{3,}$ ]]/
MEOF
  mutf pathread-ifs-dropped <<'MEOF'
s/IFS= read -r -d '' meta \&\& IFS= read -r -d '' path/IFS= read -r -d '' meta \&\& read -r -d '' path/
MEOF
  mutf subp-prefix <<'MEOF'
s/if \[ "\$subp" != "\$root\/\$path" \]; then/if [[ "$subp" != "$root\/$path"* ]]; then/
MEOF
  mutf subp-nocase <<'MEOF'
s/if \[ "\$subp" != "\$root\/\$path" \]; then/if [ "${subp,,}" != "${root,,}\/${path,,}" ]; then/
MEOF
  mutf toplevel-prefix <<'MEOF'
s/if \[ "\$(sg -C "\$sub" rev-parse --show-toplevel 2>\/dev\/null)" != "\$subp" \]; then/if [[ "$subp" != "$(sg -C "$sub" rev-parse --show-toplevel 2>\/dev\/null)"* ]]; then/
MEOF
  mutf blob-nul-as-unreadable <<'MEOF'
s/^  \[ "\${nul\/\/ \/}" = 0 \] || return 3$/  [ "${nul\/\/ \/}" = 0 ] || return 2/
MEOF
  mutf spent-nul-as-unspent <<'MEOF'
s/(same parent) contains a NUL byte"; return 2; }$/(same parent) contains a NUL byte"; continue; }/
MEOF
  mutf waiver-nul-continues <<'MEOF'
s/(git shows such a file as binary); remove it"; return 1; }/(git shows such a file as binary); remove it"; }/
MEOF
  # ── round 8: generated member mutants (§11.4.274, §11.4.276(C)): cm_submodule_pin_not_downgraded_members.py
  # enumerates every case alternative, regex quantifier / anchor / class part, strip half, test comparison operator,
  # && / || operand, python or / and operand and `if !` of the gate. The committed ledger must equal a fresh listing
  # (a stale ledger is BAD), and every viable generated mutant must be killed (no generated mutant is claimed
  # equivalent in round 8; one that survives is a SURVIVOR, never silently dropped)
  gdir="$tmp/gen"; mkdir -p "$gdir"; gled="$here/cm_submodule_pin_not_downgraded_members.tsv"
  if ! python3 -I "$here/cm_submodule_pin_not_downgraded_members.py" emit "$gate" "$gdir" >"$tmp/members.now"; then
    echo "BAD  member generator failed"; bad=1
  elif ! cmp -s "$tmp/members.now" "$gled"; then
    echo "BAD  member ledger stale (regenerate: cm_submodule_pin_not_downgraded_members.py list <gate> > $gled)"
    diff "$gled" "$tmp/members.now" | head -6; bad=1
  else echo "ok   member ledger current: $(grep -c '' "$gled") generated members, $(grep -c $'\tviable$' "$gled") viable"
    [ "$(grep -c $'\tviable$' "$gled")" -gt 0 ] || { echo "BAD  member ledger lists no viable member (blind generator)"; bad=1; }
  fi
  while IFS=$'\t' read -r gname _ _ _ _ gv; do [ "$gv" = viable ] && mutpath "$gname" "$gdir/$gname.sh"; done <"$tmp/members.now"
  # ── round 8 (R7-7): the date self-test. A job whose `date` runs one day behind (a PATH wrapper; the gate and the
  # fixtures both see the skewed day, so the vector itself may even agree) MUST be judged INCONCLUSIVE, never killed
  mkdir -p "$tmp/skew"; printf '#!/usr/bin/env bash\nfor a in "$@"; do case "$a" in -d|-d*|--date*) exec %q "$@" ;; esac; done\nexec %q -d yesterday "$@"\n' \
    "$(command -v date)" "$(command -v date)" >"$tmp/skew/date"; chmod +x "$tmp/skew/date"
  if [ -z "${MUT_ONLY:-}" ] || [[ selftest-date-skew =~ $MUT_ONLY ]]; then n=$((n+1)); mnames[n]=selftest-date-skew; mkind[n]=dateskew; launch "$n"; fi
  # ── CON-046 round 11, screen-3 follow-up: the resource self-test. A job of the REAL gate in which one git call fails
  # the way a refused fork fails (the message git prints, exit 128) gets a different vector; it MUST be judged
  # INCONCLUSIVE, never killed (before the fix such a job read as killed: screen 3, 2026-11-13).
  mkdir -p "$tmp/resfk"; printf '#!/usr/bin/env bash\nc="${RESFK_DIR:?}/n"; i=$(( $(cat "$c" 2>/dev/null || echo 0) + 1 )); echo "$i" >"$c"\n[ "$i" = 40 ] && { echo "fatal: fork failed: Resource temporarily unavailable" >&2; exit 128; }\nexec %q "$@"\n' \
    "$realgit" >"$tmp/resfk/git"; chmod +x "$tmp/resfk/git"
  if [ -z "${MUT_ONLY:-}" ] || [[ selftest-resource-failure =~ $MUT_ONLY ]]; then n=$((n+1)); mnames[n]=selftest-resource-failure; mkind[n]=resfault; launch "$n"; fi
  # ── round 7: EQUIVALENCE claims, each with a DIFFERENTIAL proof (never by reading). eqp <name> <probe> registers the
  # equivalent mutant (sed on stdin, first here-doc) and its CONTROL mutant (a mutant of the SAME member that is NOT
  # equivalent; second here-doc, separated by a line `--`). Proof holds when: the equivalent mutant's classify vector
  # equals the real gate's (it survives the whole suite), the targeted probe gives the same answer on the real gate and
  # the equivalent mutant, and the control gives a DIFFERENT probe answer (the probe can see this member: control needle,
  # §11.4.201(7)(b)). UNCONFIRMED in the name means no shape that reaches the member was found to be constructible.
  # round 8 equivalence claims for generated members (each with its stated argument; the generated mutant itself is
  # mapped to the proof in cm_submodule_pin_not_downgraded_members_eq.tsv):
  # argc member of need(): every caller passes "${2:-}", so argc < 2 implies an empty value, which the -n member refuses
  eqp eq-need-argc-redundant pr_needargc <<'MEOF'
s/^need() { \[ "\$1" -ge 2 \] \&\& \[ -n "\$2" \] ||/need() { [ -n "$2" ] ||/
--
s/^need() { \[ "\$1" -ge 2 \] \&\& \[ -n "\$2" \] ||/need() { [ "$1" -ge 2 ] ||/
MEOF
  # upper digit bound of max_waiver_days: any 4-digit value is >= 1000 > 365, so `-le 365` refuses it anyway
  eqp eq-maxdays-upper-bound-by-le pr_maxdays <<'MEOF'
s/\^\[1-9\]\[0-9\]{0,2}\$ \]\] \&\& \[ "\$v" -le 365 \]/^[1-9][0-9]{0,3}$ ]] \&\& [ "$v" -le 365 ]/
--
s/\^\[1-9\]\[0-9\]{0,2}\$ \]\] \&\& \[ "\$v" -le 365 \]/^[1-9][0-9]{0,2}$ ]]/
MEOF
  # truthiness half of the self-waive check: for every string i, i.lstrip() and i.rstrip() are empty exactly when
  # i.strip() is (i is whitespace only), so `i.lstrip() and ...` decides as `i.strip() and ...` does. Round 9 (review F1):
  # the round-8 proof `eq-ident-strip-half` claimed the COMPARISON half (f(i.lstrip())) equivalent too, because "git
  # strips whitespace from both ident fields"; that holds for ASCII only (git keeps U+00A0 in a name), so it is withdrawn
  # and the comparison members gen-strip-38f694f31b / gen-strip-a8ce0752e7 are killed members now (fixture ZSID)
  eqp eq-ident-strip-truthiness pr_identpad <<'MEOF'
s/any(i.strip() and f(i.strip())==f(a)/any(i.lstrip() and f(i.strip())==f(a)/
--
s/    return 10 if any(.*) else 0/    return 0/
MEOF
  eqp eq-V28-missing-checkout-no-empty-check pr_checkout_shapes <<'MEOF'
s/if \[ -z "\$subp" \] || ! sg/if ! sg/
--
s/^    blindmsg "\$path" "submodule checkout missing.*$/    :; fi/
MEOF
  eqp eq-spent-absent-continue-dropped pr_sibling <<'MEOF'
/^    \[ "\$rc" = 0 \] || continue$/d
--
s/^    \[ "\$rc" = 0 \] || continue$/    [ "$rc" = 0 ] || return 0/
MEOF
  eqp eq-blob-absent-as-empty pr_sibling <<'MEOF'
s/^  id="\$(pg rev-parse -q --verify "\$1:\$2" 2>\/dev\/null)" || return 1$/  id="$(pg rev-parse -q --verify "$1:$2" 2>\/dev\/null)" || return 0/
--
s/^  id="\$(pg rev-parse -q --verify "\$1:\$2" 2>\/dev\/null)" || return 1$/  id="$(pg rev-parse -q --verify "$1:$2" 2>\/dev\/null)" || return 2/
MEOF
  eqp eq-conf-crc0-is-else pr_conf <<'MEOF'
s/^elif \[ "\$crc" = 0 \]; then$/else/
--
s/^elif \[ "\$crc" = 0 \]; then$/else conferr=absent/
MEOF
  eqp eq-idpy-len-dropped pr_auth <<'MEOF'
/^    if len(p)!=5: return 4$/d
--
s/^    if len(p)!=5: return 4$/    if len(p)!=4: return 4/
MEOF
  eqp eq-idpy-strip-and-dropped pr_auth <<'MEOF'
s/i.strip() and f(i.strip())==f(a)/f(i.strip())==f(a)/
--
s/    return 10 if any(.*) else 0/    return 0/
MEOF
  # round 9 (review F2): the round-8 proof `eq-expiry-regex-dropped` (the whole regex dropped) was FALSE under GNU date,
  # which round-trips a five-digit year (`date -d 20269-01-01 +%Y-%m-%d` prints 20269-01-01; the round-7 note "GNU date
  # rejects five-digit years" measured uutils). It is withdrawn; the same edit is now the generated member
  # gen-andor-3d5462c23c (the round-9 generator sees `[[ ... ]]` tests whose body holds `]`), killed by YEAR5, like the
  # year members gen-rxq-9efb96babf ({4,}) and gen-rxq-07a5aa0cf0 (^ dropped). What stays equivalent is the TAIL of the
  # regex: `date +%Y-%m-%d` always prints a two-digit month and day and nothing after them, under GNU and uutils alike,
  # so `= "$e"` refuses every other month or day width and any trailing text whatever the regex says after the year
  eqp eq-expiry-tail-by-roundtrip pr_expiry <<'MEOF'
s/\^\[0-9\]{4}-\[0-9\]{2}-\[0-9\]{2}\$ \]\]/^[0-9]{4}-[0-9]+-[0-9]+ ]]/
--
/not a real YYYY-MM-DD date/d
MEOF
  eqp eq-empty-path-dropped pr_paths <<'MEOF'
/^  \[ -n "\$path" \] || continue$/d
--
s/--raw -z/--raw/
MEOF
  eqp eq-unchanged-entry-dropped pr_unchanged <<'MEOF'
/^  \[ "\$osha" != "\$nsha" \] || continue$/d
--
s/^  \[ "\$om" = 160000 \] \&\& \[ "\$nm" = 160000 \] || continue$/  [ "$nm" = 160000 ] || continue/
MEOF
  # the five eq-site-*-aborts claims (round 10, review N5): `continue` (real) versus `return 1` (mutant) at a refusal site
  # whose condition is global to every candidate row gives the same EXIT code, so these are exit-equivalence claims. They
  # are NOT message-equivalent in general: with `continue` the FAIL line shows the WHY of the LAST candidate row, with
  # `return 1` the WHY of the row at this site, so the text differs when a later row fails a different check. Each probe
  # uses two rows that both reach the site, so it compares the exit code and the site's message count, not other text.
  eqp eq-site-merge-aborts pr_merge <<'MEOF'
s/commit the rollback on its own"; continue; }/commit the rollback on its own"; return 1; }/
--
/a waiver is valid only in a single-parent commit/d
MEOF
  eqp eq-site-ident-aborts pr_ident <<'MEOF'
s/unresolvable; cannot check authoriser"; continue; }/unresolvable; cannot check authoriser"; return 1; }/
--
/committer or author identity unresolvable/d
MEOF
  eqp eq-site-nopy-aborts pr_nopy <<'MEOF'
s/python3 missing; cannot check authoriser"; continue; }/python3 missing; cannot check authoriser"; return 1; }/
--
/python3 missing; cannot check authoriser/d
MEOF
  eqp eq-site-spent-aborts pr_spent <<'MEOF'
s/(a row waives one commit only)" ;;/(a row waives one commit only)"; return 1 ;;/
--
s/      0) spent "\$1" "\$2" "\$3"; case \$? in/      0) case 1 in/
MEOF
  eqp eq-site-cannottell-aborts pr_cannottell <<'MEOF'
s/cannot prove the row is unspent" ;;/cannot prove the row is unspent"; return 1 ;;/
--
s/^           \*) WHY="\$SPENT; cannot prove the row is unspent" ;;/           *) return 0 ;;/
MEOF
  wait
  judge() { # k -> J = killed | survived | inconclusive | none (no result); for an equivalence claim (eq, geneq) both
    # dates count (round 9, F2): none or inconclusive under either is that, killed under either is killed. JD names both.
    local J1 J2; if [ ! -s "$tmp/j$1.res" ]; then J1=none; else J1="$(jv "$gotf" "$(cat "$tmp/j$1.res")")"; fi; J="$J1"; JD="$J1"
    case "${mkind[$1]:-}" in eq|geneq) [ -n "$altd" ] || return 0
      if [ ! -s "$tmp/j$1.alt.res" ]; then J2=none; else J2="$(jv "$gotaf" "$(cat "$tmp/j$1.alt.res")")"; fi
      JD="pinned date $J1, alternative date $J2"
      case "$J1/$J2" in none/*|*/none) J=none ;; inconclusive/*|*/inconclusive) J=inconclusive ;; killed/*|*/killed) J=killed ;; *) J=survived ;; esac ;;
    esac; }
  # unit check of the judge (R7-7): equal dates and vectors -> survived; another vector -> killed; another day, or a
  # job that crossed midnight -> inconclusive (never killed); a result without a stamp -> inconclusive
  jvu="$(jv 'A=1 DATE=2026-01-01~2026-01-01' 'A=1 DATE=2026-01-01~2026-01-01'),$(jv 'A=1 DATE=2026-01-01~2026-01-01' 'A=2 DATE=2026-01-01~2026-01-01'),$(jv 'A=1 DATE=2026-01-01~2026-01-01' 'A=2 DATE=2026-01-02~2026-01-02'),$(jv 'A=1 DATE=2026-01-01~2026-01-01' 'A=1 DATE=2026-01-01~2026-01-02'),$(jv 'A=1 DATE=2026-01-01~2026-01-02' 'A=1 DATE=2026-01-01~2026-01-02'),$(jv 'A=1 DATE=2026-01-01~2026-01-01' 'A=1')"
  if [ "$jvu" = survived,killed,inconclusive,inconclusive,inconclusive,inconclusive ]; then echo "ok   judge unit check: $jvu"
  else echo "BAD  judge unit check: $jvu"; bad=1; fi
  inc=()
  for ((k=1; k<=n; k++)); do
    [ -n "${mnames[k]:-}" ] && [ "${mkind[k]:-}" != dateskew ] && [ "${mkind[k]:-}" != resfault ] || continue
    judge "$k"; [ "$J" = inconclusive ] && inc+=("$k")
  done
  if [ "${#inc[@]}" -gt 0 ]; then # the date changed: recompute the real vector, re-run only those jobs (once)
    echo "note ${#inc[@]} job(s) INCONCLUSIVE (another date than the real gate's vector, or a resource failure: $(ls "$tmp"/j*.resfail 2>/dev/null | wc -l) result file(s)); recomputing it and re-running them"
    for f in "$tmp"/j*.resfail; do [ -e "$f" ] && echo "note   ${f##*/}: $(cat "$f")"; done
    rsafe classify "$gate"; gotf="$RS"; got="$(vec "$gotf")"; if [ -n "$altd" ]; then rsafe altclassify "$gate"; gotaf="$RS"; fi
    for k in "${inc[@]}"; do launch "$k"; done; wait
  fi
  : >"$tmp/dirs.tsv"; nk=0; ns=0; ne=0; ni=0; gsurv=()
  for ((k=1; k<=n; k++)); do
    [ -n "${mnames[k]:-}" ] || continue
    judge "$k"
    if [ "${mkind[k]:-}" = dateskew ]; then
      if [ "$J" = inconclusive ]; then echo "ok   date self-test: a job one day behind is INCONCLUSIVE (never killed)"
      else echo "BAD  date self-test: a job one day behind was judged $J"; bad=1; fi
      continue
    fi
    if [ "${mkind[k]:-}" = resfault ]; then
      if [ "$J" = inconclusive ] && [ -e "$tmp/j$k.res.resfail" ]; then echo "ok   resource self-test: a job with a refused fork is INCONCLUSIVE (never killed): $(cat "$tmp/j$k.res.resfail")"
      else echo "BAD  resource self-test: a job with a refused fork was judged $J"; bad=1; fi
      continue
    fi
    case "$J" in
      none) echo "BAD  mutant ${mnames[k]} produced no vector ($JD)"; bad=1 ;;
      inconclusive) echo "BAD  mutant ${mnames[k]} still INCONCLUSIVE after a re-run ($(stamp "$(cat "$tmp/j$k.res")") vs $(stamp "$gotf")$(cat "$tmp/j$k.res.resfail" "$tmp/j$k.alt.res.resfail" 2>/dev/null | sed 's/^/; resource failure: /' | tr -d '\n'))"; bad=1; ni=$((ni+1)) ;;
      survived) if [ "${mkind[k]:-}" = geneq ]; then echo "ok   generated member ${mnames[k]} survives: claimed equivalent by proof ${geneqp[k]} (checked below)"; gsurv+=("$k")
                elif [ "${mkind[k]:-}" = eq ]; then echo "ok   eqproof ${mnames[k]}: whole-suite vector equals the real gate's"
                else echo "BAD  mutant ${mnames[k]} SURVIVED"; bad=1; ns=$((ns+1)); fi ;;
      killed) if [ "${mkind[k]:-}" = geneq ]; then echo "BAD  generated member ${mnames[k]} is claimed equivalent (${geneqp[k]}) but the suite kills it ($JD)"; bad=1
              elif [ "${mkind[k]:-}" = eq ]; then echo "BAD  eqproof ${mnames[k]}: the suite kills it, so it is NOT equivalent ($JD)"; bad=1
              else echo "ok   mutant ${mnames[k]} killed"; nk=$((nk+1)); fi ;;
    esac
    case "$J" in killed|survived) printf '%s\t%s\n' "${mnames[k]}" "$(vdir "$got" "$(vec "$(cat "$tmp/j$k.res")")")" >>"$tmp/dirs.tsv" ;; esac # directions: pinned date
  done
  # differential proof of every equivalence claim (targeted probe on real / equivalent / control gates); the three
  # probe runs are repeated once if the date changed between them (R7-7). Round 9 (F2): the probe triple runs under the
  # pinned date AND the alternative date, and the claim holds only when it holds under both (and the job survived both)
  : >"$tmp/eqok"
  for ((q=1; q<=eqn; q++)); do
    [ -n "${mnames[${eqk[q]}]:-}" ] || continue
    for _ in 1 2; do t0="$(date +%F)"; setdates
      prf=0; rsafe "${eqprobe[q]}" "$gate"; pa="$RS"; prf=$((prf|RSF)); rsafe "${eqprobe[q]}" "${eqfile[q]}"; pb="$RS"; prf=$((prf|RSF))
      rsafe "${eqprobe[q]}" "${eqctl[q]}"; pc="$RS"; prf=$((prf|RSF))
      if [ -n "$altd" ]; then altprobe() { PATH="$altp" "$@"; }
        rsafe altprobe "${eqprobe[q]}" "$gate"; qa="$RS"; prf=$((prf|RSF)); rsafe altprobe "${eqprobe[q]}" "${eqfile[q]}"; qb="$RS"; prf=$((prf|RSF))
        rsafe altprobe "${eqprobe[q]}" "${eqctl[q]}"; qc="$RS"; prf=$((prf|RSF))
      else qa=x; qb=x; qc=y; fi
      [ "$(date +%F)" = "$t0" ] && break; done
    judge "${eqk[q]}"
    if [ "$prf" = 0 ] && [ "$(date +%F)" = "$t0" ] && [ -n "$pa" ] && [ "$pa" = "$pb" ] && [ "$pa" != "$pc" ] && [ -n "$qa" ] && [ "$qa" = "$qb" ] && [ "$qa" != "$qc" ] && [ "$J" = survived ]; then
      echo "ok   eqproof ${eqnames[q]}: probe real=eq [$pa]; control differs [$pc]; alternative date: real=eq [$qa], control differs [$qc] ($JD)"; echo "${eqnames[q]}" >>"$tmp/eqok"; ne=$((ne+1))
    else [ "$prf" = 0 ] || echo "BAD  eqproof ${eqnames[q]}: a probe met a resource failure on all 3 tries (not a verdict)"
      echo "BAD  eqproof ${eqnames[q]}: probe real [$pa] eq [$pb] control [$pc]; alternative date real [$qa] eq [$qb] control [$qc] ($JD)"; bad=1; fi
  done
  for k in "${gsurv[@]}"; do # a generated member claimed equivalent counts only when its proof passed
    if grep -qx -- "${geneqp[k]}" "$tmp/eqok"; then ne=$((ne+1)); else echo "BAD  generated member ${mnames[k]}: its proof ${geneqp[k]} did not pass"; bad=1; fi
  done
  [ -n "${MUT_ONLY:-}" ] || # every row of the generated equivalence map must name a generated member and a registered proof (no dead claims)
  while IFS=$'\t' read -r gname gproof _; do case "$gname" in ''|'#'*) continue ;; esac
    grep -q "^$gname"$'\t' "$gled" || { echo "BAD  members_eq row $gname names no generated member"; bad=1; }
    printf '%s\n' "${eqnames[@]}" | grep -qx -- "$gproof" || { echo "BAD  members_eq row $gname names an unregistered proof $gproof"; bad=1; }
  done <"$here/cm_submodule_pin_not_downgraded_members_eq.tsv"
  echo "mutants: $n (killed $nk, survived $ns, equivalent-with-proof $ne, inconclusive $ni)"
  if [ -z "${MUT_ONLY:-}" ]; then
    lint dynamic "$tmp/dirs.tsv" "$tmp/eqok" || bad=1
    # control needle for the dynamic lint's own zero (R7-4): every mutant observed only as `ch` must leave fo / fr needs
    # unmet (DYN ... need findings), and an empty directions file must be BLIND
    cut -f1 "$tmp/dirs.tsv" | sed 's/$/\tch/' >"$tmp/dirs.ch"; : >"$tmp/dirs.empty"
    lo="$(lint dynamic "$tmp/dirs.ch" "$tmp/eqok" 2>&1)"; lrc=$?; lo2="$(lint dynamic "$tmp/dirs.empty" "$tmp/eqok" 2>&1)"; lrc2=$?
    if [ "$lrc" = 1 ] && grep -q 'DYN I[0-9a-z]*: need \(fo\|fr\|both\), observed ch' <<<"$lo" && [ "$lrc2" = 1 ] && grep -q 'DYN BLIND' <<<"$lo2"; then
      echo "ok   dynamic lint control needle: all-ch directions refused ($(grep -c 'BAD  lint DYN' <<<"$lo") findings), empty is BLIND"
    else echo "BAD  dynamic lint control needle: all-ch rc $lrc, empty rc $lrc2"; bad=1; fi
    # round 11: every mutant a data row of the site table names was killed (or its proof passed); needle: an empty
    # directions file is BLIND
    s11lint dynamic "$tmp/dirs.tsv" "$tmp/eqok" || bad=1
    lo="$(s11lint dynamic "$tmp/dirs.empty" "$tmp/eqok" 2>&1)"; lrc=$?
    if [ "$lrc" = 1 ] && grep -q 'DYN BLIND' <<<"$lo"; then echo "ok   dynamic site lint control needle: empty directions are BLIND"
    else echo "BAD  dynamic site lint control needle: rc $lrc"; bad=1; fi
  fi
fi
# ── Part 3: the hook end to end, hook copied next to the gate under test ─────
lay="$tmp/lay"; mkdir -p "$lay/scripts/gates" "$lay/scripts/hooks"
cp "$gate" "$lay/scripts/gates/cm_submodule_pin_not_downgraded.sh"; cp "$hook" "$lay/scripts/hooks/pre-commit-submodule-pin-not-downgraded"
lhook="$lay/scripts/hooks/pre-commit-submodule-pin-not-downgraded"
hk() { git -C "$1" commit -q -m hk >"$tmp/hout" 2>&1; echo $?; }
inst() { ln -s "$lhook" "$1/.git/hooks/pre-commit"; }
mk;r=$R; inst "$r"; stage "$r" "$A"; d1=$(hk "$r")
mk;r=$R; inst "$r"; stage "$r" "$A"; git -C "$r" commit -q --no-verify -m down; stage "$r" "$B"; f1=$(hk "$r"); stage "$r" "$A"; d2=$(hk "$r")
# a linked worktree with a REAL submodule (git submodule add + submodule update --init inside the worktree)
up="$tmp/up"; git init -q "$up"; for i in A M B; do git -C "$up" commit -q --allow-empty -m "$i"; done
uA=$(git -C "$up" rev-parse HEAD~2); uB=$(git -C "$up" rev-parse HEAD)
sup="$tmp/sup"; git init -q "$sup"; git -C "$sup" submodule add -q "file://$up" sub >/dev/null 2>&1; git -C "$sup" commit -q -m base; inst "$sup"
git -C "$sup" worktree add -q -b wtr "$tmp/wtr" 2>/dev/null; git -C "$tmp/wtr" submodule update -q --init 2>/dev/null
wgd="$(git -C "$tmp/wtr/sub" rev-parse --absolute-git-dir)"; case "$wgd" in */.git/worktrees/wtr/modules/sub) wlay=real ;; *) wlay="unexpected:$wgd" ;; esac
git -C "$tmp/wtr/sub" checkout -q "$uA"; git -C "$tmp/wtr" commit -q --no-verify -a -m setup
git -C "$tmp/wtr/sub" checkout -q "$uB"; wf1=$(git -C "$tmp/wtr" commit -q -a -m fwd >"$tmp/hout" 2>&1; echo $?)
git -C "$tmp/wtr/sub" checkout -q "$uA"; wd1=$(git -C "$tmp/wtr" commit -q -a -m down >"$tmp/hout" 2>&1; echo $?)
# R2-I1 replay through the hook: reviewed rollback with waiver, re-advance, then a snapshot commit -a over the stale
# checkout that stages only `notes` must be refused (the row is bound to an earlier parent)
up2="$tmp/up2"; git init -q "$up2"; for i in A B; do git -C "$up2" commit -q --allow-empty -m "$i"; done
pA=$(git -C "$up2" rev-parse HEAD~1); pB=$(git -C "$up2" rev-parse HEAD)
ps="$tmp/ps"; git init -q "$ps"; git -C "$ps" submodule add -q "file://$up2" sub >/dev/null 2>&1; echo 0 >"$ps/notes"; git -C "$ps" add notes
git -C "$ps" commit -q -m base; inst "$ps"
git -C "$ps/sub" checkout -q "$pA"; wf sub "$pB" "$pA" ops "$d10" CON-046 "$(git -C "$ps" rev-parse HEAD)" >"$ps/.submodule_pin_waivers"; git -C "$ps" add .submodule_pin_waivers
p1=$(git -C "$ps" commit -q -a -m rollback >"$tmp/hout" 2>&1; echo $?)
git -C "$ps/sub" checkout -q "$pB"; p2=$(git -C "$ps" commit -q -a -m fwd >"$tmp/hout" 2>&1; echo $?)
git -C "$ps/sub" checkout -q "$pA"; echo 1 >"$ps/notes"; p3=$(git -C "$ps" commit -q -a -m snapshot >"$tmp/hout" 2>&1; echo $?)
ppin="$(git -C "$ps" ls-tree HEAD -- sub | awk '{print $3}')"; if [ "$ppin" = "$pB" ]; then pkept=B; else pkept=A; fi
# layout SKIP: hook copied somewhere without ../gates
mkdir -p "$tmp/lonely"; cp "$hook" "$tmp/lonely/pre-commit"; mk;r=$R; echo y >"$r/doc"; git -C "$r" add doc
( cd "$r" && bash "$tmp/lonely/pre-commit" >"$tmp/lout" 2>&1 ); lr=$?
echo "hook: plain downgrade rc=$d1 forward rc=$f1 downgrade-after rc=$d2 ; real-submodule worktree ($wlay) forward rc=$wf1 downgrade rc=$wd1 ; persist rollback rc=$p1 fwd rc=$p2 snapshot rc=$p3 pin=$pkept ; layout-skip rc=$lr [$(head -c 80 "$tmp/lout")]"
if [ "$d1" != 0 ] && [ "$f1" = 0 ] && [ "$d2" != 0 ] && [ "$wlay" = real ] && [ "$wf1" = 0 ] && [ "$wd1" != 0 ] \
  && [ "$p1" = 0 ] && [ "$p2" = 0 ] && [ "$p3" != 0 ] && [ "$pkept" = B ] && [ "$lr" = 0 ] && grep -q SKIP "$tmp/lout"; then :
else echo "BAD  hook end-to-end"; bad=1; fi
exit "$bad"
