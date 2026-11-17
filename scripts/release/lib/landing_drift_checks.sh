#!/usr/bin/env bash
# scripts/release/lib/landing_drift_checks.sh - the ONE list and runner of the derived-file drift
# checks that every landing path onto main must run (CON-144 recurrence, audit 2026-11-16 F5/F6;
# CON-443). Sourced, never run:
#   scripts/release/land_vehicle.sh        publish step 6b (vehicle bundles, fast-forward or merge)
#   scripts/release/pr_landing_check.sh    the pull-request landing path (section 11.4.297 merges)
# Both call ldc_run, so both run the same checks with the same rules; a new check is added here once.
#
# ldc_run <root> <base> <head> <evidence dir>
#   <root>  a clean working tree whose checked-out commit (refs/heads/main for the lander, a detached
#           HEAD for the PR check) is the landing candidate; the checks run there with --root <root>
#   <base>  the commit main had before the landing; <head> the landing candidate commit
#   A check is REQUIRED when its script is in the tree of <base> or of <head>. A required script that
#   is missing from <head> or from the working tree, a non-zero exit (2 = BLIND included) or a timeout
#   (DRIFT_TIMEOUT seconds) is a FAIL. After the checks the working tree must be clean and the
#   candidate ref must still point at <head>. Results go to <evidence dir>/drift_checks.tsv
#   (check, script, required, rc, result) and each check's output to drift_<check>.log.
#   Returns 0 when every required check passed, 1 otherwise.
# Callbacks the caller must define before calling ldc_run:
#   LDC_GIT   name of a function or command that runs git on <root> (the caller's hardened wrapper)
#   LDC_LOG   name of a function that prints one progress line
#   LDC_REF   the ref that must still equal <head> afterwards (refs/heads/main or HEAD)
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)

# DRIFT_CHECKS: name|repository-relative script|arguments.
DRIFT_CHECKS=(
  "badges|scripts/badges/compute_badges.sh|--check"
  "gate-env-allowlist|scripts/gates/cm_gate_env_reads_allowlisted.sh|"
)
DRIFT_TIMEOUT=900

ldc_run() {
  local root=$1 base=$2 head=$3 evdir=$4 tsv spec name path args req rc res bad=0
  tsv="$evdir/drift_checks.tsv"
  printf 'check\tscript\trequired\trc\tresult\n' > "$tsv"
  for spec in "${DRIFT_CHECKS[@]}"; do
    IFS='|' read -r name path args <<< "$spec"
    req=no
    if "$LDC_GIT" cat-file -e "$base:$path" 2>/dev/null || "$LDC_GIT" cat-file -e "$head:$path" 2>/dev/null; then req=yes; fi
    if [ "$req" = no ]; then
      printf '%s\t%s\tno\t-\tnot-applicable\n' "$name" "$path" >> "$tsv"; continue
    fi
    if ! "$LDC_GIT" cat-file -e "$head:$path" 2>/dev/null || [ ! -f "$root/$path" ]; then
      printf '%s\t%s\tyes\t-\tFAIL-script-missing\n' "$name" "$path" >> "$tsv"
      "$LDC_LOG" "drift check $name: FAIL (script $path is in the base but not in the landing candidate)"; bad=1; continue
    fi
    local -a argv=()
    [ -z "$args" ] || read -r -a argv <<< "$args"
    rc=0
    (cd "$root" && timeout "$DRIFT_TIMEOUT" bash "$root/$path" --root "$root" "${argv[@]}") \
      < /dev/null > "$evdir/drift_$name.log" 2>&1 9>&- || rc=$?
    if [ "$rc" -eq 0 ]; then res=PASS; else res=FAIL; bad=1; fi
    if [ "$rc" -eq 124 ]; then res=FAIL-timeout; fi
    printf '%s\t%s\tyes\t%s\t%s\n' "$name" "$path" "$rc" "$res" >> "$tsv"
    "$LDC_LOG" "drift check $name: $res (rc=$rc, log $evdir/drift_$name.log)"
  done
  [ -z "$("$LDC_GIT" status --porcelain --untracked-files=all --ignore-submodules=none)" ] \
    || { "$LDC_LOG" "drift checks changed the clone working tree"; bad=1; }
  [ "$("$LDC_GIT" rev-parse -q --verify "$LDC_REF" || true)" = "$head" ] \
    || { "$LDC_LOG" "landing candidate moved while the drift checks ran"; bad=1; }
  [ "$bad" -eq 0 ]
}
