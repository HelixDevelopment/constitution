#!/usr/bin/env bash
# tests/release/test_derive_release_facts.sh — hermetic test of scripts/release/derive_release_facts.sh.
# Real git and real sqlite3; the oracle is a fixture tracker whose expected facts are written by hand
# below (never computed by the script under test). Exit 0 when every case passes; "RESULT: pass=N fail=M".
set -u
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
# round 6 (K3): the release scripts pass an allow-listed environment to their children; the state-file
# variables of the test doubles are added to that list here (rc_env_lockdown refuses credential-like names)
# round 11: RELEASE_ENV_KEEP reaches LOCAL children only (sqlite3 here); git runs through rc_net with the fixed
# network allow-list, so the git double reads MSEEN from the file .stubenv next to itself
export RELEASE_ENV_KEEP="MSEEN READY"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
S="${DRF_SCRIPT:-$ROOT/scripts/release/derive_release_facts.sh}"
pass=0; fail=0
ok(){ pass=$((pass+1)); echo "PASS $*"; }; bad(){ fail=$((fail+1)); echo "FAIL $*"; }
. "$HERE/env_allow.sh"   # round 7: the allow-list, the dirty environment and the SIGHUP detector of the L1 L2 L4 cases
skipped=0; skp(){ skipped=$((skipped+1)); echo "SKIP $*"; }
HUPWHY="SIGHUP is ignored in this process (nohup or an ignoring parent): bash cannot trap a signal that was ignored when it started, so the case would test the caller's signal state, not the script (round 7, L4)"
case "$(hup_control)" in ok) ok "L4 the SIGHUP detector sees an ignored and a not ignored SIGHUP (control needles)" ;;
  ok-positive-only) ok "L4 the SIGHUP detector sees an ignored SIGHUP (control needle; the negative needle cannot run: SIGHUP is ignored here)" ;;
  *) bad "L4 the SIGHUP detector is blind: $(hup_control)" ;; esac
W="$(mktemp -d "${TMPDIR:-/tmp}/drf_test.XXXXXX")"; : "${W:?}"
cleanup(){ [ -n "${W:-}" ] && [ -d "$W" ] && . "$ROOT/scripts/lib/safe_rm.sh" 2>/dev/null && safe_rm_rf "$W" 2>/dev/null; }
trap cleanup EXIT; trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM   # round 7 (L5): a signal ends the suite (the EXIT trap cleans up); a handler that returns would let the suite run on
mkdir -p "$W/tmp"; export TMPDIR="$W/tmp"   # every temp file of the script under test lands here, so leftovers are countable
G=(git -c user.email=t@t -c user.name=t -c init.defaultBranch=main)
R="$W/repo"; "${G[@]}" init -q "$R"; mkdir -p "$R/docs"
DB="$R/docs/workable_items.db"
sqlite3 -bail "$DB" <<'SQL' || { echo "FAIL fixture database could not be built"; exit 1; }
CREATE TABLE items (atm_id TEXT, status TEXT, severity TEXT, current_location TEXT, body_md TEXT,
  reproduction_state TEXT DEFAULT 'UNSET', investigation_state TEXT DEFAULT 'UNSET', closure_date TEXT);
INSERT INTO items VALUES ('T-001','Queued','Low','Issues','plain','UNSET','UNSET',NULL);
INSERT INTO items VALUES ('T-002','Queued','medium','Issues','plain','UNREPRODUCED','not-started',NULL);
INSERT INTO items VALUES ('T-003','Ready for testing','Medium','Issues','x
**Verification:** provisional -- job: j -- due: next full retest','reproduced-live','root-cause-found-with-evidence',NULL);
INSERT INTO items VALUES ('T-004','Ready for testing','High','Issues','x
**Verification:** provisional -- job: j -- due: 2099-01-01','UNSET','UNSET',NULL);
INSERT INTO items VALUES ('T-010','In progress','Medium','Issues','x
**Verification:** provisional -- job: j -- due: 2000-01-01','UNREPRODUCED','not-started',NULL);
INSERT INTO items VALUES ('T-005','Fixed (→ Fixed.md)','Low','Fixed','f','UNSET','UNSET','2001-01-01');
INSERT INTO items VALUES ('T-006','Fixed (→ Fixed.md)','Low','Fixed','f','UNSET','UNSET','2999-01-01');
SQL
( cd "$R" && printf '## Unreleased\n' >CHANGELOG.md && "${G[@]}" add -A && GIT_COMMITTER_DATE=2026-01-02T00:00:00 "${G[@]}" commit -qm a \
  && "${G[@]}" tag -a prev-v1 -m prev && printf 'b\n' >b && "${G[@]}" add b && "${G[@]}" commit -qm b )
# L2 (round 7) the environment of every child is built from the allow-list: entries whose names are not shell
# identifiers, an inherited allexport (SHELLOPTS=allexport, bash -a) and caller token variables reach no child.
# Recorders (env_census.py) read each child's /proc/$$/environ and its open fd 9; control needle: a plain bash
# child of an env -i shell with the dirty entries is a finding for each of them.
SH2="$W/shimL2"; mkdir -p "$SH2"; E2="$W/envL2"
python3 -I "$HERE/env_census.py" mk "$SH2" "$E2" git sqlite3 date mktemp awk sed grep tr cat sort rm chmod >/dev/null
TOB="$(command -v timeout)"; BASHB="$(command -v bash)"   # absolute: the suite's own timeout and bash are not recorded
: >"$E2"; env -i "${ENV_DIRTY[@]}" PATH="$SH2:$PATH" "$BASHB" -c 'git --version >/dev/null; :' </dev/null >/dev/null 2>&1 7</dev/null
o2="$(python3 -I "$HERE/env_census.py" check "$E2" --parent bash --allow PATH PWD SHLVL _ --marker $ENV_MARKERS)"
case "$o2" in
  *"'BAD-NAME'"*"'npm_config_"*) ok "L2 control: the census sees names that are not identifiers" ;; *) bad "L2 control: the census is blind" ;; esac
# round 8 control needles: an LC_ name that is no locale category and an inherited descriptor are findings
case "$o2" in *"'LC_ZZTOKEN' is not on the allow-list"*) ok "L2 control (N1): LC_ZZTOKEN is a finding (no name prefix)" ;; *) bad "L2 control (N1): LC_ZZTOKEN not seen" ;; esac
case "$o2" in *"file descriptor 7 is inherited"*) ok "L2 control (N3): an inherited descriptor is a finding" ;; *) bad "L2 control (N3): the descriptor census is blind" ;; esac
for how in shellopts dasha; do
  : >"$E2"
  if [ "$how" = shellopts ]; then set -- env "${ENV_DIRTY[@]}" SHELLOPTS=allexport "$TOB" 60 "$BASHB" "$S"; else set -- env "${ENV_DIRTY[@]}" "$TOB" 60 "$BASHB" -a "$S"; fi
  OUT="$(cd "$R" && PATH="$SH2:$PATH" XYZ_TOKEN=ZZXYZL2 M3W_GITEA_TOKEN=ZZM3WL2 "$@" --base HEAD --prev-tag prev-v1 --today 2026-06-01 </dev/null 2>&1 7</dev/null)"; RC=$?
  set --
  [ "$RC" -eq 0 ] && ok "L2 $how: the run completes (rc 0)" || bad "L2 $how: rc $RC: $(printf '%s\n' "$OUT" | tail -n 2 | tr '\n' ' ')"
  for c in git sqlite3; do grep -qx "== $c" "$E2" && ok "L2 $how: $c was recorded (control needle)" || bad "L2 $how: $c was recorded (control needle)"; done
  o2="$(python3 -I "$HERE/env_census.py" check "$E2" --allow $ENV_ALLOW $RELEASE_ENV_KEEP --allow-fd 3 4 --marker ZZXYZL2 ZZM3WL2 $ENV_MARKERS --min 3)"; r2=$?
  [ "$r2" -eq 0 ] && ok "L2 $how: no child has a name outside the allow-list, a marker, fd 9 or another inherited descriptor ($(printf '%s\n' "$o2" | tail -n 1))" || bad "L2 $how: $(printf '%s\n' "$o2" | head -n 4 | tr '\n' ' ')"
  # round 11 (rc_net): every git child has only the names of the network allow-list (NET_ALLOW, the test's copy)
  o2="$(python3 -I "$HERE/env_census.py" check "$E2" --cmd git --allow $NET_ALLOW --allow-fd 3 4 --marker ZZXYZL2 ZZM3WL2 $ENV_MARKERS --min 3)"; r2=$?
  [ "$r2" -eq 0 ] && ok "L2 $how: every git child has only the network allow-list ($(printf '%s\n' "$o2" | tail -n 1))" || bad "L2 $how net: $(printf '%s\n' "$o2" | head -n 4 | tr '\n' ' ')"
done
# round 9 (F1 F2 of the round-8 review): inherited descriptors of 3, 5 and 6 digits (300, 12345, 100000) reach no
# child either; round 8 closed only numbers of at most four digits. Control needle: the census lists all of them for
# a plain bash child.
if nofile_room; then
  : >"$E2"; env -i PATH="$SH2:$PATH" "$BASHB" -c 'git --version >/dev/null; :' </dev/null >/dev/null 2>&1 7</dev/null 300</dev/null 12345</dev/null 100000</dev/null
  o2="$(python3 -I "$HERE/env_census.py" check "$E2" --parent bash --allow PATH PWD SHLVL _)"
  for d in 7 300 12345 100000; do case "$o2" in *"file descriptor $d is inherited"*) ok "F2 control: descriptor $d is a finding for a plain child" ;; *) bad "F2 control: descriptor $d not seen by the census" ;; esac; done
  : >"$E2"
  OUT="$(cd "$R" && PATH="$SH2:$PATH" "$TOB" 60 "$BASHB" "$S" --base HEAD --prev-tag prev-v1 --today 2026-06-01 </dev/null 2>&1 7</dev/null 300</dev/null 12345</dev/null 100000</dev/null)"; RC=$?
  [ "$RC" -eq 0 ] && ok "F1: the run with descriptors 7 300 12345 100000 completes (rc 0)" || bad "F1: rc $RC: $(printf '%s\n' "$OUT" | tail -n 2 | tr '\n' ' ')"
  grep -qx "== git" "$E2" && ok "F1: git was recorded (control needle)" || bad "F1: git was recorded (control needle)"
  o2="$(python3 -I "$HERE/env_census.py" check "$E2" --allow $ENV_ALLOW $RELEASE_ENV_KEEP --allow-fd 3 4 --min 3)"; r2=$?
  [ "$r2" -eq 0 ] && ok "F1: no child of the derive script inherits a descriptor of 1, 3, 5 or 6 digits ($(printf '%s\n' "$o2" | tail -n 1))" || bad "F1: $(printf '%s\n' "$o2" | grep FINDING | sort -u | head -n 4 | tr '\n' ' ')"
else skp "F1 F2 descriptors of 5 and 6 digits: $NOFILE_WHY"; fi
OUT="$(cd "$R" && bash "$S" --base HEAD --prev-tag prev-v1 --today 2026-06-01 2>&1)"; RC=$?
has(){ if printf '%s\n' "$OUT" | grep -qxF -- "$2"; then ok "$1"; else bad "$1 (missing line: $2)"; fi; }
[ "$RC" = 0 ] && ok "exit 0" || bad "exit 0 (got $RC)"
has "commit count" "commits_since_prev=1"
has "items total" "items_total=7"
has "open count" "items_open=5"
has "status Ready ids" "open_status_ids[Ready for testing]=T-003 T-004"
has "severity case-folded" "open_severity[medium]=3"
has "severity ids" "open_severity_ids[medium]=T-002 T-003 T-010"
has "raw spellings kept" "open_severity_raw_spellings=High Low Medium medium"
has "states count" "open_states[UNREPRODUCED/not-started]=2"
has "states ids" "open_states_ids[UNREPRODUCED/not-started]=T-002 T-010"
has "UNSET counted, not listed" "open_states[UNSET/UNSET]=2"
has "any-state count" "open_items_with_any_state=3"
printf '%s\n' "$OUT" | grep -q '^open_states_ids\[UNSET/UNSET\]' && bad "UNSET/UNSET ids not listed" || ok "UNSET/UNSET ids not listed"
has "provisional ids" "provisional_ids=T-003 T-004 T-010"
has "overdue: undated and past-dated, not future" "overdue_ids=T-003 T-010"
has "verified after prev tag date only" "verified_since_prev_ids=T-006"
has "count line" "count_line=1 verified + 3 provisional (2 overdue)"
# control needles (§11.4.273): a present id is found by the same path, a fabricated id is not
printf '%s\n' "$OUT" | grep -q 'T-004' && ok "positive control T-004 present" || bad "positive control T-004 present"
printf '%s\n' "$OUT" | grep -q 'T-999' && bad "negative control T-999 absent" || ok "negative control T-999 absent"
# missing data fails closed (exit 3), never a partial set of facts
( cd "$R" && bash "$S" --base HEAD --prev-tag no-such-tag >/dev/null 2>&1 ); [ $? = 3 ] && ok "unknown tag exits 3" || bad "unknown tag exits 3"
# a value with a quote must neither break nor alter any query (no DB value is put back into SQL)
sqlite3 -bail "$DB" "INSERT INTO items VALUES ('T-011','Queued','x''y) or 1 --','Issues','plain','UN''SET','not-started',NULL);" \
  || { echo "FAIL quote fixture could not be built"; exit 1; }
( cd "$R" && "${G[@]}" add -A && "${G[@]}" commit -qm quote )
OUT="$(cd "$R" && bash "$S" --base HEAD --prev-tag prev-v1 --today 2026-06-01 2>&1)"; RC=$?
[ "$RC" = 0 ] && ok "quote value: exit 0" || bad "quote value: exit 0 (got $RC)"
has "quote severity counted" "open_severity[x'y) or 1 --]=1"
has "quote severity ids exact" "open_severity_ids[x'y) or 1 --]=T-011"
has "quote state ids exact" "open_states_ids[UN'SET/not-started]=T-011"
has "other severity unchanged" "open_severity_ids[medium]=T-002 T-003 T-010"
has "quote: open count" "items_open=6"
printf '%s\n' "$OUT" | grep -qi 'error\|parse' && bad "no sqlite error printed" || ok "no sqlite error printed"
# round 3 (review of f4c6e8ab, N4): a value that becomes part of a KEY may not hold "=", "[" or "]": a reader splitting
# KEY=VALUE at the first "=" would read another key (the quote case above used "1=1" until round 3). Refused, exit 3,
# nothing printed; then the fixture is put back.
sqlite3 -bail "$DB" "UPDATE items SET severity='a=b' WHERE atm_id='T-011'" && ( cd "$R" && "${G[@]}" commit -qam eqkey )
EOUT="$(cd "$R" && bash "$S" --base HEAD --prev-tag prev-v1 --today 2026-06-01 2>"$W/eqerr")"; ERC=$?
[ "$ERC" = 3 ] && [ -z "$EOUT" ] && grep -q 'or (in a key) \[, \] or =' "$W/eqerr" && ok "N4: a severity holding = is refused as a key (exit 3, nothing printed)" \
  || bad "N4: a severity holding = is refused as a key (rc $ERC: $(head -c 300 "$W/eqerr"))"
sqlite3 -bail "$DB" "UPDATE items SET severity='x''y) or 1 --' WHERE atm_id='T-011'" && ( cd "$R" && "${G[@]}" commit -qam eqkey-back )
# CON-227 (review mutants D1, D5). D5: an item with UNSET reproduction and a SET investigation state
# counts as an item with a state. D1: an item closed ON the previous tag's date (2026-01-02) is NOT
# verified since that tag: the tag date has day granularity only, so a same-day closure cannot be
# shown to postdate the tag and is left out (the rule of the script's header: "after the previous
# tag's date"; whether that day should count is UNCONFIRMED as an operator decision, the test pins
# the stated rule).
sqlite3 -bail "$DB" "INSERT INTO items VALUES ('T-012','Queued','Low','Issues','plain','UNSET','in-progress',NULL);
INSERT INTO items VALUES ('T-013','Fixed (→ Fixed.md)','Low','Fixed','f','UNSET','UNSET','2026-01-02');" \
  || { echo "FAIL boundary fixture could not be built"; exit 1; }
( cd "$R" && "${G[@]}" add -A && "${G[@]}" commit -qm boundary )
OUT="$(cd "$R" && bash "$S" --base HEAD --prev-tag prev-v1 --today 2026-06-01 2>&1)"; RC=$?
[ "$RC" = 0 ] && ok "boundary: exit 0" || bad "boundary: exit 0 (got $RC)"
has "boundary: tag date is the fixture's" "prev_tag_date=2026-01-02"
has "D5: UNSET reproduction with a set investigation state counts" "open_items_with_any_state=5"
has "D1: closed on the tag date is not verified since it" "verified_since_prev_ids=T-006"
has "D1: count line" "count_line=1 verified + 3 provisional (2 overdue)"
# round 9 (F6 of the round-8 review): a remote with no refs gives the ref loop one empty line; it must be skipped,
# never counted as "B..HEAD" (with the base behind HEAD that count is not 0). Control needle: a real ref of another
# remote at HEAD is counted.
( cd "$R" && "${G[@]}" update-ref refs/remotes/rv9/feat HEAD )
OUT="$(cd "$R" && bash "$S" --base HEAD~1 --prev-tag prev-v1 --today 2026-06-01 --remotes "rnone9 rv9" 2>&1)"; RC=$?
[ "$RC" = 0 ] && ok "F6: exit 0" || bad "F6: exit 0 (got $RC: $(printf '%s\n' "$OUT" | tail -n 1))"
has "F6: a remote with no refs has no unmerged ref" "unmerged_refs_count[rnone9]=0"
has "F6: a remote with no refs lists nothing" "unmerged_refs[rnone9]="
has "F6: a real unmerged ref is counted (control needle)" "unmerged_refs_count[rv9]=1"
has "F6: a real unmerged ref is listed with its count (control needle)" "unmerged_refs[rv9]=feat:1"
( cd "$R" && "${G[@]}" update-ref -d refs/remotes/rv9/feat )
# CON-228: a tracker missing a column the queries need fails closed: exit 3 and NO facts on stdout.
# One fixture per missing column, so each query wrapper is covered alone: closure_date is read only
# through q(), body_md only through qa(), reproduction_state through both.
nm=0
for col in reproduction_state closure_date body_md; do
  nm=$((nm+1)); M="$W/mrepo$nm"; "${G[@]}" init -q "$M"; mkdir -p "$M/docs"
  cols="atm_id TEXT, status TEXT, severity TEXT, current_location TEXT, body_md TEXT, reproduction_state TEXT, investigation_state TEXT, closure_date TEXT"
  cols="$(printf '%s' "$cols" | sed "s/, $col TEXT//")"
  sqlite3 -bail "$M/docs/workable_items.db" "CREATE TABLE items ($cols); INSERT INTO items (atm_id,status,severity,current_location) VALUES ('T-001','Queued','Low','Issues');" \
    || { echo "FAIL missing-column fixture ($col) could not be built"; exit 1; }
  ( cd "$M" && printf '## Unreleased\n' >CHANGELOG.md && "${G[@]}" add -A && "${G[@]}" commit -qm a && "${G[@]}" tag -a prev-v1 -m prev )
  MOUT="$(cd "$M" && bash "$S" --base HEAD --prev-tag prev-v1 --today 2026-06-01 2>"$W/merr")"; MRC=$?
  [ "$MRC" = 3 ] && ok "CON-228 [$col]: missing column exits 3" || bad "CON-228 [$col]: missing column exits 3 (got $MRC)"
  [ -z "$MOUT" ] && ok "CON-228 [$col]: no partial facts on stdout" || bad "CON-228 [$col]: no partial facts on stdout (got $(printf '%s\n' "$MOUT" | wc -l) lines)"
  grep -q 'query failed' "$W/merr" && ok "CON-228 [$col]: the refusal is named on stderr" || bad "CON-228 [$col]: the refusal is named on stderr"
done
# round 3 (review of f4c6e8ab): every column q() reads is now also read by a qa() query and the other way round (the
# separator check reads the bodies through q()), so a missing column no longer covers one wrapper alone (it covered
# mutants O4 and O7 of test_release_tooling_mutations.sh). Fault injection instead (gate-logic test, section
# 11.4.289(C)(2)): a sqlite3 on PATH that fails every call of one wrapper (q(): no -ascii; qa(): -ascii) and runs the
# real sqlite3 for the other. Each run must fail closed AND name the tracker query.
qreal="$(command -v sqlite3)"
for qn in q qa; do
  QS="$W/qshim_$qn"; mkdir -p "$QS"
  if [ "$qn" = q ]; then qcase='*" -ascii "*) exec "%s" "$@" ;;'; else qcase='*" -ascii "*) ;; *) exec "%s" "$@" ;;'; fi
  printf "#!/bin/sh\ncase \" \$* \" in $qcase esac\necho \"Error: injected $qn() failure\" >&2\nexit 1\n" "$qreal" >"$QS/sqlite3"; chmod 755 "$QS/sqlite3"
  QOUT="$(cd "$R" && PATH="$QS:$PATH" bash "$S" --base HEAD --prev-tag prev-v1 --today 2026-06-01 2>"$W/qerr")"; QRC=$?
  [ "$QRC" = 3 ] && [ -z "$QOUT" ] && grep -q 'tracker query failed' "$W/qerr" && ok "$qn() failure alone: exit 3, nothing printed, named as a tracker query" \
    || bad "$qn() failure alone: exit 3, nothing printed, named (rc $QRC, $(printf '%s\n' "$QOUT" | wc -l) lines: $(head -c 200 "$W/qerr"))"
  grep -q "injected $qn() failure" "$W/qerr" && ok "$qn() failure alone: the shim was reached (control needle)" || bad "$qn() failure alone: the shim was not reached (instrument blind)"
done
# F6: a base without CHANGELOG.md fails closed (exit 3, empty stdout, named)
N="$W/nochg"; "${G[@]}" init -q "$N"; mkdir -p "$N/docs"; cp -- "$DB" "$N/docs/workable_items.db"
( cd "$N" && "${G[@]}" add -A && "${G[@]}" commit -qm a && "${G[@]}" tag -a prev-v1 -m prev )
NOUT="$(cd "$N" && bash "$S" --base HEAD --prev-tag prev-v1 --today 2026-06-01 2>"$W/nerr")"; NRC=$?
[ "$NRC" = 3 ] && ok "F6: no CHANGELOG.md at the base exits 3" || bad "F6: no CHANGELOG.md at the base exits 3 (got $NRC)"
[ -z "$NOUT" ] && ok "F6: no partial facts on stdout" || bad "F6: no partial facts on stdout"
# G5: the script's OWN message (git's own "path 'CHANGELOG.md' does not exist" must not satisfy this) and not the tracker-query text
grep -q '^derive_release_facts: CHANGELOG.md is missing at the base ' "$W/nerr" && ok "F6: the refusal is the script's own line naming CHANGELOG.md" || bad "F6: the refusal is the script's own line naming CHANGELOG.md"
grep -q 'tracker query failed' "$W/nerr" && bad "F6: the refusal does not blame a tracker query" || ok "F6: the refusal does not blame a tracker query"
# G1-class (round 3): stderr of an external command that is not an error is still redacted when it is printed
# (exit-time flush): a git double warns with an unredacted URL (raw @ in the password) on rev-list and runs the real git
mkdir -p "$W/gitbin"; REALGIT="$(command -v git)"
printf '#!/bin/sh\nfor a in "$@"; do [ "$a" = rev-list ] && { echo "warning: https://u:ZZDRFSECRET@ZZRAWAT@h.invalid/x" >&2; break; }; done\nexec "%s" "$@"\n' "$REALGIT" >"$W/gitbin/git"; chmod +x "$W/gitbin/git"
GOUT="$(cd "$R" && PATH="$W/gitbin:$PATH" bash "$S" --base HEAD --prev-tag prev-v1 2>"$W/gerr")"; GRC=$?
[ "$GRC" = 0 ] && [ -n "$GOUT" ] && ok "G1-class: a git warning does not fail the run and facts are printed (control)" || bad "G1-class: a git warning does not fail the run (got $GRC)"
grep -q 'https://<redacted>@h.invalid' "$W/gerr" && ok "G1-class: the warning is printed, redacted (positive needle)" || bad "G1-class: the warning is printed, redacted (positive needle)"
grep -q 'ZZDRFSECRET\|ZZRAWAT' "$W/gerr" && bad "G1-class: no secret on stderr" || ok "G1-class: no secret on stderr"
# round 5 (CON-234 class): caller values that can hold a credential are validated and never echoed when invalid
vn=0
for a in "--base https://u:ZZDBASE@h/x --prev-tag prev-v1" "--base HEAD --prev-tag https://u:ZZDPREV@h" "--base HEAD --prev-tag prev-v1 --remotes https://ZZDREM@h/x" "--https://u:ZZDARG@h/x"; do
  vn=$((vn + 1))
  # shellcheck disable=SC2086
  VOUT="$(cd "$R" && bash "$S" $a 2>&1)"; VRC=$?
  [ "$VRC" = 2 ] && ok "V$vn: an invalid caller value is a usage error" || bad "V$vn: an invalid caller value is a usage error (got $VRC)"
  printf '%s\n' "$VOUT" | grep -q 'ZZD' && bad "V$vn: the invalid value is not echoed" || ok "V$vn: the invalid value is not echoed"
done
VOUT="$(cd "$R" && bash "$S" --frobnicate 2>&1)"; printf '%s\n' "$VOUT" | grep -q 'unknown argument: --frobnicate' && ok "V: an option-shaped unknown argument is named (control)" || bad "V: an option-shaped unknown argument is named (control)"
VOUT="$(cd "$R" && bash "$S" --base HEAD~0 --prev-tag prev-v1 --remotes "origin up.stream" 2>&1)"; VRC=$?
[ "$VRC" = 0 ] && ok "V: safe base, tag and remote names are accepted (control)" || bad "V: safe names are accepted (got $VRC)"
# V13 class: the private directory is mode 700 while the script runs (a git double reads it on rev-list)
printf '#!/bin/sh\n. "${0%%/*}/.stubenv"\nfor a in "$@"; do [ "$a" = rev-list ] && { for d in "$TMPDIR"/rf_db.*; do [ -d "$d" ] && stat -c %%a "$d" >>"$MSEEN"; done; break; }; done\nexec "%s" "$@"\n' "$REALGIT" >"$W/gitbin/git"; chmod +x "$W/gitbin/git"
MSEEN="$W/mseen"; : >"$MSEEN"; printf "MSEEN='%s'\n" "$MSEEN" >"$W/gitbin/.stubenv"; ( cd "$R" && PATH="$W/gitbin:$PATH" bash "$S" --base HEAD --prev-tag prev-v1 >/dev/null 2>&1 )
[ -s "$MSEEN" ] && ok "V13: the directory mode is read during the run (control needle)" || bad "V13: the directory mode census is blind"
grep -vqx 700 "$MSEEN" && bad "V13: the private directory is mode 700 ($(sort -u "$MSEEN" | tr '\n' ' '))" || ok "V13: the private directory is mode 700"
# round 6 (X10) SIGTERM and SIGHUP while sqlite3 runs: the run ends through the script's own trap (exit 143 / 129,
# read by python), nothing is left under TMPDIR, the buffered stderr is flushed redacted
mkdir -p "$W/sqbin"; REALSQ="$(command -v sqlite3)"
printf '#!/bin/sh\necho "Error: https://u:ZZSQSECRET@h.invalid/x ZZSQMARK" >&2\n: >"$READY"\nsleep 3\nexec "%s" "$@"\n' "$REALSQ" >"$W/sqbin/sqlite3"; chmod +x "$W/sqbin/sqlite3"
for sg in TERM:143 HUP:129; do
  if [ "${sg%:*}" = HUP ] && hup_ignored; then skp "X10 HUP: $HUPWHY"; continue; fi
  rm -f -- "$W/ready10"
  src="$(cd "$R" && python3 -I - "${sg%%:*}" "$S" "$W/sqbin" "$W/ready10" "$W/sig10.out" <<'PYS'
import os, signal, subprocess, sys, time
sig, s, sh, ready, outf = sys.argv[1:6]
env = dict(os.environ, PATH=sh + ":" + os.environ["PATH"], READY=ready)
with open(outf, "wb") as o:
    p = subprocess.Popen(["bash", s, "--base", "HEAD", "--prev-tag", "prev-v1"], env=env, stdin=subprocess.DEVNULL, stdout=o, stderr=o)
    for _ in range(200):
        if os.path.exists(ready): break
        time.sleep(0.1)
    print("ready" if os.path.exists(ready) else "notready", end=" ")
    p.send_signal(getattr(signal, "SIG" + sig))
    print(p.wait(timeout=60))
PYS
)"
  [ "${src%% *}" = ready ] && ok "X10 ${sg%%:*}: the sqlite3 double ran (control needle)" || bad "X10 ${sg%%:*}: the sqlite3 double never ran"
  [ "${src#* }" = "${sg#*:}" ] && ok "X10 ${sg%%:*}: the run ends through its trap (rc ${src#* })" || bad "X10 ${sg%%:*}: rc ${src#* }, want ${sg#*:}"
  [ "$(find "$W/tmp" -maxdepth 1 -name 'rf_db.*' | wc -l)" = 0 ] && ok "X10 ${sg%%:*}: nothing left under TMPDIR" || bad "X10 ${sg%%:*}: rf_db.* left under TMPDIR"
  grep -q ZZSQMARK "$W/sig10.out" && ok "X10 ${sg%%:*}: the buffered stderr is flushed (positive needle)" || bad "X10 ${sg%%:*}: buffered stderr not flushed"
  grep -q ZZSQSECRET "$W/sig10.out" && bad "X10 ${sg%%:*}: the secret is printed" || ok "X10 ${sg%%:*}: the secret is not printed"
done
# round 6 (K3) a caller's exported *TOKEN* variable reaches no child (git, sqlite3, date): sh doubles record their
# environment (control needle: PATH recorded)
mkdir -p "$W/envbin"; E3="$W/env3"; : >"$E3"
for c in git sqlite3 date; do printf '#!/bin/sh\n{ echo "== %s"; env; } >>"%s"\nexec "%s" "$@"\n' "$c" "$E3" "$(command -v "$c")" >"$W/envbin/$c"; chmod +x "$W/envbin/$c"; done
( cd "$R" && ZZDRF_TOKEN=ZZDRFTOK3 PATH="$W/envbin:$PATH" bash "$S" --base HEAD --prev-tag prev-v1 >/dev/null 2>&1 )
for c in git sqlite3 date; do grep -qx "== $c" "$E3" && ok "K3: $c environment recorded (control needle)" || bad "K3: $c environment census blind"; done
grep -q ZZDRFTOK3 "$E3" && bad "K3: a caller *TOKEN* variable reaches a child of the derive script" || ok "K3: no caller *TOKEN* variable reaches a child of the derive script"
( cd "$R" && "${G[@]}" rm -q docs/workable_items.db && "${G[@]}" commit -qm rmdb )
( cd "$R" && bash "$S" --base HEAD --prev-tag prev-v1 >/dev/null 2>&1 ); [ $? = 3 ] && ok "no tracker exits 3" || bad "no tracker exits 3"
left="$(find "$W/tmp" -maxdepth 1 -name 'rf_db.*' | wc -l)"
[ "$left" = 0 ] && ok "temp files removed" || bad "temp files removed ($left left)"
# positive control: the counter sees a leftover directory of that name (R5: a cleanup that drops the buffered output file leaves one)
mkdir "$W/tmp/rf_db.control"; [ "$(find "$W/tmp" -maxdepth 1 -name 'rf_db.*' | wc -l)" = 1 ] && ok "temp-file counter sees a leftover (control)" || bad "temp-file counter sees a leftover (control)"
# L1 (round 6, K5 class; round 7: rc_env_clean): no external command runs before rc_env_clean in the script under test. The census lint
# runs on this copy; only its order findings count here (the table rows are checked by test_channel_census.sh).
l1t="$(mktemp -d "${TMPDIR:-/tmp}/l1.XXXXXX")"; : "${l1t:?}"
l1o="$(python3 -I "$HERE/channel_census.py" lint "$HERE/channels.tsv" "$S" 2>&1)"
case "$l1o" in *BLIND*|*"CENSUS invocations=0 "*|"") bad "L1 the lint is blind on $(basename "$S")" ;; *) ok "L1 the lint sees $(basename "$S") (control)" ;; esac
l1b="$(printf '%s\n' "$l1o" | grep -E 'before rc_env_clean|never calls rc_env_clean')"
[ -z "$l1b" ] && ok "L1 no external command before rc_env_clean" || bad "L1 external command before rc_env_clean: ${l1b:0:160}"
sed '2i date >/dev/null' "$S" >"$l1t/needle.sh"
python3 -I "$HERE/channel_census.py" lint "$HERE/channels.tsv" "$l1t/needle.sh" 2>&1 | grep -q 'before rc_env_clean: needle.sh:2 date' \
  && ok "L1 needle: a date inserted at line 2 is found" || bad "L1 needle: a date inserted at line 2 is not found"
rm -rf -- "${l1t:?}"
# C53 (round 12, F1 of the round-11 review): the network-spawn gate (tests/release/channel_census.py netgate) over
# this copy of the script and the helper library it loads: every network child goes through rc_net and every command
# is classified by its syntax alone (an unclassified command word is a finding; round 13: not a proof of default
# deny over bash, see test_channel_census.sh part 2c), with an empty PATH (no lookup on the host). A git started any
# other way (command -p git, "git", a redirection before git, /usr/bin/git, an absent program) is a finding here,
# also where the runtime recorders cannot see it (command -p and a path bypass the recorders on PATH). The number of
# network calls through rc_net is a positive needle, and a copy with "command -p git status" appended is a control
# needle that must be a finding.
# Round 13: the gate runs in analyser mode (--pin TABLE --analyser-only; the name list and the awk and sed
# programs of the pin still apply): this suite tests mutated copies, and the byte pin of the real scripts is
# checked by test_channel_census.sh part 2d. The library is copied next to the copy, so the appended line is
# the only finding.
c53py="$(command -v python3)"; c53d="$(mktemp -d "${TMPDIR:-/tmp}/c53.XXXXXX")"; : "${c53d:?}"
o53="$(env -i PATH=/nonexistent LANG=C.UTF-8 "$c53py" -I "$HERE/channel_census.py" netgate --pin "$HERE/netgate_pin.tsv" --analyser-only "$S" "$(dirname "$S")/redact_cut.sh" 2>&1)"; r53=$?
n53="$(printf '%s\n' "$o53" | sed -n 's/^NETGATE .*network_through_rc_net=\([0-9]*\).*/\1/p')"
[ "$r53" -eq 0 ] && ok "C53 netgate: $(basename "$S") and its library start every network child through rc_net, every command classified ($(printf '%s\n' "$o53" | tail -n 1))" \
  || bad "C53 netgate rc=$r53: $(printf '%s\n' "$o53" | grep -E '^FINDING|BLIND' | head -n 3 | tr '\n' ' ')"
[ "${n53:-0}" -ge 10 ] && ok "C53 netgate: ${n53} network calls are seen through rc_net (positive needle)" || bad "C53 netgate: network count ${n53:-none} (blind?)"
mkdir -p -- "$(dirname "$c53d/redact_cut.sh")"; cp -- "$(dirname "$S")/redact_cut.sh" "$c53d/redact_cut.sh"; cp -- "$S" "$c53d/$(basename "$S")"; printf '%s\n' 'command -p git status' >>"$c53d/$(basename "$S")"
o53c="$(env -i PATH=/nonexistent LANG=C.UTF-8 "$c53py" -I "$HERE/channel_census.py" netgate --pin "$HERE/netgate_pin.tsv" --analyser-only "$c53d/$(basename "$S")" "$c53d/redact_cut.sh" 2>&1)"; r53c=$?
[ "$r53c" -eq 1 ] && printf '%s\n' "$o53c" | grep -q "^FINDING builtin command other than command -v NAME: $(basename "$S"):[0-9]* | key=483e5249\$" \
  && printf '%s\n' "$o53c" | grep -q '^NETGATE .* findings=1$' && ok "C53 netgate control needle: a command -p git appended to a copy is the only finding" \
  || bad "C53 netgate control needle: an appended command -p git is not a finding (rc $r53c)"
rm -rf -- "${c53d:?}"
[ "$skipped" -eq 0 ] || echo "SKIPPED: $skipped case(s) did not run (see the SKIP lines); the result does not cover them"
echo "RESULT: pass=$pass fail=$fail"
suite_exit "$fail" "$skipped"   # round 8 (N6): 77 when a case was SKIPPED
