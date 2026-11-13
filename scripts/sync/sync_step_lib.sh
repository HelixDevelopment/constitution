#!/usr/bin/env bash
# scripts/sync/sync_step_lib.sh -- the ONE integration seam of sync_all_upstreams.sh, sourced by
# scripts/setup.sh (first-time / repeat setup) and scripts/post_update_hook.sh (STEP 5c, check only).
#
#   sync_step MODE PROJECT_ROOT ENGINE
#     MODE    off      print how to run it; run nothing
#             offline  --check --no-fetch   (read-only, no network: the post-update default)
#             check    --check              (fetch every remote, change nothing else)
#             apply    --apply              (fetch, fast-forward; non-interactive: the flag is the consent)
#             ask      --apply --interactive (the engine asks on /dev/tty before fetching and before
#                      every change; without a terminal the step is SKIPPED, never run unasked)
#   Sets SYNC_STEP_RC to the engine's exit code (or 0 for off / skip) and SYNC_STEP_VERDICT to one of
#   OFF SKIP CURRENT UPDATES-AVAILABLE ATTENTION FAILED BLIND. Returns 0, except 1 when an --apply
#   integration step failed (exit 1 of the engine). Never prints a URL or a credential itself; the
#   engine redacts its own output.
# Classification: universal (§11.4.17).
sync_step() {
  local mode="${1:-off}" root="${2:-}" engine="${3:-}" top rc=0
  local -a args
  SYNC_STEP_RC=0; SYNC_STEP_VERDICT=OFF
  case "$mode" in
    off)     echo "[sync-upstreams] off; to fetch every remote and fast-forward the whole tree: bash <constitution>/scripts/sync/sync_all_upstreams.sh --check --root ${root:-.}"; return 0 ;;
    offline) args=(--check --no-fetch --non-interactive) ;;
    check)   args=(--check --non-interactive) ;;
    apply)   args=(--apply --non-interactive) ;;
    ask)     args=(--apply --interactive) ;;
    *)       echo "[sync-upstreams] unknown mode '$mode' (off|offline|check|apply|ask): SKIP"; SYNC_STEP_VERDICT=SKIP; return 0 ;;
  esac
  if [ -z "$engine" ] || [ ! -f "$engine" ]; then
    echo "[sync-upstreams] SKIP: engine not found (${engine:-unset})"; SYNC_STEP_VERDICT=SKIP; return 0
  fi
  if [ -z "$root" ] || ! top="$(git -C "$root" rev-parse --show-toplevel 2>/dev/null)" || [ -z "$top" ]; then
    echo "[sync-upstreams] SKIP: ${root:-<unset>} is not a git work tree"; SYNC_STEP_VERDICT=SKIP; return 0
  fi
  if [ "$mode" = ask ] && ! { : </dev/tty; } 2>/dev/null; then
    echo "[sync-upstreams] SKIP: 'ask' needs a terminal; use check or apply for a non-interactive run"; SYNC_STEP_VERDICT=SKIP; return 0
  fi
  # SYNC_STEP_EXTRA_ARGS: extra engine flags for tests (e.g. --out DIR); word-split on purpose, no spaces in values
  # shellcheck disable=SC2086
  bash "$engine" "${args[@]}" --root "$top" --quiet ${SYNC_STEP_EXTRA_ARGS:-} || rc=$?
  SYNC_STEP_RC=$rc
  case "$rc" in
    0) SYNC_STEP_VERDICT=CURRENT;           echo "[sync-upstreams] $mode: CURRENT (exit 0)" ;;
    3) SYNC_STEP_VERDICT=UPDATES-AVAILABLE; echo "[sync-upstreams] $mode: UPDATES-AVAILABLE (exit 3; run with apply to fast-forward)" ;;
    4) SYNC_STEP_VERDICT=ATTENTION;         echo "[sync-upstreams] $mode: ATTENTION (exit 4; see the report above)" ;;
    1) SYNC_STEP_VERDICT=FAILED;            echo "[sync-upstreams] $mode: FAILED (exit 1)"; return 1 ;;
    *) SYNC_STEP_VERDICT=BLIND;             echo "[sync-upstreams] $mode: BLIND (exit $rc; nothing was decided)" ;;
  esac
  return 0
}
