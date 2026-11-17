#!/usr/bin/env bash
# scripts/forge/live_probe.sh -- LIVE, READ-ONLY proof of scripts/forge/forge.sh against the real forges.
#
# Usage: scripts/forge/live_probe.sh OUT_DIR [--tag TAG]
#
# For every upstream declared in upstreams/*.sh (the line `export UPSTREAMABLE_REPOSITORY="<url>"`, PARSED,
# never sourced) it runs `forge.sh probe --url <url>`. With --tag it also runs `forge.sh tag-get` and
# `forge.sh release-get` for TAG on every upstream and writes them to OUT_DIR/readpaths.txt. Every command
# makes HTTP GET requests only: the repository, its release list, its tag list (Gitea/Forgejo also /version),
# the tag and the release of TAG. It prints the HTTP status and the JSON KEY NAMES of each answer, never a
# value. No release, tag or setting is created or changed.
# Endpoint identity (section 11.4.289(D)): the runs set FORGE_TRACE_PEER=1, so every answer also prints a
# "PEER:" line (resolved IP and port, HTTP version, curl's ssl_verify_result, sha256 of the leaf
# certificate, its subject, and the provider's request id header when one is sent), and every PROBE line
# carries the same fields.
# Output: OUT_DIR/<upstream>.txt (forge.sh stdout + stderr, rc), OUT_DIR/readpaths.txt (with --tag),
# OUT_DIR/summary.tsv, OUT_DIR/tool_fingerprint.txt (commit + sha256 of every file of scripts/forge),
# OUT_DIR/leak_check.txt, OUT_DIR/SHA256SUMS.
# Before writing the sums it scans EVERY output file for every token value forge.sh's sanitiser knows of
# (lib/credentials.sh fg_secrets_load: all hosts-map names, the environment, the keys file and the .env files,
# with the SAME parser and file checks), every 12-character part of each value included. A value reaches grep
# through a pipe (never an argv, never a file). Each file first has to show a known string (a per-file
# control needle) and not a known-absent one. It refuses (exit 1, files removed) if any value appears.
# FORGE_HOSTS_FILE (default config/forge/hosts.tsv) names the hosts map, as for forge.sh.
# Exit: 0 all probes ran (whatever the forges answered), 1 leak detected, blind leak check or no upstream
# found, 2 usage.
# Class (section 11.4.289): LIVE evidence (real forges, real network); it proves the READ paths only.
set +x +a
set -u
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
OUT="" TAG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --tag) [ $# -ge 2 ] || { printf 'usage: %s OUT_DIR [--tag TAG]\n' "$0" >&2; exit 2; }; TAG="$2"; shift 2 ;;
    -*) printf 'usage: %s OUT_DIR [--tag TAG]\n' "$0" >&2; exit 2 ;;
    *) [ -z "$OUT" ] || { printf 'usage: %s OUT_DIR [--tag TAG]\n' "$0" >&2; exit 2; }; OUT="$1"; shift ;;
  esac
done
[ -n "$OUT" ] || { printf 'usage: %s OUT_DIR [--tag TAG]\n' "$0" >&2; exit 2; }
if [ -n "$TAG" ]; then [[ $TAG =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]] || { printf 'bad tag\n' >&2; exit 2; }; fi
mkdir -p -- "$OUT" || exit 2
OUT="$(cd "$OUT" && pwd)"
export FORGE_TRACE_PEER=1

: >"$OUT/summary.tsv"
printf 'upstream\tprovider\trc\tresult\treason\n' >>"$OUT/summary.tsv"
[ -z "$TAG" ] || printf '# live read-only tag-get + release-get for tag %s at %s\n# command: scripts/forge/live_probe.sh OUT_DIR --tag %s (forge.sh tag-get/release-get --url <the URL of upstreams/NAME.sh> --tag %s)\n' \
  "$TAG" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$TAG" "$TAG" >"$OUT/readpaths.txt"
n=0
for f in "$ROOT"/upstreams/*.sh; do
  [ -f "$f" ] || continue
  name="$(basename "$f" .sh)"
  url="$(sed -n 's/^[[:space:]]*export[[:space:]]\{1,\}UPSTREAMABLE_REPOSITORY="\([^"$`\\]*\)"[[:space:]]*$/\1/p' "$f" | head -1)"
  [ -n "$url" ] || { printf 'skip %s: no UPSTREAMABLE_REPOSITORY line\n' "$name" >&2; continue; }
  n=$((n + 1))
  {
    printf '# live read-only probe of upstream %s at %s\n' "$name" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '# command: scripts/forge/forge.sh probe --url <the URL of upstreams/%s.sh> (FORGE_TRACE_PEER=1)\n' "$name"
    nice -n 10 "$ROOT/scripts/forge/forge.sh" probe --url "$url" 2>&1
    printf '# rc=%s\n' "$?"
  } >"$OUT/$name.txt"
  rc="$(sed -n 's/^# rc=//p' "$OUT/$name.txt")"
  prov="$(sed -n 's/^PROVIDER: //p' "$OUT/$name.txt" | head -1)"
  res="$(sed -n 's/^RESULT: //p' "$OUT/$name.txt" | tail -1)"
  rea="$(sed -n 's/^REASON: //p' "$OUT/$name.txt" | tail -1)"
  printf '%s\t%s\t%s\t%s\t%s\n' "$name" "${prov:--}" "$rc" "${res:--}" "${rea:--}" >>"$OUT/summary.tsv"
  if [ -n "$TAG" ]; then
    for c in tag-get release-get; do
      {
        printf '## %s %s\n' "$name" "$c"
        nice -n 10 "$ROOT/scripts/forge/forge.sh" "$c" --url "$url" --tag "$TAG" 2>&1
        printf '# rc=%s\n' "$?"
      } >>"$OUT/readpaths.txt"
    done
  fi
done
[ "$n" -gt 0 ] || { printf 'no upstream found under upstreams/\n' >&2; exit 1; }

# ---- tool fingerprint (review finding R2-m4): which code produced this evidence -------------------------------
{
  printf '# fingerprint of the tool that produced this evidence (sha256 of every file of scripts/forge)\n'
  printf 'commit: %s\n' "$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo none)"
  if [ -n "$(git -C "$ROOT" status --porcelain -- scripts/forge 2>/dev/null)" ]; then printf 'scripts_forge_dirty: yes\n'; else printf 'scripts_forge_dirty: no\n'; fi
  ( cd "$ROOT" && find scripts/forge -type f -print | LC_ALL=C sort | while IFS= read -r f; do sha256sum -- "$f"; done )
} >"$OUT/tool_fingerprint.txt"

# ---- leak check ------------------------------------------------------------------------------------------
# the same token sources, parser and value set as forge.sh's output sanitiser (lib/credentials.sh
# fg_secrets_load: every *TOKEN name of EVERY hosts-map row, of the environment, of the keys file and of the
# .env files), and the same 12-character windows (lib/common.sh _fg_windows): a part of a token counts too.
# shellcheck source=scripts/forge/lib/common.sh
. "$ROOT/scripts/forge/lib/common.sh" || exit 1
# shellcheck source=scripts/forge/lib/credentials.sh
. "$ROOT/scripts/forge/lib/credentials.sh" || exit 1
FG_REPO_ROOT="$(cd "$ROOT" && pwd -P)" FG_DIR_PHYS="$(cd "$ROOT/scripts/forge" && pwd -P)"
hf="${FORGE_HOSTS_FILE:-$ROOT/config/forge/hosts.tsv}"
FG_ALL_TOKEN_VARS="$(awk -F'\t' '!/^#/ && NF>=4 {print $4}' "$hf" | paste -sd, -)"
fg_secrets_load || { printf 'leak check is blind: the keys file could not be read to its end\n' >&2; exit 1; }
files=()
for f in "$OUT"/*; do [ -f "$f" ] && files+=("$f"); done
# the needle(s) go through a pipe (never an argv, never a file)
hasin() { local n="$1"; shift; grep -qF -f <(printf '%s\n' "$n") -- "$@"; }
hasany() { grep -qF -f <(_fg_windows "$1") -- "${files[@]}"; }
# control needles (section 11.4.273(f)): PER FILE, the same grep path must find a string known to be in that
# file, and must not find one known to be absent
for f in "${files[@]}"; do
  case "${f##*/}" in
    summary.tsv) needle="$(printf 'upstream\tprovider')" ;;
    tool_fingerprint.txt) needle='scripts/forge/forge.sh' ;;
    *) needle='RESULT:' ;;   # every forge.sh run ends with a RESULT line, whatever the forge answered
  esac
  hasin "$needle" "$f" || { printf 'leak check is blind: control needle not found in %s\n' "${f##*/}" >&2; exit 1; }
  ! hasin 'NO_SUCH_STRING_9f3c1e' "$f" || { printf 'leak check is broken: negative control matched in %s\n' "${f##*/}" >&2; exit 1; }
done
# the PEER fields come from the server: at least one file must show them to the same instrument
hasin 'PEER' "${files[@]}" || { printf 'leak check is blind: control needle PEER not found\n' >&2; exit 1; }
leak=0 checked="${#FG_SEC_VALS[@]}"
for i in "${!FG_SEC_VALS[@]}"; do
  if hasany "${FG_SEC_VALS[$i]}"; then leak=1; printf 'LEAK: a value (or a 12-character part) of %s appears in the output\n' "${FG_SEC_NAMES[$i]}" >&2; fi
done
FG_SEC_VALS=()
if [ "$leak" -ne 0 ]; then
  for f in "${files[@]}"; do rm -f -- "$f"; done
  exit 1
fi
{ printf 'leak check: per-file positive controls found, negative control absent in every file\n'
  printf 'token values checked (all hosts, env, keys file, .env; values never printed): %s\n' "$checked"
  printf 'files scanned: %s\n' "${#files[@]}"
  for f in "${files[@]}"; do printf '  %s\n' "${f##*/}"; done
  printf 'result: no checked value, and no 12-character part of one, appears in any scanned file\n'
} >"$OUT/leak_check.txt"
( cd "$OUT" && rm -f -- SHA256SUMS && sha256sum -- *.txt summary.tsv >SHA256SUMS )
cat "$OUT/summary.tsv"
exit 0
