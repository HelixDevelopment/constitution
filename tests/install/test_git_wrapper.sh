#!/usr/bin/env bash
# test_git_wrapper.sh — runtime tests of hi_gx, the allow-listed git wrapper of the installer and the updater.
#
# Both scripts are sourced in library mode with a FAKE git first on PATH (a test double that only records its
# arguments; gate-logic/unit class per §11.4.289(C)). Every forbidden or obfuscated call must return 3, print
# the [git-allowlist] message and never reach git; every allowed form must reach git with the same words.
# A real run then proves the wrapper is the code path in use: HI_GX_COMMIT_OK=1 inherited from the caller's
# environment does not let a commit through (hi_init_state clears it), and a normal install still works.
# Usage: bash tests/install/test_git_wrapper.sh   Exit 0 all pass · 1 a case failed · 2 env error.
T_NAME=git-wrapper
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
new_sandbox
mkdir -p "$SB/fake"
cat >"$SB/fake/git" <<'EOF'
#!/bin/sh
# FAKE git (TEST DOUBLE, unit class): records the call, does nothing
printf '%s\n' "$*" >>"${MARK:?}"
printf 'ENV GIT_DIR=%s GIT_WORK_TREE=%s GIT_CONFIG_COUNT=%s GIT_CONFIG_PARAMETERS=%s GIT_EXEC_PATH=%s GIT_SSH=%s GIT_TEMPLATE_DIR=%s GIT_EXTERNAL_DIFF=%s GIT_INDEX_FILE=%s\n' \
  "${GIT_DIR:-}" "${GIT_WORK_TREE:-}" "${GIT_CONFIG_COUNT:-}" "${GIT_CONFIG_PARAMETERS:-}" "${GIT_EXEC_PATH:-}" "${GIT_SSH:-}" \
  "${GIT_TEMPLATE_DIR:-}" "${GIT_EXTERNAL_DIFF:-}" "${GIT_INDEX_FILE:-}" >>"${MARK:?}"
printf 'SSHCMD %s\n' "${GIT_SSH_COMMAND:-}" >>"${MARK:?}"
exit 0
EOF
chmod +x "$SB/fake/git"
export MARK="$SB/mark"
SHA=0123456789abcdef0123456789abcdef01234567

for script in "$INSTALLER" "$UPDATER"; do
  name="${script##*/}"; echo "# $name"
  (
    T_PASS=0; T_FAIL=0   # counted here, added to the parent's totals below
    if [ "$name" = install_constitution.sh ]; then HELIX_INSTALLER_LIB_MODE=1 . "$script"; else HELIX_UPDATER_LIB_MODE=1 . "$script"; fi
    PATH="$SB/fake:$PATH"
    refused() { # description words...
      local d="$1"; shift; : >"$MARK"
      hi_gx "$@" >/dev/null 2>"$SB/err"; local rc=$?
      if [ "$rc" = 3 ] && [ ! -s "$MARK" ] && grep -q '^\[git-allowlist\] ERROR: refused git call' "$SB/err"; then ok "$name refuses: $d"
      else nok "$name refuses: $d (rc=$rc, git reached: $(cat "$MARK"))"; fi
    }
    allowed() { # description expected-recorded words...
      local d="$1" want="$2"; shift 2; : >"$MARK"
      hi_gx "$@" >/dev/null 2>&1; local rc=$?
      if [ "$rc" = 0 ] && [ "$(head -n 1 "$MARK")" = "$want" ]; then ok "$name allows: $d"
      else nok "$name allows: $d (rc=$rc, recorded [$(head -n 1 "$MARK")] want [$want])"; fi
    }
    P=p; x=pu
    refused "push" push origin main
    refused '${P}ush' ${P}ush
    refused "\$'\\x70ush'" $'\x70ush'
    refused 'p\ush' p\ush
    refused 'x=pu; ${x}sh' ${x}sh
    refused '$(printf pu)sh' "$(printf pu)sh"
    refused "send-pack" send-pack origin
    refused "reset --hard" reset --hard
    refused "checkout -f" checkout -f "$SHA"
    refused "checkout -qf" checkout -qf main
    refused "checkout a branch" checkout --detach main
    refused "fetch --force" fetch --force origin
    refused "fetch +refspec" fetch origin '+refs/heads/*:refs/heads/*'
    refused "clone --upload-pack" clone --upload-pack=touch u d
    refused "-c alias" -c 'alias.p=!git push' p
    refused "config core.hooksPath" config core.hooksPath /tmp
    refused "rm without --cached" rm -- x
    refused "commit (no HI_GX_COMMIT_OK)" commit -m x
    refused "init (no HI_GX_INIT_OK)" init
    refused "--git-dir=x push" --git-dir=x push
    refused "no subcommand" -C /x
    # round-4 IMPORTANT-2: fetch/clone/submodule/remote/ls-remote only in the fixed shapes the callers use
    refused "fetch -- origin +refspec (after --)" fetch --quiet -- origin +refs/heads/main:refs/heads/main
    refused "fetch origin +refspec (bare)" fetch --quiet --tags origin +refs/heads/main:refs/heads/main
    refused "fetch --refmap=+..." fetch --quiet origin main '--refmap=+refs/heads/*:refs/heads/*'
    refused "fetch --refmap (separate)" fetch --quiet --tags origin --refmap '+refs/heads/*:refs/heads/*'
    refused "fetch --update-head-ok" fetch --quiet --update-head-ok --tags origin
    refused "fetch with a refspec (not the fixed shape)" fetch --quiet --tags origin main
    refused "fetch from a URL instead of a remote name" fetch --quiet --tags 'ext::sh -c touch% x'
    refused "submodule update --recursive" submodule update --init --recursive
    refused "submodule update --recursive after --" submodule update --init --quiet -- x --recursive
    refused "submodule add ext:: URL" submodule add --quiet -- 'ext::sh -c x' p
    refused "submodule status (unused)" submodule status
    refused "remote set-url to ext::" remote set-url origin 'ext::sh -c touch% /tmp/p'
    refused "remote set-url to an https URL (only absolute paths are set by the installer)" remote set-url origin https://x/y.git
    refused "clone -- --upload-pack=" clone -- '--upload-pack=touch x' d
    refused "clone ext:: URL" clone --quiet --no-checkout -- 'ext::sh -c x' d
    refused "clone without --" clone --quiet --no-checkout u d
    refused "clone extra option" clone --quiet --depth=1 --no-checkout -- u d
    refused "ls-remote ext:: URL" ls-remote --tags -- 'ext::sh -c x'
    refused "ls-remote option-like URL after --" ls-remote -- --upload-pack=x
    refused "add without --" add x
    refused "add a +path" add -- +x
    refused "init with an option" init --template=/tmp
    refused "a +word anywhere (rev-parse)" rev-parse +HEAD
    allowed "fetch fixed shape" "fetch --quiet --tags origin" fetch --quiet --tags origin
    allowed "clone fixed shape" "clone --quiet --filter=blob:none --no-checkout -- u d" clone --quiet --filter=blob:none --no-checkout -- u d
    allowed "submodule update fixed shape" "submodule update --init --quiet -- p" submodule update --init --quiet -- p
    allowed "submodule add fixed shape" "submodule add --quiet -- /x/u.git p" submodule add --quiet -- /x/u.git p
    allowed "remote set-url origin /abs" "remote set-url origin /x/up.git" remote set-url origin /x/up.git
    allowed "ls-remote -- url ref" "ls-remote -- u v1" ls-remote -- u v1
    allowed "ls-remote --tags NAME" "ls-remote --tags origin" ls-remote --tags origin
    # the environment git sees is sanitised (no inherited GIT_* that redirect the repository, config or exec path)
    : >"$MARK"; GIT_DIR=/evil GIT_WORK_TREE=/evil GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.fsmonitor GIT_CONFIG_VALUE_0=x \
      GIT_CONFIG_PARAMETERS="'core.hooksPath'='/tmp'" GIT_EXEC_PATH=/evil GIT_SSH=/evil GIT_TEMPLATE_DIR=/evil \
      GIT_EXTERNAL_DIFF=/evil GIT_SSH_COMMAND=/evil-ssh GIT_INDEX_FILE=/evil hi_gx rev-parse HEAD >/dev/null 2>&1
    eq "$name: git ran" "rev-parse HEAD" "$(head -n 1 "$MARK")"
    eq "$name: inherited GIT_DIR/WORK_TREE/CONFIG_*/EXEC_PATH/SSH/TEMPLATE_DIR/EXTERNAL_DIFF/INDEX_FILE removed" \
       "ENV GIT_DIR= GIT_WORK_TREE= GIT_CONFIG_COUNT= GIT_CONFIG_PARAMETERS= GIT_EXEC_PATH= GIT_SSH= GIT_TEMPLATE_DIR= GIT_EXTERNAL_DIFF= GIT_INDEX_FILE=" \
       "$(sed -n 2p "$MARK")"
    eq "$name: GIT_SSH_COMMAND is the installer's own (BatchMode), never the inherited one" \
       "SSHCMD ssh -o BatchMode=yes -o ConnectTimeout=10" "$(sed -n 3p "$MARK")"
    # git is resolved ONCE to an absolute path: a later PATH change cannot swap the binary
    hi_gx rev-parse HEAD >/dev/null 2>&1; mkdir -p "$SB/fake2"; printf '#!/bin/sh\necho SWAPPED >>"$MARK"\n' >"$SB/fake2/git"; chmod +x "$SB/fake2/git"
    : >"$MARK"; PATH="$SB/fake2:$PATH" hi_gx rev-parse HEAD >/dev/null 2>&1
    eq "$name: a PATH change after the first call does not swap git" "rev-parse HEAD" "$(head -n 1 "$MARK")"
    allowed "rev-parse" "rev-parse HEAD" rev-parse HEAD
    allowed "-C + --no-optional-locks status" "-C /x --no-optional-locks status --porcelain" -C /x --no-optional-locks status --porcelain
    allowed "checkout --detach <sha>" "checkout -q --detach $SHA" checkout -q --detach "$SHA"
    allowed "rm --cached" "rm -q --cached -- x" rm -q --cached -- x
    allowed "protocol.file ls-remote" "-c protocol.file.allow=always ls-remote -- u" -c protocol.file.allow=always ls-remote -- u
    : >"$MARK"; HI_GX_COMMIT_OK=1 hi_gx commit -q -m x -- p >/dev/null 2>&1
    eq "$name: commit reaches git only with HI_GX_COMMIT_OK=1" "commit -q -m x -- p" "$(head -n 1 "$MARK")"
    : >"$MARK"; hi_gx fetch https://user:SECRET@example.invalid/x.git --force 2>"$SB/err" >/dev/null
    check "$name: refusal message does not print URL credentials" eval '! grep -q "user:SECRET" "$SB/err"'
    finish >/dev/null; echo "$T_PASS $T_FAIL" >"$SB/counts.$name"
  )
  read -r p f <"$SB/counts.$name" || { echo "subshell for $name died" >&2; exit 2; }
  T_PASS=$((T_PASS + p)); T_FAIL=$((T_FAIL + f))
done

echo "# REAL git (no fake): a forced fetch refspec never moves a local branch (round-4 IMPORTANT-2)"
RG="$SB/realgit"; mkdir -p "$RG"
git init -q --bare "$RG/up.git"; git clone -q "$RG/up.git" "$RG/w" 2>/dev/null
git -C "$RG/w" commit -q --allow-empty -m base && git -C "$RG/w" push -q origin HEAD:main
git -C "$RG/w" commit -q --allow-empty -m "local only" && keep="$(git -C "$RG/w" rev-parse HEAD)"   # a commit only the local branch has
git -C "$RG/w" checkout -q --detach HEAD; git -C "$RG/w" branch -q -f main "$keep"
mkforced() { # rewrite the upstream main to an unrelated commit, so +refspec would be a forced, commit-dropping move
  git clone -q "$RG/up.git" "$RG/w2" 2>/dev/null && git -C "$RG/w2" checkout -q --orphan o && git -C "$RG/w2" commit -q --allow-empty -m other \
    && git -C "$RG/w2" push -q -f origin o:main; }
mkforced
for form in "fetch --quiet -- origin +refs/heads/main:refs/heads/main" \
            "fetch --quiet origin main --refmap=+refs/heads/*:refs/heads/*" \
            "fetch --quiet --tags origin +refs/heads/main:refs/heads/main" \
            "fetch --update-head-ok --quiet origin +main:main"; do
  out="$( (HELIX_INSTALLER_LIB_MODE=1 . "$INSTALLER"; read -r -a w <<<"$form"; hi_gx -C "$RG/w" "${w[@]}") 2>&1)"; rc=$?
  eq "real git: '$form' refused (exit 3)" 3 "$rc"
  eq "real git: local main NOT moved by '$form'" "$keep" "$(git -C "$RG/w" rev-parse main)"
done
# positive control: the SAME forced refspec through raw git does move the branch (the test can see a move)
cp -a "$RG/w" "$RG/wc"; git -C "$RG/wc" fetch -q -- origin +refs/heads/main:refs/heads/main 2>/dev/null
check "control needle: raw git with the forced refspec DOES move the branch (dropping the local commit)" \
  eval '[ "$(git -C "$RG/wc" rev-parse main)" != "$keep" ]'
out="$( (HELIX_INSTALLER_LIB_MODE=1 . "$INSTALLER"; hi_gx -C "$RG/w" fetch --quiet --tags origin) 2>&1)"; rc=$?
eq "real git: the fixed fetch shape runs (exit 0)" 0 "$rc"; eq "real git: fixed fetch leaves local main alone" "$keep" "$(git -C "$RG/w" rev-parse main)"

echo "# a real install: an inherited HI_GX_COMMIT_OK=1 does not enable a commit"
mkdir -p "$SB/up"; make_upstream "$SB/up" || exit 2
P="$SB/proj"; new_project "$P"; head0="$(git -C "$P" rev-parse HEAD)"
OUT="$(cd "$P" && HI_GX_COMMIT_OK=1 HI_GX_INIT_OK=1 bash "$INSTALLER" --non-interactive --agent none --run-setup off \
       --upstream-url "$SB/up/upstream.git" 2>&1)"; RC=$?
eq "install exit 0" 0 "$RC"; [ "$RC" = 0 ] || printf '%s\n' "$OUT" | tail -6
eq "no commit was made (HEAD unchanged; --commit was not asked)" "$head0" "$(git -C "$P" rev-parse HEAD)"
check "no refusal was needed on a normal run" eval '! grep -q "git-allowlist" <<<"$OUT"'
finish
