#!/usr/bin/env python3
"""fc_entry.py - the ONE shared CLI-entry primitive for spec-004
"fast-dev-cycles" User Story 5's orchestration tools (`handoff.py`,
`limit_class.py`, `custody_sweep.py`), landed per T140 Round 10 independent
review (docs/CONTINUATION.md ADDENDUM 114, "Recommended root-cause work
instead of a Round 11 patch"):

  "The same defect family ('exit status or --out truth corrupted by
  stream I/O or an unguarded edge') has now come back 4 times: R7 (per-
  site write guards), R8 (catch set), R9 (boundary coverage, stderr
  prints) and R10 (argparse, raw writes, shutdown flush, primary
  output). Round 9 prescribed 'close the whole class'. The fix closed a
  syntactic proxy, the `print` token, rather than the class ... This is
  made worse by the 3 tools being near-forks (section 11.4.251). Every
  helper exists in 3 copies (`_safe_print`, `_safe_str`,
  `_scan_argv_for_out`, `_invalidate_stale_out`, `run_determinism_check`,
  `_write_dispatch_internal_error_doc`), so each round has to patch 3
  places."

Section 11.4.250 (heuristic-tower/primitive-defect): the Round 9 `_safe_print`
rewrite was itself the 4th layer stacked on the SAME underlying primitive
defect -- "a print/write call that can silently corrupt this tool's own exit
status is reachable from too many places, in too many forms, for a per-call
patch to ever close." This module is the deliberate STOP: it is now the
ONLY place any of the three sibling orchestration tools writes to stdout or
stderr at all (enforced mechanically -- see `check_no_bare_io` below, wired
as a static AST gate in `tests/test_fc_entry_r10_regression.sh`, T140 Round
10 review finding M2).

Section 11.4.227 (reuse, not reinvention): every one of `_safe_print`/
`_safe_str`/`_scan_argv_for_out`/`_invalidate_stale_out` previously existed
as three independently-authored, near-byte-identical copies (one per
sibling tool -- section 11.4.251's own "near-fork" defect, named explicitly
by the Round 10 review). This module is the ONE shared copy every sibling
tool now imports; a future fix lands here ONCE, not three times.

Two distinct emitters (T140 Round 10 review, "Recommended root-cause work",
item 2), replacing the single, overloaded `_safe_print` that conflated
them:

  - `emit_result(...)` -- the PRIMARY output channel: a document/verdict
    this tool's caller is meant to actually consume as THIS invocation's
    real deliverable (e.g. `custody_sweep.py inventory`'s own verdict
    document, printed to stdout only when `--out` was not given -- T140
    Round 10 review finding B1's exact scenario). A write OR flush
    failure here is NEVER swallowed -- it is raised to the caller, which
    MUST turn it into an honest, non-zero exit code (section 11.4 anti-
    bluff: an apparently-clean success whose own stated output could not
    actually be delivered is not a genuine success).
  - `diag(...)` -- the DIAGNOSTIC/informational channel: a progress
    message, a warning, a "here is what I did" success line whose real
    verdict already landed durably elsewhere (typically `--out`). A
    write OR flush failure here is always swallowed (section 11.4.101
    safe-reversible default) -- a failure to deliver a mere diagnostic
    must never itself become this tool's own exit status.

  T140 Round 10 review finding M4 (fixed here, closing a NEW regression
  the Round 9 `_safe_print` itself introduced): the retired `_safe_print`
  redirected the WHOLE target file descriptor to `os.devnull` via
  `os.dup2` the FIRST time any write failed (e.g. on one
  `UnicodeEncodeError`) -- silently dropping EVERY SUBSEQUENT, unrelated
  line for the rest of the process. `diag` here handles each call's own
  failure independently: a failure is caught and discarded for THAT call
  only, never mutating global process/file-descriptor state, so one bad
  line never silences every later, good one.

`FcArgumentParser` (T140 Round 10 review finding I1(a)): argparse's own
`_print_message` (the method every one of `--help`, a usage error via
`parser.error(...)`, and `parser.exit(status, message)` funnels its output
through) writes DIRECTLY to the target stream via `file.write(...)`,
entirely outside this module's `emit_result`/`diag` split -- an unwritable
stream during a usage error previously escaped uncaught, undocumented exit
code 120 (see `run_cli_main`'s own docstring for the mechanism). This
subclass overrides `_print_message` to route through `diag` (argparse's
own help/usage text is diagnostic, not this tool's primary deliverable),
closing the ONE remaining raw-write path into argparse-owned code without
touching argparse's own message-construction logic at all.

`run_cli_main` (T140 Round 10 review finding I1(b), the "Recommended root-
cause work" item 1): the single entry point every sibling tool's own
`if __name__ == "__main__":` footer now calls instead of
`sys.exit(main(sys.argv[1:]))` directly -- see its own docstring below for
the full stdout-block-buffering / interpreter-shutdown-flush mechanism this
closes, and why it deliberately ends in `os._exit(rc)` rather than
`sys.exit(rc)`.

Producer != Verifier (section 11.4.240): this module is infrastructure
shared BY the three sibling tools' own implementations; it carries no
subcommand-specific business logic of its own (no `handoff_id`/
`body_hash`/`limit_signal`/verdict semantics) and is not itself a T140
Round-N review target for any tool-specific wire-format claim -- it is
reviewed, and regression-tested, on its OWN channel-delivery and exit-code
contract alone (`tests/test_fc_entry_r10_regression.sh`).

Stdlib only. Python 3.
"""
import argparse
import ast
import os
import sys

# Captured before any renaming below -- diag()/emit_result() always call the
# REAL builtin, never (recursively) themselves.
_real_print = print

# ---------------------------------------------------------------------------
# The two emitters.
# ---------------------------------------------------------------------------
_PRIMARY_EMITTER_NAMES = ("emit_result",)
_DIAGNOSTIC_EMITTER_NAMES = ("diag",)


def emit_result(*args, **kwargs):
    """PRIMARY output channel (see module docstring). Writes exactly as
    `print(*args, **kwargs)` would, then EXPLICITLY, IMMEDIATELY flushes
    the target stream -- closing T140 Round 10 review finding I1(b) for
    this specific call site's own class of failure: a text stream is
    commonly block-buffered when its target is not a tty (a file, a
    pipe, `/dev/full`), so `stream.write(...)` alone can report SUCCESS
    while the real underlying OS write only happens -- and can only FAIL
    -- at a later flush. Flushing HERE, at the call site, makes that
    failure surface to THIS caller immediately, rather than being
    silently deferred to interpreter shutdown (see `run_cli_main`'s own
    docstring for the second, backstop half of this same fix).

    Deliberately raises on failure (`print`'s own exception, or the
    explicit `flush()` call's own exception) -- NEVER swallowed. Every
    caller of this function MUST wrap it and convert a raised exception
    into an honest, non-zero exit code (T140 Round 10 review finding
    B1's own fix: `custody_sweep.py`'s `inventory`/`propose`/
    `verify-proposal`, without `--out`, print the verdict document
    itself to stdout as their ONLY delivery channel -- a write failure
    there must never be reported as a clean exit 0)."""
    stream = kwargs.get("file", sys.stdout)
    _real_print(*args, **kwargs)
    stream.flush()


def diag(*args, **kwargs):
    """DIAGNOSTIC/informational channel (see module docstring). Writes
    exactly as `print(*args, **kwargs)` would, then immediately flushes
    the target stream (the SAME immediate-flush fix `emit_result` above
    applies, closing T140 Round 10 review finding I1(b) for every
    diagnostic/success-line call site too -- e.g. `handoff.py validate`'s
    own success line, whose real verdict already landed in `--out`).

    Swallows ANY exception from either the underlying `print()` call OR
    the explicit `flush()` -- a diagnostic message failing to deliver
    must never itself become this tool's exit status. Unlike the retired
    `_safe_print` (T140 Round 10 review finding M4), a failure here never
    mutates any global process/file-descriptor state -- each call is
    handled entirely independently, so one bad line can never silence
    every later, unrelated one."""
    stream = kwargs.get("file", sys.stdout)
    try:
        _real_print(*args, **kwargs)
        stream.flush()
    except Exception:
        pass


def safe_str(exc):
    """T140 Round 9 review finding R9-M1, landed here ONCE (section
    11.4.227 reuse-not-reinvention -- this function previously existed as
    three independent, zero-test-coverage copies, T140 Round 10 review
    finding M1): `str(exc)` is not guaranteed safe -- an exception class
    with a pathological, raising `__str__`/`__repr__` would itself escape
    a naive `"%s" % exc` interpolation used while ALREADY handling an
    unrelated crash (the worst possible place for a second, masking
    crash to occur). No stdlib exception actually does this; this is
    defense-in-depth for a hostile/buggy third-party exception type
    reaching this boundary. Falls back to just the exception's type name
    on failure."""
    try:
        return str(exc)
    except Exception:
        return "<%s: str() raised>" % type(exc).__name__


def scan_argv_for_out(argv, flag="--out"):
    """Best-effort extraction of `flag`'s value directly from RAW argv,
    usable even BEFORE argparse has parsed (or even successfully
    CONSTRUCTED its parser). Supports both `--out VALUE` and
    `--out=VALUE`.

    T140 Round 10 review finding M3, second half (fixed here): the
    retired per-tool copies of this function returned the FIRST matching
    occurrence -- argparse itself resolves a REPEATED single-value option
    to its LAST occurrence (`run_determinism_check`'s own child
    invocation, `inner + ["--out", out_i]`, relies on exactly this
    last-wins behaviour to override a caller-supplied `--out` with its
    own private temp path). A first-match scan here would silently
    disagree with what the real parser will actually resolve to, and --
    combined with `invalidate_stale_out` below -- could delete the
    CALLER's own real `--out` file instead of the determinism-check
    child's own private temp file. This function now scans the WHOLE
    argv and keeps the LAST match, matching argparse's own resolution
    exactly.

    Heuristic/best-effort only -- does not validate flag ownership per
    subcommand; a false-positive match only causes an extra, harmless
    defensive invalidation (see `invalidate_stale_out` below) of a path
    this invocation may not end up writing to anyway, never a security
    concern."""
    result = None
    eq_prefix = flag + "="
    for i, tok in enumerate(argv):
        if tok == flag and i + 1 < len(argv):
            result = argv[i + 1]
        elif tok.startswith(eq_prefix):
            result = tok[len(eq_prefix):]
    return result


def invalidate_stale_out(out_path):
    """Remove any EXISTING `out_path` file, so that a crash reaching this
    tool's own top-level dispatch boundary BEFORE a fresh document is
    written for THIS invocation can never leave a STALE, previous-run
    `--out` document in place looking like a genuine, fresh, correct
    result for THIS invocation -- the caller trusts `--out`'s content,
    and a leftover verdict from an unrelated earlier run, read as if it
    were THIS run's real verdict, is a silent lie (worse than an honest,
    detectable absence).

    T140 Round 10 review finding M3, first half (fixed here): every
    sibling tool's own `main()` previously called this UNCONDITIONALLY,
    before argument parsing even began -- so a PURE, legitimate usage
    error (e.g. a required flag genuinely missing) deleted a caller's
    pre-existing, genuinely UNRELATED `--out` file even though this
    invocation never attempted, and was never going to attempt, any real
    operation on it at all. Each sibling tool's own `main()` now calls
    this function ONLY from inside its own top-level exception handler
    (the ONE place a genuinely unanticipated crash -- not a clean
    argparse usage error, which raises `SystemExit` and is never caught
    there -- is handled), immediately before writing that handler's own
    internal-error document: this tool is "confident it's about to
    genuinely attempt the operation" (write something honest to --out)
    at exactly that point, never merely because a command line was
    typed. Best-effort: a removal failure (permission denied, read-only
    filesystem) is swallowed here -- it surfaces downstream when the
    real write is attempted."""
    if not out_path:
        return
    try:
        os.remove(out_path)
    except OSError:
        pass


class FcArgumentParser(argparse.ArgumentParser):
    """T140 Round 10 review finding I1(a) (fixed here): argparse's own
    `_print_message` -- the one method `--help`, `parser.error(...)`
    (every usage error), and `parser.exit(status, message)` all funnel
    their output through -- writes DIRECTLY to the target stream
    (`file.write(message)`), entirely bypassing `emit_result`/`diag`
    above. An unwritable stream during any of those paths previously
    escaped as an uncaught `OSError` reaching `main()`'s own dispatch
    boundary from OUTSIDE its `try:` (argument-parser construction and
    parsing sits INSIDE that boundary in every sibling tool, per the
    T140 Round 9b fix -- but `_print_message`'s OWN raw write was never
    covered by it, so this specific raise still corrupted the exit code
    even with that boundary present), reported as an undocumented exit
    code (120) outside this tool's own documented {0,1,2,...} contract.

    Overriding ONLY `_print_message` -- never `error`/`exit`/
    `format_usage`/`format_help` -- routes every one of argparse's own
    message-printing call sites through this ONE override without
    touching argparse's own message-CONSTRUCTION logic at all (section
    11.4.227 reuse-not-reinvention: argparse's own text/formatting stays
    entirely unchanged, only WHERE the bytes are written changes).
    argparse's own help/usage/error text is diagnostic, never this
    tool's primary deliverable (the primary deliverable, where one
    exists, is always a real `--out` document written by this tool's own
    subcommand handlers, never argparse's help text) -- so this routes
    through `diag`, never `emit_result`: a failure to DISPLAY a usage
    message must never itself become this tool's exit status (the exit
    status argparse itself computes -- 0 for `--help`, 2 for a usage
    error -- is unaffected either way; only the MESSAGE delivery is
    guarded)."""

    def _print_message(self, message, file=None):
        if not message:
            return
        # `end=""` matches argparse's own `file.write(message)` exactly --
        # argparse's own message text already carries every newline it
        # wants; `diag`'s default `print`-style trailing newline would add
        # one argparse never asked for.
        diag(message, file=file, end="")


def run_cli_main(main_fn, argv):
    """T140 Round 10 review, "Recommended root-cause work" item 1 (see
    module docstring for the full finding text): the ONE shared CLI-entry
    primitive every sibling tool's own `if __name__ == "__main__":`
    footer now calls -- `run_cli_main(main, sys.argv[1:])` -- in place of
    the previous `sys.exit(main(sys.argv[1:]))`.

    Runs `main_fn(argv)`. `main_fn` is expected to return an int exit
    code on a normal, already-handled path (every sibling tool's own
    `main()` already catches every exception ITS OWN body anticipates
    and returns an honest code for it -- this primitive is the OUTERMOST
    layer, not a replacement for that). Two additional cases are handled
    here, deliberately NOT inside any individual tool's own `main()`,
    because they are properties of the PROCESS boundary, not of any one
    tool's own business logic:

      - `SystemExit` (argparse's own `--help` / usage-error path, which
        is NOT a subclass of `Exception` and so is never caught by any
        sibling tool's own `except Exception` dispatch boundary) is
        caught HERE and its `code` becomes `rc` -- so `--help`/usage
        errors are folded into this SAME final-flush-then-`os._exit`
        path below, rather than propagating all the way to Python's own
        default top-level `SystemExit` handling (which performs ITS OWN
        interpreter-shutdown flush -- see below for why that matters).
      - Any other uncaught `Exception` escaping `main_fn` entirely (a
        genuinely unanticipated case none of that tool's own boundary
        widening enumerated) is reported to the diagnostic channel and
        mapped to `EXIT_USAGE` (2) -- the same "an internal error is
        never silently swallowed into a fabricated finding" convention
        (section 11.4.6) every sibling tool's own boundary already uses.
        `BaseException` subclasses OTHER than `SystemExit`
        (`KeyboardInterrupt`) are deliberately NOT caught -- an operator
        interrupt still terminates this process immediately, exactly as
        before this primitive existed.

    THEN -- regardless of how `main_fn` returned -- explicitly,
    unconditionally flushes BOTH `sys.stdout` and `sys.stderr` ONE LAST
    TIME, as a backstop closing T140 Round 10 review finding I1(b) for
    any content a FUTURE caller might someday write through some path
    this module does not yet enumerate (matching this project's own "fix
    the primitive, not merely today's one reachable path" convention,
    section 11.4.250). A failure flushing EITHER stream here is ALWAYS
    swallowed, NEVER escalated into `rc` -- this backstop flush is
    deliberately NOT where PRIMARY-channel delivery failures are
    detected: that detection already happened, precisely, at
    `emit_result`'s OWN call site (its own immediate `flush()`, which
    RAISES on failure and is caught by THIS function's own `except
    Exception` clause above, mapping to `EXIT_USAGE`). A live, corrected
    bug from an earlier draft of this function is the reason this is
    stated so explicitly: an EARLIER version of this backstop escalated
    ANY stdout-flush failure to `EXIT_USAGE` whenever `rc == 0` --
    reasoning "stdout is the primary channel" -- which is WRONG for
    `handoff.py`/`limit_class.py` (where `--out` is ALWAYS the real
    deliverable and stdout NEVER carries primary content at all).
    Live-reproduced: `handoff.py --help >/dev/full` -- a pure DIAGNOSTIC
    print via `diag()`, whose own internal flush already swallowed the
    failure correctly -- still wrongly turned `--help`'s own clean
    `SystemExit(0)` into `rc=2`, because THIS backstop's OWN second,
    redundant `sys.stdout.flush()` call observed the SAME already-broken
    stream's lingering error state and (wrongly) escalated it. The fix:
    this backstop's flush is diagnostic-only (belt-and-suspenders that a
    stream WAS flushed before process exit), never a SECOND, independent
    primary-channel-failure detector competing with `emit_result`'s own,
    correctly-scoped one.

    Finally calls `os._exit(rc)` -- deliberately NEVER `sys.exit(rc)`.
    `sys.exit`/a normal Python return from `main()` triggers Python's OWN
    interpreter-shutdown sequence, which performs ITS OWN final flush of
    every still-open stream (including stdout/stderr) -- and can ITSELF
    raise, turning an already-clean `rc` into a completely different,
    undocumented process exit status (T140 Round 9's own docstring
    claimed this "cannot" happen; T140 Round 10 review's own live
    reproduction proved that claim false for stdout -- this was, in
    fact, the exact mechanism behind every one of this round's own rc=120
    findings). By the time `run_cli_main` reaches this final line, every
    stream this tool could possibly have written to has ALREADY been
    explicitly flushed (via `emit_result`/`diag`'s own per-call flush, or
    -- immediately above -- this function's own best-effort backstop
    flush) and `rc` already correctly reflects any genuine primary-
    channel delivery failure (detected, precisely, at `emit_result`'s own
    call site, never guessed here) -- so `os._exit`, which skips every
    atexit handler and every interpreter-shutdown buffer flush Python
    would otherwise attempt, loses nothing, and closes the one remaining
    gap through which a stream failure could still
    silently rewrite this tool's own exit code."""
    try:
        rc = main_fn(argv)
    except SystemExit as exc:
        rc = exc.code
        if rc is None:
            rc = 0
        elif not isinstance(rc, int):
            # argparse's own `exit()` always passes an int; this is
            # defense-in-depth for a non-argparse SystemExit(str) some
            # future code path might someday raise.
            rc = 2
    except Exception as exc:
        diag("%s: an uncaught %s escaped the top-level dispatch entirely: %s -- this is a genuinely "
             "unanticipated case no individual tool-level fix enumerated; treat as "
             "unsafe/unverified until independently, manually re-verified"
             % (os.path.basename(sys.argv[0]) if sys.argv else "fastcycle", type(exc).__name__, safe_str(exc)),
             file=sys.stderr)
        rc = 2
    if rc is None:
        rc = 0
    elif not isinstance(rc, int):
        rc = 2
    try:
        sys.stdout.flush()
    except Exception:
        pass
    try:
        sys.stderr.flush()
    except Exception:
        pass
    os._exit(rc)


# ---------------------------------------------------------------------------
# Static AST gate (T140 Round 10 review finding M2, section 11.4.227 reuse-
# not-reinvention, section 11.4.250 heuristic-tower/primitive-defect): a
# MECHANICAL check that a bare `print(...)` call, or a raw `sys.stdout.write
# (...)`/`sys.stderr.write(...)` call, can never silently creep back into
# one of the three sibling orchestration tools outside the two designated
# emitters -- the exact class of regression T140 Round 10 review finding M2
# demonstrated live ("my mutation reverting custody's WARNING print
# (:1116) to print( SURVIVED all 5 custody files"). Wired into
# `tests/test_fc_entry_r10_regression.sh`.
# ---------------------------------------------------------------------------
def check_no_bare_io(path):
    """Parses the Python source file at `path` and returns a list of
    human-readable violation strings (one per offending call site,
    "<path>:<lineno>: <what>"), or an empty list if the file is clean.

    A violation is any `Call` node, anywhere in the module's top-level
    code or ANY function body, whose callee is:
      - the bare name `print` (a `Name` node, `id == "print"`) -- catches
        both a freshly-typed `print(...)` and a reverted-from-`diag(...)`
        mutation identically; OR
      - an attribute-call chain of the exact literal shape
        `sys.stdout.write(...)` / `sys.stderr.write(...)` (a `Call` whose
        `func` is `Attribute(attr="write", value=Attribute(attr in
        ("stdout","stderr"), value=Name(id="sys")))`) -- catches a raw
        diagnostic bypass like the retired `sys.stderr.write(proc.stderr)`
        T140 Round 10 review finding I1(c) found in every one of the
        three sibling tools' own `run_determinism_check`.

    EXCLUDED, by design, never a gap this gate is meant to close: the
    `_real_print(*args, **kwargs)` calls inside `diag`/`emit_result`
    themselves (`_real_print` is a distinct name from the bare `print`
    builtin -- the whole point of capturing it once at module load, see
    this module's own header comment); the assignment `_real_print =
    print` (a `Name` in `Load` context, never a `Call`); and argparse's
    OWN internal `file.write(...)` calls inside its own, unmodified
    stdlib source (this gate only ever parses files THIS project owns,
    never argparse's own installed stdlib module).

    This function deliberately does NOT special-case "except inside
    `diag`/`emit_result` in THIS file" -- it is meant to be run against
    the three sibling ORCHESTRATION tools (`handoff.py`, `limit_class.py`,
    `custody_sweep.py`), none of which define their OWN `diag`/
    `emit_result`/`print` call sites anymore (every one of their former
    `_safe_print` call sites is now a call to THIS module's imported
    `diag`/`emit_result` -- a plain `Name` reference to an IMPORTED
    function, never a bare `print` or `sys.std*.write` AST shape at
    all). Running it against `fc_entry.py` itself is a SEPARATE,
    narrower check (`tests/test_fc_entry_r10_regression.sh` does this
    too, but scoped to exclude `diag`/`emit_result`/
    `FcArgumentParser._print_message`'s own bodies by function name,
    since THIS file is where the two legitimate raw-print sites are
    meant to live)."""
    with open(path, encoding="utf-8") as fh:
        source = fh.read()
    tree = ast.parse(source, filename=path)
    violations = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        func = node.func
        if isinstance(func, ast.Name) and func.id == "print":
            violations.append("%s:%d: bare print(...) call outside the designated diag()/emit_result() "
                               "emitters" % (path, getattr(node, "lineno", 0)))
            continue
        if (isinstance(func, ast.Attribute) and func.attr == "write"
                and isinstance(func.value, ast.Attribute)
                and func.value.attr in ("stdout", "stderr")
                and isinstance(func.value.value, ast.Name)
                and func.value.value.id == "sys"):
            violations.append("%s:%d: raw sys.%s.write(...) call outside the designated diag()/"
                               "emit_result() emitters" % (path, getattr(node, "lineno", 0), func.value.attr))
    return violations


def check_no_bare_io_excluding(path, exempt_function_names):
    """Same as `check_no_bare_io` above, but violations whose enclosing
    function definition's name is in `exempt_function_names` are excluded
    -- used to check THIS module (`fc_entry.py`) itself, where `diag`/
    `emit_result`/`FcArgumentParser._print_message` are the intentional,
    sole home of the two raw-I/O patterns this gate otherwise forbids."""
    with open(path, encoding="utf-8") as fh:
        source = fh.read()
    tree = ast.parse(source, filename=path)
    exempt_nodes = set()
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name in exempt_function_names:
            for sub in ast.walk(node):
                exempt_nodes.add(sub)
    violations = []
    for node in ast.walk(tree):
        if node in exempt_nodes:
            continue
        if not isinstance(node, ast.Call):
            continue
        func = node.func
        if isinstance(func, ast.Name) and func.id == "print":
            violations.append("%s:%d: bare print(...) call outside the designated diag()/emit_result() "
                               "emitters" % (path, getattr(node, "lineno", 0)))
            continue
        if (isinstance(func, ast.Attribute) and func.attr == "write"
                and isinstance(func.value, ast.Attribute)
                and func.value.attr in ("stdout", "stderr")
                and isinstance(func.value.value, ast.Name)
                and func.value.value.id == "sys"):
            violations.append("%s:%d: raw sys.%s.write(...) call outside the designated diag()/"
                               "emit_result() emitters" % (path, getattr(node, "lineno", 0), func.value.attr))
    return violations


def _cli_ast_gate(argv):
    """`fc_entry.py ast-gate <file> [<file> ...]` -- prints every
    violation found across every named file and exits 1 if any were
    found, 0 if every file is clean. Standalone CLI entry so the gate can
    be invoked directly from a test script without importing this module
    from Python (though `tests/test_fc_entry_r10_regression.sh` does
    both)."""
    any_violation = False
    for path in argv:
        for v in check_no_bare_io(path):
            diag(v, file=sys.stderr)
            any_violation = True
    return 1 if any_violation else 0


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "ast-gate":
        run_cli_main(_cli_ast_gate, sys.argv[2:])
    else:
        diag("usage: fc_entry.py ast-gate <file> [<file> ...]", file=sys.stderr)
        sys.exit(2)
