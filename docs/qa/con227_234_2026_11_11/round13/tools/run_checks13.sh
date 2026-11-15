#!/usr/bin/env bash
# run_checks13.sh REPO OUT: the round-13 checks other than the suites, written to OUT (which must not exist):
#   golden_netgate_{normalpath,emptypath}.txt   netgate --pin --sites on the four release files, both PATHs (+ cmp)
#   lint_{normalpath,emptypath}.txt             the census lint on channels.tsv, both PATHs (+ cmp)
#   lint output of shellcheck (file shellcheck.txt): -S warning on the release scripts, env_allow.sh, 7 suites
#   pyright.txt                                 pyright on channel_census.py and env_census.py
#   verify_manifest.txt                         scripts/run_full_suite.sh --verify-manifest
#   gate_ledger_ratchet.txt                     scripts/gates/cm_gate_ledger_ratchet.sh
#   checks.tsv                                  one line per check: name, rc, the line that states the result
# Nothing outside OUT is written; the caller gives the hermetic scope (systemd-run, nice).
set -u
R="$(cd "${1:?REPO}" && pwd)"; OUT="${2:?OUT}"
[ -e "$OUT" ] && { echo "refusing: $OUT exists" >&2; exit 2; }
mkdir -p "$OUT" || exit 2
cd "$R" || exit 2
PY3="$(command -v python3)"; : "${PY3:?python3}"
CEN=tests/release/channel_census.py
S=(scripts/release/derive_release_facts.sh scripts/release/redact_cut.sh scripts/release/tag_and_release.sh scripts/release_publish_gitea.sh)
rec() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >>"$OUT/checks.tsv"; }

env -i PATH=/usr/local/bin:/usr/bin:/bin LANG=C.UTF-8 "$PY3" -I "$CEN" netgate --pin tests/release/netgate_pin.tsv --sites "${S[@]}" >"$OUT/golden_netgate_normalpath.txt" 2>&1; r1=$?
env -i PATH=/nonexistent LANG=C.UTF-8 "$PY3" -I "$CEN" netgate --pin tests/release/netgate_pin.tsv --sites "${S[@]}" >"$OUT/golden_netgate_emptypath.txt" 2>&1; r2=$?
if cmp -s "$OUT/golden_netgate_normalpath.txt" "$OUT/golden_netgate_emptypath.txt"; then same=identical; else same=DIFFERENT; fi
rec golden_netgate "$r1/$r2" "$(tail -n 1 "$OUT/golden_netgate_normalpath.txt") sites=$(grep -c '^SITE' "$OUT/golden_netgate_normalpath.txt") findings_lines=$(grep -c '^FINDING' "$OUT/golden_netgate_normalpath.txt") both_paths=$same"

env -i PATH=/usr/local/bin:/usr/bin:/bin LANG=C.UTF-8 "$PY3" -I "$CEN" lint tests/release/channels.tsv "${S[@]}" >"$OUT/lint_normalpath.txt" 2>&1; r1=$?
env -i PATH=/nonexistent LANG=C.UTF-8 "$PY3" -I "$CEN" lint tests/release/channels.tsv "${S[@]}" >"$OUT/lint_emptypath.txt" 2>&1; r2=$?
if cmp -s "$OUT/lint_normalpath.txt" "$OUT/lint_emptypath.txt"; then same=identical; else same=DIFFERENT; fi
rec lint "$r1/$r2" "$(tail -n 1 "$OUT/lint_normalpath.txt") both_paths=$same"

SC=("${S[@]}" tests/release/env_allow.sh tests/release/test_redact_cut.sh tests/release/test_channel_census.sh
    tests/release/test_derive_release_facts.sh tests/release/test_publish_gitea.sh tests/release/test_tag_and_release.sh
    tests/release/test_render_release_entry.sh tests/release/test_release_tooling_mutations.sh)
{ shellcheck --version | sed -n '2p'; printf 'files=%s\n' "${#SC[@]}"; shellcheck -S warning "${SC[@]}"; echo "rc=$?"; } >"$OUT/shellcheck.txt" 2>&1
rec shellcheck "$(tail -n 1 "$OUT/shellcheck.txt" | cut -d= -f2)" "$(sed -n '1,2p' "$OUT/shellcheck.txt" | tr '\n' ' ')output_lines=$(( $(wc -l <"$OUT/shellcheck.txt") - 3 ))"

{ pyright --version; pyright tests/release/channel_census.py tests/release/env_census.py; echo "rc=$?"; } >"$OUT/pyright.txt" 2>&1
rec pyright "$(tail -n 1 "$OUT/pyright.txt" | cut -d= -f2)" "$(grep -E '[0-9]+ errors?' "$OUT/pyright.txt" | tail -n 1)"

bash scripts/run_full_suite.sh --verify-manifest >"$OUT/verify_manifest.txt" 2>&1; r=$?
rec verify_manifest "$r" "$(grep -E '^RESULT' "$OUT/verify_manifest.txt" | tail -n 1)"

bash scripts/gates/cm_gate_ledger_ratchet.sh >"$OUT/gate_ledger_ratchet.txt" 2>&1; r=$?
rec gate_ledger_ratchet "$r" "$(grep -E '^LEDGER' "$OUT/gate_ledger_ratchet.txt" | tail -n 1)"
echo DONE >>"$OUT/checks.tsv"
