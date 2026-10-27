#!/usr/bin/env bash
# test_safe_rm.sh — tests for scripts/lib/safe_rm.sh (constitution §11.4.287).
#
# Safety design of THIS test (it exercises a delete helper, so it must not be able
# to delete anything real even if the helper under test is broken):
#   - All scratch lives under ONE `mktemp -d` root ($SB), verified non-empty and
#     strictly inside the resolved temp base before anything else runs.
#   - $HOME is NEVER reassigned. A fake home inside $SB is declared through
#     SAFE_RM_EXTRA_HOMES, which the helper treats exactly like $HOME.
#   - A fake `rm` is placed first on PATH. It logs every call and deletes only paths
#     strictly inside $SB; anything else is logged as BLOCKED and left untouched.
#     Refusal cases assert that the fake rm was NOT invoked at all.
#   - Cleanup is a Python check (realpath strictly inside the temp base + marker
#     file present) followed by shutil.rmtree. No shell `rm -rf` on a variable.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
LIB="$HERE/safe_rm.sh"
LIST="$HERE/protected_paths.list"
PASS=0; FAIL=0

TMPBASE="$(readlink -m -- "${TMPDIR:-/tmp}")"
SB="$(mktemp -d)"
case "$SB" in ""|/) echo "ABORT: mktemp -d returned '$SB'"; exit 99;; esac
SB="$(readlink -m -- "$SB")"
case "$SB" in "$TMPBASE"/?*) ;; *) echo "ABORT: sandbox $SB is not inside $TMPBASE"; exit 99;; esac
MARKER=".safe_rm_test_sandbox"
: > "$SB/$MARKER"

CLEANUP_PY='
import os, shutil, sys
sb, base, marker = sys.argv[1], sys.argv[2], sys.argv[3]
if not sb or not base:
    sys.exit("cleanup: refusing, empty argument")
rs, rb = os.path.realpath(sb), os.path.realpath(base)
if rb in ("/", "") or rs == rb or not rs.startswith(rb + os.sep):
    sys.exit("cleanup: refusing, %r is not strictly inside %r" % (rs, rb))
if not os.path.isfile(os.path.join(rs, marker)):
    sys.exit("cleanup: refusing, sandbox marker missing in %r" % rs)
shutil.rmtree(rs)
'
cleanup() { python3 -c "$CLEANUP_PY" "$SB" "$TMPBASE" "$MARKER"; }
trap cleanup EXIT

# --- fake rm: logs, deletes only inside $SB, never follows a symlink ---
mkdir -p "$SB/bin"
printf '%s\n' \
  '#!/usr/bin/env python3' \
  'import os, shutil, sys' \
  'sb = os.path.realpath(os.environ["SAFE_RM_TEST_SB"])' \
  'log = os.path.join(sb, "rm.log")' \
  'args = sys.argv[1:]' \
  'paths = args[args.index("--") + 1:] if "--" in args else [a for a in args if not a.startswith("-")]' \
  'nodelete = os.environ.get("FAKE_RM_NODELETE") == "1"' \
  'rc = 0' \
  'with open(log, "a") as fh:' \
  '    for p in paths:' \
  '        ap = os.path.abspath(p)' \
  '        target = os.path.join(os.path.realpath(os.path.dirname(ap)), os.path.basename(ap))' \
  '        if not target.startswith(sb + os.sep) or os.path.basename(ap) in ("", ".", ".."):' \
  '            fh.write("BLOCKED %s\n" % p); rc = 1; continue' \
  '        fh.write(("NODELETE %s\n" if nodelete else "RM %s\n") % p)' \
  '        if nodelete: continue' \
  '        if os.path.islink(target) or os.path.isfile(target): os.unlink(target)' \
  '        elif os.path.isdir(target): shutil.rmtree(target)' \
  'sys.exit(rc)' > "$SB/bin/rm"
chmod +x "$SB/bin/rm"
export SAFE_RM_TEST_SB="$SB"
PATH="$SB/bin:$PATH"; export PATH; hash -r
[ "$(command -v rm)" = "$SB/bin/rm" ] || { echo "ABORT: fake rm is not first on PATH"; exit 99; }
: > "$SB/rm.log"

# shellcheck disable=SC1090
. "$LIB"

FH="$SB/fakehome/user"
export SAFE_RM_EXTRA_HOMES="$FH"
mkdir -p "$FH/Projects/p/deep/dir" "$FH/scripts" "$FH/.claude-claude4" "$FH/.cache/x" "$FH/.ssh" \
         "$SB/work/a/b/c" "$SB/tmp" "$SB/other"
: > "$FH/Projects/sentinel"; : > "$FH/keep"; : > "$FH/scripts/s"

rmcalls() { wc -l < "$SB/rm.log" | tr -d ' '; }
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]"; }
# refuse label cmd... : expect rc 2 AND no rm invocation
refuse() {
  local label="$1"; shift; local before after rc
  before="$(rmcalls)"; "$@" >/dev/null 2>&1; rc=$?; after="$(rmcalls)"
  if [ "$rc" -eq 2 ] && [ "$before" = "$after" ]; then ok; else bad "$label (rc=$rc, rm calls $before->$after)"; fi
}
allow() { # allow label cmd... : expect rc 0
  local label="$1"; shift; "$@" >/dev/null 2>&1; local rc=$?
  if [ "$rc" -eq 0 ]; then ok; else bad "$label (rc=$rc)"; fi
}
alive() { if [ -e "$1" ]; then ok; else bad "should still exist: $1"; fi; }
gone()  { if [ ! -e "$1" ]; then ok; else bad "should be removed: $1"; fi; }

# --- the incident: empty variable composition ---
W=""
refuse "incident W empty -> /home"   safe_rm_rf "$W/home"
refuse "empty string"                safe_rm_rf ""
refuse "no args"                     safe_rm_rf
refuse "option-like"                 safe_rm_rf "-rf"
refuse "root"                        safe_rm_rf /
refuse "/home"                       safe_rm_rf /home
refuse "/home/"                      safe_rm_rf /home/
refuse "/home/someone"               safe_rm_rf /home/someone
refuse "/usr"                        safe_rm_rf /usr
refuse "/tmp itself"                 safe_rm_rf /tmp
refuse "real HOME itself"            safe_rm_rf "$HOME"
refuse "real HOME trailing slash"    safe_rm_rf "$HOME/"
refuse "real HOME dot"               safe_rm_rf "$HOME/."
refuse "real HOME ancestor"          safe_rm_rf "$(dirname "$HOME")"
refuse "relative ..-chain to /"      safe_rm_rf "../../../../../../../../../.."
refuse "shallow (depth<3)"           safe_rm_rf /srvx/a
refuse "one bad among good"          safe_rm_rf "$SB/work/a/b/c" /usr
alive "$SB/work/a/b/c"      # atomic: bad arg must prevent ALL deletions
alive "$FH/keep"; alive "$FH/Projects/sentinel"

# --- extra home (SAFE_RM_EXTRA_HOMES) treated like $HOME ---
refuse "extra home itself"           safe_rm_rf "$FH"
refuse "extra home trailing slash"   safe_rm_rf "$FH/"
refuse "extra home dot"              safe_rm_rf "$FH/."
refuse "ancestor of extra home"      safe_rm_rf "$SB/fakehome"
refuse "dotdot escapes to extra home" safe_rm_rf "$FH/Projects/.."
SAFE_RM_EXTRA_HOMES="$SB/other:$FH" refuse "second extra home in list" safe_rm_rf "$SB/other"
alive "$SB/other"
SAFE_RM_EXTRA_HOMES="relative/home" refuse "relative extra home is a config error" safe_rm_rf "$SB/work/does/not/exist"

# --- protected home-relative children ---
refuse "protected child scripts"     safe_rm_rf "$FH/scripts"
refuse "protected child Projects"    safe_rm_rf "$FH/Projects/"
refuse "protected child .ssh"        safe_rm_rf "$FH/.ssh"
refuse "protected child glob .claude*" safe_rm_rf "$FH/.claude-claude4"
refuse "protected child .cache"      safe_rm_rf "$FH/.cache"
refuse "protected child of real HOME" safe_rm_rf "$HOME/Projects"
alive "$FH/scripts/s"; alive "$FH/.claude-claude4"
allow  "inside a protected child is deletable" safe_rm_rf "$FH/.cache/x"
gone "$FH/.cache/x"

# --- symlink to protected target ---
ln -s "$FH" "$SB/work/linkhome"
refuse "symlink to extra home"       safe_rm_rf "$SB/work/linkhome/"
ln -s "$FH/scripts" "$SB/work/linkscripts"
refuse "symlink to protected child"  safe_rm_rf "$SB/work/linkscripts/"
alive "$FH/keep"; alive "$FH/scripts/s"

# --- temp root ---
TMPDIR="$SB/tmp" refuse "the temp root itself is refused" safe_rm_rf "$SB/tmp"
alive "$SB/tmp"

# --- allowed-roots barrier ---
SAFE_RM_ALLOWED_ROOTS="$SB/work" refuse "outside allowed root" safe_rm_rf "$FH/Projects/p/deep/dir"
alive "$FH/Projects/p/deep/dir"

# --- readlink -m failure -> refuse (fake readlink fails for one marker path) ---
mkdir -p "$SB/rlbin"
printf '%s\n' '#!/usr/bin/env bash' \
  'for a in "$@"; do case "$a" in *READLINK_FAIL*) exit 1;; esac; done' \
  'exec /usr/bin/readlink "$@"' > "$SB/rlbin/readlink"
chmod +x "$SB/rlbin/readlink"
mkdir -p "$SB/work/READLINK_FAIL/x"
PATH="$SB/rlbin:$PATH" refuse "readlink -m failure refused" safe_rm_rf "$SB/work/READLINK_FAIL/x"
hash -r
alive "$SB/work/READLINK_FAIL/x"

# --- protected list missing / unusable -> fail closed ---
# Sourcing a variant library (mutant or fail-closed copy) in a subshell must REPLACE the inherited function, never fall back to it:
# unset it first and abort the subshell (rc 97) if the mutant does not load.
# shellcheck disable=SC1090
load_mutant() { unset -f safe_rm_rf; . "$1" || exit 97; declare -F safe_rm_rf >/dev/null || exit 97; }
mkdir -p "$SB/nolist" "$SB/emptylist" "$SB/badlist" "$SB/victim/a/b"
cp "$LIB" "$SB/nolist/safe_rm.sh"
cp "$LIB" "$SB/emptylist/safe_rm.sh"; printf '# only a comment\n~/scripts\n' > "$SB/emptylist/protected_paths.list"
cp "$LIB" "$SB/badlist/safe_rm.sh";  { cat "$LIST"; printf 'not-a-valid-entry\n'; } > "$SB/badlist/protected_paths.list"
for d in nolist emptylist badlist; do
  b="$(rmcalls)"
  ( load_mutant "$SB/$d/safe_rm.sh"; safe_rm_rf "$SB/victim/a/b" ) >/dev/null 2>&1; rc=$?
  [ "$rc" -ne 97 ] || bad "variant $d failed to load"
  a="$(rmcalls)"
  if [ "$rc" -eq 2 ] && [ "$b" = "$a" ]; then ok; else bad "list $d must fail closed (rc=$rc, rm calls $b->$a)"; fi
done
alive "$SB/victim/a/b"

# --- legitimate deletes still work (false-positive guard) ---
allow "normal deep dir"             safe_rm_rf "$SB/work/a/b/c"
gone "$SB/work/a/b/c"
allow "nonexistent is ok"           safe_rm_rf "$SB/work/does/not/exist"
allow "project subdir"              safe_rm_rf "$FH/Projects/p/deep/dir"
gone "$FH/Projects/p/deep/dir"
alive "$FH/keep"
SAFE_RM_ALLOWED_ROOTS="$SB/work" allow "inside allowed root" safe_rm_rf "$SB/work/a/b"
gone "$SB/work/a/b"

# --- each rule pinned independently with the depth rule lowered ---
export SAFE_RM_MIN_DEPTH=0
refuse "depth off: root still refused"        safe_rm_rf /
refuse "depth off: /home still refused"       safe_rm_rf /home
refuse "depth off: /usr still refused"        safe_rm_rf /usr
refuse "depth off: user home still refused"   safe_rm_rf /home/someone
refuse "depth off: real HOME still refused"   safe_rm_rf "$HOME"
refuse "depth off: extra home still refused"  safe_rm_rf "$FH"
refuse "depth off: ancestor of extra home"    safe_rm_rf "$SB/fakehome"
refuse "depth off: protected child refused"   safe_rm_rf "$FH/scripts"
refuse "depth off: empty still refused"       safe_rm_rf ""
refuse "depth off: option-like still refused" safe_rm_rf "-rf"
unset SAFE_RM_MIN_DEPTH
SAFE_RM_MIN_DEPTH=abc refuse "non-integer depth refused" safe_rm_rf "$SB/work/a"
SAFE_RM_MIN_DEPTH="" allow "empty depth falls back to default" safe_rm_rf "$SB/work/does/not/exist2"
# a direct child of the temp root is a legitimate scratch dir (depth counted from the temp root)
mkdir -p "$SB/tmp"
TD="$(TMPDIR="$SB/tmp" mktemp -d)" || TD=""
case "$TD" in "$SB/tmp"/?*) ;; *) echo "ABORT: mktemp under $SB/tmp returned '$TD'"; exit 99;; esac
mkdir -p "${TD:?}/child"
TMPDIR="$SB/tmp" allow "child of mktemp root is deletable" safe_rm_rf "$TD/child"
gone "$TD/child"
TMPDIR="$SB/tmp" allow "mktemp -d result itself (direct child of temp root) is deletable" safe_rm_rf "$TD"
gone "$TD"

# --- review round 1 findings (B1, I1-I4) ---
mkdir -p "$SB/work/rr/x/y"
# B1: HOME unset must not silently drop the home rules; refuse (fail closed)
nohome() ( unset HOME; safe_rm_rf "$@" )
refuse "B1 HOME unset -> refuse"                 nohome "$SB/work/rr/x/y"
alive "$SB/work/rr/x/y"
# I1: protected ~/ patterns apply to every /home/<x> and /Users/<x>, not only $HOME
refuse "I1 other user's ~/scripts"               safe_rm_rf /home/otheruser/scripts
refuse "I1 other user's ~/.claude-x"             safe_rm_rf /home/otheruser/.claude-x
refuse "I1 macOS-style /Users/<x>/scripts"       safe_rm_rf /Users/someone/scripts
# I2: a shallow or system TMPDIR must not grant the temp-root depth bonus
TMPDIR=/usr refuse "I2 TMPDIR=/usr does not bypass depth" safe_rm_rf /usr/x
TMPDIR=/srvx refuse "I2 TMPDIR=/srvx (shallow, unlisted)" safe_rm_rf /srvx/x
TMPDIR=relative/tmp refuse "I2 relative TMPDIR"  safe_rm_rf "$SB/work/rr/x"
# I3: absolute list entries are compared after symlink resolution (merged-/usr hosts)
if [ -L /bin ]; then SAFE_RM_MIN_DEPTH=0 refuse "I3 /bin symlink target protected" safe_rm_rf /bin; fi
# I4: a depth setting that breaks the integer comparison must refuse, not pass
SAFE_RM_MIN_DEPTH=99999999999999999999 refuse "I4 overlong depth refused" safe_rm_rf "$SB/work/rr/x"
SAFE_RM_MIN_DEPTH=" 3" refuse "I4 depth with whitespace refused" safe_rm_rf "$SB/work/rr/x"
alive "$SB/work/rr/x/y"
# M: a dangling symlink is deletable, and deleting it leaves its target untouched
ln -s "$SB/does_not_exist_target" "$SB/work/rr/dangling"
allow "dangling symlink deletable" safe_rm_rf "$SB/work/rr/dangling"
gone "$SB/work/rr/dangling"

# F1: a protected home child that is a SYMLINK must be refused lexically, also with a trailing
# slash (rm would follow the link and empty its target); the target stays untouched
mkdir -p "$SB/work/realcfg"; : > "$SB/work/realcfg/precious"
ln -s "$SB/work/realcfg" "$FH/.config"
refuse "F1 protected symlink child, trailing slash" safe_rm_rf "$FH/.config/"
refuse "F1 protected symlink child, no slash"       safe_rm_rf "$FH/.config"
alive "$SB/work/realcfg/precious"
# F5 (false-positive class): a plain symlink leaf elsewhere that points AT a protected path is
# removable as a link (no trailing slash) - rm removes only the link
ln -s "$FH/scripts" "$SB/work/a/linkToScripts"
allow "F5 symlink leaf to protected path is removable as a link" safe_rm_rf "$SB/work/a/linkToScripts"
alive "$FH/scripts/s"; gone "$SB/work/a/linkToScripts"
ln -s "$FH/scripts" "$SB/work/a/linkToScripts2"
refuse "F5 same link WITH trailing slash is refused" safe_rm_rf "$SB/work/a/linkToScripts2/"
alive "$FH/scripts/s"
# F2: sourced without a usable BASH_SOURCE (eval of the file text) must fail closed, never read
# a protected list from the current directory
mkdir -p "$SB/evil"; printf '%s\n' '/nonexistent_only_entry' > "$SB/evil/protected_paths.list"
( cd "$SB/evil" && eval "$(cat "$LIB")" && safe_rm_rf "$FH/scripts" ) >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 2 ]; then ok; else bad "F2 eval-sourced lib must refuse (rc=$rc)"; fi
alive "$FH/scripts/s"
# F3: leading-zero depth and newline-bearing targets refuse cleanly with rc 2 (no arithmetic abort)
SAFE_RM_MIN_DEPTH=08 refuse "F3 leading-zero depth 08" safe_rm_rf "$SB/work/rr/x"
SAFE_RM_MIN_DEPTH=010 refuse "F3 leading-zero depth 010" safe_rm_rf "$SB/work/rr/x"
NL="$SB/work/a/new
line"
refuse "F3 newline in target" safe_rm_rf "$NL"
# F4: ALLOWED_ROOTS / EXTRA_HOMES are not glob-expanded and relative roots are config errors
mkdir -p "$SB/work/a/b/c"  # recreate: the allow-case above removed it
SAFE_RM_ALLOWED_ROOTS='/*' refuse "F4 glob allowed root" safe_rm_rf "$SB/work/a/b/c"
SAFE_RM_ALLOWED_ROOTS='relroot' refuse "F4 relative allowed root" safe_rm_rf "$SB/work/a/b/c"
alive "$SB/work/a/b/c"
# F6: a last component of . or .. is refused cleanly (rc 2), not passed on to rm
refuse "F6 trailing /."   safe_rm_rf "$SB/work/a/b/."
refuse "F6 trailing /.."  safe_rm_rf "$SB/work/a/b/c/.."

# B1: an eval-loaded or foreign-symlinked library must NOT read a protected list from the caller's directory
mkdir -p "$SB/caller"; printf '%s\n' '/nonexistent_only_entry' > "$SB/caller/protected_paths.list"
printf '%s\n' 'eval "$(cat "$1")"' 'safe_rm_rf "$2"' > "$SB/caller/c.sh"
bash "$SB/caller/c.sh" "$LIB" "$FH/scripts" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 2 ]; then ok; else bad "B1 eval from caller dir with weak list must refuse (rc=$rc)"; fi
alive "$FH/scripts/s"
ln -s "$LIB" "$SB/caller/safe_rm.sh"
printf '%s\n' '. "$1"' 'safe_rm_rf "$2"' > "$SB/caller/c2.sh"
bash "$SB/caller/c2.sh" "$SB/caller/safe_rm.sh" "$FH/scripts" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 2 ]; then ok; else bad "B1 symlinked lib must use the real list next to the real file (rc=$rc)"; fi
alive "$FH/scripts/s"
cp "$LIB" "$SB/caller/renamed.sh"
printf '%s\n' '. "$1"' 'safe_rm_rf "$2"' > "$SB/caller/c3.sh"
bash "$SB/caller/c3.sh" "$SB/caller/renamed.sh" "$FH/scripts" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 2 ]; then ok; else bad "B1 library copy not named safe_rm.sh must refuse (rc=$rc)"; fi
alive "$FH/scripts/s"
# I1: a SET but empty-yielding allow-list / extra-homes must fail closed, never open
mkdir -p "$SB/work/a/b/c"
SAFE_RM_ALLOWED_ROOTS='' refuse "I1 empty allowed roots (set)" safe_rm_rf "$SB/work/a/b/c"
SAFE_RM_ALLOWED_ROOTS=':' refuse "I1 colon-only allowed roots" safe_rm_rf "$SB/work/a/b/c"
SAFE_RM_ALLOWED_ROOTS=$'\n/x' refuse "I1 newline-first allowed roots" safe_rm_rf "$SB/work/a/b/c"
SAFE_RM_EXTRA_HOMES=$'\n'"$FH" refuse "I1 newline-first extra homes" safe_rm_rf "$FH/scripts"
alive "$SB/work/a/b/c"; alive "$FH/scripts/s"
# M3: allowed root '/' is legitimate (everything below passes the root rule)
mkdir -p "$SB/work/rootok/x/y"
SAFE_RM_ALLOWED_ROOTS='/' allow "M3 allowed root /" safe_rm_rf "$SB/work/rootok/x/y"
# I2: other users' homes under a resolved/injected home root are protected like /home/<user>
mkdir -p "$SB/vh/otheruser/.ssh" "$SB/vh/otheruser/cache/x"
ln -s "$SB/vh" "$SB/homelink"
SAFE_RM_EXTRA_HOME_ROOTS="$SB/vh" refuse "I2 other user home" safe_rm_rf "$SB/vh/otheruser"
SAFE_RM_EXTRA_HOME_ROOTS="$SB/vh" refuse "I2 other user .ssh" safe_rm_rf "$SB/vh/otheruser/.ssh"
SAFE_RM_EXTRA_HOME_ROOTS="$SB/homelink" refuse "I2 via symlinked home root" safe_rm_rf "$SB/homelink/otheruser"
SAFE_RM_EXTRA_HOME_ROOTS="$SB/vh" allow "I2 deep cache under other home" safe_rm_rf "$SB/vh/otheruser/cache/x"
SAFE_RM_EXTRA_HOME_ROOTS="relative" refuse "I2 relative home root is a config error" safe_rm_rf "$SB/work/a/b/c"
alive "$SB/vh/otheruser/.ssh"
# M2: HOME-like entry "/" must still apply protected children (no '//' pattern hole)
SAFE_RM_EXTRA_HOMES="/" refuse "M2 home / protects /.ssh style children" safe_rm_rf /Projects

# I-c: the injected home root itself and its ancestors are protected, not only the homes below it
mkdir -p "$SB/deep/a/vh/u1"
SAFE_RM_EXTRA_HOME_ROOTS="$SB/deep/a/vh" refuse "R3 home root itself" safe_rm_rf "$SB/deep/a/vh"
SAFE_RM_EXTRA_HOME_ROOTS="$SB/deep/a/vh" refuse "R3 ancestor of home root" safe_rm_rf "$SB/deep/a"
alive "$SB/deep/a/vh/u1"

# --- review round 2 (2026-10-24): S3 temp-root depth bonus vs homes, S1 what is removed ---
# S3: a temp root that IS a home root (or an ancestor of a home / home root) buys no depth bonus.
# SAFE_RM_MIN_DEPTH=99 makes the bonus the only way past the depth rule.
mkdir -p "$SB/s3/u/p/x" "$SB/s3b/h1" "$SB/zz/y/x"
TMPDIR="$SB/s3" SAFE_RM_EXTRA_HOME_ROOTS="$SB/s3" SAFE_RM_MIN_DEPTH=99 refuse "S3 temp root is a home root: no depth bonus" safe_rm_rf "$SB/s3/u/p/x"
TMPDIR="$SB" SAFE_RM_EXTRA_HOMES="$SB/s3b/h1" SAFE_RM_MIN_DEPTH=99 refuse "S3 temp root is an ancestor of a home: no depth bonus" safe_rm_rf "$SB/zz/y/x"
mkdir -p "$SB/zz/y/x"
TMPDIR="$SB" SAFE_RM_EXTRA_HOME_ROOTS="$SB/s3b" SAFE_RM_MIN_DEPTH=99 refuse "S3 temp root is an ancestor of a home root: no depth bonus" safe_rm_rf "$SB/zz/y/x"
mkdir -p "$SB/tmp/c1/d"
TMPDIR="$SB/tmp" SAFE_RM_MIN_DEPTH=99 allow "S3 control: ordinary temp root still buys the bonus" safe_rm_rf "$SB/tmp/c1/d"
gone "$SB/tmp/c1/d"
# S1: "link/" whose link points at an unprotected dir: only the LINK is removed, never the target
mkdir -p "$SB/work/s1tgt/keep"
ln -s "$SB/work/s1tgt" "$SB/work/s1lnk"
allow "S1 link/ to an unprotected dir is accepted" safe_rm_rf "$SB/work/s1lnk/"
gone "$SB/work/s1lnk"
alive "$SB/work/s1tgt/keep"

# --- mutation audit (2026-10-24): tests for mutants that survived the earlier suite ---
# S06: a newline in a path is a CLEAN refusal (rc 2 + the specific message), not an accidental one
NL2="$SB/work/a/n"$'\n'"l/zz"
out="$( safe_rm_rf "$NL2" 2>&1 )"; rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q "path contains a newline"; then ok; else bad "S06 newline path: rc=$rc msg=$out"; fi
# S15: TMPDIR must not buy depth when the temp root is itself a protected path of depth >= 2.
# The shipped list has only depth-1 absolute entries, so use a COPY of the lib whose list gains /usr/local.
mkdir -p "$SB/libcopy"
cp "$LIB" "$SB/libcopy/safe_rm.sh"
{ cat "$LIST"; printf '%s\n' "/usr/local"; } > "$SB/libcopy/protected_paths.list"
( . "$SB/libcopy/safe_rm.sh"; TMPDIR=/usr/local SAFE_RM_MIN_DEPTH=5 safe_rm_rf /usr/local/zz_nonexistent ) >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 2 ]; then ok; else bad "S15 protected TMPDIR buys no depth bonus (rc=$rc)"; fi
# S15 control: an unprotected temp root of the same depth does buy the bonus (the test is not vacuous)
mkdir -p "$SB/tmp2/c1/d"
( . "$SB/libcopy/safe_rm.sh"; TMPDIR="$SB/tmp2" SAFE_RM_MIN_DEPTH=99 safe_rm_rf "$SB/tmp2/c1/d" ) >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ]; then ok; else bad "S15 control: ordinary temp root buys the bonus (rc=$rc)"; fi
# S14: missing protected list -> refusal carries the SPECIFIC message
mkdir -p "$SB/libnolist"; cp "$LIB" "$SB/libnolist/safe_rm.sh"
out="$( . "$SB/libnolist/safe_rm.sh"; safe_rm_rf "$SB/work/a/b/c" 2>&1 )"; rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q "protected list not readable"; then ok; else bad "S14 missing list message: rc=$rc msg=$out"; fi
alive "$SB/work/a/b/c"

# --- per-entry coverage of protected_paths.list (review round 1, finding 5) ---
# Two independent sources: (a) a REQUIRED set written out in this file, so that deleting an entry from
# the list cannot also delete its test; (b) every entry actually present in the list file. Each entry
# gets its own refusal case; each home-relative entry also gets a per-entry mutant (list copy without
# that one line) that must stop being refused, proving the entry itself carries the refusal.
REQ_ABS="/bin /boot /dev /etc /lib /lib32 /lib64 /libx32 /opt /proc /root /run /sbin /srv /sys /usr /var /mnt /media /snap /home /tmp /Users"
REQ_REL="scripts Projects .ssh .gnupg .claude* .config .local vasic ytdlp backups .cache"
n_req=0
for e in $REQ_ABS; do
  n_req=$((n_req+1))
  if grep -qxF -- "$e" "$LIST"; then ok; else bad "required absolute entry missing from list: $e"; fi
  refuse "list entry (abs) $e" safe_rm_rf "$e"
done
set -f
for e in $REQ_REL; do
  n_req=$((n_req+1))
  if grep -qxF -- "~/$e" "$LIST"; then ok; else bad "required home-relative entry missing from list: ~/$e"; fi
done
set +f
# every entry present in the file (covers entries added later), with a control needle on the count
n_list=0
while IFS= read -r line; do
  line="${line#"${line%%[![:space:]]*}"}"; line="${line%"${line##*[![:space:]]}"}"
  case "$line" in ""|"#"*) continue;; esac
  n_list=$((n_list+1))
  case "$line" in
    /*) refuse "list file entry (abs) $line" safe_rm_rf "$line";;
    "~/"*)
      comp="${line#\~/}"; conc="${comp//\*/zz}"; conc="${conc//\?/z}"
      mkdir -p "$FH/$conc"; : > "$FH/$conc/.keep_entry"
      refuse "list file entry (home) ~/$comp" safe_rm_rf "$FH/$conc"
      alive "$FH/$conc/.keep_entry"
      if [[ "$comp" != *'['* ]]; then
        # per-entry mutant: the same list without this one line must no longer refuse the child
        md="$SB/pe_mut_$n_list"; mkdir -p "$md"; cp "$LIB" "$md/safe_rm.sh"
        grep -vxF -- "$line" "$LIST" > "$md/protected_paths.list"
        if [ "$(wc -l < "$md/protected_paths.list")" -ge "$(wc -l < "$LIST")" ]; then bad "per-entry mutant not applied for $line"
        else
          ( . "$md/safe_rm.sh"; FAKE_RM_NODELETE=1 safe_rm_rf "$FH/$conc" ) >/dev/null 2>&1; mrc=$?
          if [ "$mrc" -ne 2 ]; then ok; else bad "per-entry mutant for $line survives (still refused without the entry)"; fi
        fi
      fi;;
    *) bad "unexpected list entry shape: $line";;
  esac
done < "$LIST"
if [ "$n_list" -ge "$n_req" ]; then ok; else bad "control: list has $n_list entries, fewer than the $n_req required"; fi
# negative control: an unlisted child of the fake home is deletable (the refusals above are not vacuous)
mkdir -p "$FH/notlisted_zz/x"
allow "negative control: unlisted home child is deletable" safe_rm_rf "$FH/notlisted_zz/x"
gone "$FH/notlisted_zz/x"

# --- the fake rm never had to block anything (no attempt left the sandbox) ---
if grep -q '^BLOCKED' "$SB/rm.log"; then bad "fake rm blocked an out-of-sandbox delete: $(grep '^BLOCKED' "$SB/rm.log" | head -3 | tr '\n' ' ')"; else ok; fi

# --- paired mutations (each must make a test above fail) ---
mutate() { # name marker -> prints path of mutated lib; FAIL if sed changed nothing
  local name="$1" marker="$2" d="$SB/mut_$1"
  mkdir -p "$d"; cp "$LIST" "$d/protected_paths.list"
  sed "/# MUT:$marker\$/d" "$LIB" > "$d/safe_rm.sh"
  if cmp -s "$LIB" "$d/safe_rm.sh"; then echo "FAIL [mutation $name not applied: marker MUT:$marker missing]" >&2; return 1; fi
  if ! bash -n "$d/safe_rm.sh" 2>/dev/null; then echo "FAIL [mutation $name produced a file that does not parse]" >&2; return 1; fi
  printf '%s\n' "$d/safe_rm.sh"
}
# M1: neuter the protected-child check -> "protected child scripts" must no longer be refused
if M1="$(mutate protected_child protected-child)"; then
  ( load_mutant "$M1"; FAKE_RM_NODELETE=1 safe_rm_rf "$FH/scripts" ) >/dev/null 2>&1; rc=$?
  [ "$rc" -ne 97 ] || bad "mutant protected-child failed to load"
  if [ "$rc" -ne 2 ]; then ok; else bad "mutation protected-child not detected (still rc=2)"; fi
  alive "$FH/scripts/s"
else bad "mutation protected-child could not be applied"; fi
# M2: remove the empty-arg check -> the specific empty-path refusal message must disappear
if M2="$(mutate empty_arg empty-arg)"; then
  msg="$( load_mutant "$M2"; safe_rm_rf "" 2>&1 )"; [ "$?" -ne 97 ] || bad "mutant empty-arg failed to load"
  case "$msg" in *"empty path"*) bad "mutation empty-arg not detected";; *) ok;; esac
  # shellcheck disable=SC1090
  msg="$( . "$LIB"; safe_rm_rf "" 2>&1 )"
  case "$msg" in *"empty path"*) ok;; *) bad "control: unmutated lib lost the empty-path message";; esac
else bad "mutation empty-arg could not be applied"; fi

# M3: remove the lexical-path candidate -> a protected plain target is no longer validated at all
if M3="$(mutate lexical lexical)"; then
  ( load_mutant "$M3"; FAKE_RM_NODELETE=1 safe_rm_rf "$FH/scripts" ) >/dev/null 2>&1; rc=$?
  [ "$rc" -ne 97 ] || bad "mutant lexical failed to load"
  if [ "$rc" -ne 2 ]; then ok; else bad "mutation lexical not detected (still rc=2)"; fi
  alive "$FH/scripts/s"
else bad "mutation lexical could not be applied"; fi
echo "safe_rm tests: pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
