#!/bin/sh
# fastcycle-timeout-s: 7200
# =============================================================================
# test_precheck_shellcheck_delta_mutants.sh (ATM-1217 r3 + r4 + r5)
# Paired 1.1 mutation harness for test_precheck_shellcheck_baseline_delta.sh.
# Each mutant is a one-place semantic break of the baseline-delta rule, its
# dispatchers or its seams with the round-5/6 gate, applied to a SCRATCH COPY of
# the review tree; the suite is run against that copy (FC_OVERRIDE) and the mutant
# is KILLED when the suite exits 1 (a case failed). Exit 2 (environment) or any
# other code is reported INVALID-RUN, never counted as a kill. A SURVIVOR means a
# rule with no teeth -> exit 1.
#
# A mutant whose search string does not occur exactly once is INVALID (never a
# kill): a stale mutant is decoration, not proof.
#
# M01-M21: the r2 mutant set, re-targeted at the r3 code (where the r2 mechanism
# was dropped as redundant with the round-6 gate, the mutant targets the round-6
# mechanism that now carries the property -- see r3/DESIGN.md section 6).
# S01-S08: new mutants on the MERGE SEAMS between the delta rule and the round-6 gate.
# R01-R14 (r4): the independent reviewer's 14 mutants of the r3 review, VERBATIM (11.4.276(D):
# every reviewer-surviving mutant must FAIL the suite before the next review).
# F01-F18 (r4): the F1 class (base content not proven gated at base), the F2 window-boundary
# proof, F5 (unchanged files policed) and F8 (dispatch activation).
# X01-X08 (r5): the independent reviewer's 8 mutants of the r4 review, VERBATIM.
# P01-P11 (r5): successors on the r5 code (no window fallback; committed activation record).
# r5 RETIRED: a mutant whose needle the r5 structural change deleted (the window fallback, its lexer, the
# working-tree activation check) is kept verbatim and marked RETIRED; the harness PROVES its needle is absent
# (if it ever comes back the mutant is run and must be killed). Retired is never counted as killed.
#
# Usage: sh test_precheck_shellcheck_delta_mutants.sh [-j N]   (default -j 4)
# =============================================================================
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
JOBS=4
[ "${1:-}" = "-j" ] && JOBS=${2:-4}
SUITE="$HERE/test_precheck_shellcheck_baseline_delta.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

cat >"$TMP/mutants.py" <<'PYEOF'
RUN = "lib/precheck_pack_run.py"
BRUN = "lib/precheck_pack_build_run.py"
SH = "precheck_pack.sh"
BUILD = "precheck_pack_build.sh"
# 5th field: None = active (must be KILLED); a string = RETIRED by the r5 structural change: the harness then
# requires the needle to be ABSENT (it proves the targeted code is gone); if the needle comes back the mutant
# is run again and must be killed.
MUTANTS = [
 ('M01-key-includes-raw-line', RUN,
  '    return ("SC%s" % c.get("code"), msg, _line_text(lines, c.get("line")))',
  '    return ("SC%s" % c.get("code"), msg, _line_text(lines, c.get("line")), c.get("line"))',
  None),
 ('M02-set-not-multiset', RUN,
  '        n_old = min(len(occ), budget.get(k, 0))',
  '        n_old = len(occ) if k in budget else 0',
  None),
 ('M03-rc-empty-read-as-clean', RUN,
  '    if not out.strip():  # json1 always prints {"comments":[...]}; silence is not "clean"',
  '    if not out.strip():\n        out = "{\\"comments\\": []}"\n    if False:',
  None),
 ('M04-timeout-hardcoded', RUN,
  '    sc_timeout = opts.get("timeout") or _default_sc_timeout(rule)',
  '    sc_timeout = 30',
  None),
 ('M05-floor-ignored-in-delta', RUN,
  '        blocking = [c for c in comments if _blocking(c)]',
  '        blocking = list(comments)',
  None),
 ('M06-new-file-passes', RUN,
  '                (findings if _blocking(c) else advisory).append(f_)',
  '                (findings if _blocking(c) and dfile is None else advisory).append(f_)',
  None),
 ('M07-rename-ignored', RUN,
  '            base_rel = renames.get(rel, rel)',
  '            base_rel = rel',
  None),
 ('M08-window-reported-as-full', RUN,
  '        dfile["state"] = "window"',
  '        dfile["state"] = "full"',
  'r5 removed the window fallback (_window_delta / _window_snippet / _windows / _hunk_ranges); a side that cannot be linted whole is BLIND (head) or no baseline (base) -- successors P01-P06'),
 ('M09-unlintable-window-ignored', RUN,
  '        if any(1000 <= int(c.get("code") or 0) < 2000 for c in com):',
  '        if False:',
  'r5 removed the window fallback (_window_delta / _window_snippet / _windows / _hunk_ranges); a side that cannot be linted whole is BLIND (head) or no baseline (base) -- successors P01-P06'),
 ('M10-memory-cap-not-applied-to-delta-lints', RUN,
  '            t = min(sc_timeout, left)\n            com, er, to, _el = _run_shellcheck(_flag, data, t, mem_cap)',
  '            t = min(sc_timeout, left)\n            com, er, to, _el = _run_shellcheck(_flag, data, t, 8192)',
  None),
 ('M11-no-base-reads-as-delta', RUN,
  '    delta_on = rule == "baseline-delta" and baseline is not None',
  '    delta_on = rule == "baseline-delta"',
  None),
 ('M12-unchanged-shortcut-inverted', RUN,
  '        return ("unchanged" if blob == cdata else "delta"), blob, ""',
  '        return ("unchanged" if blob != cdata else "delta"), blob, ""',
  None),
 ('M13-new-directive-violation-ignored', RUN,
  '                dir_viol.append(rec)',
  '                pass',
  None),
 ('M14-timeout-ceiling-not-refused', RUN,
  '    for name, ceiling in (("shellcheck_timeout", MAX_SC_TIMEOUT), ("shellcheck_exception_timeout", MAX_EXCEPTION_TIMEOUT)):',
  '    for name, ceiling in ():',
  None),
 ('M15-window-base-side-dropped', RUN,
  '    hw, bw = _windows(hl, new_r), _windows(bl, old_r)',
  '    hw, bw = _windows(hl, new_r), []',
  'r5 removed the window fallback (_window_delta / _window_snippet / _windows / _hunk_ranges); a side that cannot be linted whole is BLIND (head) or no baseline (base) -- successors P01-P06'),
 ('M16-window-line-not-translated', RUN,
  '                    c[k] = 1 if on_prefix else c[k] + off',
  '                    c[k] = 1 if on_prefix else c[k]',
  'r5 removed the window fallback (_window_delta / _window_snippet / _windows / _hunk_ranges); a side that cannot be linted whole is BLIND (head) or no baseline (base) -- successors P01-P06'),
 ('M17-whole-file-window-guard-removed', RUN,
  '    if head_failed and len(hw) == 1 and hw[0][0] == 1 and hw[0][1] >= len(hl):',
  '    if False:',
  'r5 removed the window fallback (_window_delta / _window_snippet / _windows / _hunk_ranges); a side that cannot be linted whole is BLIND (head) or no baseline (base) -- successors P01-P06'),
 ('M18-cli-timeout-ignored', RUN,
  '    sc_timeout = opts.get("timeout") or _default_sc_timeout(rule)',
  '    sc_timeout = _default_sc_timeout(rule)',
  None),
 ('M19-dispatcher-drops-rule', SH,
  'if [ -n "$SC_RULE" ]; then set -- "$@" --shellcheck-rule "$SC_RULE"; fi',
  ':',
  None),
 ('M20-base-failure-read-as-clean', RUN,
  '        if berr:\n            delta_window(rel, dfile, cdata, bdata, flag, False, True, ["base: " + berr], False)\n            return',
  '        if berr:\n            return',
  'r5 removed the window fallback (_window_delta / _window_snippet / _windows / _hunk_ranges); a side that cannot be linted whole is BLIND (head) or no baseline (base) -- successors P01-P06'),
 ('M21-build-wrapper-drops-rule', BUILD,
  'if [ -n "$SC_RULE" ]; then set -- "$@" --shellcheck-rule "$SC_RULE"; fi',
  ':',
  None),
 ('S01-exception-row-goes-delta', RUN,
  '        if delta_on and row is None:',
  '        if delta_on:',
  None),
 ('S02-forbidden-directive-tolerated', RUN,
  '        if d["violations"] and all(v.startswith("D5") for v in d["violations"]):',
  '        if d["violations"]:',
  None),
 ('S03-delta-default-timeout-not-rule-aware', RUN,
  '    return DEFAULT_SC_TIMEOUT_DELTA if rule == "baseline-delta" else DEFAULT_SC_TIMEOUT',
  '    return DEFAULT_SC_TIMEOUT',
  None),
 ('S04-cache-ignores-rule', BRUN,
  '    if tool.get("rule", gate.DEFAULT_SC_RULE) != rule:  # ATM-1217: the rule changes the verdict',
  '    if False:',
  None),
 ('S05-size-cap-blind-not-windowed', RUN,
  '            if dstate == "delta" and cap_problem is None and (len(clines) > max_lines or len(cdata) > max_bytes):',
  '            if False:',
  'r5 removed the window fallback (_window_delta / _window_snippet / _windows / _hunk_ranges); a side that cannot be linted whole is BLIND (head) or no baseline (base) -- successors P01-P06'),
 ('S07-verifier-refuses-delta-mode', BRUN,
  '        if mode == "baseline-delta":',
  '        if False:',
  None),
 ('S08-verifier-accepts-inconsistent-delta', BRUN,
  '            if rule != "baseline-delta" or dl.get("base_resolved") is not True or not dl.get("rule_id"):',
  '            if False:',
  None),
 ('S06-delta-default-rule', RUN,
  'DEFAULT_SC_RULE = "whole-file"',
  'DEFAULT_SC_RULE = "baseline-delta"',
  None),
 ('R01-verifier-drops-base_resolved', BRUN,
  '            if rule != "baseline-delta" or dl.get("base_resolved") is not True or not dl.get("rule_id"):',
  '            if rule != "baseline-delta" or not dl.get("rule_id"):',
  None),
 ('R02-verifier-drops-rule_id', BRUN,
  '            if rule != "baseline-delta" or dl.get("base_resolved") is not True or not dl.get("rule_id"):',
  '            if rule != "baseline-delta" or dl.get("base_resolved") is not True:',
  None),
 ('R03-verifier-wholefile-accepts-any-rule', BRUN,
  '        elif mode != "whole-file" or rule != "whole-file":',
  '        elif mode != "whole-file":',
  None),
 ('R04-key-drops-line-text', RUN,
  '    return ("SC%s" % c.get("code"), msg, _line_text(lines, c.get("line")))',
  '    return ("SC%s" % c.get("code"), msg)',
  None),
 ('R05-line-ref-not-normalised', RUN,
  '    msg = _LINE_REF_RE.sub("line N", " ".join(str(c.get("message") or "").split()))',
  '    msg = " ".join(str(c.get("message") or "").split())',
  None),
 ('R06-base-whole-window-guard-removed', RUN,
  '    if base_failed and len(bw) == 1 and bw[0][0] == 1 and bw[0][1] >= len(bl):',
  '    if False:',
  'r5 removed the window fallback (_window_delta / _window_snippet / _windows / _hunk_ranges); a side that cannot be linted whole is BLIND (head) or no baseline (base) -- successors P01-P06'),
 ('R07-window-max-lines-removed', RUN,
  '    if total > WINDOW_MAX_LINES:',
  '    if False:',
  'r5 removed the window fallback (_window_delta / _window_snippet / _windows / _hunk_ranges); a side that cannot be linted whole is BLIND (head) or no baseline (base) -- successors P01-P06'),
 ('R08-oldest-occurrences-new', RUN,
  '        old.extend(occ[:n_old])\n        new.extend(occ[n_old:])',
  '        old.extend(occ[len(occ)-n_old:])\n        new.extend(occ[:len(occ)-n_old])',
  None),
 ('R09-untracked-base-unchanged', RUN,
  '    return "new-file", None, st  # untracked-at-base | symlink | gitlink at base: no regular base to compare',
  '    return "unchanged", None, st',
  None),
 ('R10-head-window-not-differential', RUN,
  '    ok, hitems, why = _lint_window_side(cdata, hw, lint, True, flag)',
  '    ok, hitems, why = _lint_window_side(cdata, hw, lint, False, flag)',
  'r5 removed the window fallback (_window_delta / _window_snippet / _windows / _hunk_ranges); a side that cannot be linted whole is BLIND (head) or no baseline (base) -- successors P01-P06'),
 ('R11-base-large-lock-skipped', RUN,
  '        if len(blines) >= LARGE_LINES:',
  '        if False:',
  None),
 ('R12-window-snippet-generic-shebang', RUN,
  '    first = raw[0] if raw and raw[0].startswith(b"#!") else b"#!/bin/sh"',
  '    first = b"#!/bin/sh"',
  'r5 removed the window fallback (_window_delta / _window_snippet / _windows / _hunk_ranges); a side that cannot be linted whole is BLIND (head) or no baseline (base) -- successors P01-P06'),
 ('R13-hunk-rc-unchecked', RUN,
  '    if p.returncode not in (0, 1):\n        return None, None',
  '    if False:\n        return None, None',
  'r5 removed the window fallback (_window_delta / _window_snippet / _windows / _hunk_ranges); a side that cannot be linted whole is BLIND (head) or no baseline (base) -- successors P01-P06'),
 ('R14-params-mismatch-ignores-rule-default', BRUN,
  '            ("--shellcheck-timeout", sc_timeout, "timeout_s", gate._default_sc_timeout(rule)),',
  '            ("--shellcheck-timeout", sc_timeout, "timeout_s", gate.DEFAULT_SC_TIMEOUT),',
  None),
 ('F01-base-not-shell-accepted', RUN,
  '    if not (base_rel.endswith(_SHELL_EXTS) or _bytes_are_shell(blob)):',
  '    if False:',
  None),
 ('F02-base-shebang-read-from-head-bytes', RUN,
  '    if not (base_rel.endswith(_SHELL_EXTS) or _bytes_are_shell(blob)):',
  '    if not (base_rel.endswith(_SHELL_EXTS) or _bytes_are_shell(cdata)):',
  None),
 ('F03-base-nul-accepted', RUN,
  '    if b"\\0" in blob:',
  '    if False:',
  None),
 ('F04-base-ledger-unknown-accepted', RUN,
  '    if base_ex_rows is None:',
  '    if False:',
  None),
 ('F05-dropped-exception-row-laundered', RUN,
  '    if base_rel in base_ex_rows:',
  '    if False:',
  None),
 ('F06-dialect-change-accepted', RUN,
  '    if bd != hd:',
  '    if False:',
  None),
 ('F07-unchanged-not-policed', RUN,
  '                delta_police(rel, dirs, bdata)\n                continue',
  '                continue',
  None),
 ('F08-window-boundaries-not-snapped', RUN,
  '        snapped, why = _snap_windows(hw if side == "head" else bw, ok, nlines)',
  '        snapped, why = (hw if side == "head" else bw), None',
  'r5 removed the window fallback and its boundary lexer (_neutral_boundaries); every lint input is a whole blob -- the G-class cases + census pin the replacement'),
 ('F09-lexer-heredoc-untracked', RUN,
  '                pending.append((word, m.group(1) == "-"))',
  '                pass',
  'r5 removed the window fallback and its boundary lexer (_neutral_boundaries); every lint input is a whole blob -- the G-class cases + census pin the replacement'),
 ('F10-lexer-double-quote-untracked', RUN,
  '            if ch == \'"\':\n                stack.append(("dq", 0))',
  '            if ch == \'"\':\n                pass',
  'r5 removed the window fallback and its boundary lexer (_neutral_boundaries); every lint input is a whole blob -- the G-class cases + census pin the replacement'),
 ('F11-lexer-single-quote-untracked', RUN,
  '            if ch == "\'":\n                stack.append(("sq", 0))',
  '            if ch == "\'":\n                pass',
  'r5 removed the window fallback and its boundary lexer (_neutral_boundaries); every lint input is a whole blob -- the G-class cases + census pin the replacement'),
 ('F12-lexer-case-in-cmd-guessed', RUN,
  '                return ok, "line %d: \'case\' inside a command substitution (paren counting unsound)" % (i + 1)',
  '                pass',
  'r5 removed the window fallback and its boundary lexer (_neutral_boundaries); every lint input is a whole blob -- the G-class cases + census pin the replacement'),
 ('F13-prefix-finding-not-line-1', RUN,
  '            on_prefix = off != 0 and c.get("line") == 1  # the prefixed shebang IS real line 1, not line a-1',
  '            on_prefix = False',
  'r5 removed the window fallback (_window_delta / _window_snippet / _windows / _hunk_ranges); a side that cannot be linted whole is BLIND (head) or no baseline (base) -- successors P01-P06'),
 ('F14-line1-not-deduplicated', RUN,
  '                if k1 in line1_seen:\n                    continue',
  '                if False:\n                    continue',
  'r5 removed the window fallback (_window_delta / _window_snippet / _windows / _hunk_ranges); a side that cannot be linted whole is BLIND (head) or no baseline (base) -- successors P01-P06'),
 ('F15-verifier-activation-not-required', BRUN,
  '            if deep:\n                # r4 F8',
  '            if False:\n                # r4 F8',
  None),
 ('F16-verifier-rule-id-value-unchecked', BRUN,
  '            if dl.get("rule_id") and dl.get("rule_id") != _g.DELTA_RULE_ID:',
  '            if False:',
  None),
 ('F17-activation-record-not-validated', BRUN,
  '    if len(ref) < 8 or not _re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", day):',
  '    if False:',
  None),
 ('F19-lexer-eof-consistency-unchecked', RUN,
  '        if not lex_why and not ok[nlines]:',
  '        if False:',
  'r5 removed the window fallback and its boundary lexer (_neutral_boundaries); every lint input is a whole blob -- the G-class cases + census pin the replacement'),
 ('F18-lexer-continuation-ignored', RUN,
  '                if j + 1 >= L:\n                    cont = True',
  '                if False:\n                    cont = True',
  'r5 removed the window fallback and its boundary lexer (_neutral_boundaries); every lint input is a whole blob -- the G-class cases + census pin the replacement'),
 ('X01-activation-ref-len-dropped', BRUN,
  '    if len(ref) < 8 or not _re.fullmatch',
  '    if not _re.fullmatch',
  None),
 ('X02-heredoc-dash-strips-spaces', RUN,
  'if (line.lstrip("\\t") if strip else line) == word:',
  'if (line.strip() if strip else line) == word:',
  'r5 removed the window fallback and its boundary lexer (_neutral_boundaries); every lint input is a whole blob -- the G-class cases + census pin the replacement'),
 ('X03-activation-symlink-accepted', BRUN,
  '    if os.path.islink(path) or not os.path.isfile(path):',
  '    if not os.path.isfile(path):',
  'r5 G3 replaced the working-tree activation check with a read of the COMMITTED record at the pack base -- successors P07-P11'),
 ('X04-arith-depth-1', RUN,
  '        stack.append(("arith", 2))',
  '        stack.append(("arith", 1))',
  'r5 removed the window fallback and its boundary lexer (_neutral_boundaries); every lint input is a whole blob -- the G-class cases + census pin the replacement'),
 ('X05-dialect-shebang-only', RUN,
  '    if bd != hd:',
  '    if bd[0] != hd[0]:',
  None),
 ('X06-comment-left-brace', RUN,
  '_COMMENT_LEFT = " \\t;&|()<>`"',
  '_COMMENT_LEFT = " \\t;&|()<>`}"',
  'r5 removed the window fallback and its boundary lexer (_neutral_boundaries); every lint input is a whole blob -- the G-class cases + census pin the replacement'),
 ('X07-selfconsistency-dropped', RUN,
  '        if not lex_why and not ok[nlines]:',
  '        if False:',
  'r5 removed the window fallback and its boundary lexer (_neutral_boundaries); every lint input is a whole blob -- the G-class cases + census pin the replacement'),
 ('X08-heredoc-delim-trailing-ws', RUN,
  'if (line.lstrip("\\t") if strip else line) == word:',
  'if (line.lstrip("\\t") if strip else line).rstrip() == word:',
  'r5 removed the window fallback and its boundary lexer (_neutral_boundaries); every lint input is a whole blob -- the G-class cases + census pin the replacement'),
 ('P01-head-unlintable-delta-skipped', RUN,
  '                delta_head_blind(dfile, err)  # r5: a head that cannot be linted whole is BLIND (never a window)\n                hint',
  '                if dfile is not None and dstate == "delta":\n                    continue\n                hint',
  None),
 ('P02-base-unlintable-findings-dropped', RUN,
  '        for c in blocking:\n            findings.append(dict(_finding(rel, c, _line_text(clines, c.get("line"))), new_in="new-file"))',
  '        for c in []:\n            findings.append(dict(_finding(rel, c, _line_text(clines, c.get("line"))), new_in="new-file"))',
  None),
 ('P03-base-size-cap-ignored', RUN,
  '        if len(blines) > max_lines or len(bdata) > max_bytes:\n            delta_base_unlintable(',
  '        if False:\n            delta_base_unlintable(',
  None),
 ('P04-base-lint-error-read-as-clean', RUN,
  '        if berr:\n            delta_base_unlintable(rel, dfile, blocking, clines, berr)\n            return',
  '        if berr:\n            return',
  None),
 ('P05-blind-state-not-recorded', RUN,
  '            dfile["state"] = "blind"',
  '            pass',
  None),
 ('P06-head-size-cap-skipped-for-delta', RUN,
  '        if len(clines) > max_lines or len(cdata) > max_bytes:\n            msg = ("BLIND (fails closed)',
  '        if dfile is None and (len(clines) > max_lines or len(cdata) > max_bytes):\n            msg = ("BLIND (fails closed)',
  None),
 ('P07-activation-read-at-gate-head', BRUN,
  '        return gate_top, base, None',
  '        return gate_top, "HEAD", None',
  None),
 ('P08-activation-symlink-mode-accepted', BRUN,
  '    if len(meta) != 3 or meta[1] != b"blob" or meta[0] not in (b"100644", b"100755"):',
  '    if len(meta) != 3 or meta[1] != b"blob":',
  None),
 ('P09-activation-worktree-fallback', BRUN,
  '    if not rec:\n        out["error"] = ("no operator activation record committed',
  '    if not rec and os.path.isfile(os.path.join(os.path.dirname(_HERE), DELTA_ACTIVATION_REL)):\n        return dict(out, decision_ref="worktree", activated_on="2026-10-13")\n    if not rec:\n        out["error"] = ("no operator activation record committed',
  None),
 ('P10-activation-gitlink-mode-unchecked', BRUN,
  '    if len(parts) != 3 or parts[0] != b"160000" or parts[1] != b"commit":',
  '    if len(parts) != 3:',
  None),
 ('P11-activation-submodule-read-at-pack-base', BRUN,
  '    return gate_top, parts[2].decode("ascii"), None',
  '    return gate_top, base, None',
  None),
]
PYEOF

python3 - "$TMP/mutants.py" "$TMP/list.tsv" <<'PY'
import sys
ns = {}
exec(open(sys.argv[1]).read(), ns)
with open(sys.argv[2], "w") as fh:
    for i, (n, f, o, w, r) in enumerate(ns["MUTANTS"]):
        fh.write("%d\t%s\t%s\n" % (i, n, f))
PY

run_one() { # <idx> <name> <file>
    idx=$1; name=$2; rel=$3
    d="$TMP/m$idx"
    mkdir -p "$d"
    cp -R "$FC/review" "$d/review"
    python3 - "$TMP/mutants.py" "$idx" "$d/review/$rel" <<'PY'
import sys
ns = {}
exec(open(sys.argv[1]).read(), ns)
_, _, old, new, retired = ns["MUTANTS"][int(sys.argv[2])]
p = sys.argv[3]
s = open(p).read()
if retired and s.count(old) == 0:
    sys.exit(4)
if s.count(old) != 1:
    print("needle found %d times" % s.count(old), file=sys.stderr)
    sys.exit(3)
open(p, "w").write(s.replace(old, new))
PY
    rc=$?
    if [ "$rc" -eq 3 ]; then echo "INVALID $name (search string not found exactly once)"; return; fi
    if [ "$rc" -eq 4 ]; then echo "RETIRED  $name (needle absent: the targeted code was removed by r5)"; return; fi
    FC_OVERRIDE="$d" sh "$SUITE" >"$d/suite.log" 2>&1
    src=$?
    case $src in
        0) echo "SURVIVED $name" ;;
        1) echo "KILLED   $name ($(grep -c '^NOT ok' "$d/suite.log") case(s) failed)" ;;
        *) echo "INVALID-RUN $name (suite exit $src)"; tail -n 3 "$d/suite.log" ;;
    esac
}

N=$(wc -l <"$TMP/list.tsv")
running=0
: >"$TMP/results.txt"
while IFS='	' read -r idx name rel; do
    ( run_one "$idx" "$name" "$rel" >>"$TMP/results.txt" ) &
    running=$((running+1))
    if [ "$running" -ge "$JOBS" ]; then wait; running=0; fi
done <"$TMP/list.tsv"
wait

sort "$TMP/results.txt"
KILLED=$(grep -c '^KILLED' "$TMP/results.txt")
SURV=$(grep -c '^SURVIVED' "$TMP/results.txt")
INV=$(grep -c '^INVALID' "$TMP/results.txt")
RETN=$(grep -c '^RETIRED' "$TMP/results.txt")
echo "== mutants: $N total, $KILLED killed, $SURV survived, $INV invalid, $RETN retired (needle proven absent) =="
[ "$SURV" -eq 0 ] && [ "$INV" -eq 0 ] && [ $((KILLED + RETN)) -eq "$N" ] || exit 1
exit 0
