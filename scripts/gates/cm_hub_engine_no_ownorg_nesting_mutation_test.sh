#!/usr/bin/env bash
# cm_hub_engine_no_ownorg_nesting_mutation_test.sh — §1.1 paired-mutation meta-test for CM-HUB-ENGINE-NO-OWNORG-NESTING.
# Throwaway fixtures only (the real repo is never touched).
# Part 1 — fixture classification with the real gate:
#   PASS-expected : CLEAN (third-party nested only) · NONE (engine has no .gitmodules)
#                   · RECORDED-CLEAN-HEAD-DIRTY (the recorded commit governs)
#                   · STAGED-CLEAN-HEADREC-DIRTY (a staged/index gitlink that differs from HEAD governs)
#                   · NAME-PREFIX-NOT-HUB (someone/constitution-tools.git — golden-FALSE: a name that merely STARTS
#                     with "constitution" is not the hub; kills a mutant dropping the hub regex end-anchor)
#                   · RELATIVE-THIRDPARTY (../../ggml-org/llama.cpp.git resolves to a third-party organisation)
#   FAIL-expected : VASIC (own-org nested) · HELIXDEV (HelixDevelopment nested) · HUB (nested constitution)
#                   · HELIXQA (HelixDevelopment, not a hub name — kills a mutant dropping helixdevelopment from OWN)
#                   · FOREIGN-HUB-NAME (someone/constitution.git — kills a mutant dropping the $HUB name match)
#                   · FOREIGN-HELIXCONSTITUTION (someone/HelixConstitution.git — kills a mutant dropping
#                     helixconstitution from the hub-name regex)
#                   · RELATIVE-OWNORG (../Containers.git resolves to the engine's own organisation)
#                   · RECORDED-DIRTY-HEAD-CLEAN · STAGED-DIRTY-HEADREC-CLEAN
#   BLIND-expected: RELATIVE-UNRESOLVABLE (a relative URL with too many ../ cannot be resolved)
#   SKIP-expected : UNINIT (no engine checked out -> nothing inspected -> exit 3, never PASS)
#                   · UNINIT-EMPTY-DIR (the engine path is an EMPTY directory, as `git submodule` leaves an
#                     uninitialised submodule; git would find the HUB's repository there — kills a mutant dropping
#                     the --show-toplevel check)
# Part 2 — gate mutants: the gate is copied to a scratch dir, one defect is injected per mutant, and every fixture
#   is re-classified. Each mutant MUST change at least one verdict (be KILLED); a survivor means a defect class is
#   invisible to the fixtures.
# Usage: cm_hub_engine_no_ownorg_nesting_mutation_test.sh   Exit: 0 proof holds · 1 misclassified/survivor · 2 env error.
# Side-effects: temp dir under $TMPDIR (trap-cleaned). Dependencies: bash, git, sed, cmp. Classification: universal (§11.4.17).
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
gate="$here/cm_hub_engine_no_ownorg_nesting.sh"
[ -r "$gate" ] || { echo "META: gate missing" >&2; exit 2; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
bad=0
engine_commit() { # <engine-dir> <gitmodules-content or ''> -> commit sha
  local d="$1"; [ -d "$d/.git" ] || { mkdir -p "$d"; git -C "$d" init -q; }
  if [ -n "$2" ]; then printf '%s\n' "$2" >"$d/.gitmodules"; else rm -f "$d/.gitmodules"; echo x >"$d/f"; git -C "$d" add f; fi
  [ -n "$2" ] && git -C "$d" add .gitmodules
  git -C "$d" commit -q --allow-empty -m e && git -C "$d" rev-parse HEAD
}
mk_hub() { # <hub-dir> <recorded-sha or ''>
  local h="$1"; mkdir -p "$h"; git -C "$h" init -q
  printf '[submodule "submodules/eng"]\n\tpath = submodules/eng\n\turl = git@github.com:vasic-digital/eng.git\n' >"$h/.gitmodules"
  git -C "$h" add .gitmodules
  [ -n "$2" ] && git -C "$h" update-index --add --cacheinfo "160000,$2,submodules/eng"
  git -C "$h" commit -q -m hub
}
FIXTURES=""
fx() { FIXTURES+="$1:$2 "; }   # label expected-rc (hub dir is $tmp/<label>/hub)
sm() { printf '[submodule "x"]\n\tpath = submodules/x\n\turl = %s\n' "$1"; }
case_one() { # <label> <rc> <gitmodules-content-or-empty>
  local d="$tmp/$1"; mkdir -p "$d"; local sha; sha="$(engine_commit "$d/hub-eng" "$3")"
  mk_hub "$d/hub" "$sha"; mkdir -p "$d/hub/submodules"; mv "$d/hub-eng" "$d/hub/submodules/eng"; fx "$1" "$2"
}
case_one CLEAN 0 "$(sm git@github.com:ggml-org/llama.cpp.git)"
case_one NONE 0 ""
case_one VASIC 1 "$(sm git@github.com:vasic-digital/Containers.git)"
case_one HELIXDEV 1 "$(sm git@github.com:HelixDevelopment/constitution.git)"
case_one HUB 1 "$(sm git@github.com:HelixDevelopment/HelixConstitution.git)"
case_one HELIXQA 1 "$(sm https://github.com/HelixDevelopment/HelixQA.git)"
case_one FOREIGN-HUB-NAME 1 "$(sm git@github.com:someone/constitution.git)"
case_one FOREIGN-HELIXCONSTITUTION 1 "$(sm git@github.com:someone/HelixConstitution.git)"
case_one NAME-PREFIX-NOT-HUB 0 "$(sm git@github.com:someone/constitution-tools.git)"
# relative URLs resolve against the engine's own URL (git@github.com:vasic-digital/eng.git in the hub .gitmodules)
case_one RELATIVE-OWNORG 1 "$(sm ../Containers.git)"
case_one RELATIVE-THIRDPARTY 0 "$(sm ../../ggml-org/llama.cpp.git)"
case_one RELATIVE-UNRESOLVABLE 2 "$(sm ../../../../x.git)"
# UNINIT: hub records a gitlink but the engine dir is absent -> nothing inspected -> SKIP (exit 3), never PASS
d="$tmp/UNINIT"; mkdir -p "$d"; mk_hub "$d/hub" "0123456789abcdef0123456789abcdef01234567"; fx UNINIT 3
# UNINIT-EMPTY-DIR: the engine path exists but is an EMPTY directory (an uninitialised submodule) -> SKIP (exit 3)
d="$tmp/UNINIT-EMPTY-DIR"; mkdir -p "$d"; mk_hub "$d/hub" "0123456789abcdef0123456789abcdef01234567"; mkdir -p "$d/hub/submodules/eng"
fx UNINIT-EMPTY-DIR 3
# recorded-clean / head-dirty and the reverse
d="$tmp/RECORDED-CLEAN-HEAD-DIRTY"; mkdir -p "$d"; e="$d/hub-eng"; c1="$(engine_commit "$e" "$(sm git@github.com:ggml-org/llama.cpp.git)")"; engine_commit "$e" "$(sm git@github.com:vasic-digital/x.git)" >/dev/null
mk_hub "$d/hub" "$c1"; mkdir -p "$d/hub/submodules"; mv "$e" "$d/hub/submodules/eng"; fx RECORDED-CLEAN-HEAD-DIRTY 0
d="$tmp/RECORDED-DIRTY-HEAD-CLEAN"; mkdir -p "$d"; e="$d/hub-eng"; c1="$(engine_commit "$e" "$(sm git@github.com:vasic-digital/x.git)")"; engine_commit "$e" "$(sm git@github.com:ggml-org/llama.cpp.git)" >/dev/null
mk_hub "$d/hub" "$c1"; mkdir -p "$d/hub/submodules"; mv "$e" "$d/hub/submodules/eng"; fx RECORDED-DIRTY-HEAD-CLEAN 1
# staged (index) gitlink differs from the one HEAD records: the staged one governs
stage() { git -C "$1" update-index --cacheinfo "160000,$2,submodules/eng"; }
d="$tmp/STAGED-CLEAN-HEADREC-DIRTY"; mkdir -p "$d"; e="$d/hub-eng"; cd_="$(engine_commit "$e" "$(sm git@github.com:vasic-digital/x.git)")"; cc="$(engine_commit "$e" "$(sm git@github.com:ggml-org/llama.cpp.git)")"
mk_hub "$d/hub" "$cd_"; stage "$d/hub" "$cc"; mkdir -p "$d/hub/submodules"; mv "$e" "$d/hub/submodules/eng"; fx STAGED-CLEAN-HEADREC-DIRTY 0
d="$tmp/STAGED-DIRTY-HEADREC-CLEAN"; mkdir -p "$d"; e="$d/hub-eng"; cc="$(engine_commit "$e" "$(sm git@github.com:ggml-org/llama.cpp.git)")"; cd_="$(engine_commit "$e" "$(sm git@github.com:vasic-digital/x.git)")"
mk_hub "$d/hub" "$cc"; stage "$d/hub" "$cd_"; mkdir -p "$d/hub/submodules"; mv "$e" "$d/hub/submodules/eng"; fx STAGED-DIRTY-HEADREC-CLEAN 1

classify() { # gate-path -> "LABEL:rc ..." for every fixture
  local g="$1" pair lab res=""
  for pair in $FIXTURES; do lab="${pair%%:*}"; bash "$g" --root "$tmp/$lab/hub" >/dev/null 2>&1; res+="$lab:$? "; done
  printf '%s\n' "${res% }"
}
echo "── Part 1: fixture classification with the real gate"
got="$(classify "$gate")"
for pair in $FIXTURES; do
  if [[ " $got " == *" $pair "* ]]; then echo "ok   $pair"
  else echo "BAD  expected $pair"; bash "$gate" --root "$tmp/${pair%%:*}/hub" 2>&1 | sed 's/^/     /'; bad=1; fi
done

echo "── Part 2: gate mutants (each MUST be killed)"
mutant() { # label sed-expression
  local m="$tmp/mut/$1"; mkdir -p "$m"; cp "$gate" "$m/g.sh"; sed -i "$2" "$m/g.sh"
  if cmp -s "$m/g.sh" "$gate"; then echo "BAD  mutant $1 did not apply"; bad=1; return; fi
  local r; r="$(classify "$m/g.sh")"
  if [ "$r" = "$got" ]; then echo "BAD  mutant $1 SURVIVED"; bad=1; else echo "ok   mutant $1 killed"; fi
}
mutant G1-no-show-toplevel-check 's/ || \[ "$(git -C "$sub" rev-parse --show-toplevel 2>\/dev\/null)" != "$sub" \]//'
mutant G2-no-helixconstitution-name 's/(helixconstitution|constitution)/(constitution)/'
mutant G3-hub-name-not-end-anchored 's/(\\.git)?\$'"'"'/(\\.git)?'"'"'/'
mutant G4-no-helixdevelopment-org 's/(vasic-digital|helixdevelopment)/(vasic-digital)/'
mutant G5-relative-urls-unresolved 's/^  case "$u" in \.\/\*|\.\.\/\*) ;; \*) printf/  case "$u" in NEVER) ;; *) printf/'
mutant G6-recorded-commit-ignored 's/then src="$rec"$/then src="$(git -C "$sub" rev-parse HEAD)"/'
mutant G7-skip-reads-as-pass 's/exit 3; fi$/exit 0; fi/'
[ "$bad" = 0 ] && echo "META PASS — CM-HUB-ENGINE-NO-OWNORG-NESTING classifies every fixture and kills every mutant" || { echo "META FAIL"; exit 1; }
