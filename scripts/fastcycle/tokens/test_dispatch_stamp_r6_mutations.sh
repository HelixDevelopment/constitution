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
# Runtime: about 60 mutants x 5 suites, roughly 25 minutes. Run it in the
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
M3 accept item=? as an item id	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'if m and m.group(1) != "?":'	'if m:'
M4 disable subagents/ discovery	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'        if os.path.isdir(subagents_dir):'	'        if False:'
M8 parent turns item-attributed	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'        agent_id = None\n        item_id = None  #'	'        agent_id = None\n        item_id = next((v["item_id"] for v in dispatch_map.values() if v["item_id"]), None)  #'
M9 partial usage gets a total	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'    if not absent:\n        return MEASURED, None, it + ot + crt + cct\n'	'    if not absent:\n        return MEASURED, None, it + ot + crt + cct\n    if it is not None and ot is not None:\n        return MEASURED, None, it + ot\n'
F5 partial usage labelled measured	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'    return (UNMEASURED,\n'	'    return (MEASURED,\n'
M10 missing_instrument loses the file path	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'% (ref, filepath, what),'	'% (ref, "", what),'
M11 ignore extra prefixes (ingest)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'for tok in re.split(r"[,| \\t\\n]+", extra):'	'for tok in []:'
M12 ignore the full override (ingest)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'    if override:\n        value_re = override'	'    if False:\n        value_re = override'
M13 no upper-case on extra prefixes (ingest)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'prefixes.append(_ascii_upper(tok))'	'prefixes.append(tok)'
F2 strict decode on invalid UTF-8	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'errors="replace")'	'errors="strict")'
D1 guard always allows	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'FOUND="$(extract_item "$DESCRIPTION")"\nif [[ -n "$FOUND" ]]; then'	'FOUND="$(extract_item "$DESCRIPTION")"\nif true; then'
D2 left boundary (^|.)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'ITEM_RE="(^|[[:space:]])item='	'ITEM_RE="(^|.)item='
RB drop the right tag boundary (stamp)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'([^[:alnum:]_]|\\$)"'	'"'
D3 release_prefix resolved via cwd git toplevel	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'rp_script="$(cd "$self_dir/../.." 2>/dev/null && pwd 2>/dev/null || true)/release_prefix.sh"'	'rp_script="$(git rev-parse --show-toplevel 2>/dev/null)/scripts/release_prefix.sh"'
DS-M3 ignore extra prefixes (stamp)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'[ -n "$_fc_p_upper" ] && ITEM_ALL_PREFIXES='	'[ -n "" ] && ITEM_ALL_PREFIXES='
DS no upper-case on extra prefixes (stamp)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'_fc_p_upper="$(printf \'%s\' "$_fc_p" | tr \'[:lower:]\' \'[:upper:]\')"'	'_fc_p_upper="$_fc_p"'
DS-M5 fall back to .prompt instead of .subagent	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'DESCRIPTION="$(json_field .tool_input.subagent)"'	'DESCRIPTION="$(json_field .tool_input.prompt)"'
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
L5 ingest extra prefix upper-cased with str.upper (V1-M2)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'prefixes.append(_ascii_upper(tok))'	'prefixes.append(tok.upper())'
L6 jq-less reader takes the key at any depth (V1-M4a)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'if (cur_path() == want) val = STR'	'if (key[d] == substr(want, index(want, ".") + 1) || key[d] == want) val = STR'
L7 guard fails open on an unparseable payload (V1-M4a)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'if [[ "$PARSE_OK" -eq 0 ]]; then'	'if false; then'
L8 jq parse error treated as an empty field (V1-M4a)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'[ "$rc" -eq 0 ] || return 3'	'[ "$rc" -eq 0 ] || return 0'
L9 prefix fallback silent in GUARD mode (V1-M3)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'[ -n "$FC_PREFIX_NOTICE" ] && echo "$FC_PREFIX_NOTICE" >&2'	':'
L10 refusal example hardcodes ATM (V1-M3)	constitution/scripts/fastcycle/tokens/dispatch_stamp.sh	'ITEM_EXAMPLE="item=${FC_DEFAULT_PREFIX}-1041"'	'ITEM_EXAMPLE="item=ATM-1041"'
L11 summary keeps a row first status (V1-M1)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'final_status[row["row_hash"]] = status'	'final_status.setdefault(row["row_hash"], status)'
L12 non-string identity fields reach the SQL binding (class: abort loses the run)	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'    if value is None or isinstance(value, str):\n        return value\n    READ_STATS'	'    if True:\n        return value\n    READ_STATS'
L13 a JSON true counts as 1 token	constitution/scripts/fastcycle/tokens/transcript_ingest.py	'    if isinstance(value, bool) or not isinstance(value, int):'	'    if not isinstance(value, int):'
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
if [ "$TOTAL" -eq 0 ] || [ "$SURVIVED" -ne 0 ] || [ "$SETUP_FAILED" -ne 0 ] || [ "$RESTORE_BAD" -ne 0 ]; then
  echo "  RESULT: FAIL"
  exit 1
fi
echo "  RESULT: PASS (all $TOTAL mutants killed)"
exit 0
