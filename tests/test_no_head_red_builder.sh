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
#      Shapes covered (each is a golden-TRUE fixture): show and cat-file -p|blob,
#      options before the revision (--no-textconv), the @ alias, HEAD~N /
#      HEAD^N / HEAD^{type}, a "$(git rev-parse HEAD)" revision, > >> 1> &>
#      | tee | tar, --output= / -o, git archive HEAD (| tar, > , -o), a two-step
#      capture (v=$(git show HEAD:p) then "$v" written to a file), a variable
#      holding the revision (r=HEAD:p or r=HEAD, then git show "$r"/"${r}:p"),
#      and in Python a plain, f-string or variable revision. NOT covered
#      (honest limit, §11.4.6): a revision built in another file or function
#      argument, eval / sh -c strings, a read whose output reaches a file
#      through a pipe into any tool other than tee/tar, and languages other
#      than shell and Python. The census lists tracked AND untracked,
#      not-ignored files.
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
# Empty since CON-043 landed (its test now pins RED_PIN=ca88eda...).
PENDING=''

# --- the detector -------------------------------------------------------------
# No line of this file may itself look like a builder (the census scans this
# file too): every revision token in the detector and the fixtures is spelled
# through a placeholder that is substituted at run time.
cat > "$S/detect.py" <<'PY'
import os, re, sys
MUT = os.environ.get("REDPIN_DETECTOR_MUTANT", "")
H = "HE" + "AD"
# The revision core: HEAD (never ORIG_HEAD / FETCH_HEAD), or the alias @ (never @{u}),
# each with optional ~N / ^N / ^{type} suffixes.
CORE = r"(?:(?<![A-Za-z0-9_])" + H + r"|(?<![A-Za-z0-9_@.%-])@(?!\{))(?:[~^][0-9]*|\^\{[a-z]*\})*"
RVP = r"\$\(\s*git\b[^)]*?\brev-parse\b[^)]*?(?:(?<![A-Za-z0-9_])" + H + r"|(?<![A-Za-z0-9_@.%-])@)(?![A-Za-z0-9_])[^)]*\)"
REV = r"(?:" + CORE + r"|" + RVP + r")[\"']?:"
OPTS = r"(?:\s+--?[A-Za-z][\w-]*(?:=\S*)?)*"
VERB = r"(?:show|cat-file" + OPTS + r"\s+(?:-p|blob))" + OPTS
SH_READ = re.compile(r"\bgit\b[^#\n]*?\b" + VERB + r"\s+[\"']?" + REV)
ARCHIVE = re.compile(r"\bgit\b[^#\n]*?\barchive\b[^#\n|;]*?(?:(?<![A-Za-z0-9_/.:-])" + H + r"|(?<![A-Za-z0-9_/.:@-])@)(?:[~^][0-9]*)*(?=[\"']?(?:\s|$|;|\|))")
PY_READ = re.compile(r"[\"'](?:show|-p|blob)[\"']\s*,\s*[fFrRbBuU]{0,2}[\"']" + REV)
# Written to a file: > or >> (not 2>, not >&N, not /dev/null), 1> and &> included, | tee, | tar.
WRITE = re.compile(r"(?<![02-9<])>>?\s*(?!&|\s*/dev/null)[^\s)]|\|\s*(?:tee|tar)\b")
OUTOPT = re.compile(r"(?:^|\s)(?:-o\s*[^\s-]|--output[= ]\S)")
MARK = re.compile(r"#\s*redpin:\s*not-a-red-builder\s+\S")
# two-step shapes: a variable that captures a HEAD read, or holds a HEAD revision
SH_CAPTURE = re.compile(r"(?:^|[\s;(])(?:local\s+|export\s+|readonly\s+)?([A-Za-z_]\w*)=[\"']?\$\(\s*git\b[^#\n]*?\b" + VERB + r"\s+[\"']?" + REV)
SH_REVVAR = re.compile(r"(?:^|[\s;(])(?:local\s+|export\s+|readonly\s+)?([A-Za-z_]\w*)=[\"']?(?:" + CORE + r"|" + RVP + r")(?=([\"']?:)|[\"'\s;]|$)")
PY_REVVAR = re.compile(r"^\s*([A-Za-z_]\w*)\s*=\s*[fFrRbBuU]{0,2}[\"'](?:" + CORE + r")(:[^\"']*)?[\"']")
if MUT == "never-match":
    SH_READ = re.compile(r"(?!x)x"); PY_READ = SH_READ; ARCHIVE = SH_READ
    SH_CAPTURE = SH_READ; SH_REVVAR = SH_READ; PY_REVVAR = SH_READ
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

def own_cmd(line, m):
    # the git command itself: from the match start up to the first | ; && ||
    return re.split(r"\||;|&&", line[m.start():], maxsplit=1)[0]

def sh_hits(line, captured, revvars):
    m = SH_READ.search(line)
    if m and (WRITE.search(line[m.end():]) or OUTOPT.search(own_cmd(line, m))):
        return True
    m = ARCHIVE.search(line)
    if m and (WRITE.search(line[m.end():]) or OUTOPT.search(own_cmd(line, m))):
        return True
    for v in captured:
        m = re.search(r"\$\{?" + re.escape(v) + r"\b\}?", line)
        if m and WRITE.search(line[m.end():]):
            return True
    for v, colon in revvars.items():
        m = re.search(r"\bgit\b[^#\n]*?\b" + VERB + r"\s+[\"']?\$\{?" + re.escape(v) + r"\b\}?([\"']?:)?", line)
        if m and (colon or m.group(1)) and WRITE.search(line[m.end():]):
            return True
    return False

def hits(path, text):
    py = path.endswith(".py")
    captured, revvars = set(), {}
    for n, line in logical_lines(text):
        if line.lstrip().startswith("#") or MARK.search(line):
            continue
        if py:
            m = PY_REVVAR.search(line)
            if m:
                revvars[m.group(1)] = bool(m.group(2))
            if PY_READ.search(line):
                yield n, line.strip(); continue
            for v in revvars:
                if re.search(r"[\"'](?:show|-p|blob)[\"']\s*,\s*(?:[fF][\"']\{" + re.escape(v) + r"\}|" + re.escape(v) + r"\b)", line):
                    yield n, line.strip(); break
            continue
        if sh_hits(line, captured, revvars):
            yield n, line.strip()
        for m in SH_CAPTURE.finditer(line):
            captured.add(m.group(1))
        for m in SH_REVVAR.finditer(line):
            revvars[m.group(1)] = bool(m.group(2))

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
# Fixture text uses __H__ for the revision word and __AT__ for its alias; the
# real tokens are substituted below, so this file never carries a builder line.
# A golden-TRUE line that must be flagged ends in "#T"; an untagged line in the
# TRUE file is a setup line (the first half of a two-step shape).
H=$(printf 'HE%s' AD)
mkdir -p "$S/fx"
cat > "$S/fx/true.tmpl" <<'EOF'
git -C "$CONST_ROOT" show __H__:scripts/x.sh > "$PREFIX_COPY" 2>/dev/null #T
git show "__H__:$p" > "$o" #T
git cat-file -p __H__:a/b >"$W/b" #T
git cat-file blob __H__:a/b >> out.txt #T
git show __H__~1:x > f #T
git show __H__^{commit}:x > f #T
git -C "$R" show __H__:x.sh \
    > "$W/x.sh" #T
git show __H__:x | tee "$W/x" #T
git show --no-textconv __H__:x > f #T
git show __AT__:x > f #T
git show __H__:x 1> "$W/x" #T
git show __H__:x &> "$W/x" #T
_c=$(git -C "$R" show __H__:x)
printf '%s\n' "$_c" > "$W/x" #T
rev=__H__:x
git show "$rev" > "$W/x" #T
base=__H__
git show "${base}:x" > "$W/x" #T
git -C "$R" show "$(git -C "$R" rev-parse __H__)":x > f #T
git -C "$R" archive __H__ x | tar -x -C "$W" #T
git archive -o "$W/a.tar" __H__ x #T
git show __H__:x --output="$W/x" #T
EOF
cat > "$S/fx/false.tmpl" <<'EOF'
eq "same" "$(git -C "$P" show __H__:CLAUDE.md | sha256sum)" "$(sha256sum <"$P/CLAUDE.md")"
cmp -s "$bk" <(git -C "$P6" show __H__:CLAUDE.md)
[ "$(git -C "$G" show __H__:docs/latest.md)" = "$(cat "$GD/x.md")" ]
git show __H__:x >/dev/null 2>&1
git show __H__:x 2>/dev/null | grep -q needle
git show __H__:x 2> "$W/err.log"
git -C "$CONST_ROOT" show "$RED_PIN:scripts/x.sh" > "$PREFIX_COPY"
git show e60cbde2e33e7d0542a937331763f6be7e739c9a:x > f
git show ORIG___H__:x > f
git show __AT__{u}:x > f
git checkout __H__ -- scripts/x.sh
git rev-parse __H__:constitution > f
git log -1 --format=%H __H__ > f
git archive "$RED_PIN" x | tar -x -C "$W"
pin=$RED_PIN
git show "$pin:x" > f
_k=$(git show __H__:x)
[ "$_k" = "$(cat f)" ] && echo same
# git show __H__:x > f   (a comment)
git show __H__:x > "$W/x"   # redpin: not-a-red-builder restores the file for a byte compare
git push -q origin __H__:refs/heads/main > log
EOF
cat > "$S/fx/true_test.tmpl" <<'EOF'
out = subprocess.run(["git", "show", "__H__:scripts/x.sh"], capture_output=True).stdout #T
out = subprocess.run(["git", "show", f"__H__:{p}"], capture_output=True).stdout #T
rev = "__H__"
out = subprocess.run(["git", "show", f"{rev}:{p}"], capture_output=True).stdout #T
EOF
cat > "$S/fx/false_test.tmpl" <<'EOF'
out = subprocess.run(["git", "show", RED_PIN + ":scripts/x.sh"], capture_output=True).stdout
rev = RED_PIN
out = subprocess.run(["git", "show", f"{rev}:{p}"], capture_output=True).stdout
EOF
for t in true false true_test false_test; do
    sed -e "s/__H__/$H/g" -e 's/__AT__/@/g' "$S/fx/$t.tmpl" > "$S/fx/$t.src"
done
# compare the flagged line numbers with the #T-tagged line numbers
check_true() {   # $1 = label for the detector (decides sh vs py), $2 = fixture
    # a #T on a continuation line belongs to the logical line that starts above it
    want=$(awk '{ if (!cont) start=NR; cont=/\\$/ } /#T$/ { printf "%d ", start }' "$2")
    got=$(detect "$1=$2" | grep '^HIT' | cut -f2 | cut -d: -f2 | tr '\n' ' ')
    [ -n "$want" ] && [ "$got" = "$want" ]
}
if check_true t.sh "$S/fx/true.src"; then pass "detector golden-TRUE: all $(grep -c '#T$' "$S/fx/true.src") builder lines flagged, setup lines not"
else fail "detector golden-TRUE: flagged lines differ from the #T lines"; detect "t.sh=$S/fx/true.src"; fi
got_false=$(detect "f.sh=$S/fx/false.src" | grep -c '^HIT')
if [ "$got_false" = "0" ]; then pass "detector golden-FALSE: none of $(wc -l < "$S/fx/false.src") compare/restore/pinned/stderr/marked lines flagged"
else fail "detector golden-FALSE: $got_false non-builder line(s) flagged"; detect "f.sh=$S/fx/false.src"; fi
if check_true t_test.py "$S/fx/true_test.src" \
   && [ "$(detect "f_test.py=$S/fx/false_test.src" | grep -c '^HIT')" = "0" ]; then
    pass "detector python: HEAD blob reads (plain, f-string, via a variable) flagged, pinned reads not flagged"
else fail "detector python: HEAD/pinned discrimination wrong"; detect "t_test.py=$S/fx/true_test.src" "f_test.py=$S/fx/false_test.src"; fi

# --- the census set ------------------------------------------------------------
census() {   # $1 = revision or "WORKTREE"; prints the file list
    # WORKTREE = tracked files plus untracked, not-ignored ones (a new test not yet
    # added is scanned too).
    if [ "$1" = WORKTREE ]; then git -C "$ROOT" ls-files --cached --others --exclude-standard; else git -C "$ROOT" ls-tree -r --name-only "$1"; fi \
    | grep -v -e '^submodules/' -e '/fixtures/' \
    | grep -E '(^|/)tests?/.*\.(sh|bash|py)$|(^|/)test[^/]*\.(sh|bash|py)$|_mutation_test\.sh$'
}

# --- 3. positive and negative controls ------------------------------------------
CTRL_REV=8e496db76bf4b8570b0b14db55fd94468260884b
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
