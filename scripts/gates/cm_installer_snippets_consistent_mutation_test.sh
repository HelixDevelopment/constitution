#!/usr/bin/env bash
# cm_installer_snippets_consistent_mutation_test.sh — §1.1 paired-mutation meta-test for CM-INSTALLER-SNIPPETS-CONSISTENT.
#
# Golden: the real installer PASSES; with a docs root holding only canonical URLs and a web (non-raw) link it PASSES.
# Mutants on scratch copies (the real file is never touched) MUST FAIL (exit 1):
#   M1 one upstream URL altered · M2 snippet format changed to `| sh` · M3 a duplicate snippet line
#   M4 a doc carrying a non-canonical raw URL
# Usage: cm_installer_snippets_consistent_mutation_test.sh   Exit 0 proof holds · 1 survivor · 2 env error.
# Classification: universal (§11.4.17).
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
gate="$here/cm_installer_snippets_consistent.sh"; inst="$here/../install_constitution.sh"
[ -r "$gate" ] && [ -r "$inst" ] || { echo "META: gate or installer missing" >&2; exit 2; }
tmp="$(mktemp -d "${TMPDIR:-/tmp}/cm_snip_meta.XXXXXX")" || exit 2
trap 'rm -f -- "${tmp:?}"/*.sh "${tmp:?}"/good/*.md "${tmp:?}"/bad/*.md; rmdir -- "${tmp:?}/good" "${tmp:?}/bad" "${tmp:?}"' EXIT
mkdir "$tmp/good" "$tmp/bad"
bad=0
expect() { # name want-rc args...
  local n="$1" w="$2"; shift 2; bash "$gate" "$@" >/dev/null 2>&1; local rc=$?
  if [ "$rc" = "$w" ]; then echo "  ok   $n (rc=$rc)"; else echo "  FAIL $n (want rc=$w got $rc)"; bad=$((bad+1)); fi
}
applied() { cmp -s "$inst" "$1" && { echo "  FAIL mutation $2 did not apply"; bad=$((bad+1)); }; }
GH='https://raw.githubusercontent.com/HelixDevelopment/HelixConstitution/main/scripts/install_constitution.sh'
printf 'Install:\n\n    curl -fsSL %s | bash\n\nSee https://github.com/HelixDevelopment/HelixConstitution/blob/main/scripts/install_constitution.sh\n' "'$GH'" >"$tmp/good/a.md"
printf 'curl -fsSL https://raw.githubusercontent.com/HelixDevelopment/HelixConstitution/master/scripts/install_constitution.sh | bash\n' >"$tmp/bad/b.md"
expect "golden real installer PASS" 0 --installer "$inst"
expect "golden-FALSE: docs with canonical raw + web link PASS" 0 --installer "$inst" --docs-root "$tmp/good"
sed 's#gitverse.ru/api/repos/helixdevelopment#gitverse.ru/api/repos/someoneelse#' "$inst" >"$tmp/m1.sh"; applied "$tmp/m1.sh" M1
expect "M1 altered upstream URL -> FAIL" 1 --installer "$tmp/m1.sh"
sed "s/printf \"curl -fsSL '%s' | bash\\\\n\"/printf \"curl -fsSL '%s' | sh\\\\n\"/" "$inst" >"$tmp/m2.sh"
applied "$tmp/m2.sh" M2
expect "M2 snippet piped to sh -> FAIL" 1 --installer "$tmp/m2.sh"
awk '{ print } /^hi_print_snippets\(\) \{/ { print "  hi_upstream_table | head -n 1 | cut -d\"|\" -f2 | sed \"s/.*/curl -fsSL \x27&\x27 | bash/\"" }' "$inst" >"$tmp/m3.sh"; applied "$tmp/m3.sh" M3
expect "M3 duplicate snippet line -> FAIL" 1 --installer "$tmp/m3.sh"
expect "M4 doc with non-canonical raw URL -> FAIL" 1 --installer "$inst" --docs-root "$tmp/bad"
[ "$bad" = 0 ] && echo "META PASS: CM-INSTALLER-SNIPPETS-CONSISTENT kills every mutant" || echo "META FAIL: $bad case(s)"
[ "$bad" = 0 ]
