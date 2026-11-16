#!/usr/bin/env bash
# history_secret_scan.sh -- read-only full-history secret scan of one repository
# across ALL its remotes, with control needles planted INSIDE the scanned
# mirror. Never writes to any remote.
#
# Status: PROVISIONAL (§11.4.290). Tested only with a fake gitleaks
# (tests/security/test_history_secret_scan.sh). A run with the real gitleaks
# binary is a separate LIVE-class check (§11.4.289) and is owed.
#
# Steps:
#   1. WORK=mktemp -d under $SCRATCH (required). `git clone --mirror` of the
#      first URL, then `git fetch` of every other URL into refs/fetched/r<n>/*
#      (all branches + tags of every forge in ONE object store).
#   2. Control needles (§11.4.201(7)(b), §11.4.273), written into the SAME bare
#      mirror under refs/fetched/needle/*, so they cross the same path, options
#      and ref set as the real history:
#        pos    a fabricated github-pat-shaped token added in one commit and
#               deleted in the next (history only)       -> MUST be found
#        merge  a fabricated token present ONLY in a merge commit's diff (an
#               evil merge), deleted in the next commit  -> MUST be found
#               (proves the merge-diff option -m is really applied)
#        neg    a plain text file                        -> MUST NOT be found
#      Needle values are random per run and never printed.
#   3. ONE scan: gitleaks git --redact --log-opts="--all -m" over the mirror.
#      The scanner's own console output (file paths, commits, rule ids) goes
#      to a file inside $WORK, never to this script's stdout or stderr.
#      Only gitleaks exit 0 (no leak) or 1 (leaks) is accepted, with a JSON
#      array report consistent with that exit; anything else is SCANNER-ERROR.
#   4. The needle results are read from that same report; any needle failing
#      is BLIND. Needle findings are then removed; the rest goes to $OUT as a
#      value-free TSV (rule, file:line, commit, entropy) to classify by hand.
#   5. Optional exact-match pass (--keys-file F, mode 600 or stricter): every
#      variable the file defines, value >= 12 chars and not a placeholder, is
#      searched in every blob of the mirror. Values go to the matcher on a
#      pipe, never argv; output is variable NAMES + blob counts only
#      ($OUT.keys.tsv). Controls: a needle value MUST be found, a random value
#      MUST NOT; else BLIND. Values that are not searched (shorter than 12
#      characters, or a placeholder) are never silent: a note names the
#      variables and counts them (names only, never values).
#      The blob ids reach `git cat-file --batch` from a file in $WORK, not a
#      pipe written before the answers are read (CON-PENDING-secscan: with a
#      few thousand blobs both pipes filled and both processes waited for
#      ever). Every reply is checked against the requested id; a missing or
#      malformed reply is exit 7, never a count.
#      --exact-only (needs --keys-file) skips step 3 and the scanner
#      needle checks: no gitleaks binary is needed, nf is 0, and only the
#      exact-match controls guard the result.
#   Known limit: a value shorter than 12 characters is NOT searched (too many
#      chance matches). Such variables are listed by NAME with their count in
#      the "not searched" note on every run (0 included), so a skip is never
#      silent; check them by another means.
#   6. cleanup: safe_rm_rf "$WORK" (scripts/lib/safe_rm.sh).
# Scanner: gitleaks from $GITLEAKS or PATH (a pinned, pre-installed v8
# binary). Nothing is downloaded at run time; without it the exit is 4.
# URLs carrying credentials (http(s) with user info, or user:password@) are
# refused.
#
# Usage: SCRATCH=/abs/dir history_secret_scan.sh [--keys-file F [--exact-only]] URL [URL...]
#        OUT=/path/report.tsv may be set (default $SCRATCH/history_secret_scan_<date>.tsv)
# Exit: 0 no finding; 1 findings to classify; 2 usage; 3 BLIND (a control
#       needle failed); 4 no scanner; 5 missing prerequisite (git, jq,
#       python3, safe_rm.sh); 6 SCANNER-ERROR (exit not 0/1, report missing,
#       unparseable or inconsistent); 7 git or internal error.
set -euo pipefail
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
trap 'echo "ERROR: unexpected failure at line $LINENO" >&2; exit 7' ERR
fail(){ local c=$1; shift; echo "$*" >&2; exit "$c"; }

KEYS=""; EXACT_ONLY=0; declare -a URLS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --keys-file) [ $# -ge 2 ] || fail 2 "usage: --keys-file needs a file"; KEYS=$2; shift ;;
    --exact-only) EXACT_ONLY=1 ;;
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d'; exit 0 ;;
    -*) fail 2 "usage: unknown option $1" ;;
    *) URLS+=("$1") ;;
  esac; shift
done
[ ${#URLS[@]} -ge 1 ] || fail 2 "usage: need at least one remote URL"
[ "$EXACT_ONLY" = 0 ] || [ -n "$KEYS" ] || fail 2 "usage: --exact-only needs --keys-file"
[ -n "${SCRATCH:-}" ] || fail 2 "usage: set SCRATCH to an absolute scratch directory"
case "$SCRATCH" in /*) ;; *) fail 2 "usage: SCRATCH must be absolute" ;; esac
[ -d "$SCRATCH" ] || fail 2 "usage: SCRATCH is not a directory: $SCRATCH"
for u in "${URLS[@]}"; do
  if [[ "$u" =~ ^[Hh][Tt][Tt][Pp][Ss]?://[^/]*@ ]] || [[ "$u" =~ ^[A-Za-z][A-Za-z0-9+.-]*://[^/@]*:[^/@]*@ ]]; then
    fail 2 "usage: refused a URL that carries credentials (the URL is not printed)"
  fi
done
if [ -n "$KEYS" ]; then
  [ -f "$KEYS" ] && [ -r "$KEYS" ] || fail 2 "usage: keys file not readable"
  perm=$(stat -c '%a' "$KEYS"); [ "${perm: -2}" = 00 ] || fail 2 "usage: keys file is readable by group/others ($perm)"
fi

for t in git jq python3 mktemp stat; do command -v "$t" >/dev/null 2>&1 || fail 5 "missing prerequisite: $t"; done
SELF_DIR=$(cd "$(dirname "$0")" && pwd)
SAFE_RM="${SAFE_RM:-$SELF_DIR/../lib/safe_rm.sh}"
[ -f "$SAFE_RM" ] && [ -r "$SAFE_RM" ] || fail 5 "missing prerequisite: safe_rm.sh ($SAFE_RM)"
# shellcheck source=../lib/safe_rm.sh
. "$SAFE_RM" || fail 5 "missing prerequisite: safe_rm.sh did not load"
declare -F safe_rm_rf >/dev/null || fail 5 "missing prerequisite: safe_rm_rf not defined by $SAFE_RM"

GL="${GITLEAKS:-$(command -v gitleaks || true)}"
[ "$EXACT_ONLY" = 1 ] || { [ -n "$GL" ] && [ -x "$GL" ]; } || fail 4 "no scanner: install a pinned gitleaks v8 binary on PATH or set GITLEAKS (nothing is downloaded at run time)"

WORK=$(mktemp -d "$SCRATCH/hss.XXXXXX") || fail 7 "mktemp failed"
# shellcheck disable=SC2154  # _rc is assigned inside the trap string
trap '_rc=$?; trap - ERR; safe_rm_rf "${WORK:?}" || echo "WARNING: cleanup refused for $WORK" >&2; exit $_rc' EXIT
OUT="${OUT:-$SCRATCH/history_secret_scan_$(date +%F).tsv}"
M="$WORK/m.git"

git clone -q --mirror "${URLS[0]}" "$M" 2>"$WORK/git.err" || fail 7 "git error: clone of remote #1 failed"
i=0
for u in "${URLS[@]:1}"; do
  i=$((i+1))
  git -C "$M" fetch -q --no-tags "$u" "+refs/heads/*:refs/fetched/r$i/heads/*" "+refs/tags/*:refs/fetched/r$i/tags/*" 2>"$WORK/git.err" \
    || fail 7 "git error: fetch of remote #$((i+1)) failed"
done

# ---- control needles inside the mirror ---------------------------------------------------------
export GIT_AUTHOR_NAME=hss-needle GIT_AUTHOR_EMAIL=needle@invalid GIT_COMMITTER_NAME=hss-needle GIT_COMMITTER_EMAIL=needle@invalid
export GIT_AUTHOR_DATE='2000-01-01T00:00:00Z' GIT_COMMITTER_DATE='2000-01-01T00:00:00Z'
rnd(){ python3 -I -c 'import secrets,string,sys;a=string.ascii_letters+string.digits;print("".join(secrets.choice(a) for _ in range(int(sys.argv[1]))))' "$1"; }
POS="ghp_$(rnd 36)"; MRG="ghp_$(rnd 36)"; NEGV="hss$(rnd 37)"
blob(){ printf '%s\n' "$1" | git -C "$M" hash-object -w --stdin; }
# ntree NAME=BLOB... -> a tree with the files under __hss_needle__/
ntree(){
  local sub e
  sub=$(for e in "$@"; do printf '100644 blob %s\t%s\n' "${e#*=}" "${e%%=*}"; done | git -C "$M" mktree)
  printf '040000 tree %s\t__hss_needle__\n' "$sub" | git -C "$M" mktree
}
EMPTY=$(git -C "$M" mktree </dev/null)
commit(){ local t=$1; shift; git -C "$M" commit-tree "$t" "$@" -m hss-needle; }
B_POS=$(blob "T=$POS"); B_MRG=$(blob "T=$MRG"); B_NEG=$(blob "hss negative control, nothing secret: plain text"); B_BASE=$(blob base); B_A=$(blob a); B_B=$(blob b)
p1=$(commit "$(ntree pos.env="$B_POS")"); p2=$(commit "$EMPTY" -p "$p1")
git -C "$M" update-ref refs/fetched/needle/pos "$p2"
git -C "$M" update-ref refs/fetched/needle/neg "$(commit "$(ntree neg.txt="$B_NEG")")"
x=$(commit "$(ntree base.txt="$B_BASE")")
y1=$(commit "$(ntree base.txt="$B_BASE" a.txt="$B_A")" -p "$x")
y2=$(commit "$(ntree base.txt="$B_BASE" b.txt="$B_B")" -p "$x")
mm=$(commit "$(ntree base.txt="$B_BASE" a.txt="$B_A" b.txt="$B_B" merge.env="$B_MRG")" -p "$y1" -p "$y2")
git -C "$M" update-ref refs/fetched/needle/merge "$(commit "$(ntree base.txt="$B_BASE" a.txt="$B_A" b.txt="$B_B")" -p "$mm")"

# ---- the one scan -----------------------------------------------------------------------------
nf=0
if [ "$EXACT_ONLY" = 1 ]; then
  echo "scanner not run (--exact-only): only the exact-match controls guard this run"
else
REP="$WORK/scan.json"
grc=0; "$GL" git --redact --no-banner --log-opts="--all -m" -f json -r "$REP" "$M" >"$WORK/gl.out" 2>&1 || grc=$?
case "$grc" in 0|1) ;; *) fail 6 "SCANNER-ERROR: gitleaks exited $grc" ;; esac
[ -s "$REP" ] || fail 6 "SCANNER-ERROR: no report written"
len=$(jq -e 'if type=="array" then length else error("not an array") end' "$REP" 2>/dev/null) || fail 6 "SCANNER-ERROR: report is not a JSON array"
if { [ "$grc" = 0 ] && [ "$len" -gt 0 ]; } || { [ "$grc" = 1 ] && [ "$len" -eq 0 ]; }; then
  fail 6 "SCANNER-ERROR: exit $grc inconsistent with $len findings"
fi
npos=$(jq '[.[]|select(.File=="__hss_needle__/pos.env")]|length' "$REP")
nmrg=$(jq '[.[]|select(.File=="__hss_needle__/merge.env")]|length' "$REP")
nneg=$(jq '[.[]|select(.File=="__hss_needle__/neg.txt")]|length' "$REP")
[ "$npos" -ge 1 ] || fail 3 "BLIND: the history needle was not found (the scan did not see deleted history)"
[ "$nmrg" -ge 1 ] || fail 3 "BLIND: the merge-only needle was not found (merge diffs were not scanned)"
[ "$nneg" -eq 0 ] || fail 3 "BLIND: the negative needle was flagged (the scanner flags everything)"
jq -r '.[]|select(.File|startswith("__hss_needle__/")|not)|[.RuleID,"\(.File):\(.StartLine)",(.Commit//""|.[0:12]),(.Entropy|tostring)]|@tsv' "$REP" | sort -u > "$OUT"
nf=$(wc -l < "$OUT")
echo "needles: history=$npos merge=$nmrg negative=$nneg (control OK)"
echo "findings=$nf -> $OUT (classify each: fixture vs real)"
fi

# ---- optional exact-match pass ----------------------------------------------------------------
kh=0
if [ -n "$KEYS" ]; then
  KOUT="$OUT.keys.tsv"
  # NAME\0VALUE\0 pairs on a pipe (printf builtin); the two controls first.
  if ! { printf '%s\0%s\0%s\0%s\0' __HSS_CONTROL_PRESENT__ "$POS" __HSS_CONTROL_ABSENT__ "$NEGV"
         env -i KF="$KEYS" bash --noprofile --norc -c '
           before=$(compgen -v | sort); set +u; . "$KF" >/dev/null 2>&1
           for n in $(comm -13 <(echo "$before") <(compgen -v | sort)); do
             case "$n" in before|n|BASH_*|_|PIPESTATUS|FUNCNAME|LINENO|RANDOM|SECONDS|SRANDOM|EPOCH*|COLUMNS|LINES) continue ;; esac
             printf "%s\0%s\0" "$n" "${!n}"
           done'
       } | python3 -I -c '
import subprocess, sys
raw = sys.stdin.buffer.read().split(b"\0")
pairs = [(raw[i].decode(), raw[i + 1]) for i in range(0, len(raw) - 1, 2)]
bad = (b"YOUR", b"CHANGE", b"placeholder", b"xxxx")
vals, short, place = [], [], []
for n, v in pairs:
    if n.startswith("__HSS_CONTROL_"):
        vals.append((n, v))
    elif len(v) < 12:
        short.append(n)
    elif any(b in v for b in bad):
        place.append(n)
    else:
        vals.append((n, v))
cnt = {n: 0 for n, _ in vals}
ids = subprocess.run(["git", "-C", sys.argv[1], "cat-file", "--batch-all-objects", "--batch-check=%(objectname) %(objecttype)"],
                     capture_output=True, check=True).stdout.split(b"\n")
blobs = [l.split()[0] for l in ids if l.endswith(b" blob")]
# The requests come from a regular file, never from a pipe this process
# writes before it reads the answers: git reads requests while we read
# answers, so neither side can block the other (CON-PENDING-secscan).
with open(sys.argv[2], "wb") as f:
    f.write(b"".join(b + b"\n" for b in blobs))
def bad_reply(p):
    sys.stderr.write("exact-match: unexpected reply from git cat-file --batch\n")
    p.kill(); p.wait(); sys.exit(7)
with open(sys.argv[2], "rb") as req:
    p = subprocess.Popen(["git", "-C", sys.argv[1], "cat-file", "--batch"], stdin=req, stdout=subprocess.PIPE)
for b in blobs:
    hdr = p.stdout.readline().split()
    if len(hdr) != 3 or hdr[0] != b or hdr[1] != b"blob" or not hdr[2].isdigit():
        bad_reply(p)
    size = int(hdr[2]); data = p.stdout.read(size)
    if len(data) != size or p.stdout.read(1) != b"\n":
        bad_reply(p)
    for n, v in vals:
        if v in data:
            cnt[n] += 1
if p.stdout.read(1) != b"" or p.wait() != 0:
    sys.exit(7)
for n in cnt:
    print("%s\t%d" % (n, cnt[n]))
print("__HSS_SKIP_SHORT__\t%d\t%s" % (len(short), ",".join(short)))
print("__HSS_SKIP_PLACE__\t%d\t%s" % (len(place), ",".join(place)))' "$M" "$WORK/blob_ids" > "$WORK/keys.tsv"; then
    fail 7 "git error: exact-match pass failed"
  fi
  [ "$(awk -F'\t' '$1=="__HSS_CONTROL_PRESENT__"{print $2}' "$WORK/keys.tsv")" -ge 1 ] || fail 3 "BLIND: exact-match control value was not found"
  [ "$(awk -F'\t' '$1=="__HSS_CONTROL_ABSENT__"{print $2}' "$WORK/keys.tsv")" -eq 0 ] || fail 3 "BLIND: exact-match negative control was found"
  grep -v '^__HSS_' "$WORK/keys.tsv" > "$KOUT" || true
  kh=$(awk -F'\t' '$2>0' "$KOUT" | wc -l)
  echo "exact-match: $(wc -l < "$KOUT") variables searched, $kh found in a blob -> $KOUT (names + counts only)"
  ss=$(awk -F'\t' '$1=="__HSS_SKIP_SHORT__"{print $2" shorter than 12 characters ("$3")"}' "$WORK/keys.tsv")
  sp=$(awk -F'\t' '$1=="__HSS_SKIP_PLACE__"{print $2" placeholder ("$3")"}' "$WORK/keys.tsv")
  echo "exact-match note: not searched: $ss, $sp"
fi
if [ "$nf" -gt 0 ] || [ "$kh" -gt 0 ]; then exit 1; fi
exit 0
