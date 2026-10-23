#!/usr/bin/env bash
# jev-calibrate.sh — §11.4.285 traditional-LLM auto-tuning of Jev thresholds.
#
# This is the CONSTITUTION-side calibration loop (an LLM labels sampled shadow
# decisions; thresholds are earned per question type). It is a different tool
# from claude_toolkit's scripts/jev-calibrate.sh (label|sweep|check subcommands
# over operator-supplied ground truth, lock file decisions.lock.json). The two
# do not share a file format; see docs/jev/governance-guide.md.
#
# Loop:
#   1. Sample  — deterministic: sort calibratable decisions by ts, take every
#                k-th to reach --sample (default 50/type; promotion floor 30).
#   2. Label   — the project's main LLM labels each sampled decision from the
#                question, its criteria and the recorded state text. The Jev
#                answer is NOT shown to the labeler (showing it would anchor
#                the label and inflate agreement). Output is parsed
#                structurally (JSON {"label": ...}); a parse failure counts as
#                label_error and is never guessed.
#   3. Compare — per question type: agreement + 0.1-wide confidence bins.
#                recommended_threshold = lowest bin whose empirical agreement
#                is >= floor (default 0.90, env JEV_CALIBRATE_FLOOR).
#   4. Write   — atomic jev-thresholds.json (tmp + rename); the previous file is
#                preserved as jev-thresholds.<epoch>.json. A type promotes only
#                with n_labeled >= min sample AND a qualifying bin. A previously
#                promoted type that now fails is DEMOTED to shadow, loudly.
#
# A decision row is calibratable only if it records the question text and its
# criteria object AND the state text (field state_text), or carries the
# test-seam field label_hint. Rows without them (for example the rows the
# claude_toolkit gate writes today: question "gate", hash only) are counted as
# skipped_uncalibratable and reported; they are never labeled blind.
#
# Exit codes: 0 report produced (promotion is data, not an exit code);
#             1 nothing to calibrate (no decisions / no calibratable rows);
#             2 usage error or a required tool is missing (cannot determine).
#
# Usage: jev-calibrate.sh [--now] [--sample N] [--question-type T] [--alias A] [--dry-run]
# Env (names only):
#   JEV_STATE_DIR (default ~/.local/state/jev)  decisions.jsonl lives here
#   JEV_CONFIG_DIR (default ~/.config/jev)      thresholds written here
#   JEV_EVIDENCE_DIR (default .jev)             thresholds mirrored here
#   JEV_CALIBRATE_ALIAS_CMD  label command; receives the labeling prompt JSON
#        on stdin and must print JSON {"label": ...}. Default: the toolkit
#        provider alias <A> run headless through cma_run_provider (sourced from
#        JEV_CALIBRATE_ALIAS_FILE or the toolkit default alias file).
#   JEV_CALIBRATE_ALIAS_FILE  alias file defining cma_run_provider
#   JEV_CALIBRATE_FLOOR (default 0.90), JEV_CALIBRATE_MIN_SAMPLE (default 30)
#   JEV_NOW_EPOCH (deterministic-clock seam for tests)

set -euo pipefail

JEV_STATE_DIR="${JEV_STATE_DIR:-$HOME/.local/state/jev}"
JEV_CONFIG_DIR="${JEV_CONFIG_DIR:-$HOME/.config/jev}"
JEV_EVIDENCE_DIR="${JEV_EVIDENCE_DIR:-.jev}"
NOW="${JEV_NOW_EPOCH:-$(date +%s)}"
FLOOR="${JEV_CALIBRATE_FLOOR:-0.90}"
MIN_SAMPLE="${JEV_CALIBRATE_MIN_SAMPLE:-30}"

SAMPLE=50
ONLY_TYPE=""
ALIAS="claude"
DRY_RUN=0
need_val() { [ "$1" -ge 2 ] || { echo "jev-calibrate: $2 needs a value" >&2; exit 2; }; }
while [ $# -gt 0 ]; do
  case "$1" in
    --now) shift ;;
    --sample) need_val $# "$1"; SAMPLE="$2"; shift 2 ;;
    --question-type) need_val $# "$1"; ONLY_TYPE="$2"; shift 2 ;;
    --alias) need_val $# "$1"; ALIAS="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --help|-h) sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//' >&2; exit 0 ;;
    *) echo "jev-calibrate: unknown argument: $1" >&2; exit 2 ;;
  esac
done
case "$SAMPLE" in ''|*[!0-9]*) echo "jev-calibrate: --sample must be a positive integer" >&2; exit 2 ;; esac
[ "$SAMPLE" -ge 1 ] || { echo "jev-calibrate: --sample must be >= 1" >&2; exit 2; }
case "$MIN_SAMPLE" in ''|*[!0-9]*) echo "jev-calibrate: JEV_CALIBRATE_MIN_SAMPLE must be an integer" >&2; exit 2 ;; esac
case "$FLOOR" in ''|*[!0-9.]*) echo "jev-calibrate: JEV_CALIBRATE_FLOOR must be a number" >&2; exit 2 ;; esac
case "$ALIAS" in *[!A-Za-z0-9._-]*|"") echo "jev-calibrate: --alias must be a plain alias name" >&2; exit 2 ;; esac

command -v jq >/dev/null 2>&1 || { echo "jev-calibrate: jq is required (JSON parsing); cannot determine (rc 2)" >&2; exit 2; }

DECISIONS="$JEV_STATE_DIR/decisions.jsonl"
if [ ! -s "$DECISIONS" ]; then
  echo "jev-calibrate: no decisions at $DECISIONS — nothing to calibrate" >&2
  exit 1
fi

if [ -n "${JEV_CALIBRATE_ALIAS_CMD:-}" ]; then
  LABEL_CMD="$JEV_CALIBRATE_ALIAS_CMD"
else
  ALIAS_FILE="${JEV_CALIBRATE_ALIAS_FILE:-$HOME/.local/share/claude-multi-account/aliases.sh}"
  if [ ! -f "$ALIAS_FILE" ]; then
    echo "jev-calibrate: no label command: set JEV_CALIBRATE_ALIAS_CMD or provide the toolkit alias file ($ALIAS_FILE); cannot determine (rc 2)" >&2
    exit 2
  fi
  # cma_run_provider is a shell function from the toolkit alias file, not an
  # executable. The prompt JSON on stdin becomes the headless -p prompt.
  # UNCONFIRMED: the model's reply is expected to be a bare JSON object; replies
  # that are not parse as label_error (counted, never guessed).
  LABEL_CMD="bash -c 'source \"\$1\" >/dev/null 2>&1; p=\$(cat); cma_run_provider \"\$2\" -p \"Reply with ONLY a JSON object {\\\"label\\\": \\\"<criteria key>\\\"} choosing the correct criteria key for this decision: \$p\"' _ $ALIAS_FILE $ALIAS"
fi

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT

# Calibratable rows -> ts \t type \t conf \t prompt-json(compact, no TAB/NL) \t answer
jq -r '
  select((.question | type) == "string" and (.criteria | type) == "object"
         and ((.state_text | type) == "string" or (.label_hint | type) == "string"))
  | [ (.ts // 0), (.question_type // .question), (.confidence // 0),
      ({question: .question, criteria: .criteria, state_text: (.state_text // ""), label_hint: (.label_hint // "")} | tojson),
      (.answer | tostring) ]
  | map(tostring | gsub("[\t\n\r]"; " ")) | join("\t")' "$DECISIONS" > "$TMPD/all.tsv" 2>/dev/null || : > "$TMPD/all.tsv"
TOTAL_ROWS="$(grep -c . "$DECISIONS" || true)"
CAL_ROWS="$(grep -c . "$TMPD/all.tsv" || true)"
SKIPPED=$(( ${TOTAL_ROWS:-0} - ${CAL_ROWS:-0} ))
if [ "${CAL_ROWS:-0}" -eq 0 ]; then
  echo "jev-calibrate: $SKIPPED of ${TOTAL_ROWS:-0} decision row(s) lack question/criteria/state_text; nothing calibratable (see header)" >&2
  exit 1
fi

prev_promoted() { # prev_promoted <type>
  local f="$JEV_CONFIG_DIR/jev-thresholds.json"
  [ -f "$f" ] || f="$JEV_EVIDENCE_DIR/jev-thresholds.json"
  [ -f "$f" ] || { echo false; return; }
  jq -r --arg t "$1" '.per_type[$t].promoted // false' "$f" 2>/dev/null || echo false
}

cut -f2 "$TMPD/all.tsv" | sort -u > "$TMPD/types.txt"
if [ -n "$ONLY_TYPE" ]; then
  grep -Fx -- "$ONLY_TYPE" "$TMPD/types.txt" > "$TMPD/types.f" || true
  mv "$TMPD/types.f" "$TMPD/types.txt"
fi
if [ ! -s "$TMPD/types.txt" ]; then
  echo "jev-calibrate: no calibratable decisions of type '${ONLY_TYPE:-*}'" >&2
  exit 1
fi

: > "$TMPD/frags.tsv"     # type <TAB> compact-json-entry
: > "$TMPD/report.tsv"
DEMOTED=""

while IFS= read -r type; do
  [ -n "$type" ] || continue
  # deterministic sample: sort by ts, every k-th to reach SAMPLE
  awk -F'\t' -v t="$type" '$2==t' "$TMPD/all.tsv" | sort -n -k1,1 > "$TMPD/type.tsv"
  n_total="$(wc -l < "$TMPD/type.tsv" | tr -d ' ')"
  k=$(( n_total / SAMPLE )); [ "$k" -lt 1 ] && k=1
  awk -v k="$k" '(NR - 1) % k == 0' "$TMPD/type.tsv" > "$TMPD/sample.tsv"

  : > "$TMPD/labeled.tsv"   # conf \t agree(0|1)
  n_labeled=0; n_errors=0
  while IFS=$'\t' read -r _ts _qt conf prompt answer; do
    # LABEL_CMD is a command template: intentional word splitting via eval of a
    # string the OPERATOR supplied (env/arg), never of decision data.
    out="$(printf '%s' "$prompt" | bash -c "$LABEL_CMD" 2>/dev/null || true)"
    label="$(printf '%s' "$out" | jq -r '.label // empty' 2>/dev/null || true)"
    if [ -z "$label" ]; then
      n_errors=$((n_errors + 1))   # parse failure: counted, never guessed
      continue
    fi
    n_labeled=$((n_labeled + 1))
    agree=0; [ "$label" = "$answer" ] && agree=1
    printf '%s\t%s\n' "$conf" "$agree" >> "$TMPD/labeled.tsv"
  done < "$TMPD/sample.tsv"

  read -r agreement rec_threshold <<<"$(awk -F'\t' -v floor="$FLOOR" '
    { bin = int($1 * 10); if (bin > 9) bin = 9; if (bin < 0) bin = 0;
      n[bin]++; hits[bin] += $2; tot++; hitsum += $2 }
    END {
      if (tot == 0) { printf("0.0000 null\n"); exit }
      rec = "null"
      for (b = 0; b <= 9; b++)
        if (n[b] > 0 && hits[b] / n[b] >= floor + 0) { rec = sprintf("%.1f", b / 10); break }
      printf("%.4f %s\n", hitsum / tot, rec)
    }' "$TMPD/labeled.tsv")"
  agreement="${agreement:-0.0000}"; rec_threshold="${rec_threshold:-null}"

  promoted=false; reason=""
  if [ "$n_labeled" -lt "$MIN_SAMPLE" ]; then
    reason="insufficient-sample ($n_labeled < $MIN_SAMPLE)"
  elif [ "$rec_threshold" = "null" ]; then
    reason="no-confidence-bin-meets-floor ($FLOOR)"
  else
    promoted=true
  fi
  mode="shadow"; [ "$promoted" = "true" ] && mode="enforce"

  was="$(prev_promoted "$type")"
  if [ "$was" = "true" ] && [ "$promoted" = "false" ]; then
    DEMOTED="$DEMOTED$type "
    echo "jev-calibrate: DEMOTED type '$type' — reverts to shadow ($reason)" >&2
  fi

  frag="$(jq -cn --argjson thr "$rec_threshold" --argjson n "$n_labeled" --argjson le "$n_errors" \
            --argjson agr "$agreement" --argjson floor "$FLOOR" --argjson promoted "$promoted" \
            --arg mode "$mode" --arg reason "$reason" \
            '{threshold:$thr, n:$n, label_errors:$le, agreement:$agr, floor:$floor, promoted:$promoted, mode:$mode, reason:$reason}')"
  printf '%s\t%s\n' "$type" "$frag" >> "$TMPD/frags.tsv"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$type" "$n_labeled" "$agreement" "$rec_threshold" "$promoted" "$reason" >> "$TMPD/report.tsv"
done < "$TMPD/types.txt"

OUTPUT="$(jq -Rn --argjson now "$NOW" --argjson floor "$FLOOR" --argjson min "$MIN_SAMPLE" --argjson sample "$SAMPLE" \
  '{version:1, calibrated_at:$now, floor:$floor, min_sample:$min, sample_per_type:$sample,
    per_type: ([inputs | split("\t") | {key:.[0], value:(.[1] | fromjson)}] | from_entries)}' < "$TMPD/frags.tsv")"

write_thresholds() { # atomic write; previous preserved as .<epoch>.json
  local target="$1"
  if [ -f "$target" ]; then
    cp -p "$target" "$(dirname "$target")/jev-thresholds.$NOW.json"
  fi
  printf '%s\n' "$OUTPUT" > "$target.tmp.$$"
  mv -f "$target.tmp.$$" "$target"
}

if [ "$DRY_RUN" = "0" ]; then
  mkdir -p "$JEV_CONFIG_DIR" "$JEV_EVIDENCE_DIR"
  write_thresholds "$JEV_CONFIG_DIR/jev-thresholds.json"
  write_thresholds "$JEV_EVIDENCE_DIR/jev-thresholds.json"
fi

echo "jev-calibrate report (calibrated_at=$NOW floor=$FLOOR min_sample=$MIN_SAMPLE sample=$SAMPLE)"
echo "  sampling: deterministic sorted-ts every-k-th; rows skipped as uncalibratable: $SKIPPED of $TOTAL_ROWS"
while IFS=$'\t' read -r t n agr thr prom reason; do
  line="  - $t: n=$n agreement=$agr recommended_threshold=$thr promoted=$prom"
  [ -n "$reason" ] && line="$line ($reason)"
  echo "$line"
done < "$TMPD/report.tsv"
[ -n "$DEMOTED" ] && echo "  DEMOTED (reverted to shadow): $DEMOTED"
[ "$DRY_RUN" = "1" ] && echo "  (dry-run: no files written)"
exit 0
