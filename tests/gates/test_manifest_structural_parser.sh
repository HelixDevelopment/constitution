#!/usr/bin/env bash
# tests/gates/test_manifest_structural_parser.sh -- review round 4 (11.4.276): ONE real-YAML parser
# (scripts/deps_manifest/helix_deps_tsv.py) feeds BOTH hand-parser replacements:
#   scripts/lib/third_party_prune.sh (prune)  and  scripts/gates/cm_helix_deps_ref_matches_gitlink.sh (ref gate).
# REAL invocation path, no doubles. Hostile shapes: bare-dash item, quoted key, `key :`, duplicate keys,
# flow style, `deps: []`, CRLF, tab indentation, anchors, multi-document, no-PyYAML (test env switch).
# Fail-closed expectations: prune -> literal names only (scan MORE); ref gate -> BLIND (rc 2) / DRIFT, never PASS.
# Paired mutants: MUTANT_HAND=1 (hand parse), MUTANT_DUP=1 (dup keys accepted), MUTANT_PASS=1 (PASS on parser failure)
# are applied to sandbox COPIES of the real files and MUST make this suite fail (run with --mutants).
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
canon="$(cd "$here/../.." && pwd)"
sb="$(mktemp -d)"; : "${sb:?}"; trap 'rm -rf -- "${sb:?}"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "PASS $1"; }
bad() { fail=$((fail+1)); echo "FAIL $1"; }
LIBROOT="${TEST_CANON:-$canon}"
# shellcheck disable=SC1091
. "$LIBROOT/scripts/lib/third_party_prune.sh"
GATE="$LIBROOT/scripts/gates/cm_helix_deps_ref_matches_gitlink.sh"
LIT="site-packages third_party "

prune() { # dir -> sorted one-line list
    cm_third_party_prune_paths "$1" 2>/dev/null | LC_ALL=C sort | tr '\n' ' '
}
mk() { # name content(printf fmt) -> dir with helix-deps.yaml
    local d="$sb/p_$1" p; mkdir -p "$d"; printf "$2" > "$d/helix-deps.yaml"
    # a manifest mark only prunes a RECORDED gitlink (review round 3): record the candidate paths as gitlinks in a real repo
    env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git -C "$d" init -q . 2>/dev/null
    for p in submodules/vend src; do
        env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git -C "$d" update-index --add --cacheinfo "160000,0123456789abcdef0123456789abcdef01234567,$p" 2>/dev/null
    done
    echo "$d"
}
expect_prune() { # desc want dir
    local got; got="$(prune "$3")"
    if [ "$got" = "$2" ]; then ok "prune: $1"; else bad "prune: $1 -- got '$got' want '$2'"; fi
}

echo "== prune consumer =="
GOOD='schema_version: 1\ndeps:\n  - name: keep\n    path: src\n    third_party: false\n  - name: vend\n    third_party: true\n'
expect_prune "control well-formed" "site-packages submodules/vend third_party " "$(mk good "$GOOD")"
expect_prune "F1 bare-dash item" "site-packages submodules/vend third_party " \
  "$(mk bare 'schema_version: 1\ndeps:\n  - name: keep\n    path: src\n    third_party: false\n  -\n    name: vend\n    third_party: true\n')"
expect_prune "F1 quoted key" "site-packages submodules/vend third_party " \
  "$(mk quoted 'schema_version: 1\ndeps:\n  - name: keep\n    path: src\n    third_party: false\n  - "name": vend\n    third_party: true\n')"
expect_prune "F1 space before colon" "site-packages submodules/vend third_party " \
  "$(mk spc 'schema_version: 1\ndeps:\n  - name: keep\n    path: src\n    third_party: false\n  - name : vend\n    third_party : true\n')"
expect_prune "F3 duplicate key -> literals only" "$LIT" \
  "$(mk dup 'schema_version: 1\ndeps:\n  - name: a\n    path: src\n    third_party: true\n    third_party: false\n')"
expect_prune "flow-style deps -> literals only (cross-check)" "$LIT" \
  "$(mk flow 'schema_version: 1\ndeps: [{name: a, path: src, third_party: true}]\n')"
expect_prune "deps: [] -> literals only" "$LIT" "$(mk empty 'schema_version: 1\ndeps: []\n')"
expect_prune "CRLF well-formed" "site-packages submodules/vend third_party " \
  "$(mk crlf 'schema_version: 1\r\ndeps:\r\n  - name: keep\r\n    path: src\r\n    third_party: false\r\n  - name: vend\r\n    third_party: true\r\n')"
expect_prune "tab indentation -> literals only" "$LIT" \
  "$(mk tab 'schema_version: 1\ndeps:\n\t- name: a\n\t  path: src\n\t  third_party: true\n')"
expect_prune "anchor/alias" "site-packages submodules/vend third_party " \
  "$(mk anch 'schema_version: 1\ndeps:\n  - &d\n    name: vend\n    third_party: "true"\n  - name: keep\n    path: src\n    third_party: false\n')"
expect_prune "multi-document -> literals only" "$LIT" \
  "$(mk multi 'schema_version: 1\ndeps: []\n---\ndeps:\n  - name: a\n    path: src\n    third_party: true\n')"
expect_prune "deps not a list -> literals only" "$LIT" "$(mk scal 'schema_version: 1\ndeps: nope\n')"
d="$(mk noyaml "$GOOD")"
got="$(HELIX_TEST_MODE=1 HELIX_DEPS_TSV_FORCE_NO_YAML=1 prune "$d")"
[ "$got" = "$LIT" ] && ok "prune: no-PyYAML (switch) -> literals only (safe direction)" || bad "prune: no-PyYAML -> '$got'"
err="$(HELIX_TEST_MODE=1 HELIX_DEPS_TSV_FORCE_NO_YAML=1 cm_third_party_prune_paths "$d" 2>&1 >/dev/null)"
case "$err" in *PyYAML*|*helix_deps_tsv*) ok "prune: no-PyYAML prints a stderr note" ;; *) bad "prune: no stderr note ('$err')" ;; esac

# F5 (known-failures follow-up): nested-list fixtures. A nested list inside a dep must not break
# the parse, and a nested mapping carrying its own name/path/third_party must NOT be read as a dep.
expect_prune "F5 nested scalar list inside a dep is ignored, dep still parsed" "site-packages src third_party " \
  "$(mk nl1 'schema_version: 1\ndeps:\n  - name: vend\n    path: src\n    third_party: true\n    tags:\n      - a\n      - b\n  - name: keep\n    path: k\n    third_party: false\n')"
expect_prune "F5 nested list of mappings: inner third_party/path NOT promoted to a dep" "site-packages src third_party " \
  "$(mk nl2 'schema_version: 1\ndeps:\n  - name: vend\n    path: src\n    third_party: true\n    children:\n      - name: inner\n        path: deep\n        third_party: true\n  - name: keep\n    path: k\n    third_party: false\n')"

echo "== ref gate consumer =="
G=(git -c user.email=t@t -c user.name=t -c init.defaultBranch=main)
HEXA=0123456789abcdef0123456789abcdef01234567; HEXB=89abcdef0123456789abcdef0123456789abcdef
mkref() { # name manifest-printf-fmt -> root
    local r="$sb/r_$1"; "${G[@]}" init -q "$r"
    printf '[submodule "a"]\n\tpath = submodules/a\n\turl = git@x:o/a.git\n[submodule "b"]\n\tpath = submodules/b\n\turl = git@x:o/b.git\n' > "$r/.gitmodules"
    "${G[@]}" -C "$r" update-index --add --cacheinfo "160000,$HEXA,submodules/a"
    "${G[@]}" -C "$r" update-index --add --cacheinfo "160000,$HEXB,submodules/b"
    printf "$2" > "$r/helix-deps.yaml"; echo "$r"
}
expect_gate() { # desc wantrc root [envassign]
    local rc; env ${4:-X=1} bash "$GATE" --root "$3" >/dev/null 2>&1; rc=$?
    if [ "$rc" = "$2" ]; then ok "ref-gate: $1 (rc $rc)"; else bad "ref-gate: $1 -- rc $rc want $2"; fi
}
A_OK='  - name: a\n    ssh_url: git@x:o/a.git\n    ref: 0123456\n'
A_DR='  - name: a\n    ssh_url: git@x:o/a.git\n    ref: 0123457\n'
B_OK='    name: b\n    ssh_url: git@x:o/b.git\n    ref: 89abcde\n'
expect_gate "control both match" 0 "$(mkref ok "deps:\n$A_OK  - name: b\n    ssh_url: git@x:o/b.git\n    ref: 89abcde\n")"
expect_gate "control drift detected" 1 "$(mkref dr "deps:\n$A_DR  - name: b\n    ssh_url: git@x:o/b.git\n    ref: 89abcde\n")"
expect_gate "F2 bare-dash dep must not hide a's drift" 1 "$(mkref bare "deps:\n$A_DR  -\n$B_OK")"
expect_gate "F2 quoted key dep must not hide a's drift" 1 "$(mkref quo "deps:\n$A_DR  - \"name\": b\n    ssh_url: git@x:o/b.git\n    ref: 89abcde\n")"
expect_gate "F2 space-before-colon fields parsed (drift seen)" 1 "$(mkref spc "deps:\n  - name : a\n    ssh_url : git@x:o/a.git\n    ref : 0123457\n  - name: b\n    ssh_url: git@x:o/b.git\n    ref: 89abcde\n")"
expect_gate "F3 duplicate key -> BLIND" 2 "$(mkref dup "deps:\n  - name: a\n    ssh_url: git@x:o/a.git\n    ref: 0123456\n    ref: 0123457\n  - name: b\n    ssh_url: git@x:o/b.git\n    ref: 89abcde\n")"
expect_gate "F5 nested list inside a dep: ref still compared (drift seen)" 1 "$(mkref nl "deps:\n  - name: a\n    ssh_url: git@x:o/a.git\n    ref: 0123457\n    tags:\n      - x\n  - name: b\n    ssh_url: git@x:o/b.git\n    ref: 89abcde\n")"
expect_gate "F5 nested list inside a dep: match -> 0" 0 "$(mkref nlok "deps:\n  - name: a\n    ssh_url: git@x:o/a.git\n    ref: 0123456\n    tags:\n      - x\n  - name: b\n    ssh_url: git@x:o/b.git\n    ref: 89abcde\n")"
expect_gate "flow-style deps -> BLIND" 2 "$(mkref flow "deps: [{name: a, ssh_url: 'git@x:o/a.git', ref: '0123456'}]\n")"
expect_gate "deps: [] -> BLIND" 2 "$(mkref empty "deps: []\n")"
expect_gate "CRLF well-formed -> 0" 0 "$(mkref crlf "deps:\r\n  - name: a\r\n    ssh_url: git@x:o/a.git\r\n    ref: 0123456\r\n  - name: b\r\n    ssh_url: git@x:o/b.git\r\n    ref: 89abcde\r\n")"
expect_gate "tab indentation -> BLIND" 2 "$(mkref tab "deps:\n\t- name: a\n\t  ssh_url: git@x:o/a.git\n\t  ref: 0123456\n")"
expect_gate "anchors well-formed -> 0" 0 "$(mkref anch "deps:\n  - &d\n    name: a\n    ssh_url: git@x:o/a.git\n    ref: 0123456\n  - name: b\n    ssh_url: git@x:o/b.git\n    ref: 89abcde\n")"
expect_gate "multi-document -> BLIND" 2 "$(mkref multi "deps: []\n---\ndeps:\n$A_OK")"
expect_gate "no-PyYAML (switch) -> BLIND, never PASS" 2 "$(mkref noy "deps:\n$A_OK  - name: b\n    ssh_url: git@x:o/b.git\n    ref: 89abcde\n")" "HELIX_TEST_MODE=1 HELIX_DEPS_TSV_FORCE_NO_YAML=1"

echo "== control chars / separators in values (round 5: M-1, M-2) =="
SAFE="site-packages submodules/vend third_party "
expect_prune "M-1 NUL in path (third_party true) must not emit src" "$LIT" \
  "$(mk nul 'schema_version: 1\ndeps:\n  - name: vend\n    path: "src\\0"\n    third_party: true\n')"
expect_prune "M-1 DEL in path" "$LIT" \
  "$(mk del 'schema_version: 1\ndeps:\n  - name: vend\n    path: "src\\x7f"\n    third_party: true\n')"
expect_prune "M-1 other C0 (BEL) in path" "$LIT" \
  "$(mk bel 'schema_version: 1\ndeps:\n  - name: vend\n    path: "src\\a"\n    third_party: true\n')"
expect_prune "M-2 \\n escape in value" "$LIT" \
  "$(mk esc_n 'schema_version: 1\ndeps:\n  - name: vend\n    path: "src\\nx"\n    third_party: true\n')"
expect_prune "M-2 US separator escape in value" "$LIT" \
  "$(mk esc_us 'schema_version: 1\ndeps:\n  - name: vend\n    path: "src\\x1fx"\n    third_party: true\n')"
expect_prune "M-2 CR escape in value" "$LIT" \
  "$(mk esc_cr 'schema_version: 1\ndeps:\n  - name: vend\n    path: "src\\rx"\n    third_party: true\n')"
expect_prune "M-2 literal block scalar (embedded newline)" "$LIT" \
  "$(mk blk 'schema_version: 1\ndeps:\n  - name: vend\n    path: |\n      src\n      x\n    third_party: true\n')"
expect_prune "M-2 US+LF forging a second record in one value" "$LIT" \
  "$(mk forge 'schema_version: 1\ndeps:\n  - name: vend\n    path: "a\\x1fb\\x1fc\\x1fd\\x1f1\\nz"\n    third_party: true\n')"
# the parser itself must exit 6 (not just fall back)
for shape in 'src\\0' 'src\\nx' 'src\\x1fx' 'src\\rx'; do
    d="$(mk "rc6_$(printf '%s' "$shape" | tr -c 'a-z0-9' _)" "schema_version: 1\ndeps:\n  - name: v\n    path: \"$shape\"\n    third_party: true\n")"
    HELIX_TEST_MODE=1 python3 -I "$LIBROOT/scripts/deps_manifest/helix_deps_tsv.py" "$d/helix-deps.yaml" >/dev/null 2>&1; rc=$?
    [ "$rc" = 6 ] && ok "tsv.py rc 6 for value '$shape'" || bad "tsv.py rc $rc (want 6) for '$shape'"
done
expect_gate "M-2 ref gate: newline in ref value -> BLIND" 2 "$(mkref ctl "deps:\n  - name: a\n    ssh_url: git@x:o/a.git\n    ref: \"0123456\\\\nx\"\n  - name: b\n    ssh_url: git@x:o/b.git\n    ref: 89abcde\n")"

echo "== test overrides are NOT honoured in production (round 5: M-3) =="
printf 'import sys\nsys.exit(4)\n' > "$sb/evil.py"
d="$(mk ovr "$GOOD")"
want="$(prune "$d")"
got="$(HELIX_DEPS_TSV_PY="$sb/evil.py" prune "$d")"
[ "$got" = "$want" ] && [ "$want" != "$LIT" ] && ok "override HELIX_DEPS_TSV_PY ignored without HELIX_TEST_MODE (real parser used)" || bad "override honoured without test mode: '$got' vs '$want'"
err="$(HELIX_DEPS_TSV_PY="$sb/evil.py" cm_third_party_prune_paths "$d" 2>&1 >/dev/null)"
case "$err" in *ignoring*HELIX_DEPS_TSV_PY*) ok "ignored override prints a stderr note" ;; *) bad "no stderr note for ignored override ('$err')" ;; esac
got="$(HELIX_TEST_MODE=1 HELIX_DEPS_TSV_PY="$sb/evil.py" prune "$d")"
[ "$got" = "$LIT" ] && ok "override honoured with HELIX_TEST_MODE=1 under the temp root" || bad "guarded override not honoured: '$got'"
got="$(HELIX_TEST_MODE=1 HELIX_DEPS_TSV_PY="/nonexistent_dir_x/evil.py" prune "$d")"
[ "$got" = "$want" ] && ok "override outside the temp root ignored even in test mode" || bad "outside-temp override honoured: '$got'"
got="$(HELIX_DEPS_TSV_FORCE_NO_YAML=1 prune "$d")"
[ "$got" = "$want" ] && ok "FORCE_NO_YAML ignored without HELIX_TEST_MODE (real parse)" || bad "FORCE_NO_YAML honoured without test mode: '$got'"

echo "== no remaining hand-written parser =="
if grep -nE "third_party:|\^\[\[:space:\]\]\*-|/\^  - \[A-Za-z_\]" "$LIBROOT/scripts/lib/third_party_prune.sh" "$GATE" | grep -v '^\S*:[0-9]*:\s*#' | grep -q .; then
    bad "hand-parse residue in prune lib or ref gate"; else ok "no hand-parse residue in prune lib / ref gate"; fi

echo "== $pass passed, $fail failed =="
[ "$fail" = 0 ]
