#!/usr/bin/env bash
# cm_relocated_anchor_copies_lockstep_mutation_test.sh -- paired §1.1 mutation test for
# CM-RELOCATED-ANCHOR-COPIES-LOCKSTEP (scripts/gates/cm_relocated_anchor_copies_lockstep.sh).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# The gate only counts exact byte occurrences of pinned strings (see its header). This test proves
# every part of it can refuse, with an ENUMERATED, HAND-WRITTEN mutant set and no generator:
#   * CODE mutants: whole-line replacements of the gate. Every non-comment line of the gate (the
#     shebang included) must be the original line of at least one code mutant, every such line must
#     occur exactly once in the gate, and every mutant's original line must still occur exactly once.
#     So ANY edit of a gate line (for example a `startswith` turned into `in`, or a `.lower()`
#     added) or any added line FAILs this test until its mutants are rewritten against the new text.
#   * DATA mutants: every row of relocated_copies_lockstep.tsv is deleted and has its count changed,
#     and every boundary byte of every pinned string is removed (the line-start newline of each
#     marker, the trailing newline of the clause and of the carrier, each space around the mandate),
#     and the pinned clause is truncated before its last paragraph.
#   * CASES: real-tree copies with one defect each (rc 1), golden-FALSE trees that must PASS (rc 0),
#     and BLIND inputs (rc 2). Each case states its expected rc and a substring of its expected
#     output, checked against the REAL gate first.
#   A mutant is KILLED when, on at least one case, its (exit code, stdout, stderr) differs from the
#   real gate's. Each mutant also names the case(s) designed to kill it, and must be killed by them.
#   Every gate run gets its own fresh temporary directory (tempfile.mkdtemp), so two runs can never
#   share a file whatever their labels (issuerule_r6 R6-2).
#   Negative controls: NC1 an identity mutant must survive; NC2 an identity mutant and an
#   always-PASS mutant with the same label, run concurrently, must be attributed independently;
#   NC3 a mutant whose original line is absent must be refused as stillborn; NC4 the coverage check
#   must report an added gate line and an edited gate line.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_relocated_anchor_copies_lockstep_mutation_test.sh [--root DIR] [--jobs N]
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 every case behaves as declared on the real gate, every mutant is killed by its designated
#     case(s), coverage is complete and every negative control holds.
#   1 any of those does not hold (every problem is printed).
#   2 BLIND: python3 unusable, an input file missing, or run as uid 0 (the permission-denied case
#     cannot be produced).
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Temporary directories under $TMPDIR, removed on exit. The real tree is only read.
command -v python3 >/dev/null || { echo "CM-RELOCATED-ANCHOR-COPIES-LOCKSTEP mutation test: BLIND -- python3 not usable"; exit 2; }
exec python3 -I - "$(cd "$(dirname "$0")/../.." && pwd)" "$@" <<'PY'
import concurrent.futures, os, shutil, subprocess, sys, tempfile

T = "CM-RELOCATED-ANCHOR-COPIES-LOCKSTEP mutation test"
argv = sys.argv[1:]
ROOT, JOBS = argv[0], 16
rest = argv[1:]
while rest:
    if rest[0] == "--root" and len(rest) > 1:
        ROOT, rest = rest[1], rest[2:]
    elif rest[0] == "--jobs" and len(rest) > 1 and rest[1].isdigit():
        JOBS, rest = int(rest[1]), rest[2:]
    else:
        print(f"{T}: BLIND -- usage: [--root DIR] [--jobs N]"); sys.exit(2)
if os.geteuid() == 0:
    print(f"{T}: BLIND -- refusing to run as uid 0 (case B12 needs a permission denial)"); sys.exit(2)

GATE = "scripts/gates/cm_relocated_anchor_copies_lockstep.sh"
DECL = "scripts/gates/relocated_copies_lockstep.tsv"
PD = "scripts/gates/relocated_copies/"
CLAUSE, CMARK, CARRIER, KMARK, MANDATE, SPACED = (PD + n for n in ("102e_clause.txt", "102e_clause_marker.txt", "102e_carrier.txt", "102e_carrier_marker.txt", "102e_mandate.txt", "102e_mandate_spaced.txt"))
CON, CAF, GRP = "Constitution.md", "CLAUDE_ANCHORS_FULL.md", "groups/project-lifecycle-and-release.md"
CORE = ("CLAUDE.md", "AGENTS.md", "QWEN.md", "GEMINI.md")
FILES = [GATE, DECL, CLAUSE, CMARK, CARRIER, KMARK, MANDATE, SPACED, CON, CAF, GRP, *CORE]
base = {}
for rel in FILES:
    try:
        with open(os.path.join(ROOT, rel), "rb") as fh:
            base[rel] = fh.read()
    except OSError as err:
        print(f"{T}: BLIND -- {rel}: {err.strerror}"); sys.exit(2)
problems = []
TOP = tempfile.mkdtemp(prefix="relocated_lockstep_mt_")
BASEDIR = os.path.join(TOP, "base")
for rel, data in base.items():
    os.makedirs(os.path.dirname(os.path.join(BASEDIR, rel)), exist_ok=True)
    with open(os.path.join(BASEDIR, rel), "wb") as fh:
        fh.write(data)
NOPY = os.path.join(TOP, "nopython-path")
os.makedirs(NOPY)
os.symlink(shutil.which("dirname"), os.path.join(NOPY, "dirname"))
BASH = shutil.which("bash")
DIR, MODE000 = object(), object()   # special tree values: replace with a directory / write and chmod 000

# ── helpers that build a case tree from the base tree ─────────────────────────
def kth(data, needle, k):
    pos = -1
    for _ in range(k):
        pos = data.find(needle, pos + 1)
        assert pos >= 0, (needle[:40], k)
    return pos

def edit_copy(t, rel, k, old, new, pin=CLAUSE):
    """Replace OLD by NEW once inside the k-th copy of the pinned string in REL."""
    p = t[pin]; s = t[rel]; i = kth(s, p, k)
    seg = s[i:i + len(p)]
    assert seg.count(old) >= 1, (rel, k, old)
    t[rel] = s[:i] + seg.replace(old, new, 1) + s[i + len(p):]

def edit_everywhere(t, rels, old, new):
    """Replace every OLD by NEW in the given files; OLD must occur only inside copies."""
    for rel in rels:
        assert t[rel].count(old) >= 1, (rel, old)
        t[rel] = t[rel].replace(old, new)

CLAUSE_FILES = (CON, CAF, GRP, CLAUSE)
CARRIER_FILES = (*CORE, CARRIER)
B = lambda s: s.encode("utf-8")

def case(cid, rc, expect, edit=None, args=None, nopython=False):
    return {"id": cid, "rc": rc, "expect": B(expect), "edit": edit, "args": args, "nopython": nopython}

def drifted(t, old=b"forbidden", new=b"permitted"):
    return t[CLAUSE].replace(old, new, 1)

def app(rel, extra):
    def f(t): t[rel] = t[rel] + extra
    return f

def setv(rel, v):
    def f(t): t[rel] = v
    return f

def rowline(f, p, c):
    return B(f"{f}\t{p}\t{c}\n")

PASS = "PASS -- 18 row(s)"
def fl(rel, pin, found, decl):
    return f"FAIL -- {rel} holds {pin} {found} time(s), declared {decl}"

CASES = [
    # golden: must PASS
    case("G00", 0, PASS),
    case("G01_default_root", 0, PASS, args=[]),
    case("G02a_midline_cite_clause", 0, PASS, app(CON, B("A later line cites **(E) EVERY ISSUE THAT SURFACES DURING WORK mid-line.\n"))),
    case("G02b_midline_cite_carrier", 0, PASS, lambda t: t.__setitem__("CLAUDE.md", t["CLAUDE.md"].replace(b"\n", B("\nSee **EXTENSION landed 2026-10-15 — §11.4.102(E) mid-line.\n"), 1))),
    case("G03_midbody_start_everywhere", 0, PASS, lambda t: edit_everywhere(t, CLAUSE_FILES, B("**What an issue is.** "), B("**What an issue is.** (cited mid-line: **(E) EVERY ISSUE THAT SURFACES DURING WORK) "))),
    case("G04_count_zero_row", 0, "PASS -- 19 row(s)", app(DECL, rowline("QWEN.md", CLAUSE, 0))),
    case("G05_blank_and_comment_rows", 0, PASS, lambda t: t.__setitem__(DECL, t[DECL].replace(b"\nConstitution.md", b"\n\n#x comment\n\nConstitution.md", 1))),
    # defects: must FAIL
    case("F01_canon_same_length", 1, fl(CON, CLAUSE, 0, 1), lambda t: edit_copy(t, CON, 1, b"forbidden", b"permitted")),
    case("F02_caf3_same_length", 1, fl(CAF, CLAUSE, 3, 4), lambda t: edit_copy(t, CAF, 3, b"forbidden", b"permitted")),
    case("F03_caf2_double_space", 1, fl(CAF, CLAUSE, 3, 4), lambda t: edit_copy(t, CAF, 2, b"is tracked", b"is  tracked")),
    case("F04_caf4_case", 1, fl(CAF, CLAUSE, 3, 4), lambda t: edit_copy(t, CAF, 4, b"NOT closable", b"not closable")),
    case("F05_caf2_boundary_drift", 1, fl(CAF, CLAUSE, 3, 4), lambda t: edit_copy(t, CAF, 2, b"is not claimed shipped", b"is claimed shipped")),
    case("F06_group_drift", 1, fl(GRP, CLAUSE, 0, 1), lambda t: edit_copy(t, GRP, 1, b"forbidden", b"permitted")),
    case("F07_canon_extra_drifted", 1, fl(CON, CMARK, 2, 1), lambda t: t.__setitem__(CON, t[CON] + b"\n" + drifted(t))),
    case("F08_caf_fifth_drifted", 1, fl(CAF, CMARK, 5, 4), lambda t: t.__setitem__(CAF, t[CAF] + b"\n" + drifted(t))),
    case("F09_caf_fifth_exact", 1, fl(CAF, CLAUSE, 5, 4), lambda t: t.__setitem__(CAF, t[CAF] + b"\n" + t[CLAUSE])),
    case("F10_dup_canon", 1, fl(CON, CLAUSE, 2, 1), lambda t: t.__setitem__(CON, t[CON] + b"\n" + t[CLAUSE])),
    case("F11_group_extra_drifted", 1, fl(GRP, CMARK, 2, 1), lambda t: t.__setitem__(GRP, t[GRP] + b"\n" + drifted(t))),
    case("F12_caf1_crlf", 1, fl(CAF, CLAUSE, 3, 4), lambda t: (lambda i: t.__setitem__(CAF, t[CAF][:i] + t[CLAUSE].replace(b"\n", b"\r\n") + t[CAF][i + len(t[CLAUSE]):]))(kth(t[CAF], t[CLAUSE], 1))),
    case("F13_caf2_lone_cr", 1, fl(CAF, CLAUSE, 3, 4), lambda t: edit_copy(t, CAF, 2, b"is tracked", b"is\rtracked")),
    case("F14_caf2_trailing_glue", 1, fl(CAF, CLAUSE, 3, 4), lambda t: edit_copy(t, CAF, 2, b"flag.\n", b"flag. X\n")),
    case("F15_midbody_end_then_drift", 1, fl(CAF, CLAUSE, 3, 4), lambda t: (edit_everywhere(t, CLAUSE_FILES, B("**What an issue is.** "), B("**What an issue is.** (see **Clause (E) honest boundary below) ")), edit_copy(t, CAF, 3, b"is not claimed shipped", b"is claimed shipped"))),
    case("F16_caf1_leading_glue", 1, fl(CAF, CMARK, 3, 4), lambda t: edit_copy(t, CAF, 1, b"**(E) EVERY", b"X**(E) EVERY")),
] + [
    case(f"F17_{f[:-3].lower()}_carrier_changed", 1, fl(f, CARRIER, 0, 1), (lambda f: lambda t: edit_copy(t, f, 1, b"canonical text governs", b"canonical text ignores", CARRIER))(f)) for f in CORE
] + [
    case(f"F21_{f[:-3].lower()}_carrier_leading_space", 1, fl(f, KMARK, 0, 1), (lambda f: lambda t: t.__setitem__(f, t[f].replace(B("\n**EXTENSION landed 2026-10-15 — §11.4.102(E)"), B("\n **EXTENSION landed 2026-10-15 — §11.4.102(E)"))))(f)) for f in CORE
] + [
    case("F25_gemini_carrier_trailing_space", 1, fl("GEMINI.md", CARRIER, 0, 1), lambda t: t.__setitem__("GEMINI.md", t["GEMINI.md"][:-1] + b"  \n")),
    case("F26_agents_carrier_case", 1, fl("AGENTS.md", CARRIER, 0, 1), lambda t: edit_copy(t, "AGENTS.md", 1, b"Summary (the canonical", b"summary (the canonical", CARRIER)),
    case("F27_claude_carrier_crlf", 1, fl("CLAUDE.md", CARRIER, 0, 1), lambda t: t.__setitem__("CLAUDE.md", t["CLAUDE.md"][:-1] + b"\r\n")),
    case("F28_mandate_lowered_in_clause_everywhere", 1, fl(CLAUSE, MANDATE, 0, 1), lambda t: edit_everywhere(t, CLAUSE_FILES, t[MANDATE], t[MANDATE].lower())),
    case("F29_mandate_lowered_in_carrier_everywhere", 1, fl(CARRIER, MANDATE, 0, 1), lambda t: edit_everywhere(t, CARRIER_FILES, t[MANDATE], t[MANDATE].lower())),
    case("F30_mandate_glued_before", 1, fl(CLAUSE, SPACED, 0, 1), lambda t: edit_everywhere(t, CLAUSE_FILES, b' "Any issues', b'X"Any issues')),
    case("F31_mandate_glued_after", 1, fl(CLAUSE, SPACED, 0, 1), lambda t: edit_everywhere(t, CLAUSE_FILES, b'yet!" ', b'yet!"X')),
    case("F32_mandate_pasted_twice", 1, fl(CLAUSE, MANDATE, 2, 1), lambda t: edit_everywhere(t, CLAUSE_FILES, t[MANDATE], t[MANDATE] + b" " + t[MANDATE])),
    case("F33_carrier_mandate_pasted_twice", 1, fl(CARRIER, MANDATE, 2, 1), lambda t: edit_everywhere(t, CARRIER_FILES, t[MANDATE], t[MANDATE] + b" " + t[MANDATE])),
    case("F34_carrier_mandate_glued_after", 1, fl(CARRIER, SPACED, 0, 1), lambda t: edit_everywhere(t, CARRIER_FILES, b'yet!" ', b'yet!"X')),
    # BLIND: must refuse with rc 2
    case("B01_no_python", 2, "BLIND -- python3 not usable", nopython=True),
    case("B02_unknown_option", 2, "BLIND -- usage", args=["--rootx", "{RUN}"]),
    case("B03_extra_argument", 2, "BLIND -- usage", args=["--root", "{RUN}", "extra"]),
    case("B04_decl_missing", 2, f"BLIND -- {DECL} is not readable (No such file or directory)", setv(DECL, None)),
    case("B05_decl_no_row", 2, f"BLIND -- {DECL} declares no row", setv(DECL, b"# only a comment\n\n")),
    case("B06_row_two_fields", 2, "malformed row", app(DECL, b"QWEN.md\t1\n")),
    case("B07_row_four_fields", 2, "malformed row", app(DECL, rowline("QWEN.md", CARRIER, "1\textra"))),
    case("B08_row_empty_file", 2, "malformed row", app(DECL, rowline("", CARRIER, 1))),
    case("B09_row_empty_pinned", 2, "malformed row", app(DECL, rowline("QWEN.md", "", 1))),
    case("B10a_row_count_word", 2, "malformed row", app(DECL, rowline("QWEN.md", CARRIER, "x"))),
    case("B10b_row_count_cr", 2, "malformed row", app(DECL, rowline("QWEN.md", CARRIER, "1\r"))),
    case("B10c_row_count_negative", 2, "malformed row", app(DECL, rowline("QWEN.md", CARRIER, "-1"))),
    case("B11_file_missing", 2, "BLIND -- QWEN.md is not readable (No such file or directory)", setv("QWEN.md", None)),
    case("B12_file_unreadable", 2, "BLIND -- GEMINI.md is not readable (Permission denied)", setv("GEMINI.md", MODE000)),
    case("B13_file_is_directory", 2, "BLIND -- AGENTS.md is not readable (Is a directory)", setv("AGENTS.md", DIR)),
    case("B14_pinned_empty", 2, f"BLIND -- {KMARK} is empty", setv(KMARK, b"")),
    case("B15_pinned_missing", 2, f"BLIND -- {SPACED} is not readable (No such file or directory)", setv(SPACED, None)),
]
CASE_IDS = {c["id"] for c in CASES}
assert len(CASE_IDS) == len(CASES)

# ── mutants ───────────────────────────────────────────────────────────────────
# (id, old full line, new full line, designated killer cases, reviewer mutants it stands for)
L = '        print(f"{GATE}: FAIL -- {row[0].decode(errors=\'replace\')} holds {row[1].decode(errors=\'replace\')} {found} time(s), declared {int(row[2])}")'
CODE = [
    ("C01", '#!/usr/bin/env bash', '#!/bin/false', ["G00"], ""),
    ("C02a", 'command -v python3 >/dev/null || { echo "CM-RELOCATED-ANCHOR-COPIES-LOCKSTEP: BLIND -- python3 not usable"; exit 2; }', 'command -v python3 >/dev/null && { echo "CM-RELOCATED-ANCHOR-COPIES-LOCKSTEP: BLIND -- python3 not usable"; exit 2; }', ["G00"], ""),
    ("C02b", 'command -v python3 >/dev/null || { echo "CM-RELOCATED-ANCHOR-COPIES-LOCKSTEP: BLIND -- python3 not usable"; exit 2; }', 'command -v python3 >/dev/null || { echo "CM-RELOCATED-ANCHOR-COPIES-LOCKSTEP: BLIND -- python3 not usable"; exit 0; }', ["B01_no_python"], ""),
    ("C02c", 'command -v python3 >/dev/null || { echo "CM-RELOCATED-ANCHOR-COPIES-LOCKSTEP: BLIND -- python3 not usable"; exit 2; }', 'command -v python3 >/dev/null || { echo "CM-RELOCATED-ANCHOR-COPIES-LOCKSTEP: BLIND"; exit 2; }', ["B01_no_python"], ""),
    ("C03a", 'exec python3 -I - "$(cd "$(dirname "$0")/../.." && pwd)" "$@" <<\'PY\'', 'exec python3 -I - "$(cd "$(dirname "$0")/.." && pwd)" "$@" <<\'PY\'', ["G01_default_root"], ""),
    ("C03b", 'exec python3 -I - "$(cd "$(dirname "$0")/../.." && pwd)" "$@" <<\'PY\'', 'exec python3 -I - "$(cd "$(dirname "$0")/../.." && pwd)" <<\'PY\'', ["B02_unknown_option"], ""),
    ("C04", 'import sys', 'import os', ["G00"], ""),
    ("C05a", 'GATE, DECL = "CM-RELOCATED-ANCHOR-COPIES-LOCKSTEP", b"scripts/gates/relocated_copies_lockstep.tsv"', 'GATE, DECL = "CM-RELOCATED-ANCHOR-COPIES-LOCKSTEP", b"relocated_copies_lockstep.tsv"', ["G00"], ""),
    ("C05b", 'GATE, DECL = "CM-RELOCATED-ANCHOR-COPIES-LOCKSTEP", b"scripts/gates/relocated_copies_lockstep.tsv"', 'GATE, DECL = "CM-RELOCATED-ANCHOR-COPIES", b"scripts/gates/relocated_copies_lockstep.tsv"', ["G00"], ""),
    ("C06", 'def blind(msg):', 'def blind(message):', ["B02_unknown_option"], ""),
    ("C07", '    print(f"{GATE}: BLIND -- {msg}")', '    print(f"{GATE}: WARN -- {msg}")', ["B02_unknown_option"], "H05"),
    ("C08a", '    sys.exit(2)', '    sys.exit(0)', ["B02_unknown_option"], ""),
    ("C08b", '    sys.exit(2)', '    pass', ["B04_decl_missing"], ""),
    ("C09", 'args = sys.argv[1:]', 'args = sys.argv[2:]', ["G01_default_root"], ""),
    ("C10a", 'if len(args) == 3 and args[1] == "--root":', 'if len(args) == 3 or args[1] == "--root":', ["G01_default_root"], ""),
    ("C10b", 'if len(args) == 3 and args[1] == "--root":', 'if len(args) == 3 and args[1] != "":', ["B02_unknown_option"], ""),
    ("C11", '    args = args[2:]', '    args = args[1:]', ["G00"], ""),
    ("C12", 'if len(args) != 1:', 'if len(args) == 1:', ["G00"], ""),
    ("C13", '    blind("usage: cm_relocated_anchor_copies_lockstep.sh [--root DIR]")', '    blind("usage")', ["B02_unknown_option"], ""),
    ("C14", 'def read(rel):', 'def read(path):', ["G00"], ""),
    ("C15", '    try:', '    if True:', ["G00"], ""),
    ("C16a", '        with open(args[0].encode() + b"/" + rel, "rb") as fh:', '        with open(rel, "rb") as fh:', ["G00"], ""),
    ("C16b", '        with open(args[0].encode() + b"/" + rel, "rb") as fh:', '        with open(args[0].encode() + b"/" + rel, "r") as fh:', ["G00"], "R5-2"),
    ("C17", '            return fh.read()', '            return fh.read().replace(b"\\r", b"")', ["F12_caf1_crlf"], "R5-2"),
    ("C18", '    except OSError as err:', '    except FileNotFoundError as err:', ["B12_file_unreadable", "B13_file_is_directory"], "H04/R6-4"),
    ("C19a", '        blind(f"{rel.decode(errors=\'replace\')} is not readable ({err.strerror})")', '        blind(f"{rel.decode(errors=\'replace\')} is not readable")', ["B11_file_missing"], ""),
    ("C19b", '        blind(f"{rel.decode(errors=\'replace\')} is not readable ({err.strerror})")', '        return b""', ["B04_decl_missing", "B11_file_missing"], ""),
    ("C20a", 'rows = [row.split(b"\\t") for row in read(DECL).split(b"\\n") if row and not row.startswith(b"#")]', 'rows = [row.split(b"\\t") for row in read(DECL).split(b"\\n") if row]', ["G00"], ""),
    ("C20b", 'rows = [row.split(b"\\t") for row in read(DECL).split(b"\\n") if row and not row.startswith(b"#")]', 'rows = [row.split(b"\\t") for row in read(DECL).split(b"\\n") if row and not row.startswith(b"# ")]', ["G00"], ""),
    ("C20c", 'rows = [row.split(b"\\t") for row in read(DECL).split(b"\\n") if row and not row.startswith(b"#")]', 'rows = [row.split(b"\\t") for row in read(DECL).split(b"\\n") if not row.startswith(b"#")]', ["G00"], ""),
    ("C21", 'if not rows:', 'if rows:', ["G00"], ""),
    ("C22", '    blind(f"{DECL.decode()} declares no row")', '    blind("no row")', ["B05_decl_no_row"], ""),
    ("C23", 'failed = 0', 'failed = 1', ["G00"], ""),
    ("C24a", 'for row in rows:', 'for row in rows[:-1]:', ["F34_carrier_mandate_glued_after"], "NM3"),
    ("C24b", 'for row in rows:', 'for row in rows[1:]:', ["F01_canon_same_length"], "NM3"),
    ("C25a", '    if len(row) != 3 or not row[0] or not row[1] or not row[2].isdigit():', '    if len(row) < 3 or not row[0] or not row[1] or not row[2].isdigit():', ["B07_row_four_fields"], ""),
    ("C25b", '    if len(row) != 3 or not row[0] or not row[1] or not row[2].isdigit():', '    if len(row) != 3 or not row[1] or not row[2].isdigit():', ["B08_row_empty_file"], ""),
    ("C25c", '    if len(row) != 3 or not row[0] or not row[1] or not row[2].isdigit():', '    if len(row) != 3 or not row[0] or not row[2].isdigit():', ["B09_row_empty_pinned"], ""),
    ("C25d", '    if len(row) != 3 or not row[0] or not row[1] or not row[2].isdigit():', '    if len(row) != 3 or not row[0] or not row[1]:', ["B10a_row_count_word", "B10b_row_count_cr", "B10c_row_count_negative"], ""),
    ("C26", '        blind(f"{DECL.decode()}: malformed row {row!r}")', '        blind("malformed row")', ["B06_row_two_fields"], ""),
    ("C27", '    haystack, pinned = read(row[0]), read(row[1])', '    pinned, haystack = read(row[0]), read(row[1])', ["G00"], ""),
    ("C28", '    if not pinned:', '    if pinned is None:', ["B14_pinned_empty"], ""),
    ("C29", '        blind(f"{row[1].decode(errors=\'replace\')} is empty")', '        blind("empty")', ["B14_pinned_empty"], ""),
    ("C30a", '    found = haystack.count(pinned)', '    found = haystack.count(pinned[:64])', ["F01_canon_same_length", "F02_caf3_same_length"], "RM1/RM4"),
    ("C30b", '    found = haystack.count(pinned)', '    found = b" ".join(haystack.split()).count(b" ".join(pinned.split()))', ["F03_caf2_double_space", "F13_caf2_lone_cr"], "RM2"),
    ("C30c", '    found = haystack.count(pinned)', '    found = haystack.lower().count(pinned.lower())', ["F04_caf4_case", "F28_mandate_lowered_in_clause_everywhere", "F26_agents_carrier_case"], "H19/RM5"),
    ("C30d", '    found = haystack.count(pinned)', '    found = haystack.count(pinned.strip())', ["F14_caf2_trailing_glue", "F21_claude_carrier_leading_space"], "H01/H03"),
    ("C30e", '    found = haystack.count(pinned)', '    found = haystack.replace(b"\\r", b"").count(pinned)', ["F12_caf1_crlf", "F27_claude_carrier_crlf"], "R5-2"),
    ("C30f", '    found = haystack.count(pinned)', '    found = min(haystack.count(pinned), int(row[2]))', ["F09_caf_fifth_exact", "F10_dup_canon"], "dup_canon"),
    ("C31a", '    if found != int(row[2]):', '    if found > int(row[2]):', ["F01_canon_same_length"], "NM6"),
    ("C31b", '    if found != int(row[2]):', '    if found < int(row[2]):', ["F10_dup_canon"], ""),
    ("C32a", L, L.replace(": FAIL --", ": WARN --"), ["F01_canon_same_length"], "H05"),
    ("C32b", L, L.replace("{found} time(s), declared {int(row[2])}", "{int(row[2])} time(s), declared {found}"), ["F01_canon_same_length"], "H07"),
    ("C32c", L, L.replace("{row[0].decode(errors='replace')} holds", "{row[1].decode(errors='replace')} holds"), ["F01_canon_same_length"], "H06"),
    ("C33", '        failed += 1', '        failed += 0', ["F01_canon_same_length"], ""),
    ("C34", 'if failed:', 'if not failed:', ["G00"], ""),
    ("C35", '    sys.exit(1)', '    sys.exit(0)', ["F01_canon_same_length"], ""),
    ("C36", 'print(f"{GATE}: PASS -- {len(rows)} row(s) hold their declared exact byte counts")', 'print(f"{GATE}: PASS")', ["G00"], ""),
    ("C37", 'PY', 'PYX', ["G00"], ""),
]
# data mutants: (id, file, old bytes, new bytes, designated killers, reviewer mutants)
TRUNC_AT = base[CLAUSE].index(B("\n\n**Clause (E) honest boundary"))
DATA = [
    ("D01", CMARK, b"\n**(E)", b"**(E)", ["G02a_midline_cite_clause", "G03_midbody_start_everywhere"], "H01/H02/NM2"),
    ("D02", KMARK, b"\n**EXTENSION", b"**EXTENSION", ["G02b_midline_cite_carrier"], "H01/NM2 (carrier)"),
    ("D03", CLAUSE, b"flag.\n", b"flag.", ["F14_caf2_trailing_glue"], "H03/NM5"),
    ("D04", CARRIER, B("LOCKSTEP`.\n"), B("LOCKSTEP`."), ["F25_gemini_carrier_trailing_space"], "carrier trailing"),
    ("D08", MANDATE, b'popup', b'POPUP', ["G00"], "mandate pin content"),
    ("D05", CLAUSE, base[CLAUSE][TRUNC_AT:], b"\n", ["F05_caf2_boundary_drift"], "NM1"),
    ("D06", SPACED, b' "Any', b'"Any', ["F30_mandate_glued_before"], "RM3"),
    ("D07", SPACED, b'yet!" ', b'yet!"', ["F31_mandate_glued_after"], "RM3 (after)"),
]
ROW_KILLER = {
    (CON, CLAUSE): "F01_canon_same_length", (CON, CMARK): "F07_canon_extra_drifted",
    (CAF, CLAUSE): "F02_caf3_same_length", (CAF, CMARK): "F08_caf_fifth_drifted",
    (GRP, CLAUSE): "F06_group_drift", (GRP, CMARK): "F11_group_extra_drifted",
    (CLAUSE, MANDATE): "F32_mandate_pasted_twice", (CLAUSE, SPACED): "F30_mandate_glued_before",
    (CARRIER, MANDATE): "F33_carrier_mandate_pasted_twice", (CARRIER, SPACED): "F34_carrier_mandate_glued_after",
}
for f in CORE:
    ROW_KILLER[(f, CARRIER)] = f"F17_{f[:-3].lower()}_carrier_changed"
    ROW_KILLER[(f, KMARK)] = f"F21_{f[:-3].lower()}_carrier_leading_space"
rows = [ln for ln in base[DECL].split(b"\n") if ln and not ln.startswith(b"#")]
if len(rows) != len(ROW_KILLER):
    problems.append(f"the data file has {len(rows)} rows but the row-killer table has {len(ROW_KILLER)}: every row needs a delete and a count mutant")
for n, ln in enumerate(rows, 1):
    f, p, c = ln.decode().split("\t")
    k = ROW_KILLER.get((f, p))
    if k is None:
        problems.append(f"data row {n} ({f} / {p}) has no designated delete-killer case")
        continue
    DATA.append((f"R{n:02d}del", DECL, ln + b"\n", b"", [k], "row deleted"))
    DATA.append((f"R{n:02d}cnt", DECL, ln + b"\n", B(f"{f}\t{p}\t{int(c) + 1}\n"), ["G00"], "row count changed"))

# ── coverage: every non-comment gate line is the original of a code mutant ─────
def coverage(gate_text, code):
    out, lines = [], gate_text.split("\n")
    olds = {m[1] for m in code}
    for i, line in enumerate(lines, 1):
        if line == "" or (line.startswith("#") and i != 1):
            continue
        if lines.count(line) != 1:
            out.append(f"gate line {i} is not unique: {line!r}")
        if line not in olds:
            out.append(f"gate line {i} has no code mutant: {line!r}")
    for m in code:
        if lines.count(m[1]) != 1:
            out.append(f"mutant {m[0]} is stillborn: its original line occurs {lines.count(m[1])} times")
    return out

GT = base[GATE].decode()
problems += coverage(GT, CODE)
for m in CODE + DATA:
    for k in m[3] if m in CODE else m[4]:
        if k not in CASE_IDS:
            problems.append(f"mutant {m[0]} names unknown killer case {k}")
for m in DATA:
    if base[m[1]].count(m[2]) != 1:
        problems.append(f"data mutant {m[0]} is stillborn: its original bytes occur {base[m[1]].count(m[2])} times in {m[1]}")
for p in (CLAUSE, CMARK, CARRIER, KMARK, MANDATE, SPACED):
    if not any(m[1] == p and not m[0].startswith("R") for m in DATA):
        problems.append(f"pinned file {p} has no boundary mutant")

# ── running the gate ─────────────────────────────────────────────────────────
def run(tree, cs):
    rundir = tempfile.mkdtemp(dir=TOP)
    try:
        for rel, v in tree.items():
            dst = os.path.join(rundir, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            if v is None:
                continue
            if v is DIR:
                os.mkdir(dst); continue
            if v is MODE000:
                with open(dst, "wb") as fh: fh.write(base[rel])
                os.chmod(dst, 0); continue
            if v is base.get(rel) and rel != GATE:
                os.link(os.path.join(BASEDIR, rel), dst); continue
            with open(dst, "wb") as fh: fh.write(v)
        gate = os.path.join(rundir, GATE)
        os.chmod(gate, 0o755)
        args = ["--root", rundir] if cs["args"] is None else [a.replace("{RUN}", rundir) for a in cs["args"]]
        env = dict(os.environ)
        cmd = [gate] + args
        if cs["nopython"]:
            env["PATH"] = NOPY; cmd = [BASH, gate] + args
        p = subprocess.run(cmd, cwd=TOP, env=env, capture_output=True, timeout=60)
        return (p.returncode, p.stdout, p.stderr.replace(rundir.encode(), b"<RUN>"))
    finally:
        for d, _, fs in os.walk(rundir):
            for f in fs:
                try: os.chmod(os.path.join(d, f), 0o600)
                except OSError: pass
        shutil.rmtree(rundir, ignore_errors=True)

def tree_for(cs, gate_text=None, data_mut=None):
    t = dict(base)
    if cs["edit"]:
        cs["edit"](t)
    if gate_text is not None:
        t[GATE] = gate_text.encode()
    if data_mut is not None:
        f, old, new = data_mut
        if not isinstance(t.get(f), bytes) or t[f].count(old) != 1:
            return None   # the case removed or rewrote what the mutant edits: not applicable here
        t[f] = t[f].replace(old, new)
    return t

def apply_code(old, new):
    lines = GT.split("\n")
    if lines.count(old) != 1:
        raise ValueError("stillborn")
    return "\n".join(new if l == old else l for l in lines)

pool = concurrent.futures.ThreadPoolExecutor(max_workers=JOBS)
real = dict(zip([c["id"] for c in CASES], pool.map(lambda c: run(tree_for(c), c), CASES)))
for c in CASES:
    rc, out, err = real[c["id"]]
    if rc != c["rc"] or c["expect"] not in out:
        problems.append(f"case {c['id']}: real gate gave rc {rc} {out.decode(errors='replace').strip()!r}, declared rc {c['rc']} with {c['expect'].decode()!r}")

def kills(gate_text=None, data_mut=None):
    def one(c):
        t = tree_for(c, gate_text, data_mut)
        return None if t is None else (run(t, c) != real[c["id"]])
    res = list(pool.map(one, CASES))
    return sorted(c["id"] for c, r in zip(CASES, res) if r)

report = []
for mid, old, new, killers, names in CODE:
    try:
        ks = kills(gate_text=apply_code(old, new))
    except ValueError:
        continue   # already reported by coverage()
    miss = [k for k in killers if k not in ks]
    report.append(f"{mid:8} {'KILLED' if ks and not miss else 'SURVIVES'} by {len(ks)} case(s){' [' + names + ']' if names else ''}; designated {','.join(killers)}")
    if not ks or miss:
        problems.append(f"code mutant {mid} {'survives' if not ks else 'is not killed by designated ' + ','.join(miss)}")
for mid, f, old, new, killers, names in DATA:
    if base[f].count(old) != 1:
        continue
    ks = kills(data_mut=(f, old, new))
    miss = [k for k in killers if k not in ks]
    report.append(f"{mid:8} {'KILLED' if ks and not miss else 'SURVIVES'} by {len(ks)} case(s) [{names}]; designated {','.join(killers)}")
    if not ks or miss:
        problems.append(f"data mutant {mid} {'survives' if not ks else 'is not killed by designated ' + ','.join(miss)}")

# ── negative controls ────────────────────────────────────────────────────────
nc = []
g00 = CASES[0]
if kills(gate_text=GT):
    problems.append("NC1: the identity mutant was reported killed -- kill detection is broken")
else:
    nc.append("NC1 identity mutant survives")
always_pass = GT.replace('if failed:', 'if False:')
futs = []
for _ in range(10):
    futs.append(("same", pool.submit(lambda: run(tree_for(CASES[7], GT), CASES[7]) != real[CASES[7]["id"]])))
    futs.append(("pass", pool.submit(lambda: run(tree_for(CASES[7], always_pass), CASES[7]) != real[CASES[7]["id"]])))
bad = [lab for lab, f in futs if f.result() != (lab == "pass")]
if bad:
    problems.append(f"NC2: concurrent same-label mutants were mis-attributed {len(bad)} time(s)")
else:
    nc.append("NC2 20 concurrent same-label runs attributed independently")
try:
    apply_code("this line is not in the gate", "x")
    problems.append("NC3: a stillborn mutant was applied")
except ValueError:
    nc.append("NC3 stillborn mutant refused")
added = GT.replace("failed = 0\n", "failed = 0\nfailed = failed\n")
edited = GT.replace('if row and not row.startswith(b"#")', 'if row and not b"#" in row[:1]')
ca, ce = coverage(added, CODE), coverage(edited, CODE)
if any("has no code mutant" in x for x in ca) and any("stillborn" in x for x in ce) and any("has no code mutant" in x for x in ce):
    nc.append("NC4 coverage reports an added line and an edited line")
else:
    problems.append(f"NC4: coverage did not report an added or an edited line ({ca}, {ce})")
pool.shutdown()
shutil.rmtree(TOP, ignore_errors=True)

print(f"{T}: {len(CASES)} cases on the real gate; {len(CODE)} code + {len(DATA)} data mutants")
for line in report:
    print("  " + line)
for line in nc:
    print("  " + line)
for p in problems:
    print(f"{T}: FAIL -- {p}")
if problems:
    sys.exit(1)
print(f"{T}: PASS -- every case as declared, every mutant killed by its designated case(s), every gate line covered, NC1-NC4 hold")
PY
