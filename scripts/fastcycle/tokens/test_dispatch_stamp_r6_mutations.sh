#!/usr/bin/env bash
# test_dispatch_stamp_r6_mutations.sh -- paired-mutation proof for the
# token-attribution tools (T048 restart, round-1 structural fixer round,
# §11.4.276(D) and §1.1).
#
# WHAT IT PROVES: every mutation below re-creates a defect an independent
# reviewer found (R3 / R4, round 1 of the T048 restart) or one this round's
# fixer added, in a SCRATCH COPY of the tools. For each mutant the five suites
# that guard these tools are run against the mutated copy, exactly as they
# run on the real tree. A mutant is KILLED when at least one suite exits
# non-zero. The harness FAILs if any mutant survives, if a mutation's anchor
# text is not found exactly once (the mutation could not be applied), or if
# a file is not restored byte-identically afterwards.
#
# Files mutated (scratch copies only; the real tree is never written):
#   tokens/transcript_ingest.py, tokens/dispatch_stamp.sh,
#   ../release_prefix.sh (its superproject tier and .env parsing are what the
#   r5 suite guards), and the consumer's .claude/settings.json hook entry.
#
# Suites run per mutant:
#   tokens/test_dispatch_stamp.sh, tokens/test_dispatch_stamp_r4_regression.sh,
#   tokens/test_dispatch_stamp_r5_regression.sh,
#   tests/test_dispatch_stamp_red.sh, tests/test_token_attribution_red.sh
#
# SCRATCH LAYOUT: the current constitution scripts/ tree is committed into a
# scratch git repo and registered as the `constitution` submodule of a scratch
# parent, so the suites see the same submodule boundary as a real consumer.
# The parent gets a copy of the consuming project's agent_registry_writer.sh
# and .claude/settings.json (PART A of test_token_attribution_red.sh needs
# them), an empty docs/requests/ directory, and a .env whose
# HELIX_RELEASE_PREFIX is a FIXTURE value deriving the ticket prefix "ATM"
# (the static transcript fixtures use ATM ids). No secret is involved.
#
# SKIP: when this constitution checkout has no superproject carrying those two
# consumer files, the harness prints SKIP and exits 0 without claiming a
# result (it can only prove kills it actually ran).
#
# Round 2 (T048 restart, §11.4.276(D)): the nine reviewer mutants that
# survived round 1 (N2, N3, N4, N6, N7, N8, N9, N14, N23) are adopted
# verbatim in intent, with anchors on the current code, plus this round's
# own mutants L1-L13 for the round-2 fixes (concurrent ingest, ownership,
# locale, jq-less reader, fail-closed guard, prefix notice, refusal text,
# summary counts, malformed field types) and N7b (path spelling).
#
# Round 3 (T048 restart, §11.4.276(E) STRUCTURAL round): the eight reviewer
# mutants that survived round 2 (X1-X7, X9, review area V1, round 3) are
# adopted. X3, X4, X5 and X6 are verbatim (their anchors are unchanged). X1,
# X2, X7 and X9 are re-anchored on the restructured code with the SAME
# semantics: X1 the whole-run rollback commits instead; X2 the lock-timeout
# exit returns 0; X7 a negative timeout is accepted; X9 an unparseable
# timeout behaves as 0. Plus this round's own mutants Y1-Y12 (per-record
# isolation, timeout refusal, ranges, negative counters) and Z1-Z8 (the
# shared strict JSON reader: duplicate keys, depth, NUL handling, the gate,
# the awk-missing refusal), and A1-A4, the resuming fixer's own adversarial
# mutants (off-by-one depth limit; duplicate-key check keyed on depth, a false
# refusal; off-by-one counter / total range), each first shown to SURVIVE the
# suites and then killed by new rows (r7 M33b/M33c, PART J J-P4). Two suites
# are added: the generated failure-path
# matrix tokens/test_dispatch_stamp_r7_matrix.sh (which ALSO neutralises
# every enumerated failure branch of dispatch_stamp.sh itself, a generated
# mutant per branch) and PART J of the attribution suite (its own meta-check
# over every except / non-zero return / raise of transcript_ingest.py).
# RETIRED in round 3, with the reason (not run): L8 "jq parse error treated as
# an empty field" -- after the shared strict reader became the gate for both
# paths, jq can no longer fail on a payload that reaches json_field; the
# line is a fail-closed backstop and is listed EQUIVALENT in the r7 matrix,
# whose parity half shows jq and the reader agree on 546 payloads. Likewise
# not adopted: "jq reads only the first of two documents" (the jq-side
# single-document check) -- shown to survive every suite because the shared
# reader refuses a second document before jq runs; it is the same backstop.
# Also not adopted, equivalent by construction: removing the per-record
# SAVEPOINT rollback (every upsert is one SQL statement, which SQLite already
# rolls back as a unit) and removing the lone-LOW-surrogate -> U+FFFD
# decoding (both spellings are non-separators, so no verdict changes).
#
# Round 8 (T048 restart, independent review of the V1 tokens): the four
# reviewer mutants that survived (RV3 hexval without tolower, RV6 symlinked
# subagent classification, RV7 dispatch sessionId before the record's own,
# RV10 the fill branch overwriting a non-NULL item_id/session_id) are adopted
# as the R8-RV* rows, each killed by a new row (r7 M40, PART K K9/K1b/K8),
# plus the fixer's own R8-F* mutants for the sidecar attribution and its
# counters (F1), resumed-session replays (F7) and symlinked directories (F8).
# Two anchors were re-pointed because the code they sit in changed: M3 (the
# item=? rule now exists on two lines, one per description source; the sidecar
# line is R8-F1h) and X6 (the awk path encoding is now <length>:<key>). The F2
# collision fix has no revert row: restoring the "."-joined path needs two
# non-adjacent edits, which a one-anchor row cannot express; its guard is the
# r7 rows M41-M41d, observed RED before the fix.
# Round 9 (T48 restart, V1 re-review follow-ups): the reviewer mutants RV-F
# (item=?? accepted as one id), RV-G (short prefix padded with Z), RV-M (sidecar
# read capped at 256 bytes) and RV-C (surrogate pair formula *1000) are adopted
# as R9-T1a/b, R9-T2a/b, R9-T3, R9-T4 (the two-sided ones have a row per tool),
# plus this round's own rows for the symlinked-subagent classification (S1),
# the zeroed-copy identity rule (S4), the silent dispatch pass (N1), the
# tool_name type contract (S2), the linear escape decoding (S3) and the awk
# capability probe (P2). R6_ONLY=<regex on the mutant id> runs a SUBSET and says
# so; without it every row runs.
# Round 10 (T048 restart, V1 re-review of the landed round-9 tree): the
# reviewer's mutants MA (4-byte UTF-8 lead 241), MD (sidecar cap 600), MG and
# MG2 (short prefix padded with Z) are adopted as R10-MA/MD/MG/MG2. On the
# landed tree all four were already KILLED (subset run, 2026-10-09: MA by the
# r7 matrix, MD and MG by the attribution suite, MG2 by test_dispatch_stamp.sh);
# each now also has a dedicated row (test_dispatch_stamp.sh section K, PART K
# K18). Z2 and A1 are re-anchored on the weighted depth limit (F8), and the
# R10-F8a/b rows (jq's depth weights) and R10-F9a/b/c rows (no glob expansion
# of the extra prefixes; the invalid-pattern fallback and its notice) are this
# round's own. DO NOT edit this file while it runs: bash reads a script as it
# executes, and an edit shifts the offsets of the lines not yet read.
# Round 11 (T048 restart, STRUCTURAL round on V1, §11.4.276(E)): the
# reviewer's surviving mutants V1 (CR is not whitespace), V11 (an all-zero copy
# moves the identity) and V12 (the sidecar order) are adopted as R11-V1,
# R11-V11, R11-V12, each with a behavioural row (test_dispatch_stamp.sh
# section O, PART K K14f, K13f). This round's own rows R11-1* (extra prefixes
# are data), R11-2* (the clean environment), R11-3* (the incremental path
# match), R11-4* (the directory walk) and R11-6* (the sidecar cap) guard the
# class-wide fixes. Re-anchored, same semantics, because the code they sat in
# was restructured: M13, L5 (the upper-casing now feeds `candidate`), DS-M3
# (a valid token is appended in a `case` arm), L6 and X6 (cur_path() was
# replaced by the per-depth match at_want() / seg_ok()); and L10, whose
# anchor has not been unique since round 10 added a second identical
# ITEM_EXAMPLE line (a full run would have reported it "not applied").
# Runtime: about 150 mutants x 6 suites, several hours. Run it in the
# background (§11.4.89).
#
# Exit: 0 = every mutant killed (or SKIP); 1 = a mutant survived, a mutation
# could not be applied, a restore was not byte-identical, or the unmutated
# baseline was not green.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
CONST_SCRIPTS="$(cd "$HERE/../.." && pwd)"
SUPER="$(git -C "$HERE" rev-parse --show-superproject-working-tree 2>/dev/null || true)"
WRITER_SRC="${SUPER:+$SUPER/scripts/hooks/agent_registry_writer.sh}"
SETTINGS_SRC="${SUPER:+$SUPER/.claude/settings.json}"

if [ -z "$SUPER" ] || [ ! -f "$WRITER_SRC" ] || [ ! -f "$SETTINGS_SRC" ]; then
  echo "SKIP: no consuming superproject with scripts/hooks/agent_registry_writer.sh and .claude/settings.json was found (superproject='${SUPER}'); the attribution suite's PART A cannot run, so no mutant result is claimed"
  exit 0
fi

WORK="$(mktemp -d)" || { echo "FAIL: mktemp"; exit 1; }
trap 'rm -rf "$WORK"' EXIT
G=(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git -c user.email=r6@example.invalid -c user.name=r6 -c protocol.file.allow=always -c init.defaultBranch=main)

SRC="$WORK/const_src"
P="$WORK/consumer"
mkdir -p "$SRC" "$P/scripts/hooks" "$P/.claude" "$P/docs/requests"
cp -R "$CONST_SCRIPTS" "$SRC/scripts"
find "$SRC" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null
cp "$WRITER_SRC" "$P/scripts/hooks/agent_registry_writer.sh"
cp "$SETTINGS_SRC" "$P/.claude/settings.json"
printf 'HELIX_RELEASE_PREFIX=atm_fixture_prefix\n' > "$P/.env"
if ! { "${G[@]}" -C "$SRC" init -q && "${G[@]}" -C "$SRC" add -A && "${G[@]}" -C "$SRC" commit -qm scratch \
       && "${G[@]}" -C "$P" init -q && "${G[@]}" -C "$P" add -A && "${G[@]}" -C "$P" commit -qm scratch \
       && "${G[@]}" -C "$P" submodule add -q "$SRC" constitution; } >/dev/null 2>&1; then
  echo "FAIL: scratch consumer setup (git init / submodule add) failed"
  exit 1
fi
C="$P/constitution/scripts"
if [ ! -f "$C/fastcycle/tokens/transcript_ingest.py" ]; then
  echo "FAIL: scratch submodule checkout is missing the tools"
  exit 1
fi

SUITES=(
  fastcycle/tokens/test_dispatch_stamp.sh
  fastcycle/tokens/test_dispatch_stamp_r4_regression.sh
  fastcycle/tokens/test_dispatch_stamp_r5_regression.sh
  fastcycle/tests/test_dispatch_stamp_red.sh
  fastcycle/tests/test_token_attribution_red.sh
  fastcycle/tokens/test_dispatch_stamp_r7_matrix.sh
)

# run_suites <tag> -> prints "<suite>=<rc> ..." and returns the number of
# suites that exited non-zero.
run_suites() {
  local tag="$1" s rc nfail=0 line=""
  for s in "${SUITES[@]}"; do
    (cd "$P" && env -u FC_DISPATCH_ITEM_ID_RE -u FC_DISPATCH_EXTRA_ITEM_PREFIXES -u HELIX_RELEASE_PREFIX -u HELIX_PROJECT_ROOT \
       bash "$C/$s") < /dev/null > "$WORK/log_${tag}_$(basename "$s").log" 2>&1
    rc=$?
    line="$line $(basename "$s" .sh)=$rc"
    [ "$rc" -ne 0 ] && nfail=$((nfail + 1))
  done
  echo "$line"
  return "$nfail"
}

echo "=== baseline (unmutated scratch copy) ==="
BASE_LINE="$(run_suites baseline)"
BASE_FAILS=$?
echo "  $BASE_LINE"
if [ "$BASE_FAILS" -ne 0 ]; then
  echo "FAIL: the unmutated scratch copy is not green ($BASE_FAILS suite(s) failed); no mutant result would mean anything. Logs: $WORK (removed on exit)"
  for f in "$WORK"/log_baseline_*.log; do grep -E '^FAIL|  FAIL|NOT ok' "$f" | head -3; done
  exit 1
fi

# Mutation table: id <TAB> file (relative to the consumer root) <TAB> python
# literal for the anchor text <TAB> python literal for its replacement.
cat > "$WORK/mutants.tsv" <<'EOF'
TI-M1 drop msg-id dedup	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'    if msg_id:\n        row_hash = hashlib'	'    if False:\n        row_hash = hashlib'
TI-M3 total excludes both cache fields	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'return MEASURED, None, it + ot + crt + cct'	'return MEASURED, None, it + ot'
M7 total drops cache_creation	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'return MEASURED, None, it + ot + crt + cct'	'return MEASURED, None, it + ot + crt'
TI-M5 first line wins (old INSERT OR IGNORE)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'            merged[name] = max(a, b)'	'            merged[name] = a'
M6 last line wins (INSERT OR REPLACE)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'            merged[name] = max(a, b)'	'            merged[name] = b'
H1c re-ingest never updates	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'    if not grew and reattribution is None:\n        return "unchanged"'	'    if True:\n        return "unchanged"'
M5 silence the decreasing-duplicate warning	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'    if decreased:\n        print('	'    if False:\n        print('
M1 dispatch map first id wins on conflict	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'            if len(values) == 1:\n                entry[key] = values[0]\n            elif len(values) > 1:'	'            if values:\n                entry[key] = values[0]\n            if len(values) > 1:'
M1b dispatch map last id wins on conflict	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'            if len(values) == 1:\n                entry[key] = values[0]\n            elif len(values) > 1:'	'            if values:\n                entry[key] = values[-1]\n            if len(values) > 1:'
M2b drop the left tag boundary	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'ITEM_TAG_TEMPLATE = r"(?:^|[ \\t\\n\\r\\f\\v])item='	'ITEM_TAG_TEMPLATE = r"item='
RB drop the right tag boundary (ingest)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'(%s|\\?)(?![A-Za-z0-9_])"'	'(%s|\\?)"'
M3 accept item=? as an item id (dispatch description)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'\n                if m and m.group(1) != "?":'	'\n                if m:'
R8-F1h accept item=? as an item id (sidecar description)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'\n            if m and m.group(1) != "?":'	'\n            if m:'
M4 disable subagents/ discovery	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'        if os.path.isdir(subagents_dir):'	'        if False:'
M8 parent turns item-attributed	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'        agent_id = None\n        item_id = None  #'	'        agent_id = None\n        item_id = next((v["item_id"] for v in dispatch_map.values() if v["item_id"]), None)  #'
M9 partial usage gets a total	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'        return MEASURED, None, it + ot + crt + cct\n'	'        return MEASURED, None, it + ot + crt + cct\n    if it is not None and ot is not None:\n        return MEASURED, None, it + ot\n'
F5 partial usage labelled measured	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'    return (UNMEASURED,\n'	'    return (MEASURED,\n'
M10 missing_instrument loses the file path	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'% (ref, filepath, what),'	'% (ref, "", what),'
M11 ignore extra prefixes (ingest)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'for tok in re.split(r"[,| \\t\\n]+", extra):'	'for tok in []:'
M12 ignore the full override (ingest)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'    if override:\n        value_re = override'	'    if False:\n        value_re = override'
M13 no upper-case on extra prefixes (ingest; re-anchored round 11)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'candidate = _ascii_upper(tok)'	'candidate = tok'
F2 strict decode on invalid UTF-8	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'errors="replace")'	'errors="strict")'
D1 guard always allows	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'FOUND="$(extract_item "$DESCRIPTION")"\nif [[ -n "$FOUND" ]]; then'	'FOUND="$(extract_item "$DESCRIPTION")"\nif true; then'
D2 left boundary (^|.)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'ITEM_RE="(^|[[:space:]])item='	'ITEM_RE="(^|.)item='
RB drop the right tag boundary (stamp)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'([^[:alnum:]_]|\\$)"'	'"'
D3 release_prefix resolved via cwd git toplevel	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'rp_script="$(cd "$self_dir/../.." 2>/dev/null && pwd 2>/dev/null || true)/release_prefix.sh"'	'rp_script="$(git rev-parse --show-toplevel 2>/dev/null)/scripts/release_prefix.sh"'
DS-M3 ignore extra prefixes (stamp; re-anchored round 11)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'*) ITEM_ALL_PREFIXES="${ITEM_ALL_PREFIXES}|${_fc_p_upper}" ;;'	'*) : ;;'
DS no upper-case on extra prefixes (stamp)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'_fc_p_upper="$(printf \'%s\' "$_fc_p" | tr \'[:lower:]\' \'[:upper:]\')"'	'_fc_p_upper="$_fc_p"'
DS-M5 fall back to .prompt instead of .subagent	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'DESCRIPTION="$(json_field tool_input subagent)"'	'DESCRIPTION="$(json_field tool_input prompt)"'
DS restore the hardcoded ATM fallback	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'FC_DEFAULT_PREFIX="$(_fc_derive_key_prefix "$base")"'	'FC_DEFAULT_PREFIX="$(_fc_derive_key_prefix "${base:-ATM}")"'
DS ignore the full override	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'if [ -n "${FC_DISPATCH_ITEM_ID_RE:-}" ]; then'	'if false; then'
DS extract mode writes to stderr	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'  extract_item "$DESCRIPTION"\n  exit 0'	'  extract_item "$DESCRIPTION"\n  echo debug >&2\n  exit 0'
R1 release_prefix keeps double quotes	constitution/scripts/release_prefix.sh	'    \\"*\\") val="${val#\\"}"; val="${val%\\"}" ;;'	'    \\"*\\") : ;;'
R2 release_prefix first .env assignment wins	constitution/scripts/release_prefix.sh	"| grep -vE '^[[:space:]]*#' | tail -n1 || true)\""	"| grep -vE '^[[:space:]]*#' | head -n1 || true)\""
R3 release_prefix drops the camelCase split	constitution/scripts/release_prefix.sh	"s/([a-z0-9])([A-Z])/\\1_\\2/g; "	""
R4 release_prefix superproject tier disabled	constitution/scripts/release_prefix.sh	'  if root="$(git -C "$self_dir" rev-parse --show-superproject-working-tree 2>/dev/null)" \\'	'  if root="" \\'
RS1 unreadable file not counted	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'        READ_STATS["unreadable_files"] += 1\n'	''
RS2 invalid UTF-8 line not counted	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'                READ_STATS["invalid_utf8_lines"] += 1\n'	''
RS3 unparseable line not counted	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'                READ_STATS["unparseable_lines"] += 1\n'	''
W1 normal streaming growth warns	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'    merged, decreased = merge_usage(stored, row)\n'	'    merged, decreased = merge_usage(stored, row)\n    decreased = decreased or [n for n in CORE_FIELDS if row[n] != stored[n]]\n'
DS guard fails open from /tmp only	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'if [[ -n "$FOUND" ]]; then'	'if [[ -n "$FOUND" ]] || [ "$PWD" = /tmp ]; then'
S1 settings.json hook points at a missing file	.claude/settings.json	'tokens/dispatch_stamp.sh\\"'	'tokens/dispatch_stamp.sh.disabled\\"'
N2 merge rewrites identity on every update (V1-I3)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'    if stored["agent_id"] is not None and row["agent_id"] is None:'	'    if True:'
N3 merge never fills a missing counter (V1-I3)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'        if a is None:\n            merged[name] = b'	'        if a is None:\n            merged[name] = a'
N4 merged row takes status/missing from the incoming line (V1-I3)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'    params.update(row_hash=row["row_hash"], usage_status=status,\n                  missing_instrument=missing, total_tokens=total)'	'    params.update(row_hash=row["row_hash"], usage_status=row["usage_status"],\n                  missing_instrument=row["missing_instrument"], total_tokens=total)'
N6 session conflict resolves to the first session (V1-I3)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'seen_sessions.setdefault(agent_id, []).append(session_id)'	'seen_sessions.setdefault(agent_id, [session_id])'
N7 subagent transcripts read before parents (V1-I3)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'return sorted(is_sub, key=lambda p: (is_sub[p], p))'	'return sorted(is_sub, key=lambda p: (not is_sub[p], p))'
N7b path spelling decides the order again (V1-I2)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'        real = os.path.realpath(p)'	'        real = p'
N8 stamp right boundary accepts _ (V1-I3)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'([^[:alnum:]_]|\\$)"'	'([^[:alnum:]]|\\$)"'
N9 ingest right boundary accepts _ (V1-I3)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'(%s|\\?)(?![A-Za-z0-9_])"'	'(%s|\\?)(?![A-Za-z0-9])"'
N14 missing_instrument ignores the no-usage-block case (V1-I3)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'    if not usage_block_present:'	'    if False:'
N23 decrease warning only for output_tokens (V1-I3)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'            if b < a:'	'            if b < a and name == "output_tokens":'
L1 row pass under a DEFERRED transaction (V1-I1)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'conn.execute("BEGIN IMMEDIATE")'	'conn.execute("BEGIN")'
L2 same-owner attribution never filled (V1-I2)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'    elif stored["agent_id"] == row["agent_id"]:'	'    elif False:'
L3 stamp locale not pinned (V1-M2)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'export LC_ALL=C\n'	':\n'
L4 ingest left boundary accepts non-ASCII spaces (V1-M2)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'r"(?:^|[ \\t\\n\\r\\f\\v])item='	'r"(?:^|[ \\t\\n\\r\\f\\v\\u00a0\\u2003])item='
L5 ingest extra prefix upper-cased with str.upper (V1-M2; re-anchored round 11)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'candidate = _ascii_upper(tok)'	'candidate = tok.upper()'
L6 jq-less reader takes the key at any depth (V1-M4a; re-anchored round 11)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'if (at_want()) val = STR'	'if (typ[d] == "o" && key[d] == wkey[WD]) val = STR'
L7 guard fails open on an unparseable payload (V1-M4a)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'if [[ "$PARSE_OK" -eq 0 ]]; then'	'if false; then'
L9 prefix fallback silent in GUARD mode (V1-M3)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'[ -n "$FC_PREFIX_NOTICE" ] && echo "$FC_PREFIX_NOTICE" >&2'	':'
L10 refusal example hardcodes ATM (V1-M3; re-anchored round 11: since round 10 the line exists twice and the old anchor was not unique)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'  ITEM_EXAMPLE="item=${FC_DEFAULT_PREFIX}-1041"\nfi\n'	'  ITEM_EXAMPLE="item=ATM-1041"\nfi\n'
L11 summary keeps a row first status (V1-M1)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'final_status[row["row_hash"]] = status'	'final_status.setdefault(row["row_hash"], status)'
L12 non-string identity fields reach the SQL binding (class: abort loses the run)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'    if value is None or isinstance(value, str):\n        return value\n    READ_STATS'	'    if True:\n        return value\n    READ_STATS'
L13 a JSON true counts as 1 token	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'    if isinstance(value, bool) or not isinstance(value, int):'	'    if not isinstance(value, int):'
X1 whole-run rollback commits instead (R3V1-I1, re-anchored)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'            if conn.in_transaction:\n                conn.execute(\"ROLLBACK\")'	'            if conn.in_transaction:\n                conn.execute(\"COMMIT\")'
X2 lock-timeout exit returns 0 (R3V1-I1, re-anchored)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'\"it, or raise FC_TELEMETRY_DB_LOCK_TIMEOUT_S\" % (args.db, _lock_timeout_s(), exc),\n              file=sys.stderr)\n        return 1'	'\"it, or raise FC_TELEMETRY_DB_LOCK_TIMEOUT_S\" % (args.db, _lock_timeout_s(), exc),\n              file=sys.stderr)\n        return 0'
X3 lock timeout ignored, sqlite default 5s (R3V1-I1, verbatim)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'conn = sqlite3.connect(path, timeout=_lock_timeout_s(), isolation_level=None)'	'conn = sqlite3.connect(path, isolation_level=None)'
X4 awk reader accepts raw control characters (R3V1-I1, verbatim)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'        if (c < \" \") return 0\n'	''
X5 ingest left boundary drops CR (R3V1-I1, verbatim)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'ITEM_TAG_TEMPLATE = r\"(?:^|[ \\t\\n\\r\\f\\v])item='	'ITEM_TAG_TEMPLATE = r\"(?:^|[ \\t\\n\\f\\v])item='
X6 awk path: an array level matches any segment (R3V1-I1; re-anchored round 11)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	': (wtyp[j] == "a") }'	': 1 }'
X7 negative timeout accepted (R3V1-I1, re-anchored)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'if value is None or not math.isfinite(value) or value < 0:'	'if value is None or not math.isfinite(value):'
X9 unparseable timeout behaves as 0 (R3V1-I1, re-anchored)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'    except ValueError:\n        value = None\n    if value is None'	'    except ValueError:\n        value = 0.0\n    if value is None'
Y1 an unexpected per-record error aborts the run	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'except Exception as exc:  # one record'	'except ZeroDivisionError as exc:  # one record'
Y2 record-level database errors treated as fatal	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'        if not _is_record_level_db_error(exc):\n            raise'	'        if True:\n            raise'
Y3 timeout nan/inf accepted	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'not math.isfinite(value) or '	''
Y4 a rejected record keeps its read counters	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'    READ_STATS.clear()\n    READ_STATS.update(stats_before)\n'	''
Y5 a too-deep line aborts the run again	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'            except RecursionError:'	'            except ZeroDivisionError:'
Y6 a too-long number line aborts the run again	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'            except ValueError:\n                if on_reject'	'            except ZeroDivisionError:\n                if on_reject'
Y7 rejected records not counted	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'rejected[reason] = rejected.get(reason, 0) + 1'	'rejected.setdefault(reason, 0)'
Y8 total range not checked	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'        if it + ot + crt + cct > INT64_MAX:'	'        if False:'
Y9 counter range not checked	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'    if value > INT64_MAX:\n        raise RecordRejected'	'    if False:\n        raise RecordRejected'
Y10 a negative counter is measured again	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'    if value < 0:\n        READ_STATS[\"malformed_fields\"] += 1\n        return None\n'	''
Y11 a refused timeout exits 1	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'print(\"transcript_ingest: refusing to run: %s\" % exc, file=sys.stderr)\n        return 2'	'print(\"transcript_ingest: refusing to run: %s\" % exc, file=sys.stderr)\n        return 1'
Y12 database failure prints a traceback (handler removed)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'    except sqlite3.DatabaseError as exc:\n        print(\"transcript_ingest: the database'	'    except ZeroDivisionError as exc:\n        print(\"transcript_ingest: the database'
Z1 duplicate keys accepted again (R3V1-M1)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'          if ((oid[d], STR) in seen) exit 3\n'	''
Z2 depth limit raised past jq's (re-anchored round 10: the weighted limit)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'      MAXW = 10000\n'	'      MAXW = 100000\n'
Z3 awk decodes \u0000 to NUL again (R3V1-M4)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'            if (cp == 0) cp = 65533\n'	''
Z4 jq outputs NUL again (R3V1-M4)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'then gsub(\\\"\\\\u0000\\\"; \\\"\\\\ufffd\\\") else'	'then . else'
Z5 raw NUL bytes dropped silently again	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'  PAYLOAD=\"$(awk '	'  PAYLOAD=\"$(cat; : awk '
Z6 the gate result is ignored	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'GATE=\"$(json_read -)\" || PARSE_OK=0'	'GATE=\"$(json_read -)\" || :'
Z7 no awk: fail open	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'if [[ \"$AWK_MISSING\" -eq 1 ]]; then\n  PARSE_OK=0'	'if [[ \"$AWK_MISSING\" -eq 1 ]]; then\n  PARSE_OK=1'
Z8 a lone high surrogate accepted	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'              if (substr(s, pos + 2, 2) != \"\\\\u\") return 0\n'	''
A1 object depth limit off by one (fixer-authored; re-anchored round 10)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'          if (nw > MAXW) exit 3\n          note_type("object")'	'          if (nw > MAXW + 1) exit 3\n          note_type("object")'
A2 duplicate-key check keyed on depth, not the object (fixer-authored; false refusal)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'if ((oid[d], STR) in seen) exit 3\n          seen[oid[d], STR] = 1'	'if ((d, STR) in seen) exit 3\n          seen[d, STR] = 1'
A3 counter range off by one (fixer-authored)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'    if value > INT64_MAX:\n        raise RecordRejected'	'    if value >= INT64_MAX:\n        raise RecordRejected'
A4 total range off by one (fixer-authored)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'        if it + ot + crt + cct > INT64_MAX:'	'        if it + ot + crt + cct >= INT64_MAX:'
R8-RV3 hexval does not fold case (reviewer RV3)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'tolower(substr(h, i, 1))'	'substr(h, i, 1)'
R8-RV7 dispatch session wins over the record's own sessionId (reviewer RV7)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'        session_id = _text(rec.get("sessionId")) or attribution["session_id"]'	'        session_id = attribution["session_id"] or _text(rec.get("sessionId"))'
R8-RV10 filling overwrites a non-NULL item_id / session_id (reviewer RV10)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'            if identity[col] is None and row[col] is not None:'	'            if row[col] is not None:'
R8-RV6 symlinked subagent transcript classified by its target only (reviewer RV6)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'or _is_subagent_transcript(real) or sub_given'	'or _is_subagent_transcript(real)'
R8-F1a sidecar ignored	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'                desc = _read_sidecar_description(sidecar)'	'                desc = None'
R8-F1b foreground dispatch not counted	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'DISPATCH_STATS["dispatch_without_description"] += 1'	'pass'
R8-F1c unattributed agents not counted	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'DISPATCH_STATS["agents_without_item"] += 1'	'pass'
R8-F1d unreadable sidecar not counted	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'except (OSError, ValueError, RecursionError):\n        DISPATCH_STATS["bad_sidecars"] += 1'	'except (OSError, ValueError, RecursionError):\n        pass'
R8-F1e non-object sidecar not counted	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'if not isinstance(doc, dict):\n        DISPATCH_STATS["bad_sidecars"] += 1'	'if not isinstance(doc, dict):\n        pass'
R8-F1f sidecar-only items not counted	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'DISPATCH_STATS["item_from_sidecar"] += 1'	'pass'
R8-F1g sidecar read from any file not just subagent transcripts	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'if not (m_file and _is_subagent_transcript(named)):'	'if not m_file:'
R8-F7a a replayed dispatch record is a second dispatch	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'if (agent_id, rec_uuid) in seen_dispatch_records:'	'if False:'
R8-F7b replayed lines never recognised	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'    return first != row["source_file"]'	'    return False'
R8-F7c every repeated uuid is a replay, in the same file too	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'    return first != row["source_file"]'	'    return True'
R8-F8a symlinked subdirectories not followed	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'os.walk(path, followlinks=True)'	'os.walk(path)'
R8-F8b no visited-directory guard (link cycles)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'            if real_root in visited:'	'            if False:'
R9-T1a stamp accepts item=?? as one id (reviewer RV-F)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'|\\\\?)([^[:alnum:]_]|\\$)"'	'|\\\\?+)([^[:alnum:]_]|\\$)"'
R9-T1b ingest accepts item=?? as one id (RV-F, ingest side)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'(%s|\\?)(?![A-Za-z0-9_])"'	'(%s|\\?+)(?![A-Za-z0-9_])"'
R9-T2a stamp pads a short prefix with Z (reviewer RV-G)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'letters="${letters}X"'	'letters="${letters}Z"'
R9-T2b ingest pads a short prefix with Z (RV-G, ingest side)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'return letters.ljust(3, "X")'	'return letters.ljust(3, "Z")'
R9-T3 sidecar read capped at 256 bytes (reviewer RV-M)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'_SIDECAR_MAX_BYTES = 1 << 20'	'_SIDECAR_MAX_BYTES = 256'
R9-T4 surrogate pair decoded with *1000 (reviewer RV-C)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'cp = 65536 + (cp - 55296) * 1024 + (lo - 56320); pos += 6'	'cp = 65536 + (cp - 55296) * 1000 + (lo - 56320); pos += 6'
R9-S1a reached-by path ignored in the dispatch pass	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'        named = _SUBAGENT_REACHED_BY.get(filepath, filepath)'	'        named = filepath'
R9-S1b reached-by path never recorded	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'            _SUBAGENT_REACHED_BY[real] = given'	'            pass'
R9-S1c sidecar looked up beside the resolved file only	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'for sidecar_dir in dict.fromkeys((os.path.dirname(filepath), os.path.dirname(named))):'	'for sidecar_dir in (os.path.dirname(filepath),):'
R9-S1d unmapped agents never counted	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'                _UNMAPPED_AGENTS.add(agent_id)'	'                pass'
R9-S4a zeroed-copy identity takeover disabled	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'and _usage_total(stored) == 0 and _usage_total(row) > 0):'	'and False):'
R9-S4b takeover whenever the other file carries usage	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'and _usage_total(stored) == 0 and _usage_total(row) > 0):'	'and _usage_total(row) > 0):'
R9-S4c takeover also from the same file	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'        if (row["source_file"] != stored["source_file"]\n'	'        if (True\n'
R9-N1a the dispatch pass warns again (every warning twice)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'iter_records(filepath, warn=False)'	'iter_records(filepath)'
R9-S2a a non-string tool_name is allowed again	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'if [[ "$PARSE_OK" -eq 1 && -n "$TOOL_NAME_TYPE" && "$TOOL_NAME_TYPE" != "string" ]]; then'	'if false; then'
R9-S2b an absent tool_name is refused (false refusal)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'&& -n "$TOOL_NAME_TYPE" && "$TOOL_NAME_TYPE" != "string" ]]'	'&& "$TOOL_NAME_TYPE" != "string" ]]'
R9-S2c jq type query always answers string	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'(.[$k] | type)'	'"string"'
R9-S2d awk type query answers the value instead	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'      if (typeq != "") printf "%s", vtype\n'	'      if (0) printf "%s", vtype\n'
R9-S3 quadratic escape decoding restored	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'            ch = utf8(cp)\n            out = out ch'	'            out = out utf8(cp)'
R9-P2a awk capability probe disabled	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'  if ! printf \'a\\0b\\0\' | awk "$_AWK_PROBE" >/dev/null 2>&1; then'	'  if false; then'
R9-P2b awk probe does not require RT	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'n == 2 && RT == "\\0" && '	'n == 2 && '
R9-P2c awk probe does not require a single-byte %c	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	' && sprintf("%c", 233) == "\\351"'	''
R10-MA utf8() 4-byte lead byte 241 instead of 240 (reviewer MA)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'return sprintf("%c%c%c%c", 240 + int(cp / 262144)'	'return sprintf("%c%c%c%c", 241 + int(cp / 262144)'
R10-MD sidecar read capped at 600 bytes (reviewer MD)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'_SIDECAR_MAX_BYTES = 1 << 20'	'_SIDECAR_MAX_BYTES = 600'
R10-MG ingest pads a short prefix with Z (reviewer MG)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'return letters.ljust(3, "X")'	'return letters.ljust(3, "Z")'
R10-MG2 stamp pads a short prefix with Z (reviewer MG2)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'letters="${letters}X"'	'letters="${letters}Z"'
R10-F8a an object holding a container charged one level, as before round 10 (F8)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'(typ[d] == "o" ? 2 : 1)'	'(typ[d] == "o" ? 1 : 1)'
R10-F8b array depth limit off by one (F8)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'          if (nw > MAXW) exit 3\n          note_type("array")'	'          if (nw > MAXW + 1) exit 3\n          note_type("array")'
R10-F9a extra prefixes glob-expanded again (F9)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'    set -f\n'	'    :\n'
R10-F9b invalid configured pattern: no fallback to the derived prefix (F9)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'if [ "$?" -eq 2 ]; then'	'if false; then'
R10-F9c invalid configured pattern: the GUARD-mode notice is silent (F9)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'[ -n "$FC_RE_NOTICE" ] && echo "$FC_RE_NOTICE" >&2'	':'
R11-1a stamp: any extra-prefix token is used as a regex fragment again (RV11-1)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	"''|*[!A-Z0-9]*) FC_PREFIX_IGNORED="	"'#never#') FC_PREFIX_IGNORED="
R11-1b ingest: any extra-prefix token is used as a regex fragment again (RV11-1)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'if _PREFIX_TOKEN_RE.fullmatch(candidate):'	'if True:'
R11-1c stamp: the ignored-token notice is silent (RV11-1)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'[ -n "$FC_PREFIX_IGNORED" ] && echo "$FC_PREFIX_IGNORED" >&2'	':'
R11-1d ingest: the ignored-token warning is silent (RV11-1)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'        if ignored:\n            print('	'        if False:\n            print('
R11-1e ingest: a token may carry any ASCII character (RV11-1)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'_PREFIX_TOKEN_RE = re.compile(r"[A-Z0-9]+", re.ASCII)'	'_PREFIX_TOKEN_RE = re.compile(r"[ -~]+", re.ASCII)'
R11-2a no clean re-execution: the caller's environment is kept (RV11-2)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'exec -c "$BASH" "$0" --fc-clean-env'	'exec "$BASH" "$0" --fc-clean-env'
R11-2b jq loads the real ~/.jq again (RV11-2)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'_FC_JQ_HOME=/dev/null/fc-no-home'	'_FC_JQ_HOME="$HOME"'
R11-2c a failed re-execution allows the dispatch (fail open)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'exit 2 # FAIL CLOSED: no clean re-execution'	'exit 0 # FAIL CLOSED: no clean re-execution'
R11-2d ingest runs release_prefix.sh with the caller's whole environment (RV11-2)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'env=_clean_subprocess_env(),'	'env=dict(os.environ, LC_ALL="C"),'
R11-2e the allowlist loses HELIX_RELEASE_PREFIX (a false narrowing)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'FC_DISPATCH_EXTRA_ITEM_PREFIXES HELIX_RELEASE_PREFIX HELIX_PROJECT_ROOT; do'	'FC_DISPATCH_EXTRA_ITEM_PREFIXES HELIX_PROJECT_ROOT; do'
R11-3a per-value work proportional to the depth again (RV11-3)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'function at_want() { return (WD > 0 && d == WD && pm[d] && seg_ok(d)) }'	'function at_want(   j, r) { r = 1; for (j = 1; j <= d; j++) if (j > WD || !seg_ok(j)) r = 0; return (WD > 0 && d == WD && r) }'
R11-3b an object opened anywhere counts as on the wanted path (RV11-3)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'typ[d] = "o"; key[d] = ""; oid[d] = ++nobj; pm[d] = npm;'	'typ[d] = "o"; key[d] = ""; oid[d] = ++nobj; pm[d] = 1;'
R11-3c the payload is read line by line and the line feeds are dropped	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'BEGIN { RS = "\\0" }\n    { buf = buf $0 }'	'BEGIN { RS = "\\n" }\n    { buf = buf $0 }'
R11-4a the names a directory is reached by are not recorded (RV11-4)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'                names_here[base] = root\n'	'                pass\n'
R11-4b the last reached-by path wins, not the smallest (RV11-4)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'if real not in _SUBAGENT_REACHED_BY or given < _SUBAGENT_REACHED_BY[real]:'	'if True:'
R11-4c a skipped directory loses its files under the other names (RV11-4)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'            for root in reached_as[real_root].values():'	'            for root in list(reached_as[real_root].values())[:1]:'
R11-6a sidecar read stops at the cap again (truncated read, RV11-6)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'data = fh.read(_SIDECAR_MAX_BYTES + 1)'	'data = fh.read(_SIDECAR_MAX_BYTES)'
R11-6b an oversized sidecar is parsed anyway (RV11-6)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'doc = None if len(data) > _SIDECAR_MAX_BYTES else'	'doc = None if False else'
R11-V1 CR is no longer JSON whitespace (reviewer V1)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'index(" \\t\\r\\n", substr(s, pos, 1))'	'index(" \\t\\n", substr(s, pos, 1))'
R11-V11 an all-zero copy takes the place of a row with no usage (reviewer V11)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'and _usage_total(stored) == 0 and _usage_total(row) > 0):'	'and _usage_total(stored) == 0 and _usage_total(row) >= 0):'
R11-V12 the sidecar beside the link is read before the one beside the resolved file (reviewer V12)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'for sidecar_dir in dict.fromkeys((os.path.dirname(filepath), os.path.dirname(named))):'	'for sidecar_dir in dict.fromkeys((os.path.dirname(named), os.path.dirname(filepath))):'
EOF

cat > "$WORK/apply.py" <<'PYEOF'
import ast, sys
path, old_lit, new_lit = sys.argv[1], sys.argv[2], sys.argv[3]
old, new = ast.literal_eval(old_lit), ast.literal_eval(new_lit)
src = open(path, encoding="utf-8").read()
n = src.count(old)
if n != 1:
    sys.stderr.write("anchor found %d times (want 1)\n" % n)
    sys.exit(2)
open(path, "w", encoding="utf-8").write(src.replace(old, new, 1))
PYEOF

TOTAL=0; KILLED=0; SURVIVED=0; SETUP_FAILED=0; RESTORE_BAD=0
echo
echo "=== mutants ==="
while IFS=$'\t' read -r mid mfile mold mnew; do
  [ -z "$mid" ] && continue
  # R6_ONLY (round 9): an extended regex on the mutant id; when set, only the
  # matching mutants run and the result is labelled a SUBSET run.
  if [ -n "${R6_ONLY:-}" ] && ! printf '%s' "$mid" | grep -Eq -- "$R6_ONLY"; then
    continue
  fi
  TOTAL=$((TOTAL + 1))
  target="$P/$mfile"
  cp "$target" "$WORK/pristine"
  before="$(md5sum < "$target")"
  if ! err="$(python3 "$WORK/apply.py" "$target" "$mold" "$mnew" 2>&1 < /dev/null)"; then
    echo "  FAIL  $mid: mutation could not be applied ($err)"
    SETUP_FAILED=$((SETUP_FAILED + 1))
    continue
  fi
  tag="m$TOTAL"
  line="$(run_suites "$tag")"
  nfail=$?
  cp "$WORK/pristine" "$target"
  if [ "$(md5sum < "$target")" != "$before" ]; then
    echo "  FAIL  $mid: restore of $mfile is not byte-identical"
    RESTORE_BAD=$((RESTORE_BAD + 1))
  fi
  if [ "$nfail" -gt 0 ]; then
    KILLED=$((KILLED + 1))
    echo "  PASS  $mid: KILLED by $nfail suite(s) [$line ]"
  else
    SURVIVED=$((SURVIVED + 1))
    echo "  FAIL  $mid: SURVIVED every suite [$line ]"
  fi
done < "$WORK/mutants.tsv"

echo
echo "  total: mutants=$TOTAL killed=$KILLED survived=$SURVIVED not_applied=$SETUP_FAILED restore_mismatch=$RESTORE_BAD"
if [ -n "${R6_ONLY:-}" ]; then
  echo "  SUBSET RUN (R6_ONLY='$R6_ONLY'): only the mutants whose id matches were run; this is NOT a full-harness result"
fi
if [ "$TOTAL" -eq 0 ] || [ "$SURVIVED" -ne 0 ] || [ "$SETUP_FAILED" -ne 0 ] || [ "$RESTORE_BAD" -ne 0 ]; then
  echo "  RESULT: FAIL"
  exit 1
fi
if [ -n "${R6_ONLY:-}" ]; then
  echo "  RESULT: PASS (SUBSET: all $TOTAL selected mutants killed)"
  exit 0
fi
echo "  RESULT: PASS (all $TOTAL mutants killed)"
exit 0
