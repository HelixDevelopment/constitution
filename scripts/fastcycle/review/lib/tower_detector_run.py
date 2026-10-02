#!/usr/bin/env python3
"""tower_detector_run.py -- git-history "patch-tower" detector (S11.4.250
heuristic-tower pattern, research-derived shortlist item 4,
docs/research/fast_dev_cycles_acceleration_2026-10/FINDINGS.md S6):
"A git-history tower detector flags any symbol with 3+ branch-adding
commits under one item in a cycle -- mechanically triggers S11.4.250
before the 3rd patch round."

Forensic motivation (this session, SpecKit-004 fastcycle track): three
tracked stories -- T048 (fc_timer golden-output comparison logic), T085
(device-sandbox + evidence-check hardening), T177 (migrate.sh publish
step) -- each accumulated many successive narrow, special-case-adding
patches under one item before an independent reviewer finally diagnosed
an S11.4.250 "heuristic-tower" pattern (many layers compensating for one
unfixed root defect, instead of a genuine architectural fix) and told the
fixer to stop patching and rebuild properly. In every case the diagnosis
came LATE: T048 round 20-21 (after ~8 compensating layers across rounds
8/10/12/14/16/18/19, see commit b348b4056bdc108bfbe9749d5b6f726426aaa963's
own enumeration), T085 round 3-4 (the Round-4 review named the
architectural rewrite), T177 round 19-20 (data-integrity hardening after
many per-round remediation rounds). This tool exists to make that
diagnosis MECHANICAL and EARLY -- flag the symbol the moment a 3rd
compensating branch-adding commit lands under the SAME tracked item,
before review round N+1 has to re-discover it by hand.

NOT A GATE (S11.4.269): this tool's output is an ADVISORY signal only.
It is correctly dispatcher+library split (house pattern: this project's
own gates/io_trace.sh -> gates/lib/io_trace_parse.py,
review/precheck_pack.sh -> review/lib/precheck_pack_run.py), runnable
standalone by a human or an agent before writing a 4th patch to a symbol,
and it is NEVER wired to block any build/review/dispatch seam on its own
judgment -- a mechanical heuristic like this one can be wrong in both
directions (S11.4.201: a false-positive refusal is a FAIL-bluff exactly
as a false-negative pass is a PASS-bluff), so per S11.4.269 it informs,
it never decides. See the companion doc TOWER_DETECTOR.md (S11.4.18) for
the full false-positive/false-negative boundary and the recommended human
response to a flag.

HOW ITEMS ARE GROUPED (S11.4.6, never invented): this repository's real,
observed commit-message convention (verified via `git log --oneline` on
this very history before writing this file, never guessed) is a
Conventional-Commits subject line carrying a SpecKit task id as a literal
token somewhere in the subject -- e.g.
"fix(fastcycle/T085-r5): 4 shared architectural primitives ..." or
"fix(fastcycle/T048): round 11 -- remediate ..." or, in a main-repo
checkout using the S11.4.54 ATM-id convention, "fix(ATM-123): ...". Round
numbers appear EITHER as a `-r<N>` scope suffix OR as free text "round
<N>" -- NOT a fixed position -- so this tool groups commits by a plain
WORD-BOUNDARY TOKEN MATCH of the requested item id anywhere in the
subject line (`\b<item>\b`), which is robust to both observed forms,
rather than parsing the Conventional-Commits scope grammar exactly (a
narrower parser would miss the free-text "round 11" form this repo's own
T048 history actually uses). This is a DOCUMENTED, GREPPABLE,
unit-testable rule, not an invented one -- see test_item_token_regex() in
the paired test suite for the exact pattern proven against real commit
subjects from this repo's own history.

HOW A "BRANCH-ADDING COMMIT" IS DETECTED (real, grep-able, testable --
never vibes): per symbol touched by a commit (see SYMBOL BOUNDARIES
below), this tool parses that commit's own `git show -U0` diff hunks
restricted to the touched file, and classifies the commit as
branch-adding FOR THAT SYMBOL iff BOTH of:

  (1) DIFF SHAPE -- the net count of added-minus-removed lines matching
      BRANCH_TOKEN_RE (a conditional-branch opener: `if`/`elif`/`else
      if`/`case`/`except`/`catch`, the enumerated keyword list this
      tool's own design brief names) in that symbol's hunk(s) is >= 1,
      AND the hunk's total deleted-line count is LESS than
      REFRACTOR_RATIO (default 0.8) times its total added-line count --
      i.e. the hunk is not "roughly equal code removed", which this
      tool's design brief explicitly treats as the refactor/replace shape
      rather than the compensating-patch shape (a hunk that deletes
      almost as much as it adds is characteristic of "remove the old
      special case, add a different one in its place" refactors, not of
      "layer another special case on top of what is already there").

  (2) MESSAGE SHAPE -- the commit's own Conventional-Commits TYPE is NOT
      in REFRACTOR_VERBS = {"refactor", "revert"}, AND the commit's
      description (the text after the first ": ") does not itself START
      with one of the explicit de-weighting verbs {"remove", "replace",
      "delete", "revert", "refactor"} (matching real history in this
      very repo, e.g. "chore(fastcycle/T048-r21): remove obsolete
      member-consistency ... regression suite" -- a commit whose stated
      intent is REMOVAL is excluded from the compensating-patch count
      even when its line-level diff shape would otherwise qualify, since
      S11.4.250's whole point is distinguishing "fixed the primitive and
      removed the cascade" from "added another layer").

Both conditions are independently greppable/testable (see
test_branch_token_re() and test_message_is_removal() in the paired test
suite) and BOTH must hold -- this is the AND-NOT structure the design
brief asked for ("based on real, grep-able, testable patterns, not
vibes").

SYMBOL BOUNDARIES (coarser FILE fallback per the design brief's explicit
permission): this tool uses `git diff -U0`'s own per-hunk FUNCTION
CONTEXT line (the text git prints after the second `@@` on a hunk
header, e.g. "@@ -63 +90,13 @@ write_out() {") as the symbol name when
git's own context detector found one -- VERIFIED empirically against this
repo's real history before relying on it (git emits real function-name
context for this repo's own shell scripts, e.g. "write_out() {" /
"not_migrated() {", confirmed via a real `git diff -U0` run; this is
git's own builtin xfuncname heuristic, not reinvented here). When a
hunk's context line is empty (git could not determine one for that
hunk), this tool coarsens to the FILE-level fallback the design brief
explicitly sanctions: `FILE:<path>`. normalize_symbol() below performs
this reduction deterministically and is independently unit-testable.

EXIT CODES: 0 = ran cleanly, zero symbols flagged. 1 = ran cleanly, >= 1
symbol flagged (an ADVISORY non-zero per this project's own house
convention, e.g. review/precheck_pack.sh's "1 any check FAILs" -- a
caller choosing to treat this as a blocking condition is THAT caller's
decision, never this tool's; S11.4.269 forbids this tool itself from
being wired as a gate, it does not forbid a human script from reading
the exit code). 2 = usage/argument error. 3 = git/repository resolution
error (not a git repo, bad revision, requested item matches zero
commits where the caller asked for --item and that is itself unusual
enough to report distinctly from "zero flags on real history" -- NOTE:
an item matching zero commits still exits 0 with an empty finding list,
NOT exit 3; exit 3 is reserved for genuine git-command failures, e.g. an
unresolvable --range).

Honest limitations (S11.4.6, stated explicitly, never silently):
  - Symbol-boundary detection relies on git's OWN function-context
    heuristic, which is itself a regex-based guess for most languages
    (git's "default"/builtin pattern family) -- it can and does
    occasionally land on an unrelated nearby line rather than the exact
    enclosing function, especially near nested blocks. This tool neither
    improves nor second-guesses that heuristic; a mis-attributed hunk
    will be counted against whatever symbol git's own hunk header names
    (or FILE: if none), not silently dropped.
  - A bare early-return/guard-clause addition with NO branch keyword on
    the SAME added line (e.g. a lone `return 1` with its guarding `if`
    unchanged from a prior commit) is a documented FALSE-NEGATIVE this
    revision does not detect -- the design brief's own enumerated primary
    signal is the branch-OPENER keyword set, which this tool implements
    in full; bare-guard-clause detection would require tracking
    cross-commit AST structure this revision does not attempt.
  - This tool reads commit SUBJECT lines only for item-token matching,
    not commit bodies -- every real commit in this repo's own history
    used to calibrate this tool carries its item id in the subject, so
    this is not a guessed narrowing, but a project using a body-only
    convention would see every commit treated as item-less (silently
    excluded from every --item query, never crashing).
  - REFRACTOR_RATIO (0.8) and MIN_BRANCH_COMMITS (3, the S11.4.250
    shortlist item's own stated threshold) are tunable constants, never
    silently hardcoded policy -- both are CLI-overridable, their defaults
    stated once here and in TOWER_DETECTOR.md, never duplicated with
    drift risk.
"""
import argparse
import json
import re
import subprocess
import sys
from collections import OrderedDict, defaultdict

# ---------------------------------------------------------------------------
# Tunable constants (CLI-overridable; see argparse defaults below -- the
# single source of truth for the DEFAULT value is argparse itself, these
# module-level names exist only so the pure functions below can be
# unit-tested without going through argv).
# ---------------------------------------------------------------------------
DEFAULT_MIN_BRANCH_COMMITS = 3
DEFAULT_REFRACTOR_RATIO = 0.8

# A conditional-branch OPENER on an added (+) line. Deliberately scoped to
# the design brief's own enumerated keyword list (if/elif/case/except,
# plus the shell "elif"/"case ... in" spellings and the common
# else-if/catch spellings for non-shell/python callers) -- NOT a generic
# "any control flow" matcher, which would drown in false positives on
# ordinary loop/function edits that have nothing to do with a
# compensating special case.
BRANCH_TOKEN_RE = re.compile(
    r"^(?:"
    r"if\b"
    r"|elif\b"
    r"|else\s+if\b"
    r"|\}\s*else\s+if\b"
    r"|\}?\s*elif\b"
    r"|case\b.*\bin\b"
    r"|except\b"
    r"|except:"
    r"|catch\b"
    r"|catch\s*\("
    r")",
    re.IGNORECASE,
)

# Conventional-Commits TYPE(scope): description -- captures type and the
# free-text description (the part after the FIRST ": ") so both the
# message-shape checks below can inspect each independently.
CONVENTIONAL_COMMIT_RE = re.compile(
    r"^(?P<type>[a-zA-Z]+)(?:\([^)]*\))?\s*:\s*(?P<description>.*)$"
)

REFRACTOR_TYPES = {"refactor", "revert"}
REFRACTOR_LEAD_VERBS = ("remove", "replace", "delete", "revert", "refactor")

# Shell/generic control-flow KEYWORDS that git's own hunk-context
# heuristic frequently surfaces as the "context" line for a hunk located
# just after a closing/continuing control-flow token (e.g. a hunk whose
# preceding top-level-indented line is a bare "fi"/"done"/"else" in a
# shell script) -- MEASURED on this repo's own real history while
# calibrating this tool (a literal real-world false-match: a hunk inside
# scripts/fastcycle/consumers/migrate.sh whose context git reported as
# the single word "fi" was, before this fix, treated as a real symbol
# named "fi", silently merging UNRELATED patches to different functions
# that merely both happen to follow an `if` block into one spurious
# "symbol"). A context line whose FULL (not merely leading) token is one
# of these keywords carries NO real symbol information and is treated
# exactly like an empty context -- coarsened to the FILE-level fallback,
# never silently accepted as a function name (S11.4.201(7)(a): match
# STRUCTURE, not a token that merely LOOKS like an identifier).
_CONTROL_FLOW_KEYWORDS = frozenset(
    {
        "if", "fi", "then", "elif", "else", "for", "while", "until",
        "do", "done", "case", "esac", "in", "try", "except", "finally",
        "end", "begin", "function", "{", "}",
    }
)

# Round-number extraction: prefer an explicit "-r<N>" scope suffix (e.g.
# "T048-r22"), else fall back to free-text "round <N>" (e.g. "T048):
# round 11 --"), matching BOTH forms this repo's own real history uses
# (verified, never guessed -- see module docstring).
ROUND_SCOPE_RE = re.compile(r"-r(\d+)\b", re.IGNORECASE)
ROUND_TEXT_RE = re.compile(r"\bround\s+(\d+)\b", re.IGNORECASE)

# Hunk header: "@@ -a[,b] +c[,d] @@[ <context>]"
HUNK_HEADER_RE = re.compile(
    r"^@@ -(?P<old_start>\d+)(?:,(?P<old_count>\d+))? "
    r"\+(?P<new_start>\d+)(?:,(?P<new_count>\d+))? @@\s?(?P<context>.*)$"
)


class GitError(RuntimeError):
    """Raised on a genuine git-command failure (exit code 3 at the CLI
    boundary) -- distinct from "ran fine, matched nothing", which is a
    normal, exit-0 empty result, never an error."""


def run_git(repo, args):
    """Run a git subcommand in `repo`, returning stdout as str. Raises
    GitError on nonzero exit so a genuine git failure (bad revision,
    not-a-repo) is never silently read as an empty result (S11.4.201: a
    false "zero commits" reading, where the real condition is "git itself
    failed", is exactly the false-null class this constitution's
    measurement-semantics anchors forbid)."""
    proc = subprocess.run(
        ["git", "-C", repo] + args,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if proc.returncode != 0:
        raise GitError(
            "git {} failed (exit {}): {}".format(
                " ".join(args), proc.returncode, proc.stderr.strip()
            )
        )
    return proc.stdout


def normalize_symbol(file_path, context):
    """Reduce a hunk's raw function-context string (as git's own
    xfuncname heuristic emits it) to a stable symbol id. Pure, stateless,
    independently unit-testable (test_normalize_symbol in the paired
    test suite) -- the FILE fallback is the design brief's own explicit
    permission for "at minimum each FILE as a coarser fallback if
    cross-language symbol-boundary detection isn't readily available"."""
    context = (context or "").strip()
    if not context:
        return "FILE:{}".format(file_path)
    # shell: "name() {" / "function name() {"
    m = re.match(r"^(?:function\s+)?([A-Za-z_][\w]*)\s*\(\)\s*\{?", context)
    if m:
        return "{}::{}".format(file_path, m.group(1))
    # python: "def name(" / "class Name"
    m = re.match(r"^def\s+([A-Za-z_][\w]*)\s*\(", context)
    if m:
        return "{}::{}".format(file_path, m.group(1))
    m = re.match(r"^class\s+([A-Za-z_][\w]*)", context)
    if m:
        return "{}::{}".format(file_path, m.group(1))
    # generic fallback: first identifier-shaped token in the context line
    # -- rejected when the FULL context line is nothing but a bare
    # control-flow keyword (see _CONTROL_FLOW_KEYWORDS above): that is
    # not a symbol name, it is git's heuristic surfacing the nearest
    # enclosing block token, which carries no real attribution value and
    # must coarsen to FILE-level rather than be accepted as a fake
    # "symbol".
    if context.strip().lower().rstrip("(){};:") in _CONTROL_FLOW_KEYWORDS:
        return "FILE:{}".format(file_path)
    m = re.match(r"^([A-Za-z_][\w.:-]{1,80})", context)
    if m and m.group(1).lower() not in _CONTROL_FLOW_KEYWORDS:
        return "{}::{}".format(file_path, m.group(1))
    return "FILE:{}".format(file_path)


def parse_commit_subject(subject):
    """Split a Conventional-Commits subject into (type, description),
    defaulting type to "" and description to the whole subject when the
    subject does not match the convention (never crashes on an
    off-convention message -- an off-convention commit simply never
    matches REFRACTOR_TYPES/REFRACTOR_LEAD_VERBS, the conservative-safe
    direction: it is never spuriously EXCLUDED from the branch-adding
    count for a reason it does not actually carry)."""
    m = CONVENTIONAL_COMMIT_RE.match(subject)
    if not m:
        return "", subject
    return m.group("type").lower(), m.group("description").strip()


def message_is_removal(subject):
    """True iff this commit's OWN message shape (never its diff) states a
    refactor/removal intent -- see MESSAGE SHAPE in the module docstring.
    Independently unit-testable against literal subject strings."""
    ctype, description = parse_commit_subject(subject)
    if ctype in REFRACTOR_TYPES:
        return True
    lowered = description.lower()
    for verb in REFRACTOR_LEAD_VERBS:
        if lowered.startswith(verb):
            return True
    return False


def extract_round(subject):
    """Best-effort round number for reporting only (never for the
    AND-NOT flagging decision itself) -- prefers the "-r<N>" scope
    suffix, falls back to free-text "round <N>", else None (the caller
    then falls back to a 1-based sequential index, documented at the
    call site, never silently presented as a real round number)."""
    m = ROUND_SCOPE_RE.search(subject)
    if m:
        return int(m.group(1))
    m = ROUND_TEXT_RE.search(subject)
    if m:
        return int(m.group(1))
    return None


def item_token_regex(item_id):
    """A literal, word-bounded token match for `item_id` anywhere in a
    commit subject -- see HOW ITEMS ARE GROUPED in the module docstring
    for why this (not a Conventional-Commits scope parse) is the correct,
    repo-verified rule. `item_id`'s own round suffix, if the caller passed
    one (e.g. "T085-r5"), is stripped to its base id first so --item
    T085-r5 and --item T085 behave identically (both mean "the T085
    item", never "exactly commits whose subject spells the scope exactly
    that way")."""
    base = ROUND_SCOPE_RE.sub("", item_id)
    return re.compile(r"\b{}\b".format(re.escape(base)))


def parse_diff_hunks(diff_text):
    """Parse a `git show -U0 -- <path>` style unified diff into a list of
    (file_path, context, added_lines, removed_lines) tuples, one per
    hunk, restricted to the single file this diff was already scoped to
    by the caller via `-- <path>`. Pure text parsing, no git invocation --
    independently unit-testable against a literal diff string
    (test_parse_diff_hunks)."""
    current_file = None
    hunks = []
    cur_context = None
    cur_added = []
    cur_removed = []
    in_hunk = False

    def _flush():
        if in_hunk and current_file is not None:
            hunks.append((current_file, cur_context, cur_added[:], cur_removed[:]))

    for line in diff_text.splitlines():
        if line.startswith("diff --git "):
            _flush()
            in_hunk = False
            cur_context, cur_added, cur_removed = None, [], []
            # "diff --git a/<path> b/<path>" -- take the b/ side (the
            # post-image path, correct for renames too since git always
            # prints the destination path here).
            m = re.match(r"^diff --git a/(.+) b/(.+)$", line)
            current_file = m.group(2) if m else None
            continue
        if line.startswith("@@ "):
            _flush()
            m = HUNK_HEADER_RE.match(line)
            cur_context = m.group("context") if m else ""
            cur_added, cur_removed = [], []
            in_hunk = True
            continue
        if not in_hunk:
            continue
        if line.startswith("+++") or line.startswith("---"):
            continue
        if line.startswith("+"):
            cur_added.append(line[1:])
        elif line.startswith("-"):
            cur_removed.append(line[1:])
    _flush()
    return hunks


def count_branch_tokens(lines):
    """Count how many of `lines` (already stripped of their leading
    diff +/- marker) open a conditional branch per BRANCH_TOKEN_RE,
    ignoring blank lines -- a pure, independently testable counter."""
    n = 0
    for raw in lines:
        stripped = raw.strip()
        if not stripped:
            continue
        if BRANCH_TOKEN_RE.match(stripped):
            n += 1
    return n


def classify_hunk(added_lines, removed_lines, refractor_ratio):
    """Return (is_branch_adding, net_branch, total_add, total_del) for one
    hunk's DIFF SHAPE (condition (1) in the module docstring) -- the
    MESSAGE SHAPE check (condition (2)) is applied separately by the
    caller against the owning commit, since one commit's message governs
    every hunk it touches."""
    add_branch = count_branch_tokens(added_lines)
    del_branch = count_branch_tokens(removed_lines)
    net_branch = add_branch - del_branch
    total_add = len(added_lines)
    total_del = len(removed_lines)
    is_refactor_shaped = total_del >= refractor_ratio * max(total_add, 1)
    is_branch_adding = net_branch >= 1 and not is_refactor_shaped
    return is_branch_adding, net_branch, total_add, total_del


def list_commits(repo, item=None, rev_range=None, path=None):
    """Return an ordered (oldest-first) list of {"sha", "subject"} dicts
    for non-merge commits matching the given selectors. At least one of
    `item`/`rev_range` is required by the CLI layer (argparse enforces
    this, not this function) -- this function itself tolerates any
    combination (e.g. item AND rev_range together narrows both ways,
    exactly like the design brief's "a tracked workable-item id (or a
    commit range / a file path)" three-selector contract)."""
    git_args = [
        "log",
        "--no-merges",
        "--reverse",
        "--format=%H%x01%s",
    ]
    if rev_range:
        git_args.append(rev_range)
    else:
        git_args.append("HEAD")
    if path:
        git_args.extend(["--", path])
    out = run_git(repo, git_args)
    commits = []
    for line in out.splitlines():
        if not line.strip():
            continue
        sha, _, subject = line.partition("\x01")
        commits.append({"sha": sha, "subject": subject})
    if item:
        pattern = item_token_regex(item)
        commits = [c for c in commits if pattern.search(c["subject"])]
    return commits


def commit_touched_paths(repo, sha, path_filter=None):
    """Return the list of file paths this commit's own diff touches,
    restricted to `path_filter` (a single path or glob-free directory
    prefix) when given."""
    git_args = ["show", "--format=", "--name-only", sha]
    if path_filter:
        git_args.extend(["--", path_filter])
    out = run_git(repo, git_args)
    return [line for line in out.splitlines() if line.strip()]


def commit_diff(repo, sha, path_filter=None):
    """Return this commit's own `-U0` unified diff text, restricted to
    `path_filter` when given."""
    git_args = ["show", "--format=", "-U0", "--no-color", sha]
    if path_filter:
        git_args.extend(["--", path_filter])
    return run_git(repo, git_args)


def detect(repo, item=None, rev_range=None, path=None,
           min_branch_commits=DEFAULT_MIN_BRANCH_COMMITS,
           refractor_ratio=DEFAULT_REFRACTOR_RATIO):
    """Core detection entry point -- returns a JSON-serializable dict
    report. Never raises on a clean "zero matching commits" result
    (returns an empty findings list); raises GitError only on a genuine
    git-command failure, which the CLI layer maps to exit 3."""
    commits = list_commits(repo, item=item, rev_range=rev_range, path=path)

    # symbol -> ordered list of per-commit records that qualified as
    # branch-adding FOR THAT SYMBOL (insertion order == chronological
    # order, since `commits` is already oldest-first).
    symbol_hits = defaultdict(list)
    # Every commit touching a symbol (qualifying or not) -- kept so a
    # finding can report its full evidence trail, not only the
    # qualifying subset, making a human/agent's #11.4.102 investigation
    # strictly easier.
    symbol_all_touches = defaultdict(list)

    for commit in commits:
        sha = commit["sha"]
        subject = commit["subject"]
        is_removal_commit = message_is_removal(subject)
        round_no = extract_round(subject)
        diff_text = commit_diff(repo, sha, path_filter=path)
        hunks = parse_diff_hunks(diff_text)
        # One commit can touch the SAME symbol via more than one hunk
        # (e.g. two non-adjacent edits inside the same function) --
        # aggregate per (commit, symbol) before deciding qualification,
        # so a single compensating patch spread over two hunks is still
        # counted as ONE qualifying commit for that symbol, never two.
        per_symbol_hunks = defaultdict(lambda: ([], []))
        for file_path, context, added, removed in hunks:
            symbol = normalize_symbol(file_path, context)
            a, r = per_symbol_hunks[symbol]
            a.extend(added)
            r.extend(removed)
        for symbol, (added, removed) in per_symbol_hunks.items():
            is_branch_adding, net_branch, total_add, total_del = classify_hunk(
                added, removed, refractor_ratio
            )
            record = {
                "sha": sha,
                "subject": subject,
                "round": round_no,
                "net_branch": net_branch,
                "total_add": total_add,
                "total_del": total_del,
                "message_is_removal": is_removal_commit,
            }
            symbol_all_touches[symbol].append(record)
            qualifies = is_branch_adding and not is_removal_commit
            record["qualifies"] = qualifies
            if qualifies:
                symbol_hits[symbol].append(record)

    findings = []
    for symbol, hits in symbol_hits.items():
        if len(hits) < min_branch_commits:
            continue
        tipping_commit = hits[min_branch_commits - 1]
        fired_at_round = tipping_commit["round"]
        if fired_at_round is None:
            fired_at_round = "sequential-index-{}".format(min_branch_commits)
        file_path = symbol.split("::", 1)[0] if "::" in symbol else symbol[len("FILE:"):]
        findings.append(
            {
                "symbol": symbol,
                "file": file_path,
                "qualifying_commit_count": len(hits),
                "qualifying_commits": hits,
                "all_touches": symbol_all_touches[symbol],
                "fired_at_round": fired_at_round,
                "fired_at_commit": tipping_commit["sha"],
                "recommendation": (
                    "S11.4.250 heuristic-tower threshold reached on {}: "
                    "{} successive branch-adding commits under this item "
                    "touched this symbol. STOP adding a {}th patch -- "
                    "invoke superpowers:systematic-debugging / S11.4.102 "
                    "root-cause investigation on this symbol's real "
                    "underlying defect BEFORE writing another compensating "
                    "branch.".format(
                        symbol, len(hits), len(hits) + 1
                    )
                ),
            }
        )

    # Deterministic ordering -- oldest "fired_at_commit" first (matches
    # `commits`' own chronological order via a stable index lookup),
    # never dict/set iteration order (S11.4.50 / this repo's own house
    # C-003 determinism convention).
    sha_order = {c["sha"]: i for i, c in enumerate(commits)}
    findings.sort(key=lambda f: sha_order.get(f["fired_at_commit"], 0))

    return OrderedDict(
        [
            ("schema", "tower-detector-report/v1"),
            ("item", item),
            ("range", rev_range),
            ("path", path),
            ("min_branch_commits", min_branch_commits),
            ("refractor_ratio", refractor_ratio),
            ("commits_scanned", len(commits)),
            ("findings", findings),
        ]
    )


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="tower_detector_run.py",
        description=(
            "git-history patch-tower (S11.4.250 heuristic-tower) "
            "detector -- ADVISORY ONLY, see module docstring."
        ),
    )
    parser.add_argument("--repo", default=".", help="path to the git repository (default: .)")
    parser.add_argument(
        "--item",
        default=None,
        help=(
            "tracked workable-item id token to match anywhere in commit "
            "subjects, e.g. T085 or T085-r5 or ATM-123 (word-bounded "
            "literal match; see HOW ITEMS ARE GROUPED in the module "
            "docstring)."
        ),
    )
    parser.add_argument(
        "--range",
        dest="rev_range",
        default=None,
        help="a git revision range, e.g. v1.0..HEAD (default: HEAD, i.e. full reachable history)",
    )
    parser.add_argument(
        "--path",
        default=None,
        help="restrict to commits/diffs touching this path (file or directory)",
    )
    parser.add_argument(
        "--min-branch-commits",
        type=int,
        default=DEFAULT_MIN_BRANCH_COMMITS,
        help="flag threshold (default: {})".format(DEFAULT_MIN_BRANCH_COMMITS),
    )
    parser.add_argument(
        "--refractor-ratio",
        type=float,
        default=DEFAULT_REFRACTOR_RATIO,
        help="deletion/addition ratio above which a hunk is treated as a refactor, not a compensating patch (default: {})".format(
            DEFAULT_REFRACTOR_RATIO
        ),
    )
    parser.add_argument("--out", required=True, help="output report JSON path")
    args = parser.parse_args(argv)

    if not args.item and not args.rev_range and not args.path:
        parser.error("at least one of --item, --range, --path is required")

    if args.min_branch_commits < 1:
        parser.error("--min-branch-commits must be >= 1")
    if not (0.0 <= args.refractor_ratio <= 1.0):
        parser.error("--refractor-ratio must be within [0.0, 1.0]")

    try:
        report = detect(
            args.repo,
            item=args.item,
            rev_range=args.rev_range,
            path=args.path,
            min_branch_commits=args.min_branch_commits,
            refractor_ratio=args.refractor_ratio,
        )
    except GitError as exc:
        sys.stderr.write("tower_detector_run.py: {}\n".format(exc))
        return 3

    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2, sort_keys=False)
        fh.write("\n")

    if report["findings"]:
        sys.stderr.write(
            "tower_detector_run.py: {} symbol(s) flagged (advisory -- see {})\n".format(
                len(report["findings"]), args.out
            )
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
