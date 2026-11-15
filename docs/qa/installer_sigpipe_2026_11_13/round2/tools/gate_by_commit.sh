#!/usr/bin/env bash
# gate_by_commit.sh REPO WORKDIR COMMIT... — runs each commit's own CM-INSTALLER-NO-PUSH-NO-FORCE gate on that
# commit's installer and updater, in a full `git archive` of that commit under WORKDIR/<commit>, and prints the
# verdict line and every finding. The files are passed as absolute paths: the runtime check (d) sources them from
# a temporary directory, so a relative path reports SOURCE-FAILED. The base commit passing is the control needle. Exit 0 always; the verdicts are the
# result.
set -u
repo="${1:?REPO}"; work="${2:?WORKDIR}"; shift 2
for c in "$@"; do
  full="$(git -C "$repo" rev-parse --verify "$c^{commit}")" || { echo "== $c: not a commit"; continue; }
  d="$work/${full:0:12}"; mkdir -p "$d"
  git -C "$repo" archive "$full" | tar -x -C "$d"
  echo "== ${full:0:12} $(git -C "$repo" log -1 --format=%s "$full" | cut -c1-90)"
  (cd "$d" && TMPDIR="$d" bash scripts/gates/cm_installer_no_push_no_force.sh \
     --file "$d/scripts/install_constitution.sh" --file "$d/scripts/update_constitution.sh" 2>&1)
  rc=$?
  echo "   exit=$rc"
done
exit 0
