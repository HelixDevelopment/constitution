#!/bin/bash
# fastcycle-timeout-s: 1200
# Purpose : CON-146 regression guard for
#           `constitution/scripts/fastcycle/orchestration/custody_sweep.py`:
#           the stash patch (inventory hash + verify-proposal live hash) is
#           derived with `git diff <CANONICAL_PATCH_OPTS> <ref>^1 <ref>`, never
#           `git stash show -p`; EVERY `diff --git` header (each side bare or
#           C-quoted, carrying the a/ b/ prefixes) is checked and a patch with
#           one bad header is reported as UNMEASURED (never hashed), naming the
#           real cause. CON-157: the display-only file list names both paths
#           of a rename and C-quoted, spaced and non-ASCII paths correctly.
# Forensic: measured on git 2.53.0, `git stash show -p --src-prefix=a/
#           --dst-prefix=b/` printed `diff --git f sf`, `diff --git f |f`
#           (different on every run), so every stash `land` was REFUSED as a
#           stale backup (r11 B2, r13 G7, r15 G3 RED on that host).
# Usage   : bash test_custody_sweep_stash_patch_r22_regression.sh
#           Exit 0 when every check passes, 1 otherwise. The last line is the
#           summary line.
# Method  : REAL throwaway git repositories under a temp dir (never this
#           project's repo); the REAL tool's `inventory` and `verify-proposal`
#           CLIs. Host independence: PATH shims around the real git make the
#           result the same on any git version. `stashshow` mangles the headers
#           of `git stash show` output (models the 2.53.0 bug); `diffpos`
#           rewrites ONE chosen `diff --git` header (or all, or makes the diff
#           fail) of `git diff ... <ref>^1 <ref>` output.
#           Fixture axes (CON-146 review round 2, finding R2-F1-A: a fixture
#           on which a partial implementation gives the same answer as the
#           correct one proves nothing): header POSITION (first, middle, last
#           of a three-header stash), garble QUOTING (bare `f xf`, quoted with
#           no prefixes `"f" "xf"`), git diff FAILURE (cause text), a correct
#           MIXED-quoting header (bare a/ side, quoted b/ side), file-list
#           SHAPES (rename, spaces, `x b/y.txt`, quotes, non-ASCII, binary,
#           mode change, delete, add). Paired mutations on a copy of the tool:
#           each must fail at least the functional check named for it (the
#           partial implementation it models disagrees with the correct one on
#           that fixture); a mutation that only breaks an anchor is reported
#           as an anchor failure, never as caught.
#           Round 4 (CON-146 review round 3, class recurrence #3: hand-picked
#           fixtures let partial implementations through): the same class is now
#           covered as a MATRIX (check MX: header count 1..7 x both section orders
#           x three git configs x every header position x garbled a half, b half,
#           both halves, bare, quoted; section types text, binary, new, empty-new,
#           deleted, mode-only, rename, copy, non-UTF-8 name; expected header count
#           and file list taken from git's own `diff -z --name-status`, never from
#           the tool) plus the CLI axes XS (one half of one header), XC (each
#           header of five), XB/XB1 (after / at a binary section), XM (deleted,
#           new, mode-only), XG (header-like body lines, a CR), XQ
#           (core.quotePath=false, Latin-1 name). The reviewer mutants NM1..NM13
#           (header tripwire) and FL1/3..10 (file list) run as self-tests, each
#           against the named checks. Run time is about 7 minutes.
#           Round 5 (CON-146 review round 4): F2 -- the matrix repositories were
#           made by mkdtemp under $TMPDIR and never removed (measured: 35 dirs,
#           168 MB per run); the matrix now removes its base at exit, runs with
#           its own TMPDIR, and check MX fails when anything is left there; the
#           whole test runs with TMPDIR under its own temp dir and check TD
#           fails when anything is left there at the end. F3 -- an empty stash
#           patch (untracked-only `stash -u`: EP1; index-only change: EP2) is
#           `empty_patch`, never UNMEASURED, and `land` of an untracked-only
#           stash is refused for its untracked content, not as unreadable
#           (EP1V); reviewer mutant RD and its live-path twin RD2 run as
#           self-tests. Round 6 (review fsfix5 M1): `land` of the index-only
#           stash with a faithful empty backup is refused for its INDEX
#           content, never as a stale backup (EP2V; paired mutant EP2M).
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
IMPL="$FC/orchestration/custody_sweep.py"
LIB="$FC/lib/fc_common.py"
EXLIB="$FC/lib/fc_entry.py"

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES \
      GIT_CONFIG GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS GIT_CEILING_DIRECTORIES GIT_NAMESPACE GIT_PREFIX \
      GIT_COMMON_DIR CUSTODY_SWEEP_GIT_TIMEOUT_S SHIM_POS SHIM_TEXT SHIM_FAIL
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

g() { git -c commit.gpgsign=false -c core.hooksPath=/dev/null -c init.defaultBranch=main "$@"; }
CANON=(--binary --no-color --no-ext-diff --no-textconv --no-relative --src-prefix=a/ --dst-prefix=b/ --ignore-submodules=none)
TAB=$'\t'

fail=0
pass=0
ok() { pass=$((pass + 1)); echo "ok $*"; }
notok() { fail=$((fail + 1)); echo "NOT ok $*"; }

TMP=$(mktemp -d)
trap 'rm -rf "${TMP:?}"' EXIT
# CON-146 round 5 (review round 4, F2: the matrix left 35 dirs / 168 MB in the
# caller's TMPDIR per run): every child of this test writes its temporaries
# under $TMP, which the EXIT trap removes; the leak checks are MX (per matrix
# run) and TD (the whole run) below.
export TMPDIR="$TMP/tmpdir"
mkdir -p "$TMPDIR"

for p in "$IMPL" "$LIB" "$EXLIB"; do [ -f "$p" ] || notok "control needle: $p not found"; done
REALGIT=$(command -v git) || notok "control needle: git not on PATH"
[ "$fail" = 0 ] && ok "control needle: implementation + libs resolve, git at $REALGIT"

sha() { sha256sum "$1" | cut -d' ' -f1; }

# --- shims (each forwards to the real git; only the named output changes) ---
mkdir -p "$TMP/shim_stashshow" "$TMP/shim_diffpos"
cat > "$TMP/shim_stashshow/git" <<EOF
#!/bin/bash
real=$REALGIT
case " \$* " in *" stash show "*)
  set -o pipefail
  "\$real" "\$@" | sed -e 's#^diff --git .*#diff --git f xf#'
  exit \$? ;;
esac
exec "\$real" "\$@"
EOF
# diffpos: only a call that has the argument `diff` AND an argument ending in
# `^1` (the stash patch derivation). SHIM_FAIL=1: print nothing, exit 3.
# Otherwise SHIM_POS = 1, 2, 3, ... or all: that `diff --git` header is
# replaced by SHIM_TEXT; every other byte is passed through.
cat > "$TMP/shim_diffpos/git" <<EOF
#!/bin/bash
real=$REALGIT
d=0; c=0
for a in "\$@"; do case \$a in diff) d=1 ;; *'^1') c=1 ;; esac; done
if [ \$d = 1 ] && [ \$c = 1 ]; then
  [ "\${SHIM_FAIL:-0}" = 1 ] && { echo "shim: forced git diff failure" >&2; exit 3; }
  if [ -n "\${SHIM_POS:-}" ]; then
    set -o pipefail
    "\$real" "\$@" | SHIM_POS="\$SHIM_POS" SHIM_TEXT="\${SHIM_TEXT:-diff --git f xf}" awk '
      /^diff --git / { n++; if (ENVIRON["SHIM_POS"] == "all" || n == ENVIRON["SHIM_POS"] + 0) { print ENVIRON["SHIM_TEXT"]; next } }
      { print }'
    exit \$?
  fi
fi
exec "\$real" "\$@"
EOF
chmod +x "$TMP/shim_stashshow/git" "$TMP/shim_diffpos/git"

# --- repo R: one plain stash (one tracked change) and its faithful backup ---
R="$TMP/r"
g init --quiet "$R"
printf 'one\n' > "$R/f"; g -C "$R" add f; g -C "$R" commit --quiet -m init
printf 'two\n' > "$R/f"; g -C "$R" stash --quiet
g -C "$R" diff "${CANON[@]}" 'stash@{0}^1' 'stash@{0}' > "$TMP/st.patch"
if head -1 "$TMP/st.patch" | grep -qx 'diff --git a/f b/f'; then
  ok "control needle: the test's own backup has canonical a/ b/ headers"
else
  notok "control needle: backup header is '$(head -1 "$TMP/st.patch")'"
fi
WANT_SHA=$(sha "$TMP/st.patch")

# --- repo R3: a THREE-header stash; the MIDDLE header mixes a bare and a
# C-quoted path (git quotes each path on its own; a rename to a name with a
# TAB prints `diff --git a/b2.txt "b/b2 sp\ttab.txt"`, measured on git 2.53.0).
R3="$TMP/r3"
g init --quiet "$R3"
for f in a1 b2 c3; do printf '%s\n' "$f" > "$R3/$f.txt"; done
g -C "$R3" add a1.txt b2.txt c3.txt; g -C "$R3" commit --quiet -m init
g -C "$R3" mv b2.txt "b2 sp${TAB}tab.txt"; printf 'a1x\n' > "$R3/a1.txt"; printf 'c3x\n' > "$R3/c3.txt"
g -C "$R3" stash --quiet
g -C "$R3" diff "${CANON[@]}" 'stash@{0}^1' 'stash@{0}' > "$TMP/st3.patch"
H3=$(grep '^diff --git ' "$TMP/st3.patch" | tr '\n' '|')
if [ "$H3" = 'diff --git a/a1.txt b/a1.txt|diff --git a/b2.txt "b/b2 sp\ttab.txt"|diff --git a/c3.txt b/c3.txt|' ]; then
  ok "control needle: repo 3 patch = plain, mixed-quoting, plain header"
else
  notok "control needle: repo 3 headers are '$H3'"
fi
WANT_SHA3=$(sha "$TMP/st3.patch")

# Shim self-checks (control needles): the stashshow shim mangles `stash show`
# only; diffpos rewrites exactly the chosen header and nothing else.
if PATH="$TMP/shim_stashshow:$PATH" git -C "$R" stash show -p "${CANON[@]}" 'stash@{0}' | head -1 | grep -qx 'diff --git f xf' \
   && PATH="$TMP/shim_stashshow:$PATH" git -C "$R" diff "${CANON[@]}" 'stash@{0}^1' 'stash@{0}' | cmp -s - "$TMP/st.patch"; then
  ok "shim self-check: stashshow mangles 'stash show' headers only"
else
  notok "shim self-check: stashshow shim does not behave as designed"
fi
selfcheck_pos() {  # POS TEXT -> 0 when only header POS of the R3 patch changed to TEXT
  local got want
  got=$(SHIM_POS=$1 SHIM_TEXT=$2 PATH="$TMP/shim_diffpos:$PATH" git -C "$R3" diff "${CANON[@]}" 'stash@{0}^1' 'stash@{0}') || return 1
  want=$(awk -v p="$1" -v t="$2" '/^diff --git /{n++; if (p == "all" || n == p + 0) {print t; next}} {print}' "$TMP/st3.patch")
  [ "$got" = "$want" ] && [ "$got" != "$(cat "$TMP/st3.patch")" ]
}
sc=ok
for p in 1 2 3 all; do selfcheck_pos "$p" 'diff --git f xf' || sc="pos $p bare"; done
for p in 1 2 3; do selfcheck_pos "$p" 'diff --git "f" "xf"' || sc="pos $p quoted"; done
if SHIM_FAIL=1 PATH="$TMP/shim_diffpos:$PATH" git -C "$R3" diff "${CANON[@]}" 'stash@{0}^1' 'stash@{0}' >/dev/null 2>&1; then sc="fail mode exits 0"; fi
if PATH="$TMP/shim_diffpos:$PATH" git -C "$R3" diff "${CANON[@]}" 'stash@{0}^1' 'stash@{0}' | cmp -s - "$TMP/st3.patch"; then :; else sc="pass-through changed the patch"; fi
if SHIM_FAIL=1 PATH="$TMP/shim_diffpos:$PATH" git -C "$R3" rev-parse 'stash@{0}^1' >/dev/null 2>&1; then :; else sc="fail mode hit a non-diff call"; fi
if [ "$sc" = ok ]; then ok "shim self-check: diffpos rewrites only the chosen header (1, 2, 3, all; bare and quoted), fails only git diff"
else notok "shim self-check: diffpos does not behave as designed ($sc)"; fi
# Host evidence only (never decides PASS): is this host's `stash show -p` canonical?
echo "info: host $(git --version): 'git stash show -p' first header = '$(git -C "$R" stash show -p "${CANON[@]}" 'stash@{0}' | head -1)'"

# --- repo R4 (CON-157): file-list shapes ---
R4="$TMP/r4"
g init --quiet "$R4"
mkdir -p "$R4/x b"
printf '1\n' > "$R4/x b/y.txt"; printf 'u\n' > "$R4/ünï.txt"; printf 'd\n' > "$R4/del.txt"; printf 'm\n' > "$R4/mode.sh"
printf '\000\001' > "$R4/bin.dat"; printf 'q\n' > "$R4/q\"\\.txt"; printf 'r\n' > "$R4/old.txt"
g -C "$R4" add -A; g -C "$R4" commit --quiet -m init
printf '2\n' > "$R4/x b/y.txt"; printf 'u2\n' > "$R4/ünï.txt"; g -C "$R4" rm --quiet del.txt; chmod +x "$R4/mode.sh"
printf '\000\002' > "$R4/bin.dat"; printf 'q2\n' > "$R4/q\"\\.txt"; printf 'new\n' > "$R4/new file.txt"
g -C "$R4" add "new file.txt"; g -C "$R4" mv old.txt "new name.txt"
g -C "$R4" stash --quiet
# Expected list, built from git's own -z name-status (unambiguous, raw bytes):
# both paths of a rename, every other path once, in patch order.
WANT_FILES4=$(g -C "$R4" diff -z --name-status --no-color 'stash@{0}^1' 'stash@{0}' | python3 -c '
import sys
t = sys.stdin.buffer.read().split(b"\0")
out, i = [], 0
while i < len(t) and t[i]:
    st = t[i].decode()
    if st[0] in "RC":
        out += [t[i + 1], t[i + 2]] if st[0] == "R" else [t[i + 2]]; i += 3
    else:
        out.append(t[i + 1]); i += 2
print(",".join(p.decode("utf-8", "surrogateescape") for p in out))')
case "$WANT_FILES4" in
  *"x b/y.txt"*"ünï.txt"*) ok "control needle: repo 4 expected file list built from git -z name-status ($WANT_FILES4)" ;;
  *) notok "control needle: repo 4 expected file list unexpected: '$WANT_FILES4'" ;;
esac
WANT_FILES3="a1.txt,b2.txt,b2 sp${TAB}tab.txt,c3.txt"

# --- round-4 repos (CON-146 review round 3: the axes a hand-picked fixture set
# left open). Each is a plain stash made in a throwaway repo; a control needle
# per repo proves the shape it is named for really is in its patch.
mkrepo() { g init --quiet "$1"; }
R5="$TMP/r5"; mkrepo "$R5"; for i in 1 2 3 4 5; do printf '%s\n' $i > "$R5/f$i.txt"; done
g -C "$R5" add -A; g -C "$R5" commit --quiet -m i; for i in 1 2 3 4 5; do printf '%sx\n' $i > "$R5/f$i.txt"; done; g -C "$R5" stash --quiet
RB="$TMP/rb"; mkrepo "$RB"; printf '\000\001' > "$RB/a.bin"; printf 't\n' > "$RB/b.txt"; g -C "$RB" add -A; g -C "$RB" commit --quiet -m i
printf '\000\002' > "$RB/a.bin"; printf 't2\n' > "$RB/b.txt"; g -C "$RB" stash --quiet
RM="$TMP/rm"; mkrepo "$RM"; printf 'd\n' > "$RM/d.txt"; printf 'm\n' > "$RM/m.sh"; printf 'n\n' > "$RM/n.txt"; g -C "$RM" add -A; g -C "$RM" commit --quiet -m i
g -C "$RM" rm --quiet d.txt; : > "$RM/e.txt"; g -C "$RM" add e.txt; chmod +x "$RM/m.sh"; printf 'n2\n' > "$RM/n.txt"; g -C "$RM" stash --quiet
RG="$TMP/rg"; mkrepo "$RG"; printf 'keep\n' > "$RG/p.txt"; g -C "$RG" add -A; g -C "$RG" commit --quiet -m i
printf 'keep\ndiff --git f xf\ny\rdiff --git "f" "xf"\n diff --git a/q xq\n' > "$RG/p.txt"; g -C "$RG" stash --quiet
g -C "$RG" diff "${CANON[@]}" 'stash@{0}^1' 'stash@{0}' > "$TMP/stg.patch"; WANT_SHAG=$(sha "$TMP/stg.patch")
RQ="$TMP/rq"; mkrepo "$RQ"; g -C "$RQ" config core.quotePath false; printf 'a\n' > "$RQ/caf$(printf '\351').txt"; printf 'b\n' > "$RQ/ünï.txt"
g -C "$RQ" add -A; g -C "$RQ" commit --quiet -m i; printf 'a2\n' > "$RQ/caf$(printf '\351').txt"; printf 'b2\n' > "$RQ/ünï.txt"; g -C "$RQ" stash --quiet
g -C "$RQ" diff "${CANON[@]}" 'stash@{0}^1' 'stash@{0}' > "$TMP/stq.patch"; WANT_SHAQ=$(sha "$TMP/stq.patch")
[ "$(g -C "$R5" diff "${CANON[@]}" 'stash@{0}^1' 'stash@{0}' | grep -c '^diff --git ')" = 5 ] && ok "control needle: repo 5 has 5 headers" || notok "control needle: repo 5 header count"
[ "$(g -C "$RB" diff "${CANON[@]}" 'stash@{0}^1' 'stash@{0}' | grep -c 'GIT binary patch')" -ge 1 ] && ok "control needle: repo B has a binary section" || notok "control needle: repo B has no binary section"
g -C "$RM" diff "${CANON[@]}" 'stash@{0}^1' 'stash@{0}' > "$TMP/stm.patch"
if grep -q '^deleted file mode' "$TMP/stm.patch" && grep -q '^new file mode' "$TMP/stm.patch" && grep -q '^old mode' "$TMP/stm.patch"; then
  ok "control needle: repo M has deleted, new and mode-only sections"; else notok "control needle: repo M shapes"; fi
grep -q 'caf' "$TMP/stq.patch" && ! grep -q '^diff --git a/"' "$TMP/stq.patch" && ok "control needle: repo Q patch holds unquoted non-ASCII names" || notok "control needle: repo Q names"

# --- round-5 repos (F3): REU = untracked-only stash, REP = index-only change
# whose worktree equals HEAD; control needles: both tracked patches are empty,
# REU has the untracked third parent, REP has none.
REU="$TMP/reu"; mkrepo "$REU"; printf 'one\n' > "$REU/f"; g -C "$REU" add f; g -C "$REU" commit --quiet -m i
printf 'u\n' > "$REU/u.txt"; g -C "$REU" stash -u --quiet
REP="$TMP/rep"; mkrepo "$REP"; printf 'one\n' > "$REP/f"; g -C "$REP" add f; g -C "$REP" commit --quiet -m i
printf 'two\n' > "$REP/f"; g -C "$REP" add f; printf 'one\n' > "$REP/f"; g -C "$REP" stash --quiet
: > "$TMP/empty.patch"
if [ -z "$(g -C "$REU" diff "${CANON[@]}" 'stash@{0}^1' 'stash@{0}')" ] && [ -z "$(g -C "$REP" diff "${CANON[@]}" 'stash@{0}^1' 'stash@{0}')" ] \
   && g -C "$REU" rev-parse -q --verify 'stash@{0}^3' >/dev/null && ! g -C "$REP" rev-parse -q --verify 'stash@{0}^3' >/dev/null; then
  ok "control needle: repos EU and EP have empty tracked patches; EU has an untracked parent, EP none"
else
  notok "control needle: repos EU / EP do not have the shapes they are named for"
fi

# --- the MATRIX over the whole class "which headers does the tripwire see".
# Cells = fixture (header count 1..7 x two section orders x three git configs)
# x header position x garble form (a half, b half, both halves, bare no-prefix,
# quoted no-prefix). The expectation of a cell is NOT taken from the tool: the
# header count and each section's status and paths come from git's own
# `diff -z --name-status`, and the garble is applied by this script to the raw
# patch bytes. In-process: the tool's own `_run_bytes` is replaced by a
# function that returns the (garbled or faithful) bytes, so every cell costs
# no process. Also asserted per cell set: the faithful patch is trusted, its
# file list equals the oracle's, and the fixtures really contain every
# section type (text, binary, new, empty-new, deleted, mode-only, rename, copy,
# non-UTF-8 name, a removed line `-- a/zz.txt` and an added line `++ b/zz.txt`
# (they print as `--- a/zz.txt` / `+++ b/zz.txt` and look like path lines),
# header-like body lines, a CR).
cat > "$TMP/matrix.py" <<'PYEOF'
import atexit, importlib.util, os, re, shutil, subprocess, sys, tempfile

impl = sys.argv[1]
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(impl)), "lib"))
spec = importlib.util.spec_from_file_location("cs_under_test", impl)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

ENV = dict(os.environ, GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL="/dev/null",
           GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@example.invalid",
           GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@example.invalid")
CANON = ["--binary", "--no-color", "--no-ext-diff", "--no-textconv", "--no-relative",
         "--src-prefix=a/", "--dst-prefix=b/", "--ignore-submodules=none"]
base = tempfile.mkdtemp(prefix="matrix.")
# CON-146 round 5 (review round 4, F2): the fixture repositories are removed on
# every exit path the interpreter controls (normal end, sys.exit, an exception).
atexit.register(shutil.rmtree, base, True)


def git(repo, *a, raw=False):
    r = subprocess.run(["git", "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null",
                        "-C", repo] + list(a), env=ENV, capture_output=True)
    if r.returncode != 0:
        raise SystemExit("FIXTURE-BAD git %s: %s" % (a, r.stderr[:200]))
    return r.stdout


def w(repo, name, data):
    path = os.path.join(repo, name.decode("utf-8", "surrogateescape") if isinstance(name, bytes) else name)
    os.makedirs(os.path.dirname(path) or repo, exist_ok=True)
    open(path, "wb").write(data)


TEN = b"".join(b"l%d\n" % i for i in range(10))
TEN2 = TEN.replace(b"l3\n", b"l3 changed\n")
# section builders: (setup-in-base-commit, change-in-stash)
def sec_T(r, phase):
    if phase == 0: w(r, "tf sp.txt", b"keep\n-- a/zz.txt\nend\n")
    else: w(r, "tf sp.txt", b"keep\ndiff --git f xf\ny\rdiff --git \"f\" \"xf\"\n diff --git a/q xq\nend\n")
def sec_B(r, phase):
    w(r, "bf.bin", b"\000\001" if phase == 0 else b"\000\002")
def sec_N(r, phase):
    if phase == 1:
        w(r, "nf.txt", b"new\n++ b/zz.txt\n"); w(r, "ne.txt", b""); git(r, "add", "nf.txt", "ne.txt")
def sec_D(r, phase):
    if phase == 0: w(r, "df.txt", b"d\n-- a/zz.txt\n")
    else: git(r, "rm", "--quiet", "df.txt")
def sec_M(r, phase):
    if phase == 0: w(r, "mf.sh", b"m\n")
    else: os.chmod(os.path.join(r, "mf.sh"), 0o755)
def sec_R(r, phase):
    if phase == 0: w(r, "ro.txt", TEN)
    else:
        git(r, "mv", "ro.txt", "r n sp\ttab.txt"); w(r, "r n sp\ttab.txt", TEN2)
def sec_C(r, phase):
    if phase == 0: w(r, "cs.txt", TEN)
    else: w(r, "cc.txt", TEN); w(r, "cs.txt", TEN2); git(r, "add", "cc.txt")
def sec_Q(r, phase):
    w(r, b"caf\xe9.txt", b"a\n" if phase == 0 else b"a2\n")
    w(r, "ünï.txt", b"b\n" if phase == 0 else b"b2\n")
SEC = {"T": sec_T, "B": sec_B, "N": sec_N, "D": sec_D, "M": sec_M, "R": sec_R, "C": sec_C, "Q": sec_Q}
ORDER = "TBNDMRC"

def build(tag, sections, cfg):
    r = os.path.join(base, tag)
    os.makedirs(r)
    git(r, "init", "--quiet", "-b", "main")
    for k, v in cfg.items(): git(r, "config", k, v)
    for s in sections: SEC[s](r, 0)
    git(r, "add", "-A"); git(r, "commit", "--quiet", "-m", "i")
    for s in sections: SEC[s](r, 1)
    git(r, "stash", "--quiet")
    return r

def oracle(r):
    """git's own account of the stash: list of (status, [paths]) in patch order."""
    t = git(r, "diff", "-z", "--name-status", "--no-color", "stash@{0}^1", "stash@{0}").split(b"\0")
    out, i = [], 0
    while i < len(t) and t[i]:
        st = t[i].decode()
        if st[0] in "RC": out.append((st, [t[i + 1], t[i + 2]])); i += 3
        else: out.append((st, [t[i + 1]])); i += 2
    return out

def want_files(ent):
    out = []
    for st, ps in ent:
        for p in ([ps[0], ps[1]] if st[0] == "R" else [ps[1]] if st[0] == "C" else [ps[0]]):
            d = p.decode("utf-8", "surrogateescape")
            if d not in out: out.append(d)
    return out

def garble(line, bpath, form):
    """line = b'diff --git ...'; bpath = the b-side path from git's name-status."""
    rest = line[len(b"diff --git "):]
    if rest.endswith(b'"'):
        bs = rest.rfind(b' "b/') + 1
    else:
        bs = len(rest) - len(b"b/" + bpath)
    ah, bh = rest[:bs - 1], rest[bs:]
    if form == "a": ah = ah.replace(b"a/", b"xa/", 1)
    elif form == "b": bh = bh.replace(b"b/", b"xb/", 1)
    elif form == "ab": ah = ah.replace(b"a/", b"xa/", 1); bh = bh.replace(b"b/", b"xb/", 1)
    elif form == "bare": return b"diff --git f xf"
    elif form == "quoted": return b'diff --git "f" "xf"'
    return b"diff --git " + ah + b" " + bh

FORMS = ["a", "b", "ab", "bare", "quoted"]
cells = green = bad = 0
badlines = []
def report(msg):
    global bad
    bad += 1
    if len(badlines) < 12: badlines.append(msg)

def run_tool(patch):
    mod._run_bytes = lambda *a, **k: (0, patch, "")
    return mod.stash_patch_bytes_why("/x", "stash@{0}")

fixtures = []
for n in range(1, 8):
    fixtures.append(("n%d_fwd" % n, list(ORDER[:n]), {"diff.renames": "copies"}))
    fixtures.append(("n%d_rev" % n, list(reversed(ORDER[:n])), {"diff.renames": "copies"}))
fixtures.append(("full_q_nopath", list(ORDER) + ["Q"], {"diff.renames": "copies", "core.quotePath": "false"}))
fixtures.append(("full_norenames", list(ORDER) + ["Q"], {"diff.renames": "false"}))
fixtures.append(("full_default", list(ORDER) + ["Q"], {}))
seen_types = set()
for tag, secs, cfg in fixtures:
    r = build(tag, secs, cfg)
    patch = git(r, "diff", *CANON, "stash@{0}^1", "stash@{0}")
    ent = oracle(r)
    hdrs = [l for l in patch.split(b"\n") if l.startswith(b"diff --git ")]
    if len(hdrs) != len(ent):
        raise SystemExit("FIXTURE-BAD %s: %d headers in the patch, %d in git's name-status" % (tag, len(hdrs), len(ent)))
    for st, ps in ent: seen_types.add(st[0])
    if b"GIT binary patch" in patch: seen_types.add("bin")
    if b"\nnew file mode" in patch: seen_types.add("newmode")
    if b"\ndeleted file mode" in patch: seen_types.add("delmode")
    if b"\nold mode" in patch: seen_types.add("modeonly")
    if b"\n--- a/zz.txt\n" in patch: seen_types.add("dashdash")
    if b"\n+++ b/zz.txt\n" in patch: seen_types.add("plusplus")
    if b"\r" in patch: seen_types.add("cr")
    if b"\xe9" in patch: seen_types.add("latin1")
    # GREEN: the faithful patch is trusted, byte for byte, and the file list is git's
    cells += 1
    got, why = run_tool(patch)
    if got != patch or why is not None:
        report("GREEN %s: faithful patch not trusted (%r)" % (tag, (why or "")[:100]))
    else:
        green += 1
    files = mod._patch_file_paths(patch)
    if files != want_files(ent):
        report("FILES %s: %r != oracle %r" % (tag, files, want_files(ent)))
    for k, line in enumerate(hdrs):
        bpath = ent[k][1][-1]
        for form in FORMS:
            g = garble(line, bpath, form)
            if g == line:
                raise SystemExit("FIXTURE-BAD %s header %d form %s: garble changed nothing" % (tag, k + 1, form))
            bad_patch = patch.replace(line, g, 1) if hdrs.count(line) == 1 else None
            if bad_patch is None:   # two identical header lines (cannot happen: paths differ)
                raise SystemExit("FIXTURE-BAD %s: duplicate header" % tag)
            cells += 1
            got, why = run_tool(bad_patch)
            if got is not None:
                report("GARBLE %s header %d/%d form %s: tripwire silent" % (tag, k + 1, len(hdrs), form))
need = {"M", "A", "D", "R", "C", "bin", "newmode", "delmode", "modeonly", "dashdash", "plusplus", "cr", "latin1"}
if need - seen_types:
    raise SystemExit("FIXTURE-BAD: section types never produced: %s" % sorted(need - seen_types))
for b in badlines: print("BAD " + b)
print("MATRIX cells=%d green=%d bad=%d" % (cells, green, bad))
sys.exit(1 if bad else 0)
PYEOF

run_vp() {  # IMPL REPO PATCH [ENV...] -> "VERDICT<TAB>DETAIL"
  local impl="$1" repo="$2" patch="$3" pj="$TMP/prop.$RANDOM$RANDOM.json" oj="$TMP/out.$RANDOM$RANDOM.json"
  shift 3
  python3 - "$pj" "$(sha "$patch")" "$patch" <<'PYEOF'
import json, sys
p, h, path = sys.argv[1:]
json.dump({"entry_kind": "stash", "entry_id": "stash@{0}", "action": "land",
           "backup_hash": h, "backup_artifact_path": path}, open(p, "w"))
PYEOF
  env "$@" python3 "$impl" verify-proposal --proposal "$pj" --repo-root "$repo" --out "$oj" >/dev/null 2>&1
  python3 - "$oj" <<'PYEOF'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    print("%s\t%s" % (d.get("verdict"), d.get("verdict_detail")))
except Exception as e:
    print("NO_DOC\t%s" % e)
PYEOF
}
run_inv() {  # IMPL REPO [ENV...] -> "STATUS<TAB>SHA256<TAB>FILES"
  local impl="$1" repo="$2" oj="$TMP/inv.$RANDOM$RANDOM.json"
  shift 2
  env "$@" python3 "$impl" inventory --repo-root "$repo" --backup-root "$TMP/nobackups" --out "$oj" >/dev/null 2>&1
  python3 - "$oj" <<'PYEOF'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    e = [x for x in d.get("entries", []) if x.get("entry_id") == "stash@{0}"][0]
    h = e["dirty_file_hash"]
    print("%s\t%s\t%s" % (h.get("status"), h.get("sha256"), ",".join(e.get("files_touched") or [])))
except Exception as ex:
    print("NO_DOC\t%s\t" % ex)
PYEOF
}
verdict() { printf '%s' "${1%%$'\t'*}"; }
detail() { printf '%s' "${1#*$'\t'}"; }
status() { printf '%s' "${1%%$'\t'*}"; }

SS="PATH=$TMP/shim_stashshow:$PATH"
DP="PATH=$TMP/shim_diffpos:$PATH"
QG='diff --git "f" "xf"'

# battery IMPL MODE: every functional check. MODE=report prints ok/NOT ok per
# check; MODE=collect prints only the ids of the checks that FAILED.
battery() {
  local impl=$1 mode=$2 V I k id
  BF=""
  chk() {  # ID RESULT(0=pass) MESSAGE
    if [ "$2" = 0 ]; then [ "$mode" = report ] && ok "$1 $3"
    else BF="$BF $1"; [ "$mode" = report ] && notok "$1 $3"; fi
  }
  V=$(run_vp "$impl" "$R" "$TMP/st.patch" "PATH=$PATH")
  [ "$(verdict "$V")" = ALLOWED ]; chk G1 $? "plain stash, faithful backup, host git -> ALLOWED (got $(verdict "$V"))"
  I=$(run_inv "$impl" "$R" "PATH=$PATH")
  [ "$I" = "dirty${TAB}$WANT_SHA${TAB}f" ]; chk G2 $? "inventory: dirty, sha256 = sha256 of 'git diff CANON ref^1 ref', files=f (got '$I')"
  V=$(run_vp "$impl" "$R" "$TMP/st.patch" "$SS")
  [ "$(verdict "$V")" = ALLOWED ]; chk G3 $? "a git whose 'stash show -p' ignores the prefixes -> still ALLOWED (got $(verdict "$V"))"
  V=$(run_vp "$impl" "$R" "$TMP/st.patch" "$DP" SHIM_POS=all)
  [ "$(verdict "$V")" = REFUSED ] && [[ "$(detail "$V")" == *"could not be read"* ]] \
    && [[ "$(detail "$V")" == *"diff --git header"* ]] && [[ "$(detail "$V")" != *"git status/diff failed"* ]]
  chk B1 $? "every header non-canonical -> REFUSED as unmeasured, naming the bad diff --git header (got $(verdict "$V"): $(detail "$V" | cut -c1-160))"
  I=$(run_inv "$impl" "$R" "$DP" SHIM_POS=all)
  [ "$(status "$I")" = UNMEASURED ]; chk B2 $? "inventory with non-canonical headers -> UNMEASURED, never hashed (got '$I')"
  I=$(run_inv "$impl" "$R3" "PATH=$PATH")
  [ "$I" = "dirty${TAB}$WANT_SHA3${TAB}$WANT_FILES3" ]
  chk G4 $? "three-header stash with a mixed-quoting middle header -> dirty, sha256 = backup, files = both rename paths (got '$I')"
  V=$(run_vp "$impl" "$R3" "$TMP/st3.patch" "PATH=$PATH")
  [ "$(verdict "$V")" = ALLOWED ]; chk G5 $? "three-header mixed-quoting stash, faithful backup -> ALLOWED (got $(verdict "$V"))"
  for k in 1 2 3; do
    I=$(run_inv "$impl" "$R3" "$DP" SHIM_POS=$k)
    [ "$(status "$I")" = UNMEASURED ]; chk "P$k" $? "only header $k of 3 garbled bare ('diff --git f xf') -> UNMEASURED (got '$(status "$I")')"
    I=$(run_inv "$impl" "$R3" "$DP" SHIM_POS=$k "SHIM_TEXT=$QG")
    [ "$(status "$I")" = UNMEASURED ]; chk "Q$k" $? "only header $k of 3 quoted with no prefixes ('$QG') -> UNMEASURED (got '$(status "$I")')"
  done
  V=$(run_vp "$impl" "$R3" "$TMP/st3.patch" "$DP" SHIM_POS=2)
  [ "$(verdict "$V")" = REFUSED ] && [[ "$(detail "$V")" == *"diff --git header"* ]] && [[ "$(detail "$V")" == *"diff --git f xf"* ]]
  chk V2 $? "verify-proposal, middle header garbled -> REFUSED naming that header (got $(verdict "$V"): $(detail "$V" | cut -c1-160))"
  V=$(run_vp "$impl" "$R3" "$TMP/st3.patch" "$DP" SHIM_POS=3 "SHIM_TEXT=$QG")
  [ "$(verdict "$V")" = REFUSED ] && [[ "$(detail "$V")" == *'"f" "xf"'* ]]
  chk V3 $? "verify-proposal, last header quoted without prefixes -> REFUSED naming that header (got $(verdict "$V"): $(detail "$V" | cut -c1-160))"
  V=$(run_vp "$impl" "$R3" "$TMP/st3.patch" "$DP" SHIM_FAIL=1)
  [ "$(verdict "$V")" = REFUSED ] && [[ "$(detail "$V")" == *'git diff stash@{0}^1 stash@{0} failed (rc=3)'* ]]
  chk F1 $? "git diff of the stash fails (rc 3) -> REFUSED naming 'git diff ... failed (rc=3)' (got $(verdict "$V"): $(detail "$V" | cut -c1-160))"
  I=$(run_inv "$impl" "$R3" "$DP" SHIM_FAIL=1)
  [ "$(status "$I")" = UNMEASURED ]; chk F2 $? "git diff of the stash fails -> inventory UNMEASURED (got '$(status "$I")')"
  I=$(run_inv "$impl" "$R4" "PATH=$PATH")
  [ "$(status "$I")" = dirty ] && [ "${I##*$'\t'}" = "$WANT_FILES4" ]
  chk L1 $? "CON-157 file list: rename both paths, spaces, 'x b/y.txt', quotes, non-ASCII, binary, mode, delete, add (got '${I##*$'\t'}')"
  # --- round-4 axes (review round 3: mutants NM1..NM13 survived) ---
  local spec t
  k=0
  for spec in "1|diff --git xa/a1.txt b/a1.txt" "2|diff --git a/b2.txt xb/b2.txt" "3|diff --git a/c3.txt \"xb/c3.txt\"" "2|diff --git \"xa/b2.txt\" \"b/b2.txt\""; do
    k=$((k + 1)); t=${spec#*|}
    I=$(run_inv "$impl" "$R3" "$DP" "SHIM_POS=${spec%%|*}" "SHIM_TEXT=$t")
    [ "$(status "$I")" = UNMEASURED ]; chk "XS$k" $? "one half of one header garbled ('$t') -> UNMEASURED (got '$(status "$I")')"
  done
  for k in 1 2 3 4 5; do
    I=$(run_inv "$impl" "$R5" "$DP" SHIM_POS=$k)
    [ "$(status "$I")" = UNMEASURED ]; chk "XC$k" $? "header $k of 5 garbled -> UNMEASURED (got '$(status "$I")')"
  done
  I=$(run_inv "$impl" "$RB" "$DP" SHIM_POS=2); [ "$(status "$I")" = UNMEASURED ]
  chk XB $? "a header after a binary section garbled -> UNMEASURED (got '$(status "$I")')"
  I=$(run_inv "$impl" "$RB" "$DP" SHIM_POS=1); [ "$(status "$I")" = UNMEASURED ]
  chk XB1 $? "the binary section's own header garbled -> UNMEASURED (got '$(status "$I")')"
  for k in 1 2 3; do
    I=$(run_inv "$impl" "$RM" "$DP" SHIM_POS=$k); [ "$(status "$I")" = UNMEASURED ]
    chk "XM$k" $? "deleted/new/mode-only section: header $k garbled -> UNMEASURED (got '$(status "$I")')"
  done
  I=$(run_inv "$impl" "$RM" "PATH=$PATH"); [ "${I##*$'\t'}" = "d.txt,e.txt,m.sh,n.txt" ] && [ "$(status "$I")" = dirty ]
  chk XMG $? "deleted/new/mode-only stash -> dirty, files d,e,m,n (got '$I')"
  I=$(run_inv "$impl" "$RG" "PATH=$PATH"); [ "$I" = "dirty${TAB}$WANT_SHAG${TAB}p.txt" ]
  chk XG $? "body lines that look like headers (mid-line, after a CR, at column 2) -> dirty, sha = backup (got '$I')"
  V=$(run_vp "$impl" "$RG" "$TMP/stg.patch" "PATH=$PATH"); [ "$(verdict "$V")" = ALLOWED ]
  chk XGV $? "the same stash, faithful backup -> ALLOWED (got $(verdict "$V"): $(detail "$V" | cut -c1-120))"
  I=$(run_inv "$impl" "$RQ" "PATH=$PATH"); [ "$(status "$I")" = dirty ] && [ "$(printf '%s' "$I" | cut -f2)" = "$WANT_SHAQ" ]
  chk XQ $? "core.quotePath=false with a Latin-1 and a UTF-8 name -> dirty, sha = backup (got '$I')"
  local mxd="$TMP/mxtmp.$RANDOM$RANDOM"; mkdir -p "$mxd"
  V=$(TMPDIR="$mxd" python3 "$TMP/matrix.py" "$impl" 2>&1); k=$?
  [ -z "$(ls -A "$mxd")" ] || V="LEFT UNDER TMPDIR: $(ls -A "$mxd" | head -3 | tr '\n' ' ') $V"
  [ "$k" = 0 ] && [[ "$V" == *"MATRIX cells="* ]] && [[ "$V" != *"cells=0 "* ]] && [[ "$V" != "LEFT UNDER TMPDIR"* ]]
  chk MX $? "matrix over header count x position x side x section type x git config, oracle = git name-status; nothing left under its TMPDIR (got: $(printf '%s' "$V" | head -3 | tr '\n' ' ' | cut -c1-200))"
  rm -rf "${mxd:?}"
  # --- round-5 axis (review round 4, F3: no check pinned empty_patch vs
  # UNMEASURED). An untracked-only stash and an index-only stash whose worktree
  # equals HEAD both have an EMPTY tracked patch: a measured empty patch, never
  # UNMEASURED; the untracked one is refused for its untracked content, not as
  # unreadable.
  I=$(run_inv "$impl" "$REU" "PATH=$PATH"); [ "$I" = "empty_patch${TAB}None${TAB}" ]
  chk EP1 $? "untracked-only stash (git stash -u) -> empty_patch, no sha256, no files (got '$I')"
  I=$(run_inv "$impl" "$REP" "PATH=$PATH"); [ "$I" = "empty_patch${TAB}None${TAB}" ]
  chk EP2 $? "index-only stash, worktree = HEAD -> empty_patch, no sha256, no files (got '$I')"
  V=$(run_vp "$impl" "$REU" "$TMP/empty.patch" "PATH=$PATH")
  [ "$(verdict "$V")" = REFUSED ] && [[ "$(detail "$V")" == *"has untracked content"* ]] && [[ "$(detail "$V")" != *"could not be read"* ]]
  chk EP1V $? "untracked-only stash, land -> REFUSED for its untracked content, not as unreadable (got $(verdict "$V"): $(detail "$V" | cut -c1-120))"
  # round-6 axis (review fsfix5 M1): the index-only stash is refused BECAUSE of
  # its index content, never as a stale backup (the faithful empty backup is not stale).
  V=$(run_vp "$impl" "$REP" "$TMP/empty.patch" "PATH=$PATH")
  [ "$(verdict "$V")" = REFUSED ] && [[ "$(detail "$V")" == *"index (staged) content"* ]] && [[ "$(detail "$V")" != *"the backup is stale"* ]]
  chk EP2V $? "index-only stash, faithful empty backup, land -> REFUSED for its index content, not as stale (got $(verdict "$V"): $(detail "$V" | cut -c1-140))"
  [ "$mode" = collect ] && printf '%s' "$BF"
  return 0
}

battery "$IMPL" report

# --- paired mutations: each a copy of the tool; each must fail its named check ---
mk_mutant() {  # NAME OLD NEW -> prints the mutant path, or "" when the anchor is not unique
  local d="$TMP/mut_$1"
  mkdir -p "$d/orchestration" "$d/lib"
  cp "$IMPL" "$d/orchestration/custody_sweep.py"; cp "$LIB" "$d/lib/fc_common.py"; cp "$EXLIB" "$d/lib/fc_entry.py"
  if python3 - "$d/orchestration/custody_sweep.py" "$2" "$3" <<'PYEOF'
import sys
p, old, new = sys.argv[1:]
c = open(p, encoding="utf-8").read()
if c.count(old) != 1:
    sys.exit(1)
open(p, "w", encoding="utf-8").write(c.replace(old, new))
PYEOF
  then echo "$d/orchestration/custody_sweep.py"; fi
}
mutation() {  # NAME "EXPECTED IDS" OLD NEW
  local m got e miss=""
  m=$(mk_mutant "$1" "$3" "$4")
  if [ -z "$m" ]; then notok "mutation $1: anchor not unique in the tool (not a catch)"; return; fi
  got=$(battery "$m" collect)
  for e in $2; do case " $got " in *" $e "*) ;; *) miss="$miss $e" ;; esac; done
  if [ -z "$got" ]; then notok "mutation $1 SURVIVED every functional check"
  elif [ -n "$miss" ]; then notok "mutation $1: caught by$got but NOT by its named check(s)$miss"
  else ok "mutation $1: caught by$got (named: $2)"; fi
}
HDRS='[l for l in out.split(b"\n") if l.startswith(b"diff --git ")]'
LOOP_A='    for raw_line in '
LOOP_B=':
        if raw_line.startswith(b"diff --git ") and not _CANONICAL_DIFF_HEADER_RE.match(raw_line):'
LOOP="${LOOP_A}"'out.split(b"\n")'"${LOOP_B}"
IFL='        if raw_line.startswith(b"diff --git ") and not _CANONICAL_DIFF_HEADER_RE.match(raw_line):'
PAT="_CANONICAL_DIFF_HEADER_RE = re.compile(rb'^diff --git (?:a/.*|\"a/.*\") (?:b/.*|\"b/.*\")\$')"

# M1: derive the stash patch with `git stash show -p` again (the pre-fix code).
mutation M1_stash_show "G3" \
  '["git", "-C", root, "diff"] + list(CANONICAL_PATCH_OPTS)
                            + ["%s^1" % ref, ref]' \
  '["git", "-C", root, "stash", "show", "-p"] + list(CANONICAL_PATCH_OPTS)
                            + [ref]'
# M2: drop the header self-check.
mutation M2_no_header_check "B2 P1 P2 P3" "$IFL" '        if False:'
# M3: report a failed derivation as measured again.
mutation M3_measured_true "B1" \
  'dirty_submodules=[], has_unmerged=False, measured=patch_bytes is not None)' \
  'dirty_submodules=[], has_unmerged=False, measured=True)'
# M4 (round-1 reviewer R1g): check only the FIRST header.
mutation M4_first_header_only "P2 P3" "$LOOP" "${LOOP_A}${HDRS}[:1]${LOOP_B}"
# M5: the pre-F1-1 header pattern (both paths bare, or both quoted).
mutation M5_no_mixed_quoting "G4 G5" "$PAT" \
  "_CANONICAL_DIFF_HEADER_RE = re.compile(rb'^diff --git (a/.* b/.*|\"a/.*\" \"b/.*\")\$')"
# RV1 (round-2 reviewer): check only the LAST header.
mutation RV1_last_only "P1 P2" "$LOOP" "${LOOP_A}${HDRS}[-1:]${LOOP_B}"
# RV2: check only the first and the last header.
mutation RV2_first_and_last "P2" "$LOOP" "${LOOP_A}(lambda h: h[:1] + h[-1:])(${HDRS})${LOOP_B}"
# RV6: check only the first two headers.
mutation RV6_first_two_only "P3" "$LOOP" "${LOOP_A}${HDRS}[:2]${LOOP_B}"
# RV3: trust any header that holds a quote.
mutation RV3_quoted_trusted "Q1 Q2 Q3" "$IFL" "        if b'\"' in raw_line:
            continue
$IFL"
# RV4: a looser pattern -- any quoted token counts as prefixed.
mutation RV4_loose_regex "Q1 Q2 Q3" "$PAT" \
  "_CANONICAL_DIFF_HEADER_RE = re.compile(rb'^diff --git (?:a/.*|\".*\") (?:b/.*|\".*\")\$')"
# RV5: a failed git diff returns no cause text.
mutation RV5_rc_why_dropped "F1" \
  '        return None, "git diff %s^1 %s failed (rc=%s)" % (ref, ref, rc)' \
  '        return None, None'
# L1 (CON-157): the pre-fix file list (first path of each header, DIFF_FILE_RE).
mutation L1_old_file_list "G4 L1" \
  '    files = _patch_file_paths(out)' \
  '    files = []
    for raw_line in out.split(b"\n"):
        if raw_line.startswith(b"diff --git "):
            m = DIFF_FILE_RE.match(raw_line.decode("utf-8", "surrogateescape"))
            if m:
                files.append(m.group(1))'

# --- round-4 reviewer mutants NM1..NM13 (class: a partial header tripwire) and
# FL1..FL9 (CON-157 file list), adopted verbatim from the round-3 review. Each
# is one exact, unique replacement in a copy of the tool; each must fail the
# functional check(s) named for it. The generator aborts on a non-unique anchor.
cat > "$TMP/genmut.py" <<'PYEOF'
import os, sys

src, outdir, name = sys.argv[1:4]
base = open(src, encoding="utf-8").read()
PAT = "_CANONICAL_DIFF_HEADER_RE = re.compile(rb'^diff --git (?:a/.*|\"a/.*\") (?:b/.*|\"b/.*\")$')"
LOOP = ('    for raw_line in out.split(b"\\n"):\n'
        '        if raw_line.startswith(b"diff --git ") and not _CANONICAL_DIFF_HEADER_RE.match(raw_line):')
HDRS = '[l for l in out.split(b"\\n") if l.startswith(b"diff --git ")]'
LOOP_A = '    for raw_line in '
LOOP_B = (':\n        if raw_line.startswith(b"diff --git ") and not _CANONICAL_DIFF_HEADER_RE.match(raw_line):')
IFL = '        if raw_line.startswith(b"diff --git ") and not _CANONICAL_DIFF_HEADER_RE.match(raw_line):'
M = {}
M["NM1_a_side_only"] = (PAT, "_CANONICAL_DIFF_HEADER_RE = re.compile(rb'^diff --git (?:a/.*|\"a/.*\") .*$')")
M["NM2_b_side_only"] = (PAT, "_CANONICAL_DIFF_HEADER_RE = re.compile(rb'^diff --git .* (?:b/.*|\"b/.*\")$')")
M["NM3_first_three"] = (LOOP, LOOP_A + HDRS + "[:3]" + LOOP_B)
M["NM4_last_three"] = (LOOP, LOOP_A + HDRS + "[-3:]" + LOOP_B)
M["NM5_first1_last2"] = (LOOP, LOOP_A + "(lambda h: h[:1] + h[-2:])(" + HDRS + ")" + LOOP_B)
M["NM6_stop_at_binary"] = (LOOP, '    for raw_line in out.split(b"\\n"):\n'
                           '        if raw_line.startswith(b"GIT binary patch"):\n'
                           '            break\n' + IFL)
M["NM7_splitlines"] = (LOOP, '    for raw_line in out.splitlines():\n' + IFL)
M["NM8_substring_match"] = (LOOP, '    for raw_line in out.split(b"\\n"):\n'
                            '        if b"diff --git " in raw_line and not _CANONICAL_DIFF_HEADER_RE.match(raw_line):')
M["NM9_strict_utf8_decode"] = (LOOP, '    for raw_line in out.split(b"\\n"):\n'
                               '        raw_line.decode("utf-8")\n' + IFL)
M["NM10_skip_single_header"] = (LOOP, LOOP_A + "(lambda h: h if len(h) > 1 else [])(" + HDRS + ")" + LOOP_B)
M["NM11_skip_mode_new_deleted_sections"] = (LOOP,
    '    _ls = out.split(b"\\n")\n'
    '    for _i, raw_line in enumerate(_ls):\n'
    '        if _i + 1 < len(_ls) and _ls[_i + 1].startswith((b"deleted file mode", b"new file mode", b"old mode")):\n'
    '            continue\n' + IFL)
M["NM12_skip_rename_sections"] = (LOOP,
    '    _ls = out.split(b"\\n")\n'
    '    for _i, raw_line in enumerate(_ls):\n'
    '        if _i + 1 < len(_ls) and _ls[_i + 1].startswith(b"similarity index"):\n'
    '            continue\n' + IFL)
M["NM13_skip_binary_sections"] = (LOOP,
    '    _ls = out.split(b"\\n")\n'
    '    _bin = set(i for i, l in enumerate(_ls) if l.startswith(b"GIT binary patch"))\n'
    '    for _i, raw_line in enumerate(_ls):\n'
    '        if any(_i < j <= _i + 4 for j in _bin):\n'
    '            continue\n' + IFL)
M["FL1_rename_new_only"] = ('            paths = [s["rf"], s["rt"]]', '            paths = [s["rt"]]')
M["FL3_no_tab_strip"] = (
    '            cur["minus"] = _strip_prefix(_git_unquote(raw_line[4:].rstrip(b"\\t")), b"a/")',
    '            cur["minus"] = _strip_prefix(_git_unquote(raw_line[4:]), b"a/")')
M["FL4_no_dedupe"] = ('            if p is None or p in seen:', '            if p is None:')
M["FL5_no_header_fallback"] = ('            paths = [_same_path_header(s["hdr"])]', '            paths = [None]')
M["FL6_copy_ignored"] = ('        elif s["ct"] is not None:\n            paths = [s["ct"]]',
                         '        elif False:\n            paths = [s["ct"]]')
M["FL7_minus_overwritten_by_body"] = ('        elif raw_line.startswith(b"--- ") and cur["minus"] is None:',
                                      '        elif raw_line.startswith(b"--- "):')
M["FL10_plus_overwritten_by_body"] = ('        elif raw_line.startswith(b"+++ ") and cur["plus"] is None:',
                                      '        elif raw_line.startswith(b"+++ "):')
M["FL8_octal_ignored"] = ('            if len(octal) == 3 and all(48 <= c <= 55 for c in octal):', '            if False:')
M["FL9_sorted"] = ('    return files\n\n\ndef stash_has_untracked', '    return sorted(files)\n\n\ndef stash_has_untracked')
old, new = M[name]
if base.count(old) != 1:
    sys.exit(1)
open(os.path.join(outdir, "orchestration", "custody_sweep.py"), "w", encoding="utf-8").write(base.replace(old, new))
PYEOF
pymutation() {  # NAME "EXPECTED IDS"
  local d="$TMP/mut_$1" got e miss=""
  mkdir -p "$d/orchestration" "$d/lib"
  cp "$LIB" "$d/lib/fc_common.py"; cp "$EXLIB" "$d/lib/fc_entry.py"
  if ! python3 "$TMP/genmut.py" "$IMPL" "$d" "$1"; then notok "mutation $1: anchor not unique in the tool (not a catch)"; return; fi
  got=$(battery "$d/orchestration/custody_sweep.py" collect)
  for e in $2; do case " $got " in *" $e "*) ;; *) miss="$miss $e" ;; esac; done
  if [ -z "$got" ]; then notok "mutation $1 SURVIVED every functional check"
  elif [ -n "$miss" ]; then notok "mutation $1: caught by$got but NOT by its named check(s)$miss"
  else ok "mutation $1: caught by$got (named: $2)"; fi
}
pymutation NM1_a_side_only "XS2 XS3 MX"
pymutation NM2_b_side_only "XS1 MX"
pymutation NM3_first_three "XC4 XC5 MX"
pymutation NM4_last_three "XC1 XC2 MX"
pymutation NM5_first1_last2 "XC2 XC3 MX"
pymutation NM6_stop_at_binary "XB MX"
pymutation NM7_splitlines "XG MX"
pymutation NM8_substring_match "XG MX"
pymutation NM9_strict_utf8_decode "XQ"
pymutation NM10_skip_single_header "B1 MX"
pymutation NM11_skip_mode_new_deleted_sections "XM1 XM2 XM3 MX"
pymutation NM12_skip_rename_sections "P2 MX"
pymutation NM13_skip_binary_sections "XB1 MX"
pymutation FL1_rename_new_only "G4 L1 MX"
pymutation FL3_no_tab_strip "L1 MX"
pymutation FL4_no_dedupe "G4 L1 MX"
pymutation FL5_no_header_fallback "L1 MX"
pymutation FL6_copy_ignored "MX"
pymutation FL7_minus_overwritten_by_body "MX"
pymutation FL10_plus_overwritten_by_body "MX"
pymutation FL8_octal_ignored "L1 MX"
pymutation FL9_sorted "G4 L1 MX"
# RD (round-4 reviewer, verbatim): an empty patch reported as UNMEASURED.
mutation RD_empty_patch_is_unmeasured "EP1 EP2" '    if patch_bytes is None:
        dirty_status = "UNMEASURED"' '    if not patch_bytes:
        dirty_status = "UNMEASURED"'
# RD2 (round-5 sibling of RD in verify-proposal): an empty live patch read as unmeasured.
mutation RD2_empty_live_patch_unmeasured "EP1V" \
  'dirty_submodules=[], has_unmerged=False, measured=patch_bytes is not None)' \
  'dirty_submodules=[], has_unmerged=False, measured=bool(patch_bytes))'
# EP2M (round 6, review fsfix5 M1): the index-content check removed.
mutation EP2M_index_content_not_checked "EP2V" \
  '    if entry_kind == "stash" and live.get("index_unpatched") is not False:' \
  '    if False:'
# FL2 (reviewer: unquote of the `---`/`+++` lines dropped) is EQUIVALENT: the
# header fallback names the same path, so no input separates it; not adopted.

# TD: nothing this run started is left in its TMPDIR (F2, whole-run check).
[ -z "$(ls -A "$TMPDIR")" ] && ok "TD nothing left under the run's TMPDIR" || notok "TD left under the run's TMPDIR: $(ls -A "$TMPDIR" | head -5 | tr '\n' ' ')"
echo "=== stash patch regression guard (CON-146): pass=$pass fail=$fail ==="
[ "$fail" = 0 ]
