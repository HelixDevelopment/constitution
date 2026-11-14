#!/usr/bin/env bash
# tests/workable_items/test_intake_lint_mutations.sh -- paired mutation test (section 1.1) for
# scripts/workable-items/intake_lint.py and its suite tests/workable_items/test_intake_lint.sh.
#
# Documentation (section 11.4.18): docs/guides/intake_lint_guide.md.
#
# WHAT  Each mutant is one exact text replacement in a COPY of the lint, or of the suite (target S);
#   the replaced text must occur exactly once, otherwise the mutant is stale and the test fails.
#   For each mutant: (a) the suite runs with --no-selfcheck (and stops at its first failing case),
#   so the suite's own cases must kill it; (b) for a lint mutant declared "yes", the shipped lint's
#   built-in control needles must also stop it (one direct call, which must print
#   "BLIND: control needle failed"). An unmutated copy must pass the full suite (the control).
#   The O-mutants are the round-1/round-2 set, adapted to the round-4 text (O4, O10, O12, O17, O19
#   rewritten where the code they mutated moved); the C-mutants are the round-2 reviewer's surviving
#   code mutants (C2, C3, C4, C6, C8, C9, C11, C14); the N-mutants cover the checks added in round 3
#   (N7, N9, N12, N13, N19, N25 rewritten for the round-4 code); the LC-mutants are the round-3
#   reviewer's code mutants, verbatim where the text still exists (LC1, LC4..LC11) and mapped where the
#   round-4 code unified the check (LC2, LC3: the per-key compare loop, the mutant skips that one key);
#   the M-mutants cover the checks added in round 4 (every surface, rendered documents, BLIND classes,
#   evidence files, competing heads); M27 reverts the clause-scan fix and M28 drops the binding of a
#   golden-bad needle to its own check (both found by the round-4 run itself); LV1..LV6 are the
#   round-4 reviewer's lint mutants (LV6 mapped onto the round-5 load, which keeps a second location row
#   instead of dropping it); the LN-mutants cover the checks added in round 5 (format characters, the
#   ASCII fast path, the earliest character, unquoted assignments and their reference-value guard,
#   Basic auth, non-ASCII ids, second location rows, the -wal sidecar, URI quoting; LN4 and LN5 remapped
#   onto the round-6 key list); the LS-mutants cover the round-6 keyed-credential shape class (key quoting,
#   each separator, colon values, masks, references, header keys, URL user-info, the Token scheme; O17, LV5, LN5,
#   LS1, LS2, LS4, LS6, LS7, LS9, LS11 and LS12 remapped onto the round-7 text); the LR-mutants cover each rule
#   round 7 added to close the secret-shape class (class_inventory.md section L of the round-7 pack); S1 mutates the
#   suite's own cleanup (round-2 review R2-10).
# ENV   INTAKE_LINT_MUT_JOBS  parallel mutants (default 3)
#       INTAKE_LINT_MUT_ONLY  run only the mutants whose id is listed (comma separated)
# EXIT  0 every mutant killed as declared and the control passes; 1 otherwise; 2 setup error, or
#       the cleanup of the temp dir was refused.
# EVIDENCE CLASS  gate-logic only (section 11.4.289).
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 2
root=$(cd "$here/../.." && pwd) || exit 2
src=$root/scripts/workable-items/intake_lint.py
suite=$here/test_intake_lint.sh
[ -f "$src" ] && [ -f "$suite" ] || { echo "setup: lint or suite missing" >&2; exit 2; }
# shellcheck source=../../scripts/lib/safe_rm.sh
. "$root/scripts/lib/safe_rm.sh" || exit 2
tmp=$(mktemp -d) || exit 2
cleanup() {
  local st=$?
  if ! safe_rm_rf "${tmp:?}"; then echo "CLEANUP REFUSED: temp dir left behind: $tmp" >&2; exit 2; fi
  exit "$st"
}
trap cleanup EXIT
jobs=${INTAKE_LINT_MUT_JOBS:-3}
case "$jobs" in ''|*[!0-9]*|0) echo "setup: INTAKE_LINT_MUT_JOBS must be a positive integer" >&2; exit 2 ;; esac

# Escapes in old/new: \n is a newline, \\n is a literal backslash-n (as written in Python source).
# id | target (L lint, S suite) | needle (yes: the control needles must stop it too) | old ||| new
# (old and new are split at the first "|||", so either may contain a single "|")
mutants=(
  'O1 XREF-DANGLING check off|L|yes|            if ref not in fids and ref not in all_items:|||            if False:'
  'O2 XREF-LABEL check off|L|yes|                    if not (lw & tw) or 3 * len(missing) > len(lw):|||                    if False:'
  'O3 declared foreign ids not excluded|L|yes|            if ref not in fids and ref not in all_items:|||            if ref not in all_items:'
  'O4 ephemeral note exempts the whole surface|L|yes|            if "(ephemeral" in line:|||            if "(ephemeral" in text:'
  'O5 UNREPRODUCED accepted for any column value|L|yes|                ok = (rs in UNREPRO_FAMILY) if canon == "UNREPRODUCED" else (rs == canon)|||                ok = True if canon == "UNREPRODUCED" else (rs == canon)'
  'O6 structured state line not checked|L|yes|            if line.startswith("**Reproduction:**"):|||            if False:'
  'O7 PATH-MISSING check off|L|yes|                if not exists(rel):|||                if False:'
  'O8 SAME-DEFECT head not compared|L|yes| and r["obsolete_superseding"] == head):|||):'
  'O9 SHARED-PATH check off|L|yes|            if hit and o["id"] not in dup_named:|||            if False:'
  'O10 empty selection exits 0|L|no|        if not sel:\n            raise Blind("the selection is empty")|||        if not sel:\n            return 0'
  'O11 unknown --skip-check code accepted|L|no|        print("intake_lint: unknown --skip-check code(s): " + ",".join(unknown), file=sys.stderr)\n        return 2|||        print("intake_lint: unknown --skip-check code(s): " + ",".join(unknown), file=sys.stderr)'
  'O12 the title is not a scanned surface|L|yes|    yield "title", r["title"]\n|||'
  'O13 XREF does not scan the title|L|no|        body_text = r["title"] + "\\n" + text_without_foreign_line(desc)|||        body_text = text_without_foreign_line(desc)'
  'O14 PROBABLY accepted as a verdict|L|yes|            elif verdict not in DUP_VERDICTS:|||            elif verdict not in DUP_VERDICTS | {"PROBABLY"}:'
  'O15 embeddings call foreign ids own|L|no|            ns = "foreign" if ref in fids else|||            ns = "own" if ref in fids else'
  'O16 BODY-SYNC check off|L|yes|        for p in body_problems(r):|||        for p in []:'
  $'O17 SECRET prints the matched string (remapped onto secret_hits, round 7)|L|no|for name, _ in secret_hits(text):\\n            hit("SECRET", name, surface)|||for name, _ in secret_hits(text):\\n            hit("SECRET", name, surface, _)'
  'O18 FOREIGN-STALE check off|L|yes|        for f in sorted(fids - named):|||        for f in []:'
  'O19 a crash exits 0|L|no|        print("BLIND: the lint crashed (%s: %s): no verdict" % (type(e).__name__, str(e)[:200]), file=sys.stderr)\n        return 3|||        print("BLIND: the lint crashed (%s: %s): no verdict" % (type(e).__name__, str(e)[:200]), file=sys.stderr)\n        return 0'
  'C2 mktemp mixed suffix lower bound 4 to 5|L|yes|[A-Za-z0-9]{4,12}|||[A-Za-z0-9]{5,12}'
  'C3 github token minimum 30 to 40|L|yes|gh[pousr]_[A-Za-z0-9]{30,}|||gh[pousr]_[A-Za-z0-9]{40,}'
  'C4 private-key-block pattern broken|L|yes|PRIVATE KEY( BLOCK)?-----|||PRIVATE KEYS( BLOCK)?-----'
  'C6 prefix auto-detection takes the alphabetically first|L|no|        prefix = a.prefix or max(sorted(counts), key=lambda k: counts[k])|||        prefix = a.prefix or sorted(counts)[0]'
  'C8 PATH-MISSING ignores operator_decisions/|L|yes|docs/(?:qa|operator_decisions)/|||docs/(?:qa)/'
  'C9 UNDECIDED dropped from the verdict set|L|yes|DUP_VERDICTS = {"DISTINCT", "DISTINCT-but-similar", "SAME-DEFECT", "UNDECIDED"}|||DUP_VERDICTS = {"DISTINCT", "DISTINCT-but-similar", "SAME-DEFECT"}'
  'C11 jwt segment minimum 8 to 80|L|yes|eyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}|||eyJ[A-Za-z0-9_-]{80,}\.eyJ[A-Za-z0-9_-]{80,}'
  'C14 stopword list emptied|L|yes|    "they them will would should could".split()\n)|||    "they them will would should could".split()\n) & set()'
  'N1 XREF-UNLABELLED check off|L|yes|                if not (cw & tw):|||                if False:'
  'N2 XREF-LABEL accepts one shared title word|L|yes|                    if not (lw & tw) or 3 * len(missing) > len(lw):|||                    if not (lw & tw):'
  'N3 range interiors not expanded|L|yes|        if 0 < b - a <= MAX_RANGE:|||        if False:'
  'N4 empty body_md accepted|L|yes|        return ["body_md is empty"]|||        return []'
  'N5 text after the description in body_md ignored|L|yes|    if suf.strip():|||    if False:'
  'N6 body_md heading not compared|L|no|    if m.group(1) != r["id"] or m.group(2) != r["title"]:|||    if False:'
  'N7 body_md Status line not compared|L|yes|    for key in EXACT_KEYS:|||    for key in EXACT_KEYS[1:]:'
  'N8 body_md header keys not checked|L|no|        if key not in BODY_KEYS:|||        if False:'
  'N9 body_md Reproduction line not compared|L|yes|        elif want is not None and have != want:|||        elif want is not None and have != want and key != "Reproduction":'
  'N10 mktemp-default pattern blind|L|yes|tmp\.(?!X{10})[A-Za-z0-9]{10}|||tmp\.(?!X{10})[A-Za-z0-9]{11}'
  'N11 lowercase mktemp directory branch removed|L|yes||[a-z]{4,12}(?=/))")),|||)")),'
  'N12 DUP-HEAD accepts a closed head|L|yes|                if not is_open(t):|||                if False:'
  'N13 DUP-HEAD ignores competing heads|L|yes|                    for y in sorted(others):|||                    for y in []:'
  'N14 any named id counts as the head (round-2 behaviour)|L|yes|r["obsolete_superseding"] == head)|||r["obsolete_superseding"] in dup_named)'
  'N15 UNDECIDED without a candidate accepted|L|yes|            if not cands:|||            if False:'
  'N16 closed UNDECIDED item accepted|L|no|            if r["status"].startswith("Obsolete") or r["location"] != "Issues":\n                findings.append(("DUP-UNDECIDED"|||            if False:\n                findings.append(("DUP-UNDECIDED"'
  'N17 DUP-STATUS check off|L|yes|        if closed_dup and verdict != "SAME-DEFECT":|||        if False:'
  'N18 OBSOLETE-STALE check off|L|yes|            if not ok:\n                findings.append(("OBSOLETE-STALE"|||            if False:\n                findings.append(("OBSOLETE-STALE"'
  'N19 stale note may name a closed item|L|no|                    if o and is_open(o):\n                        ok = True|||                    if o:\n                        ok = True'
  'N20 prefix with no ids not BLIND|L|no|    if not any(id_re(prefix).fullmatch(i) for i in items):|||    if False:'
  'N21 unknown --skip-check accepted with --embeddings|L|no|    if unknown:|||    if unknown and not a.embeddings:'
  'N22 every line exempt from XREF-UNLABELLED|L|yes|    return bool(DUP_LINE.match(line) or STALE_NOTE.match(line))|||    return True'
  'N24 header line separator not reported|L|yes|        if LINE_SEPARATORS.search(line):|||        if False:'
  'N25 a NULL or non-text title or description not BLIND by name|L|no|                if not isinstance(row.get(name), str):|||                if False:'
  'N26 a crash escapes as a traceback|L|no|    except Exception as e:  # noqa: BLE001|||    except ZeroDivisionError as e:  # noqa: BLE001'
  'LC1 obsolete_details query broken (reviewer round 3, verbatim)|L|no|from obsolete_details"|||from obsolete_detailz"'
  'LC2 Investigation line not compared (reviewer round 3, mapped to the unified compare)|L|no|        elif want is not None and have != want:|||        elif want is not None and have != want and key != "Investigation":'
  'LC3 Obsolete-Details on an open item not reported (reviewer round 3, mapped)|L|yes|        if want is None and have is not None:|||        if want is None and have is not None and key != "Obsolete-Details":'
  'LC4 structured Investigation line not checked (reviewer round 3, verbatim)|L|yes|elif line.startswith("**Investigation:**"):|||elif False:'
  'LC5 slack-token minimum 10 to 50 (reviewer round 3, verbatim)|L|yes|xox[abposre]-[A-Za-z0-9-]{10,}|||xox[abposre]-[A-Za-z0-9-]{50,}'
  'LC6 telegram-bot-token AA to AB (reviewer round 3, verbatim)|L|yes|\d{8,10}:AA[A-Za-z0-9_-]{33}|||\d{8,10}:AB[A-Za-z0-9_-]{33}'
  'LC7 tmp-path branch broken (reviewer round 3, verbatim)|L|yes|/(?:var/)?tmp/|||/(?:var/)?tmpx/'
  'LC8 range interiors limited to 11 (reviewer round 3, verbatim)|L|yes|MAX_RANGE = 200|||MAX_RANGE = 11'
  'LC9 PATH-MISSING keeps trailing punctuation (reviewer round 3, verbatim)|L|yes|rel = m.group(1).rstrip(".,;:)")|||rel = m.group(1)'
  'LC10 body_md heading id not compared (reviewer round 3, verbatim)|L|yes|if m.group(1) != r["id"] or m.group(2) != r["title"]:|||if m.group(2) != r["title"]:'
  'LC11 exemption on any line saying ephemeral (reviewer round 3, verbatim)|L|yes|if "(ephemeral" in line:|||if "ephemeral" in line:'
  'M1 CONTROL-CHAR check off|L|yes|        ch = control_char(text)\n        if ch:|||        ch = control_char(text)\n        if False:'
  'M2 home-path misses /home/<user>/|L|yes|/(?:home|Users)/|||/(?:Users)/'
  'M3 home-path misses ~/.<dir>/|L|yes||~/\.[\w-]+/)|||)'
  'M4 session-store misses projects/|L|yes|(?:projects|todos|shell-snapshots)|||(?:todos|shell-snapshots)'
  'M5 rendered documents not scanned|L|yes|    for fname, line in rendered.get(r["id"], []):|||    for fname, line in []:'
  'M6 description start not checked|L|no|    if not m or not b.startswith(d, m.end()):|||    if not m:'
  'M7 head naming another item not a competing head|L|yes|        elif links_as_duplicate(head["description"], y, prefix):|||        elif False:'
  'M8 open item with a stale duplicate-of row not a competing head|L|yes|        elif (o["obsolete_reason"] == "duplicate-of" and o["obsolete_superseding"] == hid|||        elif (False'
  'M9 a BLOB not BLIND|L|no|            if isinstance(v, (bytes, bytearray, memoryview)):|||            if False:'
  'M10 evidence sha256 not compared with the file|L|yes|        elif shas and fs.sha256(path) not in shas:|||        elif False:'
  'M11 blocked state without a blocker accepted|L|yes|    if rs == "blocked-no-device-with-recorded-blocker" and not col(r, "reproduction_blocker").strip():|||    if False:'
  'M12 a header key written twice not reported|L|no|        if key in hdr:\n            out.append("body_md header key %s is written twice" % key)|||        if False:\n            out.append("body_md header key %s is written twice" % key)'
  'M13 Evidence line not checked against closure evidence|L|yes|    if "Evidence" in hdr and hdr["Evidence"][len("**Evidence:** "):] not in closure_evidence(r):|||    if False:'
  'M14 Reopened-Details line not compared|L|no|        elif hdr["Reopened-Details"] != reopen_line(rr[-1]):|||        elif False:'
  'M15 item absent from the rendered documents not BLIND|L|no|            if unseen:|||            if False:'
  'M16 missing required table not BLIND by name|L|no|        if missing:\n            raise Blind("required table(s) missing: "|||        if False:\n            raise Blind("required table(s) missing: "'
  'M17 items columns not scanned|L|yes|    for name in r["_cols"]:|||    for name in []:'
  'M18 missing evidence file not reported|L|no|        if not fs.exists(path):\n            out.append("%s evidence %s does not exist" % (block, path))|||        if False:\n            out.append("%s evidence %s does not exist" % (block, path))'
  'M19 investigation sha256 read from the evidence column only|L|no|col(r, "investigation_root_cause") + " " + col(r, "investigation_evidence")|||col(r, "investigation_evidence")'
  'M20 undecodable rendered document not BLIND by name|L|no|        except (OSError, UnicodeDecodeError) as e:|||        except OSError as e:'
  'M21 no rendered document not BLIND|L|no|    if not read:\n        raise Blind|||    if False:\n        raise Blind'
  'M22 tab or newline in the title accepted|L|yes|        if surface == "title" and ("\\n" in text or "\t" in text):|||        if False:'
  'M23 C1 controls not reported|L|no|\x7f-\x9f|||\x7f'
  'M24 operator_block_details not scanned|L|yes|    for table, row in (("obsolete_details", r["od"]), ("operator_block_details", r["obd"])):|||    for table, row in (("obsolete_details", r["od"]),):'
  'M25 item_history not scanned|L|yes|    for h in r["hist"]:\n        for name, v in sorted(h.items()):|||    for h in []:\n        for name, v in sorted(h.items()):'
  'M26 every exact header key may differ|L|yes|        elif want is not None and have != want:|||        elif False:'
  'M27 clause scan bounded at the id (the dot before a range end reads as a sentence end)|L|yes|    for m in CLAUSE_SPLIT.finditer(text):\n        if m.end() > start:\n            break\n        s = m.end()|||    for m in CLAUSE_SPLIT.finditer(text, 0, start):\n        s = m.end()'
  'M28 a golden-bad needle accepts any finding of its code (the check-text binding dropped)|L|no|        if not any(f[0] == code.split("/")[0] and want in f[2] for f in run(row, items)):|||        if not any(f[0] == code.split("/")[0] for f in run(row, items)):'
  'LV1 CONTROL-CHAR: U+2028/U+2029 dropped from the class (round-4 reviewer)|L|yes|\u2028\u2029]")|||]")'
  'LV2 rendered docs not scanned by default with --repo-root (round-4 reviewer)|L|no|        rendered_dir = a.rendered or (os.path.join(a.repo_root, "docs") if a.repo_root else None)|||        rendered_dir = a.rendered'
  'LV3 item_history.reason not a scanned surface (round-4 reviewer)|L|yes|            if name not in ("atm_id", "id") and v is not None:|||            if name not in ("atm_id", "id", "reason") and v is not None:'
  'LV4 rendered: a non-item ## heading does not end the item section (round-4 reviewer)|L|no|                    cur = hm.group(1) if hm else None|||                    cur = hm.group(1) if hm else cur'
  $'LV5 SECRET: pattern anchored at the surface start (round-4 reviewer; remapped onto secret_hits)|L|yes|        m = pat.search(t)|||        m = pat.match(t)'
  'LV6 load: a second location row dropped (round-4 reviewer, mapped)|L|no|        if i in items:  # a second location row is linted too|||        if False:  # a second location row is linted too'
  'LN1 CONTROL-CHAR: format characters (Cf) not reported|L|yes|        if CONTROL_CHAR.match(ch) or unicodedata.category(ch) == "Cf":|||        if CONTROL_CHAR.match(ch):'
  'LN2 CONTROL-CHAR: every text read through the ASCII class|L|yes|    if text.isascii():\n        cm = CONTROL_CHAR.search(text)|||    if True:\n        cm = CONTROL_CHAR.search(text)'
  'LN3 CONTROL-CHAR: the last character reported, not the earliest|L|no|    for ch in text:\n        if CONTROL_CHAR.match(ch) or|||    for ch in reversed(text):\n        if CONTROL_CHAR.match(ch) or'
  $'LN4 SECRET: the password key family not read (remapped onto the round-6 key list)|L|yes|r"(?:pass(?:word|wd|phrase)|client|||r"(?:client'
  $'LN5 SECRET: a reference value ($VAR, <placeholder>) reported as a secret (remapped onto the round-7 unquoted assignment)|L|no|(?::=|=>|=)\\s*(?![$<{%\'\\"`(\\[\\\\>])|||(?::=|=>|=)\\s*(?![>])'
  $'LS1 SECRET: a quoted key (JSON) not read (remapped onto _KQ)|L|no|_KQ = r"(?:\\\\?[\\"\'`])?"|||_KQ = r""'
  $'LS2 SECRET: the quoted value after a colon not read (remapped)|L|no|(?::=|=>|:|=)\\s*\\\\?([\\"\'`])(?![$<{%])(?![xX*.#-]+\\\\?\\1)|||(?::=|=>|=)\\s*\\\\?([\\"\'`])(?![$<{%])(?![xX*.#-]+\\\\?\\1)'
  $'LS3 SECRET: an unquoted colon value after a strong key not read|L|yes|[^\\s\'\\"`,;]{8,}")),\\n    ("secret-colon|||[^\\s\'\\"`,;]{80,}")),\\n    ("secret-colon'
  $'LS4 SECRET: a generic-key colon value read without a digit (too broad; remapped onto _LD)|L|yes|_LD = r"(?=[^\\s\'\\"`,;<]*[0-9])(?=[^\\s\'\\"`,;<]*[A-Za-z])"|||_LD = r"(?=[^\\s\'\\"`,;<]*[A-Za-z])"'
  $'LS5 SECRET: a masked colon value reported|L|no|(?![xX*.#-]+(?:[\\s,;]|$))|||'
  $'LS6 SECRET: a short URL user-info password not read (remapped)|L|yes|(?![$<{%*]|[xX]+@|\\d+(?:[/\\s]|$))[^\\s@]+@|||(?![$<{%*]|[xX]+@|\\d+(?:[/\\s]|$))[^\\s@]{6,}@'
  $'LS7 SECRET: a URL user-info reference reported (remapped)|L|yes|(?![$<{%*]|[xX]+@|\\d+(?:[/\\s]|$))|||(?!\\d+(?:[/\\s]|$))'
  $'LS8 SECRET: Authorization: Token not read|L|no|(?:bearer|token)\\s+|||(?:bearer)\\s+'
  $'LS9 SECRET: the => separator of a quoted value not read (remapped)|L|no|(?::=|=>|:|=)\\s*\\\\?([\\"\'`])(?![$<{%])(?![xX*.#-]+\\\\?\\1)|||(?::=|:|=)\\s*\\\\?([\\"\'`])(?![$<{%])(?![xX*.#-]+\\\\?\\1)'
  $'LS10 SECRET: the := separator of an unquoted value not read|L|no|(?::=|=>|=)\\s*(?![$<{%\'|||(?:=>|=)\\s*(?![$<{%\''
  $'LS11 SECRET: a header key after a hyphen (X-Api-Key) not read (remapped onto _KEY_LEAD)|L|no|_KEY_LEAD = r"(?:\\b|_|(?<=[A-Za-z0-9.-]))"|||_KEY_LEAD = r"(?:^|(?<=\\s)|_)"'
  $'LS12 SECRET: a masked quoted value reported (remapped)|L|no|(?![xX*.#-]+\\\\?\\1)|||'
  'LN6 SECRET: Authorization: Basic not reported|L|yes|(?i)authorization:\s*basic\s+[A-Za-z0-9+/=]{8,}|||(?i)authorization:\s*basic\s+[A-Za-z0-9+/=]{80,}'
  'LN7 XREF-DANGLING: an id in non-ASCII digits not reported|L|yes|state_text(r)) if not u.group(1).isascii()}):|||state_text(r)) if False}):'
  'LN8 a second location row not linted|L|no|                for e in extras.get(r["id"], ()):|||                for e in ():'
  'LN9 a second-row finding not named by its row|L|no|"%s [%s row]" % (f[2], e["location"])|||f[2]'
  'LN10 a finding both rows carry reported twice|L|no|                        if f not in raw:|||                        if True:'
  'LN11 a non-empty -wal sidecar read|L|no|    if os.path.isfile(wal) and os.path.getsize(wal) > 0:\n        raise Blind(|||    if False:\n        raise Blind('
  'LN12 the database path read as URI syntax|L|no|urllib.parse.quote(os.path.abspath(db))|||os.path.abspath(db)'
  'S1 suite cleanup refusal not an error|S|no|    echo "CLEANUP REFUSED: temp dir left behind: $tmp" >&2\n    exit 2|||    echo "CLEANUP REFUSED: temp dir left behind: $tmp" >&2'
  $'LR1 SECRET: a key joined to a prefix by nothing (PGPASSWORD) not read|L|no|_KEY_LEAD = r"(?:\\b|_|(?<=[A-Za-z0-9.-]))"|||_KEY_LEAD = r"(?:\\b|_)"'
  $'LR2 SECRET: the NFKC form not read (full-width separators and letters)|L|no|SECRET_NFKC = True|||SECRET_NFKC = False'
  $'LR3 SECRET: the second half of a fat arrow read as a value|L|no|(?![$<{%\'\\"`(\\[\\\\>])|||(?![$<{%\'\\"`(\\[\\\\])'
  $'LR4 SECRET: a backtick-quoted value not read|L|no|\\\\?([\\"\'`])(?![$<{%])(?![xX|||\\\\?([\\"\'])(?![$<{%])(?![xX'
  $'LR5 SECRET: an escaped closing quote (JSON in a string) not read|L|no|[^\\"\'`\\s\\\\]{8,}\\\\?\\1")),|||[^\\"\'`\\s\\\\]{8,}\\1")),'
  $'LR6 SECRET: a short key read inside a word (bypass, oauth)|L|no|_SHORT_LEAD = r"(?<![A-Za-z0-9])"|||_SHORT_LEAD = r""'
  $'LR7 SECRET: a short key with a quoted colon value (Docker auth) not read|L|no||:(?!=)\\s*\\\\?[\\"\'`])(?![$<{%/~.>])|||)(?![$<{%/~.>])'
  $'LR8 SECRET: a path after a short key read as a value|L|no|(?![$<{%/~.>])|||(?![$<{%])'
  $'LR9 SECRET: an upper-case flag placeholder (--password PASSWORD) read as a value|L|no|(?!(?-i:[A-Z][A-Z0-9_]*)(?:[\\s\'\\"`]|$))|||'
  $'LR10 SECRET: a netrc password keyword not read|L|no|\\blogin\\s+\\S+\\s+pass(?:word|wd)\\s+|||\\blogin\\s+\\S+\\s+passwd\\s+'
  $'LR11 SECRET: an XML element named by a strong key not read|L|no|r"(?i)<([\\w.-]*?" + _SECRET_KEYS + r")|||r"(?i)<(nomatchxml" + _SECRET_KEYS + r")'
  $'LR12 SECRET: an XML element named by a generic key not read|L|no|r"|<((?:[\\w.-]*?" + _SECRET_KEYS_GENERIC|||r"|<((?:(?!)" + _SECRET_KEYS_GENERIC'
  $'LR13 SECRET: a quoted value with a space (a passphrase) not read|L|no|\\\\?([\\"\'`])(?![$<{%])(?=[|||\\\\?([\\"\'`])(?!)(?=['
  $'LR14 SECRET: a strong key, whitespace and a value (fish set) not read|L|no|_SECRET_KEYS + r"[ \\t]+(?!|||_SECRET_KEYS + r"[ \\t]+(?!.)(?!'
  $'LR15 SECRET: a URL with an empty user name (redis://:pw@h) not read|L|no|://[^/\\s:@]*:|||://[^/\\s:@]+:'
  $'LR16 SECRET: a URL password with a slash in it not read|L|no|[^\\s@]+@")),|||[^/\\s@]+@")),'
  $'LR17 SECRET: a URL port and path read as a password|L|no||\\d+(?:[/\\s]|$))|||)'
  $'LR18 SECRET: the round-7 key names (credentials, *_token) not read|L|no|r"|credentials?|(?:auth|access|refresh|bearer|session|api|id|oauth|app)[_.-]?token)")|||r")")'
  $'LR19 SECRET: a dot-joined strong key (api.key) not read|L|no|api[_.-]?key|||api[_-]?key'
)

mkcopy() { # mkcopy <src> <dest> <old> <new>  (\n in old/new is a newline)
  python3 -I - "$1" "$2" "$3" "$4" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
def unesc(t):  # "\\\\n" (two backslashes) is a literal backslash-n; "\\n" is a newline
    return t.replace("\\\\n", "\0").replace("\\n", "\n").replace("\0", "\\n")
old, new = unesc(old), unesc(new)
s = open(src).read()
n = s.count(old)
if old and n != 1:
    sys.stderr.write("stale mutant: %d matches for %r\n" % (n, old[:80])); sys.exit(1)
open(dst, "w").write(s.replace(old, new) if old else s)
PY
}

# one_mutant <index>: prints one verdict line; never touches files outside its own dir $tmp/m<index>
one_mutant() {
  local i=$1 m id rest target needle old new d a nb verdict
  m=${mutants[$i]}
  id=${m%%|*}; rest=${m#*|}; target=${rest%%|*}; rest=${rest#*|}; needle=${rest%%|*}; rest=${rest#*|}
  old=${rest%%|||*}; new=${rest#*|||}
  d=$tmp/m$i; mkdir -p "$d" || { echo "FAIL $id: no work dir"; return; }
  if [ "$target" = S ]; then
    if ! mkcopy "$suite" "$d/test_intake_lint.sh" "$old" "$new" 2>"$d/err"; then echo "FAIL $id: stale mutant"; return; fi
    INTAKE_LINT_ROOT=$root INTAKE_LINT=$src INTAKE_LINT_EXTRA=--no-selfcheck INTAKE_LINT_FAILFAST=1 \
      bash "$d/test_intake_lint.sh" >"$d/log" 2>&1
    a=$?
    nb=n/a
  else
    if ! mkcopy "$src" "$d/m.py" "$old" "$new" 2>"$d/err"; then echo "FAIL $id: stale mutant"; return; fi
    INTAKE_LINT=$d/m.py INTAKE_LINT_EXTRA=--no-selfcheck INTAKE_LINT_FAILFAST=1 bash "$suite" >"$d/log" 2>&1
    a=$?
    python3 -I "$d/m.py" --db "$d/none.db" --ids X-1 >"$d/needle" 2>&1
    nb=no; grep -q 'BLIND: control needle failed' "$d/needle" && nb=yes
  fi
  verdict=PASS
  [ "$a" = 0 ] && verdict=FAIL
  [ "$needle" = yes ] && [ "$nb" != yes ] && verdict=FAIL
  echo "$verdict $id: cases-kill=$([ "$a" != 0 ] && echo yes || echo no) first-failure=$(grep -m1 '^FAIL' "$d/log" | cut -c6-70) needle-kill=$nb (declared $needle)"
}

fail=0
mkcopy "$src" "$tmp/ctl.py" "" "" || exit 2
INTAKE_LINT=$tmp/ctl.py INTAKE_LINT_EXTRA=--no-selfcheck bash "$suite" >"$tmp/ctl.log" 2>&1; a=$?
python3 -I "$tmp/ctl.py" --db "$tmp/none.db" --ids X-1 >"$tmp/ctl.needle" 2>&1
if [ "$a" = 0 ] && grep -q 'BLIND: database not found' "$tmp/ctl.needle"; then echo "PASS control: unmutated copy passes the suite and its control needles"
else echo "FAIL control: suite rc=$a; $(tr '\n' '|' <"$tmp/ctl.needle")"; fail=1; fi

sel=()
for i in "${!mutants[@]}"; do
  id=${mutants[$i]%% *}
  if [ -n "${INTAKE_LINT_MUT_ONLY:-}" ]; then case ",$INTAKE_LINT_MUT_ONLY," in *",$id,"*) ;; *) continue ;; esac; fi
  sel+=("$i")
done
export -f one_mutant mkcopy
export tmp root src suite
# bash cannot export arrays: hand each worker the mutant list through a file
printf '%s\n' "${mutants[@]}" >"$tmp/mutants.txt"
printf '%s\n' "${sel[@]}" | xargs -P "$jobs" -I{} bash -c 'mapfile -t mutants <"$tmp/mutants.txt"; one_mutant "$1" >"$tmp/v$1"' _ {}
for i in "${sel[@]}"; do
  if [ -f "$tmp/v$i" ]; then cat "$tmp/v$i"; grep -q '^PASS' "$tmp/v$i" || fail=1
  else echo "FAIL ${mutants[$i]%%|*}: no verdict"; fail=1; fi
done
echo "RESULT: mutants=${#sel[@]} $([ "$fail" = 0 ] && echo 'all killed as declared' || echo 'FAILED')"
[ "$fail" = 0 ]
