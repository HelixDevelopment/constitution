#!/usr/bin/env bash
# make_con424_subset.sh — builds a runnable subset of the account-name mutation test that holds only its setup
# (lines up to the GREEN section) and the CON-424 section, so the RED baseline of the new cases can be shown
# on the gate before and after the fix. Usage: make_con424_subset.sh <repo-root> <out-file>
set -u -o pipefail
R="${1:?repo root}"; O="${2:?out file}"
T="$R/scripts/gates/cm_pr_delivery_account_name_free_mutation_test.sh"
s="$(grep -n '^# ── GREEN control' "$T" | cut -d: -f1)"; a="$(grep -n '^# ── CON-424' "$T" | cut -d: -f1)"; b="$(grep -n '^# ── SKIP and BLIND' "$T" | cut -d: -f1)"
[ -n "$s" ] && [ -n "$a" ] && [ -n "$b" ] || exit 2
{ sed -n "1,$((s - 1))p" "$T" | sed "s|^HERE=.*|HERE=\"$R/scripts/gates\"|"
  sed -n "${a},$((b - 1))p" "$T"
  echo 'say "subset: $NOK ok, RESULT=$RESULT"; exit "$RESULT"'; } >"$O"
