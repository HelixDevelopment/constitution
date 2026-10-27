#!/usr/bin/env bash
# lib_decide.sh — ONE definition of "which llmctl decision infrastructure counts as usable", shared by the detection
# bootstrap (scripts/jev/bootstrap.sh) and the detection gate (scripts/gates/cm_jev_detection.sh clause 7), so the two
# can never disagree about an empty record (review r2 I-new-2).
#   * a registry service is classified by its PROFILE: labels.profile, else its name;
#   * a profile whose capacity protocol is `jev-verdict` has no driver and is NOT usable decision capacity;
#   * a profile whose protocol is unknown is counted usable (conservative: it may be live).
# Needs jq. Functions print TSV on stdout and nothing else; a parse failure prints nothing and returns 1.

# shellcheck source=lib_keys.sh
declare -F jev_url_host_class >/dev/null 2>&1 || . "$(dirname "${BASH_SOURCE[0]}")/lib_keys.sh"

# jev_decide_services <status-json> <capacity-json>
#   -> one line per HEALTHY registry service with labels.kind == decide:  name TAB profile TAB url TAB protocol
jev_decide_services() {
  jq -nr --argjson st "$1" --argjson cap "${2:-{\}}" '
    def proto($p): (($cap.decision_instances // {})[$p].protocol // "");
    $st.registry.services[]? | select(.healthy == true and (.labels.kind // "") == "decide")
    | (.labels.profile // .name) as $p | [.name, $p, (.url // ""), proto($p)] | @tsv' 2>/dev/null
}

# jev_running_profiles <status-json> <capacity-json>
#   -> one line per profile the scheduler reports running:  profile TAB protocol
jev_running_profiles() {
  jq -nr --argjson st "$1" --argjson cap "${2:-{\}}" '
    def proto($p): (($cap.decision_instances // {})[$p].protocol // "");
    $st.profiles[]? | select(.running == true) | [.profile, proto(.profile)] | @tsv' 2>/dev/null
}

# jev_usable_live <status-json> <capacity-json> -> comma list "profile:X,service:NAME" of usable live infrastructure
jev_usable_live() {
  local out="" n p u proto
  while IFS=$'\t' read -r p proto; do
    [ -n "$p" ] || continue; [ "$proto" = "jev-verdict" ] && continue
    out="${out:+$out,}profile:$p"
  done < <(jev_running_profiles "$1" "${2:-{\}}")
  while IFS=$'\t' read -r n p u proto; do
    [ -n "$n" ] || continue; [ "$proto" = "jev-verdict" ] && continue
    out="${out:+$out,}service:$n"
  done < <(jev_decide_services "$1" "${2:-{\}}")
  printf '%s' "$out"
}

# ---- jev_effective_mode: the ONE decision "may this host enforce" (review r3 I3-1/I3-2/I3-3, r4 I4-1) -------------------
# Bootstrap stage 5, skills/jev-decision-layer/register.sh and jev-status.sh all call THIS function; none keeps its own
# enforce predicate and none has to supply the inputs that matter: the function RESOLVES them itself, so the three callers
# can never disagree and a stored `enforce` is re-derived (and downgraded) on every run.
#   jev_effective_mode <requested-mode> [<extra-base-url>|""] [<detection-json>|""] [<thresholds-json>...]
#   -> prints  MODE TAB REASON   (MODE is shadow or enforce; REASON has no tab/newline and never a secret)
# enforce needs ALL of (any failure -> shadow, with the reason; an input that cannot be resolved is a failure):
#   1. the request is `enforce`;
#   2. the BASE URL resolves (jev_base_verdict: the extra argument, the process JEV_BASE_URL, the env file, the MCP entry,
#      and the ranked cache endpoints[0].base_url) to AT LEAST ONE value and EVERY resolved value is loopback by the
#      anchored parse of jev_url_host_class; an empty / unresolvable base is shadow (fail closed), never "loopback";
#   3. a readable detection record exists, is fresh (generated_at within 604800 s; JEV_NOW_EPOCH and JEV_DETECTION_MAX_AGE are honoured only under JEV_TEST=1) and has
#      at least one QUALIFYING local endpoint: source local-llmctl, id `llmctl-<profile>` with a safe profile name, and a
#      LOOPBACK url (anything else is ignored, so a record whose only local endpoint is `https://evil.example` -> shadow);
#   4. a thresholds file (the caller's, $JEV_CONFIG_DIR, $JEV_EVIDENCE_DIR) has a PROMOTED per-type entry whose numeric
#      threshold is in (0,1];
#   5. every qualifying profile passes `llmctl require-validated <profile>` (exactly one argument, as the pinned CLI requires) under LLMCTL_VALIDATE_STRICT=1 (60 s each).
# Test overrides JEV_DECISION_PROFILES / JEV_REQUIRE_VALIDATED_CMD are honoured ONLY when JEV_TEST=1 and then recorded as
# `test-override(JEV_TEST=1)` in the reason; outside a test they are ignored and recorded as `override-ignored`.
# JEV_SKIP_VALIDATION=1 (jev-status --no-validate) never yields enforce: the result is shadow `validation-skipped`.

# jev_profile_name_ok <name> -> rc 0 when safe as a command argument (letter/digit first, so never an option).
jev_profile_name_ok() { [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; }

# ---- THE path resolver (review r5 I5-2, r6 I6-2) ----------------------------------------------------------------------------
# EVERY directory / file location the Jev layer reads or writes is derived HERE and nowhere else. bootstrap.sh, jev-status.sh,
# jev-calibrate.sh, register.sh and the cm_jev_* gates all call these functions; none keeps its own `${JEV_X:-default}`
# (tests/jev/test_review_fixes_r6.sh scans for a second derivation and fails if one reappears). Results are ABSOLUTE and the
# DEFAULTS never depend on the caller's working directory (r6 I6-2: bootstrap run from a repo wrote ./.jev/jev-detection.json
# while register looked in $HOME/.local/state/jev/evidence). Explicit overrides: a relative JEV_STATE_DIR / JEV_CONFIG_DIR /
# JEV_EVIDENCE_DIR / JEV_DETECTION_FILE / ... value is anchored at the cwd of the CALL (callers that must agree pass absolute
# paths); a relative JEV_HOME is REFUSED when this file is sourced (r7 m7-4), because every default hangs off it.
#   jev_home          $JEV_HOME, else $HOME (the target home an MCP/env registration is written for)
#   jev_state_dir     $JEV_STATE_DIR, else <home>/.local/state/jev
#   jev_config_dir    $JEV_CONFIG_DIR, else <home>/.config/jev
#   jev_evidence_dir  $JEV_EVIDENCE_DIR, else <state>/evidence
#   jev_detection_file  $JEV_DETECTION_FILE (selects the record), else <evidence>/jev-detection.json
#   jev_thresholds_candidates  the thresholds files read, in order: <config>/jev-thresholds.json, <evidence>/jev-thresholds.json
#   jev_decisions_file  <state>/decisions.jsonl (the shadow decision log; independent of the evidence dir)
#   jev_bootstrap_home  $JEV_BOOTSTRAP_HOME, else <home>/.local/share/helix   (managed-clone root)
#   jev_toolkit_dir     $CLAUDE_TOOLKIT_DIR, else <bootstrap-home>/claude_toolkit
#   jev_cma_share_dir   <home>/.local/share/claude-multi-account
#   jev_providers_dir   $CMA_PROVIDERS_DIR, else <cma-share>/providers   (the toolkit endpoint cache dir)
#   jev_aliases_file    $JEV_CALIBRATE_ALIAS_FILE, else <cma-share>/aliases.sh
case "${JEV_HOME:-}" in ""|/*) ;; *) echo "jev: JEV_HOME must be an absolute path (got a relative value); refusing - every default path hangs off it" >&2; exit 2 ;; esac
jev_home() { printf '%s' "${JEV_HOME:-${HOME:-}}"; }
jev_abs() { case "$1" in /*) printf '%s' "$1" ;; ./*) printf '%s/%s' "$PWD" "${1#./}" ;; *) printf '%s/%s' "$PWD" "$1" ;; esac; }
jev_state_dir() { jev_abs "${JEV_STATE_DIR:-$(jev_home)/.local/state/jev}"; }
jev_config_dir() { jev_abs "${JEV_CONFIG_DIR:-$(jev_home)/.config/jev}"; }
jev_evidence_dir() { jev_abs "${JEV_EVIDENCE_DIR:-$(jev_state_dir)/evidence}"; }
jev_detection_file() { jev_abs "${JEV_DETECTION_FILE:-$(jev_evidence_dir)/jev-detection.json}"; }
jev_thresholds_candidates() { printf '%s\n' "$(jev_config_dir)/jev-thresholds.json" "$(jev_evidence_dir)/jev-thresholds.json"; }
jev_decisions_file() { printf '%s/decisions.jsonl' "$(jev_state_dir)"; }
jev_bootstrap_home() { jev_abs "${JEV_BOOTSTRAP_HOME:-$(jev_home)/.local/share/helix}"; }
jev_toolkit_dir() { jev_abs "${CLAUDE_TOOLKIT_DIR:-$(jev_bootstrap_home)/claude_toolkit}"; }
jev_cma_share_dir() { printf '%s/.local/share/claude-multi-account' "$(jev_home)"; }
jev_providers_dir() { jev_abs "${CMA_PROVIDERS_DIR:-$(jev_cma_share_dir)/providers}"; }
# jev_default_cache_file -> the toolkit endpoint cache at the location `claude-providers sync-jev` writes to regardless of
# CMA_PROVIDERS_DIR (live-measured 2026-10-24): always under the real $HOME.
jev_default_cache_file() { printf '%s/.local/share/claude-multi-account/providers/jev-endpoints.json' "${HOME:-}"; }
jev_aliases_file() { jev_abs "${JEV_CALIBRATE_ALIAS_FILE:-$(jev_cma_share_dir)/aliases.sh}"; }

# ---- value whitelists for anything written into an env file / MCP entry (review r6 m6-5) --------------------------------------
# The env file is SOURCED by a shell, so a value must be inert there: `a;cmd` or `http://h/$(id)` must never be written.
# Each field has its own closed character set; a rejected value is refused (rc 1), never quoted-and-hoped.
jev_check_url()   { local re='^https?://[][A-Za-z0-9._:-]+(/[A-Za-z0-9._~/%+-]*)?$'; [[ "${1:-}" =~ $re ]]; }
jev_check_model() { [[ "${1:-}" =~ ^[A-Za-z0-9._:/@+-]+$ ]]; }
jev_check_path()  { [[ "${1:-}" =~ ^[A-Za-z0-9._/~+@%:=,-]+$ ]]; }
jev_check_word()  { [[ "${1:-}" =~ ^[A-Za-z0-9._-]+$ ]]; }

# ---- write helpers (review r6 m6-4, I6-1) -------------------------------------------------------------------------------------
# jev_real_target <file> -> the file a write must land in: a symlink is resolved (readlink -f), so an atomic replace never
# swaps a symlinked ~/.mcp.json / env file for a regular file. A missing file is its own target.
jev_real_target() { local t; t="$(readlink -f -- "$1" 2>/dev/null || true)"; printf '%s' "${t:-$1}"; }
# jev_write_atomic <dest> (content on stdin): same-dir temp + mv onto the RESOLVED target, mode of the old file kept.
jev_write_atomic() {
  local dest tmp mode
  dest="$(jev_real_target "$1")"
  tmp="$(mktemp "$(dirname "$dest")/.jev-tmp.XXXXXX")" || return 1
  if ! cat > "$tmp"; then rm -f -- "$tmp"; return 1; fi
  if [ -e "$dest" ]; then mode="$(stat -c %a -- "$dest" 2>/dev/null || true)"; [ -z "$mode" ] || chmod "$mode" "$tmp" 2>/dev/null || true; fi
  mv -f -- "$tmp" "$dest"
}
# jev_file_has_key_material <file> -> rc 0 when the file holds (or may hold) a credential value. Detection is by SHAPE, in three
# ways (review r7 m7-1; stated exactly in docs/jev/governance-guide.md): (1) JSON: a string value under a key whose name contains
# API_KEY / TOKEN / SECRET / PASSWORD / AUTH; (2) an `args`-style array element that follows a key flag (--api-key, --token,
# --secret, --password, --auth* ...) or the `--flag=value` form; (3) a string holding a credential-shaped URL query
# (?key= / &token= / api_key= / access_token= / secret= / password= / auth...=). Anything jq cannot parse is judged textually
# (same shapes), and an unreadable file counts as holding key material (conservative: the caller then does NOT copy it).
# A secret stored in any other shape (a bare positional argument, a value with no key name) is NOT detected.
jev_file_has_key_material() {
  local f="$1"
  [ -r "$f" ] || return 0
  if jq -e . "$f" >/dev/null 2>&1; then
    jq -e '[.. | objects | to_entries[] | select((.key | test("API_?KEY|TOKEN|SECRET|PASSWORD|AUTH"; "i")) and ((.value | type) == "string") and (.value | length) > 0)] | length > 0' "$f" >/dev/null 2>&1 && return 0
    jq -e 'def kf: test("^--?[a-z0-9_-]*(api[_-]?key|token|secret|password|auth)[a-z0-9_-]*$"; "i");
           [ (.. | strings | select(test("[?&](api[_-]?key|key|token|access[_-]?token|secret|password|auth[a-z_]*)=[^&#\\s]+"; "i") or test("^--?[a-z0-9_-]*(api[_-]?key|token|secret|password|auth)[a-z0-9_-]*=."; "i"))),
             (.. | arrays | . as $a | range(0; ($a | length) - 1) | select((($a[.] | type) == "string") and ($a[.] | kf) and (($a[. + 1] | type) == "string") and (($a[. + 1] | length) > 0) and (($a[. + 1] | startswith("-")) | not)) | 1)
           ] | length > 0' "$f" >/dev/null 2>&1
  else
    grep -qiE "(API_?KEY|TOKEN|SECRET|PASSWORD|AUTH)[A-Za-z0-9_\"']*[[:space:]]*[=:][[:space:]]*[\"']?[^[:space:]\"']" "$f" 2>/dev/null && return 0
    grep -qiE "[?&](api[_-]?key|key|token|access[_-]?token|secret|password|auth[a-z_]*)=[^&#[:space:]]+|--?[a-z0-9_-]*(api[_-]?key|token|secret|password|auth)[a-z0-9_-]*([[:space:]]+|=)[^-[:space:]]" "$f" 2>/dev/null
  fi
}
# jev_backup_once <file> <stamp> -> first-backup-wins safety copy `<file>.prejev.<stamp>`. NEVER accumulates (any existing
# `<file>.prejev.*` means a pre-Jev copy is already kept) and NEVER copies a file holding key material: a timestamped
# plaintext duplicate of an API key is a leak that grows with every run (review r6 I6-1). The copy is mode 0600.
jev_backup_once() {
  local f="$1" stamp="$2" b
  [ -f "$f" ] || return 0
  for b in "$f".prejev.*; do [ -e "$b" ] && return 0; done
  if jev_file_has_key_material "$f"; then
    echo "jev: no backup of $f (it holds key material; the edit is a jq-preserving rewrite, nothing else is touched)" >&2
    return 0
  fi
  ( umask 077; cp -- "$f" "$f.prejev.$stamp" && chmod 600 -- "$f.prejev.$stamp" )
}

# jev_mcp_mode_rewrite <file> <mode> -> set env.JEV_MODE of every `jev` server entry that already has one (review r7 m7-6).
# Agents rewrite their own config continuously, so the edit is optimistic: checksum the file, compute the new content, re-check
# the checksum immediately before the atomic replace, and recompute (up to 3 attempts) when it moved. If it never settles the
# file is LEFT as the other writer wrote it (rc 1, warning) - a skipped mode rewrite is reported by jev-status as a mismatch,
# a lost agent write is not recoverable. The remaining window is the instant between the re-check and the rename (not zero).
# Test seam (JEV_TEST=1 only): JEV_BEFORE_WRITE_CMD runs between the compute and the re-check to play the concurrent writer.
jev_mcp_mode_rewrite() {
  local f="$1" m="$2" try s1 s2 out
  for try in 1 2 3; do
    s1="$(cksum < "$f" 2>/dev/null)" || return 1
    out="$(jq --arg m "$m" '(.. | objects | .jev? | objects | .env? | objects | select(has("JEV_MODE")) | .JEV_MODE) = $m' "$f")" && [ -n "$out" ] || return 1
    if [ "${JEV_TEST:-}" = "1" ] && [ -n "${JEV_BEFORE_WRITE_CMD:-}" ]; then "$JEV_BEFORE_WRITE_CMD" >/dev/null 2>&1 || true; fi
    s2="$(cksum < "$f" 2>/dev/null)" || return 1
    if [ "$s1" = "$s2" ]; then
      jev_backup_once "$f" "${NOW:-$(date +%s)}"
      printf '%s\n' "$out" | jev_write_atomic "$f"
      return $?
    fi
  done
  echo "jev: $f changed while being rewritten (3 attempts); JEV_MODE left as the other writer wrote it - re-run to reconcile" >&2
  return 1
}

# jev_mcp_files -> the COMPLETE set of agent config files that may carry a `jev` server entry, one per line, existing ones
# only (this function only NAMES paths). The covered set (review r6 m6-2, stated exactly in docs/jev/governance-guide.md):
#   <home>/.mcp.json, $HOME/.mcp.json, $HOME/.claude-*/.mcp.json, $HOME/.claude.json, $HOME/.claude-*/.claude.json,
#   $CLAUDE_CONFIG_DIR/.claude.json (+ /.mcp.json), <home>/.kimi-code/mcp.json, $HOME/.kimi-code/mcp.json, <home>/mcp.json
# where <home> = jev_home. The OpenCode / Pi agent configs are NOT scanned (UNCONFIRMED whether the toolkit writes a jev
# entry there; documented as an explicit gap).
jev_mcp_files() {
  local jh f seen="" out="" cc="${CLAUDE_CONFIG_DIR:-}"
  jh="$(jev_home)"
  for f in "$jh/.mcp.json" "${HOME:-}/.mcp.json" "${HOME:-}"/.claude-*/.mcp.json "${HOME:-}/.claude.json" "${HOME:-}"/.claude-*/.claude.json \
           ${cc:+"$cc/.claude.json" "$cc/.mcp.json"} "$jh/.kimi-code/mcp.json" "${HOME:-}/.kimi-code/mcp.json" "$jh/mcp.json"; do
    [ -f "$f" ] || continue
    case "
$seen
" in *"
$f
"*) continue ;; esac
    seen="${seen:+$seen
}$f"; out="$f"; printf '%s\n' "$out"
  done
}

# jev_env_values <file> <VAR> -> EVERY assignment of VAR in a shell-style env file, one value per line, in file order
# (plain or `export `-prefixed, optional leading blanks, one level of surrounding quotes stripped). The LAST line is what a
# shell sourcing the file would end up with; callers that must be conservative look at all of them.
jev_env_values() {
  [ -f "$1" ] || return 0
  sed -nE "s/^[[:space:]]*(export[[:space:]]+)?$2=(.*)\$/\2/p" "$1" 2>/dev/null | sed -E "s/^\"(.*)\"[[:space:]]*\$/\1/; s/^'(.*)'[[:space:]]*\$/\1/"
}
# jev_env_get <file> <VAR> -> the effective (last) value, empty when unset.
jev_env_get() { jev_env_values "$1" "$2" | tail -1; }
# jev_env_base_candidates <file> -> EVERY `JEV_BASE_URL=<value>` occurrence anywhere on any line (so `declare -x JEV_BASE_URL=...`,
# `A=1; JEV_BASE_URL=...`, `A=1 JEV_BASE_URL=...` and a commented-out line all count: a candidate, never a skipped line). One
# surrounding quote level stripped. A value needing shell expansion becomes @unresolvable-expansion@ (review r6 m6-2).
jev_env_base_candidates() {
  local f="$1" v
  [ -f "$f" ] || return 0
  grep -oE "JEV_BASE_URL=(\"[^\"]*\"|'[^']*'|[^;&|[:space:]]*)" "$f" 2>/dev/null | sed -E 's/^JEV_BASE_URL=//; s/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/' | while IFS= read -r v; do
    case "$v" in *'$'*|*'`'*) v="@unresolvable-expansion@" ;; esac
    printf '%s\n' "$v"
  done
}

# jev_mcp_base_values <file> -> every JEV_BASE_URL under a `jev` server entry anywhere in the file (one per line). A file
# jq cannot parse never silently yields nothing: the URLs it textually contains are returned, and when there are none the
# literal marker `@unparseable@` is (it is not loopback, so the caller falls to shadow).
jev_mcp_base_values() {
  local f="$1" v
  if jq -e . "$f" >/dev/null 2>&1; then
    jq -r '.. | objects | .jev? | objects | .env? | objects | .JEV_BASE_URL? | strings' "$f" 2>/dev/null
  else
    v="$(grep -oE 'JEV_BASE_URL"?[[:space:]]*:[[:space:]]*"[^"]*' "$f" 2>/dev/null | sed -E 's/^.*:[[:space:]]*"//' || true)"
    [ -n "$v" ] && printf '%s\n' "$v" || printf '@unparseable@\n'
  fi
}
# jev_mcp_modes -> `file TAB mode` for each jev entry with a JEV_MODE in the files above (read-only; unparseable files skipped).
jev_mcp_modes() {
  local f
  while IFS= read -r f; do
    jq -r --arg f "$f" '.. | objects | .jev? | objects | .env? | objects | .JEV_MODE? | strings | [$f, .] | @tsv' "$f" 2>/dev/null || true
  done < <(jev_mcp_files)
}

# jev_base_verdict [<extra-base-url>] -> prints `ok` or a reason (no tab/newline); the single base-URL resolver.
jev_base_verdict() {
  local cfg v c f n=0 src url
  local -a cand=()
  cfg="$(jev_config_dir)"
  [ -z "${1:-}" ] || cand+=("explicit|$1")
  [ -z "${JEV_BASE_URL:-}" ] || cand+=("process-env|$JEV_BASE_URL")
  # every assignment counts (not only the first line): ANY non-loopback occurrence, or a value needing shell expansion
  # (which cannot be determined here), makes the whole answer shadow (review r5 m5-1)
  while IFS= read -r v; do cand+=("env-file|$v"); done < <(jev_env_base_candidates "$cfg/env")
  while IFS= read -r f; do
    while IFS= read -r v; do [ -n "$v" ] || continue
      if [ "$v" = "@unparseable@" ]; then cand+=("mcp-unparseable|$v"); else cand+=("mcp-entry|$v"); fi
    done < <(jev_mcp_base_values "$f")
  done < <(jev_mcp_files)
  # the toolkit endpoint cache: the resolved providers dir, and the stock $HOME location too (both are read - fail closed).
  # A cache file jq cannot parse is a candidate that is NOT loopback (an unreadable cache never silently counts as absent);
  # a `typesafe`-style base URL variable inside it is read as well (review r6 m6-2).
  for c in "$(jev_providers_dir)/jev-endpoints.json" "$(jev_default_cache_file)"; do
    [ -n "$c" ] && [ -f "$c" ] || continue
    if jq -e . "$c" >/dev/null 2>&1; then
      v="$(jq -r '[.endpoints[0].base_url, .endpoints[0].TYPESAFE_BASE_URL, .TYPESAFE_BASE_URL] | map(strings) | .[]' "$c" 2>/dev/null || true)"
      while IFS= read -r v; do [ -z "$v" ] || cand+=("cache|$v"); done <<< "$v"
    else cand+=("cache-unparseable|@unparseable@"); fi
  done
  [ -z "${TYPESAFE_BASE_URL:-}" ] || cand+=("process-env-typesafe|$TYPESAFE_BASE_URL")
  for v in "${cand[@]}"; do
    src="${v%%|*}"; url="${v#*|}"; n=$((n+1))
    [ "$(jev_url_host_class "$url")" = "loopback" ] || { printf 'hosted-or-non-loopback-base-url(%s)' "$src"; return 0; }
  done
  [ "$n" -gt 0 ] || { printf 'base-url-unresolved'; return 0; }
  printf ok
}

jev_effective_mode() {
  local req="${1:-shadow}" base="${2:-}" det="${3:-}" thr="" f note="" profs="" p rv id url bv now gen max dj
  [ $# -ge 3 ] && shift 3 || shift $#
  command -v jq >/dev/null 2>&1 || { printf 'shadow\tjq-absent\n'; return 0; }
  if [ -n "${JEV_DECISION_PROFILES:-}" ] || [ -n "${JEV_REQUIRE_VALIDATED_CMD:-}" ]; then
    if [ "${JEV_TEST:-}" = "1" ]; then note=";test-override(JEV_TEST=1)"; else note=";override-ignored(JEV_TEST!=1)"; fi
  fi
  [ "$req" = "enforce" ] || { printf 'shadow\tnot-requested%s\n' "$note"; return 0; }
  bv="$(jev_base_verdict "$base")"
  [ "$bv" = "ok" ] || { printf 'shadow\t%s%s\n' "$bv" "$note"; return 0; }
  [ -n "$det" ] || det="$(jev_detection_file)"
  # the record is read ONCE into $dj and every later question is asked of that snapshot (review r6 n6-2: four separate reads
  # let a concurrent writer make the answers disagree with each other)
  dj=""; [ ! -f "$det" ] || dj="$(jq -c 'select((.endpoints | type) == "array")' "$det" 2>/dev/null || true)"
  [ -n "$dj" ] || { printf 'shadow\tno-detection-record%s\n' "$note"; return 0; }
  # the clock and the age limit are test seams: honoured ONLY under JEV_TEST=1 (review r5 m5-3), otherwise real time and the
  # fixed default - an environment variable must not be able to age a stale record into a fresh one
  now="$(date +%s)"; max=604800
  if [ "${JEV_TEST:-}" = "1" ]; then now="${JEV_NOW_EPOCH:-$now}"; max="${JEV_DETECTION_MAX_AGE:-$max}"; fi
  gen="$(jq -r 'if (.generated_at | type) == "number" then (.generated_at | floor) else "" end' <<< "$dj" 2>/dev/null || true)"
  { [[ "$gen" =~ ^[0-9]+$ ]] && [[ "$now" =~ ^[0-9]+$ ]] && [[ "$max" =~ ^[0-9]+$ ]] \
    && [ "$gen" -le $((now + 3600)) ] && [ $((now - gen)) -le "$max" ]; } \
    || { printf 'shadow\tdetection-record-stale-or-undated%s\n' "$note"; return 0; }
  while IFS=$'\t' read -r id url; do
    [ -n "$id" ] || continue
    [[ "$id" == llmctl-* ]] || continue
    p="${id#llmctl-}"; jev_profile_name_ok "$p" || continue
    [ "$(jev_url_host_class "$url")" = "loopback" ] || continue
    profs="${profs:+$profs }$p"
  done < <(jq -r '.endpoints[]? | select(.source == "local-llmctl") | [(.id // ""), (.url // "")] | @tsv' <<< "$dj" 2>/dev/null)
  [ -n "$profs" ] || { printf 'shadow\tno-qualifying-local-llmctl-endpoint(hosted-or-non-llmctl-or-non-loopback-never-enforce)%s\n' "$note"; return 0; }
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    if jq -e '(.per_type | type == "object") and ([.per_type[]? | select(.promoted == true and ((.threshold | type) == "number") and .threshold > 0 and .threshold <= 1)] | length > 0)' "$f" >/dev/null 2>&1; then thr="$f"; break; fi
  done < <(for f in "$@"; do [ -z "$f" ] || printf '%s\n' "$f"; done; jev_thresholds_candidates)
  [ -n "$thr" ] || { printf 'shadow\tno-promoted-threshold%s\n' "$note"; return 0; }
  if [ "${JEV_TEST:-}" = "1" ] && [ -n "${JEV_DECISION_PROFILES:-}" ]; then profs="${JEV_DECISION_PROFILES//,/ }"; fi
  [ "${JEV_SKIP_VALIDATION:-}" != "1" ] || { printf 'shadow\tvalidation-skipped%s\n' "$note"; return 0; }
  rv="llmctl require-validated"
  [ "${JEV_TEST:-}" = "1" ] && [ -n "${JEV_REQUIRE_VALIDATED_CMD:-}" ] && rv="$JEV_REQUIRE_VALIDATED_CMD"
  for p in $profs; do
    jev_profile_name_ok "$p" || { printf 'shadow\tinvalid-profile-name%s\n' "$note"; return 0; }
    # shellcheck disable=SC2086  # the command is a word list on purpose
    LLMCTL_VALIDATE_STRICT=1 timeout 60 $rv "$p" >/dev/null 2>&1 \
      || { printf 'shadow\trequire-validated-not-passed:%s%s\n' "$p" "$note"; return 0; }
  done
  printf 'enforce\tpromoted+validated%s\n' "$note"
}
