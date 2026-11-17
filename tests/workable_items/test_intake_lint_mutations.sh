#!/usr/bin/env bash
# tests/workable_items/test_intake_lint_mutations.sh -- paired mutation test (section 1.1) for
# scripts/workable-items/intake_lint.py and its suite tests/workable_items/test_intake_lint.sh.
#
# Documentation (section 11.4.18): docs/guides/intake_lint_guide.md.
#
# WHAT  Each mutant is one exact text replacement in a COPY of the lint, of the suite (target S), or of the
#   shared credential primitive secret_canon.py (target C, round 11; the copy is placed next to an
#   unmutated lint copy, and every lint copy gets an unmutated canon next to it);
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
#   round 7 added to close the secret-shape class (class_inventory.md section L of the round-7 pack); round 8
#   replaced the round-7 regex set by a front end (format characters, NFKC, lookalike fold, escape and percent
#   decoding), keyed extractors and one value classifier, so LN5, LS2..LS7, LS9, LS10, LS12, LR3..LR5, LR7..LR9
#   and LR11..LR17 are remapped onto that code with the same intent (LR1, LR2, LR6, LR10, LR18, LR19 still apply);
#   RL1..RL10 are the round-8 reviewer's lint mutants (probes/mk_mutants_r8.py of that review): only RL2 occurs
#   verbatim, the others mutated round-7 regexes that no longer exist and are ported onto the same rule of the
#   round-8 code; the R8-mutants cover each part of the round-8 engine (the front-end switches, the backslash
#   value of review N1, each extractor of review N2, the value classifier's guards); S1 mutates the suite's own
#   cleanup (round-2 review R2-10).
# ENV   INTAKE_LINT_MUT_JOBS  parallel mutants (default 3)
#       INTAKE_LINT_MUT_ONLY  run only the mutants whose id is listed (comma separated)
# EXIT  0 every mutant killed as declared and the control passes; 1 otherwise; 2 setup error, or
#       the cleanup of the temp dir was refused.
# EVIDENCE CLASS  gate-logic only (section 11.4.289).
set -u
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 2
root=$(cd "$here/../.." && pwd) || exit 2
src=$root/scripts/workable-items/intake_lint.py
canon=$root/scripts/workable-items/secret_canon.py
suite=$here/test_intake_lint.sh
[ -f "$src" ] && [ -f "$canon" ] && [ -f "$suite" ] || { echo "setup: lint or suite missing" >&2; exit 2; }
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
# id | target (L lint, S suite, C shared primitive) | needle (yes: the control needles must stop it too) | old ||| new
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
  'LN1 CONTROL-CHAR: format characters (Cf) not reported (remapped round 9)|L|yes|        if CONTROL_CHAR.match(ch) or unicodedata.category(ch) == "Cf" or INVISIBLE_CHAR.match(ch):|||        if CONTROL_CHAR.match(ch) or INVISIBLE_CHAR.match(ch):'
  'LN2 CONTROL-CHAR: every text read through the ASCII class|L|yes|    if text.isascii():\n        cm = CONTROL_CHAR.search(text)|||    if True:\n        cm = CONTROL_CHAR.search(text)'
  'LN3 CONTROL-CHAR: the last character reported, not the earliest|L|no|    for ch in text:\n        if CONTROL_CHAR.match(ch) or|||    for ch in reversed(text):\n        if CONTROL_CHAR.match(ch) or'
  $'LN4 SECRET: the password key family not read (remapped onto the round-9 STRONG_HEADS)|L|yes|STRONG_HEADS = frozenset({"password", "passwd", "passphrase", "passwort"|||STRONG_HEADS = frozenset({"passwort"'
  'LN5 SECRET: a reference value ($VAR, <placeholder>) reported as a secret (remapped onto the round-8 value classifier)|L|no|    if v[0] in _REF_START:\n|||    if False:\n'
  $'LS1 SECRET: a quoted key (JSON) not read (remapped onto _KQ)|L|no|_KQ = r"(?:\\\\?[\\"\'`])?"|||_KQ = r""'
  'LS2 SECRET: the quoted value after a colon not read (remapped round 10)|L|no|_SEP_Q = r"\s*(?::=|=>|<<-|<-|:|=)\s*"|||_SEP_Q = r"\s*(?::=|=>|<<-|<-|=)\s*"'
  'LS3 SECRET: an unquoted colon value after a strong key not read (remapped)|L|no|        if tier == "strong" and credential_value("strong", v, ""):\n            yield "password-colon-unquoted"|||        if False:\n            yield "password-colon-unquoted"'
  'LS4 SECRET: a generic-key colon value read without a digit (too broad; remapped)|L|no|        elif tier == "generic" and credential_value("generic", v, ""):|||        elif tier == "generic" and credential_value("generic", v, "", generic_ld=False):'
  'LS5 SECRET: a masked unquoted value reported (remapped onto _MASK)|L|no|    if _MASK.match(v):\n|||    if _MASK.match(v) and quote:\n'
  'LS6 SECRET: a short URL user-info password not read (remapped)|L|no|:(?P<v>[^\s@]+)@")|||:(?P<v>[^\s@]{6,})@")'
  'LS7 SECRET: a URL user-info reference reported (remapped)|L|no|        if v[0] in "$<{%*" or re.fullmatch|||        if v[0] in "*" or re.fullmatch'
  $'LS8 SECRET: Authorization: Token not read|L|no|(?:bearer|token)\\s+|||(?:bearer)\\s+'
  'LS9 SECRET: the => separator of a quoted value not read (remapped round 10)|L|no|_SEP_Q = r"\s*(?::=|=>|<<-|<-|:|=)\s*"|||_SEP_Q = r"\s*(?::=|<<-|<-|:|=)\s*"'
  'LS10 SECRET: the := separator of an unquoted value not read (remapped round 9)|L|no|_KQ + r"\s*(?::=|=>|=)\s*(?=(?P<v>|||_KQ + r"\s*(?:=>|=)\s*(?=(?P<v>'
  $'LS11 SECRET: a header key after a hyphen (X-Api-Key) not read (remapped onto the round-9 key split)|L|no|_WSPLIT = re.compile(r"[\\W_]+")|||_WSPLIT = re.compile(r"[^\\w-]+|_+")'
  'LS12 SECRET: a masked quoted value reported (remapped onto _MASK)|L|no|    if _MASK.match(v):\n|||    if _MASK.match(v) and not quote:\n'
  'LN6 SECRET: Authorization: Basic not reported|L|yes|(?i)authorization:\s*basic\s+[A-Za-z0-9+/=]{8,}|||(?i)authorization:\s*basic\s+[A-Za-z0-9+/=]{80,}'
  'LN7 XREF-DANGLING: an id in non-ASCII digits not reported|L|yes|state_text(r)) if not u.group(1).isascii()}):|||state_text(r)) if False}):'
  'LN8 a second location row not linted|L|no|                for e in extras.get(r["id"], ()):|||                for e in ():'
  'LN9 a second-row finding not named by its row|L|no|"%s [%s row]" % (f[2], e["location"])|||f[2]'
  'LN10 a finding both rows carry reported twice|L|no|                        if f not in raw:|||                        if True:'
  'LN11 a non-empty -wal sidecar read|L|no|    if os.path.isfile(wal) and os.path.getsize(wal) > 0:\n        raise Blind(|||    if False:\n        raise Blind('
  'LN12 the database path read as URI syntax|L|no|urllib.parse.quote(os.path.abspath(db))|||os.path.abspath(db)'
  'RV1 Cf strip narrowed to ZWSP (reviewer round 9, ported to the round-9 code)|L|no|            drop.add("Cf")|||            t = t.replace("\u200b", "")'
  'RV3 \x escapes not decoded (reviewer round 9, remapped round 10: both \x forms)|L|no|x\{[0-9A-Fa-f]{1,6}\}|x[0-9A-Fa-f]{2}|[0-7]{3}||||[0-7]{3}'
  'RV4 min value length 8->9 (reviewer round 9, verbatim)|L|no|    if len(v) < 8:\n        return False\n    if _MASK.match(v):|||    if len(v) < 9:\n        return False\n    if _MASK.match(v):'
  'RV5 mask regex unanchored at end (reviewer round 9, verbatim)|L|no|r"^[xX*.#\s-]+$"|||r"^[xX*.#\s-]+"'
  'RV6 percent not a reference start (reviewer round 9, verbatim)|L|no|_REF_START = "$<{%"|||_REF_START = "$<{"'
  'RV7 placeholder suffix -here dropped (reviewer round 9, verbatim)|L|no|[-_.](?:here|goes[-_]here|placeholder)$|||[-_.](?:goes[-_]here|placeholder)$'
  'RV8 URL digit-start password treated as port (reviewer round 9, verbatim)|L|no|if re.match(r"\d+/", v):|||if re.match(r"\d+", v):'
  'RV9 pgpass wildcard port dropped (reviewer round 9, verbatim)|L|no|[^\s:#]+:(?:\d{1,5}|\*):|||[^\s:#]+:(?:\d{1,5}):'
  'RV10 Greek omicron unfolded (reviewer round 9, verbatim)|L|no|"\u03b1": "a", "\u03bf": "o",|||"\u03b1": "a",'
  'RV11 upper-case identifier key needs >8 chars (reviewer round 9, verbatim)|L|no|(key.isupper() and len(key) > 3)|||(key.isupper() and len(key) > 8)'
  'RV12 tab allowed inside a value (reviewer round 9, ported to the round-9 code)|L|no|    if "\t" in v:\n        return False  # a tab inside|||    if False:\n        return False  # a tab inside'
  'RV13 percent view only when at start (reviewer round 9, ported to the round-9 code)|L|no|_PCT.search(t) else None|||_PCT.match(t) else None'
  'RV14 stripe restricted-key prefix dropped (reviewer round 9, verbatim)|L|no|\b[rs]k_(?:live|test)_|||\bsk_(?:live|test)_'
  'RV15 telegram id min 8->9 digits (reviewer round 9, verbatim)|L|no|\b\d{8,10}:AA|||\b\d{9,10}:AA'
  'RV16 xml close-tag check removed (reviewer round 9, ported to the round-9 code)|L|no|        if tier is None or m.group("ctag") != m.group("key"):\n            continue|||        if tier is None or not m.group("ctag"):\n            continue'
  'RV17 flag usage placeholder accepts lower case (reviewer round 9, verbatim)|L|no|if re.fullmatch(r"[A-Z][A-Z0-9_]*", v):|||if re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", v):'
  'RV18 code-attr exclusion ignores digits (reviewer round 9, verbatim)|L|no|(_CODE_ATTR.match(v) and not any(c.isdigit() for c in v))|||_CODE_ATTR.match(v)'
  'RV19 short-key ">" guard dropped (reviewer round 9, verbatim)|L|no|    if tier == "short" and v[0] in ".>":\n        return False\n|||'
  'RV20 single-quoted $literal allowed for double quotes (reviewer round 9, verbatim)|L|no|if not (quote == "'\''" and v[0] == "$"|||if not (quote in "'\''\"" and v[0] == "$"'
  'OL1 SECRET r9: the loose two-letter qualifier rule off (PGid_token)|L|no|_qualified(prev, w, head, quals, loose=(i > 0 and ws[i - 1][1]) or upper)|||_qualified(prev, w, head, quals, loose=False)'
  'OL2 SECRET r9: a word that ends with a strong head is not a key (PGPASSWORD)|L|no|any(_like(w, h) for h in STRONG_HEADS) or any(_ends_like(w, h) for h in SUFFIX_HEADS):|||any(_like(w, h) for h in STRONG_HEADS):'
  'OL3 SECRET r9: META_WORDS after the head ignored (password_policy reported)|L|no|    return all(x.isdigit() or re.fullmatch(r"v[0-9]+", x) or x not in META_WORDS for x in tail)|||    return True'
  'OL4 SECRET r9: KEY_NEGATIVE ignored (public_key reported)|L|no|            return None if prev in KEY_NEGATIVE else "short"|||            return "short"'
  'OL5 SECRET r9: the HTML entity view off|L|no|SECRET_DECODE_ENTITIES = True|||SECRET_DECODE_ENTITIES = False'
  'OL6 SECRET r9: adjacent string literals not joined|L|no|SECRET_JOIN_LITERALS = True|||SECRET_JOIN_LITERALS = False'
  'OL7 SECRET r9: marks (Mn, Me) not stripped from a key|L|no|SECRET_STRIP_MARKS = True|||SECRET_STRIP_MARKS = False'
  'OL8 SECRET r9: the Latin-by-name fold off (small capitals)|L|no|SECRET_FOLD_LATIN_NAMES = True|||SECRET_FOLD_LATIN_NAMES = False'
  'OL9 SECRET r9: the decoding closure one layer deep (double percent)|L|no|SECRET_VIEW_LAYERS = 3|||SECRET_VIEW_LAYERS = 1'
  'OL10 SECRET r9: the string prefix (b, f, r) before a quoted value not read|L|no|_QPRE = r"(?P<sp>(?<![\w])[bBrRuUfF]{1,2})?"|||_QPRE = r"(?P<sp>)"'
  'OL11 SECRET r9: the bracketed key subscript not read (config[password])|L|no|(?:\[\s*\\?[\"'\''`]?[\w.\-]{1,255}\\?[\"'\''`]?\s*\]){0,4}|||(?:\[\s*\\?[\"'\''`]?[\w.\-]{1,255}\\?[\"'\''`]?\s*\]){0,0}'
  'OL12 SECRET r9: a quoted value after whitespace (IDENTIFIED BY) not read|L|no|        if tier == "strong" and _has_ld(v) and credential_value("strong", v, q):\n            yield "password-space-quoted"|||        if False:\n            yield "password-space-quoted"'
  'OL13 SECRET r9: the Authorization header of another scheme not read|L|no|        if credential_value("generic", v, ""):\n            yield "authorization-header"|||        if False:\n            yield "authorization-header"'
  'OL14 SECRET r9: openssl pass: not read|L|no|    r"(?<![\w-])-(?:pass|passin|passout)\s+pass:(?P<v>\S+)",\n|||'
  'OL15 SECRET r9: redis-cli -a not read|L|no|    r"\bredis-cli\b[^\\n|;&]*?\s-a\s+(?P<v>[^\s-]\S*)",\n|||'
  'OL16 SECRET r9: the secret-manager reference guard off (vault:..., remapped round 10)|L|no|    if _REF_URI.match(v) or _REF_ANNOT.match(v) or _REF_ARN.match(v) or _REF_SCHEME.match(v):|||    if _REF_ARN.match(v) or _REF_SCHEME.match(v):'
  'S1 suite cleanup refusal not an error|S|no|    echo "CLEANUP REFUSED: temp dir left behind: $tmp" >&2\n    exit 2|||    echo "CLEANUP REFUSED: temp dir left behind: $tmp" >&2'
  $'LR1 SECRET: a key joined to a prefix by nothing (PGPASSWORD) not read (remapped onto SUFFIX_HEADS)|L|no| or any(_ends_like(w, h) for h in SUFFIX_HEADS)|||'
  $'LR3 SECRET: an unquoted value starting with > read (remapped round 9)|L|no|        if tier is None or v[:1] in "\'\\"`(\\\\[>" or not v:|||        if tier is None or v[:1] in "\'\\"`(\\\\[" or not v:'
  $'LR4 SECRET: a backtick-quoted value not read (remapped onto the round-9 _QVAL)|L|no|_QVAL = _QPRE + r"\\\\?(?P<q>[\\"\'`])|||_QVAL = _QPRE + r"\\\\?(?P<q>[\\"\'])'
  'LR5 SECRET: an escaped closing quote (JSON in a string) not read (remapped onto _QVAL)|L|no|[^\\n\\])*)\\?(?P=q)"\n|||[^\\n\\])*)(?P=q)"\n'
  $'LR6 SECRET: a short key read inside a word (bypass, oauth) (remapped onto the round-9 short heads)|L|no|    if w in SHORT_HEADS:\\n|||    if w in SHORT_HEADS or w.endswith(("pass", "auth")):\\n'
  'LR7 SECRET: a short key with a quoted value (Docker auth) not read (remapped round 9)|L|no|            if credential_value(tier, v, q):\n                yield "short-key-assign"|||            if False:\n                yield "short-key-assign"'
  'LR8 SECRET: a path after a short key read as a value (remapped)|L|no|    if _PATH.match(v):\n|||    if _PATH.match(v) and tier != "short":\n'
  'LR9 SECRET: an upper-case flag placeholder (--password PASSWORD) read as a value (remapped)|L|no|        if re.fullmatch(r"[A-Z][A-Z0-9_]*", v):\n            continue  # a usage-line placeholder|||        if False:\n            continue  # a usage-line placeholder'
  $'LR10 SECRET: a netrc password keyword not read|L|no|\\blogin\\s+\\S+\\s+pass(?:word|wd)\\s+|||\\blogin\\s+\\S+\\s+passwd\\s+'
  'LR11 SECRET: an XML element named by a strong key not read (remapped round 9)|L|no|        if tier is None or m.group("ctag") != m.group("key"):\n            continue|||        if tier is None or m.group("ctag") != m.group("key") or tier == "strong":\n            continue'
  'LR12 SECRET: an XML element named by a generic key not read (remapped round 9)|L|no|        if tier is None or m.group("ctag") != m.group("key"):\n            continue|||        if tier is None or m.group("ctag") != m.group("key") or tier == "generic":\n            continue'
  'LR13 SECRET: a quoted value with a space (a passphrase) not read (remapped)|L|no|            if tier == "strong" and credential_value("strong", v.strip(), q, allow_space=True) and v.strip():|||            if False:'
  'LR14 SECRET: a strong key, whitespace and a value (fish set) not read (remapped)|L|no|        if ident and _has_ld(v) and credential_value("strong", v, ""):|||        if False:'
  'LR15 SECRET: a URL with an empty user name (redis://:pw@h) not read (remapped)|L|no|://[^/\s:@\[\]]*:|||://[^/\s:@\[\]]+:'
  'LR16 SECRET: a URL password with a slash in it not read (remapped)|L|no|        if "/" in v and (v.endswith("/") or not _has_ld(v)):|||        if "/" in v:'
  'LR17 SECRET: a URL port and path read as a password (remapped)|L|no|        if re.match(r"\d+/", v):\n            continue|||        if False:\n            continue'
  $'LR18 SECRET: the round-7 key names (credentials) not read (remapped onto STRONG_HEADS)|L|no|"salasana", "credential", "credentials"})|||"salasana"})'
  $'LR19 SECRET: a dot-joined strong key (api.key) not read (remapped onto the round-9 key split)|L|no|_WSPLIT = re.compile(r"[\\W_]+")|||_WSPLIT = re.compile(r"[^\\w.]+|_+")'
  'RL1 SECRET: the views not read, the raw text searched (reviewer round 8, ported)|L|no|    views = secret_views(text)\n|||    views = [text]\n'
  'RL2 SECRET: short key auth dropped (reviewer round 8, ported to the round-9 head words)|L|no|SHORT_HEADS = frozenset({"pwd", "pass", "pw", "auth", |||SHORT_HEADS = frozenset({"pwd", "pass", "pw", '
  'RL3 SECRET: password-assign-spaced without its space requirement (reviewer round 8, ported)|L|no|        elif re.search(r"[ \t]", v):|||        elif re.search(r"[ \t]", v) or tier == "strong":'
  'RL4 SECRET: the XML closing tag need not match the opening key (reviewer round 8, ported round 9)|L|no|        if tier is None or m.group("ctag") != m.group("key"):\n            continue|||        if tier is None:\n            continue'
  'RL5 SECRET: password-space reads a space, not a tab (reviewer round 8, ported round 9)|L|no|(?P<sep>[ \t]+)|||(?P<sep>[ ]+)'
  'RL6 SECRET: a digit-only value accepted where a letter and a digit are needed (reviewer round 8, ported)|L|no|    return any(c.isdigit() for c in v) and any(c.isalpha() for c in v)\n|||    return any(c.isdigit() for c in v)\n'
  'RL7 SECRET: the URL x-mask exclusion dropped (reviewer round 8, ported)|L|no|        if v[0] in "$<{%*" or re.fullmatch(r"[xX*]+", v):|||        if v[0] in "$<{%*":'
  'RL8 SECRET: the --flag boundary lookbehind dropped (reviewer round 8, ported round 9)|L|no|_RX_FLAG = re.compile(r"(?i)(?<![\w-])--(?P<key>|||_RX_FLAG = re.compile(r"(?i)--(?P<key>'
  'RL9 SECRET: the minimum value length 8 to 9 (reviewer round 8, ported from the netrc minimum)|L|no|    if len(v) < 8:\n|||    if len(v) < 9:\n'
  'RL10 SECRET: secret_hits stops after the first rule found (reviewer round 8, ported)|L|no|        if name in found:\n            yield name, found[name]\n|||        if name in found:\n            yield name, found[name]\n            return\n'
  'R8-1 SECRET front end: format characters not removed|L|no|SECRET_STRIP_FORMAT = True|||SECRET_STRIP_FORMAT = False'
  'R8-2 SECRET front end: lookalike letters not folded|L|no|SECRET_FOLD = True|||SECRET_FOLD = False'
  'R8-3 SECRET front end: escapes not decoded|L|no|SECRET_DECODE_ESCAPES = True|||SECRET_DECODE_ESCAPES = False'
  'R8-4 SECRET front end: percent-encoding not decoded|L|no|SECRET_DECODE_PERCENT = True|||SECRET_DECODE_PERCENT = False'
  'R8-5 SECRET front end: Cyrillic a not folded|L|no|"\u0430": "a", "\u0435"|||"\u0435"'
  'R8-6 SECRET front end: \u escapes not decoded (remapped round 10)|L|no|U[0-9A-Fa-f]{8}|u[0-9A-Fa-f]{4}|x\{|||U[0-9A-Fa-f]{8}|q[0-9A-Fa-f]{4}|x\{'
  'R8-7 SECRET: a quoted value holding a backslash not read (the round-7 regression, N1)|L|no|(?P<v>(?:\\[^\\n]|(?!\\?(?P=q))[^\\n\\])*)\\?(?P=q)"\n|||(?P<v>(?:(?!\\?(?P=q))[^\\n\\])*)\\?(?P=q)"\n'
  'R8-8 SECRET: argument pairs not read (remapped round 9)|L|no|        if tier and credential_value(tier, v, q):\n            yield "argument-pair"|||        if False:\n            yield "argument-pair"'
  'R8-9 SECRET: the argument-pair separator not a comma|L|no|(?P=kq)\s*,\s*(?P<q>|||(?P=kq)\s*;\s*(?P<q>'
  'R8-10 SECRET: setter calls not read (remapped round 9)|L|no|        if tier in ("strong", "generic") and credential_value(tier, v, q):\n            yield "setter-call"|||        if False:\n            yield "setter-call"'
  'R8-11 SECRET: the snake-case setter (set_api_key) not read (remapped round 9)|L|no|r"(?<![A-Za-z0-9])set_?(?P<key>|||r"(?<![A-Za-z0-9])set(?P<key>'
  'R8-12 SECRET: the key/value XML attribute pair not read (remapped round 9)|L|no|        if tier and credential_value(tier, m.group("v"), m.group("q2")):|||        if False:'
  'R8-13 SECRET: an entry element whose closing tag differs read (remapped round 9)|L|no|if tier and m.group("ctag") == m.group("otag") and credential_value(tier, m.group("v"), "<"):|||if tier and credential_value(tier, m.group("v"), "<"):'
  'R8-14 SECRET: the XML attribute name= key not read (remapped round 10)|L|no|\b(?:key|name|type|id)\s*=\s*(?P<q1>|||\b(?:key|type|id)\s*=\s*(?P<q1>'
  'R8-15 SECRET: mysqldump'"'"'s -p flag not read|L|no|(?:mysql|mysqldump|mysqladmin|||(?:mysql|mysqladmin'
  'R8-16 SECRET: sshpass -p not read (remapped round 9)|L|no|    r"\bsshpass\b[^\\n|;&]*?\s-p\s*(?P<v>[^\s-]\S*)",\n|||'
  'R8-17 SECRET: curl --user not read|L|no|(?:-u|--user)\s+|||(?:-u)\s+'
  'R8-18 SECRET: the mysql flag read in any case (-P port read as -p) (remapped round 9)|L|no|    r"\b(?:mysql|mysqldump|||    r"(?i)\b(?:mysql|mysqldump'
  'R8-19 SECRET: the folded YAML block scalar (>) not read|L|no|[ \t]*:[ \t]*[|>][-+0-9]*|||[ \t]*:[ \t]*[|][-+0-9]*'
  'R8-20 SECRET: YAML block scalars not read (remapped round 9)|L|no|        if tier and credential_value(tier, v, "|"):\n            yield "yaml-block-scalar"|||        if False:\n            yield "yaml-block-scalar"'
  'R8-21 SECRET: a pgpass line with * fields not read|L|no|:(?:\d{1,5}|\*):|||:(?:\d{1,5}):'
  'R8-22 SECRET: a pgpass value without a digit read (a time stamp)|L|no|        if _has_ld(v) and credential_value("strong", v, ""):\n            yield "pgpass-line"|||        if credential_value("strong", v, ""):\n            yield "pgpass-line"'
  'R8-23 SECRET: the URL scheme read in lower case only|L|no|_RX_URL = re.compile(r"(?i)(?<!|||_RX_URL = re.compile(r"(?<!'
  'R8-24 SECRET: the placeholder word changeme read as a value|L|no|"changeme", "change_me",|||"change_me",'
  'R8-25 SECRET: your_/my_ placeholders read as a value|L|no|(?:your|my|enter|insert|put|some)[-_.]|||(?:enter|insert|put|some)[-_.]'
  'R8-26 SECRET: a code call read as a value|L|no|if not quote and (_CODE_CALL.match(v) or|||if not quote and (False or'
  'R8-27 SECRET: a dotted name with a digit dropped as code|L|no|(_CODE_ATTR.match(v) and not any(c.isdigit() for c in v))|||(_CODE_ATTR.match(v))'
  'R8-28 SECRET: a path read as a value|L|no|    if _PATH.match(v):\n        return False\n|||'
  'R8-29 SECRET: a single-quoted $ literal treated as a reference|L|no|if not (quote == "'"'"'" and v[0] == "$"|||if not (False and v[0] == "$"'
  'R8-30 SECRET: a multi-part key name with whitespace (client_secret VALUE) not read|L|no| or bool(re.search(r"[_.-]", key))|||'
  'R8-31 SECRET: a short key read without a letter and a digit|L|no|if (tier == "short" or (tier == "generic" and generic_ld)) and not _has_ld(v):|||if (tier == "generic" and generic_ld) and not _has_ld(v):'
  'R8-32 SECRET: a short-key value starting with a dot read|L|no|    if tier == "short" and v[0] in ".>":|||    if False:'
  'R8-33 SECRET: a generic key'"'"'s quoted = value needs a digit|L|no|        elif credential_value(tier, v, q, generic_ld=False):|||        elif credential_value(tier, v, q, generic_ld=True):'
  'R8-34 SECRET: the decoding closure applied to the first view of a layer only (remapped round 9)|L|no|        for v in frontier:\n            for f in _TRANSFORMS:|||        for v in frontier[:1]:\n            for f in _TRANSFORMS:'
  # round 10: the round-9 reviewer's lint mutants XL2 to XL9 ported onto the round-10 text (XL12 is in
  # equivalent=() below; the XL13 port is killed by contract C8 of test_secret_frontend.py), and the fixer's own mutants R10-1..R10-20 of every part round 10 added
  'XL2 CGJ U+034F not an invisible char (reviewer round 9)|L|no|INVISIBLE_CHAR = re.compile("[\u034f|||INVISIBLE_CHAR = re.compile("['
  'XL3 word back in META_WORDS (reviewer round 9, ported: round 10 removed it)|L|no|    "words", "case", "cases",|||    "word", "words", "case", "cases",'
  'XL4 stand-ins: one more than half allowed (reviewer round 9, ported)|L|no|    return 2 * odd <= len(h)\n|||    return 2 * odd <= len(h) + 2\n'
  'XL4b stand-ins: fewer than half allowed (the stricter twin of XL4)|L|no|    return 2 * odd <= len(h)\n|||    return 2 * odd < len(h)\n'
  'XL5 stand-in reading for 4-letter heads (reviewer round 9)|L|no|or len(w) != len(h) or len(h) < 5:|||or len(w) != len(h) or len(h) < 4:'
  'XL6 identifier value excluded after strong keys too (reviewer round 9)|L|no|    if tier in ("short", "generic") and _IDENT_VALUE.match(v):|||    if _IDENT_VALUE.match(v):'
  'XL9 reference URI needs no / or # (reviewer round 9)|L|no|_REF_URI = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]{1,}:(?://)?\S*[/#]")|||_REF_URI = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]{1,}:(?://)?\S*")'
  'R10-1 SECRET: the fixpoint view off|L|no|SECRET_FIXPOINT = True|||SECRET_FIXPOINT = False'
  'R10-2 SECRET: the base64 view off|L|no|SECRET_DECODE_BASE64 = True|||SECRET_DECODE_BASE64 = False'
  'R10-3 SECRET: triple-quoted strings not read|L|no|SECRET_TRIPLE_QUOTES = True|||SECRET_TRIPLE_QUOTES = False'
  'R10-4 SECRET: parenthesised literals not read|L|no|SECRET_PAREN_LITERAL = True|||SECRET_PAREN_LITERAL = False'
  'R10-5 SECRET: split heads (pass_word, mot_de_passe) not read|L|no|SECRET_SPLIT_HEADS = True|||SECRET_SPLIT_HEADS = False'
  'R10-6 SECRET: the multilingual lexicon not added to the strong heads|L|no|STRONG_HEADS = STRONG_HEADS | frozenset(_clean(|||STRONG_HEADS = STRONG_HEADS | frozenset() and frozenset(_clean('
  'R10-7 SECRET: the confusable skeleton (Coptic, Cherokee, Armenian, Lisu) not folded|L|no|_FOLD.update(str.maketrans(_SKELETON))|||_FOLD.update({})'
  'R10-8 SECRET: spacing marks (Mc) kept in a key|L|no|            drop |= {"Mn", "Me", "Mc"}|||            drop |= {"Mn", "Me"}'
  'R10-9 SECRET: brace escapes (\u{70}) not decoded|L|no|_ESC = re.compile(r"\\(u\{[0-9A-Fa-f]{1,6}\}||||_ESC = re.compile(r"\\('
  'R10-10 SECRET: long escapes (\U00000070) not decoded|L|no|U[0-9A-Fa-f]{8}|u[0-9A-Fa-f]{4}||||u[0-9A-Fa-f]{4}|'
  'R10-11 SECRET: table rows not read|L|no|        if tier and tier != "numeric" and _has_ld(v) and credential_value(tier, v, ""):\n            yield "table-row-pair"|||        if False:\n            yield "table-row-pair"'
  'R10-12 SECRET: set statements not read|L|no|        if tier in ("strong", "generic") and _has_ld(v) and credential_value(tier, v, ""):\n            yield "set-command"|||        if False:\n            yield "set-command"'
  'R10-13 SECRET: a ticket id after a generic key read as a value|L|no|(_TICKET_VALUE.match(v) or _VERSION_VALUE.match(v))|||(False or _VERSION_VALUE.match(v))'
  'R10-14 SECRET: a version after a generic key read as a value|L|no|(_TICKET_VALUE.match(v) or _VERSION_VALUE.match(v))|||(_TICKET_VALUE.match(v) or False)'
  'R10-15 SECRET: a secret-store scheme reference (env:...) read as a value|L|no| or _REF_SCHEME.match(v):|||:'
  'R10-16 SECRET: joined literals across a newline not read|L|no|([\"'"'"'])\s*(?:\+|\.\.?|\|\||&|~)?\s*\1|||([\"'"'"'])[ \t]*(?:\+|\.\.?|\|\||&|~)?[ \t]*\1'
  'R10-17 SECRET: the R left arrows (<-, <<-) not a separator|L|no|_SEP_Q = r"\s*(?::=|=>|<<-|<-|:|=)\s*"|||_SEP_Q = r"\s*(?::=|=>|:|=)\s*"'
  'R10-18 SECRET: a digest key tail (sha256, split to sha) not a meta word|L|no|"storage", "sha", "md",|||"storage", "md",'
  'R10-19 SECRET: the type= attribute key (input type=password) not read|L|no|\b(?:key|name|type|id)\s*=\s*(?P<q1>|||\b(?:key|name|id)\s*=\s*(?P<q1>'
  'XL13 entity view on a text html.unescape leaves unchanged (reviewer round 9, ported: round 10 gates the view on a change, not on _ENT)|L|no|    d = html.unescape(t)\n    return d if d != t else None|||    d = html.unescape(t)\n    return d'
  'R10-20 SECRET: named entities (&equals;) not decoded|L|no|    d = html.unescape(t)\n    return d if d != t else None|||    d = re.sub(r"&#(\d+);?", lambda m: chr(int(m.group(1))), t)\n    return d if d != t else None'
  # round 11 (review r10 item 2): the round-10 reviewer's lint mutants LM1..LM18 VERBATIM (tools/rev_mutants.py
  # of that review; LM2 and LM15 are in equivalent=() below), and the C-mutants of the shared primitive
  # scripts/workable-items/secret_canon.py (target C: a mutated canon next to an unmutated lint): the
  # reviewer's scan mutants SM1..SM16 ported onto the same knob of the shared module (the round-11 scan
  # has no reader of its own for them any more) and own mutants K2a..K6d, one per part of the primitive
  'LM1 fixpoint steps 64 -> 4 (reviewer round 10, verbatim)|L|no|SECRET_FIXPOINT_STEPS = 64|||SECRET_FIXPOINT_STEPS = 4'
  'LM3 base64 decoded needs '\''='\'' only (colon form dropped) (reviewer round 10, verbatim)|L|no|if len(d) < 8 or not re.search(r"[=:]", d)|||if len(d) < 8 or not re.search(r"[=]", d)'
  'LM4 base64 run minimum 16 -> 20 (reviewer round 10, verbatim)|L|no|(?:[A-Za-z0-9+/_-]{4}){4,}|||(?:[A-Za-z0-9+/_-]{4}){5,}'
  'LM5 stand-in letters: at most half -> under half (reviewer round 10, verbatim)|L|no|return 2 * odd <= len(h)|||return 2 * odd < len(h)'
  'LM6 split heads: three-part form dropped (reviewer round 10, verbatim)|L|no|for j in (i + 2, i + 3):|||for j in (i + 2,):'
  'LM7 ticket value not anchored at end (reviewer round 10, verbatim)|L|no|_TICKET_VALUE = re.compile(r"^[A-Z][A-Z0-9]{1,9}-[0-9]{1,7}$")|||_TICKET_VALUE = re.compile(r"^[A-Z][A-Z0-9]{1,9}-[0-9]{1,7}")'
  'LM8 version: a bare number is a version (reviewer round 10, verbatim)|L|no|_VERSION_VALUE = re.compile(r"^v?[0-9]+(?:\.[0-9]+){1,3}|||_VERSION_VALUE = re.compile(r"^v?[0-9]+(?:\.[0-9]+){0,3}'
  'LM9 ref scheme: any text after the colon (reviewer round 10, verbatim)|L|no|r"awssm|azkv|k8s|kms):[A-Za-z_$]")|||r"awssm|azkv|k8s|kms):")'
  'LM10 R '\''<<-'\'' arrow dropped (reviewer round 10, verbatim)|L|no|_SEP_Q = r"\s*(?::=|=>|<<-|<-|:|=)\s*"|||_SEP_Q = r"\s*(?::=|=>|<-|:|=)\s*"'
  'LM11 set command only at line start (reviewer round 10, verbatim)|L|no|_RX_SET_CMD = re.compile(r"(?im)(?:^|[;\[{])|||_RX_SET_CMD = re.compile(r"(?im)(?:^)'
  'LM12 table row needs a closing pipe (reviewer round 10, verbatim)|L|no|`?[ \t]*(?:\||$)")|||`?[ \t]*\|")'
  'LM13 join: '\''&'\'' and '\''~'\'' operators dropped (reviewer round 10, verbatim)|L|no|\s*(?:\+|\.\.?|\|\||&|~)?\s*\1|||\s*(?:\+|\.\.?|\|\|)?\s*\1'
  'LM14 set command: generic keys dropped (reviewer round 10, verbatim)|L|no|if tier in ("strong", "generic") and _has_ld(v) and credential_value(tier, v, ""):\n            yield "set-command"|||if tier == "strong" and _has_ld(v) and credential_value(tier, v, ""):\n            yield "set-command"'
  'LM16 attribute key '\''id'\'' dropped (reviewer round 10, verbatim)|L|no|_ATTR_KEY = r"\b(?:key|name|type|id)\s*|||_ATTR_KEY = r"\b(?:key|name|type)\s*'
  'LM17 paren literal window 1024 -> 12 (reviewer round 10, verbatim)|L|no|[^()]{0,1024}?|||[^()]{0,12}?'
  'LM18 entity view returned even when unchanged (reviewer round 10, verbatim)|L|no|    return d if d != t else None\n\n\ndef _v_join|||    return d\n\n\ndef _v_join'
  'SM1c fixpoint 16 -> 1 and layers 3 -> 0|C|no|SECRET_LAYERS = 3 |||SECRET_LAYERS = 0 '
  'SM1d full fixpoint 16 -> 1|C|no|    for _ in range(16):\n        u = t|||    for _ in range(1):\n        u = t'
  'SM2c base64 run minimum 8 -> 20|C|no|(?:[A-Za-z0-9+/]{4}){2,}(?:[A-Za-z0-9+/]{2}==|||(?:[A-Za-z0-9+/]{4}){5,}(?:[A-Za-z0-9+/]{2}=='
  'SM3c base64 decoded: half alnum -> three quarters|C|no|if sum(1 for c in s if c.isalnum()) * 2 < len(s):|||if sum(1 for c in s if c.isalnum()) * 4 < len(s) * 3:'
  'SM4c base64 decoder dropped|C|no|    lambda t: _B64.sub(lambda m: _blob(m, base64.b64decode), t),\n|||'
  'SM5c Mn marks kept|C|no|if cat in ("Mn", "Me", "Cf")|||if cat in ("Me", "Cf")'
  'SM6c brace escapes dropped|C|no||\\u\{([0-9A-Fa-f]{1,6})\}|||||\\u\{(ZZZZ)\}|'
  'SM7c long U escape dropped|C|no||\\U([0-9A-Fa-f]{8})|||||\\U(ZZZZ)|'
  'SM8c join: & and ~ dropped|C|no|(?:\+|\.\.?|\|\||&|~)?\s*\1")|||(?:\+|\.\.?|\|\|)?\s*\1")'
  'SM11c mot de passe dropped|C|no|"credentials", "motdepasse",|||"credentials",'
  'SM13c set only at line start|C|no|(?:^|[;\[{\\n])[ \t]*(?:set|setenv|||(?:^)[ \t]*(?:set|setenv'
  'SM14c Cherokee small s dropped|C|no|"\uabaa": "s", |||'
  'SM15c pin needs 5 digits|C|no|r"[0-9]{4,12}", v|||r"[0-9]{5,12}", v'
  'K2a Mc placeholder dropped|C|no|            r = MC_MARK|||            r = '\'''\'''
  'K3a squash off|C|no|SQUASH_MIN = 3 |||SQUASH_MIN = 99 '
  'K3b join max 4 -> 2|C|no|JOIN_MAX = 4 |||JOIN_MAX = 2 '
  'K4a wildcard: any share of ASCII|C|no|return asc * 2 >= len(w) and|||return asc >= 0 and'
  'K6a value min 8 -> 6|C|no|    if len(v) < 8 or len(v) > 4096:|||    if len(v) < 6 or len(v) > 4096:'
  'K6b ticket accepted|C|no|(_IDENT.match(v) or _TICKET.match(v) or _VERSION.match(v)):\n        return False\n    if tier == "space"|||(_IDENT.match(v) or _VERSION.match(v)):\n        return False\n    if tier == "space"'
  'K6c version accepted|C|no|(_IDENT.match(v) or _TICKET.match(v) or _VERSION.match(v)):\n        return False\n    if tier == "space"|||(_IDENT.match(v) or _TICKET.match(v)):\n        return False\n    if tier == "space"'
  'K6d ref uri accepted|C|no|if _PATH.match(v) or _REF_URI.match(v) or|||if _PATH.match(v) or'
  'SM10c dot separator dropped|C|no|_JOINGAP = re.compile(r"^[ \t_.\-|||_JOINGAP = re.compile(r"^[ \t_\-'
  'SM12c tail loop never extends (ported: round 11 removed the cancel flag)|C|no|            e = ws[q][2]\n            q += 1\n        out.append|||            break\n        out.append'
  'SM12d any attached word is a tail|C|no|            if not (nw in TAIL_OK or nw.isdigit()|||            if not (True or nw.isdigit()'
  'C25 r11 a number joins a split key word across a space|C|no|            if k > 1 and lows[j + 1].isdigit() and re.search(|||            if False and lows[j + 1].isdigit() and re.search('
  'C26 r11 a URL user-info placeholder is a value|C|no|"${<[(" and not is_placeholder(v) and not re.fullmatch|||"${" and not re.fullmatch'
  'C27 r11 the value classifier keeps placeholders|C|no|    if is_placeholder(v):\n        return False\n    literal|||    if False:\n        return False\n    literal'
  'C28 r11 an identifier needs letters-then-digits parts again|C|no|(?=(?:[a-z0-9]+[_.-])*[a-z]{3,}(?:[_.-]|$))[a-z][a-z0-9]*(?:[_.-][a-z0-9]+)+$|||[a-z]+[0-9]*(?:[_.-](?:[a-z]+[0-9]*|[0-9]+))+$'
  'C29 r11 the attached join-negative words are keys again|C|no|            if t == "short" and j > 0 and view[ws[j - 1][2]:ws[j][1]] == "" and lows[j - 1] in SHORT_JOIN_NEGATIVE:|||            if False:'
  'C30 r11 the suffix rules read joined forms too|C|no|            t = word_tier(joined, prev, k == 1)|||            t = word_tier(joined, prev, True)'
  'C31 r11 a reference by name is a value|C|no| or _REF_NAME.match(v) or ||| or '
  'C32 r11 a short key colon label is read|C|no|    if tier == "short" and not quoted and op in (":", "\uff1a"):\n        return False|||    if False:\n        return False'
  'C33 r11 the suffix join-negative prefix check off|C|no| and w[:-len(h)] not in SHORT_JOIN_NEGATIVE:|||:'
)

# Equivalent mutants (section 11.4.276(D), review r9 F4): an edit the harness would apply but that cannot
# change the lint's answer. They are not run as mutants; each is listed with its evidence file, a run of
# docs/qa/tracker_intake_2026_11_16_v10/tools/equiv_check.py on the same edit (every census member, every
# fixture row, 200000 seeded fuzz strings and every code point inside and before a key; views and rule
# names compared; its control needle SECRET_FOLD off must differ). The harness checks that the edit still
# matches the lint exactly once (so a code change re-opens the question) and that the evidence says
# view_differences=0 hit_differences=0 with the control needle ok.
# id description | evidence file (repo-relative) | old ||| new
equivalent=(
  'RV2 escape view without NFKC (reviewer round 9): _clean() applies NFKD then NFKC to every non-ASCII view, and NFKD(NFKC(s)) = NFKD(s)|docs/qa/tracker_intake_2026_11_16_v11/runs/equiv_RV2.txt|                d = _clean(unicodedata.normalize("NFKC", d))|||                d = _clean(d)'
  'LR2 SECRET_NFKC off: the same identity for the first view; an ASCII text is NFKC-invariant|docs/qa/tracker_intake_2026_11_16_v11/runs/equiv_LR2.txt|SECRET_NFKC = True|||SECRET_NFKC = False'
  'XL12 U+3164 dropped from the fillers (reviewer round 9): NFKC folds HANGUL FILLER U+3164 to U+1160, which stays a filler|docs/qa/tracker_intake_2026_11_16_v11/runs/equiv_XL12.txt|_FILLERS = frozenset("\u115f\u1160\u3164\uffa0")|||_FILLERS = frozenset("\u115f\u1160\uffa0")'
  'LM2 base64 decoded minimum 8 -> 12 (reviewer round 10): the run regex needs 16 or more base64 characters, which decode to 12 or more bytes, so no decoded text is shorter than 12|docs/qa/tracker_intake_2026_11_16_v11/runs/equiv_LM2.txt|if len(d) < 8 or not re.search(r"[=:]", d)|||if len(d) < 12 or not re.search(r"[=:]", d)'
  'LM15 table row admits the numeric tier (reviewer round 10): a numeric value is digits only (credential_value) while _has_ld needs a letter, so the conjunction is false for the numeric tier either way|docs/qa/tracker_intake_2026_11_16_v11/runs/equiv_LM15.txt|if tier and tier != "numeric" and _has_ld(v) and credential_value(tier, v, ""):|||if tier and _has_ld(v) and credential_value(tier, v, ""):'
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
    if [ "$target" = C ]; then  # the shared primitive: a mutated canon next to an unmutated lint
      if ! mkcopy "$canon" "$d/secret_canon.py" "$old" "$new" 2>"$d/err"; then echo "FAIL $id: stale mutant"; return; fi
      mkcopy "$src" "$d/m.py" "" "" || { echo "FAIL $id: no copy"; return; }
    else
      if ! mkcopy "$src" "$d/m.py" "$old" "$new" 2>"$d/err"; then echo "FAIL $id: stale mutant"; return; fi
      cp "$canon" "$d/secret_canon.py" || { echo "FAIL $id: no canon copy"; return; }
    fi
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
cp "$canon" "$tmp/secret_canon.py" || exit 2
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
export tmp root src suite canon
# bash cannot export arrays: hand each worker the mutant list through a file
printf '%s\n' "${mutants[@]}" >"$tmp/mutants.txt"
printf '%s\n' "${sel[@]}" | xargs -P "$jobs" -I{} bash -c 'mapfile -t mutants <"$tmp/mutants.txt"; one_mutant "$1" >"$tmp/v$1"' _ {}
for i in "${sel[@]}"; do
  if [ -f "$tmp/v$i" ]; then cat "$tmp/v$i"; grep -q '^PASS' "$tmp/v$i" || fail=1
  else echo "FAIL ${mutants[$i]%%|*}: no verdict"; fail=1; fi
done
neq=0
for e in "${equivalent[@]}"; do
  id=${e%% *}; rest=${e#*|}; ev=${rest%%|*}; rest=${rest#*|}; old=${rest%%|||*}; new=${rest#*|||}
  if [ -n "${INTAKE_LINT_MUT_ONLY:-}" ]; then case ",$INTAKE_LINT_MUT_ONLY," in *",$id,"*) ;; *) continue ;; esac; fi
  neq=$((neq + 1))
  if ! mkcopy "$src" "$tmp/eq.py" "$old" "$new" 2>"$tmp/eq.err"; then echo "FAIL $id: equivalent edit is stale (re-run equiv_check.py)"; fail=1
  elif ! [ -f "$root/$ev" ]; then echo "FAIL $id: no evidence file $ev"; fail=1
  elif ! grep -qx "EDIT edit_sha256=$(printf '%s|||%s' "$old" "$new" | sha256sum | cut -d' ' -f1)" "$root/$ev"; then
    echo "FAIL $id: the evidence was made for another edit (re-run equiv_check.py): $ev"; fail=1
  elif grep -q '^CONTROL needle (SECRET_FOLD off): hit_differences>=1 ok$' "$root/$ev" \
       && grep -q '^RESULT corpus=[0-9]* view_differences=0 hit_differences=0 fuzz=[1-9][0-9]* codepoints=True$' "$root/$ev"; then
    echo "EQUIV $id: $(grep '^RESULT' "$root/$ev")"
  else echo "FAIL $id: the evidence does not show an equivalent mutant: $ev"; fail=1; fi
done
echo "RESULT: mutants=${#sel[@]} equivalent=$neq $([ "$fail" = 0 ] && echo 'all killed as declared' || echo 'FAILED')"
[ "$fail" = 0 ]
