#!/usr/bin/env bash
# test_setup_prompt_round5_stops.sh — class-exhaustive STOP-site suite for the marked shell
# blocks of docs/prompts/setup/latest.md (review round 5, finding I-3).
#
# THE CLASS: every STOP condition of every runnable block. Every line of a marked block
# (`# <ID>-BEGIN` .. `# <ID>-END`) that contains `exit 3` (a STOP) or, inside the canonical
# helper copies of STEP5, `return 1` (a refusal the caller turns into a STOP) is a SITE.
#   COVERAGE  every site is matched by exactly one row of the SITES table below and every row
#             matches exactly one site line (a new STOP without a test FAILS this suite);
#   IDENTITY  the helper functions (redact, rrun, credrx, gm_cred, own_checkout, unpushed) are
#             byte-identical in every block that defines them, so a STOP inside a non-canonical
#             copy is covered by the canonical copy's scenario plus this identity check;
#   SCENARIO  each row builds a throw-away git fixture that reaches that site, runs the REAL block
#             and requires rc 3 (or the row's rc) and the row's marker on the LAST output line.
# Failures that cannot be produced by a fixture alone (mkdir, cp, chmod, mktemp, a git command
# failing or printing nothing) are injected by a PATH shim in front of the real binary: the shim
# fails / answers empty / runs a post-command only for the argument pattern of that row.
# Paired mutation proof: test_setup_prompt_round5_stops_mutants.sh turns each site off
# (`exit 3` -> `true`, `return 1` -> `return 0`) and requires its row to FAIL.
# Env: R5_LATEST (file under test), R5_ONLY=<row id> (run only that scenario; skips coverage),
#      R5_NOSCEN=1 (coverage + identity only, no scenarios), R5_DUMP=1 (print the SITES rows).
# Nothing outside mktemp -d sandboxes is written; GIT_ALLOW_PROTOCOL=file (no network); $HOME
# untouched; GIT_CONFIG_GLOBAL=/dev/null.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_ALLOW_PROTOCOL=file GIT_TERMINAL_PROMPT=0
git_q() { git -c protocol.file.allow=always -c init.defaultBranch=main "$@"; }
LATEST="${R5_LATEST:-$REPO/docs/prompts/setup/latest.md}"
ONLY="${R5_ONLY:-}"
. "$REPO/scripts/lib/setup_prompt_extract.sh"
block="$(spx_extract_prompt "$LATEST")" || { no "PROMPT block extracted"; summary round5_stops; exit 1; }
blk_of() { awk -v b="# $1-BEGIN" -v e="# $1-END" 'index($0,e){f=0} f{print} index($0,b){f=1}' <<<"$2"; }

# ------------------------------------------------------------------------------ fixtures
mk_remote() { # <S> -> S/remote.git: c1(v1) c2(v2) on main, plus branch side (pushed) off c1
  local s="$1" w="$1/work"
  git_q init -q "$w"; printf 'one\n' >"$w/f"; printf 'keep\n' >"$w/k"; git -C "$w" add f k; git -C "$w" commit -q -m c1
  git -C "$w" tag helixconstitution-v1
  git -C "$w" checkout -q -b side; printf 'side\n' >"$w/s"; git -C "$w" add s; git -C "$w" commit -q -m side; git -C "$w" checkout -q main
  printf 'two\n' >"$w/f"; git -C "$w" commit -q -am c2; git -C "$w" tag helixconstitution-v2
  git_q clone -q --bare "$w" "$s/remote.git"
}
mk_p0() { # <S> <subpath>
  local s="$1" sp="$2"
  git_q init -q "$s/p0"; printf '# p\n' >"$s/p0/README.md"; git -C "$s/p0" add README.md; git -C "$s/p0" commit -q -m init
  [ "$sp" = constitution ] || mkdir -p "$s/p0/submodules"
  git_q -C "$s/p0" submodule add -q "$s/remote.git" "$sp" >/dev/null 2>&1
  git -C "$s/p0/$sp" checkout -q helixconstitution-v1; git -C "$s/p0" add "$sp"; git -C "$s/p0" commit -q -m sub
}
mk_full() { mk_remote "$1"; mk_p0 "$1" "$2"; git_q clone -q --recurse-submodules "$1/p0" "$1/p" >/dev/null 2>&1; }
mk_bare() { mk_remote "$1"; mk_p0 "$1" "$2"; git_q clone -q "$1/p0" "$1/p" >/dev/null 2>&1; }  # submodule NOT initialised
mk_new() { git_q init -q "$1/p"; printf '# p\n' >"$1/p/README.md"; git -C "$1/p" add README.md; git -C "$1/p" commit -q -m init; }
mk_foreign() { # <S> <subpath>: the path holds ANOTHER repository (origin is not the recorded URL)
  mk_bare "$1" "$2"; git -C "$1/p" submodule init >/dev/null 2>&1
  git_q init -q "$1/p/$2"; printf 'z\n' >"$1/p/$2/z"; git -C "$1/p/$2" add z; git -C "$1/p/$2" commit -q -m z
  git -C "$1/p/$2" remote add origin "$1/other.git"
}
mk_worktree() { # <S> <subpath>: a worktree of the PARENT at the submodule path
  mk_bare "$1" "$2"; git -C "$1/p" submodule init >/dev/null 2>&1; git -C "$1/p" worktree add -q --detach "$2" >/dev/null 2>&1
}
TOK='R5_DECOY_TOKEN_42'
tok_gitmodules() { # <S>: add a second submodule entry whose URL carries a token (a tracked file)
  git -C "$1/p" config -f .gitmodules submodule.other.path other
  git -C "$1/p" config -f .gitmodules submodule.other.url "https://x-access-token:$TOK@example.invalid/o.git"
}
shim() { printf 'export %s=%q\n' "$1" "$2" >>"$S/env"; }   # shim <VAR> <value> (run-time env of the block)

# ------------------------------------------------------------------------------ scenarios
# Each scenario builds $S/p (and writes $S/env) and names the block it runs via BLK.
s1_base() { BLK=STEP1; mk_new "$S"; mkdir -p "$S/p/.claude"; printf '{}\n' >"$S/p/.claude/settings.json"; printf '# c\n' >"$S/p/CLAUDE.md"; }
sc_s1_symlink() { s1_base; mkdir -p "$S/outside"; chmod 755 "$S/outside"; ln -s "$S/outside" "$S/p/.constitution-install-backup"; }   # round 7 M-a
sc_s1_chmod()  { s1_base; shim SHIM_FAIL_CHMOD '^chmod 700 \.constitution-install-backup$'; }
sc_s1_mktemp() { s1_base; shim SHIM_FAIL_MKTEMP '^mktemp -d'; }
sc_s1_refs()   { s1_base; shim SHIM_FAIL_GIT '^git for-each-ref'; }
sc_s1_bundle() { s1_base; shim SHIM_FAIL_GIT '^git bundle verify'; }
sc_s1_cptop()  { s1_base; shim SHIM_FAIL_CP '^cp -p CLAUDE\.md '; }
sc_s1_cpdir()  { s1_base; shim SHIM_FAIL_CP '^cp -p \.claude/'; }
sc_s1_hooks()  { s1_base; shim SHIM_FAIL_CP '^cp -pR '; }
sc_s1_excl()   { s1_base; shim SHIM_FAIL_MKDIR '^mkdir -p .*info$'; }

sc_cred()      { BLK="$1"; local sp=submodules/constitution; [ "$1" = STEP4 ] && sp=constitution
                 if [ "$1" = STEP3 ]; then mk_new "$S"; else mk_full "$S" "$sp"; fi; tok_gitmodules "$S"; }
sc_status()    { BLK="$1"; local sp=submodules/constitution; [ "$1" = STEP4 ] && sp=constitution
                 mk_full "$S" "$sp"; shim SHIM_FAIL_GIT "^git submodule status -- $sp\$"; }
sc_stempty()   { BLK="$1"; local sp=submodules/constitution; [ "$1" = STEP4 ] && sp=constitution
                 mk_full "$S" "$sp"; shim SHIM_EMPTY_GIT "^git submodule status -- $sp\$"; }
sc_initfail()  { BLK="$1"; local sp=submodules/constitution; [ "$1" = STEP4 ] && sp=constitution
                 mk_bare "$S" "$sp"; mv "$S/remote.git" "$S/remote.gone"; }
sc_foreign()   { BLK="$1"; local sp=submodules/constitution; [ "$1" = STEP4 ] && sp=constitution; mk_foreign "$S" "$sp"; }
sc_top()       { BLK=STEP5; mk_full "$S" submodules/constitution; shim SHIM_EMPTY_GIT '^git -C submodules/constitution rev-parse --show-toplevel$'; }
sc_wt()        { BLK=STEP5; mk_worktree "$S" submodules/constitution; }
sc_dirty()     { BLK="$1"; local sp=submodules/constitution; [ "$1" = STEP4 ] && sp=constitution
                 mk_full "$S" "$sp"; printf 'x\n' >>"$S/p/$sp/k"
                 git -C "$S/p" config "submodule.$sp.ignore" all; }   # the parent's status no longer shows it
sc_noremote()  { BLK="$1"; local sp=submodules/constitution; [ "$1" = STEP4 ] && sp=constitution
                 mk_full "$S" "$sp"; git -C "$S/p/$sp" remote remove origin; }
sc_unpushed()  { BLK="$1"; local sp=submodules/constitution; [ "$1" = STEP4 ] && sp=constitution
                 mk_full "$S" "$sp"; local c="$S/p/$sp"   # a commit on a LOCAL branch, HEAD and the parent unchanged
                 git -C "$c" checkout -q -b mine; printf 'u\n' >"$c/u"; git -C "$c" add u; git -C "$c" commit -q -m u
                 git -C "$c" checkout -q --detach helixconstitution-v1; }

sc_s3_ininit() { BLK=STEP3; mk_bare "$S" submodules/constitution; mv "$S/remote.git" "$S/remote.gone"; }
sc_s3_inown()  { BLK=STEP3; mk_foreign "$S" submodules/constitution; }
sc_s3_exists() { BLK=STEP3; mk_new "$S"; mkdir -p "$S/p/submodules/constitution"; }
sc_s3_nomirr() { BLK=STEP3; mk_new "$S"; shim CONSTITUTION_URLS "$S/nonexistent.git"; }
s3_ok()        { BLK=STEP3; mk_remote "$S"; mk_new "$S"; shim CONSTITUTION_URLS "$S/remote.git"; }
sc_s3_mkdir()  { s3_ok; shim SHIM_FAIL_MKDIR '^mkdir -p submodules$'; }
sc_s3_add()    { s3_ok; shim SHIM_FAIL_GIT 'submodule add'; }
sc_s3_lsr()    { s3_ok; shim SHIM_FAIL_GIT 'ls-remote --tags --refs origin'; }
sc_s3_co()     { s3_ok; shim SHIM_FAIL_GIT 'checkout -q helixconstitution'; }
sc_s3_gadd()   { s3_ok; shim SHIM_FAIL_GIT '^git add \.gitmodules'; }

sc_s4_parent() { BLK=STEP4; mk_full "$S" constitution; git -C "$S/p" config -f .gitmodules foo.bar x; }
sc_s4_exists() { BLK=STEP4; mk_full "$S" constitution; mkdir -p "$S/p/submodules/constitution"; }
sc_s4_mkdir()  { BLK=STEP4; mk_full "$S" constitution; shim SHIM_FAIL_MKDIR '^mkdir -p submodules$'; }
sc_s4_mv()     { BLK=STEP4; mk_full "$S" constitution; shim SHIM_FAIL_GIT '^git mv '; }
sc_s4_gm()     { BLK=STEP4; mk_full "$S" constitution
                 shim SHIM_POST_RE_GIT '^git mv constitution submodules/constitution$'
                 shim SHIM_POST_CMD_GIT 'git config -f .gitmodules submodule.constitution.path constitution'; }
sc_s4_init()   { BLK=STEP4; mk_full "$S" constitution; shim SHIM_EMPTY_GIT '^git submodule status -- submodules/constitution$'; }
sc_s4_link()   { BLK=STEP4; mk_full "$S" constitution; shim SHIM_EMPTY_GIT '^git -C submodules/constitution rev-parse --show-toplevel$'; }
sc_s4_still()  { BLK=STEP4; mk_full "$S" constitution
                 shim SHIM_POST_RE_GIT '^git mv constitution submodules/constitution$'
                 shim SHIM_POST_CMD_GIT 'mkdir constitution'; }

s5_ok()        { BLK=STEP5; mk_full "$S" submodules/constitution; }
sc_s5_fetch()  { s5_ok; shim SHIM_FAIL_GIT 'fetch --tags origin'; }
sc_s5_head()   { s5_ok; shim SHIM_FAIL_GIT '^git -C submodules/constitution rev-parse HEAD$'; }
sc_s5_lsr()    { s5_ok; shim SHIM_FAIL_GIT 'ls-remote --tags --refs origin'; }
sc_s5_target() { s5_ok; shim SHIM_FAIL_GIT 'rev-parse --verify -q helixconstitution'; }
sc_s5_noff()   { s5_ok; git -C "$S/p/submodules/constitution" checkout -q origin/side; }   # pushed, diverged from v2
sc_s5_co()     { s5_ok; shim SHIM_FAIL_GIT 'checkout -q [0-9a-f]{40}$'; }
sc_s5_add()    { s5_ok; shim SHIM_FAIL_GIT '^git add submodules/constitution$'; }

s6b() { BLK=STEP6B; git_q init -q "$S/p"; mkdir -p "$S/p/submodules/constitution/scripts"
        printf '#!/bin/sh\n%s\n' "$1" >"$S/p/submodules/constitution/scripts/setup.sh"; }
sc_s6b_rc()    { s6b 'echo "post_update_hook.sh: OK"; exit 1'; }
sc_s6b_parse() { s6b 'echo "x.sh: PARSE ERROR"; echo "post_update_hook.sh: OK"'; }
sc_s6b_miss()  { s6b 'echo "y: MISSING"; echo "post_update_hook.sh: OK"'; }
sc_s6b_notc()  { s6b 'echo "Not a constitution checkout"; echo "post_update_hook.sh: OK"'; }
sc_s6b_nook()  { s6b 'echo "all fine"'; }

s7a() { BLK=STEP7A; mk_new "$S"; mkdir -p "$S/p/submodules/constitution/scripts/deps_manifest"
        printf '#!/bin/sh\nexit %s\n' "$1" >"$S/p/submodules/constitution/scripts/deps_manifest/verify_helix_deps_manifests.sh"
        printf 'schema_version: 1\ndeps:\n  - name: x\n    ssh_url: %s\n' "$2" >"$S/p/helix-deps.yaml"; }
sc_s7_inval()  { s7a 1 'git@github.com:vasic-digital/X.git'; }
sc_s7_tok()    { s7a 0 "https://x-access-token:$TOK@github.com/vasic-digital/X.git"; }
sc_s7_scp()    { s7a 0 "user:$TOK@github.com:vasic-digital/X.git"; }
sc_s7_add()    { s7a 0 'git@github.com:vasic-digital/X.git'; shim SHIM_FAIL_GIT '^git add helix-deps\.yaml$'; }

s10() { BLK=STEP10; git_q init -q "$S/p"; printf 'a\n' >"$S/p/a"; git -C "$S/p" add a; git -C "$S/p" commit -q -m init; }
sc_s10_br()    { s10; git -C "$S/p" checkout -q -b other; }
sc_s10_norem() { s10; }
sc_s10_fetch() { s10; git -C "$S/p" remote add dead "$S/dead.git"; }
sc_s10_ahead() { s10; git_q clone -q --bare "$S/p" "$S/up.git"; git_q clone -q "$S/up.git" "$S/o"
                 printf 'b\n' >"$S/o/b"; git -C "$S/o" add b; git -C "$S/o" commit -q -m b; git -C "$S/o" push -q origin main
                 git -C "$S/p" remote add up "$S/up.git"; }
sc_s10_push()  { s10; git_q init -q --bare "$S/up.git"; git -C "$S/p" remote add up "$S/up.git"; shim SHIM_FAIL_GIT '^git push '; }

# ------------------------------------------------------------------------------ the SITES table
# id | block | unique substring of the site line | scenario (+arg) | want rc | marker (ERE, last line)
SITES=(
"S1-SYMLINK|STEP1|[ ! -L .constitution-install-backup ]|||sc_s1_symlink|3|STOP: .constitution-install-backup is a symlink"
"S1-CHMOD|STEP1|chmod 700 .constitution-install-backup |||sc_s1_chmod|3|SHIM-FAIL chmod"
"S1-MKTEMP|STEP1|bk=\"\$(mktemp -d|||sc_s1_mktemp|3|SHIM-FAIL mktemp"
"S1-REFS|STEP1|> \"\$bk/refs.txt\" @@@@ exit 3|||sc_s1_refs|3|SHIM-FAIL git for-each-ref"
"S1-BUNDLE|STEP1|git bundle verify \"\$bk/project.bundle\"; } @@@@ exit 3|||sc_s1_bundle|3|SHIM-FAIL git bundle verify"
"S1-CPTOP|STEP1|cp -p \"\$f\" \"\$bk/\$f\" @@@@ exit 3|||sc_s1_cptop|3|SHIM-FAIL cp -p CLAUDE.md"
"S1-CPDIR|STEP1|cp -p \"\$d/\$p\" \"\$bk/\$d/\$p\" @@@@ exit 3|||sc_s1_cpdir|3|SHIM-FAIL cp -p .claude/"
"S1-HOOKS|STEP1|cp -pR \"\$hooks\"|||sc_s1_hooks|3|SHIM-FAIL cp -pR"
"S1-EXCL|STEP1|mkdir -p \"\$(dirname \"\$excl\")\" @@@@ exit 3|||sc_s1_excl|3|SHIM-FAIL mkdir"
"S2-CRED|STEP2|k=\"\$(gm_cred)\"|||sc_cred STEP2|3|^STOP: \\.gitmodules \\(submodule\\.other\\.url\\) holds a URL with credentials"
"S2-STATUS|STEP2|st=\"\$(git submodule status -- \"\$c\" 2>/dev/null)\"|||sc_status STEP2|3|SHIM-FAIL git submodule status"
"S2-EMPTY|STEP2|[ -n \"\$st\" ]|||sc_stempty STEP2|3|^STOP: submodules/constitution is not a registered submodule"
"S2-INIT|STEP2|case \"\$st\" in -*)|||sc_initfail STEP2|3|^STOP: could not initialise submodules/constitution"
"S2-OWN|STEP2|why=\"\$(own_checkout \"\$c\")\"|||sc_foreign STEP2|3|^STOP: submodules/constitution is not the submodule's own checkout: .*another repository"
"S3-CRED|STEP3|k=\"\$(gm_cred)\"|||sc_cred STEP3|3|^STOP: \\.gitmodules \\(submodule\\.other\\.url\\) holds a URL with credentials"
"S3-ININIT|STEP3|rrun git submodule update --init -- submodules/constitution @@@@ exit 3|||sc_s3_ininit|3|(Failed to clone@@^fatal:)"
"S3-INOWN|STEP3|why=\"\$(own_checkout submodules/constitution)\"|||sc_s3_inown|3|^STOP: submodules/constitution is not the submodule's own checkout"
"S3-EXISTS|STEP3|exists but is not a registered submodule|||sc_s3_exists|3|^STOP: submodules/constitution exists but is not a registered submodule"
"S3-NOMIRROR|STEP3|[ -n \"\$url\" ]|||sc_s3_nomirr|3|^STOP: no constitution mirror is reachable"
"S3-MKDIR|STEP3|mkdir -p submodules @@@@ exit 3|||sc_s3_mkdir|3|SHIM-FAIL mkdir -p submodules"
"S3-ADD|STEP3|rrun git submodule add -- \"\$url\" submodules/constitution @@@@ exit 3|||sc_s3_add|3|SHIM-FAIL git submodule add"
"S3-LSR|STEP3|rt=\"\$(git -C submodules/constitution ls-remote|||sc_s3_lsr|3|^STOP: could not list the remote tags"
"S3-CO|STEP3|checkout -q \"\$tag\" @@@@ exit 3|||sc_s3_co|3|SHIM-FAIL git -C submodules/constitution checkout"
"S3-GADD|STEP3|git add .gitmodules submodules/constitution @@@@ exit 3|||sc_s3_gadd|3|SHIM-FAIL git add .gitmodules"
"S4-CRED|STEP4|k=\"\$(gm_cred)\"|||sc_cred STEP4|3|^STOP: \\.gitmodules \\(submodule\\.other\\.url\\) holds a URL with credentials"
"S4-STATUS|STEP4|st=\"\$(git submodule status -- constitution 2>/dev/null)\"|||sc_status STEP4|3|SHIM-FAIL git submodule status"
"S4-EMPTY|STEP4|[ -n \"\$st\" ]|||sc_stempty STEP4|3|^STOP: the legacy constitution path is not a registered submodule"
"S4-INIT|STEP4|case \"\$st\" in -*)|||sc_initfail STEP4|3|^STOP: could not initialise the legacy constitution submodule"
"S4-OWN|STEP4|why=\"\$(own_checkout constitution)\"|||sc_foreign STEP4|3|^STOP: the legacy constitution path is not the submodule's own checkout"
"S4-NODIRTY|STEP4|the legacy constitution has local changes|||sc_dirty STEP4|3|^STOP: the legacy constitution has local changes"
"S4-NOREMOTE|STEP4|np=\"\$(unpushed constitution)\"|||sc_noremote STEP4|3|^STOP: no remote of the legacy constitution answered"
"S4-NOUNPUSHED|STEP4|[ -z \"\$np\" ]|||sc_unpushed STEP4|3|^STOP: the legacy constitution holds commits no remote has"
"S4-PARENT|STEP4|.gitmodules or the legacy path has uncommitted changes|||sc_s4_parent|3|^STOP: \\.gitmodules or the legacy path has uncommitted changes"
"S4-EXISTS|STEP4|already exists next to the legacy path|||sc_s4_exists|3|^STOP: submodules/constitution already exists next to the legacy path"
"S4-MKDIR|STEP4|mkdir -p submodules @@@@ exit 3|||sc_s4_mkdir|3|SHIM-FAIL mkdir -p submodules"
"S4-MV|STEP4|git mv constitution submodules/constitution @@@@ exit 3|||sc_s4_mv|3|SHIM-FAIL git mv"
"S4-GM|STEP4|.gitmodules not updated|||sc_s4_gm|3|^STOP: \\.gitmodules not updated"
"S4-INITM|STEP4|submodule not initialised after the move|||sc_s4_init|3|^STOP: submodule not initialised after the move"
"S4-LINK|STEP4|gitdir link broken|||sc_s4_link|3|^STOP: gitdir link broken"
"S4-STILL|STEP4|the legacy path still exists|||sc_s4_still|3|^STOP: the legacy path still exists"
"S5-CRED|STEP5|k=\"\$(gm_cred)\"|||sc_cred STEP5|3|^STOP: \\.gitmodules \\(submodule\\.other\\.url\\) holds a URL with credentials"
"S5-OC-TOP|STEP5|[ \"\$top\" = \"\$(pwd -P)/\$p\" ]|||sc_top|3|^STOP: submodules/constitution is not the submodule's own checkout: git resolves"
"S5-OC-WT|STEP5|is a worktree of the parent project's own repository|||sc_wt|3|^STOP: .*worktree of the parent project"
"S5-OC-FOREIGN|STEP5|is another repository: its git dir|||sc_foreign STEP5|3|^STOP: .*another repository"
"S5-UNP-NOREMOTE|STEP5|[ \"\$ok\" = 1 ] @@@@ return 1|||sc_noremote STEP5|3|^STOP: no remote of submodules/constitution answered"
"S5-STATUS|STEP5|st=\"\$(git submodule status -- \"\$c\" 2>/dev/null)\"|||sc_status STEP5|3|SHIM-FAIL git submodule status"
"S5-EMPTY|STEP5|[ -n \"\$st\" ]|||sc_stempty STEP5|3|^STOP: submodules/constitution is not a registered submodule"
"S5-INIT|STEP5|case \"\$st\" in -*)|||sc_initfail STEP5|3|^STOP: could not initialise submodules/constitution"
"S5-OWN|STEP5|why=\"\$(own_checkout \"\$c\")\"|||sc_foreign STEP5|3|^STOP: submodules/constitution is not the submodule's own checkout"
"S5-DIRTY|STEP5|has local changes\"; exit 3|||sc_dirty STEP5|3|^STOP: submodules/constitution has local changes"
"S5-NOREMOTE|STEP5|np=\"\$(unpushed \"\$c\")\"|||sc_noremote STEP5|3|^STOP: no remote of submodules/constitution answered"
"S5-UNPUSHED|STEP5|[ -z \"\$np\" ]|||sc_unpushed STEP5|3|^STOP: submodules/constitution holds commits no remote has"
"S5-FETCHOK|STEP5|fetch --tags origin @@@@ |||sc_s5_fetch|3|^STOP: fetch failed"
"S5-HEAD|STEP5|before=\"\$(git -C \"\$c\" rev-parse HEAD)\" @@@@ exit 3|||sc_s5_head|3|SHIM-FAIL git -C submodules/constitution rev-parse HEAD"
"S5-LSR|STEP5|rt=\"\$(git -C \"\$c\" ls-remote|||sc_s5_lsr|3|^STOP: could not list the remote tags of submodules/constitution"
"S5-TARGET|STEP5|STOP: target \$target not found|||sc_s5_target|3|^STOP: target helixconstitution-v2 not found"
"S5-NOFF|STEP5|NOT-FF|||sc_s5_noff|3|^STOP: NOT-FF"
"S5-CO|STEP5|git -C \"\$c\" checkout -q \"\$t\" @@@@ exit 3|||sc_s5_co|3|SHIM-FAIL git -C submodules/constitution checkout"
"S5-ADD|STEP5|git add \"\$c\" @@@@ exit 3|||sc_s5_add|3|SHIM-FAIL git add submodules/constitution"
"S6B-RC|STEP6B|echo \"STOP: setup.sh --check-only reported a problem|||sc_s6b_rc|3|^STOP: setup.sh --check-only reported a problem \\(rc=1\\)"
"S7A-INVALID|STEP7A|does not validate; not staged|||sc_s7_inval|3|^STOP: helix-deps.yaml does not validate"
"S7A-CRED|STEP7A|carries a URL with credentials; not staged|||sc_s7_tok|3|^STOP: helix-deps.yaml carries a URL with credentials"
"S7A-ADD|STEP7A|git add helix-deps.yaml @@@@ exit 3|||sc_s7_add|3|SHIM-FAIL git add helix-deps.yaml"
"S10-BRANCH|STEP10|[ \"\$br\" = main ]|||sc_s10_br|3|^STOP: the current branch is 'other', not main"
"S10-NOREMOTE|STEP10|[ -n \"\$remotes\" ]|||sc_s10_norem|3|^STOP: no remote is configured"
"S10-FETCH|STEP10|rrun git fetch \"\$r\" @@@@|||sc_s10_fetch|3|^STOP: fetch from dead failed"
"S10-AHEAD|STEP10|has commits HEAD lacks|||sc_s10_ahead|3|^STOP: up/main has commits HEAD lacks"
"S5-GMCRED-NONE|STEP5|done < <(git config -f .gitmodules --get-regexp|||s5_ok|0|^"
"S10-PUSH|STEP10|push to \$r failed|||sc_s10_push|3|^STOP: push to up failed"
)
# Extra rows: the same site reached by another trigger (sub-conditions of one STOP line), and
# golden-FALSE rows (a clean fixture must PASS: a site that refuses everything is a defect too).
EXTRA=(
"X-S6B-PARSE|STEP6B||||sc_s6b_parse|3|^STOP: setup.sh --check-only"
"X-S6B-MISSING|STEP6B||||sc_s6b_miss|3|^STOP: setup.sh --check-only"
"X-S6B-NOTCONST|STEP6B||||sc_s6b_notc|3|^STOP: setup.sh --check-only"
"X-S6B-NOOK|STEP6B||||sc_s6b_nook|3|^STOP: setup.sh --check-only"
"X-S7A-SCP|STEP7A||||sc_s7_scp|3|^STOP: helix-deps.yaml carries a URL with credentials"
"G-STEP1|STEP1||||s1_base|0|^backup: "
"G-STEP3|STEP3||||s3_ok|0|."
"G-STEP4|STEP4||||g_s4|0|^legacy path migrated$"
"G-STEP5|STEP5||||s5_ok|0|."
"G-STEP7A|STEP7A||||g_s7|0|^"
"G-STEP10|STEP10||||g_s10|0|."
)
g_s4() { BLK=STEP4; mk_full "$S" constitution; }
g_s7() { s7a 0 'git@github.com:vasic-digital/X.git'; }
g_s10() { s10; git_q init -q --bare "$S/up.git"; git -C "$S/p" remote add up "$S/up.git"; }

# ------------------------------------------------------------------------------ shim + runner
mk_shim() { # <dir>
  mkdir -p "$1"
  cat >"$1/_shim" <<'SH'
#!/bin/bash
n="${0##*/}"; N="${n^^}"
real="$(PATH="$SHIM_REALPATH" command -v "$n")"
f="SHIM_FAIL_$N"; e="SHIM_EMPTY_$N"; pr="SHIM_POST_RE_$N"; pc="SHIM_POST_CMD_$N"
a="$n $*"
if [ -n "${!f:-}" ] && [[ "$a" =~ ${!f} ]]; then echo "SHIM-FAIL $a" >&2; exit 1; fi
if [ -n "${!e:-}" ] && [[ "$a" =~ ${!e} ]]; then exit 0; fi
if [ -n "${!pr:-}" ] && [[ "$a" =~ ${!pr} ]]; then "$real" "$@"; rc=$?; PATH="$SHIM_REALPATH" eval "${!pc}"; exit "$rc"; fi
exec "$real" "$@"
SH
  chmod +x "$1/_shim"
  local n; for n in git mkdir cp chmod mktemp; do ln -s _shim "$1/$n"; done
}
run_row() { # <row> -> 0 PASS / 1 FAIL; prints the verdict line
  local id blk key scen want marker rc last
  IFS='|' read -r id blk key _ _ scen want marker <<<"$1"; key="${key//@@/|}"; marker="${marker//@@/|}"
  S="$(mk_sandbox)"; : >"$S/env"; BLK=""
  ( $scen ) >"$S/fixture.log" 2>&1 || true
  # re-run in this shell to get BLK (scenarios only set variables and build files idempotently? no:
  # BLK is derived from the row instead, the scenario output above built the fixture)
  BLK="$blk"
  code="$(blk_of "$BLK" "$block")"
  [ -n "$code" ] || { no "$id: block $BLK missing"; return 1; }
  printf '%s\n' "$code" >"$S/run.sh"
  mk_shim "$S/shim"
  ( cd "$S/p" && export SHIM_REALPATH="$PATH" && . "$S/env" && PATH="$S/shim:$PATH" bash "$S/run.sh" ) >"$S/out" 2>&1; rc=$?
  last="$(grep -v '^[[:space:]]*$' "$S/out" | tail -n 1)"
  if [ "$rc" -eq "$want" ] && grep -qE -- "$marker" <<<"$last"; then
    ok "$id ($blk): rc=$rc, last line matches"
  else
    no "$id ($blk): rc=$rc want=$want; last line: $(cut -c1-160 <<<"$last")"
  fi
}

if [ -n "${R5_DUMP:-}" ]; then printf '%s\n' "${SITES[@]}"; exit 0; fi
if [ -n "$ONLY" ]; then
  for r in "${SITES[@]}" "${EXTRA[@]}"; do [ "${r%%|*}" = "$ONLY" ] && run_row "$r"; done
  summary "round5_stops($ONLY)"; exit $?
fi

# ------------------------------------------------------------------------------ COVERAGE
cov="$(python3 -I - "$LATEST" <<'PY' 2>&1
import re, sys, subprocess, os
text = open(sys.argv[1], encoding='utf-8').read()
m = re.search(r'^## PROMPT[ \t]*\n(?:[^\n]*\n)*?(```+|~~~+)[^\n]*\n(.*?)^\1[ \t]*$', text, re.M | re.S)
body = m.group(2)
blocks = dict((b, s) for b, s in re.findall(r'# ([A-Z0-9]+)-BEGIN\n(.*?)\n[ \t]*# \1-END', body, re.S))
HELPERS = ('own_checkout', 'unpushed', 'gm_cred', 'redact', 'rrun')
for b, s in blocks.items():
    infn = None
    for ln in s.split('\n'):
        st = ln.strip()
        mm = re.match(r'^([a-z_]+)\(\) \{', st)
        if mm and not st.endswith('}'):
            infn = mm.group(1)
        site = ('exit 3' in ln) or (infn and re.search(r'\breturn 1\b', ln))
        if site:
            canonical = (infn is None) or b == 'STEP5'
            print('%s\t%s\t%s' % (b, 'C' if canonical else 'H', st))
        if infn and st == '}':
            infn = None
PY
)"
nsite=0; nh=0
while IFS=$'\t' read -r b kind line; do
  [ -n "$b" ] || continue
  if [ "$kind" = H ]; then nh=$((nh + 1)); continue; fi
  nsite=$((nsite + 1)); m=0; mid=""
  for r in "${SITES[@]}"; do
    IFS='|' read -r id rb key _ <<<"$r"
    [ "$rb" = "$b" ] || continue
    k="${key//\@@/|}"
    case "$line" in *"$k"*) m=$((m + 1)); mid="$mid $id" ;; esac
  done
  [ "$m" -eq 1 ] && ok "COVERAGE $b site covered by$mid" || no "COVERAGE $b site matched by $m rows ($mid): $(cut -c1-120 <<<"$line")"
done <<<"$cov"
[ "$nsite" -ge 60 ] && ok "COVERAGE control: the enumerator found $nsite STOP sites (+$nh in helper copies)" || no "COVERAGE enumerator found only $nsite sites (BLIND?)"
for r in "${SITES[@]}"; do   # every row names exactly one site line
  IFS='|' read -r id rb key _ <<<"$r"; k="${key//\@@/|}"
  c="$(grep -cF -- "$k" <<<"$(blk_of "$rb" "$block" | grep -E 'exit 3|return 1')")"
  [ "$c" -eq 1 ] || no "ROW $id matches $c site lines in $rb"
done
ok "ROWS checked: ${#SITES[@]} rows, each naming one site line (failures listed above, if any)"

# ------------------------------------------------------------------------------ IDENTITY
idn="$(python3 -I - "$LATEST" <<'PY'
import re, sys
text = open(sys.argv[1], encoding='utf-8').read()
m = re.search(r'^## PROMPT[ \t]*\n(?:[^\n]*\n)*?(```+|~~~+)[^\n]*\n(.*?)^\1[ \t]*$', text, re.M | re.S)
body = m.group(2)
blocks = dict((b, s) for b, s in re.findall(r'# ([A-Z0-9]+)-BEGIN\n(.*?)\n[ \t]*# \1-END', body, re.S))
defs = {}
for b, s in blocks.items():
    ls = s.split('\n'); i = 0
    while i < len(ls):
        st = ls[i].strip()
        mm = re.match(r'^(own_checkout|unpushed|gm_cred|redact|rrun)\(\) \{', st) or re.match(r'^(credrx)=', st)
        if mm:
            name = mm.group(1); body_ = [ls[i]]
            if not (st.endswith('}') or name == 'credrx' or st.endswith('# hide credentials in URLs') or st.endswith('redacted')):
                while i + 1 < len(ls):
                    i += 1; body_.append(ls[i])
                    if ls[i].strip() == '}': break
            defs.setdefault(name, {})[b] = '\n'.join(body_)
        i += 1
for name, per in sorted(defs.items()):
    variants = set(per.values())
    print('%s\t%d\t%d\t%s' % (name, len(per), len(variants), ','.join(sorted(per))))
PY
)"
while IFS=$'\t' read -r name n nv where; do
  [ "$nv" -eq 1 ] && ok "IDENTITY $name: one definition in $n blocks ($where)" || no "IDENTITY $name: $nv different definitions across $where"
done <<<"$idn"
for need in own_checkout:4 unpushed:2 gm_cred:4 credrx:4 redact:5 rrun:5; do
  n="$(awk -F'\t' -v k="${need%%:*}" '$1 == k { print $2 }' <<<"$idn")"
  [ "${n:-0}" -ge "${need##*:}" ] && ok "IDENTITY control: ${need%%:*} found in ${n} blocks" || no "IDENTITY control: ${need%%:*} found in ${n:-0} blocks (< ${need##*:})"
done

# ------------------------------------------------------------------------------ SCENARIOS
[ -n "${R5_NOSCEN:-}" ] && { summary round5_stops_static; exit $?; }
for r in "${SITES[@]}" "${EXTRA[@]}"; do run_row "$r"; done
summary round5_stops
