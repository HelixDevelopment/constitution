#!/usr/bin/env bash
# =============================================================================
# tests/test_no_head_red_builder.sh — census guard for the "redpin" class
#     (§11.4.115 / §11.4.224 / §11.4.292(E)).
# -----------------------------------------------------------------------------
# The class: a test builds its RED artifact at run time from `git show HEAD:`
# (or `git cat-file -p|blob HEAD:`, or HEAD~N / HEAD^N). Once the fix under
# test is committed, HEAD holds the FIXED copy, so such a RED can never go RED
# on a committed tree: the test either fails for the wrong reason or proves
# nothing. The cure is to pin the RED artifact to the pre-fix commit (see
# scripts/multitrack/test_multitrack_orchestrator_reconcile.sh, RED_PIN).
#
# What this guard does:
#   1. Scans every tracked test file (test*.sh/.bash/.py, *_mutation_test.sh,
#      anything under a tests/ directory; never submodules/ or fixtures/) for a
#      HEAD-relative blob read whose output is WRITTEN TO A FILE (`>` to a
#      path other than /dev/null, or `| tee`) -- that is a builder. A HEAD read
#      that is only compared (`| sha256sum`, `$(...)`, `<(...)`) or discarded
#      is not a builder. Python tests: any show/cat-file HEAD blob read.
#      A line may opt out with `# redpin: not-a-red-builder <reason>` (the
#      reason is required).
#   2. Self-validates the detector on built-in fixtures: golden-TRUE lines
#      must be flagged, golden-FALSE lines (compare, restore, discard, pinned
#      rev, ORIG_HEAD, comment, marked line) must not (§11.4.201(1)).
#   3. Positive control: the five multitrack tests at commit 8e496db (before
#      this class was fixed) must be flagged, all five. Negative control: a
#      fabricated revision token is never flagged.
#   4. The current tree must have no builder outside PENDING (instances owned
#      by another open vehicle, each with its reason). A PENDING entry that no
#      longer matches is reported as a NOTE so it can be removed.
#
# Usage: bash tests/test_no_head_red_builder.sh
# Exit: 0 when every check passes; 1 on any FAIL. Summary "PASS=n FAIL=n SKIP=n".
# Inputs: REDPIN_DETECTOR_MUTANT (test-only: name of a detector mutation, used
#   by tests/test_no_head_red_builder_mutations.sh; unset in normal runs).
# Side-effects: one scratch directory (fixtures), removed on exit.
# Dependencies: bash, git, python3.
# =============================================================================
set -u

ROOT=$(cd "$(dirname "$0")/.." && git rev-parse --show-toplevel 2>/dev/null)
[ -n "$ROOT" ] || { echo "FATAL: not inside a git checkout"; exit 90; }
# shellcheck source=../scripts/lib/safe_rm.sh
. "$ROOT/scripts/lib/safe_rm.sh" || { echo "FATAL: cannot source safe_rm.sh"; exit 90; }

PASS=0; FAIL=0; SKIP=0
pass() { PASS=$((PASS+1)); echo "PASS: $*"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL: $*"; }

S=$(mktemp -d "${TMPDIR:-/tmp}/redpin_census.XXXXXX") || { echo "FATAL: mktemp failed"; exit 90; }
cleanup() { [ -n "${S:-}" ] && [ -d "$S" ] && safe_rm_rf "${S:?}"; }
trap cleanup EXIT INT TERM

# Instances owned by another open vehicle: path<TAB>reason. Keep this short;
# each entry is debt with an owner.
PENDING='tests/gates/test_oracle_ratchet_and_consumer_skips.sh	CON-043 round 2 vehicle pins this RED (RED_PIN=ca88eda...), not landed on main yet'

# --- the detector -------------------------------------------------------------
cat > "$S/detect.py" <<'PY'
import os, re, sys
MUT = os.environ.get("REDPIN_DETECTOR_MUTANT", "")
# HEAD, HEAD~N, HEAD^N, HEAD^{...}, never ORIG_HEAD / FETCH_HEAD / a pinned sha.
REV = r"(?<![A-Za-z0-9_])HEAD(?:[~^][0-9]*|\^\{[a-z]*\})*:"
SH_READ = re.compile(r"\bgit\b[^#\n]*?\b(?:show|cat-file\s+(?:-p|blob))\s+[\"']?" + REV)
PY_READ = re.compile(r"[\"'](?:show|-p|blob)[\"']\s*,\s*[\"']" + REV)
WRITE = re.compile(r"(?<![0-9&<])>>?\s*(?!&|\s*/dev/null)[^\s)]|\|\s*tee\b")
MARK = re.compile(r"#\s*redpin:\s*not-a-red-builder\s+\S")
if MUT == "never-match":
    SH_READ = re.compile(r"(?!x)x"); PY_READ = SH_READ
if MUT == "ignore-write":
    WRITE = re.compile(r".")

def logical_lines(text):
    buf, start = "", 0
    for n, line in enumerate(text.splitlines(), 1):
        if not buf:
            start = n
        if line.endswith("\\"):
            buf += line[:-1] + " "
            continue
        yield start, buf + line
        buf = ""
    if buf:
        yield start, buf

def hits(path, text):
    py = path.endswith(".py")
    for n, line in logical_lines(text):
        if line.lstrip().startswith("#") or MARK.search(line):
            continue
        if py:
            if PY_READ.search(line):
                yield n, line.strip()
            continue
        m = SH_READ.search(line)
        if m and WRITE.search(line[m.end():]):
            yield n, line.strip()

for path in sys.argv[1:]:
    label, _, real = path.partition("=")
    real = real or label
    try:
        text = open(real, encoding="utf-8", errors="replace").read()
    except OSError as e:
        print("ERROR\t%s\t%s" % (label, e)); continue
    for n, line in hits(label, text):
        print("HIT\t%s:%d\t%s" % (label, n, line[:160]))
PY
detect() { python3 -I "$S/detect.py" "$@"; }

# --- 2. detector self-validation on fixtures ---------------------------------
mkdir -p "$S/fx"
cat > "$S/fx/true.sh" <<'EOF'
git -C "$CONST_ROOT" show HEAD:scripts/x.sh > "$PREFIX_COPY" 2>/dev/null
git show "HEAD:$p" > "$o"
git cat-file -p HEAD:a/b >"$W/b"
git cat-file blob HEAD:a/b >> out.txt
git show HEAD~1:x > f
git show HEAD^{commit}:x > f
git -C "$R" show HEAD:x.sh \
    > "$W/x.sh"
git show HEAD:x | tee "$W/x"
EOF
cat > "$S/fx/false.sh" <<'EOF'
eq "same" "$(git -C "$P" show HEAD:CLAUDE.md | sha256sum)" "$(sha256sum <"$P/CLAUDE.md")"
cmp -s "$bk" <(git -C "$P6" show HEAD:CLAUDE.md)
[ "$(git -C "$G" show HEAD:docs/latest.md)" = "$(cat "$GD/x.md")" ]
git show HEAD:x >/dev/null 2>&1
git show HEAD:x 2>/dev/null | grep -q needle
git -C "$CONST_ROOT" show "$RED_PIN:scripts/x.sh" > "$PREFIX_COPY"
git show e60cbde2e33e7d0542a937331763f6be7e739c9a:x > f
git show ORIG_HEAD:x > f
git checkout HEAD -- scripts/x.sh
git rev-parse HEAD:constitution > f
# git show HEAD:x > f   (a comment)
git show HEAD:x > "$W/x"   # redpin: not-a-red-builder restores the file for a byte compare
git push -q origin HEAD:refs/heads/main > log
EOF
cat > "$S/fx/true_test.py" <<'EOF'
out = subprocess.run(["git", "show", "HEAD:scripts/x.sh"], capture_output=True).stdout
EOF
cat > "$S/fx/false_test.py" <<'EOF'
out = subprocess.run(["git", "show", RED_PIN + ":scripts/x.sh"], capture_output=True).stdout
EOF
want_true=$(grep -vc '^    ' "$S/fx/true.sh")   # continuation line is part of the line above
got_true=$(detect "t.sh=$S/fx/true.sh" | grep -c '^HIT')
if [ "$got_true" = "$want_true" ]; then pass "detector golden-TRUE: all $want_true builder lines flagged"
else fail "detector golden-TRUE: flagged $got_true of $want_true builder lines"; detect "t.sh=$S/fx/true.sh"; fi
got_false=$(detect "f.sh=$S/fx/false.sh" | grep -c '^HIT')
if [ "$got_false" = "0" ]; then pass "detector golden-FALSE: none of $(wc -l < "$S/fx/false.sh") compare/restore/pinned/marked lines flagged"
else fail "detector golden-FALSE: $got_false non-builder line(s) flagged"; detect "f.sh=$S/fx/false.sh"; fi
if [ "$(detect "t_test.py=$S/fx/true_test.py" | grep -c '^HIT')" = "1" ] \
   && [ "$(detect "f_test.py=$S/fx/false_test.py" | grep -c '^HIT')" = "0" ]; then
    pass "detector python: HEAD blob read flagged, pinned read not flagged"
else fail "detector python: HEAD/pinned discrimination wrong"; fi

# --- the census set ------------------------------------------------------------
census() {   # $1 = revision or "WORKTREE"; prints the file list
    if [ "$1" = WORKTREE ]; then git -C "$ROOT" ls-files; else git -C "$ROOT" ls-tree -r --name-only "$1"; fi \
    | grep -v -e '^submodules/' -e '/fixtures/' \
    | grep -E '(^|/)tests?/.*\.(sh|bash|py)$|(^|/)test[^/]*\.(sh|bash|py)$|_mutation_test\.sh$'
}

# --- 3. positive and negative controls ------------------------------------------
CTRL_REV=8e496db
if git -C "$ROOT" cat-file -e "$CTRL_REV^{commit}" 2>/dev/null; then
    args=()
    for t in orchestrator_reconcile orchestrator_reconcile_rc sessions_argparse sessions_pid_status supervisor_wiring; do
        f=scripts/multitrack/test_multitrack_$t.sh
        git -C "$ROOT" show "$CTRL_REV:$f" > "$S/ctrl_$t.sh" || true
        args+=("$f=$S/ctrl_$t.sh")
    done
    n=$(detect "${args[@]}" | grep '^HIT' | cut -f2 | cut -d: -f1 | sort -u | wc -l)
    if [ "$n" = "5" ]; then pass "positive control: all 5 known instances at $CTRL_REV are flagged"
    else fail "positive control: $n of 5 known instances at $CTRL_REV flagged (the instrument is blind)"; fi
else
    fail "positive control: commit $CTRL_REV is not in this clone (shallow?) -- the instrument cannot be proven to see the class"
fi
printf 'git show ZZQX_FABRICATED_REV:x > f\n' > "$S/neg.sh"
if [ "$(detect "n.sh=$S/neg.sh" | grep -c '^HIT')" = "0" ]; then pass "negative control: a fabricated revision token is not flagged"
else fail "negative control: a fabricated revision token was flagged"; fi

# --- 4. the current tree ---------------------------------------------------------
mapfile -t files < <(census WORKTREE)
pargs=()
for f in "${files[@]}"; do [ -f "$ROOT/$f" ] && pargs+=("$f=$ROOT/$f"); done
detect "${pargs[@]}" > "$S/tree.hits"
if grep -q '^ERROR' "$S/tree.hits"; then fail "census: unreadable file(s)"; grep '^ERROR' "$S/tree.hits"; fi
pending_paths=$(printf '%s\n' "$PENDING" | cut -f1)
bad=0
while IFS=$'\t' read -r kind where text; do
    [ "$kind" = HIT ] || continue
    p=${where%%:*}
    if printf '%s\n' "$pending_paths" | grep -qxF "$p"; then continue; fi
    bad=$((bad+1)); echo "  builder: $where  $text"
done < "$S/tree.hits"
if [ "$bad" = "0" ]; then pass "census: ${#pargs[@]} test files scanned, no HEAD-built RED artifact outside PENDING"
else fail "census: $bad HEAD-built RED artifact line(s) -- pin the RED to the pre-fix commit (see scripts/multitrack/test_multitrack_orchestrator_reconcile.sh RED_PIN)"; fi
while IFS=$'\t' read -r p reason; do
    [ -n "$p" ] || continue
    if grep -q "^HIT	$p:" "$S/tree.hits"; then echo "NOTE: pending $p ($reason)"
    else echo "NOTE: pending entry $p no longer matches; remove it from PENDING"; fi
done <<< "$PENDING"

echo ""
echo "PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
[ "$FAIL" -eq 0 ]
