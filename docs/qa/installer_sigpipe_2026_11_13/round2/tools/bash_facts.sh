#!/usr/bin/env bash
# bash_facts.sh BASHES_DIR BASE_ROOT NEW_ROOT OUT_DIR — measures the bash facts the round-2 README relies on and writes
# one text file per fact into OUT_DIR. Read-only for both trees: it runs the installers with --help, --version and
# --print-snippets only (no network, nothing installed).
#   herestring_storage.txt  where each bash keeps a here-string: a pipe or a temporary file, by size and BASH_COMPAT
#   notemp_emulation.txt    what each bash does with a here-string when no temporary file can be written
#   awk_strnum.txt          the awk numeric-string comparison that made the base hi_resolve_ref_in pick a wrong tag
#   old_bash_version_gate.txt  the installers' version gate under bash 3.2.57 and 5.0.17, clean and under POSIXLY_CORRECT
#   base_notemp_help.txt    base and new installer --help / --print-snippets with no temporary file
# BASHES_DIR holds <version>/bin/bash for every copied bash; the host bash is always measured too.
# Exit 0 when every file was written, 2 on a usage error.
set -u
bashes="${1:?BASHES_DIR}"; base="${2:?BASE_ROOT}"; new="${3:?NEW_ROOT}"; out="${4:?OUT_DIR}"
[ -d "$bashes" ] && [ -f "$base/scripts/install_constitution.sh" ] && [ -f "$new/scripts/install_constitution.sh" ] || {
  echo "bash_facts: usage: BASHES_DIR BASE_ROOT NEW_ROOT OUT_DIR" >&2; exit 2; }
mkdir -p "$out" || exit 2
tmp="$(mktemp -d "${TMPDIR:-/tmp}/bfacts.XXXXXX")" || exit 2
export TMPDIR="$tmp"

list=(/usr/bin/bash)
for b in "$bashes"/*/bin/bash; do [ -x "$b" ] && list+=("$b"); done
run() { env -u LD_PRELOAD -u LD_LIBRARY_PATH "$@"; }   # the copied musl bashes must not see a host preload
ver() { run "$1" -c 'echo "$BASH_VERSION"'; }

# 1. Here-string storage. N is the length of the word; bash appends one newline, so the document is N+1 bytes.
#    readlink of the reader's fd 0 prints pipe:[...] for a pipe and the temporary file's path for a file.
probe='n=$1; s=$(head -c "$n" /dev/zero | tr "\0" x); readlink /proc/self/fd/0 <<<"$s"'
{
  echo "# where the here-string is kept; size = word length in bytes (the document is one byte longer, the newline)"
  echo "# columns: default settings; then BASH_COMPAT=50 at 100 bytes and at 102400 bytes"
  for b in "${list[@]}"; do
    case "$(ver "$b")" in 3.*) continue ;; esac   # bash 3.2 cannot run the installer; its gate is measured in 4.
    line="$(ver "$b"):"
    for n in 4095 4096 8190 8191 8192 16384 65536 131072; do
      r="$(run "$b" -c "$probe" _ "$n" 2>&1)"; case "$r" in pipe:*) k=pipe ;; /*) k=file ;; *) k="?($r)" ;; esac
      line="$line $n:$k"
    done
    line="$line |"
    for n in 100 102400; do
      r="$(BASH_COMPAT=50 run "$b" -c "$probe" _ "$n" 2>&1)"; case "$r" in pipe:*) k=pipe ;; /*) k=file ;; *) k="?($r)" ;; esac
      line="$line compat50:$n:$k"
    done
    echo "$line"
  done
} >"$out/herestring_storage.txt" 2>&1

# 2. No temporary file: ulimit -f 0 makes the temporary-file write fail (EFBIG); SIGXFSZ is ignored so bash sees the
#    error instead of being killed. The 102400-byte word is kept in a file by every bash measured in 1.
{
  echo "# here-string read by cat while no temporary file can be written (trap '' XFSZ; ulimit -f 0)"
  for b in "${list[@]}"; do
    case "$(ver "$b")" in 3.*) continue ;; esac
    for c in default 50; do
      for n in 100 102400; do
        r="$( (trap '' XFSZ; ulimit -f 0
               if [ "$c" = default ]; then run "$b" -c 's=$(head -c "$1" /dev/zero | tr "\0" x); cat <<<"$s" | wc -c; echo "rc=${PIPESTATUS[0]}"' _ "$n"
               else BASH_COMPAT=50 run "$b" -c 's=$(head -c "$1" /dev/zero | tr "\0" x); cat <<<"$s" | wc -c; echo "rc=${PIPESTATUS[0]}"' _ "$n"; fi) 2>&1 | tr '\n' ' ')"
        printf '%s BASH_COMPAT=%s size=%s: %s\n' "$(ver "$b")" "$c" "$n" "$r"
      done
    done
  done
} >"$out/notemp_emulation.txt" 2>&1

# 3. awk numeric strings: the base compared the ref with awk -v n="$ref" '$1 == n'. Both "1.0" and "1.00" look numeric,
#    so awk compares them as numbers and the first line matches.
{
  echo "# input lines: '1.0 aaaa' then '1.00 bbbb'; program: awk -v n=1.00 '\$1 == n {print \$2; exit}'"
  for a in awk gawk mawk "busybox awk"; do
    set -- $a
    command -v "$1" >/dev/null 2>&1 || { echo "$a: not installed"; continue; }
    r="$(printf '1.0 aaaa\n1.00 bbbb\n' | "$@" -v n=1.00 '$1 == n {print $2; exit}' 2>&1)"
    echo "$a ($(command -v "$1")): ref 1.00 -> $r (bbbb is the right answer)"
  done
} >"$out/awk_strnum.txt" 2>&1

# 4. The version gate (env -i clears LD_PRELOAD). bash 3.2 must get the "bash 4.4 or newer" message; under POSIXLY_CORRECT the base did not parse.
{
  for v in 3.2.57 5.0.17; do
    b="$bashes/$v/bin/bash"; [ -x "$b" ] || { echo "== bash $v: not available"; continue; }
    for side in base new; do
      if [ "$side" = base ]; then r="$base"; else r="$new"; fi
      for mode in clean posix; do
        if [ "$mode" = clean ]; then o="$(cd "$tmp" && env -i PATH=/usr/bin:/bin HOME="$tmp" "$b" "$r/scripts/install_constitution.sh" --version 2>&1)"; rc=$?
        else o="$(cd "$tmp" && env -i PATH=/usr/bin:/bin HOME="$tmp" POSIXLY_CORRECT=1 "$b" "$r/scripts/install_constitution.sh" --version 2>&1)"; rc=$?; fi
        printf '== bash %s, %s installer, %s --version: %s rc=%s\n' "$v" "$side" "$mode" "$(printf '%s' "$o" | tr '\n' ' ')" "$rc"
      done
    done
  done
} >"$out/old_bash_version_gate.txt" 2>&1

# 5. --help and --print-snippets with no temporary file, base and new (host bash, BASH_COMPAT=50 so that even a small
#    here-document goes to a file), plus --version under POSIXLY_CORRECT=1. Output is captured through a pipe, which
#    ulimit -f does not limit.
{
  for flag in --help --print-snippets; do
    for side in base new; do
      if [ "$side" = base ]; then r="$base"; else r="$new"; fi
      o="$( (cd "$tmp" && trap '' XFSZ && ulimit -f 0 && env -i PATH=/usr/bin:/bin HOME="$tmp" BASH_COMPAT=50 \
              bash "$r/scripts/install_constitution.sh" "$flag"; echo "rc=$?") 2>&1)"
      printf '== %s %s, no writable temporary file: %s bytes of output; messages: %s; %s\n' "$side" "$flag" \
        "$(printf '%s' "$o" | wc -c | tr -d ' ')" \
        "$(printf '%s\n' "$o" | grep -E 'cannot create temp|rror' | head -3 | tr '\n' ' ')" "$(printf '%s\n' "$o" | tail -1)"
    done
  done
  for side in base new; do
    if [ "$side" = base ]; then r="$base"; else r="$new"; fi
    o="$(cd "$tmp" && env -i PATH=/usr/bin:/bin HOME="$tmp" POSIXLY_CORRECT=1 bash "$r/scripts/install_constitution.sh" --version 2>&1)"; rc=$?
    printf '== %s --version under POSIXLY_CORRECT=1: %s rc=%s\n' "$side" "$(printf '%s' "$o" | tr '\n' ' ')" "$rc"
  done
} >"$out/base_notemp_help.txt" 2>&1

rm -rf -- "${tmp:?}"
exit 0
