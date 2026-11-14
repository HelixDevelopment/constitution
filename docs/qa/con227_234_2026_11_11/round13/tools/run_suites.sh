#!/usr/bin/env bash
# run_suites.sh REPO OUTDIR TMPROOT: run the six release suites one after another (hermetic environment is given by the
# caller with env -i), each with its own TMPDIR under TMPROOT; per suite: OUTDIR/<suite>.out and one line in
# OUTDIR/summary.tsv (suite, rc, seconds, PASS count, FAIL count, RESULT line, sha256 of the sorted PASS/FAIL/SKIP lines).
set -u
repo="${1:?repo}"; out="${2:?outdir}"; troot="${3:?tmproot}"
mkdir -p "$out" "$troot"
cd "$repo" || exit 2
: >"$out/summary.tsv"
for s in test_redact_cut test_channel_census test_derive_release_facts test_publish_gitea test_tag_and_release test_render_release_entry; do
  t="$(mktemp -d "$troot/$s.XXXXXX")"; : "${t:?}"
  t0=$(date +%s)
  TMPDIR="$t" bash "tests/release/$s.sh" >"$out/$s.out" 2>&1; rc=$?
  p=$(grep -c '^PASS' "$out/$s.out"); f=$(grep -c '^FAIL' "$out/$s.out")
  res="$(grep -E '^RESULT' "$out/$s.out" | tail -n 1)"
  h="$(grep -E '^(PASS|FAIL|SKIP)' "$out/$s.out" | LC_ALL=C sort | sha256sum | cut -c1-16)"
  printf '%s\t%s\t%ss\t%s\t%s\t%s\t%s\n' "$s" "$rc" "$(( $(date +%s) - t0 ))" "$p" "$f" "$res" "$h" >>"$out/summary.tsv"
done
echo DONE >>"$out/summary.tsv"
