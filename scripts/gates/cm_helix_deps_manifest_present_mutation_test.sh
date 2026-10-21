#!/usr/bin/env bash
# cm_helix_deps_manifest_present_mutation_test.sh — §1.1 paired-mutation meta-test for CM-HELIX-DEPS-MANIFEST-PRESENT.
#
# ── Purpose ───────────────────────────────────────────────────────────────
# Part 1 — fixture classification (throwaway git trees only; the real repo is never touched):
#   PASS-expected : CLEAN (root + own-org leaf with manifests; third-party leaf WITHOUT one = golden-FALSE)
#                   · HUB-CLEAN (constitution/submodules/x own-org with a manifest)
#                   · SYMLINK-LEAF (an own-org leaf that is a symlink to a real checkout)
#   FAIL-expected : MISSING-LEAF · MISSING-ROOT · MALFORMED (https ssh_url) · UNTRACKED · UNDECLARED
#                   · NESTED-OWNORG · HUB-LEAF-MISSING · HUBNAME-NESTED (someone/constitution.git nested in a leaf)
#                   · CONFLICT-RES (conflict_resolution other than operator-required)
#                   · REL-NESTED-OWN (a leaf nests ../Containers.git, which resolves to its own organisation)
#   BLIND-expected: UNINIT (own-org leaf declared but not checked out) · ENGINE-MISSING
#                   · EMPTY-GITDIR (own-org leaf directory holding only an empty .git directory: not a checkout)
#                   · REL-ROOT-UNRES (a root-level relative URL with no root remote to resolve it against)
# Part 2 — engine mutants: the engine is copied to a scratch dir, one defect is injected per mutant, and the
#   gate is pointed at it through HELIX_DEPS_ENGINE. Each mutant MUST change at least one fixture verdict
#   (i.e. be KILLED); a surviving mutant means the gate cannot see that defect class.
#
# ── Usage ─────────────────────────────────────────────────────────────────
#   cm_helix_deps_manifest_present_mutation_test.sh   Exit: 0 proof holds · 1 misclassified/survivor · 2 env error.
# Side-effects: temp dir under $TMPDIR (trap-cleaned). Dependencies: bash, git, python3 + PyYAML, sed.
# Classification: universal (§11.4.17).
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
gate="$here/cm_helix_deps_manifest_present.sh"
engdir="$(cd "$here/../deps_manifest" 2>/dev/null && pwd)" || { echo "META: engine dir missing" >&2; exit 2; }
[ -r "$gate" ] || { echo "META: gate missing" >&2; exit 2; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset HELIX_OWN_ORGS HELIX_DEPS_ENGINE
bad=0

man() { # [own-org dep names...]
  printf 'schema_version: 1\n'
  if [ $# -eq 0 ]; then printf 'deps: []\n'; else printf 'deps:\n'; fi
  local d; for d in "$@"; do
    printf '  - name: %s\n    ssh_url: git@github.com:vasic-digital/%s.git\n    ref: abc1234\n    why: "needed"\n    layout: grouped\n' "$d" "$d"
  done
  printf 'transitive_handling:\n  recursive: true\n  conflict_resolution: operator-required\nlanguage_specific_subtree: false\n'
}
repo() { # dir manifest|-
  mkdir -p "$1"; git -C "$1" init -q
  [ "$2" = "-" ] || { printf '%s\n' "$2" >"$1/helix-deps.yaml"; git -C "$1" add helix-deps.yaml; }
  echo x >"$1/f"; git -C "$1" add f; git -C "$1" commit -q -m i
}
sm() { git -C "$1" config -f "$1/.gitmodules" "submodule.$2.path" "$2"; git -C "$1" config -f "$1/.gitmodules" "submodule.$2.url" "$3"; }
tree() { # dir — clean fixture
  repo "$1/submodules/a" "$(man)"; repo "$1/submodules/tp" -
  repo "$1" "$(man a)"; sm "$1" submodules/a git@github.com:vasic-digital/a.git; sm "$1" submodules/tp git@github.com:someone/tp.git
}
build_fixtures() { # base-dir
  local b="$1"
  tree "$b/CLEAN"
  tree "$b/HUB-CLEAN"; repo "$b/HUB-CLEAN/constitution/submodules/x" "$(man)"; repo "$b/HUB-CLEAN/constitution" "$(man x)"
  sm "$b/HUB-CLEAN/constitution" submodules/x git@github.com:vasic-digital/x.git
  sm "$b/HUB-CLEAN" constitution git@github.com:HelixDevelopment/HelixConstitution.git
  tree "$b/MISSING-LEAF"; git -C "$b/MISSING-LEAF/submodules/a" rm -q helix-deps.yaml
  tree "$b/MISSING-ROOT"; git -C "$b/MISSING-ROOT" rm -q helix-deps.yaml
  tree "$b/MALFORMED"; sed -i 's#git@github.com:vasic-digital/a.git#https://github.com/vasic-digital/a.git#' "$b/MALFORMED/helix-deps.yaml"
  tree "$b/UNTRACKED"; git -C "$b/UNTRACKED/submodules/a" rm -q --cached helix-deps.yaml
  tree "$b/UNDECLARED"; man >"$b/UNDECLARED/helix-deps.yaml"
  tree "$b/NESTED-OWNORG"; sm "$b/NESTED-OWNORG/submodules/a" submodules/y git@github.com:HelixDevelopment/y.git
  tree "$b/HUB-LEAF-MISSING"; repo "$b/HUB-LEAF-MISSING/constitution/submodules/x" -; repo "$b/HUB-LEAF-MISSING/constitution" "$(man x)"
  sm "$b/HUB-LEAF-MISSING/constitution" submodules/x git@github.com:vasic-digital/x.git
  sm "$b/HUB-LEAF-MISSING" constitution git@github.com:HelixDevelopment/HelixConstitution.git
  tree "$b/URL-HTTPS-TP"; repo "$b/URL-HTTPS-TP/submodules/h" -; sm "$b/URL-HTTPS-TP" submodules/h https://go.googlesource.com/go
  tree "$b/URL-SSHURL-TP"; repo "$b/URL-SSHURL-TP/submodules/h" -; sm "$b/URL-SSHURL-TP" submodules/h ssh://git@example.org:2222/someone/h.git
  tree "$b/URL-HTTPS-OWN-UNINIT"; sm "$b/URL-HTTPS-OWN-UNINIT" submodules/b https://github.com/vasic-digital/b.git; man a b >"$b/URL-HTTPS-OWN-UNINIT/helix-deps.yaml"
  tree "$b/URL-UNPARSEABLE"; repo "$b/URL-UNPARSEABLE/submodules/h" -; sm "$b/URL-UNPARSEABLE" submodules/h ftp://example.org/o/r.git
  tree "$b/UNINIT"; sm "$b/UNINIT" submodules/b git@github.com:vasic-digital/b.git; man a b >"$b/UNINIT/helix-deps.yaml"
  tree "$b/HUBNAME-NESTED"; sm "$b/HUBNAME-NESTED/submodules/a" submodules/k git@github.com:someone/constitution.git
  tree "$b/CONFLICT-RES"; sed -i 's#conflict_resolution: operator-required#conflict_resolution: auto-merge#' "$b/CONFLICT-RES/helix-deps.yaml"
  tree "$b/EMPTY-GITDIR"; mkdir -p "$b/EMPTY-GITDIR/submodules/b/.git"; sm "$b/EMPTY-GITDIR" submodules/b git@github.com:vasic-digital/b.git
  man a b >"$b/EMPTY-GITDIR/helix-deps.yaml"
  tree "$b/SYMLINK-LEAF"; repo "$b/SYMLINK-LEAF-target" "$(man)"; ln -s "$b/SYMLINK-LEAF-target" "$b/SYMLINK-LEAF/submodules/b"
  sm "$b/SYMLINK-LEAF" submodules/b git@github.com:vasic-digital/b.git; man a b >"$b/SYMLINK-LEAF/helix-deps.yaml"
  tree "$b/REL-NESTED-OWN"; sm "$b/REL-NESTED-OWN/submodules/a" submodules/c ../Containers.git
  tree "$b/REL-ROOT-UNRES"; repo "$b/REL-ROOT-UNRES/submodules/h" "$(man)"; sm "$b/REL-ROOT-UNRES" submodules/h ../h.git
}
EXPECT="CLEAN:0 HUB-CLEAN:0 MISSING-LEAF:1 MISSING-ROOT:1 MALFORMED:1 UNTRACKED:1 UNDECLARED:1 NESTED-OWNORG:1 HUB-LEAF-MISSING:1 URL-HTTPS-TP:0 URL-SSHURL-TP:0 URL-HTTPS-OWN-UNINIT:2 URL-UNPARSEABLE:2 UNINIT:2 HUBNAME-NESTED:1 CONFLICT-RES:1 EMPTY-GITDIR:2 SYMLINK-LEAF:0 REL-NESTED-OWN:1 REL-ROOT-UNRES:2"
classify() { # engine-path -> prints "LABEL:rc ..." for every fixture
  local e="$1" pair lab res=""
  for pair in $EXPECT; do
    lab="${pair%%:*}"
    HELIX_DEPS_ENGINE="$e" bash "$gate" --root "$tmp/fx/$lab" >/dev/null 2>&1
    res+="$lab:$? "
  done
  printf '%s\n' "${res% }"
}
build_fixtures "$tmp/fx"

echo "── Part 1: fixture classification with the real engine"
got="$(classify "$engdir/verify_helix_deps_manifests.sh")"
for pair in $EXPECT; do
  if [[ " $got " == *" $pair "* ]]; then echo "ok   $pair"; else echo "BAD  expected $pair, got: $got"; bad=1; fi
done
HELIX_DEPS_ENGINE="$tmp/no-such-engine.sh" bash "$gate" --root "$tmp/fx/CLEAN" >/dev/null 2>&1; rc=$?
if [ "$rc" = 2 ]; then echo "ok   ENGINE-MISSING:2"; else echo "BAD  ENGINE-MISSING expected 2 got $rc"; bad=1; fi
out="$(bash "$gate" --root "$tmp/fx/CLEAN" 2>&1)"
if grep -q 'SKIP(third_party)'$'\t''submodules/tp' <<<"$out" && ! grep -q '^PASS'$'\t''submodules/tp' <<<"$out"; then
  echo "ok   GOLDEN-FALSE third-party leaf without manifest is SKIP(third_party), not FAIL, not PASS"
else echo "BAD  GOLDEN-FALSE third-party classification"; bad=1; fi

echo "── Part 2: engine mutants (each MUST be killed)"
mutant() { # label sed-expression
  local m="$tmp/mut/$1"; mkdir -p "$m"; cp "$engdir"/* "$m/"
  sed -i "$2" "$m/helix_deps_manifest.py"
  if cmp -s "$m/helix_deps_manifest.py" "$engdir/helix_deps_manifest.py"; then echo "BAD  mutant $1 did not apply"; bad=1; return; fi
  local r; r="$(classify "$m/verify_helix_deps_manifests.sh")"
  if [ "$r" = "$got" ]; then echo "BAD  mutant $1 SURVIVED ($r)"; bad=1; else echo "ok   mutant $1 killed"; fi
}
mutant M1-missing-manifest-passes 's/reasons.append("helix-deps.yaml missing at the repository root/pass  # (/'
mutant M2-untracked-accepted 's/if not is_tracked(d, "helix-deps.yaml"):/if False:/'
mutant M3-ssh-regex-accepts-https 's/^SSH_RE = .*/SSH_RE = re.compile(r".+")/'
mutant M4-third-party-required 's/if not is_own(p\[1\], own_orgs) and not is_hub_name(url):/if False:/'
mutant M5-uninit-reads-as-pass 's/rep.add("BLIND", lab, role, "own-org repository not checked out/rep.add("PASS", lab, role, "(/'
mutant M6-nesting-ignored 's/elif own_ents:/elif False:/'
mutant M7-undeclared-ignored 's/reasons.append("undeclared own-org submodule/pass  # (/'
mutant M9-single-segment-url-unparseable 's/return (host, segs\[0\] if len(segs) > 1 else host, repo)/return None if len(segs) < 2 else (host, segs[0], repo)/'
mutant M10-https-not-parsed 's#https?|ssh|git#ssh|git#'
mutant M11-unparseable-reads-as-third-party 's/rep.add("BLIND", lab, role, "remote URL unknown or unparseable/rep.add("SKIP(third_party)", lab, role, "(/'
mutant M12-https-ownorg-reads-as-third-party 's/    return (host, segs\[0\] if len(segs) > 1 else host, repo)/    return (host, host if host.startswith("github") else segs[0] if len(segs) > 1 else host, repo)/'
mutant M8-hub-leaves-not-walked 's/for hlabel, hdir, _ in hubs\[1:\]:/for hlabel, hdir, _ in []:/'

mutant M13-hub-name-dropped-from-nesting-filter 's/ or is_hub_name(u)\]$/]/'
mutant M14-conflict-resolution-unchecked 's/if th.get("conflict_resolution") != "operator-required":/if False:/'
mutant M15-is-checkout-no-toplevel-comparison 's/    return rc == 0 and os.path.realpath(out.strip()) == os.path.realpath(d)/    return rc == 0/'
mutant M16-is-checkout-no-realpath 's/    return rc == 0 and os.path.realpath(out.strip()) == os.path.realpath(d)/    return rc == 0 and out.strip() == d/'
mutant M17-relative-urls-unresolved 's/    return u.startswith("\.\/") or u.startswith("\.\.\/")/    return False/'
[ "$bad" = 0 ] && echo "META PASS — CM-HELIX-DEPS-MANIFEST-PRESENT classifies every fixture and kills every mutant" || { echo "META FAIL"; exit 1; }
