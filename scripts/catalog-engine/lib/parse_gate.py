#!/usr/bin/env python3
# catalog-engine / lib / parse_gate.py
#
# Purpose:   Parse the pre-build verification gate file into one catalog record
#            per `CM-*` gate. A gate is REGISTERED in the file by ONE of three
#            wiring forms (the "gate call forms"), each recognised STRUCTURALLY:
#              F1 echo-banner   `echo -n "  CM-<ID>: <what-it-checks>... "` — the
#                               literal banner; it both DEFINES the gate AND
#                               carries its human-readable description.
#              F2 wrapper-call  `<wrapper> "CM-<ID>" "<desc>" ...` — the gate name
#                               is the FIRST ARGUMENT of a shell helper function
#                               whose body prints the verdict banner from that
#                               argument (`echo -n "  ${label}: ..."` or
#                               `log_pass "${label}: ..."`). A literal `CM-<ID>:`
#                               never appears in such a banner, so F1 cannot see
#                               it (the ATM-1473 blind spot). Wrappers are
#                               DETECTED from the function bodies, never named in
#                               this engine (§11.4.28 — no project literal).
#              F3 log-verdict   `log_pass|log_fail "CM-<ID>: <text>"` for a gate
#                               that has NO F1 banner (verdict-line-only gate);
#                               the pairing audit already counts these tokens.
#            Each record is DERIVED from its registration line; the source line
#            number is captured so a reader can jump to the gate (§11.4.6).
#            Precedence F1 > F2 > F3 per gate id (first occurrence within a form
#            wins), so adding F2/F3 never changes an F1 record.
# Usage:     records = parse_gate_file(path, type_root)
#            unrecognised = unrecognised_call_forms_file(path)      # blind-spot guard
#            python3 parse_gate.py --selftest
#            python3 parse_gate.py --wrapper-ids FILE   # F2 ids (pairing audit consumes)
#            python3 parse_gate.py --verdict-ids FILE   # F3 ids
#            python3 parse_gate.py --unrecognised FILE [--exempt a,b]   # exit 1 if any
#            python3 parse_gate.py --report FILE        # wrappers + per-form counts
# Inputs:    absolute path to pre_build_verification.sh + type-root tag.
# Outputs:   a list of dicts matching the §2 schema (gate subset); CLI modes print
#            to stdout and exit 0 (ok) / 1 (finding) / 2 (usage or IO error).
# Side-effects: none — read-only.
# Dependencies: stdlib only (re, os, sys).
# Cross-refs: docs/research/test_catalog/P0_design.md §1 (632 raw CM-* tokens;
#            510 are gate DEFINITIONS via the echo-n idiom — the rest are
#            cross-reference mentions in comments, which do NOT define a gate);
#            docs/scripts/audit_gate_mutation_pairing.md (the pairing audit shares
#            F2/F3 through the CLI modes above, so catalog and audit cannot
#            disagree about which gates exist); constitution §11.4.201(7)
#            (carrier vs thing; a count is a lead, the lines are the finding),
#            §11.4.273 (control needle, see --selftest), §11.4.276(C)
#            (class-exhaustive closure of a blind-spot class).
"""Pre-build CM-* gate parser for the catalog engine (decoupled, §11.4.28)."""

import os
import re
import sys

# Canonical gate-DEFINITION idiom (F1): the line that prints the gate banner just
# before running its check:  echo -n "  CM-<ID>: <description>... "
# Captures (1) the gate id, (2) the description, with the trailing "..." dropped.
_RE_GATE_DEF = re.compile(
    r'echo\s+-n\s+"\s*(CM-[A-Z0-9_-]+):\s*(.*?)\s*(?:\.\.\.)?\s*"'
)

# ATM-NNN reference inside the gate description (§11.4.54), if present.
_RE_ATM = re.compile(r"\bATM-([0-9]+)\b")
# Fix #NN reference inside the description (project cross-ref).
_RE_FIX = re.compile(r"\bFix #([0-9]+)\b")
# §-letter / §11.4.NN anchor reference inside the description.
_RE_SECTION = re.compile(r"§\s*([0-9A-Za-z.]+)")
# Feature-class hint (§11.4.69 taxonomy token) appearing literally in the desc.
_RE_FEATURE = re.compile(
    r"\b(audio_output|audio_input|video_display|network_throughput|"
    r"network_connectivity|bluetooth_a2dp|bluetooth_pair|touch_input|sensor|"
    r"gpu_render|storage_read|storage_write|mediacodec_decode|"
    r"mediacodec_encode|miracast|cast|boot_service|package_install|"
    r"permission_grant|wifi_link|wifi_throughput|ethernet_link|"
    r"display_topology|drm_playback|subtitle_render)\b"
)

# --- F2/F3 recognition ------------------------------------------------------
# A shell function definition opener (column-indent captured so its closing
# brace can be located at the SAME indent).
_RE_FN_OPEN = re.compile(r"^(\s*)(?:function\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*\(\)\s*\{")
# A verdict-emitting statement whose gate label is an INTERPOLATED variable:
#   echo -n "  ${lbl}: ..."   |   log_pass "${tok}: ..."   |   log_fail "$tok: ..."
# Group 1 = the label variable, group 2 = the text after "<label>:".
_RE_EMIT = re.compile(
    r'(?:echo\s+-n|log_pass|log_fail)\s+"\s*\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?:\s*(.*)$'
)
# A positional binding:  var="$1"  /  var="${2}"  (also inside `local a="$1" b="$2"`).
_RE_POS_BIND = re.compile(r'\b([A-Za-z_][A-Za-z0-9_]*)="\$\{?([1-9])\}?"')
# The text right after the label that is itself a bound positional (-> description).
_RE_DESC_VAR = re.compile(r"^\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?")
# A line-leading call whose FIRST argument is a quoted CM-* gate name (F2 call
# site, and the shape the unrecognised-form guard looks for).
_RE_CALL_LEAD = re.compile(
    r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s+(?:\"(CM-[A-Z0-9_-]+)\"|'(CM-[A-Z0-9_-]+)')"
)
# F3: a verdict-line-only gate registration (the same token form the pairing
# audit greps: log_pass "CM-X: / log_fail "CM-X:).
_RE_LOG_VERDICT = re.compile(r'\blog_(?:pass|fail)\s+"\s*(CM-[A-Z0-9_-]+):\s*(.*)$')

# Bound on how far a function body may run before we give up looking for its
# closing brace (a runaway scan must not turn into a whole-file false wrapper).
_MAX_FN_LINES = 400

# Call-leading identifiers that are never gate helpers (shell builtins / common
# tools that legitimately take a quoted CM-* string as DATA, e.g. echo "CM-X").
# Only DEFINED functions and gate-ish names are candidates for the
# unrecognised-call-form guard, so this list is defence-in-depth, not the filter.
_NON_HELPER_IDENTS = frozenset({
    "echo", "printf", "test", "read", "eval", "export", "local", "readonly",
    "declare", "typeset", "cat", "grep", "sed", "awk", "print", "return",
    "exit", "set", "unset", "shift", "source", "bash", "sh", "python3",
    "python", "env", "command", "type", "case", "for", "while", "if", "elif",
    "then", "else", "do", "in",
})
_GATEISH_NAME = re.compile(r"gate|check|assert|verify|expect", re.IGNORECASE)


def _read_lines(path):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            return fh.read().splitlines()
    except OSError:
        return []


# ---------------------------------------------------------------------------
# structural wrapper detection
# ---------------------------------------------------------------------------
def detect_gate_wrappers(lines):
    """Find every shell function that is a GATE WRAPPER.

    A wrapper is a function whose body prints a gate verdict (`echo -n`,
    `log_pass` or `log_fail`) labelled by an interpolated variable that the body
    binds from its FIRST positional argument (`var="$1"`), i.e. the gate name is
    the call's first argument. Returns {name: info} where info carries
    `def_line`, `label_var`, `emit` (the statement) and `desc_idx` (the
    positional index of the human-readable description when the banner prints one
    straight after the label, else None). Detection is purely structural — no
    function name is ever written into this engine (§11.4.28).
    """
    found = {}
    for i, ln in enumerate(lines):
        m = _RE_FN_OPEN.match(ln)
        if not m:
            continue
        indent, name = m.group(1), m.group(2)
        rest = ln[m.end():]
        if re.search(r"\}\s*(?:#.*)?$", rest):
            # A one-line definition (`f() { ...; }`): the text after the brace IS
            # the whole body. Scanning on to a later closing brace would swallow
            # the NEXT function's body and mis-attribute its verdict to this name.
            body = [rest]
        else:
            close = re.compile(r"^" + re.escape(indent) + r"\}\s*$")
            end = None
            for j in range(i + 1, min(len(lines), i + 1 + _MAX_FN_LINES)):
                if close.match(lines[j]):
                    end = j
                    break
                n = _RE_FN_OPEN.match(lines[j])
                if n and len(n.group(1)) <= len(indent):
                    break   # next sibling definition before our close: unclosed
            if end is None:
                continue
            body = [b for b in lines[i + 1:end] if not b.lstrip().startswith("#")]
        binds = {}
        for b in body:
            for var, idx in _RE_POS_BIND.findall(b):
                binds.setdefault(var, int(idx))
        for b in body:
            e = _RE_EMIT.search(b)
            if not e or binds.get(e.group(1)) != 1:
                continue
            desc_idx = None
            d = _RE_DESC_VAR.match(e.group(2))
            if d and binds.get(d.group(1)) not in (None, 1):
                desc_idx = binds[d.group(1)]
            found[name] = {"def_line": i + 1, "label_var": e.group(1),
                           "emit": b.strip(), "desc_idx": desc_idx}
            break
    return found


def _first_args(text, n):
    """Tokenise up to `n` shell words from `text` (double/single-quoted or bare).

    Returns the list of unquoted words (fewer than `n` when the line ends first or
    a quote is unterminated). `\\"`, `\\$`, `\\\\` and a backquote escape are
    unescaped inside double quotes exactly as bash does; nothing is expanded.
    """
    out, i, L = [], 0, len(text)
    while i < L and len(out) < n:
        while i < L and text[i] in " \t":
            i += 1
        if i >= L:
            break
        c = text[i]
        if c == '"':
            j, buf = i + 1, []
            while j < L and text[j] != '"':
                if text[j] == "\\" and j + 1 < L and text[j + 1] in '"$\\`':
                    buf.append(text[j + 1])
                    j += 2
                else:
                    buf.append(text[j])
                    j += 1
            if j >= L:
                break
            out.append("".join(buf))
            i = j + 1
        elif c == "'":
            j = text.find("'", i + 1)
            if j < 0:
                break
            out.append(text[i + 1:j])
            i = j + 1
        elif c in ";|&#\\":
            break
        else:
            j = i
            while j < L and text[j] not in " \t;|&":
                j += 1
            out.append(text[i:j])
            i = j
    return out


def _logical_line(lines, idx):
    """The statement starting at lines[idx], with trailing-backslash continuations
    joined (bounded to 3 physical lines)."""
    buf = lines[idx]
    k = idx
    while buf.rstrip().endswith("\\") and k + 1 < len(lines) and k - idx < 3:
        k += 1
        buf = buf.rstrip()[:-1] + " " + lines[k].strip()
    return buf


def _calls(lines):
    """Yield (index, ident, gate_id, statement, ident_end) for every line-leading
    `<ident> "CM-X"` call; a call whose first argument sits on a backslash
    continuation line is joined first (bounded)."""
    for idx, ln in enumerate(lines):
        stmt = _logical_line(lines, idx) if ln.rstrip().endswith("\\") else ln
        m = _RE_CALL_LEAD.match(stmt)
        if m:
            yield idx, m.group(1), (m.group(2) or m.group(3)), stmt, m.end(1)


def _dq_prefix(text):
    """The text up to (not including) the first unescaped double quote."""
    out, i = [], 0
    while i < len(text):
        if text[i] == "\\" and i + 1 < len(text):
            out.append(text[i + 1] if text[i + 1] in '"$\\`' else text[i:i + 2])
            i += 2
        elif text[i] == '"':
            break
        else:
            out.append(text[i])
            i += 1
    return "".join(out)


# ---------------------------------------------------------------------------
# record construction
# ---------------------------------------------------------------------------
def _make_record(gate_id, desc, lineno, basename, type_root, form, quality, how):
    matm = _RE_ATM.search(desc)
    atm_id = "ATM-%s" % matm.group(1) if matm else None
    mfix = _RE_FIX.search(desc)
    fix_ref = "Fix #%s" % mfix.group(1) if mfix else None
    msec = _RE_SECTION.search(desc)
    section_ref = ("§" + msec.group(1)) if msec else None
    mfeat = _RE_FEATURE.search(desc.lower())
    feature_class = mfeat.group(1) if mfeat else None

    # step_by_step for a gate = the single check it performs (the banner).
    steps = [{
        "what": "pre-build assert: %s" % desc if desc else "pre-build gate",
        "how": how, "achieved": "", "result": "",
        "source": "gate-definition-line",
    }]

    derivation_gaps = []
    if not desc:
        derivation_gaps.append("no-gate-description")

    return {
        "id": gate_id,
        "name": "%s — %s" % (gate_id, desc) if desc else gate_id,
        "type": type_root,                  # "pre-build-gate"
        "subtypes": ["pre_build_gate"],
        "description": desc,
        "description_quality": quality if desc else "header-only",
        "step_by_step": steps,
        "how_tokens": [],
        # A gate is a SOURCE-layer check (§11.4.108) — it is NOT itself a
        # captured-evidence test. bluff_proofed/physical_evidence describe
        # RUNTIME tests; for a static gate both are False BY CONSTRUCTION.
        # The gate's anti-bluff guarantee comes from its PAIRED MUTATION
        # (parse_mutation.py), surfaced as the catalog gate↔mutation join.
        "bluff_proofed": False,
        "bluff_proofed_reasons": [],
        "physical_evidence": False,
        "physical_evidence_which": [],
        "feature_class": feature_class,
        "version": "unversioned",
        "atm_id": atm_id,
        "fix_ref": fix_ref,
        "section_ref": section_ref,
        "status": "gate",
        "sources_anti_bluff": False,
        "source_path": None,                # filled by scan.py
        "source_line": lineno,
        "source_file": basename,
        "derivation_gaps": derivation_gaps,
        # which registration form produced this record (F1/F2/F3) — additive.
        "wiring_form": form,
        # join key — filled at scan time by cross-referencing the mutation
        # corpus; default None means "no paired mutation found yet".
        "paired_mutation": None,
    }


def parse_gate_lines(lines, basename, type_root):
    """Core parser over an in-memory line list → list of gate records.

    One record per DISTINCT `CM-<ID>`; precedence F1 (echo banner) > F2 (wrapper
    call) > F3 (log verdict line); within a form the FIRST occurrence wins.
    """
    records = []
    seen = {}   # gate_id -> record (dedup)

    # ---- F1: echo-banner (unchanged behaviour) ----
    for lineno, ln in enumerate(lines, start=1):
        m = _RE_GATE_DEF.search(ln)
        if not m:
            continue
        gate_id = m.group(1)
        if gate_id in seen:
            continue   # first definition wins; later banners are sub-parts
        desc = (m.group(2) or "").strip()
        rec = _make_record(gate_id, desc, lineno, basename, type_root,
                           "echo-banner", "gate-banner",
                           "echo-n banner + check")
        seen[gate_id] = rec
        records.append(rec)

    # ---- F2: wrapper-call (label passed as the helper's first argument) ----
    wrappers = detect_gate_wrappers(lines)
    if wrappers:
        for idx, ident, gate_id, stmt, end in _calls(lines):
            if ident not in wrappers or gate_id in seen:
                continue
            info = wrappers[ident]
            desc = ""
            if info["desc_idx"]:
                args = _first_args(stmt[end:], info["desc_idx"])
                if len(args) >= info["desc_idx"]:
                    desc = args[info["desc_idx"] - 1].strip()
            rec = _make_record(gate_id, desc, idx + 1, basename, type_root,
                               "wrapper-call:%s" % ident, "wrapper-arg",
                               "%s wrapper banner + check" % ident)
            seen[gate_id] = rec
            records.append(rec)

    # ---- F3: log verdict line (gate with no echo banner) ----
    for lineno, ln in enumerate(lines, start=1):
        m = _RE_LOG_VERDICT.search(ln)
        if not m:
            continue
        gate_id = m.group(1)
        if gate_id in seen:
            continue
        desc = _dq_prefix(m.group(2)).strip()
        rec = _make_record(gate_id, desc, lineno, basename, type_root,
                           "log-verdict", "verdict-line",
                           "log_pass/log_fail verdict line + check")
        seen[gate_id] = rec
        records.append(rec)

    return records


def parse_gate_file(path, type_root):
    """Parse one pre-build verification file → list of gate records.

    One record per DISTINCT `CM-<ID>` gate registration (see the module header
    for the three recognised forms). If a gate id is registered more than once
    (rare — multi-part gate) the FIRST occurrence of the highest-precedence form
    wins; the source_line is that registration line.
    """
    return parse_gate_lines(_read_lines(path), os.path.basename(path), type_root)


# ---------------------------------------------------------------------------
# blind-spot guard + id listers (consumed by the pairing audit and the generator)
# ---------------------------------------------------------------------------
def wrapper_call_ids(lines):
    """Sorted distinct gate ids registered through a detected wrapper (F2)."""
    wrappers = detect_gate_wrappers(lines)
    return sorted({gid for _, ident, gid, _, _ in _calls(lines)
                   if ident in wrappers})


def verdict_line_ids(lines):
    """Sorted distinct gate ids that appear ONLY through `log_pass|log_fail
    "CM-X:` (F3) — i.e. not through an F1 banner."""
    f1 = {m.group(1) for m in (_RE_GATE_DEF.search(l) for l in lines) if m}
    f3 = {m.group(1) for m in (_RE_LOG_VERDICT.search(l) for l in lines) if m}
    return sorted(f3 - f1)


def unrecognised_call_forms(lines, exempt=()):
    """Line-leading `<ident> "CM-X"` calls whose helper is NOT a detected gate
    wrapper — the shape the next ATM-1473-class blind spot would take.

    Only identifiers that are defined as functions in the same file, or whose
    name looks like a gate helper (gate/check/assert/verify/expect), are
    candidates; shell builtins/tools that take a CM-* string as data are not.
    Returns a sorted list of (line, ident, gate_id). A non-empty result means
    "teach this engine the form or exempt the ident" — never "ignore".
    """
    wrappers = detect_gate_wrappers(lines)
    defined = {m.group(2) for m in (_RE_FN_OPEN.match(l) for l in lines) if m}
    exempt = set(exempt)
    out = []
    for idx, ident, gid, _, _ in _calls(lines):
        if ident in wrappers or ident in exempt or ident in _NON_HELPER_IDENTS:
            continue
        if ident in defined or _GATEISH_NAME.search(ident):
            out.append((idx + 1, ident, gid))
    return out


def unrecognised_call_forms_file(path, exempt=()):
    """File variant of unrecognised_call_forms (read-only)."""
    return unrecognised_call_forms(_read_lines(path), exempt)


# ---------------------------------------------------------------------------
# --selftest: golden-good + golden-bad + negative control on an embedded fixture
# (§11.4.107(10) / §11.4.273). The pairing audit runs this BEFORE trusting the
# F2/F3 listers, so a blind or broken instrument can never report "0 gates".
# ---------------------------------------------------------------------------
_SELFTEST_FIXTURE = [
    'log_pass() { echo "ok $1"; }',
    "# a wrapper: the gate name is its first argument",
    "_sw_run() {",
    '    local _l="$1" _d="$2"; shift 2',
    '    echo -n "  ${_l}: ${_d}... "',
    '    "$@" >/dev/null 2>&1',
    "}",
    "# a verdict wrapper with no description argument",
    "_sv_run() {",
    '    _t="$1"; _s="$2"; shift 2',
    '    log_pass "${_t}: PASS"',
    "}",
    "# a helper that is NOT a gate wrapper (no label-bound verdict)",
    "_sn_helper() {",
    '    echo "$1"',
    "}",
    'echo -n "  CM-SELFTEST-LITERAL: literal banner gate... "',
    '_sw_run "CM-SELFTEST-WRAPPED" "wrapped \\"quoted\\" desc (ATM-1473)" bash x.sh',
    "_sv_run \\",
    '    "CM-SELFTEST-CONT" "script.sh"',
    '# _sw_run "CM-SELFTEST-COMMENTED" "a commented call must never register"',
    'log_pass "CM-SELFTEST-VERDICT-ONLY: verdict line only gate"',
    '_sn_helper "CM-SELFTEST-UNRECOGNISED"',
    'bash "CM-SELFTEST-EXTERNAL-DATA"',
]


def selftest():
    """Returns (ok, [(name, passed)]) — golden-good, golden-bad, negative controls."""
    checks = []

    def chk(name, cond):
        checks.append((name, bool(cond)))

    recs = {r["id"]: r for r in parse_gate_lines(_SELFTEST_FIXTURE, "fx.sh",
                                                 "pre-build-gate")}
    wr = detect_gate_wrappers(_SELFTEST_FIXTURE)
    chk("wrapper _sw_run detected (golden-good)", "_sw_run" in wr)
    chk("wrapper _sv_run detected (golden-good)", "_sv_run" in wr)
    chk("non-wrapper _sn_helper NOT detected (negative control)",
        "_sn_helper" not in wr)
    chk("log_pass() definition is not a wrapper (negative control)",
        "log_pass" not in wr)
    chk("F1 literal banner catalogued",
        recs.get("CM-SELFTEST-LITERAL", {}).get("wiring_form") == "echo-banner")
    w = recs.get("CM-SELFTEST-WRAPPED")
    chk("F2 wrapper call catalogued", w is not None)
    chk("F2 description decoded (escaped quotes kept)",
        w is not None and w["description"] == 'wrapped "quoted" desc (ATM-1473)')
    chk("F2 ATM ref derived from wrapper description",
        w is not None and w["atm_id"] == "ATM-1473")
    c = recs.get("CM-SELFTEST-CONT")
    chk("F2 continuation-line call catalogued", c is not None)
    chk("F2 wrapper without description arg -> honest empty description + gap",
        c is not None and c["description"] == ""
        and "no-gate-description" in c["derivation_gaps"])
    chk("F3 verdict-line-only gate catalogued",
        recs.get("CM-SELFTEST-VERDICT-ONLY", {}).get("wiring_form")
        == "log-verdict")
    chk("commented-out wrapper call NOT catalogued (negative control)",
        "CM-SELFTEST-COMMENTED" not in recs)
    chk("external-command data string NOT catalogued (negative control)",
        "CM-SELFTEST-EXTERNAL-DATA" not in recs)
    unrec = unrecognised_call_forms(_SELFTEST_FIXTURE)
    chk("unrecognised helper call flagged (golden-bad blind-spot probe)",
        [u[2] for u in unrec] == ["CM-SELFTEST-UNRECOGNISED"])
    chk("exempting the ident silences the guard",
        unrecognised_call_forms(_SELFTEST_FIXTURE, ["_sn_helper"]) == [])
    chk("wrapper_call_ids lists exactly the F2 ids",
        wrapper_call_ids(_SELFTEST_FIXTURE)
        == ["CM-SELFTEST-CONT", "CM-SELFTEST-WRAPPED"])
    chk("verdict_line_ids lists the F3-only id",
        verdict_line_ids(_SELFTEST_FIXTURE) == ["CM-SELFTEST-VERDICT-ONLY"])
    return all(p for _, p in checks), checks


def _usage():
    sys.stderr.write(
        "usage: parse_gate.py --selftest | --wrapper-ids FILE | --verdict-ids FILE |"
        " --unrecognised FILE [--exempt a,b] | --report FILE\n")
    return 2


def main(argv):
    if not argv:
        return _usage()
    mode = argv[0]
    if mode == "--selftest":
        ok, checks = selftest()
        for name, passed in checks:
            print("  [%s] %s" % ("PASS" if passed else "FAIL", name))
        print("VERDICT: %s" % ("GREEN" if ok else "RED"))
        return 0 if ok else 1
    if len(argv) < 2 or mode not in ("--wrapper-ids", "--verdict-ids",
                                     "--unrecognised", "--report"):
        return _usage()
    path = argv[1]
    if not os.path.isfile(path):
        sys.stderr.write("parse_gate: file not found: %s\n" % path)
        return 2
    lines = _read_lines(path)
    if mode == "--wrapper-ids":
        for i in wrapper_call_ids(lines):
            print(i)
        return 0
    if mode == "--verdict-ids":
        for i in verdict_line_ids(lines):
            print(i)
        return 0
    if mode == "--unrecognised":
        exempt = []
        if len(argv) >= 4 and argv[2] == "--exempt":
            exempt = [x for x in argv[3].split(",") if x]
        found = unrecognised_call_forms(lines, exempt)
        for n, ident, gid in found:
            print("UNRECOGNISED-CALL-FORM: %s %s (line %d)" % (ident, gid, n))
        return 1 if found else 0
    # --report
    wr = detect_gate_wrappers(lines)
    per = {}
    for _, ident, gid, _, _ in _calls(lines):
        if ident in wr:
            per.setdefault(ident, set()).add(gid)
    for name, info in sorted(wr.items()):
        print("wrapper %s (line %d, label var %s, desc arg %s): %d gate(s)" % (
            name, info["def_line"], info["label_var"], info["desc_idx"],
            len(per.get(name, ()))))
    print("verdict-line-only gates (F3): %d" % len(verdict_line_ids(lines)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
