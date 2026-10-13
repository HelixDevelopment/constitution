#!/bin/bash
# Purpose: T107 (SpecKit-004 "fast-dev-cycles", User Story 4 / Phase E) RED
#          test for T116's §11.4.272 tool/skill deferral manifest
#          (tasks.md T107: "RED test ... (every deferred capability stays
#          listed and activatable per §11.4.272(B); golden-bad: a deferral
#          making a capability unlistable FAILs)"; plan.md T-E04; SC-005).
#
# T-E04 (plan.md) measures per-turn definition tokens and defers rarely-used
# capabilities "through §11.4.272's prune-to-core mechanism" -- explicitly NO
# NEW MECHANISM. T116 is the IMPLEMENTATION task that writes
# `config/fastcycle/deferral.yaml` and applies it; T107 (this file) is its
# PROTECTING TEST, authored and observed RED before T116 exists.
#
# ============================================================================
# The REAL, ALREADY-BUILT, ALREADY-TESTED mechanism this test reuses
# (constitution 11.4.251/11.4.274 -- reuse, never reimplement).
# ============================================================================
#
# constitution/scripts/skill_activation/{skill_activate.sh,
# skill_activation_lib.sh} IS the "existing prune-to-core mechanism" T-E04's
# own work line names -- it already implements §11.4.272 in full (its own
# 20-case anti-bluff suite, test_skill_activation.sh, is untouched by this
# test): a manifest declares `core:` (always active) and `sources:` (pool
# dirs to search); anything NOT core is on-demand; `list` always shows the
# WHOLE catalogue (clause B discoverability); `activate NAME` hot-loads it
# (clause E); `prune`/`session-init` demote non-core WITHOUT deleting
# anything (clause H). This test does NOT invent a second engine -- it
# drives this REAL one against scratch projects and, separately, reads the
# real live project read-only.
#
# ============================================================================
# This test's OWN choices (constitution 11.4.6 -- fixed here BEFORE T116
# exists, binding on T116 unless T116 records an explicit, evidenced
# deviation; mirrors test_core_ondemand_red.sh's identical practice for
# exactly this situation).
# ============================================================================
#
# (1) SCOPE: T-E04's title is "Tool, skill and MCP definition audit and
#     deferral", but T107's own task line and its cited §11.4.272(B) are
#     SKILL-specific (§11.4.272 governs "Agent Skills, plugins, extensions,
#     tool sets" through the shipped skill-activation engine; there is no
#     comparable "existing prune-to-core mechanism" for MCP server
#     DEFINITIONS in this tree today -- confirmed live below: `.mcp.json`
#     declares one server unconditionally, with no activation/deferral
#     concept anywhere). This test therefore scopes itself to Agent Skills,
#     the ONLY capability class with a real, existing, reusable deferral
#     mechanism -- an MCP/tool-definition deferral mechanism, if T116 adds
#     one, is a SEPARATE, NEW mechanism and therefore explicitly OUT OF
#     PLAN.T-E04'S "no new mechanism" clause and out of this test's scope.
#
# (2) CONTRACT `config/fastcycle/deferral.yaml` MUST satisfy for the real
#     "after" check (Section 4) to go GREEN: a `deferred:` list section,
#     parseable by the SAME tiny dependency-free YAML-subset parser the
#     engine already ships (`sa_parse_manifest`, reused verbatim below --
#     never a second parser), naming skill names that:
#       (a) do NOT appear under `core:` in the resolved project manifest
#           (`.helix/skill-manifest.yaml` if present, else the shipped
#           default) -- proves the deferral was genuinely APPLIED through
#           the manifest's own core/on-demand split, no new verb needed;
#       (b) DO resolve to a real, readable SKILL.md in one of the
#           manifest's `sources:` pool directories -- proves the capability
#           still EXISTS and is find-able, i.e. was demoted, not deleted.
#     The manifest does not exist today (confirmed live below) -- this is
#     the RED baseline the task instruction names explicitly.
#
# (3) ORACLE INDEPENDENCE (constitution 11.4.245 -- the oracle strategy
#     used below is DERIVED, never the tool's own opinion trusted): for
#     every capability this test checks, "should be listed / activatable"
#     is computed FIRST from raw data the tool does not control --
#     (i) the manifest's `core:`/`sources:` sections read via the parser
#     primitive alone (a data-extraction utility, not a decision), and
#     (ii) a direct filesystem existence check of `<source>/<name>/
#     SKILL.md` -- BEFORE the real `skill_activate.sh` CLI is invoked or
#     its real `list`/`activate` output is read. The tool's actual output
#     is then compared AGAINST that independently-derived expectation,
#     never accepted on its own say-so. Section 3's golden-bad case proves
#     this discrimination is real: it constructs a capability that is
#     genuinely UNLISTABLE (present in no pool source at all) and confirms
#     the independent oracle -- and, separately, the real tool's `list`
#     output -- both correctly agree it violates §11.4.272(B), rather than
#     this test's own check being decoration that always reports PASS.
#
# (4) SAFETY: `activate`/`prune`/`session-init` MUTATE `.claude/skills` and
#     `.claude/.skill-activation` under whatever PROJECT_ROOT they are
#     given. This is a live, multi-track, concurrently-committed checkout
#     (constitution 11.4.176/11.4.187) -- Section 3 (sandbox
#     self-validation) invokes those MUTATING commands ONLY against a
#     throwaway `$TMP` scratch project. Section 4 (the real "after" check
#     against THIS project's live root) is READ-ONLY: it invokes only
#     `list` (which the engine's own source never writes anything from,
#     confirmed by inspection below) plus direct file reads -- it NEVER
#     calls `activate`/`prune`/`session-init` against the real ROOT.
#
# ============================================================================
# Usage: bash test_tool_deferral_red.sh   Exit 0 = every check below held
#        (only possible once T116 has landed config/fastcycle/deferral.yaml
#        AND applied it through the manifest's core/sources split); nonzero
#        = FAIL count>0 (today, RED, by design).
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
FC="$(cd "$HERE/.." && pwd)"
ROOT="$(cd "$FC/../../.." && pwd)"
SA_DIR="$ROOT/constitution/scripts/skill_activation"

TMP="$(mktemp -d)" || { echo "cannot create temp dir (TMPDIR unusable)" >&2; exit 2; }
reap_children() { pkill -KILL -f "$TMP" 2>/dev/null; return 0; }
trap 'reap_children; rm -rf "$TMP"' EXIT
trap 'reap_children; rm -rf "$TMP"; exit 130' INT
trap 'reap_children; rm -rf "$TMP"; exit 143' TERM

FAIL=0; N=0
chk() { N=$((N+1)); if [ "$2" = "1" ]; then echo "PASS[$N]: $1"; else echo "FAIL[$N]: $1"; FAIL=$((FAIL+1)); fi; }
info() { echo "INFO: $1"; }

if ! command -v python3 >/dev/null 2>&1; then
  echo "FAIL: python3 not on PATH -- cannot run any of the checks below"
  echo "SUMMARY pass=0 fail=1 total=1"
  exit 1
fi

# -----------------------------------------------------------------------
# constitution 11.4.273 control-needle discipline (needle set #1: this
# test's own file-existence-check mechanism, generic self-check before
# trusting it against real files/dirs below).
# -----------------------------------------------------------------------
NEEDLE_PRESENT="$TMP/.needle_present_marker"
printf 'x\n' > "$NEEDLE_PRESENT"
chk "control needle #1a: a known-present, non-empty file IS found by the existence+non-empty check" \
  "$([ -s "$NEEDLE_PRESENT" ] && echo 1 || echo 0)"
NEEDLE_FABRICATED="$TMP/.needle_fabricated_never_created_$$_$(date +%s 2>/dev/null || echo x)"
chk "control needle #1b: a fabricated (never-created) path IS reported absent" \
  "$([ ! -e "$NEEDLE_FABRICATED" ] && echo 1 || echo 0)"
rm -f "$NEEDLE_PRESENT"

# =========================================================================
# Section 1: TODAY's real-file RED baseline -- config/fastcycle/
# deferral.yaml does not exist yet (T116 has not landed).
# =========================================================================
echo
echo "=== Section 1: config/fastcycle/deferral.yaml RED baseline (live) ==="
DEFERRAL_FILE="$ROOT/config/fastcycle/deferral.yaml"
if [ -e "$DEFERRAL_FILE" ]; then
  info "config/fastcycle/deferral.yaml FOUND -- T116 appears to have landed; Section 4 attempts the real after-check"
else
  info "config/fastcycle/deferral.yaml NOT FOUND at $DEFERRAL_FILE -- T116 has not landed; this is the EXPECTED RED-today outcome"
fi
chk "T116 has landed config/fastcycle/deferral.yaml naming §11.4.272 deferral candidates -- expected to FAIL today (RED), documented honestly per T107's own scope note (2)" \
  "$([ -e "$DEFERRAL_FILE" ] && echo 1 || echo 0)"

# =========================================================================
# Section 2: the existing, already-tested prune-to-core mechanism is
# present and reusable (constitution 11.4.251/11.4.274 reuse precondition
# -- confirmed by presence + syntax, never re-executed wholesale here; its
# own 20-case suite already anti-bluff-proves its behaviour).
# =========================================================================
echo
echo "=== Section 2: existing skill-activation engine presence (reuse precondition) ==="
CLI="$SA_DIR/skill_activate.sh"
LIB="$SA_DIR/skill_activation_lib.sh"
DEFAULT_MANIFEST="$SA_DIR/skill-manifest.default.yaml"
ENGINE_TEST="$SA_DIR/test_skill_activation.sh"

ENGINE_OK=1
for f in "$CLI" "$LIB" "$DEFAULT_MANIFEST" "$ENGINE_TEST"; do
  [ -r "$f" ] || { echo "FAIL: required engine artefact not found/readable: $f"; ENGINE_OK=0; }
done
chk "the existing skill-activation engine (skill_activate.sh + skill_activation_lib.sh + shipped default manifest + its own anti-bluff suite) is present and readable" \
  "$ENGINE_OK"

if [ "$ENGINE_OK" = "1" ]; then
  bash -n "$CLI" 2>"$TMP/syn_err_cli.$$" ; CLI_SYN=$?
  bash -n "$LIB" 2>"$TMP/syn_err_lib.$$" ; LIB_SYN=$?
  chk "skill_activate.sh + skill_activation_lib.sh parse clean (bash -n)" \
    "$([ "$CLI_SYN" = "0" ] && [ "$LIB_SYN" = "0" ] && echo 1 || echo 0)"
  ACTIVATE_IMPL="$(grep -c '^  activate)' "$CLI" 2>/dev/null || echo 0)"
  LIST_IMPL="$(grep -c '^  list)' "$CLI" 2>/dev/null || echo 0)"
  PRUNE_IMPL="$(grep -c '^  prune)' "$CLI" 2>/dev/null || echo 0)"
  chk "the CLI implements activate/list/prune (the three verbs T116 needs -- no new subcommand required)" \
    "$([ "$ACTIVATE_IMPL" -ge 1 ] && [ "$LIST_IMPL" -ge 1 ] && [ "$PRUNE_IMPL" -ge 1 ] && echo 1 || echo 0)"
fi

# scope note (1) live confirmation: no comparable MCP-server deferral
# mechanism exists -- .mcp.json declares its one server unconditionally,
# with no activation/manifest concept anywhere in this tree.
MCP_FILE="$ROOT/.mcp.json"
MCP_DEFERRAL_HITS="$(grep -rl 'mcp.*deferr\|deferr.*mcp' "$ROOT/constitution/scripts" 2>/dev/null | wc -l | tr -d ' ')"
info "scope note (1): $MCP_FILE exists=$([ -e "$MCP_FILE" ] && echo yes || echo no); MCP-deferral-mechanism hits under constitution/scripts=$MCP_DEFERRAL_HITS (0 confirms no existing MCP deferral mechanism -- out of this test's scope per note (1))"

# =========================================================================
# Section 3: self-contained sandbox self-validation of THIS TEST's own
# checking logic (constitution 11.4.107(10)/11.4.201(1)) -- entirely
# synthetic, drives the REAL skill_activate.sh CLI against throwaway
# scratch projects (never the live ROOT). Proves the §11.4.272(B)
# discoverability+activatability check discriminates BEFORE trusting it
# against T116's real future work.
# =========================================================================
echo
echo "=== Section 3: sandbox self-validation (golden / golden-bad / negative-control) ==="

if [ "$ENGINE_OK" != "1" ]; then
  info "engine artefacts missing -- Section 3 skipped (dependent on Section 2)"
else
  # -- independent oracle (constitution 11.4.245): derives "should be
  #    listed / activatable" from raw manifest + pool-source data ONLY,
  #    BEFORE the real CLI is invoked or its output read. Reuses the
  #    engine's own tiny YAML-subset parser as a data-extraction
  #    primitive (constitution 11.4.251 -- reuse, never a second parser),
  #    never as a decision oracle.
  oracle_expect() {
    # $1 = scratch project root   $2 = manifest path   $3 = skill name
    # Prints: LISTED_ONDEMAND | LISTED_CORE | UNLISTABLE
    local proj="$1" mf="$2" name="$3" src
    # shellcheck disable=SC1090
    ( set -uo pipefail; . "$LIB"
      if sa_is_core "$proj" "$name"; then echo LISTED_CORE; exit 0; fi
      while IFS= read -r src; do
        [ -f "$src/$name/SKILL.md" ] && { echo LISTED_ONDEMAND; exit 0; }
      done < <(sa_parse_manifest "$mf" sources | while IFS= read -r d; do
                 d="${d/#\~/$HOME}"; case "$d" in /*) : ;; *) d="$proj/$d" ;; esac; echo "$d"
               done)
      echo UNLISTABLE
    )
  }

  # -- structural (not substring) parse of the real `list` output into
  #    {name -> section} (constitution 11.4.201(7)(a): structure, not
  #    substring -- avoids the exact "-w matches inside a longer
  #    hyphenated name" class of false match this project's own record
  #    documents, constitution 11.4.273 instance #5).
  parse_list_output() {
    python3 - "$@" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
section = None
found = {}
pat = re.compile(r'^\s*\[([*! ])\]\s+(\S+)')
for line in text.splitlines():
    if line.startswith('## core'):
        section = 'core'; continue
    if line.startswith('## on-demand'):
        section = 'ondemand'; continue
    m = pat.match(line)
    if m and section:
        found[m.group(2)] = (section, m.group(1))
name = sys.argv[2]
if name in found:
    print(found[name][0] + ':' + found[name][1])
else:
    print('ABSENT')
PY
  }

  mk_skill() { mkdir -p "$1/$2"; printf -- '---\nname: %s\ndescription: sandbox skill for T107\n---\nbody\n' "$2" > "$1/$2/SKILL.md"; }

  # --- GOLDEN: a deferred (non-core) skill whose SKILL.md is genuinely
  #     present in a pool source stays listed on-demand AND activatable.
  P1="$TMP/proj_golden"
  mkdir -p "$P1/.helix/skills" "$P1/.claude"
  mk_skill "$P1/.helix/skills" "core-one"
  mk_skill "$P1/.helix/skills" "deferred-legit"
  cat > "$P1/.helix/skill-manifest.yaml" <<'M1'
schema_version: 1
core:
  - core-one
sources:
  - .helix/skills
M1
  ORACLE1="$(oracle_expect "$P1" "$P1/.helix/skill-manifest.yaml" "deferred-legit")"
  chk "GOLDEN oracle: 'deferred-legit' (non-core, present in pool source) independently derives to LISTED_ONDEMAND before the real CLI runs" \
    "$([ "$ORACLE1" = "LISTED_ONDEMAND" ] && echo 1 || echo 0)"

  LISTOUT1="$("$CLI" list "$P1" 2>/dev/null)"
  printf '%s\n' "$LISTOUT1" > "$TMP/listout1.txt"
  REAL1="$(parse_list_output "$TMP/listout1.txt" "deferred-legit")"
  chk "GOLDEN: the real 'list' output places 'deferred-legit' in the on-demand section (§11.4.272(B) discoverability -- matches the independent oracle)" \
    "$(echo "$REAL1" | grep -q '^ondemand:' && echo 1 || echo 0)"

  "$CLI" activate deferred-legit "$P1" >/dev/null 2>&1
  chk "GOLDEN: 'activate deferred-legit' produces a real, independently-readable SKILL.md at the active path (§11.4.272(B) activatability -- checked on the filesystem, not the CLI's own exit code)" \
    "$([ -r "$P1/.claude/skills/deferred-legit/SKILL.md" ] && echo 1 || echo 0)"

  # --- GOLDEN-BAD: a deferral entry whose skill exists in NO pool
  #     source (a broken deferral -- the exact class T107's task text
  #     names: "a deferral making a capability unlistable"). This test's
  #     own check MUST correctly flag it as a §11.4.272(B) violation,
  #     never silently pass it.
  P2="$TMP/proj_golden_bad"
  mkdir -p "$P2/.helix/skills" "$P2/.claude"
  mk_skill "$P2/.helix/skills" "core-two"
  # "deferred-broken" is named in intent (mirrors the deferral list a
  # broken T116 change might emit) but its SKILL.md is never created --
  # simulates a deferral entry that removed the capability from every
  # pool source instead of merely un-declaring it core.
  cat > "$P2/.helix/skill-manifest.yaml" <<'M2'
schema_version: 1
core:
  - core-two
sources:
  - .helix/skills
M2
  ORACLE2="$(oracle_expect "$P2" "$P2/.helix/skill-manifest.yaml" "deferred-broken")"
  chk "GOLDEN-BAD oracle: 'deferred-broken' (named but present in NO pool source) independently derives to UNLISTABLE -- this test's checking logic correctly flags a §11.4.272(B) violation, proving it is not decoration" \
    "$([ "$ORACLE2" = "UNLISTABLE" ] && echo 1 || echo 0)"

  LISTOUT2="$("$CLI" list "$P2" 2>/dev/null)"
  printf '%s\n' "$LISTOUT2" > "$TMP/listout2.txt"
  REAL2="$(parse_list_output "$TMP/listout2.txt" "deferred-broken")"
  chk "GOLDEN-BAD: the real 'list' output ALSO agrees 'deferred-broken' is ABSENT (never found in either section) -- the independent oracle and the real tool concur on the violation, so this is a genuine discrimination not a fixture artefact" \
    "$([ "$REAL2" = "ABSENT" ] && echo 1 || echo 0)"

  ACT2_RC=0
  "$CLI" activate deferred-broken "$P2" >"$TMP/act2.out" 2>&1 || ACT2_RC=$?
  chk "GOLDEN-BAD: 'activate deferred-broken' correctly fails (non-zero, no dangling link) rather than silently claiming success on an unlistable capability (§11.4.201 fail-safe-never-silent)" \
    "$([ "$ACT2_RC" != "0" ] && [ ! -e "$P2/.claude/skills/deferred-broken" ] && echo 1 || echo 0)"

  # --- NEGATIVE CONTROL: a capability declared core stays listed under
  #     `core`, not `ondemand` -- proves the checking logic distinguishes
  #     "core" from "deferred-and-still-findable", not merely
  #     "found somewhere".
  ORACLE3="$(oracle_expect "$P1" "$P1/.helix/skill-manifest.yaml" "core-one")"
  chk "negative control: a genuinely CORE capability ('core-one') independently derives to LISTED_CORE, not LISTED_ONDEMAND -- the oracle distinguishes core from deferred, never conflating the two" \
    "$([ "$ORACLE3" = "LISTED_CORE" ] && echo 1 || echo 0)"
  REAL3="$(parse_list_output "$TMP/listout1.txt" "core-one")"
  chk "negative control: the real 'list' output ALSO places 'core-one' in the core section" \
    "$(echo "$REAL3" | grep -q '^core:' && echo 1 || echo 0)"
fi

# =========================================================================
# Section 4: the REAL "after" comparison -- T116's own contract (2). This
# section is READ-ONLY against the live ROOT: only `list` (never
# `activate`/`prune`/`session-init`) is invoked, per safety note (4).
# =========================================================================
echo
echo "=== Section 4: real config/fastcycle/deferral.yaml after-check (live, read-only) ==="

if [ ! -e "$DEFERRAL_FILE" ]; then
  info "config/fastcycle/deferral.yaml still absent -- no deferral to check yet; this is the EXPECTED RED-today outcome (T107's task text: 'this is the RED I write to protect T116')"
  chk "every capability named in config/fastcycle/deferral.yaml stays listed and activatable per §11.4.272(B) (real, live check against this project's own manifest) -- expected to FAIL today (RED), no deferral.yaml exists yet" \
    "0"
elif [ "$ENGINE_OK" != "1" ]; then
  chk "the real after-check can run against the existing engine" "0"
else
  DEFERRED_NAMES="$(
    # shellcheck disable=SC1090
    ( . "$LIB"; sa_parse_manifest "$DEFERRAL_FILE" deferred )
  )"
  if [ -z "$DEFERRED_NAMES" ]; then
    info "config/fastcycle/deferral.yaml exists but its 'deferred:' section is empty or unparseable -- nothing to check yet"
    chk "config/fastcycle/deferral.yaml names at least one deferred capability" "0"
  else
    if [ -r "$ROOT/.helix/skill-manifest.yaml" ]; then
      REAL_MANIFEST="$ROOT/.helix/skill-manifest.yaml"
    else
      REAL_MANIFEST="$DEFAULT_MANIFEST"
    fi
    info "resolved live manifest: $REAL_MANIFEST"
    REAL_LISTOUT="$("$CLI" list "$ROOT" 2>/dev/null)"
    printf '%s\n' "$REAL_LISTOUT" > "$TMP/real_listout.txt"

    ALL_OK=1
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      oracle="$(oracle_expect "$ROOT" "$REAL_MANIFEST" "$name")"
      real="$(parse_list_output "$TMP/real_listout.txt" "$name")"
      if [ "$oracle" = "LISTED_ONDEMAND" ] && echo "$real" | grep -q '^ondemand:'; then
        info "OK: '$name' is genuinely deferred (not core) and still listed on-demand (§11.4.272(B) satisfied)"
      elif [ "$oracle" = "LISTED_CORE" ]; then
        info "VIOLATION: '$name' is named in deferral.yaml but is STILL declared core -- the deferral was never applied through the manifest"
        ALL_OK=0
      else
        info "VIOLATION: '$name' is named in deferral.yaml but resolves to UNLISTABLE (oracle=$oracle, real list=$real) -- §11.4.272(B) violated: the deferral made this capability unfindable"
        ALL_OK=0
      fi
    done <<< "$DEFERRED_NAMES"
    chk "every capability named in config/fastcycle/deferral.yaml stays listed and activatable per §11.4.272(B) (real, live check against this project's own manifest)" \
      "$ALL_OK"
  fi
fi

echo
echo "SUMMARY pass=$((N - FAIL)) fail=$FAIL total=$N"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
