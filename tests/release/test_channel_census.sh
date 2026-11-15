#!/usr/bin/env bash
# tests/release/test_channel_census.sh — the channel census of the release scripts (round 6, structural).
#
# Class (§11.4.289(C)): unit test. Part 1 checks the static instrument (tests/release/channel_census.py) on a
# fixture with known invocations (control needles, both directions). Part 2 runs the lint on the real scripts
# and on mutated copies (a new command, a changed line, a secret channel on the wrong row, a new reference to
# a secret variable, a value outside the vocabulary): each must be a finding. Part 3 runs the publisher and the
# derive script with a recorder in front of every command of the table (real commands behind the recorders,
# a local stub server for the API): every command seen at run time is in the table, and no argv and no
# environment of any child holds the token. Exit 0 when every case passes; prints "RESULT: pass=N fail=M".
set -u
export RELEASE_ENV_KEEP="CEN_LOG"
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
CEN="${CEN_PY:-$HERE/channel_census.py}"; TAB="${CHANNELS_TSV:-$HERE/channels.tsv}"
PIN="${NETGATE_PIN:-$HERE/netgate_pin.tsv}"   # round 13: the byte pin of the network-spawn gate (the first layer)
SCRIPTS=("$ROOT/scripts/release/derive_release_facts.sh" "$ROOT/scripts/release/redact_cut.sh" "$ROOT/scripts/release/tag_and_release.sh" "$ROOT/scripts/release_publish_gitea.sh")
pass=0; fail=0
ok(){ pass=$((pass+1)); echo "PASS $*"; }; bad(){ fail=$((fail+1)); echo "FAIL $*"; }
W="$(mktemp -d "${TMPDIR:-/tmp}/cen_test.XXXXXX")"; : "${W:?}"; SRV=""
cleanup(){ [ -n "$SRV" ] && [ "$SRV" -gt 1 ] && kill "$SRV" 2>/dev/null; [ -n "${W:-}" ] && [ -d "$W" ] && . "$ROOT/scripts/lib/safe_rm.sh" 2>/dev/null && safe_rm_rf "$W" 2>/dev/null; }
trap cleanup EXIT; trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM   # round 7 (L5): a signal ends the suite (the EXIT trap cleans up); a handler that returns would let the suite run on

# ---- part 1: the instrument on a fixture (every line is a control needle) ----
cat >"$W/fix.sh" <<'FIX'
#!/usr/bin/env bash
nt() { timeout -k 1 3 "$@"; }
net() { nt git -c x=1 "$@"; }
curl -q http://h.invalid/a
x="$(nt gh api repos/x --jq .id)"
printf 'q' | sqlite3 db.sqlite
TAG="$TAG" awk 'BEGIN{print}'
y="$(net fetch -q origin)"
FOO=bar git status
if true; then grep -q a b; fi
echo "curl is not run here"
# curl in a comment
z='multi
curl line
jq'
case "$k" in curl|jq) : ;; esac
u="$(uname)"; v="$(date|tr a b)"
case "$1" in -h|--help) sed -n 1p "$0" ;; *) id -u ;; esac
exec -c -a mark "$BASH" "$0" "$@" 9< <(printf x)
exec 9<&-
{ exec 3>/dev/null; } 2>/dev/null
FIX
got="$(python3 "$CEN" list "$W/fix.sh" | cut -f2,3 | tr '\t' ':' | sort -t: -k1,1n | tr '\n' ' ')"
want="2:timeout 3:git 4:curl 5:gh 6:sqlite3 7:awk 8:git 9:git 10:grep 17:date 17:tr 17:uname 18:id 18:sed 19:bash "
[ "$got" = "$want" ] && ok "instrument: the fixture invocations are found exactly (quotes, comments, case patterns, wrappers, exec of \"$BASH\" and exec with redirections only)" || bad "instrument: got '$got' want '$want'"
printf 'echo "%s"\n' '$_rpg_tok' >"$W/sec.sh"
python3 "$CEN" list "$W/sec.sh" | grep -qP '\t-\t' && ok "instrument: a line naming a secret variable is listed (control needle)" || bad "instrument: secret reference not listed"

# ---- part 2: the lint on the real scripts and on mutated copies ----
out="$(python3 "$CEN" lint "$TAB" "${SCRIPTS[@]}")"; rc=$?
[ $rc -eq 0 ] && ok "lint: the table matches the scripts (rc 0)" || bad "lint rc=$rc: $(printf '%s\n' "$out" | head -5)"
n="$(printf '%s\n' "$out" | sed -n 's/^CENSUS invocations=\([0-9]*\).*/\1/p')"
[ "${n:-0}" -ge 100 ] && ok "lint: the census counts $n invocations (positive needle)" || bad "lint: census count ${n:-none}"
mkdir -p "$W/m/release"; mut(){ # NAME SED-ON-PUBLISHER EXPECT [TABLE]
  cp "${SCRIPTS[@]:0:3}" "$W/m/release/"; cp "${SCRIPTS[3]}" "$W/m/"
  sed -i "$2" "$W/m/release_publish_gitea.sh"
  o="$(python3 "$CEN" lint "${4:-$TAB}" "$W/m/release/derive_release_facts.sh" "$W/m/release/redact_cut.sh" "$W/m/release/tag_and_release.sh" "$W/m/release_publish_gitea.sh")"; r=$?
  if [ $r -eq 1 ] && printf '%s\n' "$o" | grep -q "$3"; then ok "lint finds: $1"; else bad "lint misses $1 (rc $r): $(printf '%s\n' "$o" | head -3)"; fi; }
mut "a new command with no row" '$a curl -q http://h.invalid/x' 'no row: release_publish_gitea.sh:.* curl'
mut "a changed line (stale row and no row)" 's/^W="$(mktemp -d /W="$(mktemp -d -q /' 'stale row'
mut "a new reference to the token" '$a echo "$_rpg_tok" >/dev/null' 'secret reference with no secret-ref'
# round 13 (O2 of the round-12 review): a lint finding names its line by key; the text of the line is not printed
mut "a new token line, printed by its key only (O2)" '$a echo "$_rpg_tok" ZZO2LINTTEXT >/dev/null' \
  'secret reference with no secret-ref or allowed row: release_publish_gitea.sh:[0-9]* key=[0-9a-f]\{8\}$'
mut "a new command with no row, printed by its key only (O2)" '$a curl -q http://h.invalid/ZZO2LINTTEXT' \
  'no row: release_publish_gitea.sh:[0-9]* curl key=[0-9a-f]\{8\}$'
mut "a new command fed the token by a pipe" '$a printf %s "$_rpg_tok" | sha256sum' 'no row: release_publish_gitea.sh:.* sha256sum'
mut "an external command before rc_env_clean" '/^rc_env_clean/i : "$(uname)"' 'external command before rc_env_clean'
mut "rc_env_clean removed from the publisher" 's/^rc_env_clean /: rc_env_clean /' 'never calls rc_env_clean'
awk -F '\t' 'BEGIN{OFS="\t"} $1=="tag_and_release.sh" && $2=="git" && !d {$5="allowlist+token"; d=1} {print}' "$TAB" >"$W/t1.tsv"
mut "a secret channel on a row that may not carry it" 's/^$//' 'secret channel env=allowlist+token' "$W/t1.tsv"
awk -F '\t' 'BEGIN{OFS="\t"} $1=="release_publish_gitea.sh" && $2=="jq" && !d {$6="argv-token"; d=1} {print}' "$TAB" >"$W/t2.tsv"
mut "a value outside the vocabulary" 's/^$//' 'is not in the vocabulary' "$W/t2.tsv"
grep -v -P '^release_publish_gitea\.sh\tcurl\t' "$TAB" >"$W/t3.tsv"
mut "the curl row removed (no row, and its token line is unlisted)" 's/^$//' 'no row: release_publish_gitea.sh:.* curl' "$W/t3.tsv"
: >"$W/empty.tsv"; o="$(python3 "$CEN" lint "$W/empty.tsv" "${SCRIPTS[@]}")"; [ $? -eq 2 ] && ok "lint: an empty table is BLIND (rc 2), never clean" || bad "lint: empty table: $o"
# round 11: env 'net-allowlist' exactly on the rows reached through rc_net: a network row marked 'allowlist' is a finding
awk -F '\t' 'BEGIN{OFS="\t"} $1=="tag_and_release.sh" && $2=="git" && $5=="net-allowlist" && !d {$5="allowlist"; d=1} {print}' "$TAB" >"$W/t4.tsv"
mut "a network row not marked net-allowlist" 's/^$//' 'env=allowlist but the command is reached via' "$W/t4.tsv"
# round 12 (F1 of the round-11 review): the lint reads the scripts with the parser of the network-spawn gate, with no
# lookup on the host. A script the parser cannot read is a finding (never a short census), and the lint gives the same
# result with an empty PATH (rounds 6 to 11 kept only the words shutil.which() found on the checking host).
mut "a script the parser cannot read" '$a echo "unterminated' 'parse error'
l12a="$(python3 -I "$CEN" lint "$TAB" "${SCRIPTS[@]}" 2>&1)"; l12ar=$?
l12b="$(env -i PATH=/nonexistent LANG=C.UTF-8 "$(command -v python3)" -I "$CEN" lint "$TAB" "${SCRIPTS[@]}" 2>&1)"; l12br=$?
[ "$l12ar" -eq 0 ] && [ "$l12br" -eq 0 ] && [ -n "$l12a" ] && [ "$l12a" = "$l12b" ] && ok "lint: the same result with the normal PATH and with an empty PATH ($(printf '%s\n' "$l12a" | tail -n 1))" \
  || bad "lint depends on the host PATH (rc $l12ar/$l12br): $(printf '%s\n' "$l12b" | head -n 3 | tr '\n' ' ')"

# ---- part 2b (round 11, R10-1 of the round-10 review): the network-spawn gate (channel_census.py netgate) ----
# Every network child of the release scripts is started through rc_net. Round 13: "netgate --pin TABLE" checks the
# real scripts against the byte pin (tests/release/netgate_pin.tsv: every line of the four files, every site, every
# awk and sed program, every name written) and runs the positive-shape analyser; a fixture is checked by the analyser
# alone (--analyser-only: it is not one of the pinned files). Each fixture below is a control needle that must be a
# finding, the clean fixture and the real scripts must pass, and the number of network calls the gate sees through
# rc_net is a positive needle.
o="$(python3 "$CEN" netgate --pin "$PIN" "${SCRIPTS[@]}")"; r=$?
[ $r -eq 0 ] && ok "netgate: the release scripts start every network child through rc_net (rc 0)" || bad "netgate rc=$r: $(printf '%s\n' "$o" | head -4 | tr '\n' ' ')"
n="$(printf '%s\n' "$o" | sed -n 's/^NETGATE .*network_through_rc_net=\([0-9]*\).*/\1/p')"
[ "${n:-0}" -ge 40 ] && ok "netgate: $n network calls are seen through rc_net (positive needle)" || bad "netgate: network count ${n:-none}"
ng(){ # ng NAME LINE PATTERN: a fixture holding LINE must be a netgate finding matching PATTERN
  printf '#!/usr/bin/env bash\n%s\n' "$2" >"$W/ng.sh"
  o="$(python3 "$CEN" netgate --pin "$PIN" --analyser-only "$W/ng.sh")"; r=$?
  if [ $r -eq 1 ] && printf '%s\n' "$o" | grep -q -- "$3"; then ok "netgate finds: $1"; else bad "netgate misses $1 (rc $r): $(printf '%s\n' "$o" | head -2 | tr '\n' ' ')"; fi; }
ng "a bare git" 'git fetch -q origin' 'network command outside rc_net: ng.sh:2 git'
ng "a bare curl" 'x="$(curl -q http://h.invalid/a)"' 'network command outside rc_net: ng.sh:2 curl'
ng "a bare ssh" 'ssh h.invalid true' 'network command outside rc_net: ng.sh:2 ssh'
ng "git in backticks" 'x=`git rev-parse HEAD`' 'network command outside rc_net: ng.sh:2 git'
ng "git under env" 'env git status' 'interpreter or exec wrapper not on the allow-list: ng.sh:2 env'
ng "git under nice" 'nice git status' 'interpreter or exec wrapper not on the allow-list: ng.sh:2 nice'
ng "bash -c with a quoted git" "bash -c 'git fetch'" 'interpreter or exec wrapper not on the allow-list: ng.sh:2 bash'
ng "a command in a variable" 'G=git; $G fetch' 'expansion in command position'
ng "eval" 'eval "git fetch"' 'builtin eval outside the exact sites of DYN_SITES: ng.sh:2'
ng "an unknown command (default deny)" 'uname -a' 'unclassified command (default deny): ng.sh:2 uname'
ng "awk running a command" "awk 'BEGIN{system(\"id\")}' /dev/null" 'awk that can run a command or is not on the pin: ng.sh:2 (system())'
ng "nt defined without rc_net" $'nt() { timeout -k 1 3 "$@"; }\nnt git fetch' 'network command outside rc_net: ng.sh:2 timeout'
ng "git through an untrusted nt" $'nt() { timeout -k 1 3 "$@"; }\nnt git fetch' 'network command outside rc_net: ng.sh:3 git (via nt)'
printf '#!/usr/bin/env bash\n%s\n' 'nt() { if [ "$H" -eq 1 ]; then rc_net timeout -k 1 3 "$@"; else rc_net "$@"; fi; }' \
  'net() { nt git -c http.lowSpeedLimit=1000 "$@"; }' 'rc_net git status' 'net fetch -q origin' 'x="$(rc_net curl -q u | sed '"'"'s/ $//'"'"')"' >"$W/ngc.sh"
o="$(python3 "$CEN" netgate --pin "$PIN" --analyser-only "$W/ngc.sh")"; r=$?
case "$r:$o" in 0:*"network_through_rc_net=5 findings=0"*) ok "netgate: the clean fixture passes, 5 network calls through rc_net, nt and net (control)" ;; *) bad "netgate clean fixture: rc $r $(printf '%s\n' "$o" | head -3 | tr '\n' ' ')" ;; esac
printf '' >"$W/ngempty.sh"; o="$(python3 "$CEN" netgate --pin "$PIN" --analyser-only "$W/ngempty.sh")"; [ $? -eq 2 ] && ok "netgate: a script with no command is BLIND (rc 2)" || bad "netgate: empty: $o"
# round 13 (O2 of the round-12 review): a finding names its line by the census key (8 hex digits of the sha256 of the
# normalised line), never by its text: the positive needle is the exact finding line with the key, the negative
# needle a fake marker on that line that must not be printed
printf '#!/usr/bin/env bash\n%s\n' 'git fetch ZZO2LINETEXT' >"$W/ngo2.sh"
o="$(python3 "$CEN" netgate --pin "$PIN" --analyser-only "$W/ngo2.sh")"; r=$?
k="$(printf '%s' 'git fetch ZZO2LINETEXT' | sha256sum | cut -c1-8)"
if [ $r -eq 1 ] && printf '%s\n' "$o" | grep -qxF "FINDING network command outside rc_net: ngo2.sh:2 git (via -) | key=$k" \
  && ! printf '%s\n' "$o" | grep -qF ZZO2LINETEXT; then ok "netgate: a finding names its line by key=$k, never by its text (O2)"
else bad "netgate prints the line text or no key (rc $r, marker printed: $(printf '%s\n' "$o" | grep -c ZZO2LINETEXT))"; fi

# ---- part 2c (round 12, F1 of the round-11 review; round 13): the analyser refuses every shape outside its closed
# set, and is the same on every host. Round 13 (F3 of the round-12 review): this is not a proof of default deny over
# bash; the only layer that denies by default is the byte pin of part 2d (the reviewed bytes are the bytes that run) ----
# tests/release/netgate_controls.jsonl holds the control needles of round 12: the 50 fixtures of the round-11 reviewer
# and 88 of the round-12 class inventory (docs/qa/con227_234_2026_11_11/round12/class_inventory.md); round 13 adds
# the 45 oracle fixtures (its 48 oracle cases) and 12 discriminating fixtures of the round-12 reviewer, its own 72
# fixtures and seven NAME_r12shape controls (round-12 pass shapes the positive shape now refuses), 274 in all
# (docs/qa/con227_234_2026_11_11/round13/class_inventory.md). Each control is
# written to NAME.sh in its own directory and run by the analyser (--analyser-only) with an empty PATH (PATH=/nonexistent, so no lookup on the host can
# help or hide anything): a "finding" control must exit 1 with its pattern in the output, a "pass" control must exit
# 0. The SITE census of the real scripts must be the same with the normal PATH and with an empty one, every site must
# carry a class of the closed set, and no site may be a FINDING (the golden-FALSE corpus of the real scripts).
CTL="${NETGATE_CONTROLS:-$HERE/netgate_controls.jsonl}"; PY3="$(command -v python3)"; : "${PY3:?python3 is needed}"
mkdir -p "$W/ctl"
python3 -I -c '
import json, os, sys
n = 0
for line in open(sys.argv[1]):
    r = json.loads(line)
    assert r["want"] in ("finding", "pass") and "\t" not in r["pattern"] and "/" not in r["name"], r["name"]
    d = os.path.join(sys.argv[2], "%03d" % n)
    os.mkdir(d)
    with open(os.path.join(d, r["name"] + ".sh"), "w") as fh:
        fh.write(r["body"])
    print("%s\t%s\t%s\t%s" % (d, r["name"], r["want"], r["pattern"]))
    n += 1
' "$CTL" "$W/ctl" >"$W/ctl.idx"
cn=0; cbad=0; cfind=0; cpass=0
while IFS=$'\t' read -r d name want pat; do
  cn=$((cn+1))
  o="$(env -i PATH=/nonexistent LANG=C.UTF-8 "$PY3" -I "$CEN" netgate --pin "$PIN" --analyser-only "$d/$name.sh" 2>&1)"; r=$?
  if [ "$want" = finding ]; then
    if [ $r -eq 1 ] && [ -n "$pat" ] && printf '%s\n' "$o" | grep -qF -- "$pat"; then cfind=$((cfind+1)); else cbad=$((cbad+1)); bad "netgate control $name: want a finding '$pat', rc $r: $(printf '%s\n' "$o" | head -2 | tr '\n' ' ')"; fi
  else
    if [ $r -eq 0 ]; then cpass=$((cpass+1)); else cbad=$((cbad+1)); bad "netgate control $name: want a pass, rc $r: $(printf '%s\n' "$o" | head -2 | tr '\n' ' ')"; fi
  fi
done <"$W/ctl.idx"
[ "$cn" -ge 274 ] && [ "$cbad" -eq 0 ] && [ "$cfind" -ge 262 ] && [ "$cpass" -ge 12 ] && ok "netgate: $cn control needles with an empty PATH, $cfind findings with their reason and $cpass passes, as expected" || bad "netgate controls: n=$cn findings=$cfind passes=$cpass wrong=$cbad"
s1="$(python3 -I "$CEN" netgate --pin "$PIN" --sites "${SCRIPTS[@]}")"; r1=$?
s2="$(env -i PATH=/nonexistent LANG=C.UTF-8 "$PY3" -I "$CEN" netgate --pin "$PIN" --sites "${SCRIPTS[@]}")"; r2=$?
[ $r1 -eq 0 ] && [ $r2 -eq 0 ] && [ -n "$s1" ] && [ "$s1" = "$s2" ] && ok "netgate: the same SITE census with the normal PATH and with an empty PATH (rc 0 both, deterministic)" || bad "netgate: the census depends on the host PATH (rc $r1/$r2)"
ns="$(printf '%s\n' "$s1" | grep -c '^SITE')"
nf="$(printf '%s\n' "$s1" | awk -F '\t' '$1=="SITE" && $6=="FINDING"' | wc -l)"
nu="$(printf '%s\n' "$s1" | awk -F '\t' '$1=="SITE" && $6 !~ /^(network-through-(rc_net|nt|net)|interpreter-allow-listed|local|local-checked-(awk|sed|sort|sqlite3))$/' | wc -l)"
[ "$ns" -eq 128 ] && [ "$nf" -eq 0 ] && [ "$nu" -eq 0 ] && ok "netgate: the golden-FALSE corpus: 128 sites of the real scripts, every one labelled with a class of the closed set, none a finding" || bad "netgate golden-FALSE: sites=$ns findings=$nf unlabelled=$nu"

# ---- part 2d (round 13, F3 of the round-12 review): the byte pin, the first layer of the network-spawn gate ----
# tests/release/netgate_pin.tsv pins the exact bytes of the four release files: every line (key8 of the normalised
# line and sha16 of its bytes), every invocation site with its class, every awk and sed program (sha256) and every
# name a script writes. "netgate --pin" refuses any difference, so a new or changed line, construct, program, name or
# file is a finding whatever the analyser makes of it. The table is written only by "pin-regen" (refused while the
# analyser has a finding) and must equal what pin-regen writes for the committed scripts; a regeneration is reviewed
# with "pin-diff" (line keys, sites, programs and names, never script text).
pcopy(){ # pcopy DIR: a copy of the four files in the layout of the repository; sets PCS
  mkdir -p "$1/release"; cp "${SCRIPTS[@]:0:3}" "$1/release/"; cp "${SCRIPTS[3]}" "$1/"
  PCS=("$1/release/derive_release_facts.sh" "$1/release/redact_cut.sh" "$1/release/tag_and_release.sh" "$1/release_publish_gitea.sh"); }
pin(){ # pin NAME WANT-RC PATTERN TABLE FILE...: netgate --pin on the files
  local n="$1" want="$2" pat="$3" tab="$4"; shift 4
  o="$(env -i PATH=/nonexistent LANG=C.UTF-8 "$PY3" -I "$CEN" netgate --pin "$tab" "$@" 2>&1)"; r=$?
  if [ "$r" -eq "$want" ] && printf '%s\n' "$o" | grep -qF -- "$pat"; then ok "netgate pin: $n"; else bad "netgate pin: $n (rc $r): $(printf '%s\n' "$o" | head -3 | tr '\n' ' ')"; fi; }
pcopy "$W/pc0"; pin "unchanged copies pass (control)" 0 'NETGATE layer=pin+analyser invocations=128 network_through_rc_net=51 findings=0' "$PIN" "${PCS[@]}"
pcopy "$W/pc1"; sed -i '2s/$/ /' "$W/pc1/release/tag_and_release.sh"
pin "a trailing space on one line (same normalised key, other bytes)" 1 'PIN tag_and_release.sh:2 line key' "$PIN" "${PCS[@]}"
pcopy "$W/pc2"; printf '%s\n' '# a comment line' >>"$W/pc2/release_publish_gitea.sh"
pin "an appended comment line" 1 'pinned (none)' "$PIN" "${PCS[@]}"
pcopy "$W/pc3"; pin "a file that is not on the pin" 1 'PIN a file that is not on the pin: ngc.sh' "$PIN" "${PCS[@]}" "$W/ngc.sh"
pin "a file of the pin that was not given" 1 'PIN a file of the pin that was not given or loaded: release_publish_gitea.sh' "$PIN" "${PCS[@]:0:3}"
awk 'BEGIN{d=0} /^S\t/ && !d {d=1; next} {print}' "$PIN" >"$W/pin_s.tsv"
pin "a site row removed from the pin" 1 'PIN a site that is not on the pin' "$W/pin_s.tsv" "${PCS[@]}"
{ cat "$PIN"; printf 'S\ttag_and_release.sh\t1\tgit\trc_net\tnetwork-through-rc_net\t00000000\n'; } >"$W/pin_b.tsv"
pin "a site row the analyser does not find" 1 'PIN a site of the pin that the analyser does not find' "$W/pin_b.tsv" "${PCS[@]}"
pin "an unreadable pin" 1 'the pin table cannot be read' "$W/no_such_pin.tsv" "${PCS[@]}"
grep '^#' "$PIN" >"$W/pin_h.tsv"; pin "a pin with no rows" 1 'the pin table has no F or no N rows' "$W/pin_h.tsv" "${PCS[@]}"
pin "the analyser alone with an unreadable pin (the name and program lists come from the pin)" 1 'the pin table cannot be read' "$W/no_such_pin.tsv" --analyser-only "$W/ngc.sh"
{ cat "$PIN"; printf 'X\tzz\n'; } >"$W/pin_x.tsv"
pin "a row the gate does not know" 1 'a row the gate does not know' "$W/pin_x.tsv" "${PCS[@]}"
{ cat "$PIN"; printf 'L\ttag_and_release.sh\tzz\t00000000\t0000000000000000\n'; } >"$W/pin_n.tsv"
pin "a number field that is not a number" 1 'a number field that is not a number' "$W/pin_n.tsv" "${PCS[@]}"
o="$(env -i PATH=/nonexistent LANG=C.UTF-8 "$PY3" -I "$CEN" netgate "${SCRIPTS[@]}" 2>&1)"; r=$?
[ "$r" -eq 2 ] && ok "netgate pin: netgate without --pin is a usage error (rc 2)" || bad "netgate pin: netgate without --pin rc $r"
pcopy "$W/pc4"; printf '%s\n' 'git fetch -q origin' >>"$W/pc4/release/tag_and_release.sh"
o="$("$PY3" -I "$CEN" pin-regen "$W/regen.tsv" "${PCS[@]}" 2>&1)"; r=$?
[ "$r" -eq 1 ] && [ ! -e "$W/regen.tsv" ] && printf '%s\n' "$o" | grep -qF 'REFUSED network command outside rc_net' && ok "netgate pin: pin-regen is refused while the analyser has a finding, and writes nothing" \
  || bad "netgate pin: pin-regen with a finding (rc $r): $(printf '%s\n' "$o" | head -2 | tr '\n' ' ')"
printf '%s\n' 'x=1' >"$W/noinv.sh"; o="$("$PY3" -I "$CEN" pin-regen "$W/regen0.tsv" "$W/noinv.sh" 2>&1)"; r=$?
[ "$r" -eq 1 ] && [ ! -e "$W/regen0.tsv" ] && printf '%s\n' "$o" | grep -qxF 'REFUSED BLIND: no invocation found' && ok "netgate pin: pin-regen of a file with no invocation is refused as BLIND, and writes nothing" \
  || bad "netgate pin: pin-regen BLIND (rc $r): $(printf '%s\n' "$o" | head -2 | tr '\n' ' ')"
o1="$("$PY3" -I "$CEN" pin-regen "$W/rg1.tsv" "${SCRIPTS[@]}" 2>&1)"; r1=$?
o2="$(env -i PATH=/nonexistent LANG=C.UTF-8 "$PY3" -I "$CEN" pin-regen "$W/rg2.tsv" "${SCRIPTS[3]}" "${SCRIPTS[2]}" "${SCRIPTS[1]}" "${SCRIPTS[0]}" 2>&1)"; r2=$?
[ "$r1" -eq 0 ] && [ "$r2" -eq 0 ] && cmp -s "$W/rg1.tsv" "$PIN" && cmp -s "$W/rg2.tsv" "$PIN" && ok "netgate pin: the committed pin is what pin-regen writes for the committed scripts, in either argument order and with an empty PATH ($o1)" \
  || bad "netgate pin: the committed pin differs from pin-regen (rc $r1/$r2): run pin-diff and review ($(printf '%s\n' "$o2" | tail -n 1))"
o="$("$PY3" -I "$CEN" pin-diff "$PIN" "${SCRIPTS[@]}" 2>&1)"; r=$?
[ "$r" -eq 0 ] && printf '%s\n' "$o" | grep -qxF 'PIN-DIFF removed=0 added=0 analyser_findings=0' && ok "netgate pin: pin-diff of the committed scripts is empty (rc 0)" || bad "netgate pin: pin-diff of the committed scripts (rc $r): $(printf '%s\n' "$o" | tail -1)"
pcopy "$W/pc5"; printf '%s\n' ': ZZPINDIFFMARKER' >>"$W/pc5/release/tag_and_release.sh"
o="$("$PY3" -I "$CEN" pin-diff "$PIN" "${PCS[@]}" 2>&1)"; r=$?
[ "$r" -eq 1 ] && printf '%s\n' "$o" | grep -qP '^\+L\ttag_and_release\.sh\t' && ! printf '%s\n' "$o" | grep -qF ZZPINDIFFMARKER && ok "netgate pin: pin-diff shows a changed file as line-key rows, never its text (rc 1)" \
  || bad "netgate pin: pin-diff of a changed copy (rc $r): $(printf '%s\n' "$o" | grep -c ZZPINDIFFMARKER) text lines"

# ---- part 3: runtime recorders generated from the table and from the instrument ----
# NET_ALLOW: the test's own copy of the network allow-list of rc_net (round 11)
# shellcheck source=tests/release/env_allow.sh
. "$HERE/env_allow.sh"
REC="$W/rec"; mkdir -p "$REC"; CEN_LOG="$W/cen.log"; : >"$CEN_LOG"; export CEN_LOG
mapfile -t TCMDS < <(python3 "$CEN" commands "$TAB")
# round 6 (K5 class): a command with no row is recorded too, so the runtime half does not depend on the table being
# complete: the recorders cover every table command and every command the instrument finds in the scripts
mapfile -t CMDS < <({ printf '%s\n' "${TCMDS[@]}"; python3 "$CEN" list "${SCRIPTS[@]}" | awk -F '\t' '$3 != "-" {print $3}'; } | sort -u)
[ "${#TCMDS[@]}" -ge 10 ] && [ "${#CMDS[@]}" -ge "${#TCMDS[@]}" ] && ok "runtime: ${#CMDS[@]} commands (${#TCMDS[@]} from the table) get a recorder (control needle)" || bad "runtime: commands: ${#CMDS[@]} table: ${#TCMDS[@]}"
# the recorders call only absolute paths (a recorder that ran "sed" through PATH would call itself).
# Round 11: the log path is written into each recorder, not read from CEN_LOG: a network child runs through rc_net
# and gets the network allow-list only (CEN_LOG is a RELEASE_ENV_KEEP name, which reaches local children only).
# Round 11 (the race found by the second suite run, see env_census.py): the block is written to a per-process file
# (LOG.rec.PID; round 12, F3: per process, not private by mode) and appended to the log in one step under flock(1), so two recorders running at the same time never interleave lines.
ENVB="$(command -v env)"; AWKB="$(command -v awk)"; FLOCKB="$(command -v flock)"; CATB="$(command -v cat)"; RMB="$(command -v rm)"
[ -n "$FLOCKB" ] && [ -n "$CATB" ] && [ -n "$RMB" ] && ok "runtime: flock, cat and rm found for the recorders (control needle)" || bad "runtime: flock, cat or rm not found (the recorders would race)"
for c in "${CMDS[@]}"; do
  real="$(command -v "$c" 2>/dev/null)" || continue
  printf '#!/bin/sh\nt="%s.rec.$$"\n{ printf "== %%s\\n" "%s"; for a in "$@"; do printf "A %%s\\n" "$a"; done; "%s" | "%s" "{print \\"E \\" \\$0}"; } >"$t"\n[ -s "$t" ] && "%s" "%s" "%s" "$t" >>"%s" || exit 125\n"%s" -f "$t"\nexec "%s" "$@"\n' "$CEN_LOG" "$c" "$ENVB" "$AWKB" "$FLOCKB" "$CEN_LOG" "$CATB" "$CEN_LOG" "$RMB" "$real" >"$REC/$c"; chmod +x "$REC/$c"
done
# Round 11 RACE: 100 pairs of the git and the sed recorder started together; every record keeps its own marker and
# both are counted 100 times (control needles); then the log is emptied for the real run below.
if [ -x "$REC/git" ] && [ -x "$REC/sed" ]; then
  for _ in $(seq 1 100); do
    env -i PATH="$REC:$PATH" ZZCRACEG=1 git --version >/dev/null 2>&1 &
    env -i PATH="$REC:$PATH" ZZCRACES=1 sed --version >/dev/null 2>&1 &
    wait
  done
  rr="$(awk '/^== /{c=$2; next} /^E ZZCRACEG=/{g++; if (c!="git") x++} /^E ZZCRACES=/{s++; if (c!="sed") x++} END {printf "%d %d %d", g, s, x+0}' "$CEN_LOG")"
  [ "$rr" = "100 100 0" ] && ok "runtime: concurrent recorders never interleave (git sed misattributed: $rr)" || bad "runtime: concurrent recorders interleave or are lost (git sed misattributed: $rr)"
  : >"$CEN_LOG"
else bad "runtime: no git or sed recorder for the race check"; fi
# an unknown command the scripts must not run is caught: every recorded name is in the table
T="CENSUSTOKEN123456"
P="$W/pub"; mkdir -p "$P"; ( cd "$P" && git init -q . && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m c && git tag rel-1 )
printf '## rel-1 — y\nnotes\n' >"$P/CHANGELOG.md"
cat >"$W/stub.py" <<'PY'
import http.server, json, sys
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _s(self, c, b):
        d = json.dumps(b).encode(); self.send_response(c); self.send_header('Content-Length', str(len(d))); self.end_headers(); self.wfile.write(d)
    def do_GET(self): self._s(404, {})
    def do_POST(self):
        self.rfile.read(int(self.headers['Content-Length'])); self._s(201, {"id": 1})
http.server.HTTPServer(('127.0.0.1', int(sys.argv[1])), H).serve_forever()
PY
PORT=$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])')
python3 "$W/stub.py" "$PORT" & SRV=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do (exec 3<>/dev/tcp/127.0.0.1/$PORT) 2>/dev/null && break; sleep 0.3; done
BASH_BIN="$(command -v bash)"; TO_BIN="$(command -v timeout)"
out="$(cd "$P" && PATH="$REC:$PATH" M3W_GITEA_TOKEN=$T XYZ_TOKEN=ZZCENXYZ "$TO_BIN" 60 "$BASH_BIN" "${SCRIPTS[3]}" --tag rel-1 --base-url "http://127.0.0.1:$PORT" </dev/null 2>&1)"; rc=$?
[ $rc -eq 0 ] && printf '%s\n' "$out" | grep -q '^CREATED' && ok "runtime: the publisher run completes (control, rc 0)" || bad "runtime: publisher rc=$rc $out"
grep -qx '== curl' "$CEN_LOG" && ok "runtime: the curl call is recorded (control needle)" || bad "runtime: curl not recorded (recorders blind)"
grep -q '^A .*/api/v1/repos/' "$CEN_LOG" && ok "runtime: the request URL is in the recorded argv (positive needle)" || bad "runtime: argv census blind"
unk=""; while IFS= read -r c; do printf '%s\n' "${TCMDS[@]}" | grep -qx -- "$c" || unk="$unk $c"; done < <(sed -n 's/^== //p' "$CEN_LOG" | sort -u)
[ -z "$unk" ] && ok "runtime: every command the publisher ran is in the table" || bad "runtime: commands not in the table:$unk"
grep -q -- "$T" "$CEN_LOG" && { awk -v t="$T" '/^== /{c=$0} index($0,t){print c": "$0}' "$CEN_LOG" | head -5; bad "runtime: the token is in the argv or environment of a child"; } || ok "runtime: no argv and no environment of any child holds the token"
grep -q 'ZZCENXYZ' "$CEN_LOG" && bad "runtime: a caller *TOKEN* variable reaches a child" || ok "runtime: no caller *TOKEN* variable reaches a child"
grep -q '^E PATH=' "$CEN_LOG" && ok "runtime: the environment census reads PATH (control needle)" || bad "runtime: env census blind"
# round 11 (rc_net at run time): the curl child's environment is the network allow-list: it has LC_ALL=C (positive
# needle) and no CEN_LOG, which a local child of the same run has (control needle: a RELEASE_ENV_KEEP name)
blk(){ awk -v c="== $1" '/^== /{on=($0==c)} on' "$CEN_LOG"; }
blk curl | grep -qx 'E LC_ALL=C' && ok "runtime: the curl child has LC_ALL=C (rc_net)" || bad "runtime: the curl child has no LC_ALL=C"
blk curl | grep -q '^E CEN_LOG=' && bad "runtime: a RELEASE_ENV_KEEP name reaches the curl child" || ok "runtime: no RELEASE_ENV_KEEP name reaches the curl child"
blk jq | grep -q '^E CEN_LOG=' && ok "runtime: a local child (jq) has the RELEASE_ENV_KEEP name (control)" || bad "runtime: control: jq has no CEN_LOG"
# the recorder is a /bin/sh script, and that shell exports names of its own (dash exports PWD): measured here with
# an empty environment, never assumed, and not counted against rc_net
own="$(env -i /bin/sh -c "\"$ENVB\"" | sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' | tr '\n' ' ')"
x=""; for n in $(blk curl | sed -n 's/^E \([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' | sort -u); do case " $NET_ALLOW $own " in *" $n "*) ;; *) x="$x $n" ;; esac; done
[ -z "$x" ] && ok "runtime: every name of the curl child is on NET_ALLOW (the recorder shell adds: ${own:-none})" || bad "runtime: curl child names outside NET_ALLOW:$x"
# ---- part 4 (round 7, L5): a SIGTERM ends the mutation harness and the suite it is running ----
# The harness runs with --only control (it starts the control suites); TERM is sent 4 s later. It must exit with
# status 143 through its own handler (python reads the exact status: a process killed by the signal reads -15)
# within 30 s, leave no work directory in its TMPDIR and no suite process behind. RED on the round-6 harness: its
# trap handler returned and bash runs a trap only after the FOREGROUND suite ends, so the run went on for minutes.
H4="$W/h4"; mkdir -p "$H4"
r4="$(python3 -I - "$HERE/test_release_tooling_mutations.sh" "$H4" <<'PYS'
import os, signal, subprocess, sys, time
h, tmp = sys.argv[1:3]
p = subprocess.Popen(["bash", h, "--only", "control"], env=dict(os.environ, TMPDIR=tmp), stdin=subprocess.DEVNULL,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
time.sleep(4)
t0 = time.time(); p.send_signal(signal.SIGTERM)
try:
    rc = p.wait(timeout=30)
except subprocess.TimeoutExpired:
    rc = "timeout"
el = int(time.time() - t0)
time.sleep(1)
left = 0
for q in os.listdir("/proc"):
    if q.isdigit() and int(q) > 1:
        try:
            if tmp.encode() in open("/proc/%s/environ" % q, "rb").read():
                left += 1
        except Exception:
            pass
if rc == "timeout" and p.pid > 1:
    os.killpg(p.pid, signal.SIGKILL)   # own session leader started above (pgid == its pid > 1)
print(rc, el, left, len([d for d in os.listdir(tmp) if d.startswith("rtm_test.")]))
PYS
)"
read -r h4rc h4el h4left h4dirs <<<"$r4"
chk(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got '$2', want '$3')"; fi; }
chk "L5 the harness ends on SIGTERM through its handler: exit 143 (${h4el:-?} s after the signal)" "${h4rc:-none}" 143
chk "L5 no process of the harness run is left" "${h4left:-none}" 0
chk "L5 the harness removed its work directory" "${h4dirs:-none}" 0
# ---- round 8 (N5, N6) ----
# N5: --only with a name that is no mutant exits 2 (it ran nothing); control needle: --only with a real name under
# STALE_ONLY=1 (applies the mutant, runs no suite) exits 0 and reports it applies
o5="$(bash "$HERE/test_release_tooling_mutations.sh" --only ZZNOSUCH8 2>&1)"; r5=$?
chk "N5 --only an unknown name: exit 2" "$r5" 2
case "$o5" in *"FAIL --only ZZNOSUCH8: no mutant"*) ok "N5 --only an unknown name: says so" ;; *) bad "N5 --only an unknown name: $o5" ;; esac
o5="$(STALE_ONLY=1 bash "$HERE/test_release_tooling_mutations.sh" --only Z1 2>&1)"; r5=$?
case "$r5:$o5" in 0:*"PASS Z1 applies"*) ok "N5 --only a real name: exit 0 (control needle)" ;; *) bad "N5 --only Z1: rc $r5 $(printf '%s\n' "$o5" | tail -n 2 | tr '\n' ' ')" ;; esac
# N5b (round 14, F5 of the round-13 review): the harness's exit status from its counters (RTM_EXIT_SELFTEST runs
# nothing): a killed meq mutant ("equivalent_killed") is exit 4, distinct from a pass (0), a failure (1, which wins)
# and INCONCLUSIVE (3, which it wins over); a malformed selftest value is exit 2
for c in "0 0 0 0 0 0:0" "1 0 0 0 0 0:1" "0 1 0 0 0 0:1" "0 0 1 0 0 0:1" "0 0 0 1 0 0:4" "1 0 0 1 0 0:1" "0 0 0 2 1 1:4" "0 0 0 0 1 0:3" "0 0 0 0 0 1:3" "0 0 0 x 0 0:2"; do
  RTM_EXIT_SELFTEST="${c%%:*}" bash "$HERE/test_release_tooling_mutations.sh" >/dev/null 2>&1; chk "N5b harness exit for counters ${c%%:*}" "$?" "${c##*:}"
done
# N6: suite_exit (tests/release/env_allow.sh): a SKIPPED case is not a PASS unless the caller expects skips
# shellcheck source=tests/release/env_allow.sh
. "${ENV_ALLOW_LIB:-$HERE/env_allow.sh}"   # round 9: ENV_ALLOW_LIB lets the mutation harness test a mutated copy
for c in "0 0 0" "1 0 1" "0 1 77" "1 1 1"; do set -- $c; RELEASE_TESTS_ALLOW_SKIP="" suite_exit "$1" "$2"; chk "N6 suite_exit fail=$1 skipped=$2" "$?" "$3"; done
RELEASE_TESTS_ALLOW_SKIP=1 suite_exit 0 1; chk "N6 suite_exit with RELEASE_TESTS_ALLOW_SKIP=1: a skip is not a failure" "$?" 0
# round 9 (F9, the reviewer's E1): only the exact value 1 allows skips; 0, an empty value and any other word do not
for v in 0 "" yes true 11; do RELEASE_TESTS_ALLOW_SKIP="$v" suite_exit 0 1; chk "N6 suite_exit with RELEASE_TESTS_ALLOW_SKIP='$v': a skip exits 77" "$?" 77; done
RELEASE_TESTS_ALLOW_SKIP=1 suite_exit 1 1; chk "N6 suite_exit with RELEASE_TESTS_ALLOW_SKIP=1: a failure still exits 1" "$?" 1
set --
echo "RESULT: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
