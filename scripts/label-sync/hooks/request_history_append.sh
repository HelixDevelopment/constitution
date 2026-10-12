#!/usr/bin/env bash
# scripts/label-sync/hooks/request_history_append.sh
#
# Purpose : Append ONE operator-request row to the project-local §11.4.208
#           request-history ledger. This is the auto-capture seam that
#           label-sync-prompt.sh (UserPromptSubmit) calls for every prompt.
#           Row = JSONL object, newest LAST (append-only, under flock):
#             {accepted, timezone, session_id, prompt, prompt_kind, prompt_bytes,
#              prompt_sha256, redactions, track, alias, model, effort, cwd, source}
#           prompt_kind: verbatim | verbatim-redacted | oversize (text not
#           stored, > LABEL_SYNC_LEDGER_MAX_BYTES) | lost (the append failed:
#           text not stored, sha256 + byte count are) | withheld (no redactor
#           available — the text is never written unredacted).
#           Unrecoverable fields are the literal string "UNKNOWN" (§11.4.208(A):
#           never invented). `accepted` is ISO-8601 WITH numeric UTC offset;
#           `timezone` is the zone abbreviation.
#           OPT-IN ONLY (review finding 7): the ledger exists only where
#           LABEL_SYNC_REQUEST_LEDGER names it (or `install_label_sync.sh
#           --request-ledger PATH` wrote that into settings.json `env`); an
#           existing docs/requests/ directory no longer auto-creates one.
#           SECRETS (§11.4.10): before the append the text is REDACTED —
#           GitHub (ghp_/gho_/ghu_/ghs_/ghr_/github_pat_), GitLab (glpat-),
#           Slack (xox?-), AWS key ids (AKIA/ASIA), sk-… API keys, PEM private
#           key blocks, and password/secret/token/api_key = value pairs; the
#           count is recorded in `redactions`.
#           LARGE PROMPTS (review finding 2): the text NEVER travels as a
#           command argument (128 KiB per-argument limit, E2BIG): it is written
#           to a 0600 temp file in the state dir and read by ONE perl process
#           (redact + sha256 + dedupe + row + markdown twin). If the append
#           fails anyway, a `lost` row (sha256 + byte count, no text) is
#           appended instead, ledger-failures.count is incremented and, with
#           LABEL_SYNC_DEBUG=1 (or LABEL_SYNC_HOOK_DEBUG=1), a line goes to stderr.
#           EXACTLY-ONCE: the same (session, prompt-sha256) arriving twice within
#           LABEL_SYNC_LEDGER_DEDUPE_MS (default 2000 ms) is the SAME event
#           delivered twice (hooks wired in two settings files) and is not
#           re-appended; the dedupe state stores the hash, never the text.
#           Limit (§11.4.6): UserPromptSubmit carries no prompt id (2.1.296
#           binary: {prompt, session_title} only), so a GENUINE identical prompt
#           re-sent by the operator inside the window is also dropped.
#           OPTIONAL human-readable twin: when <ledger dir>/history.md exists and
#           contains the line `<!-- label-sync:request-history:insert -->`, a
#           newest-first block is inserted right after that marker — BOUNDED:
#           at most LABEL_SYNC_LEDGER_MD_PROMPT_MAX bytes of text (default 4096,
#           then a pointer to the jsonl), and the twin is not rewritten at all
#           once it exceeds LABEL_SYNC_LEDGER_MD_MAX bytes (default 1048576;
#           counted in ledger-md-skipped.count).
# Usage   : (a) executed: printf '%s' '{"session_id":..,"prompt":..,"track":..,
#           "alias":..,"model":..,"effort":..,"cwd":..}' | request_history_append.sh
#           (b) sourced (what label-sync-prompt.sh does):
#           . request_history_append.sh;
#           rha_append <sid> <prompt> <track> <alias> <model> <effort> <cwd>
# Inputs  : stdin JSON (above); env LABEL_SYNC_REQUEST_LEDGER (the ledger path;
#           relative => against CLAUDE_PROJECT_DIR, else $PWD), LS_LEDGER_STATE
#           (dir for dedupe/temp/counters; falls back to
#           $TMPDIR/label-sync-ledger-<uid>), LABEL_SYNC_LEDGER_MAX_BYTES
#           (default 16777216), LABEL_SYNC_LEDGER_DEDUPE_MS,
#           LABEL_SYNC_LEDGER_MD_MAX, LABEL_SYNC_LEDGER_MD_PROMPT_MAX.
# Outputs : none on stdout; with LABEL_SYNC_DEBUG=1 a line on stderr per lost row.
# Exit    : 0 appended | 0 deduped | 0 no ledger configured (nothing is
#           invented) | 0 lost/withheld row appended instead | 1 nothing could be
#           appended at all (counter incremented). Callers treat every exit as
#           non-fatal.
# Side-effects: appends to the ledger (+ optional md twin); 0700 state dir with
#           ledger-last/<sid> ("<ms> <sha256>"), ledger.lock, *.count counters;
#           a 0600 temp file removed before return.
# Deps    : bash (>=4.2: printf %(..)T, EPOCHREALTIME), perl (core Digest::SHA),
#           flock when present; sha256sum only on the failure path.
# Cross-refs: §11.4.208, §11.4.210, §11.4.10, §11.4.6 (UNKNOWN never
#           fabricated), docs/label-sync/HOOKS.md §5. The html/pdf/docx exports of
#           the ledger (§11.4.65) are the project's docs-chain job.
# Classification: universal (§11.4.17).
set -u

# ONE perl process per prompt. Args: prompt-file ledger last-file md max-bytes
# window-ms md-max md-prompt-max counter-dir now-ms, then the row fields.
# Exit 0 appended | 3 duplicate (not appended) | other: nothing appended.
_RHA_PL='
use strict; use warnings;
use Digest::SHA qw(sha256_hex);
my ($pf,$ledger,$last,$md,$max,$win,$mdmax,$mdpmax,$cdir,$now,$acc,$tz,$sid,$tr,$al,$mo,$ef,$cwd)=@ARGV;
my $p=do { local $/; my $fh; if ($pf ne "") { open($fh,"<:raw",$pf) or exit 1 } else { $fh=\*STDIN; binmode $fh } my $x=<$fh>; defined $x ? $x : "" };
my $bytes=length($p); my $sha=sha256_hex($p);
if ($last ne "" && open(my $lf,"<",$last)) { my $l=<$lf>; close $lf;
  if (defined $l && $l =~ /^(\d+) ([0-9a-f]{64})/) { exit 3 if $2 eq $sha && $now-$1 < $win; } }
my ($kind,$red,$t)=("verbatim",0,$p);
if ($bytes > $max) { ($kind,$t)=("oversize",undef); }
else {
  my $n=0;
  $n += ($t =~ s/-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----.*?-----END [A-Z0-9 ]*PRIVATE KEY-----/[REDACTED:private-key]/gs) || 0;
  $n += ($t =~ s/\bgithub_pat_[A-Za-z0-9_]{20,}/[REDACTED:github-token]/g) || 0;
  $n += ($t =~ s/\bgh[pousr]_[A-Za-z0-9]{20,}/[REDACTED:github-token]/g) || 0;
  $n += ($t =~ s/\bglpat-[A-Za-z0-9_\-]{20,}/[REDACTED:gitlab-token]/g) || 0;
  $n += ($t =~ s/\bxox[abposr]-[A-Za-z0-9\-]{10,}/[REDACTED:slack-token]/g) || 0;
  $n += ($t =~ s/\b(?:AKIA|ASIA)[0-9A-Z]{16}\b/[REDACTED:aws-key-id]/g) || 0;
  $n += ($t =~ s/\bsk-[A-Za-z0-9_\-]{20,}/[REDACTED:api-key]/g) || 0;
  $n += ($t =~ s/\b((?i:password|passwd|pwd|secret|client[_-]?secret|token|api[_-]?key|access[_-]?key|private[_-]?key))(\s*[=:]\s*)(?!\[REDACTED)("[^"\n]*"|\x27[^\x27\n]*\x27|[^\s"\x27]+)/$1$2\[REDACTED\]/g) || 0;
  $red=$n; $kind="verbatim-redacted" if $n;
  my $c=$t; if (!utf8::decode($c)) { require Encode; $t=Encode::encode("UTF-8",Encode::decode("UTF-8",$t)); }
}
sub js { my $s=shift; return "null" unless defined $s; $s =~ s/(["\\])/\\$1/g;
  $s =~ s/([\x00-\x1f])/sprintf("\\u%04x",ord($1))/ge; return "\"$s\""; }
sub uk { my $s=shift; return js((defined $s && $s ne "") ? $s : "UNKNOWN"); }
my $row="{\"accepted\":".js($acc).",\"timezone\":".js($tz).",\"session_id\":".uk($sid).
  ",\"prompt\":".js($t).",\"prompt_kind\":".js($kind).",\"prompt_bytes\":$bytes,\"prompt_sha256\":\"$sha\"".
  ",\"redactions\":$red,\"track\":".uk($tr).",\"alias\":".uk($al).",\"model\":".uk($mo).
  ",\"effort\":".uk($ef).",\"cwd\":".uk($cwd).",\"source\":\"label-sync-prompt-hook\"}\n";
open(my $o,">>:raw",$ledger) or exit 1; (print $o $row) or exit 1; close($o) or exit 1;
if ($last ne "" && open(my $w,">",$last)) { print $w "$now $sha\n"; close $w; }
if ($md ne "" && -f $md) {
  my $mk="<!-- label-sync:request-history:insert -->";
  if (-s $md > $mdmax) {
    if ($cdir ne "" && open(my $cf,"+>>",$cdir."/ledger-md-skipped.count")) { seek($cf,0,0); my $v=<$cf>; $v=(defined $v && $v=~/^(\d+)/)?$1+1:1; truncate($cf,0); print $cf "$v\n"; close $cf; }
  } elsif (open(my $mf,"<:raw",$md)) {
    my $doc=do { local $/; <$mf> }; close $mf;
    my $i=index($doc,$mk);
    if ($i >= 0) {
      my $ex;
      if (!defined $t) { $ex="[oversize prompt not stored: $bytes bytes, sha256 $sha]"; }
      elsif (length($t) <= $mdpmax) { $ex=$t; }
      else { my $b=substr($t,0,$mdpmax); my $k=0;
        while ($k++ < 4) { my $c=$b; last if utf8::decode($c); chop $b; }
        $ex=$b."\n[... truncated: $bytes bytes in total; full text in the jsonl ledger, sha256 $sha]"; }
      $ex =~ s/^/    /mg;
      my $blk="### $acc ($tz) \xe2\x80\x94 session ".(($sid ne "")?$sid:"UNKNOWN")."\n- Track: ".(($tr ne "")?$tr:"UNKNOWN")." | Alias: ".(($al ne "")?$al:"UNKNOWN")." | Model: ".(($mo ne "")?$mo:"UNKNOWN")." | Effort: ".(($ef ne "")?$ef:"UNKNOWN")."\n- Request ($kind):\n\n$ex\n\n";
      my $e=index($doc,"\n",$i); $e=($e<0)?length($doc):$e+1;
      my $tmp="$md.label-sync.$$";
      if (open(my $tf,">:raw",$tmp)) { print $tf substr($doc,0,$e).$blk.substr($doc,$e); close $tf; rename($tmp,$md) or unlink($tmp); }
    }
  }
}
exit 0;
'

# _rha_count <dir> <name> : increment <dir>/<name>.count (best effort).
_rha_count() {
  [ -n "$1" ] && [ -d "$1" ] || return 0
  local v=0; [ -f "$1/$2.count" ] && { IFS= read -r v <"$1/$2.count"; } 2>/dev/null
  case "$v" in ''|*[!0-9]*) v=0 ;; esac
  printf '%s\n' "$((v + 1))" >"$1/$2.count" 2>/dev/null
  return 0
}
_rha_dbg() { [ "${LABEL_SYNC_DEBUG:-}" = 1 ] || [ "${LABEL_SYNC_HOOK_DEBUG:-}" = 1 ] && printf 'label-sync ledger: %s\n' "$*" >&2; return 0; }
# _rha_js <string> : JSON string literal (pure bash, for the lost row).
_rha_js() { local t="$1"; t="${t//\\/\\\\}"; t="${t//\"/\\\"}"; t="${t//$'\n'/\\n}"; t="${t//$'\t'/\\t}"; t="${t//$'\r'/\\r}"; printf '"%s"' "$t"; }

# rha_ledger_path : resolve LABEL_SYNC_REQUEST_LEDGER into RHA_LEDGER ('' = none).
rha_ledger_path() {
  RHA_LEDGER="${LABEL_SYNC_REQUEST_LEDGER:-}"
  [ -n "$RHA_LEDGER" ] || return 1                 # opt-in only: nothing is invented
  case "$RHA_LEDGER" in /*) ;; *) RHA_LEDGER="${CLAUDE_PROJECT_DIR:-$PWD}/$RHA_LEDGER" ;; esac
  return 0
}
# rha_prepare : sets RHA_BASE (the 0700 state dir, '' if unusable).
# rha_prepare --tmp : additionally makes RHA_TMP, a fresh 0600 temp file in it
# (only large prompts need one; small ones reach perl through a pipe).
rha_prepare() {
  RHA_BASE="${LS_LEDGER_STATE:-${TMPDIR:-/tmp}/label-sync-ledger-${UID:-0}}"; RHA_TMP=""
  [ -d "$RHA_BASE/ledger-last" ] || ( umask 077; mkdir -p "$RHA_BASE/ledger-last" ) 2>/dev/null
  [ -d "$RHA_BASE/ledger-last" ] && [ -O "$RHA_BASE" ] || { RHA_BASE=""; return 1; }
  [ "${1:-}" = --tmp ] || return 0
  RHA_TMP="$RHA_BASE/.prompt.$$.$RANDOM"
  ( umask 077; : >"$RHA_TMP" ) 2>/dev/null || { RHA_TMP=""; return 1; }
  return 0
}

# rha_append sid prompt track alias model effort cwd — see the header for exits.
# The text goes to perl through a PIPE (never an argv, never a temp file).
rha_append() {
  [ -n "$2" ] || return 0
  rha_ledger_path || return 0
  rha_prepare || true                 # no state dir => no dedupe/lock, still recorded
  _rha_run "" "$1" "$3" "$4" "$5" "$6" "$7" "$2"
}

# rha_append_file sid prompt-file track alias model effort cwd — for a LARGE
# prompt already streamed into RHA_TMP (rha_prepare --tmp). CONSUMES the file.
rha_append_file() {
  local r=0
  if ! rha_ledger_path; then rm -f -- "$2"; return 0; fi
  if [ -s "$2" ]; then _rha_run "$2" "$1" "$3" "$4" "$5" "$6" "$7" ""; r=$?; fi
  rm -f -- "$2"; return "$r"
}

# _rha_run prompt-file|'' sid track alias model effort cwd prompt-string — the
# core: ONE perl process (under the state-dir flock when available).
_rha_run() {
  local pf="$1" sid="$2" track="$3" alias="$4" model="$5" effort="$6" cwd="$7"
  # sid names a dedupe-state FILE: only a safe id is used (review finding 3).
  [[ "$sid" =~ ^[A-Za-z0-9_-]{1,128}$ ]] || sid=""
  local ledger="$RHA_LEDGER" base="${RHA_BASE:-}" ldir="${RHA_LEDGER%/*}" last="" lock="" md=""
  [ -n "$base" ] && { last="$base/ledger-last/${sid:-nosession}"; lock="$base/ledger.lock"; }
  [ -d "$ldir" ] || mkdir -p "$ldir" 2>/dev/null
  [ -f "$ldir/history.md" ] && md="$ldir/history.md"
  local acc tz now_us="${EPOCHREALTIME/./}"
  printf -v acc '%(%Y-%m-%dT%H:%M:%S%z)T' -1; printf -v tz '%(%Z)T' -1
  local -a args=("$pf" "$ledger" "$last" "$md" "${LABEL_SYNC_LEDGER_MAX_BYTES:-16777216}"
                 "${LABEL_SYNC_LEDGER_DEDUPE_MS:-2000}" "${LABEL_SYNC_LEDGER_MD_MAX:-1048576}"
                 "${LABEL_SYNC_LEDGER_MD_PROMPT_MAX:-4096}" "$base" "$(( now_us / 1000 ))"
                 "$acc" "$tz" "$sid" "$track" "$alias" "$model" "$effort" "$cwd")
  local rc reason
  if ! command -v perl >/dev/null 2>&1; then
    rc=10; reason="no redactor (perl) available"
  elif [ -n "$lock" ] && command -v flock >/dev/null 2>&1; then
    printf '%s' "$8" | { flock -w 3 9 || exit 4; exec perl -e "$_RHA_PL" "${args[@]}"; } 9>>"$lock" 2>/dev/null; rc=$?
    reason="row builder exit $rc"
  else
    printf '%s' "$8" | perl -e "$_RHA_PL" "${args[@]}" 2>/dev/null; rc=$?; reason="row builder exit $rc"
  fi
  if [ "$rc" -eq 0 ] || [ "$rc" -eq 3 ]; then return 0; fi
  local kind=lost; [ "$rc" -eq 10 ] && kind=withheld
  RHA_KIND="$kind" rha_lost_row "$sid" "$8" "$track" "$alias" "$model" "$effort" "$cwd" "$reason" "$pf"
}

# rha_lost_row sid prompt track alias model effort cwd reason [prompt-file]
# The failure path: NEVER silent, NEVER the text (it may be unredacted). Appends
# a row with prompt=null, prompt_kind=lost|withheld, sha256 + byte count,
# increments ledger-failures.count, reports on stderr under LABEL_SYNC_DEBUG=1.
rha_lost_row() {
  local sid="$1" prompt="$2" track="$3" alias="$4" model="$5" effort="$6" cwd="$7" reason="$8" pf="${9:-}"
  [[ "$sid" =~ ^[A-Za-z0-9_-]{1,128}$ ]] || sid=""
  rha_ledger_path || return 0
  local ledger="$RHA_LEDGER" kind="${RHA_KIND:-lost}" sha bytes acc tz
  if [ -n "$pf" ] && [ -f "$pf" ]; then sha="$(sha256sum "$pf" 2>/dev/null)"; bytes="$(wc -c <"$pf" 2>/dev/null)"
  elif [ -n "$prompt" ]; then sha="$(printf '%s' "$prompt" | sha256sum 2>/dev/null)"; bytes="$(LC_ALL=C; printf '%s' "${#prompt}")"
  else sha=""; bytes=""; fi                  # text unavailable here: UNKNOWN, never the hash of ""
  sha="${sha%% *}"; bytes="${bytes//[!0-9]/}"; [ -n "$bytes" ] || bytes=null
  printf -v acc '%(%Y-%m-%dT%H:%M:%S%z)T' -1; printf -v tz '%(%Z)T' -1
  _rha_count "${RHA_BASE:-${LS_LEDGER_STATE:-}}" ledger-failures
  _rha_dbg "prompt NOT stored (prompt_kind=$kind): $reason; session ${sid:-UNKNOWN}, $bytes bytes, sha256 ${sha:-UNKNOWN}"
  local row
  row="{\"accepted\":$(_rha_js "$acc"),\"timezone\":$(_rha_js "$tz"),\"session_id\":$(_rha_js "${sid:-UNKNOWN}"),\"prompt\":null,\"prompt_kind\":\"$kind\",\"prompt_bytes\":$bytes,\"prompt_sha256\":$(_rha_js "${sha:-UNKNOWN}"),\"reason\":$(_rha_js "$reason"),\"track\":$(_rha_js "${track:-UNKNOWN}"),\"alias\":$(_rha_js "${alias:-UNKNOWN}"),\"model\":$(_rha_js "${model:-UNKNOWN}"),\"effort\":$(_rha_js "${effort:-UNKNOWN}"),\"cwd\":$(_rha_js "${cwd:-UNKNOWN}"),\"source\":\"label-sync-prompt-hook\"}"
  [ -d "${ledger%/*}" ] || mkdir -p "${ledger%/*}" 2>/dev/null
  if printf '%s\n' "$row" >>"$ledger" 2>/dev/null; then return 0; fi
  _rha_dbg "the lost row could not be appended either: $ledger"
  return 1
}

# executed directly: read the JSON from stdin
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  command -v jq >/dev/null 2>&1 || exit 0
  IN="$(cat 2>/dev/null)" || exit 0
  [ -n "$IN" ] || exit 0
  eval "$(printf '%s' "$IN" | jq -r 'def s: if type=="string" then . else "" end; @sh "sid=\(.session_id // "" | s) track=\(.track // "" | s) alias=\(.alias // "" | s) model=\(.model // "" | s) effort=\(.effort // "" | s) cwd=\(.cwd // "" | s)"' 2>/dev/null)" || exit 0
  rha_ledger_path || exit 0
  if ! rha_prepare --tmp; then
    rha_lost_row "${sid:-}" "$(printf '%s' "$IN" | jq -j '.prompt // "" | if type=="string" then . else "" end' 2>/dev/null)" "${track:-}" "${alias:-}" "${model:-}" "${effort:-}" "${cwd:-}" "no state dir for the 0600 temp file"
    exit $?
  fi
  printf '%s' "$IN" | jq -j '.prompt // "" | if type=="string" then . else "" end' >"$RHA_TMP" 2>/dev/null
  rha_append_file "${sid:-}" "$RHA_TMP" "${track:-}" "${alias:-}" "${model:-}" "${effort:-}" "${cwd:-}"
  exit $?
fi
