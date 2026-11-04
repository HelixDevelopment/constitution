#!/bin/sh
# =============================================================================
# test_precheck_gate_git_isolation.sh -- ATM-1217 review H2 regression guard
# =============================================================================
#
# The pre-check builder (review/precheck_pack_build.sh) and gate
# (review/lib/precheck_pack_run.py, review/lib/precheck_pack_build_run.py) run
# git against a repository they are REVIEWING, i.e. a repository whose author is
# the producer. r12 pinned a fixed list of config keys; any key not on the list
# (a filter named by $GIT_DIR/info/attributes, gpg.program with
# log.showSignature, include.path, core.alternateRefsCommand, ...) still ran a
# program of the producer's choosing. r13 runs every git call against a
# GATE-OWNED git dir (lib/precheck_common.py make-git-dir) under `env -i`.
#
# This file builds a hostile fixture repository whose .git/config,
# .git/info/attributes, include file, hooks and tracked .gitattributes name a
# marker program for every key class below, then:
#   A. POSITIVE CONTROLS -- plain git commands in the fixture DO run each
#      marker (so the fixture is live, not decoration); a control whose marker
#      does not fire FAILs the file.
#   B. the builder, on a commit and on a snapshot of the hostile repository,
#      must run ZERO markers and still produce precheck.json.
#   C. three paired mutants (shell gg back on the producer git dir; Python
#      env without GIT_DIR; the gate dir copying the producer config) must
#      each make some marker run.
# Marker classes: fsmonitor, smudge, clean, process, textconv, diffext, gpg,
# pager, cred, ssh, altref, hook, incl (a credential.helper set in an
# include file). Honest limits: pager has no positive control (git only pages a tty);
# altref has no positive control (needs an alternate with refs).
#
# Usage: sh test_precheck_gate_git_isolation.sh [REVIEW_DIR]   (exit 0 all PASS, 1 any FAIL)
# Never prints the environment; works under mktemp only; deletes with ${VAR:?}.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
# Optional argument: the review/ directory to test (the delta suite passes its own, possibly a mutant copy); with
# an argument section C (this file's own mutants) is skipped.
REVIEW_SRC=${1:-$HERE/../review}
BUILD="$REVIEW_SRC/precheck_pack_build.sh"
PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; }

W=$(mktemp -d)
trap 'rm -rf "${W:?}"' EXIT INT TERM
M="$W/marker"
: >"$M"
H="$W/home"
mkdir "$H"
for n in fsmonitor smudge clean process textconv diffext gpg pager cred ssh altref hook incl; do
    case "$n" in
        smudge|clean) body='cat' ;;
        textconv) body='cat "$1"' ;;
        *) body='exit 1' ;;
    esac
    printf '#!/bin/sh\necho %s >>"%s"\n%s\n' "$n" "$M" "$body" >"$W/$n"
    chmod +x "$W/$n"
done
mkdir "$W/hooks"
for h in post-checkout post-index-change reference-transaction pre-commit post-commit pre-auto-gc; do
    printf '#!/bin/sh\necho hook >>"%s"\nexit 0\n' "$M" >"$W/hooks/$h"
    chmod +x "$W/hooks/$h"
done

R="$W/repo"
mkdir "$R"
plain() { env -i PATH="$PATH" HOME="$H" GIT_CONFIG_NOSYSTEM=1 git -C "$R" "$@"; }
plain init -q -b main
plain config user.name t
plain config user.email t@invalid
printf 'one\n' >"$R/a.txt"
printf '#!/bin/sh\necho one\n' >"$R/s.sh"
plain add a.txt s.sh
plain commit -q -m base
# Signed commits (fake gpgsig header) so log.showSignature calls gpg.program.
sign_head() {
    _c=$(plain cat-file commit HEAD | awk 'BEGIN{d=0} /^$/ && !d {print "gpgsig -----BEGIN PGP SIGNATURE-----"; print " x"; print " -----END PGP SIGNATURE-----"; d=1} {print}')
    _n=$(printf '%s\n' "$_c" | plain hash-object -t commit -w --stdin)
    plain update-ref HEAD "$_n"
}
sign_head
printf 'two\n' >"$R/a.txt"
printf '#!/bin/sh\necho two\n' >"$R/s.sh"
plain commit -q -a -m change
sign_head
SHA=$(plain rev-parse HEAD)

# Hostile configuration, applied AFTER the commits so the setup itself runs no marker.
cat >>"$R/.git/config" <<EOF
[core]
	fsmonitor = $W/fsmonitor
	hooksPath = $W/hooks
	pager = $W/pager
	sshCommand = $W/ssh
	alternateRefsCommand = $W/altref
[filter "evil"]
	smudge = $W/smudge
	clean = $W/clean
[filter "evil2"]
	process = $W/process
	required = false
[diff "evil"]
	textconv = $W/textconv
[diff]
	external = $W/diffext
[credential]
	helper = $W/cred
[gpg]
	program = $W/gpg
[log]
	showSignature = true
[include]
	path = $W/incl.cfg
EOF
printf '[credential]\n\thelper = %s/incl\n' "$W" >"$W/incl.cfg"
mkdir -p "$R/.git/info"
printf '* filter=evil diff=evil\n*.sh filter=evil2\n' >"$R/.git/info/attributes"

count() { grep -cx "$1" "$M" 2>/dev/null || true; }

# --- A. positive controls under plain git ---
: >"$M"
plain status --porcelain >/dev/null 2>&1
[ "$(count fsmonitor)" -ge 1 ] && ok "control: plain git status runs core.fsmonitor" || bad "control: fsmonitor never ran"
: >"$M"
rm -f "$R/a.txt"
plain checkout -- a.txt >/dev/null 2>&1
[ "$(count smudge)" -ge 1 ] && ok "control: plain checkout runs the info/attributes smudge filter" || bad "control: smudge never ran"
: >"$M"
printf 'three\n' >"$R/a.txt"
plain add a.txt >/dev/null 2>&1
[ "$(count clean)" -ge 1 ] && ok "control: plain add runs the clean filter" || bad "control: clean never ran"
plain reset -q --hard >/dev/null 2>&1
: >"$M"
rm -f "$R/s.sh"
plain checkout -- s.sh >/dev/null 2>&1
[ "$(count process)" -ge 1 ] && ok "control: plain checkout runs filter.process" || bad "control: process never ran"
: >"$M"
plain diff --no-ext-diff HEAD~1 HEAD >/dev/null 2>&1
[ "$(count textconv)" -ge 1 ] && ok "control: plain diff runs textconv" || bad "control: textconv never ran"
: >"$M"
plain diff HEAD~1 HEAD >/dev/null 2>&1
[ "$(count diffext)" -ge 1 ] && ok "control: plain diff runs diff.external" || bad "control: diffext never ran"
: >"$M"
plain log -1 >/dev/null 2>&1
[ "$(count gpg)" -ge 1 ] && ok "control: plain log runs gpg.program (log.showSignature)" || bad "control: gpg never ran"
: >"$M"
printf 'protocol=https\nhost=example.invalid\n\n' | plain credential fill >/dev/null 2>&1
[ "$(count cred)" -ge 1 ] && ok "control: plain credential fill runs credential.helper" || bad "control: cred never ran"
[ "$(count incl)" -ge 1 ] && ok "control: plain credential fill runs a helper set in an include file" || bad "control: incl never ran"
: >"$M"
plain ls-remote ssh://example.invalid/x >/dev/null 2>&1
[ "$(count ssh)" -ge 1 ] && ok "control: plain ls-remote runs core.sshCommand" || bad "control: ssh never ran"
: >"$M"
plain worktree add -q --detach "$W/ctl_wt" HEAD >/dev/null 2>&1
[ "$(count hook)" -ge 1 ] && ok "control: plain worktree add runs a hook" || bad "control: hook never ran"
plain worktree remove --force "$W/ctl_wt" >/dev/null 2>&1
plain reset -q --hard >/dev/null 2>&1

# --- B. the builder runs zero markers ---
run_build() {  # $1 tag, rest: build args
    _t=$1
    shift
    : >"$M"
    _rc=0
    env HOME="$H" sh "$BUILD" --repo-root "$R" --out-dir "$W/out_$_t" --min-free-kb 1 "$@" \
        >"$W/build_$_t.out" 2>"$W/build_$_t.err" || _rc=$?
    _m=$(sort "$M" | uniq -c | tr '\n' ' ')
    if [ "$_rc" -ne 0 ] && [ "$_rc" -ne 1 ]; then
        bad "builder ($_t) exited $_rc: $(head -c 400 "$W/build_$_t.err")"
    elif [ ! -s "$W/out_$_t/precheck.json" ]; then
        bad "builder ($_t) wrote no precheck.json"
    else
        ok "builder ($_t) produced precheck.json (rc=$_rc)"
    fi
    if [ -s "$M" ]; then bad "builder ($_t) ran producer programs: $_m"; else ok "builder ($_t) ran zero producer programs"; fi
}
run_build commit --commit "$SHA"
printf 'four\n' >"$R/a.txt"
printf 'a.txt\n' >"$W/snap.paths"
run_build snapshot --snapshot-paths "$W/snap.paths"
plain reset -q --hard >/dev/null 2>&1
if [ -n "$(env -i PATH="$PATH" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null git -C "$R" -c core.fsmonitor=false -c core.hooksPath=/dev/null worktree list --porcelain | grep -c '^worktree ' | awk '$1>1')" ]; then
    bad "builder left a worktree registered in the reviewed repository"
else
    ok "reviewed repository has no leftover worktree registration"
fi

# --- C. paired mutants: each re-opens one hole and MUST make section B's zero-marker check fail ---
mutant() {  # $1 name, $2 file under review/, $3 python expression old, $4 new, $5 build kind
    _mn=$1
    _md="$W/mut_$1/scripts/fastcycle"
    mkdir -p "$_md"
    cp -R "$REVIEW_SRC" "$_md/review"
    if ! python3 -c 'import sys
p,o,n=sys.argv[1:4]
s=open(p).read()
assert s.count(o)==1, "mutation anchor not unique"
open(p,"w").write(s.replace(o,n))' "$_md/review/$2" "$3" "$4"; then
        bad "mutant $1: anchor not found (mutation not applied)"
        return
    fi
    : >"$M"
    if [ "$5" = snapshot ]; then
        printf 'five\n' >"$R/a.txt"
        set -- --snapshot-paths "$W/snap.paths"
    else
        set -- --commit "$SHA"
    fi
    env HOME="$H" sh "$_md/review/precheck_pack_build.sh" --repo-root "$R" --out-dir "$W/mout_$_mn" --min-free-kb 1 \
        "$@" >"$W/mut_$_mn.out" 2>"$W/mut_$_mn.err" || true
    # Read the markers BEFORE any plain git call below (plain git in the hostile repo runs them itself).
    if [ -s "$M" ]; then ok "mutant killed ($_mn): producer programs ran: $(sort "$M" | uniq -c | tr '\n' ' ')"
    else bad "mutant survived ($_mn): zero markers with the hole re-opened"; fi
    plain reset -q --hard >/dev/null 2>&1
    rm -rf "${_md:?}"
}
if [ $# -eq 0 ]; then
mutant shell_gg_producer_gitdir precheck_pack_build.sh 'GIT_DIR="$GATE_GIT" GIT_WORK_TREE="$REPO" git "$@"' 'git -C "$REPO" "$@"' commit
mutant py_no_gate_gitdir lib/precheck_common.py '    env["GIT_DIR"] = gdir
' '' snapshot
mutant py_copy_producer_config lib/precheck_common.py '    with open(os.path.join(dest, "config"), "w") as fh:
        fh.write("\n".join(cfg) + "\n")' '    shutil.copyfile(os.path.join(common, "config"), os.path.join(dest, "config"))' snapshot
fi

echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
