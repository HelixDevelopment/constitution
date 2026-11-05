#!/usr/bin/env bash
# test_dispatch_stamp_r7_matrix.sh -- T048 restart round 3 (§11.4.276 round
# 3, STRUCTURAL): the GENERATED failure-path matrix and the jq-vs-awk PARITY
# matrix for dispatch_stamp.sh.
#
# WHY THIS FILE EXISTS. Round-3 review R3V1-I1: in three consecutive rounds
# reviewer mutants survived in the branches the previous fix had added,
# because each round tested only the mutants it was handed. This file
# replaces the hand-picked list with two generated checks:
#
#   1. FAILURE-PATH MATRIX + META-CHECK. Every failure branch of
#      dispatch_stamp.sh is ENUMERATED from the file itself with a fixed
#      classifier (a non-zero `exit`/`return` in bash, a `|| PARSE_OK=0`
#      fallback, and inside the embedded awk reader every `exit N`, every
#      failure `return 0` of parse_string and every `return -1` of hexval).
#      Every enumerated branch must be NAMED by a row of the table below, and
#      the row must be proven to REACH it: the branch is neutralised in a
#      scratch copy of the tool (the exit/return removed or made a success),
#      the rows that name it are run against that copy, and at least one of
#      them must change its verdict. A branch with no row, or whose rows do
#      not notice its removal, FAILs -- unless it is listed in EQUIVALENT
#      with the reason it cannot be observed. Control needles prove the
#      classifier sees a known branch and reports a branch planted into a
#      scratch copy as unnamed.
#
#   2. PARITY MATRIX. The reviewer's 46-payload adversarial corpus (round-3
#      review, area V1, section 2) plus 500 payloads from a seeded generator
#      are run through the REAL tool in GUARD and EXTRACT mode, once with jq
#      on PATH and once with a PATH holding only awk + cat. Allow/block and
#      the extracted id must be identical in both, and EXTRACT must exit 0
#      with an empty stderr in both.
#
# Every row drives the real dispatch_stamp.sh through its real invocation
# path (JSON on stdin). FC_DISPATCH_ITEM_ID_RE pins the item pattern to the
# neutral QZT-[0-9]+ so no release-prefix derivation is involved (the
# restricted PATH has no git/sed/grep for release_prefix.sh).
#
# SKIP: without jq on this host the parity half is skipped honestly (it is a
# comparison WITH jq); the matrix still runs on the jq-less reader.
#
# Usage: bash constitution/scripts/fastcycle/tokens/test_dispatch_stamp_r7_matrix.sh
# Exit 0 = every check passed; 1 = a check failed.
set -uo pipefail

unset FC_DISPATCH_ITEM_ID_RE FC_DISPATCH_EXTRA_ITEM_PREFIXES HELIX_PROJECT_ROOT 2>/dev/null || true
export HELIX_RELEASE_PREFIX=atm_fixture_prefix

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
TOOL="$HERE/dispatch_stamp.sh"
WORK="$(mktemp -d)" || { echo "FAIL: mktemp"; exit 1; }
trap 'rm -rf "$WORK"' EXIT

NOJQ_BIN="$WORK/nojq_bin"
NOAWK_BIN="$WORK/noawk_bin"
NOMAWK_BIN="$WORK/nomawk_bin"
mkdir -p "$NOJQ_BIN" "$NOAWK_BIN" "$NOMAWK_BIN"
ln -s "$(command -v awk)" "$NOJQ_BIN/awk"
ln -s "$(command -v cat)" "$NOJQ_BIN/cat"
ln -s "$(command -v cat)" "$NOAWK_BIN/cat"
JQ_BIN="$(command -v jq 2>/dev/null || true)"
[ -n "$JQ_BIN" ] && ln -s "$JQ_BIN" "$NOAWK_BIN/jq"
# P2 (round 9): a stand-in for mawk / busybox awk -- real gawk in --traditional
# mode, which has no RT. Empty when gawk is not installed (the rows that need
# it are then skipped honestly).
GAWK_BIN="$(command -v gawk 2>/dev/null || true)"
if [ -n "$GAWK_BIN" ]; then
  printf '#!/bin/sh\nexec %s --traditional "$@"\n' "$GAWK_BIN" > "$NOMAWK_BIN/awk"
  chmod +x "$NOMAWK_BIN/awk"
  ln -s "$(command -v cat)" "$NOMAWK_BIN/cat"
fi

PASS=0; FAIL=0
echo "T048 r7: dispatch_stamp.sh failure-path matrix + jq/awk parity"
echo "tool: $TOOL"
python3 - "$TOOL" "$WORK" "$NOJQ_BIN" "$NOAWK_BIN" "$JQ_BIN" "$NOMAWK_BIN" "$GAWK_BIN" > "$WORK/driver.out" 2>&1 <<'PYEOF'
import concurrent.futures
import json
import os
import random
import re
import shutil
import signal
import subprocess
import sys

TOOL, WORK, NOJQ, NOAWK, JQ, NOMAWK, GAWK = sys.argv[1:8]
BASH = shutil.which("bash") or "/bin/bash"
HAVE_JQ = bool(JQ)
QZT = "QZT-[0-9]+"


def out(kind, text):
    print("%s\t%s" % (kind, text.replace("\n", " | ")), flush=True)


def stamp(tool, payload, mode, path_kind, timeout=20):
    """Run the tool. mode: 'g' (GUARD) or 'x' (EXTRACT). path_kind: 'jq'
    (the caller's PATH, jq present), 'awk' (only awk + cat), 'noawk' (only
    cat [+ jq])."""
    env = dict(os.environ)
    env.pop("FC_DISPATCH_EXTRA_ITEM_PREFIXES", None)
    env["FC_DISPATCH_ITEM_ID_RE"] = QZT
    if path_kind == "awk":
        env["PATH"] = NOJQ
    elif path_kind == "mawk":
        env["PATH"] = NOMAWK
    elif path_kind == "noawk":
        env["PATH"] = NOAWK
    argv = [BASH, tool] + (["--extract-item-id"] if mode == "x" else [])
    # Own process group, so a timeout kills the tool AND its awk/jq children
    # (a child left running would hold the output pipes open).
    p = subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                         env=env, start_new_session=True)
    try:
        so, se = p.communicate(payload, timeout=timeout)
    except subprocess.TimeoutExpired:
        if p.pid > 1:
            os.killpg(p.pid, signal.SIGKILL)
        p.communicate()
        return ("TIMEOUT", "", "")
    return (p.returncode, so.decode("utf-8", "replace"), se.decode("utf-8", "replace"))


def verdict(tool, payload, path_kind, timeout=20):
    g = stamp(tool, payload, "g", path_kind, timeout)
    x = stamp(tool, payload, "x", path_kind, timeout)
    return g[0], x[0], x[1], x[2]


MODES = ["awk"] + (["jq"] if HAVE_JQ else [])

# ---------------------------------------------------------------------------
# 1. Failure-path matrix. (id, payload bytes, expected guard exit, expected
#    extract stdout, branches named). The expected verdict is the same for
#    the jq and the jq-less reader.
# ---------------------------------------------------------------------------
A = b'"tool_name":"Agent"'
ROWS = []


def row(rid, payload, g, x, branches=()):
    if isinstance(payload, str):
        payload = payload.encode("utf-8", "surrogatepass")
    ROWS.append((rid, payload, g, x, tuple(branches)))


row("M01 tagged description allowed", b'{' + A + b',"tool_input":{"description":"(T1) item=QZT-1 x"}}', 0, "QZT-1")
row("M02 untagged description blocked", b'{' + A + b',"tool_input":{"description":"(T1) no tag"}}', 2, "", ["exit 2#2"])
row("M03 a non-agent tool passes", b'{"tool_name":"Read","tool_input":{"description":"x"}}', 0, "")
row("M04 empty payload passes (no tool named)", b"", 0, "")
row("M04b whitespace-only payload passes (no tool named)", b" \n\t ", 0, "")
row("M04c an object with no tool_name passes (not a dispatch)", b'{"tool_input":{"description":"untagged"}}', 0, "")
row("M05 a JSON array is not an object", b'[1]', 2, "",
    ['if (substr(s, pos, 1) != "{") exit 3', "exit 2", 'GATE="$(json_read -)" || PARSE_OK=0'])
row("M06 two documents", b'{' + A + b',"tool_input":{"description":"item=QZT-9"}} {' + A + b'}', 2, "",
    ['if (need == "done") exit 3'])
row("M07 a key that does not start with a quote", b'{Xtool_name":"Agent","tool_input":{"description":"(T1) item=QZT-1"}}', 2, "",
    ['if (c != "\\"") exit 3'])
row("M08 an unterminated key", b'{' + A + b',"tool_input":{"description":"item=QZT-1"},"k', 2, "")
row("M08b a raw TAB inside a key", b'{"a\t:"x","tool_name":"Agent","tool_input":{"description":"(T1) item=QZT-1"}}', 2, "",
    ["if (!parse_string()) exit 3"])
row("M09 '=' instead of a colon", b'{"tool_name"="Agent","tool_input":{"description":"(T1) item=QZT-1"}}', 2, "",
    ['if (need == "colon") { if (c != ":") exit 3; pos++; need = "value"; continue }'])
row("M10 a missing comma", b'{' + A + b' "tool_input":{"description":"item=QZT-1"}}', 2, "", ["exit 3"])
row("M11 an unknown escape before the tag", b'{' + A + b',"tool_input":{"description":"(T1) \\q item=QZT-1"}}', 2, "",
    ["} else return 0", "if (!parse_string()) exit 3#2"])
row("M12 a raw TAB inside the description (X4)", b'{' + A + b',"tool_input":{"description":"(T1)\titem=QZT-5"}}', 2, "",
    ['if (c < " ") return 0'])
row("M13 a \\u escape with a non-hex digit", b'{' + A + b',"tool_input":{"description":"(T1) \\u00zz item=QZT-1"}}', 2, "",
    ["if (cp < 0) return 0"])
row("M13b a \\u escape whose non-hex digits follow a hex one", b'{' + A + b',"tool_input":{"description":"(T1) \\u7zzz item=QZT-1"}}', 2, "",
    ["if (c == 0) return -1"])
row("M14 a \\u escape cut short by the end of input", b'{' + A + b',"tool_input":{"description":"(T1) item=QZT-1 \\u12', 2, "")
row("M15 a lone HIGH surrogate before the tag", b'{' + A + b',"tool_input":{"description":"(T1) \\ud800 item=QZT-2 x"}}', 2, "")
row("M15b a HIGH surrogate followed by six characters that are not a \\u escape",
    b'{' + A + b',"tool_input":{"description":"(T1) \\ud800XXdc00 item=QZT-2 x"}}', 2, "",
    ['if (substr(s, pos + 2, 2) != "\\\\u") return 0'])
row("M16 a high surrogate followed by a non-surrogate \\u", b'{' + A + b',"tool_input":{"description":"(T1) \\ud800\\u0041 item=QZT-2"}}', 2, "",
    ["if (lo < 56320 || lo >= 57344) return 0"])
row("M17 a lone LOW surrogate glued to the tag is U+FFFD, not a separator",
    b'{' + A + b',"tool_input":{"description":"(T1)\\udc00item=QZT-2 x"}}', 2, "")
row("M18 an invalid bare literal", b'{' + A + b',"x":tru,"tool_input":{"description":"item=QZT-1"}}', 2, "",
    ['if (tok != "true" && tok != "false" && tok != "null" && tok !~ /^-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][-+]?[0-9]+)?$/) exit 3'])
row("M19 duplicate description: tagged, then untagged", b'{' + A + b',"tool_input":{"description":"item=QZT-1 x","description":"untagged"}}', 2, "",
    ["if ((oid[d], STR) in seen) exit 3"])
row("M20 duplicate description: tagged, then null", b'{' + A + b',"tool_input":{"description":"item=QZT-1 x","description":null}}', 2, "",
    ["if ((oid[d], STR) in seen) exit 3"])
row("M21 duplicate tool_input: tagged, then a scalar", b'{' + A + b',"tool_input":{"description":"item=QZT-1 x"},"tool_input":5}', 2, "",
    ["if ((oid[d], STR) in seen) exit 3"])
row("M22 duplicate tool_name: Agent, then null (untagged)", b'{"tool_name":"Agent","tool_name":null,"tool_input":{"description":"untagged"}}', 2, "",
    ["if ((oid[d], STR) in seen) exit 3"])
row("M23 duplicate description: untagged, then tagged", b'{' + A + b',"tool_input":{"description":"untagged","description":"(T1) item=QZT-1"}}', 2, "",
    ["if ((oid[d], STR) in seen) exit 3"])
row("M24 the description sits inside an array (X6)", b'{' + A + b',"tool_input":[{"description":"item=QZT-16"}]}', 2, "")
row("M25 nesting 10000 deep is refused (the jq limit)",
    b'{' + A + b',"x":' + b"[" * 9999 + b"1" + b"]" * 9999 + b',"tool_input":{"description":"item=QZT-10"}}', 2, "",
    ["if (nw > MAXW) exit 3#2"])
row("M26 nesting 9999 deep is accepted",
    b'{' + A + b',"x":' + b"[" * 9998 + b"1" + b"]" * 9998 + b',"tool_input":{"description":"(T1) item=QZT-10"}}', 0, "QZT-10")
row("M26b objects 10000 deep are refused",
    b'{' + A + b',"x":' + b'{"a":' * 9999 + b"1" + b"}" * 9999 + b',"tool_input":{"description":"item=QZT-10"}}', 2, "",
    ["if (nw > MAXW) exit 3"])
# Round 10, F8: jq 1.8.1 charges an object that holds a container two parser
# stack entries (the object and its pending key), an array one, and refuses
# more than 10000. Before round 10 the jq-less reader counted every container
# as one: objects nested 5000-9998 deep were ALLOWED without jq and REFUSED
# with it. Each row below runs under both PATH kinds with ONE expected
# verdict, so the jq-presence dependence fails here. Boundaries measured on
# jq 1.8.1 (the payload is itself an object, weight 1; inside it each nested
# object weighs 2 and each array 1, an array inside an object 2).
def _objs(k):
    return b'{' + A + b',"x":' + b'{"a":' * k + b"1" + b"}" * k + b',"tool_input":{"description":"(T1) item=QZT-11"}}'
def _mixed(k):
    return b'{' + A + b',"x":' + b'{"a":[' * k + b"1" + b"]}" * k + b',"tool_input":{"description":"(T1) item=QZT-12"}}'
row("M26c F8: 4999 objects nested in the payload are accepted (jq accepts them)", _objs(4999), 0, "QZT-11")
row("M26d F8: 5000 objects nested in the payload are refused (jq refuses them)", _objs(5000), 2, "",
    ["if (nw > MAXW) exit 3"])
row("M26e F8: 7000 objects nested are refused under both PATH kinds", _objs(7000), 2, "")
row("M26f F8: 9998 objects nested are refused under both PATH kinds", _objs(9998), 2, "")
row("M26g F8: 3332 object/array pairs (an array inside each object) are accepted", _mixed(3332), 0, "QZT-12")
row("M26h F8: 3333 object/array pairs are refused (the innermost array weighs 10001)", _mixed(3333), 2, "",
    ["if (nw > MAXW) exit 3#2"])
row("M26i F8: 9995 arrays around {\"a\":{}} inside the payload are accepted (the inner {} weighs 2)",
    b'{' + A + b',"x":' + b"[" * 9995 + b'{"a":{}}' + b"]" * 9995 + b',"tool_input":{"description":"(T1) item=QZT-13"}}', 0, "QZT-13")
row("M26j F8: 9996 arrays around {\"a\":{}} inside the payload are refused",
    b'{' + A + b',"x":' + b"[" * 9996 + b'{"a":{}}' + b"]" * 9996 + b',"tool_input":{"description":"item=QZT-13"}}', 2, "")
row("M27 an escaped NUL before the tag is U+FFFD, not a separator",
    b'{' + A + b',"tool_input":{"description":"\\u0000item=QZT-7 t"}}', 2, "")
row("M28 an escaped NUL right after the tag ends it", b'{' + A + b',"tool_input":{"description":"(T1) item=QZT-7\\u0000"}}', 0, "QZT-7")
row("M29 a raw NUL byte inside the description", b'{' + A + b',"tool_input":{"description":"(T1) \x00item=QZT-7"}}', 2, "")
row("M30 a raw NUL byte after the document", b'{' + A + b',"tool_input":{"description":"(T1) item=QZT-7"}}\x00', 2, "")
row("M31 the document ends inside an object", b'{' + A + b',"tool_input":{"description":"item=QZT-1"}', 2, "",
    ['if (need != "done") exit 3'])
row("M32 a closing bracket that does not match", b'{' + A + b',"x":[1},"tool_input":{"description":"item=QZT-1"}}', 2, "",
    ["exit 3"])
row("M32b a missing comma between array values", b'{' + A + b',"x":[1 2],"tool_input":{"description":"(T1) item=QZT-1"}}', 2, "",
    ["exit 3"])
row("M33 empty containers are fine", b'{' + A + b',"x":[],"y":{},"z":[{},[]],"tool_input":{"description":"(T1) item=QZT-2"}}', 0, "QZT-2")
# Fixer-authored adversarial mutant A2 (round 3 resume): keying the
# duplicate-key check on the DEPTH instead of the object identity survived
# every behavioural row (only the meta-check's text noticed). It refuses two
# DIFFERENT objects that share a key at the same depth -- an ordinary hook
# payload shape (an array of todo/option objects) -- a §11.4.201(1) false
# refusal on a live hook. These rows pin the acceptance side.
row("M33b sibling objects sharing a key at the same depth are fine",
    b'{' + A + b',"a":{"k":1},"b":{"k":2},"tool_input":{"description":"(T1) item=QZT-2"}}', 0, "QZT-2")
row("M33c objects in an array sharing keys are fine",
    b'{' + A + b',"tool_input":{"todos":[{"id":1,"s":"a"},{"id":2,"s":"b"}],"description":"(T1) item=QZT-2"}}', 0, "QZT-2")
row("M34 the subagent fallback", b'{' + A + b',"tool_input":{"subagent":"(T1) item=QZT-3"}}', 0, "QZT-3")
row("M35 a key that is not a string inside tool_input", b'{' + A + b',"tool_input":{1:"item=QZT-1"}}', 2, "",
    ['if (c != "\\"") exit 3'])
row("M36 an unterminated value string", b'{' + A + b',"tool_input":{"description":"item=QZT-1', 2, "",
    [])
row("M36b a raw TAB inside the tool_name value", b'{"tool_input":{"description":"(T1) no tag"},"tool_name":"Read\t,"x":1}', 2, "",
    ["if (!parse_string()) exit 3#2"])
row("M37 escapes and a surrogate pair decode like jq", b'{' + A + b',"tool_input":{"description":"(T1) \\"q\\" \\\\ \\/ \\b\\f\\n\\r\\t \\ud83d\\ude00 item=QZT-77"}}', 0, "QZT-77")
row("M38 a BOM is not JSON", b'\xef\xbb\xbf{' + A + b',"tool_input":{"description":"item=QZT-8"}}', 2, "",
    ['GATE="$(json_read -)" || PARSE_OK=0'])
row("M38b a leading zero, nan and +1 are not JSON numbers", b'{' + A + b',"x":01,"y":nan,"z":+1,"tool_input":{"description":"item=QZT-8"}}', 2, "")
row("M39 no awk on PATH: the guard refuses, extraction is empty",
    b'{' + A + b',"tool_input":{"description":"(T1) item=QZT-1"}}', 2, "", ["exit 2"])

# T048 restart round 8 (reviewer findings F2/F3, RV3). Both rows pin an
# ABSOLUTE verdict, because the jq-vs-awk comparison alone cannot see them:
#  - M40/M40b: the shared awk reader is the gate for BOTH paths, so a reader
#    that wrongly refuses an upper-case hex digit (hexval without tolower)
#    refuses it identically with and without jq -- parity holds while a
#    legitimate payload is blocked. Only an expected "allowed" verdict kills it.
#  - M41/M41b: a top-level key literally named "tool_input.description" must
#    not be read as the nested tool_input -> description path.
row("M40 upper-case hex digits in a \\u escape decode (RV3)",
    b'{' + A + b',"tool_input":{"description":"(T1) caf\\u00C9 \\u00E9 \\uD83D\\uDE00 item=QZT-40"}}', 0, "QZT-40")
row("M40b an upper-case hex escape directly before the tag is a decoded character, not a refusal",
    b'{' + A + b',"tool_input":{"description":"(T1)\\u00A0item=QZT-41 x"}}', 2, "")
row("M41 a top-level key named tool_input.description is not the nested path (F2)",
    b'{' + A + b',"tool_input":{"description":"no tag here"},"tool_input.description":"item=QZT-9"}', 2, "")
row("M41b a dotted top-level key alone does not stand in for tool_input.description (F2)",
    b'{' + A + b',"tool_input.description":"(T1) item=QZT-9"}', 2, "")
row("M41c a dotted key inside tool_input does not stand in for description (F2)",
    b'{' + A + b',"tool_input":{"x.description":"(T1) item=QZT-9"}}', 2, "")
row("M41d a nested object keyed tool_input with a dotted child is not description (F2)",
    b'{' + A + b',"tool_input":{"a":{"b":"x"}},"tool_input.a":{"description":"(T1) item=QZT-9"}}', 2, "")

# T048 restart round 9, S2: a tool_name that is PRESENT but not a string is
# refused (fail closed); an absent one (M04c) and a string one (M01, M03) are
# not. Extraction never gates on tool_name, so the tag is still read.
for _tn in (b"null", b"5", b"true", b'["Agent"]', b'{"a":1}', b"1.5e2", b"-0"):
    row("M42 tool_name=%s is present but not a string" % _tn.decode(),
        b'{"tool_name":' + _tn + b',"tool_input":{"description":"(T1) item=QZT-1 x"}}', 2, "QZT-1")
row("M42b a non-string tool_name AFTER tool_input is just as refused",
    b'{"tool_input":{"description":"(T1) item=QZT-1 x"},"tool_name":null}', 2, "QZT-1")
row("M42c a nested tool_name of the wrong type is not THE tool_name",
    b'{"tool_name":"Read","tool_input":{"tool_name":null,"description":"x"}}', 0, "")
row("M42d a top-level key that only CONTAINS tool_name is not tool_name",
    b'{"x_tool_name":5,"tool_input":{"description":"(T1) item=QZT-2 x"},"tool_name":"Agent"}', 0, "QZT-2")
row("M42e a string tool_name written with an escape is still a string",
    b'{"tool_name":"Ag\\u0065nt","tool_input":{"description":"(T1) item=QZT-3 x"}}', 0, "QZT-3")
# S3: 700000 \u escapes (4.2 MB). Linear decoding takes seconds; the quadratic
# decoder took far longer than the 20 s limit of stamp(), a TIMEOUT verdict.
row("M43 a 4.2 MB description of 700000 \\u escapes decodes in linear time",
    b'{' + A + b',"tool_input":{"description":"(T1) item=QZT-43 ' + b"\\u00e9" * 700000 + b'"}}', 0, "QZT-43")
# P2: an awk that is not gawk-compatible is refused, extraction stays silent.
row("M39b a non-gawk awk (no RT): the guard refuses a TAGGED dispatch, extraction is empty",
    b'{' + A + b',"tool_input":{"description":"(T1) item=QZT-1 x"}}', 2, "")

# Rows that run only under one PATH kind (default: every mode in MODES).
ONLY = {"M39 no awk on PATH: the guard refuses, extraction is empty": ["noawk"],
        "M39b a non-gawk awk (no RT): the guard refuses a TAGGED dispatch, extraction is empty": ["mawk"]}
if not GAWK:
    ROWS[:] = [r for r in ROWS if not r[0].startswith("M39b")]

# Branches whose removal no payload can observe, with the reason. Each must
# still EXIST in the source (a stale entry FAILs).
EQUIVALENT = {
    "if (length(h) != 4) return -1":
        "a \\u escape shorter than 4 characters can only occur at the end of the input, where the string is "
        "unterminated and refused by the end-of-input check anyway (gawk's index(s, \"\") is 1, so without this "
        "line the short escape decodes, and the run still ends on the unterminated string)",
    "return 0":
        "parse_string's last line: the string ran to the end of the input; with it removed the caller's "
        "end-of-input check (need != \"done\") refuses the same input",
    "[ \"$rc\" -eq 0 ] || return 3":
        "jq can only fail on a document the shared strict reader already refused; this is the fail-closed "
        "backstop if the two ever disagree (the parity matrix below shows they do not on this host)",
    "TOOL_NAME=\"$(json_field tool_name)\" || PARSE_OK=0":
        "same backstop: after the reader accepted the document, reading .tool_name cannot fail",
    "TOOL_NAME_TYPE=\"$(json_type tool_name)\" || PARSE_OK=0":
        "same backstop for the tool_name type query (round 9, S2): after the reader accepted the document, "
        "asking jq or the reader for the type of .tool_name cannot fail",
    "[ \"$rc\" -eq 0 ] || return 3#2":
        "the same fail-closed backstop as the one in json_field, for json_type (round 9, S2): jq can only "
        "fail on a document the shared strict reader already refused",
    "DESCRIPTION=\"$(json_field tool_input description)\" || PARSE_OK=0":
        "same backstop for .tool_input.description",
    "DESCRIPTION=\"$(json_field tool_input subagent)\" || PARSE_OK=0":
        "same backstop for .tool_input.subagent",
    "exit 2 # FAIL CLOSED: no clean re-execution (test_dispatch_stamp.sh section P)":
        "round 11 (RV11-2): the clean-environment re-execution fails only when $BASH (derived by bash from "
        "its own argv[0]) names no executable file; no payload can reach it. It is reached and pinned by "
        "test_dispatch_stamp.sh section P, which starts the tool with an argv[0] that names no file",
}


# ---------------------------------------------------------------------------
# The branch classifier (the meta-check's instrument).
# ---------------------------------------------------------------------------
def enumerate_branches(text):
    lines = text.split("\n")
    found = {}
    in_awk = False
    for no, line in enumerate(lines, 1):
        s = line.strip()
        if not in_awk and re.search(r"\bawk\b.*'\s*$", line) and "-v" in line:
            in_awk = True
            continue
        if in_awk and s == "'":
            in_awk = False
            continue
        if s.startswith("#"):
            continue
        hit = False
        if in_awk:
            hit = bool(re.search(r"\bexit [1-9]", s) or re.search(r"\breturn -1\b", s)
                       or re.search(r"\breturn 0\b", s))
        else:
            hit = bool(re.search(r"\bexit [1-9]", s) or re.search(r"\breturn [1-9]", s)
                       or re.search(r"\|\|\s*PARSE_OK=0", s))
        if hit:
            bid, n = s, 1
            while bid in found:
                n += 1
                bid = "%s#%d" % (s, n)
            found[bid] = (no, in_awk)
    return found


def neutralise(text, lineno, in_awk):
    """Remove the branch: in awk an `if (...) <exit|return>` or `else
    <exit|return>` gets an empty action `{}` (the condition no longer stops
    anything); a statement standing alone is replaced by `{}` (exit) or
    `return 1` (a failure return made a success). In bash a non-zero exit or
    return becomes 0 and `|| PARSE_OK=0` becomes `|| :`."""
    lines = text.split("\n")
    s = lines[lineno - 1]
    if in_awk:
        action = r"(?:exit [1-9][0-9]*|return -1\b|return 0\b)"
        if re.search(r"(\)|\belse)\s*" + action, s):
            s2 = re.sub(r"((?:\)|\belse)\s*)" + action, r"\1{}", s)
        else:
            s2 = re.sub(r"\bexit [1-9][0-9]*", "{}", s)
            s2 = re.sub(r"\breturn 0\b", "return 1", s2)
    else:
        s2 = re.sub(r"\bexit [1-9][0-9]*", "exit 0", s)
        s2 = re.sub(r"\breturn [1-9][0-9]*", "return 0", s2)
        s2 = re.sub(r"\|\|\s*PARSE_OK=0", "|| :", s2)
    if s2 == s:
        return None
    lines[lineno - 1] = s2
    return "\n".join(lines)


def main():
    text = open(TOOL, encoding="utf-8", errors="surrogateescape").read()
    branches = enumerate_branches(text)
    if 'if (c < " ") return 0' in branches and any(not ia for _l, ia in branches.values()):
        out("OK", "META control: the classifier sees a known awk branch and bash branches (%d branches)" % len(branches))
    else:
        out("BAD", "META control BLIND: the classifier misses 'if (c < \" \") return 0' or every bash branch: %r" % sorted(branches))
    planted = text.replace("\nset -uo pipefail\n", "\nset -uo pipefail\n[ -n \"${R7_PLANTED:-}\" ] && exit 9\n", 1)
    pb = enumerate_branches(planted)
    named_all = {b for r in ROWS for b in r[4]} | set(EQUIVALENT)
    if '[ -n "${R7_PLANTED:-}" ] && exit 9' in pb and '[ -n "${R7_PLANTED:-}" ] && exit 9' not in named_all:
        out("OK", "META control: a branch planted into a scratch copy is enumerated and is unnamed")
    else:
        out("BAD", "META control: the planted branch was not enumerated (or is named)")

    # -- the rows on the real tool ------------------------------------------
    jobs = []
    for rid, payload, g, x, _b in ROWS:
        for m in ONLY.get(rid, MODES):
            jobs.append((rid, payload, g, x, m))
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as ex:
        res = list(ex.map(lambda j: (j, verdict(TOOL, j[1], j[4])), jobs))
    for (rid, _p, g, x, m), (grc, xrc, xo, xe) in res:
        good = grc == g and xrc == 0 and xo == x and xe == ""
        out("OK" if good else "BAD", "%s [%s]: guard=%s extract=%r extract_rc=%s extract_stderr=%r (want guard=%s extract=%r, rc 0, stderr empty)"
            % (rid, m, grc, xo, xrc, xe[:160], g, x))

    # -- meta-check: every branch named, and every named branch reached -----
    for bid, (lineno, in_awk) in sorted(branches.items(), key=lambda kv: kv[1][0]):
        if bid in EQUIVALENT:
            out("OK", "META: branch line %d %r is listed EQUIVALENT: %s" % (lineno, bid, EQUIVALENT[bid]))
            continue
        naming = [r for r in ROWS if bid in r[4]]
        if not naming:
            out("BAD", "META: branch line %d %r has NO row in the failure-path matrix" % (lineno, bid))
            continue
        mutated = neutralise(text, lineno, in_awk)
        if mutated is None:
            out("BAD", "META: branch line %d %r could not be neutralised (classifier/neutraliser mismatch)" % (lineno, bid))
            continue
        mpath = os.path.join(WORK, "neutralised_%d.sh" % lineno)
        open(mpath, "w", encoding="utf-8", errors="surrogateescape").write(mutated)
        changed = []
        for rid, payload, g, x, _b in naming:
            for m in ONLY.get(rid, MODES):
                # A removed exit can make the reader loop; a timeout is a
                # changed verdict. Stop at the first change.
                grc, xrc, xo, xe = verdict(mpath, payload, m, timeout=5)
                if (grc, xo) != (g, x) or xrc != 0:
                    changed.append("%s[%s]" % (rid.split()[0], m))
                    break
            if changed:
                break
        if changed:
            out("OK", "META: branch line %d %r is reached: removing it changes %s" % (lineno, bid, ", ".join(changed)))
        else:
            out("BAD", "META: branch line %d %r is named by %s but removing it changes no verdict (the rows do not reach it)"
                % (lineno, bid, [r[0].split()[0] for r in naming]))
    for b in sorted({b for r in ROWS for b in r[4]} - set(branches)):
        out("BAD", "META: a row names %r, which the source does not have (stale row)" % b)
    for b in sorted(set(EQUIVALENT) - set(branches)):
        out("BAD", "META: EQUIVALENT lists %r, which the source does not have (stale entry)" % b)

    # -- decode parity (round 9, T4) ---------------------------------------------
    # The refusal text quotes the DECODED description, so for an untagged
    # description with \u escapes the bytes after "Found: " are exactly what
    # the reader decoded. They must equal Python's decoding, with and without
    # jq: a wrong surrogate-pair formula, a wrong UTF-8 length boundary or a
    # wrong continuation byte changes them, which no allow/block verdict can
    # show (the decoded character is never a separator or part of a tag).
    decode_cases = [
        ("pair-emoji", "\\ud83d\\ude00"), ("pair-upper-hex", "\\uD83D\\uDE00"),
        ("pair-first", "\\ud800\\udc00"), ("pair-last", "\\udbff\\udfff"),
        ("pair-mid", "\\ud801\\udc37"), ("bmp-3byte", "\\u20ac"), ("bmp-3byte-edge", "\\uffff"),
        ("bmp-2byte", "\\u00e9"), ("bmp-2byte-edge", "\\u07ff"), ("bmp-3byte-low-edge", "\\u0800"),
        ("ascii", "\\u0041\\u007e"), ("mixed", "a\\u00e9b\\ud83d\\ude00c\\u20acd"),
    ]
    for label, esc in decode_cases:
        want = json.loads('"%s"' % esc)
        payload = ('{"tool_name":"Agent","tool_input":{"description":"%s"}}' % esc).encode()
        for m in MODES:
            g = stamp(TOOL, payload, "g", m)
            mt = re.search(r"^  Found: (.*)$", g[2], re.M)
            got = mt.group(1) if mt else None
            ok = g[0] == 2 and got == want
            out("OK" if ok else "BAD", "DECODE %s [%s]: the refusal quotes %r, want %r (guard=%s)" % (label, m, got, want, g[0]))

    # -- 2. parity ------------------------------------------------------------
    if not HAVE_JQ:
        out("SKIP", "PARITY: jq is not installed on this host; the jq-vs-awk comparison cannot run")
        return
    corpus = reviewer_corpus() + fixer_corpus() + fuzz(500, 20261008)
    pairs = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as ex:
        pairs = list(ex.map(lambda c: (c, verdict(TOOL, c[1], "jq"), verdict(TOOL, c[1], "awk")), corpus))
    bad = []
    for (name, payload), vj, va in pairs:
        if vj[0] != va[0] or vj[2] != va[2]:
            bad.append("%s: jq guard=%s extract=%r vs awk guard=%s extract=%r payload=%r"
                       % (name, vj[0], vj[2], va[0], va[2], payload[:140]))
        for tag, v in (("jq", vj), ("awk", va)):
            if v[1] != 0 or v[3] != "" or v[0] not in (0, 2):
                bad.append("%s [%s]: guard=%s extract_rc=%s extract_stderr=%r" % (name, tag, v[0], v[1], v[3][:120]))
    n_allow = sum(1 for _c, vj, _va in pairs if vj[0] == 0)
    if bad:
        out("BAD", "PARITY: %d of %d payloads differ between jq and the jq-less reader (or broke the extract contract): %s"
            % (len(bad), len(pairs), " || ".join(bad[:12])))
    else:
        out("OK", "PARITY: all %d payloads (46 reviewer corpus + %d round-8 additions + 500 seeded fuzz, seed 20261008) agree on allow/block "
            "and on the extracted id with and without jq; extract exits 0 with empty stderr in both (%d allowed, %d blocked). "
            "This is agreement on a finite corpus, evidence not proof; the failure-path rows pin the absolute verdicts"
            % (len(pairs), len(fixer_corpus()), n_allow, len(pairs) - n_allow))
    # control needles: the corpus must contain both verdicts, or the comparison proves nothing
    out("OK" if 0 < n_allow < len(pairs) else "BAD", "PARITY control: the corpus exercises both allow and block (%d allowed of %d)" % (n_allow, len(pairs)))


def reviewer_corpus():
    """The round-3 reviewer's 46 adversarial payloads (area V1 section 2),
    re-built here from the reviewer's own case table."""
    C = []
    A = '"tool_name":"Agent"'

    def add(name, raw):
        C.append(("corpus:" + name, raw if isinstance(raw, bytes) else raw.encode("utf-8", "surrogatepass")))
    add("dup-parent-obj-second-lacks-desc", '{%s,"tool_input":{"description":"(T1) item=QZT-1 x"},"tool_input":{"subagent":"y"}}' % A)
    add("dup-desc-then-null", '{%s,"tool_input":{"description":"(T1) item=QZT-1 x","description":null}}' % A)
    add("dup-desc-then-number", '{%s,"tool_input":{"description":"(T1) item=QZT-1 x","description":7}}' % A)
    add("dup-tool_input-then-scalar", '{%s,"tool_input":{"description":"(T1) item=QZT-1 x"},"tool_input":5}' % A)
    add("tool_name-then-null", '{"tool_name":"Agent","tool_name":null,"tool_input":{"description":"untagged"}}')
    add("tool_name-then-Read", '{"tool_name":"Agent","tool_input":{"description":"untagged"},"tool_name":"Read"}')
    add("nul-before-tag", '{%s,"tool_input":{"description":"\\u0000item=QZT-1 x"}}' % A)
    add("nul-mid-before-tag", '{%s,"tool_input":{"description":"(T1)\\u0000item=QZT-1 x"}}' % A)
    add("lone-high-surrogate", '{%s,"tool_input":{"description":"(T1) \\ud800 item=QZT-2 x"}}' % A)
    add("lone-low-surrogate-adjacent", '{%s,"tool_input":{"description":"(T1)\\udc00item=QZT-2 x"}}' % A)
    add("escaped-space-u0020", '{%s,"tool_input":{"description":"(T1)\\u0020item=QZT-3"}}' % A)
    add("escaped-nbsp", '{%s,"tool_input":{"description":"(T1)\\u00a0item=QZT-3"}}' % A)
    add("escaped-tab-sep", '{%s,"tool_input":{"description":"(T1)\\titem=QZT-3"}}' % A)
    add("escaped-slash", '{%s,"tool_input":{"description":"(T1) item=QZT-4\\/x"}}' % A)
    add("escaped-quote-after", '{%s,"tool_input":{"description":"(T1) item=QZT-4\\"x"}}' % A)
    add("uppercase-U-escape", '{%s,"tool_input":{"description":"(T1)\\U0020item=QZT-5"}}' % A)
    add("short-u-escape", '{%s,"tool_input":{"description":"(T1)\\u02item=QZT-5"}}' % A)
    add("raw-tab-in-string", '{%s,"tool_input":{"description":"(T1)\titem=QZT-5"}}' % A)
    add("raw-newline-in-string", '{%s,"tool_input":{"description":"(T1)\nitem=QZT-5"}}' % A)
    add("raw-del-0x7f", '{%s,"tool_input":{"description":"(T1)\x7fitem=QZT-5"}}' % A)
    add("invalid-utf8-before", b'{"tool_name":"Agent","tool_input":{"description":"(T1)\xff item=QZT-6"}}')
    add("invalid-utf8-adjacent", b'{"tool_name":"Agent","tool_input":{"description":"(T1) item=QZT-6\xff"}}')
    add("bom-prefix", b'\xef\xbb\xbf{"tool_name":"Agent","tool_input":{"description":"(T1) item=QZT-7"}}')
    add("leading-zero-number", '{%s,"x":01,"tool_input":{"description":"(T1) item=QZT-8"}}' % A)
    add("nan-literal", '{%s,"x":nan,"tool_input":{"description":"(T1) item=QZT-8"}}' % A)
    add("NaN-literal", '{%s,"x":NaN,"tool_input":{"description":"(T1) item=QZT-8"}}' % A)
    add("plus-number", '{%s,"x":+1,"tool_input":{"description":"(T1) item=QZT-8"}}' % A)
    add("trailing-comma", '{%s,"tool_input":{"description":"(T1) item=QZT-8"},}' % A)
    add("multi-doc-tag-in-first", '{"tool_input":{"description":"item=QZT-9"}} {%s,"tool_input":{"description":"untagged"}}' % A)
    add("multi-doc-tag-in-second", '{%s,"tool_input":{"description":"untagged"}} {"tool_input":{"description":"item=QZT-9"}}' % A)
    add("deep-nesting-1100", '{%s,"x":%s1%s,"tool_input":{"description":"(T1) item=QZT-10"}}' % (A, "[" * 1100, "]" * 1100))
    add("deep-nesting-12000", '{%s,"x":%s1%s,"tool_input":{"description":"(T1) item=QZT-10"}}' % (A, "[" * 12000, "]" * 12000))
    add("key-with-escape-description", '{%s,"tool_input":{"descr\\u0069ption":"(T1) item=QZT-11"}}' % A)
    add("key-dotted", '{%s,"tool_input.description":"(T1) item=QZT-12","tool_input":{"description":"untagged"}}' % A)
    add("cr-whitespace", '{\r%s\r,\r"tool_input"\r:\r{"description":"(T1) item=QZT-13"}}' % A)
    add("formfeed-whitespace", '{\f%s,"tool_input":{"description":"(T1) item=QZT-13"}}' % A)
    add("vt-whitespace", '{\v%s,"tool_input":{"description":"(T1) item=QZT-13"}}' % A)
    add("subagent-fallback-when-desc-empty", '{%s,"tool_input":{"description":"","subagent":"(T1) item=QZT-14"}}' % A)
    add("desc-array", '{%s,"tool_input":{"description":["item=QZT-15"],"subagent":"untagged"}}' % A)
    add("tool_input-array", '{%s,"tool_input":[{"description":"item=QZT-16"}]}' % A)
    add("escaped-backslash-u", '{%s,"tool_input":{"description":"(T1)\\\\u0020item=QZT-17"}}' % A)
    add("supplementary-raw-before", '{%s,"tool_input":{"description":"(T1)\U0001F600item=QZT-18"}}' % A)
    add("emoji-escaped-pair", '{%s,"tool_input":{"description":"(T1)\\ud83d\\ude00 item=QZT-18"}}' % A)
    add("Task-tool", '{"tool_name":"Task","tool_input":{"description":"untagged"}}')
    add("empty-object", '{}')
    add("whitespace-only", '   \n ')
    assert len(C) == 46, len(C)
    return C


def fixer_corpus():
    """Round-8 additions (reviewer findings F2/F3): a top-level key that
    CONTAINS a dot, and upper-case hex digits in \\u escapes, in the shapes
    the original 46 did not cover."""
    C = []
    A = '"tool_name":"Agent"'

    def add(name, raw):
        C.append(("fixer:" + name, raw if isinstance(raw, bytes) else raw.encode("utf-8", "surrogatepass")))
    add("dotted-key-after-nested-untagged", '{%s,"tool_input":{"description":"no tag here"},"tool_input.description":"item=QZT-9"}' % A)
    add("dotted-key-before-nested-untagged", '{%s,"tool_input.description":"item=QZT-9","tool_input":{"description":"no tag here"}}' % A)
    add("dotted-key-alone", '{%s,"tool_input.description":"(T1) item=QZT-9"}' % A)
    add("dotted-key-alone-with-subagent-fallback", '{%s,"tool_input":{"subagent":"(T1) item=QZT-9"},"tool_input.subagent":"x"}' % A)
    add("dotted-key-inside-tool_input", '{%s,"tool_input":{"x.description":"(T1) item=QZT-9"}}' % A)
    add("dotted-parent-key", '{%s,"tool_input.a":{"description":"(T1) item=QZT-9"},"tool_input":{"a":{}}}' % A)
    add("digit-colon-key-lookalike", '{%s,"tool_input":{"1:description":"(T1) item=QZT-9"}}' % A)
    add("upper-hex-escape-before-text", '{%s,"tool_input":{"description":"(T1) \\u00C9 item=QZT-9 x"}}' % A)
    add("upper-hex-surrogate-pair", '{%s,"tool_input":{"description":"(T1) \\uD83D\\uDE00 item=QZT-9 x"}}' % A)
    add("upper-hex-lone-high-surrogate", '{%s,"tool_input":{"description":"(T1) \\uD800 item=QZT-9 x"}}' % A)
    add("upper-hex-lone-low-surrogate", '{%s,"tool_input":{"description":"(T1) \\uDC00item=QZT-9 x"}}' % A)
    add("mixed-case-hex-escape", '{%s,"tool_input":{"description":"(T1) \\u00aF item=QZT-9"}}' % A)
    add("upper-hex-escape-in-key", '{%s,"tool_input":{"descr\\u0049ption":"(T1) item=QZT-9"}}' % A)
    add("upper-hex-bad-digit-G", '{%s,"tool_input":{"description":"(T1) \\u00G9 item=QZT-9"}}' % A)
    # round 9 (S2): the type of tool_name, present or absent
    for name, val in (("null", "null"), ("number", "5"), ("true", "true"), ("array", '["Agent"]'),
                      ("object", '{"a":1}'), ("exp", "1.5e2"), ("string-read", '"Read"'), ("empty-string", '""')):
        add("tool_name-%s" % name, '{"tool_name":%s,"tool_input":{"description":"(T1) item=QZT-9 x"}}' % val)
    add("tool_name-absent", '{"tool_input":{"description":"(T1) item=QZT-9 x"}}')
    add("tool_name-after-null", '{"tool_input":{"description":"untagged"},"tool_name":null}')
    add("tool_name-nested-wrong-type", '{"tool_name":"Read","tool_input":{"tool_name":5}}')
    add("tool_name-key-lookalike", '{"x_tool_name":5,"tool_input":{"description":"(T1) item=QZT-9 x"}}')
    return C


def fuzz(n, seed):
    """Seeded generator of hook-shaped payloads: well-formed and broken JSON,
    duplicate keys, every boundary character around the tag, escapes,
    surrogates, raw control and invalid UTF-8 bytes, odd whitespace and
    numbers, extra documents and deep nesting."""
    rnd = random.Random(seed)
    lefts = [" ", "\t", "\n", "\r", "\v", "\f", "\u0000", "\u0001", "\u001c", "\u0085", "\u00a0", "\u2003",
             "\u3000", "\ufeff", "x", "(", "", "\udc00", "\ud800"]
    rights = ["", " ", ",", ")", "\r", "\u0000", "\u00e9", "x", "_", "7", "\udc00"]
    values = ["QZT-1", "QZT-12", "?", "QZT-", "ATM-5", "qzt-3"]
    ws = [b"", b" ", b"\t", b"\n", b"\r", b"\f", b"\v"]

    def jstr(s):
        mode = rnd.random()
        if mode < 0.15:
            # raw (no escaping of control characters) -- often invalid JSON
            body = s.encode("utf-8", "surrogatepass").replace(b"\\", b"\\\\").replace(b'"', b'\\"')
        else:
            body = json.dumps(s, ensure_ascii=rnd.random() < 0.6)[1:-1].encode("utf-8", "surrogatepass")
            if rnd.random() < 0.2 and body:
                k = rnd.randrange(len(body) + 1)
                body = body[:k] + rnd.choice([b"\\u0020", b"\\u0000", b"\\ud800", b"\\udc00", b"\\ud83d\\ude00",
                                               b"\\q", b"\\u12", b"\xff", b"\xc3", b"\x00", b"\x01", b"\\/"]) + body[k:]
        return b'"' + body + b'"'

    def desc():
        return "%s%sitem=%s%s %s" % (rnd.choice(["(T1/main - a)", "", "x"]), rnd.choice(lefts),
                                    rnd.choice(values), rnd.choice(rights), rnd.choice(["t", ""]))

    def scalar():
        return rnd.choice([b"null", b"true", b"false", b"1", b"-0", b"2.5e3", b"01", b"+1", b"nan", b"tru",
                           jstr("plain"), jstr(desc())])

    def obj(pairs):
        sep = rnd.choice(ws)
        inner = (b"," + sep).join(jstr(k) + sep + b":" + sep + v for k, v in pairs)
        if rnd.random() < 0.05:
            inner += b","
        return b"{" + sep + inner + sep + b"}"

    def tool_input():
        pairs = []
        for k in rnd.sample(["description", "subagent", "prompt", "meta", "description"], rnd.randint(0, 4)):
            if k in ("description", "subagent"):
                v = jstr(desc()) if rnd.random() < 0.85 else scalar()
            elif k == "meta":
                v = obj([("description", jstr(desc()))]) if rnd.random() < 0.5 else b"[" + jstr(desc()) + b"]"
            else:
                v = jstr("prompt text")
            pairs.append((k, v))
        if rnd.random() < 0.1 and pairs:
            pairs.append(rnd.choice(pairs))  # duplicate key
        if rnd.random() < 0.07:
            return b"[" + obj(pairs) + b"]"
        return obj(pairs)

    res = []
    for i in range(n):
        pairs = []
        keys = ["tool_name", "tool_input"] + (["x"] if rnd.random() < 0.3 else [])
        rnd.shuffle(keys)
        for k in keys:
            if k == "tool_name":
                v = rnd.choice([jstr("Agent"), jstr("Task"), jstr("TaskCreate"), jstr("Read"), b"null", b"1"])
            elif k == "tool_input":
                v = tool_input()
            else:
                depth = rnd.choice([1, 3, 50, 9998, 9999])
                v = b"[" * depth + scalar() + b"]" * depth
            pairs.append((k, v))
        if rnd.random() < 0.06:
            pairs.append((rnd.choice(["tool_name", "tool_input"]), rnd.choice([b"null", b"5", jstr("Read")])))
        doc = obj(pairs)
        r = rnd.random()
        if r < 0.04:
            doc = doc + rnd.choice(ws) + obj([("tool_input", tool_input())])
        elif r < 0.06:
            doc = b"\xef\xbb\xbf" + doc
        elif r < 0.08:
            doc = doc + b"\x00"
        res.append(("fuzz#%03d" % i, doc))
    return res


main()
PYEOF
DRIVER_RC=$?

while IFS=$'\t' read -r kind text; do
  case "$kind" in
    OK) PASS=$((PASS + 1)); printf '  PASS  %s\n' "$text" ;;
    BAD) FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$text" ;;
    SKIP) printf '  SKIP  %s\n' "$text" ;;
    *) FAIL=$((FAIL + 1)); printf '  FAIL  driver output: %s %s\n' "$kind" "$text" ;;
  esac
done < "$WORK/driver.out"
if [ "$DRIVER_RC" -ne 0 ]; then
  FAIL=$((FAIL + 1)); echo "  FAIL  the matrix driver exited $DRIVER_RC"
fi
# Control needle: the driver must have produced verdicts at all.
if [ "$((PASS + FAIL))" -lt 40 ]; then
  FAIL=$((FAIL + 1)); echo "  FAIL  control: only $((PASS + FAIL)) verdicts were produced (want >= 40)"
fi
echo
echo "  total: PASS=$PASS FAIL=$FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo "  RESULT: FAIL"
  exit 1
fi
echo "  RESULT: PASS (all $PASS checks)"
exit 0
