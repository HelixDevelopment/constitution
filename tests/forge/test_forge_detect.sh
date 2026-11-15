#!/usr/bin/env bash
# tests/forge/test_forge_detect.sh -- unit tests of `forge.sh detect` and the hosts map (no network).
# CLASS (section 11.4.289(C)(2)): gate-logic / unit. Proves URL parsing, userinfo refusal, the
# unknown-forge GAP, hosts-file validation and --remote resolution. Run: bash tests/forge/test_forge_detect.sh
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/forge/lib.sh
. "$HERE/lib.sh"
ft_init
T=$'\t'
ft_hosts "codeberg.org${T}gitea${T}https://codeberg.org/api/v1${T}CODEBERG_GITEA_TOKEN,CODEBERG_TOKEN${T}Forgejo" \
         "git.m3w.org${T}gitea${T}https://git.m3w.org/api/v1${T}M3W_GITEA_TOKEN${T}Gitea" \
         "gitlab.com${T}gitlab${T}https://gitlab.com/api/v4${T}GITLAB_TOKEN${T}-" \
         "gitflic.ru${T}gitflic${T}https://api.gitflic.ru${T}GITFLIC_TOKEN${T}-" \
         "github.com${T}github${T}https://api.github.com${T}GITHUB_TOKEN,GH_TOKEN${T}-"

ft_run detect --url ssh://git@git.m3w.org:2222/Helix/constitution.git
ft_ok "D1 ssh url with port: rc" "$FT_RC" 0
ft_has "D1 provider" "$FT_OUT" "PROVIDER: gitea"
ft_has "D1 repo" "$FT_OUT" "REPO: Helix/constitution"
ft_has "D1 api" "$FT_OUT" "API: https://git.m3w.org/api/v1"
ft_has "D1 token vars" "$FT_OUT" "TOKEN_VARS: M3W_GITEA_TOKEN"
ft_has "D1 result" "$FT_OUT" "RESULT: OK"

ft_run detect --url git@gitflic.ru:helixdevelopment/helixconstitution.git
ft_ok "D2 scp form: rc" "$FT_RC" 0
ft_has "D2 repo" "$FT_OUT" "REPO: helixdevelopment/helixconstitution"
ft_has "D2 provider" "$FT_OUT" "PROVIDER: gitflic"

ft_run detect --url https://codeberg.org/HelixDevelopment/constitution
ft_ok "D3 https form: rc" "$FT_RC" 0
ft_has "D3 repo (no .git)" "$FT_OUT" "REPO: HelixDevelopment/constitution"

ft_run detect --url git@gitlab.com:group/sub/proj.git
ft_ok "D4 gitlab nested path: rc" "$FT_RC" 0
ft_has "D4 nested repo" "$FT_OUT" "REPO: group/sub/proj"

ft_run detect --url git@github.com:a/b/c.git
ft_ok "D5 nested path on a two-level forge refused: rc" "$FT_RC" 2

ft_run detect --url https://user:secretpw@codeberg.org/o/r.git
ft_ok "D6 https userinfo refused: rc" "$FT_RC" 2
ft_lacks "D6 password not echoed (stdout)" "$FT_OUT" "secretpw"
ft_lacks "D6 password not echoed (stderr)" "$FT_ERR" "secretpw"

ft_run detect --url https://tok@codeberg.org/o/r.git
ft_ok "D7 https user-only userinfo refused: rc" "$FT_RC" 2
# the outcome is protected twice (the userinfo check, and the host validator that never admits "@");
# the explicit check is what tells the operator WHY: assert its message (mutant M03)
ft_has "D7 refused as userinfo (clear reason)" "$FT_ERR" "carries userinfo"
ft_lacks "D7 token-like userinfo not echoed" "$FT_ERR$FT_OUT" "tok@"

ft_run detect --url ssh://git:pw@codeberg.org/o/r.git
ft_ok "D8 ssh password userinfo refused: rc" "$FT_RC" 2

ft_run detect --url git@example.org:o/r.git
ft_ok "D9 unknown host: rc GAP" "$FT_RC" 3
ft_has "D9 reason" "$FT_OUT" "REASON: unknown_forge"

ft_run detect --url 'git@codeberg.org:o/r;rm.git'
ft_ok "D10 unsafe characters refused: rc" "$FT_RC" 2

ft_run detect --url 'git@codeberg.org:../r.git'
ft_ok "D11 dot segment refused: rc" "$FT_RC" 2

ft_run detect --url http://codeberg.org/o/r.git
ft_ok "D12 plain http remote refused: rc" "$FT_RC" 2

ft_run detect --url ssh://git@CodeBerg.ORG/o/r.git
ft_ok "D13 host case-insensitive: rc" "$FT_RC" 0

# hosts file validation
ft_hosts "codeberg.org${T}bogus${T}https://codeberg.org/api/v1${T}X_TOKEN${T}-"
ft_run detect --url git@codeberg.org:o/r.git
ft_ok "H1 unknown provider in hosts file: rc" "$FT_RC" 2
ft_has "H1 reason" "$FT_OUT" "REASON: hosts_file_invalid"

ft_hosts "codeberg.org${T}gitea${T}http://codeberg.org/api/v1${T}X_TOKEN${T}-"
ft_run detect --url git@codeberg.org:o/r.git
ft_ok "H2 http api base for a non-loopback host refused: rc" "$FT_RC" 2

ft_hosts "codeberg.org${T}gitea${T}https://u:p@codeberg.org/api/v1${T}X_TOKEN${T}-"
ft_run detect --url git@codeberg.org:o/r.git
ft_ok "H3 api base with userinfo refused: rc" "$FT_RC" 2

ft_hosts "codeberg.org${T}gitea${T}https://codeberg.org/api/v1${T}lower_token${T}-"
ft_run detect --url git@codeberg.org:o/r.git
ft_ok "H4 token variable name must be upper case and end in TOKEN: rc" "$FT_RC" 2

ft_hosts "codeberg.org${T}gitea${T}https://codeberg.org/api/v1${T}PATH${T}-"
ft_run detect --url git@codeberg.org:o/r.git
ft_ok "H5 token variable PATH refused: rc" "$FT_RC" 2

# the shipped hosts map is valid and covers the six forges
FT_SAVE="$FT_SBX/hosts.tsv"
cp -- "$FT_ROOT/config/forge/hosts.tsv" "$FT_SAVE"
for u in git@github.com:HelixDevelopment/HelixConstitution.git git@gitlab.com:helixdevelopment1/helixconstitution.git \
         ssh://git@codeberg.org/HelixDevelopment/constitution.git ssh://git@git.m3w.org:2222/Helix/constitution.git \
         git@gitflic.ru:helixdevelopment/helixconstitution.git git@gitverse.ru:helixdevelopment/HelixConstitution.git; do
  ft_run detect --url "$u"
  ft_ok "S shipped map knows $u" "$FT_RC" 0
done
ft_run detect --url git@gitverse.ru:helixdevelopment/HelixConstitution.git
ft_has "S gitverse provider" "$FT_OUT" "PROVIDER: gitverse"
ft_has "S gitverse api" "$FT_OUT" "API: https://api.gitverse.ru"

# --remote resolution from a git repository (no network)
mkdir -p "$FT_SBX/repo" && git -C "$FT_SBX/repo" init -q && git -C "$FT_SBX/repo" remote add m3w ssh://git@git.m3w.org:2222/Helix/constitution.git
(cd "$FT_SBX/repo" && ft_run detect --remote m3w && printf '%s\n%s\n' "$FT_RC" "$FT_OUT" >"$FT_SBX/r1")
ft_ok "R1 --remote rc" "$(head -1 "$FT_SBX/r1")" 0
ft_has "R1 --remote repo" "$(cat "$FT_SBX/r1")" "REPO: Helix/constitution"
(cd "$FT_SBX/repo" && ft_run detect --remote nosuch && printf '%s\n' "$FT_RC" >"$FT_SBX/r2")
ft_ok "R2 unknown remote: rc usage" "$(head -1 "$FT_SBX/r2")" 2
(cd "$FT_SBX/repo" && ft_run detect --remote 'a;b' && printf '%s\n' "$FT_RC" >"$FT_SBX/r3")
ft_ok "R3 unsafe remote name: rc usage" "$(head -1 "$FT_SBX/r3")" 2

ft_run detect
ft_ok "U1 neither --remote nor --url: rc" "$FT_RC" 2
ft_run frobnicate --url git@codeberg.org:o/r.git
ft_ok "U2 unknown command: rc" "$FT_RC" 2
ft_has "U2 result usage" "$FT_OUT" "RESULT: USAGE"

ft_done
