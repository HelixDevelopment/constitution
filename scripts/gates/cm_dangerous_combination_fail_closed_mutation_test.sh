#!/usr/bin/env bash
# cm_dangerous_combination_fail_closed_mutation_test.sh — §1.1 paired-mutation
# meta-test for CM-DANGEROUS-COMBINATION-FAIL-CLOSED (anchor §11.4.252).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Proves the gate is NOT a bluff: plants each fail-open anti-pattern shape the
# gate detects (swallowed exception / silent-default-return / credential-
# defaulted-to-literal, in Python and C-family shapes) and asserts the gate
# correctly FAILs on each; then asserts it PASSes on clean fixtures using the
# LEGITIMATE counterpart patterns (logged/re-raised handling, real fallback
# work, env-var-sourced credential fallback) plus an honest SKIP on a
# no-candidate-files directory.
#
# ── Blind-spot regression fixtures (the reason this suite exists) ────────────
# The gate previously matched Python `except:` handlers with a LINE-ANCHORED
# REGEX and read the handler body at exactly `lineno+1`. That shape was blind
# in FOUR ways and false-positive in a FIFTH, and each is pinned here by its
# own fixture so the specific blind spot cannot silently return:
#
#   L1  trailing comment on the handler line  (`except Exception:  # noqa`)
#   L2  tuple exception clause                (`except (OSError, ValueError):`)
#   L3  a comment between `except` and `pass` (body no longer at lineno+1)
#   L4  silent default return                 (`except: return None`)
#   L5  CARRIER FALSE POSITIVE — a docstring / string literal that merely
#       MENTIONS `except: pass` (a style guide, or this very file) was matched
#       as if it were code. The negative control below asserts the gate stays
#       SILENT on it (§11.4.201(1): a false-positive refusal is a FAIL-bluff
#       exactly as a false-negative pass is a PASS-bluff).
#
# Every L1-L4 fixture PASSED the pre-fix gate (i.e. went undetected) and MUST
# FAIL a correct one; the L5 carrier FAILED the pre-fix gate and MUST PASS a
# correct one. Both polarities are asserted, in BOTH the structural (AST) and
# the degraded (text-fallback) execution modes.
#
# The same discipline extends to every later fixture. L30-L34 were added after
# an independent review measured that four gate invariants were pinned by
# NOTHING -- two of them SURVIVING mutations that restored real defects:
#   L30  a `#` COMMENT on a real `with` line was read as the call's own
#        argument (an OVER-report; RED against the pre-fix gate, PASSes now)
#   L31  the multi-token with-line scan must CONTINUE past a rejected token,
#        not stop: `continue` -> `break` SURVIVED the whole suite while
#        silently losing a real violation
#   L32  the SUFFIX half of the breadth word boundary: dropping it SURVIVED
#        while turning `suppress(ExceptionGroup)` -- a real 3.11+ builtin and
#        a genuinely NARROW tolerance -- into a refusal
#   L33  a `#` INSIDE a string must not truncate the line (pins the comment
#        strip's quote-awareness)
#   L34  an ESCAPED quote before such a `#` (pins its backslash handling)
#
# L35-L39 + P9-P13 were added the round after that, when a further independent
# review measured that the L30-L34 close had itself REGRESSED the gate and
# that this file's own verdict propagation was pinned by nothing:
#   L35  a TRIPLE-QUOTED string whose interior holds a quote -- the strip read
#        `"""` as three one-character toggles, so a `#` INSIDE the string read
#        as outside it and the real violation after it was SILENTLY DELETED.
#        RED against the shipped gate (ast=1/text=0), GREEN after the fix, and
#        a REGRESSION: reverting the strip CALL alone restored text=1
#   L36  the SINGLE-quoted triple delimiter, same defect, same measurement
#   L37  a `#` inside a SINGLE-quoted string: L33/L34 are both DOUBLE-quoted,
#        so both SURVIVED deleting the apostrophe from the quote tracker
#   L38  a DOCSTRING before `pass`: dropping the AST classifier's docstring
#        filter SURVIVED the whole suite while restoring a real under-report
#   L39  an UNPARSEABLE file: deleting the UNPARSED handoff SURVIVED, and made
#        the gate report a confident clean PASS with ZERO note -- the exact
#        silent skip the gate's own comment forbids
#   P9-P11  the helpers' VERDICT PROPAGATION (see the boundary note below)
#   P12/P13 `--help` clean on stderr, and HEADER_LINES accurate -- both from
#        defects introduced WHILE writing this round: an apostrophe in an awk
#        comment (loud) and a backtick in a double-quoted caveat (silent)
#   L40/L41 NEGATIVE CONTROLS for the POSITION ADVANCE of the triple-quote
#        fix itself. L35-L37 prove the strip ENTERS and LEAVES a triple-quoted
#        region; they do not prove it advances PAST the delimiter it just
#        consumed. THREE mutations of the new code SURVIVED L30-L39 -- found
#        by fuzzing the extracted function over every quote/hash/backslash/
#        paren string up to length 6 plus 400k longer random ones, then
#        filtering to lines that really parse as Python. All three are
#        §11.4.201(1) FALSE-ALARM direction (healthy code refused), which is
#        why both fixtures are `expect_pass`, not `expect_fail`.
#   L42/L43 the round after THAT, when a further independent review measured
#        two MORE surviving mutations of the same quote model -- both landing
#        on the ast=1/text=0 SILENT UNDER-REPORT that an earlier round graded
#        BLOCKING, reached through doors L30-L41 leave open:
#          L42  the OPEN-detection WIDTH. L35-L37 pin that the strip ENTERS
#               and LEAVES a triple-quoted region and L40/L41 pin that it
#               ADVANCES past the delimiter it consumed; NOTHING pinned how
#               WIDE the OPEN test looks. Narrowing it from three characters
#               to two makes any two ADJACENT quotes read as a triple-open --
#               an EMPTY short-quoted string is exactly that -- and the
#               mutation SURVIVED the whole suite (101 OK / 0 FAIL / exit 0).
#          L43  CROSS-QUOTE confusion INSIDE a string. Relaxing the in-string
#               close test so EITHER quote character closes the region also
#               SURVIVED the whole suite. L37 pins the apostrophe half of the
#               OPEN tracker; no fixture had a DOUBLE-quoted string with an
#               INTERIOR apostrophe followed by a `#` before a real violation.
#        Both are `expect_fail` in BOTH modes: each file is a REAL violation
#        the shipped gate catches (measured ast=1/text=1) and each mutant
#        silently loses (measured ast=1/text=0). Each kills ONLY its own
#        mutation -- measured: L42 leaves the L43 mutant at text=1 and L43
#        leaves the L42 mutant at text=1 -- so neither is redundant cover.
#   L44-L49 the round after THAT. A further independent review measured THREE
#        more surviving mutations and supplied ready-to-lift fixture texts for
#        them. MEASUREMENT here accepted ONE and REFUTED TWO: both of those
#        proposed files left their own mutant at exactly the shipped verdict
#        (0/0), so they killed nothing and would have shipped as decoration.
#        Re-deriving them, and then sweeping the model SYSTEMATICALLY rather
#        than one door at a time -- every WIDTH and every POSITION ADVANCE in
#        the quote machine mutated in turn (close width 2 and 4, open width 2
#        and 4, both `d3` constructions, +1/+2/+3 advances on all four
#        branches, the triple-open delimiter identity, the loop bound, the
#        comment-cut offset) -- found THREE further survivors the review had
#        not reached. Eleven of those mutations died against L30-L43; SIX
#        survived the entire 105-assertion suite and are killed here, exactly
#        one fixture each. Measured: the fixture x mutation kill matrix is
#        DIAGONAL, so no fixture below is redundant cover.
#          L44  the CLOSE-detection WIDTH -- the exact mirror of L42 one
#               branch lower. L42 pins how WIDE the OPEN test looks and
#               L40/L41 pin the position advance; NOTHING pinned the CLOSE
#               width. Narrowed to two characters, two ADJACENT quotes inside
#               a triple close it, the `#` genuinely inside the string then
#               reads as a comment, the line is cut there, and the real
#               violation after the cut is silently deleted. ast=1/text=0.
#               NOTE, measured: the obvious shape with the `#` ABUTTING the
#               quote pair does NOT demonstrate this -- the mutant's own
#               `i += 2` steps straight OVER the `#`, no cut happens, and the
#               fixture measures text=1 under BOTH shipped and mutant, i.e.
#               kills nothing. A character must sit BETWEEN the pair and the
#               `#`, which is what the `x` in this fixture is for.
#          L45  the OPEN-side position OVER-advance. L40/L41 pin the advance
#               being too SHORT; nothing pinned it being too LONG. Advancing
#               three instead of two skips the first CONTENT character of a
#               triple, which can only matter when that character is itself
#               the start of the closing run -- the EMPTY triple-quoted
#               string. The mutant never closes it, the line is returned
#               UNCUT, and the broad form quoted in the REAL trailing comment
#               is scanned as CODE: healthy code REFUSED, the §11.4.201(1)
#               FAIL-bluff direction. The fixture proposed for this finding
#               omitted the trailing comment; measured, shipped and mutant
#               both returned 0/0 and it killed nothing.
#          L46  the ESCAPE-SKIP WIDTH. L34 pins DELETING the backslash
#               handling; nothing pinned how FAR it skips. Skipping two
#               characters instead of one swallows a closing quote sitting
#               directly after an escaped character -- and a trailing
#               backslash in a Windows path literal is everyday Python. The
#               string never closes, the trailing comment is never stripped,
#               and healthy code is REFUSED. Measured: this one fixture also
#               kills the `i += 3` variant, so the whole width family falls
#               to it. The fixture proposed for this finding again omitted
#               the trailing comment and measured 0/0 both ways.
#          L47  the SHORT-string CLOSE over-advance (NOT reached by the
#               review). Skipping one character after closing a short string
#               swallows the OPENING quote of an IMPLICITLY CONCATENATED
#               neighbour, so that neighbour's body is read as CODE and a `#`
#               inside it cuts the line -- ast=1/text=0, the silent
#               under-report direction again.
#          L48  the SHORT-string OPEN over-advance (NOT reached by the
#               review). Skipping the first content character of a short
#               string matters when that character IS the closing quote --
#               the EMPTY short string. The mutant never closes it, the
#               trailing comment is never stripped, healthy code is REFUSED.
#          L49  the TRIPLE-OPEN DELIMITER IDENTITY (NOT reached by the
#               review). L36/L37 pin the apostrophe in the OPEN tracker and
#               L43 pins cross-quote confusion INSIDE a region, but nothing
#               pinned that a triple-APOSTROPHE region is tracked WITH the
#               apostrophe. Hard-wiring the opener to a double quote leaves
#               every triple-apostrophe region permanently open, its trailing
#               comment never stripped, and healthy code REFUSED.
#        TWO further survivors were measured EQUIVALENT rather than dangerous
#        and are deliberately given NO fixture: narrowing the loop bound to
#        `i < n`, and cutting at `i` instead of `i - 1`. Fuzzed over 219,607
#        inputs, EVERY divergence either one produces is exactly one retained
#        trailing `#` -- a character carrying no token the scanner keys on --
#        so neither can move a verdict. Stated as a MEASURED SAMPLE over that
#        corpus, NOT as a proof of equivalence for all inputs (§11.4.6): if a
#        later shape ever makes a bare trailing `#` load-bearing, both become
#        real doors and need fixtures.
#   L50-L63 the round after THAT (round 15). An independent review measured
#        SIX more surviving mutations. All six were re-derived here BEFORE
#        being accepted -- each mutation applied, proven applied by an md5
#        delta, observed to SURVIVE the whole 117-assertion suite, and its
#        fixture measured to flip -- and all six held. L50-L54 close them:
#          L50  the arglist NESTING COUNTER  (text)  ast=1/text=1 -> text=0
#          L51  the INDENTED module import   (text)  -> text=0
#          L52  the PARENTHESISED from-spec  (text)  -> text=0
#          L53  WHITESPACE around the dot    (text)  -> text=0
#          L54  the STRING silent default -- TWO mutations, ONE fixture, one
#               per mode: the text scanner's quoted-constant branch
#               (-> text=0) and `is_trivial_literal`'s `str` arm (-> ast=0).
#        L54's AST half is the reason this round went further. Every door
#        found on this gate up to that point lived in the TEXT scanner; that
#        one is the first MEASURED door in the PRIMARY analyser, and under it
#        even `return ""` -- a value the function's own comment enumerates --
#        passed clean. Root cause of both halves, measured: `grep -c 'return
#        "'` over this file was ZERO. No fixture anywhere returned a string,
#        in either quote style, so the entire string arm of the silent-default
#        shape was unpinned in BOTH analysers simultaneously.
#
#        That single fact retired the working assumption that the AST path was
#        pinned by construction, so the AST path was then SWEPT: every
#        predicate it evaluates was enumerated and asked "which fixture would
#        notice if this branch stopped working?", and every predicate with no
#        such fixture was mutated and MEASURED against the full suite. NINE
#        more real doors were found this way and are closed by L55-L63:
#          L55  the EMPTY-CONTAINER return   (AST arm + text values)
#          L56  the EMPTY-DICT return        (a separate arm in both)
#          L57  the BARE `return`            (AST arm + text branch)
#          L58  the ELLIPSIS handler body    (AST arm + text half)
#          L59  the EXCEPT-GROUP node type   (AST only -- see boundary below)
#          L60  is_docstring's STRING-CONSTANT test   (false-positive dir.)
#          L61  the ONE-STATEMENT body requirement    (false-positive dir.)
#          L62  the dotted attribute as a WHOLE name  (false-positive dir.)
#          L63  the DOTTED exception ARGUMENT         (SILENT-MISS dir.)
#        L63 is the most serious of the nine: `suppress(builtins.Exception)`
#        is the flagship violation written with a qualified name, and the
#        blanked arm does not fall through to the `unresolved` branch either,
#        so the §11.4.201(4) conservative-safe refusal never fires and the
#        call is classified NARROW -- dropped with no trace at all.
#        The TEXT arms of L55-L58 were swept SEPARATELY and measured to flip
#        on their own mutations, so their text assertions are load-bearing
#        rather than free riders on the AST assertion.
#        Measured: the 18-mutation x fixture kill matrix is DIAGONAL with one
#        stated exception -- the text scanner holds `[]`, `{}` and `()` on a
#        SINGLE source line, so the one mutation that blanks it is killed by
#        L55 and L56 together. Neither fixture is thereby redundant: their
#        AST arms are separate mutations (`elts` vs `keys`) and each is killed
#        by its own fixture alone.
#
# ── UNMEASURED-BEYOND-THE-FIXTURES, as of round 15 (§11.4.6) ───────────────
# Stated so the next reader inherits the boundary instead of inferring a
# guarantee from silence. Round 13 swept the quote machine and did NOT sweep
# its callers or the AST path, but recorded that only in its hand-off; the
# artifact read as though the model had been swept whole. That gap is what
# L50-L54 fell through, so the boundary now lives HERE, in the file.
#
#   SWEPT AND MEASURED this round: every predicate in the AST analyser
#   (`is_docstring`, `is_trivial_literal` in all four arms, `classify` in all
#   four branches, `suppress_bindings` in all five, `is_suppress_call` in all
#   three, `classify_suppress` in all five, the node-type tuples, and the
#   walk's own guards) and the handler-body classification of the text
#   scanner. Twenty-two mutations in total; eighteen were real doors and are
#   closed above.
#
#   MEASURED AND DELIBERATELY NOT PINNED, with reasons:
#     * `except*` in the TEXT scanner. The shipped gate is ast=1/text=0 on an
#       except-group handler: the text pattern wants whitespace or a colon
#       straight after `except` and gets a star. A PRE-EXISTING gap in the
#       degraded fallback, inside its declared caveat, NOT introduced here.
#       L59 therefore carries an AST assertion only. Pinning the blindness
#       with an `expect_pass` would freeze it as correct and make a future
#       fix fail this harness. OWED WORK, not a closed item.
#     * `isinstance(func.value, ast.Name)` and the `isinstance(call, ast.Call)`
#       guard. Both mutations SURVIVED the suite, but measured on a fixture
#       that actually reaches them the analyser raises, the gate degrades to
#       the text scanner with its loud NOTE, and the verdict is PRESERVED.
#       They are defended by the §11.4.201 fail-safe degrade rather than by a
#       fixture. Recorded as such, NOT as pinned.
#
#   NOT SWEPT, and honestly so: the bash driver around both analysers (file
#   discovery, the exclude handling, argument parsing, the exit-code
#   arithmetic) and the non-Python language scanners. Sections 0-0c probe
#   this harness's OWN helpers; nothing below probes the driver. UNMEASURED,
#   not clean.
#
# Per §11.4.115(F) an invariant no fixture kills is unvalidated
# instrumentation, which is why each of these names the specific mutation it
# is there to kill.
#
# ── HONEST BOUNDARY: how far this harness pins ITSELF (§11.4.6) ─────────────
# There is deliberately NO meta-meta layer here, so this file's own helpers
# are only as trustworthy as the probes it carries for them. Every claim below
# was MEASURED by mutating the helper and re-running the whole suite -- not
# reasoned about -- because an unstated gap reads as an absent one, and a gap
# stated WITHOUT measurement is the same guess this file exists to forbid.
#
#   MESSAGE-PINNED ONLY, by self-probe (sections 0 and 0b). P4-P8 run each
#   helper in a SUBSHELL so its `rc=1` cannot leak into this suite's verdict
#   -- which means they assert what a helper PRINTS and nothing about whether
#   that print reaches the exit code. That gap was live: deleting the single
#   `rc=1` from `expect_fail`'s bluff branch SURVIVED all 83 assertions, and
#   against a gate blinded to the flagship shape the mutant printed four ❌
#   lines and still emitted `META_EXIT=0` with a `✅ META PASS` banner.
#   Section 0c (P9-P11) closes it by running the same helpers in the CURRENT
#   shell, in both directions. The list below is therefore split:
#     * `mkfixture`      P1/P2/P3 — a blinded collision guard silently
#                        reopened a false-kill channel once already.
#     * `expect_fail`    P4/P5/P6 — including the WRONG-ROUTE closure:
#                        relaxing `[ "$st" -eq 1 ]` to `-ne 0` re-admits the
#                        gate rc=2 environment/argument error as a "kill".
#                        Measured: SURVIVED the entire suite before P6; now
#                        killed by it.
#     * `expect_pass`    P7/P8 — made to fail open it silently disables EVERY
#                        negative control in this file, i.e. every
#                        §11.4.201(1) false-refusal guard, while the suite
#                        still prints all-green. Measured: SURVIVED before
#                        P8; now killed by it.
#   VERDICT-PINNED, by self-probe (section 0c) — the propagation half:
#     * `expect_fail`    P9  — deleting the `rc=1` from its bluff branch.
#                        Measured: SURVIVED all 83 before P9; killed by it.
#     * `expect_pass`    P10 — deleting the `rc=1` from its false-alarm
#                        branch. Measured: SURVIVED; killed by P10.
#     * `expect_output_contains`
#                        P11 — deleting the `rc=1` from its missing-needle
#                        branch. Measured: SURVIVED; killed by P11.
#                        Each probe asserts BOTH directions -- a bad outcome
#                        must raise `rc`, a good one must not -- so a mutant
#                        that hard-wires `rc=1` is refused by the same probe
#                        (§11.4.107(10) golden-bad + golden-good).
#   ARTIFACT-PINNED, by self-probe (section 0d) — the gate's own header:
#     * `--help` stderr  P12 — a backtick reaching `TEXT_MODE_CAVEAT` (a
#                        DOUBLE-quoted assignment) becomes command
#                        substitution: the words vanish from the runtime NOTE
#                        and `bash -n` stays clean. Measured: introduced
#                        accidentally this round, SURVIVED every fixture,
#                        killed by P12.
#     * `HEADER_LINES`   P13 — a header that grows without the constant being
#                        updated silently truncates `--help` mid-sentence.
#                        Measured: reverting it to its previous value
#                        SURVIVED every fixture; killed by P13.
#   PINNED, incidentally, by an existing assertion:
#     * `gate_textmode`  pointing it at a USABLE interpreter (which would turn
#                        every "degraded text-fallback mode" assertion into a
#                        second AST-mode run) is caught by the section-32
#                        announcement assertions, whose needles appear ONLY in
#                        degraded mode. Measured: 3 kills. This was expected
#                        to be a survivor and measurement refuted it -- which
#                        is why it is recorded as measured, not as reasoned.
#   NOT PINNED (measured survivors, both LATENT rather than live):
#     * `expect_output_contains` losing its `-F` flag, so the needle is read
#        as a REGEX. Survives. Harmless TODAY only because every needle in
#        this file is metacharacter-free; a future needle containing `.`,
#        `(` or `*` would silently start matching more than it names.
#     * `expect_output_contains` capturing stdout only (`2>/dev/null`).
#        Survives. Harmless TODAY only because the gate writes its NOTEs to
#        stdout; a NOTE moved to stderr would silently stop being assertable.
#     Both re-measured this round with the mutation verified APPLIED before
#     the run (the first attempt at the second one had its `sed` reject the
#     expression and reported the UNMUTATED run as a survival -- §11.4.201(7)
#     (c), the edit path is part of the instrument). Both still SURVIVE.
#     Both are left OPEN deliberately: neither can currently produce a wrong
#     verdict, and adding probes for them would only move the same question up
#     one level, since any probe is itself unpinned. Note that P12 probes
#     stderr for `--help` ONLY; a gate NOTE relocated to stderr would still
#     slip past `expect_output_contains`. They are recorded so the next reader
#     inherits the measurement instead of re-deriving it.
#
# The constitution does not mandate a third layer. The standing detection
# pressure for THIS file is §11.4.194(6)(d): a reviewer MUST attempt at least
# one mutation the author did not write. That is exactly how the two gate-side
# survivors of this round were found (the multi-token `continue`, and the
# SUFFIX half of the breadth word boundary), and how the two helper-side
# survivors above were found. Reviewers of this file should mutate the
# HELPERS, not only the gate.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_dangerous_combination_fail_closed_mutation_test.sh
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Creates + removes a temp fixture dir under $TMPDIR (trap-cleaned on EXIT).
#   No network, no commit, no mutation of the real tree.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, the sibling gate script. Parses clean under bash -n.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §1.1 (paired mutation), §11.4.252, §11.4.3 (clean fixture exercises the
#   SKIP-vs-PASS boundary), §11.4.28 (gate driven via env, no hardcoded paths).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — gate FAILs-on-mutation AND PASSes-on-clean for every fixture (the §1.1
#       proof holds).
#   1 — a fixture did not FAIL on its planted mutation, or did not PASS clean.
#   2 — environment error (the gate script missing).
#
# Classification: universal (§11.4.17).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE_SCRIPT="${SCRIPT_DIR}/cm_dangerous_combination_fail_closed.sh"

[ -f "$GATE_SCRIPT" ] || { echo "META: gate script missing: $GATE_SCRIPT" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dcfc_mut.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

rc=0
expect_fail() { # $1=desc  $2..=command
    # The kill MUST be rc=1 (the gate's FAIL verdict), never merely "non-zero".
    # rc=2 is the gate's ENVIRONMENT/ARGUMENT error (an absent --root, a
    # typo'd flag); accepting it lets a fixture reach the EXPECTED OUTCOME BY
    # THE WRONG ROUTE and report a kill the gate never made -- the same
    # wrong-route class `set -u` and `mkfixture` already close at two other
    # entrances (§11.4.201: assert the REAL condition, not a proxy that
    # something-which-is-not-it can satisfy).
    local desc="$1"; shift
    local out st
    out="$("$@" 2>&1)"; st=$?
    if [ "$st" -eq 1 ]; then
        echo "✅ META OK:   ${desc} — gate correctly FAILed on the mutation (rc=1)"
    elif [ "$st" -eq 0 ]; then
        echo "❌ META FAIL: ${desc} — gate PASSed on a planted violation (bluff gate!)"
        rc=1
    else
        echo "❌ META FAIL: ${desc} — gate exited ${st}, not the FAIL verdict rc=1; the expected outcome was reached by the WRONG ROUTE (rc=2 is an environment/argument error, not a detection)"
        rc=1
    fi
}
expect_pass() { # $1=desc  $2..=command
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        echo "✅ META OK:   ${desc} — gate correctly PASSed on clean fixture"
    else
        echo "❌ META FAIL: ${desc} — gate FAILed on a clean fixture (false alarm!)"
        rc=1
    fi
}
expect_output_contains() { # $1=desc  $2=needle  $3..=command
    local desc="$1" needle="$2"; shift 2
    local out
    # CAPTURE first, then match. Piping the command straight into grep would
    # measure the PIPELINE status under `set -o pipefail`, and this gate exits
    # non-zero whenever it finds a hit - so the assertion would read the gate's
    # VERDICT instead of grep's MATCH and fail on correct output
    # (§11.4.201(12): the pipeline exit status is part of the instrument).
    out="$("$@" 2>&1)" || true
    if printf '%s' "$out" | grep -qF -- "$needle"; then
        echo "✅ META OK:   ${desc} — expected marker present in gate output"
    else
        echo "❌ META FAIL: ${desc} — expected output to contain: ${needle}"
        rc=1
    fi
}

# Fixture-directory constructor. `mkdir -p` is SILENT when the directory
# already exists, so two sections reusing one variable name land two fixtures
# in ONE directory -- and every assertion there then measures the UNION,
# reporting a verdict its own file did not produce. That is not theoretical:
# a fixture added in this round reused an existing `MUT9`, and its
# expect_fail passed on the OTHER file's violation while the branch it
# claimed to pin was disabled (the mutant survived). Fixture isolation was
# ASSUMED; here it is ASSERTED (§11.4.201 -- a guard must check the real
# condition). Sections predating this helper still use bare `mkdir -p`; they
# are audited unique by construction (no duplicate MUT*/CLEAN* assignment),
# not retrofitted, which is stated rather than implied (§11.4.6).
mkfixture() { # $1=dir -> create it, or FAIL LOUDLY if it already exists
    if [ -e "$1" ]; then
        echo "❌ META FAIL: fixture dir collision — '$1' already exists; two sections share one fixture name, so their assertions measure the UNION"
        rc=1
        return 1
    fi
    mkdir -p "$1"
}

# Degraded (text-fallback) invocation: an EXPLICIT unusable interpreter pin is
# authoritative, so this exercises the real no-Python code path rather than
# simulating it.
gate_textmode() { DANGEROUS_COMBO_PYTHON=/nonexistent/python bash "$GATE_SCRIPT" "$@"; }

# ── 0. SELF-PROBE: the fixture-collision guard is itself ASSERTED ──────────
# `mkfixture` exists because a fixture-name collision silently made one
# section's expect_fail pass on ANOTHER file's violation. But the guard was
# shipped UNVALIDATED -- §11.4.115(F) instrumentation never observed doing its
# job. Measured: mutating its test `[ -e "$1" ]` -> `[ -f "$1" ]` (so a
# pre-existing DIRECTORY stops being detected -- exactly the MUT9 shape)
# SURVIVES all other assertions, and with the guard blinded the whole
# false-kill channel silently reopens. These three probes close that: the
# guard MUST fire on a colliding DIRECTORY (P1) and on a colliding FILE (P2),
# and MUST NOT fire on a fresh path (P3, the §11.4.201(1) false-positive
# control, which additionally proves the constructor really constructs).
# Each probe runs `mkfixture` in a SUBSHELL so its internal `rc=1` cannot
# leak into this suite's own verdict.
_probe_dir="$TMP/_mkfixture_probe_dir"
mkdir -p "$_probe_dir"
if ( mkfixture "$_probe_dir" ) >/dev/null 2>&1; then
    echo "❌ META FAIL: mkfixture self-probe P1 — the collision guard did NOT fire on a pre-existing DIRECTORY (the exact MUT9 shape); fixture isolation is unasserted"
    rc=1
else
    echo "✅ META OK:   mkfixture self-probe P1 — collision guard fires on a pre-existing DIRECTORY"
fi
_probe_file="$TMP/_mkfixture_probe_file"
: > "$_probe_file"
if ( mkfixture "$_probe_file" ) >/dev/null 2>&1; then
    echo "❌ META FAIL: mkfixture self-probe P2 — the collision guard did NOT fire on a pre-existing FILE"
    rc=1
else
    echo "✅ META OK:   mkfixture self-probe P2 — collision guard fires on a pre-existing FILE"
fi
_probe_fresh="$TMP/_mkfixture_probe_fresh"
if ( mkfixture "$_probe_fresh" ) >/dev/null 2>&1 && [ -d "$_probe_fresh" ]; then
    echo "✅ META OK:   mkfixture self-probe P3 (negative control) — a FRESH path is created, not refused"
else
    echo "❌ META FAIL: mkfixture self-probe P3 — mkfixture refused a fresh path, or failed to create it (a §11.4.201(1) false-positive guard, or a broken constructor)"
    rc=1
fi

# ── 0b. SELF-PROBE: the VERDICT helpers are themselves ASSERTED ────────────
# Section 0 pins `mkfixture` because a blinded collision guard silently
# reopened a false-kill channel. The verdict helpers had the same standing:
# shipped, load-bearing, and never observed doing their job. Measured, each
# of these SURVIVED the whole suite before these probes existed --
#   * `expect_fail`: `[ "$st" -eq 1 ]` -> `-ne 0` re-admits the gate rc=2
#     ENVIRONMENT/ARGUMENT error as a "kill", so a fixture reaches the
#     expected outcome by the WRONG ROUTE and reports a detection the gate
#     never made (the exact closure this helper exists to hold);
#   * `expect_pass`: made to fail open, it silently disables EVERY negative
#     control in this file at once -- i.e. every §11.4.201(1) false-refusal
#     guard -- while the suite still prints all-green.
# Both are now killed here. Each probe runs its helper in a SUBSHELL so the
# helper own `rc=1` cannot leak into this suite verdict, and asserts on the
# emitted VERDICT LINE rather than on an exit status the helper does not set.
_probe_helper() { ( "$@" ) 2>&1; }

_p="$(_probe_helper expect_fail "self-probe" bash -c 'exit 1')"
case "$_p" in
    *"META OK"*) echo "✅ META OK:   expect_fail self-probe P4 — a genuine rc=1 FAIL verdict is accepted" ;;
    *) echo "❌ META FAIL: expect_fail self-probe P4 — a genuine rc=1 FAIL verdict was NOT accepted"; rc=1 ;;
esac
_p="$(_probe_helper expect_fail "self-probe" bash -c 'exit 0')"
case "$_p" in
    *"META FAIL"*) echo "✅ META OK:   expect_fail self-probe P5 — a PASSing gate on a planted violation is rejected" ;;
    *) echo "❌ META FAIL: expect_fail self-probe P5 — a PASSing gate on a planted violation was ACCEPTED as a kill"; rc=1 ;;
esac
_p="$(_probe_helper expect_fail "self-probe" bash -c 'exit 2')"
case "$_p" in
    *"WRONG ROUTE"*) echo "✅ META OK:   expect_fail self-probe P6 — rc=2 (environment/argument error) is rejected as a WRONG-ROUTE kill" ;;
    *) echo "❌ META FAIL: expect_fail self-probe P6 — rc=2 was accepted as a kill; the wrong-route closure is blinded"; rc=1 ;;
esac
_p="$(_probe_helper expect_pass "self-probe" bash -c 'exit 0')"
case "$_p" in
    *"META OK"*) echo "✅ META OK:   expect_pass self-probe P7 (negative control) — a clean rc=0 run is accepted" ;;
    *) echo "❌ META FAIL: expect_pass self-probe P7 — a clean rc=0 run was refused; expect_pass is a false-positive guard"; rc=1 ;;
esac
_p="$(_probe_helper expect_pass "self-probe" bash -c 'exit 1')"
case "$_p" in
    *"META FAIL"*) echo "✅ META OK:   expect_pass self-probe P8 — a gate FAILing a clean fixture is reported, not swallowed" ;;
    *) echo "❌ META FAIL: expect_pass self-probe P8 — expect_pass FAILS OPEN; every negative control in this file is silently disabled"; rc=1 ;;
esac

# ── 0c. SELF-PROBE: the helpers' VERDICT PROPAGATION, not only their text ──
# P4-P8 above run each helper in a SUBSHELL -- deliberately, so a probe's own
# `rc=1` cannot leak into this suite's verdict -- which means they pin only
# what a helper PRINTS. The propagation from "printed ❌" to "this file exits
# 1" was pinned by NOTHING. Measured: deleting the single `rc=1` from
# `expect_fail`'s gate-PASSed-on-a-planted-violation branch SURVIVED the
# whole suite, and against a gate blinded to the flagship `except: pass`
# shape that mutant printed four ❌ lines and still emitted `META_EXIT=0`,
# exit 0 and the closing `✅ META PASS` banner -- a self-contradicting
# transcript whose EXIT CODE is this file's one load-bearing contract
# (§11.4.201(11): the artifact is probed through its real invocation path,
# and "[ok] verified" beside "[FAILED]" in one transcript is the shape that
# closure exists to refuse). Deleting `expect_pass`'s `rc=1` survived
# identically.
#
# These probes therefore run the helpers IN THE CURRENT SHELL, where `rc`
# actually lives, with output discarded (a redirection on a function call
# does not fork). Each helper is probed in BOTH directions -- a bad outcome
# MUST raise `rc`, a good outcome MUST NOT -- so a mutant that hard-wires
# `rc=1` is refused by the same probe that catches one deleting it
# (§11.4.107(10): golden-bad and golden-good, and §11.4.201(1): the
# false-positive direction is a defect too). `_probe_rc` is a plain literal
# assignment, never a call to the helpers being measured.
_probe_verdict() { # $1=label  $2=rc-after-bad  $3=rc-after-good  $4=detail
    if [ "$2" -eq 1 ] && [ "$3" -eq 0 ]; then
        echo "✅ META OK:   ${1} verdict-propagation probe — a ❌ verdict RAISES rc, a ✅ verdict does not"
    else
        echo "❌ META FAIL: ${1} verdict-propagation probe — rc-after-bad=${2} (want 1), rc-after-good=${3} (want 0); ${4}"
        rc=1
    fi
}

# `rc` is the scratch register here AND this file's verdict, so each pair
# SAVES it and RESTORES it rather than resetting to 0. Measured: with a bare
# `rc=0` reset between pairs, P10's setup silently WIPED a P9 failure -- the
# probe printed its ❌ diagnosis and the suite still exited 0, which is the
# very defect P9 exists to catch, reproduced inside the probe for it
# (§11.4.201(7)(c): the instrument is part of the measurement).
_pv_saved=$rc
rc=0; expect_fail "propagation probe" bash -c 'exit 0' >/dev/null 2>&1; _bad=$rc
rc=0; expect_fail "propagation probe" bash -c 'exit 1' >/dev/null 2>&1; _good=$rc
rc=$_pv_saved
_probe_verdict "P9  expect_fail" "$_bad" "$_good" \
    "a gate PASSing a planted violation would be PRINTED as a bluff and still exit 0"

_pv_saved=$rc
rc=0; expect_pass "propagation probe" bash -c 'exit 1' >/dev/null 2>&1; _bad=$rc
rc=0; expect_pass "propagation probe" bash -c 'exit 0' >/dev/null 2>&1; _good=$rc
rc=$_pv_saved
_probe_verdict "P10 expect_pass" "$_bad" "$_good" \
    "every negative control in this file would print its false alarm and still exit 0"

_pv_saved=$rc
rc=0; expect_output_contains "propagation probe" "__ABSENT_NEEDLE__" bash -c 'exit 0' >/dev/null 2>&1; _bad=$rc
rc=0; expect_output_contains "propagation probe" "__PRESENT_NEEDLE__" bash -c 'echo __PRESENT_NEEDLE__' >/dev/null 2>&1; _good=$rc
rc=$_pv_saved
_probe_verdict "P11 expect_output_contains" "$_bad" "$_good" \
    "a missing output marker would be PRINTED as absent and still exit 0"

# ── 0d. SELF-PROBE: --help is CLEAN on stderr, and HEADER_LINES is honest ──
# The gate's long header is its user manual and its per-class enumeration, so
# it is edited every round -- and two of its containers EVALUATE what is
# written into them. Both bit this round, in opposite directions:
#   * the awk program is a SINGLE-quoted shell string, so one apostrophe in a
#     new comment TERMINATES it -> a bash PARSE ERROR (loud, caught at once);
#   * `TEXT_MODE_CAVEAT` is a DOUBLE-quoted assignment, so backticks in a new
#     sentence became COMMAND SUBSTITUTION -> `except: command not found` on
#     stderr and the backticked words SILENTLY DELETED from the runtime NOTE,
#     while `bash -n` stayed clean and every fixture kept passing. That is the
#     quiet direction, and nothing here would have caught it.
# P12 probes the artifact through its REAL invocation path (§11.4.201(11)):
# `--help` must print the header on stdout and write NOTHING to stderr. P13
# asserts HEADER_LINES is not merely non-empty but ACCURATE -- that the last
# header line really is the last comment line before the code, so a header
# that grows without the constant being updated is caught rather than
# silently truncating the manual. The check is deliberately the STRICTER of
# the two readings: it requires line HEADER_LINES to be a comment AND the
# line after it to be EMPTY (line 495 is blank -- verified with `cat -A`),
# not merely non-comment. Should a legitimate non-empty, non-comment line
# ever land there, P13 would FAIL on an accurate constant -- a §11.4.201(1)
# false-alarm direction, currently unreachable and stated rather than left
# for a future reader to discover. The message below names the condition the
# pattern actually tests, so the two can no longer drift apart.
_help_err="$(bash "$GATE_SCRIPT" --help 2>&1 >/dev/null)"
if [ -z "$_help_err" ]; then
    echo "✅ META OK:   P12 --help writes NOTHING to stderr — no shell evaluation leaked out of the header containers"
else
    echo "❌ META FAIL: P12 --help wrote to stderr — a header edit is being EVALUATED (backtick/\$() inside a double-quoted string, or similar): ${_help_err}"
    rc=1
fi

_hl="$(sed -n 's/^HEADER_LINES=\([0-9][0-9]*\)$/\1/p' "$GATE_SCRIPT" | head -1)"
_at_hl="$(sed -n "${_hl}p" "$GATE_SCRIPT")"
_after_hl="$(sed -n "$(( _hl + 1 ))p" "$GATE_SCRIPT")"
case "${_at_hl}|${_after_hl}" in
    '#'*'|') echo "✅ META OK:   P13 HEADER_LINES=${_hl} is ACCURATE — it names a comment line and the line after it is EMPTY (the exact condition the case pattern tests)" ;;
    *) echo "❌ META FAIL: P13 HEADER_LINES=${_hl} is STALE — line ${_hl} is '${_at_hl}' and line $(( _hl + 1 )) is '${_after_hl}'; --help is truncating or over-running the header"; rc=1 ;;
esac

echo "======================================================================"
echo "§1.1 paired-mutation meta-test for CM-DANGEROUS-COMBINATION-FAIL-CLOSED"
echo "fixtures under: $TMP"
echo "======================================================================"

# ── 1. MUTATED: Python bare 'except: pass' (swallowed exception) ───────────
MUT1="$TMP/mut1"
mkdir -p "$MUT1"
cat > "$MUT1/handler.py" <<'PY'
def delete_record(record_id):
    try:
        db.delete(record_id)
    except:
        pass
    return True
PY
expect_fail "Python bare 'except: pass' swallowed exception" \
    bash "$GATE_SCRIPT" --root "$MUT1" --quiet

# ── 2. CLEAN: Python except with logging + re-raise ─────────────────────────
CLEAN1="$TMP/clean1"
mkdir -p "$CLEAN1"
cat > "$CLEAN1/handler.py" <<'PY'
def delete_record(record_id):
    try:
        db.delete(record_id)
    except DatabaseError as e:
        logger.error("delete failed for %s: %s", record_id, e)
        raise
    return True
PY
expect_pass "Python except with logging + re-raise (legitimate)" \
    bash "$GATE_SCRIPT" --root "$CLEAN1" --quiet

# ── 3. MUTATED: JS empty catch block (swallowed exception) ──────────────────
MUT2="$TMP/mut2"
mkdir -p "$MUT2"
cat > "$MUT2/handler.js" <<'JS'
function deleteRecord(recordId) {
    try {
        db.delete(recordId);
    } catch (err) {
    }
    return true;
}
JS
expect_fail "JS empty catch block (swallowed exception)" \
    bash "$GATE_SCRIPT" --root "$MUT2" --quiet

# ── 4. CLEAN: JS catch with real handling ────────────────────────────────────
CLEAN2="$TMP/clean2"
mkdir -p "$CLEAN2"
cat > "$CLEAN2/handler.js" <<'JS'
function deleteRecord(recordId) {
    try {
        db.delete(recordId);
    } catch (err) {
        logger.error("delete failed", err);
        throw err;
    }
    return true;
}
JS
expect_pass "JS catch with real handling (legitimate)" \
    bash "$GATE_SCRIPT" --root "$CLEAN2" --quiet

# ── 5. MUTATED: credential silently defaulted to a literal string ───────────
MUT3="$TMP/mut3"
mkdir -p "$MUT3"
cat > "$MUT3/config.py" <<'PY'
def get_api_key():
    api_key = loaded_value or "sk-hardcoded-fallback-secret"
    return api_key
PY
expect_fail "credential (api_key) silently defaulted to a literal string" \
    bash "$GATE_SCRIPT" --root "$MUT3" --quiet

# ── 6. CLEAN: credential fallback to env var (legitimate secondary source) ──
CLEAN3="$TMP/clean3"
mkdir -p "$CLEAN3"
cat > "$CLEAN3/config.py" <<'PY'
def get_api_key():
    api_key = loaded_value or os.environ.get("API_KEY")
    return api_key
PY
expect_pass "credential fallback to env var (legitimate secondary source)" \
    bash "$GATE_SCRIPT" --root "$CLEAN3" --quiet

# ── 7. NEGATIVE CONTROL: no candidate source files at all -> honest SKIP ────
CLEAN4="$TMP/clean4"
mkdir -p "$CLEAN4"
echo "just documentation text, no source files" > "$CLEAN4/README.md"
expect_pass "no candidate source files present — honest SKIP (exit 0), never a fake FAIL" \
    bash "$GATE_SCRIPT" --root "$CLEAN4" --quiet

# ── 8. MUTATED (L1): trailing comment on the handler line ───────────────────
# The pre-fix regex anchored the handler line with `:[[:space:]]*$`, so a
# reviewed-and-annotated handler was exactly the one it could not see.
MUT4="$TMP/mut4"
mkdir -p "$MUT4"
cat > "$MUT4/l1.py" <<'PY'
def purge(path):
    try:
        shutil.rmtree(path)
    except Exception:  # noqa: S110 - best effort
        pass
PY
expect_fail "L1 swallowed exception with a TRAILING COMMENT on the handler line" \
    bash "$GATE_SCRIPT" --root "$MUT4" --quiet
expect_fail "L1 (degraded text-fallback mode)" \
    gate_textmode --root "$MUT4" --quiet

# ── 9. MUTATED (L2): tuple exception clause ─────────────────────────────────
# The pre-fix exception-type group was `[A-Za-z_.]+`, which cannot match `(`.
MUT5="$TMP/mut5"
mkdir -p "$MUT5"
cat > "$MUT5/l2.py" <<'PY'
def purge(path):
    try:
        shutil.rmtree(path)
    except (OSError, ValueError):
        pass
PY
expect_fail "L2 swallowed exception with a TUPLE exception clause" \
    bash "$GATE_SCRIPT" --root "$MUT5" --quiet
expect_fail "L2 (degraded text-fallback mode)" \
    gate_textmode --root "$MUT5" --quiet

# ── 10. MUTATED (L3): a comment between `except` and `pass` ─────────────────
# The pre-fix body check read exactly lineno+1, so a reviewer ADDING an
# explanatory comment inside the handler deleted the site from the report.
MUT6="$TMP/mut6"
mkdir -p "$MUT6"
cat > "$MUT6/l3.py" <<'PY'
def purge(path):
    try:
        shutil.rmtree(path)
    except Exception:
        # best effort - the directory may already be gone
        pass
PY
expect_fail "L3 swallowed exception with a COMMENT between except and pass" \
    bash "$GATE_SCRIPT" --root "$MUT6" --quiet
expect_fail "L3 (degraded text-fallback mode)" \
    gate_textmode --root "$MUT6" --quiet

# ── 11. MUTATED (L4): silent default return ─────────────────────────────────
# Handing the caller a plausible-looking value that carries zero information
# about the failure is the same fail-open defect as `pass` - arguably worse,
# because the caller cannot tell the operation failed.
MUT7="$TMP/mut7"
mkdir -p "$MUT7"
cat > "$MUT7/l4.py" <<'PY'
def fetch_balance(account_id):
    try:
        return ledger.balance(account_id)
    except Exception:
        return 0
PY
expect_fail "L4 silent default return (except -> return <trivial literal>)" \
    bash "$GATE_SCRIPT" --root "$MUT7" --quiet
expect_fail "L4 (degraded text-fallback mode)" \
    gate_textmode --root "$MUT7" --quiet

# ── 12. NEGATIVE CONTROL (L5): a CARRIER that only MENTIONS the pattern ─────
# A style guide documenting the anti-pattern, and a string constant holding a
# forbidden snippet. The pre-fix text scanner FIRED on both (a §11.4.201(1)
# FAIL-bluff: it refused healthy code). A parser cannot: a string literal is
# not a Try node and a comment is not a statement.
CLEAN5="$TMP/clean5"
mkdir -p "$CLEAN5"
cat > "$CLEAN5/carrier.py" <<'PY'
"""Style guide for this project.

Never write a swallowed handler like this:

    except Exception:
        pass

Always log and re-raise instead.
"""

FORBIDDEN_SNIPPET = """
except Exception:
    pass
"""


def safe_delete(record_id):
    try:
        db.delete(record_id)
    except OSError as exc:
        logger.error("delete failed for %s: %s", record_id, exc)
        raise
PY
expect_pass "L5 CARRIER negative control — docstring/string merely MENTIONING the pattern must NOT fire" \
    bash "$GATE_SCRIPT" --root "$CLEAN5" --quiet

# ── 13. NEGATIVE CONTROL: handlers that do REAL fallback work ──────────────
# Guards the new silent-default-return class against over-reach: a handler
# that logs, or returns a COMPUTED value, or runs an alternate strategy, is
# fallback handling - not a silent default - and must NOT be flagged.
CLEAN6="$TMP/clean6"
mkdir -p "$CLEAN6"
cat > "$CLEAN6/fallback.py" <<'PY'
def parse_primary(blob):
    try:
        return primary_parser(blob)
    except ParseError as exc:
        logger.warning("primary parser failed: %s", exc)
        return fallback_parser(blob)


def load_config(path):
    try:
        return json.loads(read(path))
    except FileNotFoundError:
        return build_default_config(path)


def read_rows(cursor):
    try:
        return cursor.fetchall()
    except TransientError:
        cursor.reconnect()
        return cursor.fetchall()
PY
expect_pass "handlers doing REAL fallback work (log+delegate / computed default / retry) must NOT fire" \
    bash "$GATE_SCRIPT" --root "$CLEAN6" --quiet

# ── 14. MUTATED (L6): contextlib.suppress over a BROAD exception class ──────
# THE SIM105 COVERAGE-SHRINK CHANNEL, and the reason this class exists.
# `contextlib.suppress` is a `With` node, NOT a `Try` node, so a gate that
# walks only Try handlers is structurally blind to it. That blindness is not a
# neutral gap wherever a linter enables ruff's SIM rules: SIM105 says
# "use contextlib.suppress instead of try-except-pass" — so every autofix
# rewrites a shape the gate CAN see into one it CANNOT. Coverage shrinks while
# the lint count falls, which reads as progress. Semantically
# `with suppress(Exception): X` IS `try: X / except Exception: pass`.
MUT8="$TMP/mut8"
mkdir -p "$MUT8"
cat > "$MUT8/l6.py" <<'PY'
import contextlib
import os


def purge(user_supplied_path):
    with contextlib.suppress(Exception):
        os.unlink(user_supplied_path)
PY
expect_fail "L6 contextlib.suppress(Exception) — swallow-everything via a With node" \
    bash "$GATE_SCRIPT" --root "$MUT8" --quiet
expect_fail "L6 (degraded text-fallback mode)" \
    gate_textmode --root "$MUT8" --quiet

# ── 15. MUTATED (L7): `from contextlib import suppress` (bare name binding) ─
# Same node shape, different name binding. A gate that only matched the
# dotted `contextlib.suppress` attribute form would be blind to the bare form.
MUT9="$TMP/mut9"
mkdir -p "$MUT9"
cat > "$MUT9/l7.py" <<'PY'
import os
from contextlib import suppress


def purge(user_supplied_path):
    with suppress(Exception):
        os.unlink(user_supplied_path)
PY
expect_fail "L7 bare suppress(Exception) via 'from contextlib import suppress'" \
    bash "$GATE_SCRIPT" --root "$MUT9" --quiet
expect_fail "L7 (degraded text-fallback mode)" \
    gate_textmode --root "$MUT9" --quiet

# ── 16. MUTATED (L8): module alias + BaseException + `async with` ───────────
# `import contextlib as ctx` rebinds the module, `BaseException` is the even
# broader swallow class, and an `async with` is an AsyncWith node — a distinct
# AST type that a With-only visitor would still miss.
MUT10="$TMP/mut10"
mkdir -p "$MUT10"
cat > "$MUT10/l8.py" <<'PY'
import contextlib as ctx
import os


async def purge(user_supplied_path):
    async with ctx.suppress(BaseException):
        os.unlink(user_supplied_path)
PY
expect_fail "L8 aliased module + BaseException + async with (AsyncWith node)" \
    bash "$GATE_SCRIPT" --root "$MUT10" --quiet
# The degraded pair is NOT redundant. Text mode detects the async form via its
# own `(async[ \t]+)?` alternation in the with-line regex, and that alternation
# is pinned by NOTHING else: deleting it leaves every other fixture in this
# suite green (they all use a plain `with`) while this file flips from detected
# to invisible -- a silent floor reduction in the mode that is already only a
# floor. Discriminator: this assertion flips exit 1 -> 0 under that deletion.
expect_fail "L8 (degraded text-fallback mode — pins the async-with alternation in the text regex)" \
    gate_textmode --root "$MUT10" --quiet

# ── 17. MUTATED (L9): `from contextlib import suppress as <alias>` ──────────
MUT11="$TMP/mut11"
mkdir -p "$MUT11"
cat > "$MUT11/l9.py" <<'PY'
import os
from contextlib import suppress as quiet


def purge(user_supplied_path):
    with quiet(Exception):
        os.unlink(user_supplied_path)
PY
expect_fail "L9 aliased import 'from contextlib import suppress as quiet'" \
    bash "$GATE_SCRIPT" --root "$MUT11" --quiet

# ── 18. MUTATED (L10): multi-item `with` — suppress is not the first item ───
# `with open(p) as fh, suppress(Exception):` puts the swallow in items[1]; a
# visitor that only inspected items[0] would be blind to it.
MUT12="$TMP/mut12"
mkdir -p "$MUT12"
cat > "$MUT12/l10.py" <<'PY'
import os
from contextlib import suppress


def purge(user_supplied_path, log_path):
    with open(log_path) as fh, suppress(Exception):
        os.unlink(user_supplied_path)
        fh.close()
PY
expect_fail "L10 suppress(Exception) as a NON-FIRST item of a multi-item with" \
    bash "$GATE_SCRIPT" --root "$MUT12" --quiet

# ── 19. NEGATIVE CONTROL (L11): NARROW suppress around a non-dangerous call ─
# THE REQUIRED GOLDEN-FALSE. `with suppress(FileNotFoundError): ...` is a
# DECLARED, BOUNDED tolerance: the developer named exactly the one failure
# they accept and every other exception still propagates (verified
# empirically, not assumed). Firing on it would be a §11.4.201(1)
# FALSE-POSITIVE REFUSAL — a FAIL-bluff of equal severity to missing a real
# violation. `suppress()` with NO arguments is included because it suppresses
# NOTHING at all (issubclass(exc, ()) is always False) and is likewise a
# non-violation.
CLEAN7="$TMP/clean7"
mkdir -p "$CLEAN7"
cat > "$CLEAN7/narrow.py" <<'PY'
import contextlib
from contextlib import suppress


def read_optional(path):
    value = None
    with contextlib.suppress(FileNotFoundError):
        value = open(path).read()
    return value


def parse_optional(raw):
    parsed = None
    with suppress(ValueError, KeyError):
        parsed = int(raw["count"])
    return parsed


def no_op(payload):
    with contextlib.suppress():
        payload.refresh()
PY
expect_pass "L11 NEGATIVE CONTROL — NARROW suppress(SpecificError) around a non-dangerous call must NOT fire" \
    bash "$GATE_SCRIPT" --root "$CLEAN7" --quiet
expect_pass "L11 (degraded text-fallback mode)" \
    gate_textmode --root "$CLEAN7" --quiet

# ── 20. NEGATIVE CONTROL (L12): a project-local `suppress` that is NOT ──────
# contextlib's. Matching the bare NAME `suppress` would fire here; resolving
# the IMPORT BINDING does not (§11.4.201(7)(a) — match structure, not
# substring). Asserted in BOTH modes so the degraded path is not a
# false-positive engine either.
CLEAN8="$TMP/clean8"
mkdir -p "$CLEAN8"
cat > "$CLEAN8/local_suppress.py" <<'PY'
def suppress(kind):
    """A project-local warning filter. Nothing to do with contextlib."""
    return _WarningFilter(kind)


def render(page):
    with suppress(Exception):
        page.emit()
PY
expect_pass "L12 NEGATIVE CONTROL — a project-LOCAL suppress() (not contextlib's) must NOT fire" \
    bash "$GATE_SCRIPT" --root "$CLEAN8" --quiet
expect_pass "L12 (degraded text-fallback mode)" \
    gate_textmode --root "$CLEAN8" --quiet

# ── 21. NEGATIVE CONTROL (L13): a CARRIER that only MENTIONS the new shape ──
# The §11.4.201(1) guard for the new class: a docstring or string constant
# documenting the suppress anti-pattern is not code and must stay silent.
CLEAN9="$TMP/clean9"
mkdir -p "$CLEAN9"
cat > "$CLEAN9/carrier_suppress.py" <<'PY'
"""Style guide.

Never swallow everything like this:

    with contextlib.suppress(Exception):
        os.unlink(path)

Name the exact exception you tolerate instead.
"""

FORBIDDEN = "with contextlib.suppress(Exception): os.unlink(path)"


def purge(path):
    import contextlib
    with contextlib.suppress(FileNotFoundError):
        os.unlink(path)
PY
expect_pass "L13 CARRIER negative control — docstring/string MENTIONING contextlib.suppress(Exception) must NOT fire" \
    bash "$GATE_SCRIPT" --root "$CLEAN9" --quiet

# ── 22. NEGATIVE CONTROL (L14): project-local `suppress` in a file that ─────
# ALSO imports contextlib for an unrelated reason. THE BINDING CHECK ITSELF.
# L12 cannot pin this: that file has no contextlib import at all, so the
# outer "does this module import contextlib?" guard already skips it and the
# PER-NAME binding check is never exercised. A mutation that ADDS bare-name
# acceptance (`func.id in direct_names or func.id == "suppress"`) therefore
# survives L12 untouched while false-positiving here — proven by running that
# exact mutant against this fixture. This is the fixture that pins the
# header's advertised property: detection is by IMPORT BINDING, not by NAME.
CLEAN10="$TMP/clean10"
mkdir -p "$CLEAN10"
cat > "$CLEAN10/local_plus_import.py" <<'PY'
import contextlib  # used below for ExitStack, NOT for suppress
import json


def suppress(kind):
    """Project-local warning filter. Nothing to do with contextlib."""
    return _WarningFilter(kind)


def render(page):
    with suppress(Exception):
        page.emit()


def load(path):
    with contextlib.ExitStack() as stack:
        fh = stack.enter_context(open(path))
        return json.load(fh)
PY
expect_pass "L14 NEGATIVE CONTROL — project-local suppress() beside an UNRELATED 'import contextlib' must NOT fire (binding, not name)" \
    bash "$GATE_SCRIPT" --root "$CLEAN10" --quiet
expect_pass "L14 (degraded text-fallback mode)" \
    gate_textmode --root "$CLEAN10" --quiet

# ── 23. NEGATIVE CONTROL (L15): a project exception class whose NAME merely ─
# ENDS IN "Exception". The breadth test must be a WORD-BOUNDARY match:
# `MyException` is a narrow, declared tolerance and is NOT `Exception`.
# Asserted in TEXT mode because that is where the boundary is a regex and a
# mutation weakening it to a bare /Exception/ substring survives every other
# fixture in this suite.
CLEAN11="$TMP/clean11"
mkdir -p "$CLEAN11"
cat > "$CLEAN11/custom_exc.py" <<'PY'
import contextlib
from contextlib import suppress


class MyException(Exception):
    pass


class TransportBaseException(Exception):
    pass


def render(page):
    with contextlib.suppress(MyException):
        page.emit()


def flush(sink):
    with suppress(TransportBaseException):
        sink.flush()
PY
expect_pass "L15 NEGATIVE CONTROL — suppress(MyException) / suppress(TransportBaseException) are NARROW; word-boundary breadth match" \
    bash "$GATE_SCRIPT" --root "$CLEAN11" --quiet
expect_pass "L15 (degraded text-fallback mode — where the boundary is a regex)" \
    gate_textmode --root "$CLEAN11" --quiet

# ── 24. MUTATED (L16): an UNRESOLVABLE argument list -> conservative-safe ──
# THE §11.4.201(4) BRANCH. The gate SHIPS a dedicated FAIL message for a
# suppress() whose exception list cannot be resolved statically, and until
# this fixture existed NOTHING exercised it. A mutant that makes
# classify_suppress() return None instead of "unresolved" -- i.e. deletes the
# conservative-safe refusal and silently FAILS OPEN on an ambiguous signal,
# the exact defect §11.4.252 forbids -- survived the entire suite. That is
# §11.4.115(F) unvalidated instrumentation: a branch shipped with an
# advertised message that was never once observed doing its job.
# Discriminator: this fixture flips exit 1 -> 0 under that mutant.
#
# STRUCTURAL MODE ONLY, deliberately: `*EXCS` carries no `Exception` token on
# the `with` line, so the TEXT floor cannot see it. That is recorded in the
# gate header's MEASURED degraded-mode gap list rather than papered over --
# the same honest treatment L9's aliased import already gets. L17 below
# carries the text-mode pair for the unresolvable family.
MUT13="$TMP/mut13"
mkdir -p "$MUT13"
cat > "$MUT13/l16.py" <<'PY'
import contextlib
import os

EXCS = (Exception,)


def purge(user_supplied_path):
    with contextlib.suppress(*EXCS):
        os.unlink(user_supplied_path)
PY
expect_fail "L16 UNRESOLVABLE suppress(*EXCS) — conservative-safe refusal (§11.4.201(4))" \
    bash "$GATE_SCRIPT" --root "$MUT13" --quiet
# ...and it must refuse for the RIGHT REASON. A verdict-only assertion cannot
# tell the conservative-safe path from a lucky misclassification: a mutant that
# routed the unresolved case into the "broad" message would still exit non-zero
# and survive. This pins the advertised §11.4.201(4) message itself.
expect_output_contains "L16 refusal names the UNRESOLVED signal rather than guessing breadth" \
    "could not be resolved statically" \
    bash "$GATE_SCRIPT" --root "$MUT13" --quiet

# ── 25. MUTATED (L17): a COMPUTED exception argument ───────────────────────
# The second unresolvable shape, and the one that DOES have a degraded pair.
# `RuntimeError if strict else Exception` is an IfExp: the analyser resolves no
# Name and takes the same §11.4.201(4) conservative-safe path as L16, so this
# kills the same mutant independently. The TEXT floor also refuses -- but for a
# DIFFERENT reason: the literal `Exception` token sits on the `with` line, so
# its breadth-by-name regex matches. The descriptions below say so explicitly;
# claiming text mode understands unresolvability would be a §11.4.6 overstatement.
MUT14="$TMP/mut14"
mkdir -p "$MUT14"
cat > "$MUT14/l17.py" <<'PY'
import contextlib
import os


def purge(user_supplied_path, strict):
    with contextlib.suppress(RuntimeError if strict else Exception):
        os.unlink(user_supplied_path)
PY
expect_fail "L17 COMPUTED suppress(IfExp) — unresolvable, conservative-safe refusal" \
    bash "$GATE_SCRIPT" --root "$MUT14" --quiet
expect_fail "L17 (degraded text-fallback mode — fires on the breadth token, NOT on unresolvability)" \
    gate_textmode --root "$MUT14" --quiet

# ── 26. NEGATIVE CONTROL (L18): a DOTTED suppress whose prefix is NOT ──────
# contextlib, in a file that imports contextlib for an unrelated reason.
# THE DOTTED-SIDE BINDING CHECK, and the exact sibling of L14 -- which pins
# "binding, not name" for the BARE-name branch ONLY. Nothing pinned the dotted
# branch: a mutant replacing its binding test (`func.value.id in
# module_aliases`) with a plain `return True` is invisible to every other
# fixture here, and ships a §11.4.201(1) false-POSITIVE engine that refuses
# this healthy file. Discriminator: this fixture flips exit 0 -> 1 under it.
#
# Asserted in BOTH modes because the SAME divergence existed in the text
# floor, and was found by this fixture: it licensed every dotted
# `<anything>.suppress(` on the mere PRESENCE of a contextlib import, so it
# refused this file until the prefix-NAME binding landed with this fixture.
CLEAN12="$TMP/clean12"
mkdir -p "$CLEAN12"
cat > "$CLEAN12/dotted_local.py" <<'PY'
import contextlib  # used below for ExitStack, NOT for suppress
import json

import othermod  # a project module that ships its own suppress()


def render(page):
    with othermod.suppress(Exception):
        page.emit()


def load(path):
    with contextlib.ExitStack() as stack:
        fh = stack.enter_context(open(path))
        return json.load(fh)
PY
expect_pass "L18 NEGATIVE CONTROL — dotted othermod.suppress() beside an unrelated contextlib import must NOT fire (dotted binding, not name)" \
    bash "$GATE_SCRIPT" --root "$CLEAN12" --quiet
expect_pass "L18 (degraded text-fallback mode — where the prefix binding is a name-set lookup)" \
    gate_textmode --root "$CLEAN12" --quiet

# ── 27. NEGATIVE CONTROL (L19): a project-local `suppress` in a file whose ──
# ONLY contextlib import is a `from contextlib import <SOMETHING-ELSE>`.
# THE BARE-NAME BRANCH'S BINDING CHECK — the exact sibling of L18 (which
# pinned the DOTTED branch) one branch over. L14 cannot pin this: its file
# imports contextlib as a MODULE, so it exercises the module-alias path and
# leaves the from-import path licensing the bare form on mere PRESENCE. A
# text scanner that asks only "does this file do a `from contextlib import`
# at all?" refuses this healthy file while the AST analyser — which resolves
# the bound NAMES — passes it: a §11.4.201(1) FAIL-bluff AND a mode
# DIVERGENCE. Measured on the pre-fix gate: ast rc=0, text rc=1.
CLEAN13="$TMP/clean13"
mkfixture "$CLEAN13"
cat > "$CLEAN13/from_import_other_name.py" <<'PY'
from contextlib import ExitStack   # NOT suppress
import json


def suppress(kind):
    """Project-local warning filter. Nothing to do with contextlib."""
    return _WarningFilter(kind)


def render(page):
    with suppress(Exception):
        page.emit()


def load(path):
    with ExitStack() as stack:
        fh = stack.enter_context(open(path))
        return json.load(fh)
PY
expect_pass "L19 NEGATIVE CONTROL — project-local suppress() beside 'from contextlib import ExitStack' must NOT fire (bare-name binding, not from-import presence)" \
    bash "$GATE_SCRIPT" --root "$CLEAN13" --quiet
expect_pass "L19 (degraded text-fallback mode — where the from-import binding is a name-set lookup)" \
    gate_textmode --root "$CLEAN13" --quiet

# ── 28. NEGATIVE CONTROL (L20): `from contextlib import suppress as <alias>` ─
# binds the ALIAS, so the bare name `suppress` in that same file is NOT
# contextlib's. This is the ALIAS half of the bare-name binding: L19 pins
# "a different name was imported", L20 pins "suppress WAS imported, under a
# DIFFERENT name". A presence-only from-import check licenses the local call
# here too. Measured on the pre-fix gate: ast rc=0, text rc=1.
CLEAN14="$TMP/clean14"
mkfixture "$CLEAN14"
cat > "$CLEAN14/from_import_aliased.py" <<'PY'
from contextlib import suppress as quiet
import os


def suppress(kind):
    """Project-local warning filter. Nothing to do with contextlib."""
    return _WarningFilter(kind)


def render(page):
    with suppress(Exception):
        page.emit()


def purge(path):
    with quiet(FileNotFoundError):
        os.unlink(path)
PY
expect_pass "L20 NEGATIVE CONTROL — 'from contextlib import suppress as quiet' binds the ALIAS; a bare local suppress() must NOT fire" \
    bash "$GATE_SCRIPT" --root "$CLEAN14" --quiet
expect_pass "L20 (degraded text-fallback mode)" \
    gate_textmode --root "$CLEAN14" --quiet

# ── 29. NEGATIVE CONTROL (L21): the name `suppress` imported from a module ──
# that is NOT contextlib. This pins the MODULE half of the from-import
# binding, which L19/L20 (both contextlib imports) cannot reach: a mutation
# widening the module test to accept ANY module keeps every other fixture
# green while refusing this healthy file. Discriminator: exit 0 -> 1 under it.
CLEAN15="$TMP/clean15"
mkfixture "$CLEAN15"
cat > "$CLEAN15/foreign_suppress.py" <<'PY'
from myproject.util import suppress   # the project's OWN suppress helper


def render(page):
    with suppress(Exception):
        page.emit()
PY
expect_pass "L21 NEGATIVE CONTROL — 'suppress' imported from a NON-contextlib module must NOT fire (module binding, not any-from-import)" \
    bash "$GATE_SCRIPT" --root "$CLEAN15" --quiet
expect_pass "L21 (degraded text-fallback mode)" \
    gate_textmode --root "$CLEAN15" --quiet

# ── 30. NEGATIVE CONTROL (L22): a RELATIVE `from .contextlib import suppress`
# names a SIBLING module, not the stdlib one. The AST analyser encodes this
# as `not node.level`; nothing pinned that guard, so deleting it survived the
# whole suite while refusing this healthy file. Discriminator: ast 0 -> 1.
CLEAN16="$TMP/clean16"
mkfixture "$CLEAN16"
cat > "$CLEAN16/relative_import.py" <<'PY'
from .contextlib import suppress   # a SIBLING module of this package


def render(page):
    with suppress(Exception):
        page.emit()
PY
expect_pass "L22 NEGATIVE CONTROL — RELATIVE 'from .contextlib import suppress' is a sibling module, not the stdlib (absolute-import binding)" \
    bash "$GATE_SCRIPT" --root "$CLEAN16" --quiet
expect_pass "L22 (degraded text-fallback mode)" \
    gate_textmode --root "$CLEAN16" --quiet

# ── 31. MUTATED (L23): `from contextlib import *` DOES bind `suppress` ─────
# The star-import branch is the only from-import form that binds the name
# WITHOUT naming it. Disabling it under-reports a real violation silently,
# and no fixture saw that: the suite's other star-free fixtures are all
# unaffected. Discriminator: this fixture flips exit 1 -> 0 under it.
MUT15="$TMP/mut15"
mkfixture "$MUT15"
cat > "$MUT15/star_import.py" <<'PY'
from contextlib import *


def render(page):
    with suppress(Exception):
        page.emit()
PY
expect_fail "L23 'from contextlib import *' binds suppress — broad suppress MUST fire" \
    bash "$GATE_SCRIPT" --root "$MUT15" --quiet
expect_fail "L23 (degraded text-fallback mode)" \
    gate_textmode --root "$MUT15" --quiet

# ── 32. DEGRADED MODE ANNOUNCES ITSELF (§11.4.6 / §11.4.201(6)) ────────────
# A blind instrument that reports a quiet number is the false-null this gate
# exists to avoid; when the structural analyser is unavailable the gate MUST
# say so on stdout rather than silently reporting a floor as a census.
expect_output_contains "degraded text-fallback mode is announced, never silent" \
    "not a census" \
    gate_textmode --root "$MUT4" --quiet
# ...and the announcement must state the direction HONESTLY. An earlier
# revision announced text mode as "a FLOOR", which asserts no-false-hits --
# a claim the code contradicted in five measured ways. Four were closed
# (L24/L25/L26/L27 below); the string-literal carrier was then DISCLOSED in
# the same breath as the degradation. Pinning the disclosure keeps a future
# edit from quietly restoring the flattering half of the sentence.
expect_output_contains "the degraded-mode announcement DISCLOSES its over-reporting class, not only its under-reporting" \
    "OVER-reporting class" \
    gate_textmode --root "$MUT4" --quiet
# ...and it must NOT replace one wrong absolute with another. The disclosure
# above was next written as "ONE measured OVER-reporting class", and an
# independent review measured THREE MORE (plus a fifth this round closed
# outright). The announcement now frames both gap counts as MEASURED SAMPLES
# rather than censuses (§11.4.118); pinning that phrase keeps a future edit
# from quietly restoring a completeness claim the code cannot support. This
# assertion is the reason the sentence cannot silently regain an absolute.
expect_output_contains "the degraded-mode announcement frames its gap counts as MEASURED SAMPLES, never as a complete census" \
    "MEASURED SAMPLES" \
    gate_textmode --root "$MUT4" --quiet

# ── 33. NEGATIVE CONTROL (L24): a local callable whose name ENDS in ────────
# "suppress". THE IDENTIFICATION LAYER, first of three. Every fixture before
# this one pins LICENSING ("do the imports bind this NAME?"); none pins the
# PRIOR question ("is this token even the name?"). The text scanner matched
# `suppress[ \t]*\(` as an UNANCHORED SUBSTRING, so `try_suppress(` was read
# as a bare `suppress(` call -- and this file genuinely does
# `from contextlib import suppress`, so the licensing layer then approved it.
# The AST resolves `func.id` as a WHOLE name and passes the file.
# Measured on the pre-fix gate: ast=0, text=1 -- a live §11.4.201(1)
# FAIL-bluff refusing provably-healthy code. Discriminator: this fixture
# flips text-mode exit 0 -> 1 without the I6 whole-identifier guard.
CLEAN17="$TMP/clean17"
mkfixture "$CLEAN17"
cat > "$CLEAN17/tail_name.py" <<'PY'
from contextlib import suppress
import os


def try_suppress(kind):
    """Project-local retry wrapper. Nothing to do with contextlib."""
    return _Wrapper(kind)


def render(page):
    with try_suppress(Exception):
        page.emit()


def purge(path):
    with suppress(FileNotFoundError):
        os.unlink(path)
PY
expect_pass "L24 NEGATIVE CONTROL — try_suppress() must NOT be read as suppress() (whole identifier, not substring)" \
    bash "$GATE_SCRIPT" --root "$CLEAN17" --quiet
expect_pass "L24 (degraded text-fallback mode — where the substring match lived)" \
    gate_textmode --root "$CLEAN17" --quiet

# ── 34. NEGATIVE CONTROL (L25): a DOTTED sub-attribute prefix ──────────────
# `mypkg.contextlib.suppress(...)` in a file that genuinely imports
# contextlib. The text scanner's dotted-prefix extractor takes only the LAST
# component before the `.`, so it read the prefix as `contextlib`, found it in
# the module-alias set, and approved the call. The AST requires `func.value`
# to be a SIMPLE `Name` node -- `mypkg.contextlib.suppress` has an Attribute
# there -- so the analyser correctly passes the file.
# Measured on the pre-fix gate: ast=0, text=1. This is the DOTTED half of the
# identification layer, and L24 cannot reach it (that file has no dotted
# call at all). Discriminator: text-mode exit 0 -> 1 without the I7 guard.
CLEAN18="$TMP/clean18"
mkfixture "$CLEAN18"
cat > "$CLEAN18/sub_attribute.py" <<'PY'
import contextlib
import mypkg


def render(page):
    with mypkg.contextlib.suppress(Exception):
        page.emit()


def load(path):
    with contextlib.ExitStack() as stack:
        return stack.enter_context(open(path))
PY
expect_pass "L25 NEGATIVE CONTROL — pkg.contextlib.suppress() is NOT contextlib.suppress (prefix must be a simple name)" \
    bash "$GATE_SCRIPT" --root "$CLEAN18" --quiet
expect_pass "L25 (degraded text-fallback mode — where the last-component extractor lived)" \
    gate_textmode --root "$CLEAN18" --quiet

# ── 35. NEGATIVE CONTROL (L26): breadth token bleeding from a SIBLING call ─
# `with contextlib.suppress(ValueError), othermod.wrap(Exception):` is a
# NARROW, declared, legitimate suppression standing beside an unrelated call
# that happens to mention `Exception`. The text scanner read its breadth token
# from "everything after suppress(" -- the whole rest of the line -- so the
# SIBLING's argument was credited to the suppress call and the file was
# refused. The AST reads THIS call's own args (`[Name ValueError]`) and
# passes. Measured on the pre-fix gate: ast=0, text=1.
#
# NOT found by the round-4 review: surfaced while enumerating the
# identification layer the review asked for, which is the argument for
# enumerating a layer rather than patching its instances (§11.4.250).
# Discriminator: text-mode exit 0 -> 1 without the I8 argument-list bound.
CLEAN19="$TMP/clean19"
mkfixture "$CLEAN19"
cat > "$CLEAN19/sibling_bleed.py" <<'PY'
import contextlib
import othermod


def render(page):
    with contextlib.suppress(ValueError), othermod.wrap(Exception):
        page.emit()
PY
expect_pass "L26 NEGATIVE CONTROL — a SIBLING call's Exception argument must not be credited to a narrow suppress()" \
    bash "$GATE_SCRIPT" --root "$CLEAN19" --quiet
expect_pass "L26 (degraded text-fallback mode — where the unbounded breadth scan lived)" \
    gate_textmode --root "$CLEAN19" --quiet

# ── 36. NEGATIVE CONTROL (L27): breadth token bleeding from a SAME-LINE ────
# BODY. The second shape of the same unbounded-scan defect, and a distinct
# fixture because it exercises a different part of the line: here the stray
# `Exception` sits in a one-line suite AFTER the colon, not in a sibling
# context manager. A bound that only stopped at the first `)` of a
# comma-separated item list would still fail this one. Measured on the
# pre-fix gate: ast=0, text=1.
CLEAN20="$TMP/clean20"
mkfixture "$CLEAN20"
cat > "$CLEAN20/sameline_body.py" <<'PY'
import contextlib
import logging


def render(page):
    with contextlib.suppress(ValueError): logging.info("Exception path taken")
PY
expect_pass "L27 NEGATIVE CONTROL — a same-line body mentioning Exception must not widen a narrow suppress()" \
    bash "$GATE_SCRIPT" --root "$CLEAN20" --quiet
expect_pass "L27 (degraded text-fallback mode)" \
    gate_textmode --root "$CLEAN20" --quiet

# ── 37. MUTATED (L28): KEYWORD-ARGUMENT unresolvable list ──────────────────
# THE OTHER HALF of the §11.4.201(4) conservative-safe branch. L16/L17 pin the
# POSITIONAL unresolvable paths (Starred, IfExp) via `call.args`; NOTHING
# pinned `unresolved = bool(call.keywords)`. Measured: mutating it to a bare
# `False` SURVIVES the entire suite while silently FAILING OPEN on
# `suppress(**kw)` -- pristine rc=1, mutant rc=0 -- the exact defect
# §11.4.252 forbids, in a branch shipped with an advertised message that was
# never once observed doing its job (§11.4.115(F) unvalidated instrumentation,
# the precise state L16's own comment condemns).
#
# STRUCTURAL MODE ONLY, deliberately and for the SAME reason as L16: `**kw`
# carries no `Exception` token on the `with` line, so the text approximation
# cannot see it. That is recorded in the gate header's measured degraded-mode
# gap list (which this round extends to name the keyword form explicitly),
# never papered over.
MUT16="$TMP/mut16"
mkfixture "$MUT16"
cat > "$MUT16/l28.py" <<'PY'
import contextlib
import os

KW = {"foo": Exception}


def purge(user_supplied_path):
    with contextlib.suppress(**KW):
        os.unlink(user_supplied_path)
PY
expect_fail "L28 UNRESOLVABLE suppress(**KW) — keyword half of the conservative-safe refusal (§11.4.201(4))" \
    bash "$GATE_SCRIPT" --root "$MUT16" --quiet
# ...and for the RIGHT REASON, exactly as L16 requires: a verdict-only
# assertion cannot distinguish the conservative-safe path from a lucky
# misclassification into the "broad" message.
expect_output_contains "L28 refusal names the UNRESOLVED signal rather than guessing breadth" \
    "could not be resolved statically" \
    bash "$GATE_SCRIPT" --root "$MUT16" --quiet

# ── 38. NEGATIVE CONTROL (L29): a POPULATED container return ───────────────
# THE (A2) CLASS BOUNDARY. `is_trivial_literal` flags an EMPTY container
# (`return []`) because it carries zero information about the failure, and
# deliberately does NOT flag a POPULATED one -- its own docstring says a
# populated container "is doing work, which is fallback handling rather than
# a silent default". Nothing pinned that boundary: measured, dropping
# `and not value.elts` SURVIVES all other assertions while flipping this
# documented-legitimate handler from PASS to FAIL -- a §11.4.201(1)
# FAIL-bluff manufactured out of the gate's own stated semantics.
# The dict half (`not value.keys`) is included in the same fixture because it
# is the identical boundary one node type over, and was equally unpinned.
CLEAN21="$TMP/clean21"
mkfixture "$CLEAN21"
cat > "$CLEAN21/populated_fallback.py" <<'PY'
DEFAULT_ENTRY = {"name": "default", "enabled": True}


def load_entries(path):
    try:
        return _parse(path)
    except MissingFile:
        return [DEFAULT_ENTRY]


def load_index(path):
    try:
        return _parse_index(path)
    except MissingFile:
        return {"default": DEFAULT_ENTRY}
PY
expect_pass "L29 NEGATIVE CONTROL — a POPULATED container return is fallback handling, not a silent default" \
    bash "$GATE_SCRIPT" --root "$CLEAN21" --quiet
expect_pass "L29 (degraded text-fallback mode — the text scanner's own trivial-value list)" \
    gate_textmode --root "$CLEAN21" --quiet

# ── 39. NEGATIVE CONTROL (L30): a `#` COMMENT on a REAL `with` line ────────
# An OVER-report the round-5 enumeration missed: the with-line scanner never
# stripped comments, so a `#`-commented MENTION of the broad form on an
# otherwise-healthy line was matched as if it were the call's own argument.
# A comment is not a docstring, so this sat OUTSIDE the string-literal carrier
# class that WAS enumerated -- and the gate's own header had predicted the
# comment-carrier shape for the `except` scanner all along. Measured before
# the strip: ast=0 / text=1 (a §11.4.201(1) FAIL-bluff refusing healthy code).
CLEAN22="$TMP/clean22"
mkfixture "$CLEAN22"
cat > "$CLEAN22/comment_carrier.py" <<'PY'
from contextlib import suppress


def load(path):
    with suppress(FileNotFoundError):  # was suppress(Exception) before review
        return open(path).read()
PY
expect_pass "L30 NEGATIVE CONTROL — a '#' COMMENT mentioning the broad form must NOT widen a narrow suppress()" \
    bash "$GATE_SCRIPT" --root "$CLEAN22" --quiet
expect_pass "L30 (degraded text-fallback mode — where the comment carrier fired)" \
    gate_textmode --root "$CLEAN22" --quiet

# ── 40. MUTATED (L31): a REJECTED token BEFORE a real violation, ONE line ──
# Pins the multi-token CONTINUATION of the with-line scan. The loop examines
# EVERY `suppress(` token in turn precisely so a rejected first token cannot
# stop the scan; nothing pinned that, and flipping its `continue` to `break`
# SURVIVED the whole suite while restoring a real UNDER-report. Here the
# first token (`try_suppress(`) is rejected by the whole-identifier test and
# the SECOND is a genuine broad contextlib.suppress: a scan that stops at the
# first rejection reports the file clean (§11.4.115(F) -- an invariant no
# fixture kills is unvalidated instrumentation).
MUT17="$TMP/mut17"
mkfixture "$MUT17"
cat > "$MUT17/rejected_then_real.py" <<'PY'
from contextlib import suppress


def try_suppress(resource):
    return resource


def run(handle):
    with try_suppress(handle), suppress(Exception):
        handle.close()
PY
expect_fail "L31 a REJECTED token BEFORE a real violation on ONE line — the scan must CONTINUE, not stop" \
    bash "$GATE_SCRIPT" --root "$MUT17" --quiet
expect_fail "L31 (degraded text-fallback mode — where the multi-token loop lives)" \
    gate_textmode --root "$MUT17" --quiet

# ── 41. NEGATIVE CONTROL (L32): the SUFFIX half of the breadth boundary ────
# L15 pins only the PREFIX half of the word-boundary breadth match
# (`MyException` / `TransportBaseException` both discriminate on the LEADING
# boundary), so dropping the TRAILING boundary SURVIVED the whole suite while
# turning `suppress(ExceptionGroup)` -- a real Python 3.11+ builtin, and a
# genuinely NARROW, declared tolerance -- into a refusal. This is a live
# false-refusal on modern code, not a synthetic shape.
CLEAN23="$TMP/clean23"
mkfixture "$CLEAN23"
cat > "$CLEAN23/suffix_boundary.py" <<'PY'
from contextlib import suppress


def run(group_op):
    with suppress(ExceptionGroup):
        group_op()
PY
expect_pass "L32 NEGATIVE CONTROL — suppress(ExceptionGroup) is NARROW; the breadth match needs its TRAILING boundary too" \
    bash "$GATE_SCRIPT" --root "$CLEAN23" --quiet
expect_pass "L32 (degraded text-fallback mode — where the boundary is a regex)" \
    gate_textmode --root "$CLEAN23" --quiet

# ── 42. MUTATED (L33): a `#` INSIDE a string on a violating line ───────────
# The comment strip that closes L30 must be QUOTE-AWARE. A naive
# `sub(/#.*$/, "", line)` would truncate this line at the `#` inside
# `"chan#1"`, deleting the real `suppress(Exception)` that follows it -- an
# over-report traded for an UNDER-report, which is the strictly worse
# direction. The violation must still be reported.
MUT18="$TMP/mut18"
mkfixture "$MUT18"
cat > "$MUT18/hash_in_string.py" <<'PY'
from contextlib import suppress


def run(lock, path):
    with lock.hold("chan#1"), suppress(Exception):
        return open(path).read()
PY
expect_fail "L33 a '#' INSIDE a string must not truncate the line — the real suppress(Exception) after it must still FAIL" \
    bash "$GATE_SCRIPT" --root "$MUT18" --quiet
expect_fail "L33 (degraded text-fallback mode — where the comment strip lives)" \
    gate_textmode --root "$MUT18" --quiet

# ── 43. MUTATED (L34): an ESCAPED quote before a `#` inside a string ───────
# The quote tracker must honour BACKSLASH ESCAPES. Without them the escaped
# `\"` closes the string early, the following `#` reads as outside it, the
# line is truncated, and the real violation vanishes -- the same
# over-to-under trade as L33, reached through the escape path instead.
MUT19="$TMP/mut19"
mkfixture "$MUT19"
cat > "$MUT19/escaped_quote.py" <<'PY'
from contextlib import suppress


def run(lock, path):
    with lock.hold("a\"#b"), suppress(Exception):
        return open(path).read()
PY
expect_fail "L34 an ESCAPED quote before a '#' inside a string must not truncate the line" \
    bash "$GATE_SCRIPT" --root "$MUT19" --quiet
expect_fail "L34 (degraded text-fallback mode)" \
    gate_textmode --root "$MUT19" --quiet

# ── 44. MUTATED (L35): a TRIPLE-QUOTED string whose interior holds a `"` ───
# The comment strip's quote model must treat `"""` as ONE three-character
# delimiter, not as three independent one-character toggles. Read
# character-by-character, `"""a"#b"""` opens at char 1, CLOSES at char 2,
# re-opens at char 3 and closes again at the `"` after `a` -- so the `#`,
# which is genuinely INSIDE the string, reads as OUTSIDE it, the line is
# truncated there, and the real `suppress(Exception)` after it is SILENTLY
# DELETED from the scan. Measured against the pre-fix gate: ast=1 / text=0 --
# an UNDER-report, and a REGRESSION (reverting the strip call alone restored
# text=1). L33 does not catch it because `"chan#1"` has no interior quote, so
# its odd/even toggle count happens to land right.
MUT20="$TMP/mut20"
mkfixture "$MUT20"
cat > "$MUT20/triple_dq.py" <<'PY'
from contextlib import suppress


def run(lock, path):
    with lock.hold("""a"#b"""), suppress(Exception):
        return open(path).read()
PY
expect_fail "L35 a TRIPLE-QUOTED string containing a quote then a '#' must not truncate the line" \
    bash "$GATE_SCRIPT" --root "$MUT20" --quiet
expect_fail "L35 (degraded text-fallback mode — where the comment strip lives)" \
    gate_textmode --root "$MUT20" --quiet

# ── 45. MUTATED (L36): the SINGLE-quoted triple-delimiter half of L35 ──────
# `'''` is the same three-character delimiter and was lost the same way
# (measured ast=1 / text=0 pre-fix). Pinning only the double-quoted form
# would leave the fix half-validated -- the exact gap L33/L34 left for the
# one-character delimiters and that L37 closes below.
MUT21="$TMP/mut21"
mkfixture "$MUT21"
cat > "$MUT21/triple_sq.py" <<'PY'
from contextlib import suppress


def run(lock, path):
    with lock.hold('''a'#b'''), suppress(Exception):
        return open(path).read()
PY
expect_fail "L36 the SINGLE-quoted triple delimiter must be tracked as one delimiter too" \
    bash "$GATE_SCRIPT" --root "$MUT21" --quiet
expect_fail "L36 (degraded text-fallback mode)" \
    gate_textmode --root "$MUT21" --quiet

# ── 46. MUTATED (L37): the SINGLE-QUOTE half of the strip's quote tracker ──
# L33/L34 both use DOUBLE-quoted strings, so both survive a tracker that has
# forgotten the apostrophe entirely. Measured: deleting `|| c == sq` from the
# open-quote test SURVIVED the whole suite while flipping this fixture
# text=1 -> text=0 (the L33 defect reached through the other delimiter). The
# fixture is therefore a MUTATION KILL, not a new gate defect: it PASSes the
# shipped gate and exists so that half of the tracker can no longer be
# deleted silently (§11.4.115(F) -- an invariant no fixture kills is
# unvalidated instrumentation).
MUT22="$TMP/mut22"
mkfixture "$MUT22"
cat > "$MUT22/hash_in_single_quoted.py" <<'PY'
from contextlib import suppress


def run(lock, path):
    with lock.hold('chan#1'), suppress(Exception):
        return open(path).read()
PY
expect_fail "L37 a '#' inside a SINGLE-quoted string must not truncate the line either" \
    bash "$GATE_SCRIPT" --root "$MUT22" --quiet
expect_fail "L37 (degraded text-fallback mode — the apostrophe half of the tracker)" \
    gate_textmode --root "$MUT22" --quiet

# ── 47. MUTATED (L38): the AST classifier's DOCSTRING filter ───────────────
# `classify()` drops a leading string-Expr before counting handler body
# statements, so a handler that documents WHY it ignores the error and then
# swallows it is still one statement -- still `pass`, still a violation.
# Measured: replacing the filter with `list(handler.body)` makes the body
# read as TWO statements, `classify` returns None, and this real swallow goes
# undetected -- and that mutation SURVIVED the whole suite. STRUCTURAL MODE
# ONLY, and for a stated reason (§11.4.6): the text scanner's except-shape
# matcher looks for `pass` on the line after the `except`, finds the
# docstring, and measures text=0 here. That is an EXISTING text-mode
# under-gap of the except shape, not something this fixture introduces;
# asserting it in degraded mode would pin a defect rather than an invariant.
MUT23="$TMP/mut23"
mkfixture "$MUT23"
cat > "$MUT23/docstring_then_pass.py" <<'PY'
def run(path):
    try:
        return open(path).read()
    except Exception:
        "we deliberately ignore this"
        pass
PY
expect_fail "L38 a DOCSTRING before 'pass' must not hide the swallow (structural mode)" \
    bash "$GATE_SCRIPT" --root "$MUT23" --quiet

# ── 48. MUTATED (L39): the UNPARSED handoff — never a silent skip ──────────
# A file the AST reader cannot parse MUST be handed back to the text scanner
# AND announced. Measured: deleting the `UNPARSED` write makes the analyser
# `continue` past the file in silence -- the gate then reports a confident
# clean PASS (rc 1 -> 0) with ZERO note, which is the exact silent-skip the
# gate's own comment forbids -- and that mutation SURVIVED the whole suite.
# Two assertions, because rc alone would not distinguish "text scanner caught
# it" from "the handoff was announced": the verdict, and the NOTE itself.
MUT24="$TMP/mut24"
mkfixture "$MUT24"
cat > "$MUT24/syntax_error.py" <<'PY'
from contextlib import suppress


def run(:
    with suppress(Exception):
        pass
PY
expect_fail "L39 an UNPARSEABLE file must still reach the text scanner and FAIL on its violation" \
    bash "$GATE_SCRIPT" --root "$MUT24" --quiet
expect_output_contains "L39 the UNPARSED handoff is ANNOUNCED, never a silent skip (§11.4.201(6))" \
    "could not be parsed as Python 3" \
    bash "$GATE_SCRIPT" --root "$MUT24"

# ── 49. NEGATIVE CONTROL (L40): the triple-delimiter POSITION ADVANCE ──────
# L35/L36 prove the strip enters and leaves a triple-quoted region; they do
# NOT prove it advances PAST the delimiter it just consumed. Two mutations
# of the fix added this round SURVIVED L30-L39 -- found by fuzzing the
# extracted function over every string of quote / hash / backslash / paren
# characters up to length 6 and 400k random longer ones, then filtering to
# lines that really parse as Python (§11.4.194(6)(d): attempt mutations the
# author did not write; the author reasoned BOTH of these were behaviourally
# equivalent and measurement refuted him on both):
#   * dropping `i += 2` on the OPEN branch, so the two trailing characters of
#     an opening triple are re-examined as content;
#   * dropping the `t3 = 0` reset on the CLOSE branch, so every LATER
#     one-character string on the same line is treated as triple-quoted and
#     never closes.
# This line exercises both: an opening triple whose own content STARTS with
# a quote, followed by a second, one-character-quoted argument, followed by
# a real `#` comment that quotes the broad form. The code is HEALTHY --
# `suppress(FileNotFoundError)` is a declared, bounded tolerance -- so a
# refusal here is a §11.4.201(1) FAIL-bluff. Measured: base text=0 (PASS),
# both mutants text=1 (false alarm).
CLEAN24="$TMP/clean24"
mkfixture "$CLEAN24"
cat > "$CLEAN24/triple_then_short.py" <<'PY'
from contextlib import suppress
import lock


def f(p):
    with lock.hold(""""a""", "b"), suppress(FileNotFoundError):  # suppress(Exception)
        return open(p).read()
PY
expect_pass "L40 NEGATIVE CONTROL — a triple-quoted arg then a short-quoted arg then a real comment must NOT be refused" \
    bash "$GATE_SCRIPT" --root "$CLEAN24" --quiet
expect_pass "L40 (degraded text-fallback mode — where the position advance lives)" \
    gate_textmode --root "$CLEAN24" --quiet

# ── 50. NEGATIVE CONTROL (L41): the CLOSE-side position advance ────────────
# The third surviving mutation of the same fix: dropping `i += 2` on the
# CLOSE branch, so the two trailing characters of a CLOSING triple are
# re-examined and re-open a one-character string that then swallows the rest
# of the line. L40 does not reach it; this shape does, via Python implicit
# string concatenation -- a triple-quoted literal directly abutting a
# short-quoted one, with no separator -- which puts the two delimiters back
# to back. Healthy code again, so a refusal is again a §11.4.201(1)
# FAIL-bluff. Measured: base text=0 (PASS), mutant text=1 (false alarm).
CLEAN25="$TMP/clean25"
mkfixture "$CLEAN25"
cat > "$CLEAN25/abutting_delimiters.py" <<'PY'
from contextlib import suppress
import lock


def f(p):
    with lock.hold("""a""""b"), suppress(FileNotFoundError):  # suppress(Exception)
        return open(p).read()
PY
expect_pass "L41 NEGATIVE CONTROL — ABUTTING triple and short delimiters (implicit concatenation) must NOT be refused" \
    bash "$GATE_SCRIPT" --root "$CLEAN25" --quiet
expect_pass "L41 (degraded text-fallback mode)" \
    gate_textmode --root "$CLEAN25" --quiet

# ── 51. MUTATED (L42): the OPEN-detection WIDTH of the triple delimiter ────
# L35-L37 prove the strip ENTERS and LEAVES a triple-quoted region; L40/L41
# prove it ADVANCES past the delimiter it just consumed. Neither pins how
# WIDE the OPEN test looks. Measured: narrowing `substr(s, i, 3) == d3` to a
# two-character test on the OPEN branch SURVIVED the entire suite (101 OK /
# 0 FAIL / exit 0) while flipping this fixture text=1 -> text=0. Mechanism:
# an EMPTY short-quoted string is two ADJACENT quote characters, so the
# mutant opens a triple there while consuming only two of them; the REAL
# triple-quote later on the line is then read as the CLOSE, the `#` that is
# genuinely INSIDE it reads as OUTSIDE, the line is cut there, and the real
# suppress(Exception) after the cut is SILENTLY DELETED from the scan --
# ast=1/text=0, the dangerous silent-under-report direction, reached through
# the OPEN width rather than the position advance.
MUT26="$TMP/mut26"
mkfixture "$MUT26"
cat > "$MUT26/empty_then_triple.py" <<'PY'
from contextlib import suppress


def run(lock, path):
    with lock.hold("" + """#"""), suppress(Exception):
        return open(path).read()
PY
expect_fail "L42 an EMPTY short-quoted string before a triple-quoted '#' must not be read as a triple-open" \
    bash "$GATE_SCRIPT" --root "$MUT26" --quiet
expect_fail "L42 (degraded text-fallback mode — where the open-width test lives)" \
    gate_textmode --root "$MUT26" --quiet

# ── 52. MUTATED (L43): CROSS-QUOTE confusion INSIDE a string ───────────────
# A string region closes on the delimiter that OPENED it and on NO other.
# Measured: relaxing the in-string close test so EITHER quote character
# closes the region SURVIVED the entire suite (101 OK / 0 FAIL / exit 0)
# while flipping this fixture text=1 -> text=0. L37 pins deleting the
# apostrophe from the OPEN tracker, but no fixture carried a DOUBLE-quoted
# string with an INTERIOR apostrophe followed by a `#` before a real
# violation. Under the mutant the apostrophe closes the double-quoted string
# early, the in-string `#` then reads as a real comment, the line is cut, and
# the real suppress(Exception) is SILENTLY DELETED -- ast=1/text=0, the same
# direction as L42 through the CLOSE side of the tracker instead of the OPEN
# side.
MUT27="$TMP/mut27"
mkfixture "$MUT27"
cat > "$MUT27/apostrophe_then_hash.py" <<'PY'
from contextlib import suppress


def run(lock, path):
    with lock.hold("it's #1"), suppress(Exception):
        return open(path).read()
PY
expect_fail "L43 an APOSTROPHE inside a DOUBLE-quoted string must not close it — the '#' after it is still inside" \
    bash "$GATE_SCRIPT" --root "$MUT27" --quiet
expect_fail "L43 (degraded text-fallback mode — the cross-quote close half of the tracker)" \
    gate_textmode --root "$MUT27" --quiet

# ── 53. MUTATED (L44): the CLOSE-detection WIDTH of the triple delimiter ───
# L42 pins how WIDE the OPEN test looks; L40/L41 pin that both branches
# ADVANCE past the delimiter they consumed. Neither pins how wide the CLOSE
# test looks. Measured: narrowing `substr(s, i, 3) == d3` to a two-character
# test on the CLOSE branch SURVIVED the entire suite (105 OK / 0 FAIL /
# exit 0) while flipping this fixture text=1 -> text=0. Mechanism: two
# ADJACENT quotes INSIDE a triple-quoted string are ordinary content, but the
# mutant reads them as the close, so the `#` that is genuinely inside the
# string reads as a real comment, the line is cut there, and the
# suppress(Exception) after the cut is SILENTLY DELETED from the scan --
# ast=1/text=0, the dangerous under-report direction, reached through the
# CLOSE width rather than the OPEN width L42 covers.
#
# The `x` between the quote pair and the `#` is LOAD-BEARING, and was found
# by measurement rather than by reading: with the `#` directly ABUTTING the
# pair the mutant's own `i += 2` steps straight OVER it, no cut happens, and
# the fixture measures text=1 under BOTH shipped and mutant -- silently
# killing nothing. Anyone re-deriving this fixture must keep a character
# between the pair and the `#`.
MUT28="$TMP/mut28"
mkfixture "$MUT28"
cat > "$MUT28/triple_pair_then_hash.py" <<'PY'
from contextlib import suppress


def run(lock, path):
    with lock.hold("""ab""x#cd"""), suppress(Exception):
        return open(path).read()
PY
expect_fail "L44 two ADJACENT quotes inside a triple-quoted string must not close it — the '#' after them is still inside" \
    bash "$GATE_SCRIPT" --root "$MUT28" --quiet
expect_fail "L44 (degraded text-fallback mode — where the close-width test lives)" \
    gate_textmode --root "$MUT28" --quiet

# ── 54. NEGATIVE CONTROL (L45): the OPEN-side position OVER-advance ────────
# L40/L41 pin the position advance being too SHORT (dropping `i += 2`).
# Nothing pinned it being too LONG. Measured: `i += 2` -> `i += 3` on the
# OPEN branch SURVIVED the entire suite (105 OK / 0 FAIL / exit 0) while
# flipping this fixture text=0 -> text=1. Mechanism: the over-advance skips
# the first CONTENT character of a triple-quoted string, which can only
# matter when that character is itself the start of the closing run -- i.e.
# the EMPTY triple-quoted string, six quotes, whose close begins immediately.
# The mutant therefore never closes it, the loop ends with the region still
# open, the line is returned UNCUT, and the broad form quoted in the REAL
# trailing comment is scanned as if it were code. The code here is HEALTHY --
# `suppress(FileNotFoundError)` is a declared, bounded tolerance -- so the
# refusal is a §11.4.201(1) FAIL-bluff.
#
# The trailing comment is LOAD-BEARING, and its absence is why the fixture
# proposed for this finding measured 0/0 under both shipped and mutant: with
# nothing after the string for the strip to REMOVE, "closed correctly" and
# "never closed" return the same bytes and the mutation is invisible.
CLEAN26="$TMP/clean26"
mkfixture "$CLEAN26"
cat > "$CLEAN26/empty_triple.py" <<'PY'
from contextlib import suppress
import lock


def f(p):
    with lock.hold(""""""), suppress(FileNotFoundError):  # suppress(Exception)
        return open(p).read()
PY
expect_pass "L45 NEGATIVE CONTROL — an EMPTY triple-quoted string must still close, so the real comment after it is stripped" \
    bash "$GATE_SCRIPT" --root "$CLEAN26" --quiet
expect_pass "L45 (degraded text-fallback mode — where the open-side advance lives)" \
    gate_textmode --root "$CLEAN26" --quiet

# ── 55. NEGATIVE CONTROL (L46): the ESCAPE-SKIP WIDTH ──────────────────────
# L34 pins DELETING the backslash handling (a mutant ignoring escapes
# entirely dies there). Nothing pinned how FAR that handling skips. Measured:
# `i++` -> `i += 2` on the escape branch SURVIVED the entire suite (105 OK /
# 0 FAIL / exit 0) while flipping this fixture text=0 -> text=1, and so did
# `i++` -> `i += 3`; this one fixture kills BOTH, so the whole width family
# falls to it. Mechanism: the over-wide skip swallows the character AFTER the
# escaped one, and when that character is the CLOSING quote the string never
# closes -- so the real trailing comment is never stripped and its quoted
# broad form is scanned as code. A trailing backslash in a Windows path
# literal is everyday Python, which is what makes this direction expensive:
# a gate that starts refusing ordinary path literals gets switched off, not
# fixed.
#
# As with L45 the trailing comment is LOAD-BEARING: the fixture proposed for
# this finding omitted it and measured 0/0 under both shipped and mutant.
CLEAN27="$TMP/clean27"
mkfixture "$CLEAN27"
cat > "$CLEAN27/escaped_backslash.py" <<'PY'
from contextlib import suppress
import lock


def f(p):
    with lock.hold("C:\\"), suppress(FileNotFoundError):  # suppress(Exception)
        return open(p).read()
PY
expect_pass "L46 NEGATIVE CONTROL — an escaped backslash before the closing quote must not swallow it (an everyday Windows path literal)" \
    bash "$GATE_SCRIPT" --root "$CLEAN27" --quiet
expect_pass "L46 (degraded text-fallback mode — where the escape-skip width lives)" \
    gate_textmode --root "$CLEAN27" --quiet

# ── 56. MUTATED (L47): the SHORT-string CLOSE over-advance ─────────────────
# L40/L41/L45 pin the advances on the TRIPLE branches. The SHORT-string close
# has no advance at all -- and nothing pinned that it has none. Measured:
# adding `i += 1` to the short-string close SURVIVED the entire suite (105 OK
# / 0 FAIL / exit 0) while flipping this fixture text=1 -> text=0. Mechanism:
# the spurious advance swallows the OPENING quote of an IMPLICITLY
# CONCATENATED neighbouring literal, so that neighbour's body is read as CODE
# rather than as string content; the `#` inside it then reads as a real
# comment, the line is cut, and the suppress(Exception) after the cut is
# SILENTLY DELETED -- ast=1/text=0.
#
# Not reached by the review that found L44-L46; found by sweeping EVERY
# advance in the machine rather than only the ones a previous round had
# touched (§11.4.194(6)(d) -- the reviewer must attempt mutations the author
# did not write, and the author must then attempt the ones the reviewer did
# not).
MUT29="$TMP/mut29"
mkfixture "$MUT29"
cat > "$MUT29/implicit_concat_hash.py" <<'PY'
from contextlib import suppress


def run(lock, path):
    with lock.hold("a""b#c"), suppress(Exception):
        return open(path).read()
PY
expect_fail "L47 closing a short string must not swallow the next literal's opening quote — the '#' inside it is still in a string" \
    bash "$GATE_SCRIPT" --root "$MUT29" --quiet
expect_fail "L47 (degraded text-fallback mode — where the short-close advance lives)" \
    gate_textmode --root "$MUT29" --quiet

# ── 57. NEGATIVE CONTROL (L48): the SHORT-string OPEN over-advance ─────────
# The mirror of L47 on the OPEN side, and equally unpinned. Measured: adding
# `i += 1` to the short-string open SURVIVED the entire suite (105 OK / 0
# FAIL / exit 0) while flipping this fixture text=0 -> text=1. Mechanism: the
# spurious advance skips the first CONTENT character, which matters when that
# character IS the closing quote -- the EMPTY short string. The mutant never
# closes it, the line is returned UNCUT, and the broad form quoted in the
# REAL trailing comment is scanned as code: healthy code REFUSED, a
# §11.4.201(1) FAIL-bluff.
#
# L42 also contains an empty short string, but as the SUBJECT of an
# expect_fail whose verdict this mutation does not move; measured, L42 leaves
# it alive. Not reached by the review that found L44-L46.
CLEAN28="$TMP/clean28"
mkfixture "$CLEAN28"
cat > "$CLEAN28/empty_short_string.py" <<'PY'
from contextlib import suppress
import lock


def f(p):
    with lock.hold(""), suppress(FileNotFoundError):  # suppress(Exception)
        return open(p).read()
PY
expect_pass "L48 NEGATIVE CONTROL — an EMPTY short-quoted string must still close, so the real comment after it is stripped" \
    bash "$GATE_SCRIPT" --root "$CLEAN28" --quiet
expect_pass "L48 (degraded text-fallback mode — where the short-open advance lives)" \
    gate_textmode --root "$CLEAN28" --quiet

# ── 58. NEGATIVE CONTROL (L49): the TRIPLE-OPEN DELIMITER IDENTITY ─────────
# L36/L37 pin the apostrophe in the OPEN tracker and L43 pins cross-quote
# confusion INSIDE a region. Neither pins that a triple-APOSTROPHE region is
# tracked WITH the apostrophe: the open branch stores `q = c`, and nothing
# measured what happens if it stores a fixed double quote instead. Measured:
# replacing `q = c` with a hard-wired double quote on the triple-open branch
# SURVIVED the entire suite (105 OK / 0 FAIL / exit 0) while flipping this
# fixture text=0 -> text=1. Mechanism: every triple-apostrophe region is then
# opened under the WRONG delimiter, so its real closing run never matches,
# the region stays open to end of line, the line is returned UNCUT, and the
# broad form quoted in the REAL trailing comment is scanned as code --
# healthy code REFUSED, a §11.4.201(1) FAIL-bluff on a completely ordinary
# Python string delimiter. Not reached by the review that found L44-L46.
CLEAN29="$TMP/clean29"
mkfixture "$CLEAN29"
cat > "$CLEAN29/triple_apostrophe.py" <<'PY'
from contextlib import suppress
import lock


def f(p):
    with lock.hold('''a'''), suppress(FileNotFoundError):  # suppress(Exception)
        return open(p).read()
PY
expect_pass "L49 NEGATIVE CONTROL — a triple-APOSTROPHE string must be tracked with the apostrophe, so it closes and its comment is stripped" \
    bash "$GATE_SCRIPT" --root "$CLEAN29" --quiet
expect_pass "L49 (degraded text-fallback mode — where the triple-open delimiter identity lives)" \
    gate_textmode --root "$CLEAN29" --quiet


# ── 59. MUTATED (L50): the ARGUMENT-LIST NESTING COUNTER ───────────────────
# The `arglist` extractor walks to the matching close paren, and the breadth
# scan runs over what it returns. L16/L17/L28 pin what happens to UNRESOLVABLE
# arguments; L26/L27 pin that the scan is BOUNDED to the call. Nothing pinned
# that the walk COUNTS NESTING — that a `(` inside the argument list pushes a
# level. Measured: replacing `depth++` with a no-op SURVIVED the entire suite
# (117 OK / 0 FAIL / exit 0) while flipping this fixture text=1 -> text=0.
# Mechanism: without the push, the FIRST inner `)` — the one closing a nested
# call in an earlier argument — decrements to zero and returns, TRUNCATING the
# argument list before the broad `Exception` that follows it. The breadth scan
# then reads a narrow call and the violation is SILENTLY DROPPED: ast=1/text=0.
#
# Not reached by any prior round; found by sweeping the string-machine's
# CALLERS rather than the string machine itself (§11.4.194(6)(d)).
MUT30="$TMP/mut30"
mkfixture "$MUT30"
cat > "$MUT30/nested_arg.py" <<'PY'
from contextlib import suppress


def run(errors, path):
    with suppress(getattr(errors, "Transient"), Exception):
        return open(path).read()
PY
expect_fail "L50 a NESTED call in an earlier suppress() argument must not truncate the list before the broad Exception" \
    bash "$GATE_SCRIPT" --root "$MUT30" --quiet
expect_fail "L50 (degraded text-fallback mode — where the nesting counter lives)" \
    gate_textmode --root "$MUT30" --quiet

# ── 60. MUTATED (L51): the MODULE-IMPORT HARVEST is INDENTATION-BLIND ──────
# L14/L18 pin that a module import BINDS a name rather than merely existing,
# and L25 pins the prefix shape. All of them import at column zero. Nothing
# pinned that the harvest reaches an INDENTED import — a function-local
# `import contextlib`, which is ordinary Python and which the AST analyser
# sees without effort because `ast.walk` is position-independent. Measured:
# dropping the leading `[ \t]*` from the module-import pattern SURVIVED the
# entire suite (117 OK / 0 FAIL / exit 0) while flipping this fixture
# text=1 -> text=0. Mechanism: the indented import is never harvested, so
# `contextlib` binds nothing, the dotted call is read as unlicensed, and the
# violation is SILENTLY DROPPED: ast=1/text=0.
MUT31="$TMP/mut31"
mkfixture "$MUT31"
cat > "$MUT31/indented_import.py" <<'PY'
def run(path):
    import contextlib
    with contextlib.suppress(Exception):
        return open(path).read()
PY
expect_fail "L51 a FUNCTION-LOCAL 'import contextlib' still binds the module — the indented import must be harvested" \
    bash "$GATE_SCRIPT" --root "$MUT31" --quiet
expect_fail "L51 (degraded text-fallback mode — where the import harvest is anchored)" \
    gate_textmode --root "$MUT31" --quiet

# ── 61. MUTATED (L52): the PARENTHESISED from-import SPEC SCRUB ────────────
# L19/L20/L21/L22/L23 pin WHICH names a from-import binds. Every one of them
# writes the import bare. Nothing pinned the PARENTHESISED form
# `from contextlib import (suppress)` — the shape Python's own style guides
# produce the moment an import list wraps — whose spec the harvester must
# scrub of parens before splitting. Measured: deleting the paren scrub
# SURVIVED the entire suite (117 OK / 0 FAIL / exit 0) while flipping this
# fixture text=1 -> text=0. Mechanism: the item is read as the literal
# `(suppress)`, which is not the name `suppress`, so nothing binds, the bare
# call is read as a project-local helper, and the violation is SILENTLY
# DROPPED: ast=1/text=0 — where the AST resolves `a.asname or a.name` and is
# unaffected by the parentheses entirely.
MUT32="$TMP/mut32"
mkfixture "$MUT32"
cat > "$MUT32/paren_import.py" <<'PY'
from contextlib import (suppress)


def run(path):
    with suppress(Exception):
        return open(path).read()
PY
expect_fail "L52 a PARENTHESISED 'from contextlib import (suppress)' binds suppress — the spec must be scrubbed of parens" \
    bash "$GATE_SCRIPT" --root "$MUT32" --quiet
expect_fail "L52 (degraded text-fallback mode — where the spec scrub lives)" \
    gate_textmode --root "$MUT32" --quiet

# ── 62. MUTATED (L53): WHITESPACE AROUND THE DOTTED-CALL SEPARATOR ─────────
# L18/L25 pin WHICH prefix binds and that it must be a simple name. Both
# write the dot tight. Nothing pinned that the prefix matcher TOLERATES
# WHITESPACE around the separator — `contextlib . suppress(...)`, which is
# legal Python and which the AST analyser parses into exactly the same
# Attribute node as the tight form. Measured: tightening the prefix pattern
# to a bare `\.$` SURVIVED the entire suite (117 OK / 0 FAIL / exit 0) while
# flipping this fixture text=1 -> text=0. Mechanism: the spaced prefix no
# longer matches, so the call is misclassified as a BARE call needing a
# from-import; the file has only a module import, nothing licenses it, and
# the violation is SILENTLY DROPPED: ast=1/text=0.
MUT33="$TMP/mut33"
mkfixture "$MUT33"
cat > "$MUT33/spaced_dot.py" <<'PY'
import contextlib


def run(path):
    with contextlib . suppress(Exception):
        return open(path).read()
PY
expect_fail "L53 WHITESPACE around the dotted separator ('contextlib . suppress') is the same call — the prefix must still bind" \
    bash "$GATE_SCRIPT" --root "$MUT33" --quiet
expect_fail "L53 (degraded text-fallback mode — where the prefix pattern lives)" \
    gate_textmode --root "$MUT33" --quiet

# ── 63. MUTATED (L54): the STRING silent default — in BOTH analysers ───────
# The whole silent-default shape was pinned through L4's `return 0` alone.
# Measured on this harness before this fixture: `grep -c 'return "'` = 0 —
# NO fixture anywhere returned a string, in either quote style. That left the
# string arm of the shape unpinned in BOTH analysers at once, and it is the
# arm that matters most in practice: `return "unknown"` reads as a real answer
# at the call site in a way `return 0` does not.
#
# Two independent mutations, one fixture, one per mode:
#   TEXT — making the quoted-constant branch never-true SURVIVED the entire
#   suite (117 OK / 0 FAIL / exit 0) while flipping this fixture text=1 -> 0.
#   AST  — excluding `str` from `is_trivial_literal` likewise SURVIVED
#   (117 OK / 0 FAIL / exit 0) while flipping this fixture ast=1 -> 0.
#
# The AST arm is the more serious of the two: it blinds the PRIMARY analyser,
# not the degraded fallback, and under it even `return ""` — a value the
# function's own comment enumerates — passes CLEAN (measured: ast=1 shipped,
# ast=0 mutated). Every previously-found door on this gate lived in the text
# scanner; this is the first measured door in the AST path, so the AST path
# is no longer to be treated as pinned by construction.
MUT34="$TMP/mut34"
mkfixture "$MUT34"
cat > "$MUT34/string_default.py" <<'PY'
def fetch_name(account_id):
    try:
        return ledger.name(account_id)
    except Exception:
        return "unknown"
PY
expect_fail "L54 a STRING silent default ('return \"unknown\"') is as information-free as 'return 0' — AST arm" \
    bash "$GATE_SCRIPT" --root "$MUT34" --quiet
expect_fail "L54 (degraded text-fallback mode — the text scanner's quoted-constant branch)" \
    gate_textmode --root "$MUT34" --quiet


# ══════════════════════════════════════════════════════════════════════════
# ROUND-15 AST-PATH SWEEP (L55-L59)
# ──────────────────────────────────────────────────────────────────────────
# L54 recorded the first measured door in the AST analyser. That made the
# AST path's remaining predicates a MEASUREMENT problem rather than an
# assumption: "is_trivial_literal is unlikely to be its only unpinned
# predicate" is a hypothesis, and the only honest response is to sweep it.
#
# The sweep enumerated every decision the AST analyser makes and asked of
# each one "which fixture would notice if this branch stopped working?".
# Five had NO such fixture. All five were then mutated and MEASURED: every
# one SURVIVED the full 127-assertion suite, so all five were real doors,
# not theory. Their fixtures follow.
#
# The corresponding TEXT arms were swept the same way and measured
# separately (they share these fixtures but are DIFFERENT code): dropping
# the empty-container values from the text trivial-list, the bare-return
# branch, and the `...` branch each SURVIVED the suite too. So the text
# assertions below are load-bearing in their own right, not free riders on
# the AST assertion — each was observed to flip.
# ══════════════════════════════════════════════════════════════════════════

# ── 64. MUTATED (L55): the EMPTY-CONTAINER return (List/Tuple/Set) ─────────
# L4 pins `return 0` and L29 pins that a POPULATED container is NOT trivial.
# Neither pins the arm between them: an EMPTY container. Measured: deleting
# the `(ast.List, ast.Tuple, ast.Set) and not value.elts` arm SURVIVED the
# suite (127 OK / 0 FAIL / exit 0), ast=1 -> ast=0; independently, replacing
# the text scanner's `[] {} ()` comparisons SURVIVED too, text=1 -> text=0.
# `return []` to a caller expecting rows is the silent default in its most
# common real-world dress: the caller renders "no results" and never learns
# the query failed.
MUT35="$TMP/mut35"
mkfixture "$MUT35"
cat > "$MUT35/empty_list_default.py" <<'PY'
def load_rows(path):
    try:
        return _parse(path)
    except Exception:
        return []
PY
expect_fail "L55 an EMPTY container return ('return []') is a silent default — the caller cannot tell the query failed" \
    bash "$GATE_SCRIPT" --root "$MUT35" --quiet
expect_fail "L55 (degraded text-fallback mode — the text scanner's empty-container values)" \
    gate_textmode --root "$MUT35" --quiet

# ── 65. MUTATED (L56): the EMPTY-DICT return ───────────────────────────────
# A SEPARATE arm from L55 in both analysers (`ast.Dict` has `keys`, not
# `elts`, so the container arm cannot cover it; the text scanner lists `{}`
# as its own value). Measured: deleting the `ast.Dict and not value.keys`
# arm SURVIVED the suite (127 OK / 0 FAIL / exit 0), ast=1 -> ast=0.
MUT36="$TMP/mut36"
mkfixture "$MUT36"
cat > "$MUT36/empty_dict_default.py" <<'PY'
def load_config(path):
    try:
        return _parse(path)
    except Exception:
        return {}
PY
expect_fail "L56 an EMPTY dict return ('return {}') is a silent default — a separate arm from the empty-sequence one" \
    bash "$GATE_SCRIPT" --root "$MUT36" --quiet
expect_fail "L56 (degraded text-fallback mode — where '{}' is its own listed value)" \
    gate_textmode --root "$MUT36" --quiet

# ── 66. MUTATED (L57): the BARE `return` ───────────────────────────────────
# The FIRST arm of is_trivial_literal (`value is None` — an `ast.Return`
# with no value at all), and the text scanner's own `^return$` branch.
# Nothing anywhere pinned either. Measured: disabling the AST arm SURVIVED
# the suite (127 OK / 0 FAIL / exit 0), ast=1 -> ast=0; disabling the text
# branch SURVIVED too, text=1 -> text=0. `except Exception: return` hands
# the caller None while looking deliberate.
MUT37="$TMP/mut37"
mkfixture "$MUT37"
cat > "$MUT37/bare_return_default.py" <<'PY'
def load_user(path):
    try:
        return _parse(path)
    except Exception:
        return
PY
expect_fail "L57 a BARE 'return' in a handler is a silent default — it hands back None while looking deliberate" \
    bash "$GATE_SCRIPT" --root "$MUT37" --quiet
expect_fail "L57 (degraded text-fallback mode — the scanner's bare-return branch)" \
    gate_textmode --root "$MUT37" --quiet

# ── 67. MUTATED (L58): the ELLIPSIS handler body ───────────────────────────
# `except Exception: ...` is `pass` wearing a stub's clothes, and BOTH
# analysers have a dedicated branch for it (the AST an `ast.Expr` holding a
# `Constant` that IS `Ellipsis`; the text scanner a `body == "..."` half).
# L1 pins `pass` and pins NEITHER. Measured: disabling the AST Ellipsis
# branch SURVIVED the suite (127 OK / 0 FAIL / exit 0), ast=1 -> ast=0;
# dropping the text half SURVIVED too, text=1 -> text=0.
MUT38="$TMP/mut38"
mkfixture "$MUT38"
cat > "$MUT38/ellipsis_body.py" <<'PY'
def load_index(path):
    try:
        return _parse(path)
    except Exception:
        ...
PY
expect_fail "L58 an ELLIPSIS handler body ('except Exception: ...') swallows exactly as 'pass' does" \
    bash "$GATE_SCRIPT" --root "$MUT38" --quiet
expect_fail "L58 (degraded text-fallback mode — the scanner's '...' half)" \
    gate_textmode --root "$MUT38" --quiet

# ── 68. MUTATED (L59): the EXCEPT-GROUP node type (TryStar) ────────────────
# The analyser's Try tuple is built defensively as
# `(ast.Try, ast.TryStar)` filtered for availability, so a `try:` /
# `except* E:` block (PEP 654, Python 3.11+) is in scope. Nothing pinned
# that the TryStar member is actually there. Measured: dropping TryStar from
# the tuple SURVIVED the suite (127 OK / 0 FAIL / exit 0), ast=1 -> ast=0.
#
# HONEST BOUNDARY (§11.4.6) — this fixture carries an AST assertion ONLY.
# The TEXT scanner is MEASURED BLIND to `except*` on the shipped gate
# (ast=1 / text=0): its handler pattern requires whitespace or a colon
# straight after `except`, and `except*` supplies a star. That is a
# PRE-EXISTING gap in the degraded fallback, NOT something this fixture
# introduced, and it sits inside the fallback's declared caveat. It is
# deliberately NOT pinned with an `expect_pass` text assertion: doing so
# would freeze the blindness as though it were correct behaviour and make a
# future fix fail this harness. It is recorded in the boundary block at the
# head of this file as owed work instead.
MUT39="$TMP/mut39"
mkfixture "$MUT39"
cat > "$MUT39/except_group.py" <<'PY'
def load_all(path):
    try:
        return _parse(path)
    except* ValueError:
        pass
PY
expect_fail "L59 an EXCEPT-GROUP handler ('except* E:') swallows too — the TryStar node type must be in scope" \
    bash "$GATE_SCRIPT" --root "$MUT39" --quiet


# ── 69. NEGATIVE CONTROL (L60): is_docstring's STRING-CONSTANT test ────────
# `is_docstring` filters a leading string Expr out of the handler body so a
# documented handler is judged on its real statements (L38 pins that a
# docstring must not HIDE a `pass`). Nothing pinned the CONSTANT TYPE test:
# widening it from `str` to `(str, bytes)` SURVIVED the entire suite
# (136 OK / 0 FAIL / exit 0) while flipping this fixture ast=0 -> ast=1.
# Mechanism: a non-string constant expression gets filtered out too, the
# two-statement body collapses to one, and a handler that is DOING something
# is reported as a bare swallow -- healthy code REFUSED, the §11.4.201(1)
# FAIL-bluff direction.
CLEAN30="$TMP/clean30"
mkfixture "$CLEAN30"
cat > "$CLEAN30/bytes_expr.py" <<'PY'
def load(path):
    try:
        return _parse(path)
    except Exception:
        b"note"
        pass
PY
expect_pass "L60 NEGATIVE CONTROL — only a STRING constant is a docstring; a bytes expression is a real statement" \
    bash "$GATE_SCRIPT" --root "$CLEAN30" --quiet
expect_pass "L60 (degraded text-fallback mode — where the body's first REAL statement is chosen)" \
    gate_textmode --root "$CLEAN30" --quiet

# ── 70. NEGATIVE CONTROL (L61): the ONE-STATEMENT body requirement ─────────
# "Two or more statements means the handler is doing something" is the single
# assumption separating a swallow from real handling, and nothing pinned it.
# Measured: relaxing `len(body) != 1` to accept two SURVIVED the entire suite
# (136 OK / 0 FAIL / exit 0) while flipping this fixture ast=0 -> ast=1.
# Mechanism: only `body[0]` is ever classified, so a handler that swallows
# AND THEN does real work is judged on its first statement alone and reported
# as a bare swallow -- healthy code REFUSED.
CLEAN31="$TMP/clean31"
mkfixture "$CLEAN31"
cat > "$CLEAN31/two_stmt.py" <<'PY'
def load(path):
    try:
        return _parse(path)
    except Exception:
        pass
        _seen.add(path)
PY
expect_pass "L61 NEGATIVE CONTROL — a TWO-statement handler is doing work; only body[0] is classified, so the count must gate it" \
    bash "$GATE_SCRIPT" --root "$CLEAN31" --quiet
expect_pass "L61 (degraded text-fallback mode)" \
    gate_textmode --root "$CLEAN31" --quiet

# ── 71. NEGATIVE CONTROL (L62): the DOTTED attribute is a WHOLE name ───────
# L24 pins that `try_suppress(` is not `suppress(` -- but only for the BARE
# call, and only in the text scanner. The AST analyser's dotted arm compares
# `func.attr == "suppress"` and nothing pinned that the comparison is WHOLE.
# Measured: relaxing it to `.endswith("suppress")` SURVIVED the entire suite
# (136 OK / 0 FAIL / exit 0) while flipping this fixture ast=0 -> ast=1 --
# healthy code REFUSED. This is L24's asymmetry closed: the same defect class
# was pinned on one analyser and one call shape only.
CLEAN32="$TMP/clean32"
mkfixture "$CLEAN32"
cat > "$CLEAN32/attr_suffix.py" <<'PY'
import contextlib


def run(path):
    with contextlib.resuppress(Exception):
        return open(path).read()
PY
expect_pass "L62 NEGATIVE CONTROL — a dotted attribute ENDING in 'suppress' is not the attribute 'suppress' (AST twin of L24)" \
    bash "$GATE_SCRIPT" --root "$CLEAN32" --quiet
expect_pass "L62 (degraded text-fallback mode)" \
    gate_textmode --root "$CLEAN32" --quiet

# ── 72. MUTATED (L63): the DOTTED exception ARGUMENT ───────────────────────
# `suppress(builtins.Exception)` is the flagship violation written with a
# qualified name -- ordinary in any module that imports `builtins` or a
# project `exceptions` module. Every existing breadth fixture passes the
# class as a BARE name, so the analyser's Attribute arm (`name = arg.attr`)
# was unpinned. Measured: blanking that arm SURVIVED the entire suite
# (136 OK / 0 FAIL / exit 0) while flipping this fixture ast=1 -> ast=0.
#
# This is the SILENT-MISS direction, and the mechanism makes it worse than a
# plain miss: the arm does not fall through to the `unresolved` branch, so
# the conservative-safe refusal of §11.4.201(4) never fires either. The call
# is classified as NARROW -- a bounded, declared tolerance -- and the
# violation is dropped with no trace at all.
MUT40="$TMP/mut40"
mkfixture "$MUT40"
cat > "$MUT40/dotted_broad.py" <<'PY'
import builtins
from contextlib import suppress


def run(path):
    with suppress(builtins.Exception):
        return open(path).read()
PY
expect_fail "L63 a DOTTED broad exception ('suppress(builtins.Exception)') is the same violation as the bare name" \
    bash "$GATE_SCRIPT" --root "$MUT40" --quiet
expect_fail "L63 (degraded text-fallback mode — where the breadth scan reads the qualified tail)" \
    gate_textmode --root "$MUT40" --quiet

# ═══════════════════════════════════════════════════════════════════════════
# BOB-213 / BOB-214 / BOB-216 fixtures (three related defects in this same
# gate, fixed together — see constitution/scripts/gates/
# cm_dangerous_combination_fail_closed.sh header "SHELL COUNTERPART (BOB-213)"
# + "MODE-INDEPENDENT CARRIERS" sections for the design rationale).
# ═══════════════════════════════════════════════════════════════════════════

# ── 73. NEGATIVE CONTROL (L64 / CLEAN33): BOB-216 — a COMMENT quoting the ──
# credential-default anti-pattern is NOT a live credential default.
# Pre-fix, BOTH modes reported this as a LIVE violation (measured: a `#`
# comment describing "never write `api_key = loaded_value or \"literal\"`"
# as an example-of-what-not-to-do was matched by the raw shape-(B) grep,
# which has no AST counterpart in any mode to fall back on) — the same
# false-positive class L5 already pins for the swallowed-exception shape,
# now closed for the credential-default shape via same-line comment/string
# masking (sanitize_generic_carriers) before the shape-(B) grep runs.
CLEAN33="$TMP/clean33"
mkfixture "$CLEAN33"
cat > "$CLEAN33/doc_comment.py" <<'PY'
# Anti-pattern example, DO NOT DO THIS:
#   api_key = loaded_value or "sk-hardcoded-fallback-secret"
def load_config():
    return {}
PY
expect_pass "L64 NEGATIVE CONTROL — a COMMENT quoting the credential-default anti-pattern is not a live default (BOB-216)" \
    bash "$GATE_SCRIPT" --root "$CLEAN33" --quiet
expect_pass "L64 (degraded text-fallback mode)" \
    gate_textmode --root "$CLEAN33" --quiet

# ── 74. NEGATIVE CONTROL (L65 / CLEAN34): BOB-216 — a COMMENT quoting the ──
# empty-catch anti-pattern is NOT a live swallowed exception. Pre-fix this
# fired in BOTH modes (measured ast_rc=1 AND text_rc=1) because the
# empty-catch grep is a language-agnostic raw-text match with NO structural
# counterpart to consult in any mode.
CLEAN34="$TMP/clean34"
mkfixture "$CLEAN34"
cat > "$CLEAN34/doc_comment.js" <<'JS'
// Anti-pattern example, DO NOT DO THIS:
//   try { risky(); } catch (e) { }
function safe() {
    return true;
}
JS
expect_pass "L65 NEGATIVE CONTROL — a COMMENT quoting the empty-catch anti-pattern is not a live swallow (BOB-216)" \
    bash "$GATE_SCRIPT" --root "$CLEAN34" --quiet
expect_pass "L65 (degraded text-fallback mode)" \
    gate_textmode --root "$CLEAN34" --quiet

# ── 75. NEGATIVE CONTROL (L66 / CLEAN35): BOB-216 — a STRING LITERAL ──
# holding the empty-catch anti-pattern TEXT is not live code. Pre-fix this
# also fired in both modes for the same reason as L65.
CLEAN35="$TMP/clean35"
mkfixture "$CLEAN35"
cat > "$CLEAN35/string_literal.js" <<'JS'
const antiPatternExample = "try { risky(); } catch (e) { }";
function log() {
    console.log(antiPatternExample);
}
JS
expect_pass "L66 NEGATIVE CONTROL — a STRING LITERAL holding the empty-catch anti-pattern text is not live code (BOB-216)" \
    bash "$GATE_SCRIPT" --root "$CLEAN35" --quiet
expect_pass "L66 (degraded text-fallback mode)" \
    gate_textmode --root "$CLEAN35" --quiet

# ── 76. MUTATED (L67 / MUT41): BOB-213 — shell parameter-expansion ──────────
# credential default to a LITERAL is a real violation, caught by the new
# shell-specific detector (`${VAR:-"literal"}` / `${VAR:="literal"}`, scoped
# to *.sh/*.bash, RHS must NOT start with `$`). Pre-fix (sh/bash absent from
# DANGEROUS_COMBO_EXT and no shell-native detector existed at all) this file
# was 100% invisible to the gate.
MUT41="$TMP/mut41"
mkfixture "$MUT41"
cat > "$MUT41/config.sh" <<'SH'
#!/usr/bin/env bash
password=${password:-"changeme"}
echo "$password"
SH
expect_fail "L67 shell credential silently defaulted to a literal via parameter expansion (BOB-213)" \
    bash "$GATE_SCRIPT" --root "$MUT41" --quiet
expect_fail "L67 (degraded text-fallback mode)" \
    gate_textmode --root "$MUT41" --quiet

# ── 77. NEGATIVE CONTROL (L68 / CLEAN36): BOB-213 — a shell credential ─────
# fallback to ANOTHER VARIABLE (`${token:-$FALLBACK_TOKEN}`) is a LEGITIMATE
# secondary-source fallback, not a literal default; the RHS-must-not-start-
# with-`$` exclusion in the shell detector must let it through.
CLEAN36="$TMP/clean36"
mkfixture "$CLEAN36"
cat > "$CLEAN36/config.sh" <<'SH'
#!/usr/bin/env bash
token=${token:-$FALLBACK_TOKEN}
echo "$token"
SH
expect_pass "L68 NEGATIVE CONTROL — shell credential fallback to ANOTHER VARIABLE is legitimate (BOB-213)" \
    bash "$GATE_SCRIPT" --root "$CLEAN36" --quiet
expect_pass "L68 (degraded text-fallback mode)" \
    gate_textmode --root "$CLEAN36" --quiet

# ── 78. NEGATIVE CONTROL (L69 / CLEAN37): BOB-213 — a shell credential ─────
# fallback to a COMMAND SUBSTITUTION (`${api_key:-$(vault_get_secret)}`) is
# likewise a legitimate secondary source, not a hardcoded literal.
CLEAN37="$TMP/clean37"
mkfixture "$CLEAN37"
cat > "$CLEAN37/config.sh" <<'SH'
#!/usr/bin/env bash
api_key=${api_key:-$(vault_get_secret)}
echo "$api_key"
SH
expect_pass "L69 NEGATIVE CONTROL — shell credential fallback to COMMAND SUBSTITUTION is legitimate (BOB-213)" \
    bash "$GATE_SCRIPT" --root "$CLEAN37" --quiet
expect_pass "L69 (degraded text-fallback mode)" \
    gate_textmode --root "$CLEAN37" --quiet

# ── 79. MUTATED (L70 / MUT42): BOB-213 — the PRE-EXISTING `||`/`or`-style ──
# credential-default shape, now visible for the first time in a `.sh` file
# because `sh`/`bash` were added to the default DANGEROUS_COMBO_EXT list.
# Measured pre-fix: `scripts/` (a declared DANGER_ROOT) has 71 tracked .sh
# files the gate never scanned at all — this fixture is the minimal
# reproduction of that class, independent of the NEW shell-native detector
# added in L67 (this shape is the gate's ORIGINAL `||`/`or` regex).
MUT42="$TMP/mut42"
mkfixture "$MUT42"
cat > "$MUT42/loader.sh" <<'SH'
#!/usr/bin/env bash
api_key=loaded_value || "sk-hardcoded-fallback-secret"
SH
expect_fail "L70 pre-existing credential-default-to-literal shape, now DISCOVERABLE in a .sh file (BOB-213 extension-list fix)" \
    bash "$GATE_SCRIPT" --root "$MUT42" --quiet
expect_fail "L70 (degraded text-fallback mode)" \
    gate_textmode --root "$MUT42" --quiet

# ── 80. NEGATIVE CONTROL (L71 / CLEAN38): BOB-214 — the gate's default ─────
# exclude list (.git/node_modules/vendor/.venv/__pycache__/scripts/gates/
# out/build) is UNCHANGED by the BOB-214 fix and still keeps a violation
# planted inside `.git/` from ever being scanned or flagged, confirming
# adding `--max-depth`/the repo-root DANGER_ROOTS entry does NOT now scan
# something wildly out-of-scope.
CLEAN38="$TMP/clean38"
mkfixture "$CLEAN38"
mkdir -p "$CLEAN38/.git/hooks"
cat > "$CLEAN38/.git/hooks/fake.py" <<'PY'
try:
    risky()
except Exception:
    pass
PY
expect_pass "L71 NEGATIVE CONTROL — a violation inside .git/ stays excluded by the default exclude list (BOB-214)" \
    bash "$GATE_SCRIPT" --root "$CLEAN38" --quiet
expect_pass "L71 (degraded text-fallback mode)" \
    gate_textmode --root "$CLEAN38" --quiet

# ── 81. NEGATIVE CONTROL (L72 / CLEAN39): BOB-214 — a NESTED-only violation ──
# is correctly invisible at `--max-depth 1` (intended narrowing, not a bug —
# this proves the flag genuinely limits traversal depth rather than silently
# being a no-op).
CLEAN39="$TMP/clean39"
mkfixture "$CLEAN39"
mkdir -p "$CLEAN39/nested"
cat > "$CLEAN39/nested/violation.py" <<'PY'
try:
    risky()
except Exception:
    pass
PY
expect_pass "L72 NEGATIVE CONTROL — a nested-only violation is invisible at --max-depth 1 (BOB-214, intended narrowing)" \
    bash "$GATE_SCRIPT" --root "$CLEAN39" --max-depth 1 --quiet
expect_pass "L72 (degraded text-fallback mode)" \
    gate_textmode --root "$CLEAN39" --max-depth 1 --quiet

# ── 82. MUTATED (L73 / MUT43): BOB-214 — a ROOT-LEVEL violation is STILL ────
# caught at `--max-depth 1` (the depth limit narrows scope, it does not
# blind the gate to the level it is pointed at — this is the exact
# webui-bridge.py-at-repo-root scenario BOB-214 fixes).
MUT43="$TMP/mut43"
mkfixture "$MUT43"
cat > "$MUT43/webui_probe.py" <<'PY'
def _is_root_liveness_probe(self):
    try:
        parsed = urllib.parse.urlparse(self.path)
    except Exception:
        return False
    return True
PY
expect_fail "L73 a ROOT-LEVEL violation is still caught at --max-depth 1 (BOB-214)" \
    bash "$GATE_SCRIPT" --root "$MUT43" --max-depth 1 --quiet
expect_fail "L73 (degraded text-fallback mode)" \
    gate_textmode --root "$MUT43" --max-depth 1 --quiet

# ── 83. ARGUMENT VALIDATION (L74): BOB-214 — an invalid --max-depth value ──
# is REFUSED with an environment/argument exit (rc=2), never silently
# accepted as 0/unlimited nor crashing find(1) with a confusing error. This
# is asserted directly (not via expect_fail/expect_pass) because BOTH of
# those helpers treat rc=2 as a WRONG-ROUTE failure by design (§11.4.201: an
# argument error is not a detection) — exactly the outcome under test here,
# so the real rc is read and graded on its own terms instead.
_l74_out="$(bash "$GATE_SCRIPT" --root "$TMP" --max-depth notanumber --quiet 2>&1)"; _l74_rc=$?
if [ "$_l74_rc" -eq 2 ]; then
    echo "✅ META OK:   L74 --max-depth with a non-numeric value exits 2 (argument error) (BOB-214)"
else
    echo "❌ META FAIL: L74 --max-depth notanumber exited ${_l74_rc}, expected 2 (argument error)"
    rc=1
fi

# ── 84. MUTATED (L75 / MUT44): BOB-199 — a NARROW suppress() combined with ──
# an IRREVERSIBLE-capability call (os.remove) under an UNRELATED exception
# class is a real fail-open shape: `PermissionError` names a DIFFERENT
# failure than "the file to be removed does not exist", so the delete still
# runs unconditionally and any OTHER exception the narrow suppress lets
# through is silently swallowed around a destructive call. Per the §11.4.66
# operator decision (2026-08-26): "The scanner flags a narrow
# contextlib.suppress ONLY when combined with an irreversible capability
# (delete / truncate / kill) -- the shape that actually causes harm." This is
# exactly that shape and MUST be caught.
MUT44="$TMP/mut44"
mkfixture "$MUT44"
cat > "$MUT44/l75.py" <<'PY'
import contextlib
import os

def do_thing(path):
    with contextlib.suppress(PermissionError):
        os.remove(path)
PY
expect_fail "L75 narrow suppress(PermissionError) around os.remove — BOB-199 irreversible-capability shape" \
    bash "$GATE_SCRIPT" --root "$MUT44" --quiet
# HONEST SCOPE BOUNDARY (§11.4.6): BOB-199's narrow+irreversible detection
# lives ENTIRELY in the Python AST-structural analyser -- the task's own
# scope statement names exactly "classify_suppress and its surrounding
# AST-mode machinery". The degraded text-fallback scanner
# (scan_py_text_suppress) still implements ONLY the pre-existing BROAD-form
# detection; teaching it to also resolve exception-name bindings and walk a
# with-block body for an irreversible call is a distinct, materially larger
# change and is explicitly OUT OF SCOPE here. This is a DISCLOSED gap
# consistent with the pre-existing TEXT_MODE_CAVEAT (already on record as an
# approximation that under-reports in several measured ways), never a
# silent one -- and it is PROVEN below, not merely asserted: this exact
# fixture (a NARROW suppress, so the broad-form scanner never fires, over a
# call the text scanner has no irreversible-capability concept for at all)
# genuinely produces no hit in degraded mode.
expect_pass "L75 (degraded text-fallback mode — KNOWN, DISCLOSED gap: narrow+irreversible detection is AST-mode only, per BOB-199 scope)" \
    gate_textmode --root "$MUT44" --quiet

# ── 85. NEGATIVE CONTROL (L76 / CLEAN40): BOB-199 — the CANONICAL Python ────
# stdlib delete-if-absent idiom (`with suppress(FileNotFoundError):
# os.remove(path)`) is the LITERAL example given by contextlib.suppress's own
# official documentation, and appears three times already in THIS fixture
# file (L1/L13/L20/L24-class `purge()` helpers used as realistic safe filler
# for unrelated fixtures) as unremarkable, obviously-safe code. Flagging it
# would be precisely the false-positive storm the §11.4.66 operator decision
# itself warns against: "Idiomatic narrow tolerances stay quiet, so the gate
# keeps its credibility." The suppressed exception here names the EXACT "the
# thing is already gone" condition os.remove would otherwise raise, so
# re-raising it would make the with-block pointless -- this MUST stay quiet.
CLEAN40="$TMP/clean40"
mkfixture "$CLEAN40"
cat > "$CLEAN40/l76.py" <<'PY'
import contextlib
import os

def purge(path):
    with contextlib.suppress(FileNotFoundError):
        os.remove(path)
PY
expect_pass "L76 NEGATIVE CONTROL — the canonical stdlib delete-if-absent idiom (suppress(FileNotFoundError): os.remove) stays quiet" \
    bash "$GATE_SCRIPT" --root "$CLEAN40" --quiet
expect_pass "L76 (degraded text-fallback mode)" \
    gate_textmode --root "$CLEAN40" --quiet

# ── 86. MUTATED (L77 / MUT45): BOB-199 — `os.kill` combined with a NARROW ───
# suppress(FileNotFoundError) MUST still be flagged, even though the SAME
# exception class is quiet over os.remove/unlink/rmtree at L76. There is no
# "the process is already gone" idiom that makes swallowing an unrelated
# signal-delivery failure around a kill() call safe the way FileNotFoundError
# is safe around a delete -- kill/killpg/truncate stay ALWAYS-flagged
# regardless of which exception the narrow suppress names, per the
# call_is_irreversible() DELETE_IF_ABSENT_ATTRS exclusion being scoped to
# exactly {remove, unlink, rmtree}, never {kill, killpg, truncate}.
MUT45="$TMP/mut45"
mkfixture "$MUT45"
cat > "$MUT45/l77.py" <<'PY'
import contextlib
import os

def stop(pid):
    with contextlib.suppress(FileNotFoundError):
        os.kill(pid, 9)
PY
expect_fail "L77 narrow suppress(FileNotFoundError) around os.kill — kill is ALWAYS flagged, no delete-if-absent idiom applies" \
    bash "$GATE_SCRIPT" --root "$MUT45" --quiet
# Same HONEST SCOPE BOUNDARY as L75 above: narrow+irreversible detection is
# AST-mode only (BOB-199 scope), a DISCLOSED gap in the degraded scanner.
expect_pass "L77 (degraded text-fallback mode — KNOWN, DISCLOSED gap, same as L75)" \
    gate_textmode --root "$MUT45" --quiet

# ── 87. NEGATIVE CONTROL (L78 / CLEAN41): BOB-199 — a VALID `# guardrails: ──
# allow <reason>` waiver on a narrow-suppress+irreversible-capability site
# MUST silence the FAIL and produce a WAIVED note instead (never silent per
# §11.4.201(5)) using the project's established per-line waiver convention
# (the same `check_cm_no_production_mutation_residue.sh` marker shape).
CLEAN41="$TMP/clean41"
mkfixture "$CLEAN41"
cat > "$CLEAN41/l78.py" <<'PY'
import contextlib
import os

def do_thing(path):
    with contextlib.suppress(PermissionError):  # guardrails:allow reviewed and accepted by ops 2026-09
        os.remove(path)
PY
expect_pass "L78 NEGATIVE CONTROL — a VALID guardrails:allow waiver silences the narrow+irreversible FAIL" \
    bash "$GATE_SCRIPT" --root "$CLEAN41" --quiet
# NOT asserted in degraded mode here: the waiver mechanism itself lives in
# the AST-structural path (it resolves source_lines + call.lineno from the
# parsed tree), so a degraded-mode PASS on this fixture would be true for
# the WRONG reason -- text mode is already blind to the underlying narrow+
# irreversible shape (per L75/L77's disclosed gap) and never reaches a
# waiver decision at all. Asserting it here would misleadingly imply
# degraded-mode waiver support that does not exist (§11.4.6).
expect_output_contains "L78 the WAIVED note names the waiver reason, never silent (§11.4.201(5))" \
    "reviewed and accepted by ops 2026-09" \
    bash "$GATE_SCRIPT" --root "$CLEAN41"

# ── 88. MUTATED (L79 / MUT46): BOB-199 — a MALFORMED waiver (the marker is ──
# present but carries NO REASON) MUST NOT silence the FAIL -- §11.4.224(E)
# requires a mandatory, non-empty reason on every waiver; a bare marker with
# nothing after it is indistinguishable from an operator forgetting to
# finish the comment, and honouring it would reopen the exact silent-bypass
# channel the waiver convention exists to close.
MUT46="$TMP/mut46"
mkfixture "$MUT46"
cat > "$MUT46/l79.py" <<'PY'
import contextlib
import os

def do_thing(path):
    with contextlib.suppress(PermissionError):  # guardrails:allow
        os.remove(path)
PY
expect_fail "L79 a MALFORMED guardrails:allow waiver (marker present, no reason) does NOT silence the FAIL" \
    bash "$GATE_SCRIPT" --root "$MUT46" --quiet
# NOT asserted expect_fail in degraded mode: same disclosed AST-mode-only
# boundary as L75/L77/L78 -- the malformed-waiver check lives entirely in
# the Python AST path, so text mode is blind to this fixture's shape too
# and would trivially PASS (clean) here, not because the malformed waiver
# was honoured but because the underlying narrow+irreversible violation is
# never detected in the first place. Asserted honestly below instead.
expect_pass "L79 (degraded text-fallback mode — KNOWN, DISCLOSED gap, same as L75/L77)" \
    gate_textmode --root "$MUT46" --quiet

# ── 89. MUTATED (L80): BOB-200 — a `find(1)` ENUMERATION FAILURE (a subtree ──
# `chmod 000` under --root, so find(1) cannot descend into it and exits
# non-zero) MUST be refused as an unresolved precondition (rc=1, a FINDING),
# NEVER silently read as "find succeeded, zero files" (the honest
# topology_unsupported SKIP path, rc=0). Before the fix, `find ... | mapfile`
# fed find's output through a process substitution that discarded find's own
# exit status -- mapfile always saw *some* stream (even an empty one) and
# reported success, so a permission-denied/resource-exhausted/interrupted
# scan silently downgraded from "the corpus could not be fully enumerated"
# to "the corpus is empty and clean" -- a textbook §11.4.201(6) false-null /
# §11.4.252 fail-open. This fixture RED-reproduces exactly that on the
# CURRENT (pre-fix) gate shape, and is retained here as the permanent
# regression guard for the fix.
MUT47="$TMP/mut47"
mkfixture "$MUT47"
mkdir -p "$MUT47/blocked"
cat > "$MUT47/blocked/violation.py" <<'PY'
import contextlib
with contextlib.suppress(Exception):
    pass
PY
chmod 000 "$MUT47/blocked"
# Restore permissions in a trap-local so a failed assertion still leaves the
# fixture tree removable by the suite's top-level `cleanup` on EXIT --
# `rm -rf` only needs write+execute on the PARENT (mkfixture's own dir) to
# unlink a directory entry, but a defensive restore is cheap and honest.
restore_l80_perms() { chmod 755 "$MUT47/blocked" 2>/dev/null || true; }
trap restore_l80_perms RETURN 2>/dev/null || true
_l80_out="$(bash "$GATE_SCRIPT" --root "$MUT47" --quiet 2>&1)"; _l80_rc=$?
restore_l80_perms
if [ "$_l80_rc" -eq 1 ]; then
    echo "✅ META OK:   L80 a find(1) enumeration failure (permission-denied subtree) is refused as an unresolved precondition (rc=1), never a silent empty-scan SKIP (BOB-200/§11.4.201(6))"
else
    echo "❌ META FAIL: L80 find-enumeration-failure exited ${_l80_rc}, expected rc=1 (a FINDING) -- a permission-denied subtree must not silently read as an empty/clean scan"
    rc=1
fi
if printf '%s' "$_l80_out" | grep -qF -- "scan enumeration failed"; then
    echo "✅ META OK:   L80 the refusal names the unresolved precondition (\"scan enumeration failed\"), never silent"
else
    echo "❌ META FAIL: L80 expected the find-failure output to contain: scan enumeration failed"
    rc=1
fi

# ── 90. NEGATIVE CONTROL (L81): BOB-200 — after the find-failure fix, a ─────
# NORMAL violation directly under --root (no permission-denied subtree
# anywhere in the tree) is STILL caught exactly as before -- the scratch-file
# capture of find(1)'s own exit status does not itself introduce a new
# blind spot on the ordinary success path. CLEAN4 (section 7) already pins
# the sibling golden-FALSE (a genuinely empty, fully-readable root honestly
# SKIPs at rc=0) -- this fixture is the MUTATED-polarity regression check
# for the same code path, proving the fix did not trade a false-null for a
# false-refusal on healthy input.
MUT48="$TMP/mut48"
mkfixture "$MUT48"
cat > "$MUT48/l81.py" <<'PY'
import contextlib
with contextlib.suppress(Exception):
    pass
PY
expect_fail "L81 a normal violation is still caught after the BOB-200 find-failure fix (no permission-denied subtree present)" \
    bash "$GATE_SCRIPT" --root "$MUT48" --quiet
expect_fail "L81 (degraded text-fallback mode)" \
    gate_textmode --root "$MUT48" --quiet

echo "======================================================================"
if [ "$rc" -eq 0 ]; then
    echo "✅ META PASS — CM-DANGEROUS-COMBINATION-FAIL-CLOSED FAILs-on-mutation AND PASSes-on-clean for every fixture (§1.1 proof holds)"
else
    echo "❌ META FAIL — CM-DANGEROUS-COMBINATION-FAIL-CLOSED is a bluff gate (did not FAIL on a mutation, or failed a clean fixture)"
fi
echo "META_EXIT=$rc"
exit "$rc"
