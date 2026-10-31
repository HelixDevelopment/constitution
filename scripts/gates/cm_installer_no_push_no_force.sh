#!/usr/bin/env bash
# cm_installer_no_push_no_force.sh — CM-INSTALLER-NO-PUSH-NO-FORCE gate.
#
# ── Purpose ───────────────────────────────────────────────────────────────
# The installer and the updater promise: never push, never force, never rewrite history, never delete
# recursively, never run dynamic code (§11.4.113, §9.2, §11.4.287). A lexical denylist cannot be complete
# (`git ${P}ush`, `$'\x70ush'`, `printf … | bash`, `p\ush` all hide the word), so the promise rests on an
# ALLOW-LIST enforced at runtime and on a ban of every way around it. Scanned (default):
#   scripts/install_constitution.sh and scripts/update_constitution.sh
#
# ── Checks ────────────────────────────────────────────────────────────────
#  (a) STRUCTURE. A shell lexer (quotes, $(…), backticks, ${…}, $'…', heredocs, arrays, case patterns, [[ ]])
#      finds every simple command, also inside $(…) and backticks, and fails on: `git` as a command anywhere
#      outside the two exact lines in hi_gx (also behind command/env/timeout/xargs/nice/exec/hi_user_umask …);
#      a command word that is dynamic ($var, "$@", $(…), `…`, $'…'); eval; source / .; bash/sh/zsh/… other
#      than the listed exact script runs (so no -c, no stdin, no pipe or here-string into a shell); python -c
#      with a non-literal program; a non-quoted heredoc feeding python; perl/ruby/node/php/lua; find -exec/-delete;
#      a recursive rm; `alias`; a second definition of hi_gx / hi_gx_check / hi_gx_refuse, or a function named
#      git/command; a git word inside an array literal; and every hi_gx / hi_git / hi_git_url call whose
#      subcommand is dynamic, unknown, or not on the allow-list, or whose -c is not protocol.file.allow=always.
#      The few dynamic executions the scripts need are listed below as EXACT (function, command text) pairs;
#      editing such a line makes it a finding again.
#      ALLOW-LIST OF EXTERNAL COMMANDS: every command word that is not a function of the file, a shell builtin on
#      the SAFE list, a git wrapper or a handled form must be on the external allow-list, with its permitted
#      argument shape: read-only utilities (cat, grep, tr, ... with no output-file option), and the file-changing
#      ones (remove, mkdir, rmdir, mktemp, chmod, kill, touch, cp, ln, mv) only as an exact (function, command text)
#      pair; sed and awk only with a program text that is listed (no -i, -f, w/e/r commands, system(), getline);
#      python only with a literal program (-c LITERAL, or - with a quoted heredoc) that passes an AST check
#      (imports from a short list; no open() for writing, exec/eval/compile/__import__, no os/subprocess/...); a
#      git call that changes anything (add, rm, checkout, commit, init, clone, fetch, submodule, config writes,
#      remote set-url) only as an exact (function, command text) pair. Anything else (tar, patch, unlink, ex,
#      ed, perl, ...) FAILs as "not on the allow-list". (This replaces a deny-list that every new command word
#      could walk around.)
#      WRITE POLICY: a write to a name that changes what git or the shell runs (PATH, BASH_ENV, LD_*, GIT_* other
#      than GIT_TERMINAL_PROMPT, HI_GX_COMMIT_OK/INIT_OK/BIN, …) in any form (assignment, prefix, export/declare/
#      local/readonly, env NAME=, printf -v, read/mapfile, for NAME, (( … )), nameref -n) is allowed only at the
#      exact sanctioned places; dynamic variable names, non-literal traps (a literal trap is walked as code),
#      truncate/shred/dd/tee/let/…, recursive chmod/chown/chgrp and sed -i are findings; every redirection that
#      writes a file must target /dev/null, an fd, or one exact (function, operator, target) place; the wrapper
#      switches must occur an exact number of times outside the block. hi_gx calls must use the exact argument
#      shapes (fetch --quiet --tags REMOTE, clone --quiet [--filter=blob:none] --no-checkout -- URL DIR, …), and
#      no argument may start with "+" or contain "::" (forced refspec / transport helper).
#  (b) ALLOW-LIST. The case labels of hi_gx_check are extracted: every label must be a known safe subcommand,
#      none may be push/send-pack/reset/rebase/filter-branch/update-ref/clean/tag/branch/switch/…, the default
#      `*)` must refuse, HI_GX_COMMIT_OK=1 must be set exactly once per file, and the `# >>> hi_gx … # <<< hi_gx`
#      block must be byte-identical in every scanned file that carries it.
#  (c) RAW denylist (defence in depth, outside hi_gx_check, comments and message carriers removed): push,
#      send-pack, --force, reset, rebase, filter-branch, update-ref, clean -f, checkout -f/-B, branch -D, tag -f,
#      switch, --amend, recursive rm (also `-f -r`), -delete, -exec, eval, awk system()/getline, python
#      subprocess/os.system, ANSI-C escapes $'\…'.
#  (d) RUNTIME. Each script is sourced in library mode with a FAKE git first on PATH (it only records calls)
#      and hi_gx is called with every forbidden subcommand and option form, including obfuscated spellings
#      (${P}ush, $'\x70ush', p\ush, x=pu; ${x}sh, $(printf pu)sh, -c alias…, --git-dir…): each must return 3
#      and never reach git. Allowed forms must reach the fake git (control needle: the recorder can see).
#      The fake git also records its environment: every call must see GIT_DIR/GIT_CONFIG_*/GIT_EXEC_PATH/… unset
#      and the installer's own GIT_SSH_COMMAND, and a PATH change after the first call must not swap the binary.
#      Every guard layer is also exercised on its own (a read-only subcommand with --force, -f, --refmap,
#      --recursive, "::" or "+"; commit in its exact shape without HI_GX_COMMIT_OK), so weakening one layer is
#      seen even where a stricter per-subcommand shape would still refuse the dangerous form.
# Control needles (§11.4.273): the lexer must flag a set of planted hiding shapes and must not flag comments,
# message carriers, data heredocs and [[ =~ ]] regexes; otherwise the instrument is blind and the gate says BLIND.
#
# ── Residual boundary (stated, not hidden) ────────────────────────────────
# BEST-EFFORT TRIPWIRE, NOT A PROOF (operator decision 2026-10-31, like the destructive-path guard). KNOWN LIMITS:
# (1) a path PRODUCER inside a pinned helper that uses a command substitution or a printf of another value (for
# example hi_marker_path printing .gitmodules) is not recognised — only lines that BIND a pinned variable (plain,
# += , NAME[i]=, ${NAME:=v}, local/declare/read/…, for, printf -v, (( ))) and duplicate function definitions (also ones nested in another function body, if they start their line; a definition sharing a line with other code is a further limit) are;
# (2) a value passed as a function argument is pinned at its binding, not at the callers; (3) unmodelled binding
# forms (namerefs, ${!x}, indirect expansion) are caught only by the raw switch-token counts. The real protection
# is the runtime tests (ls-remote hashes of real bare upstreams identical before/after; every forbidden git form
# refused). These limits are listed in docs/guides/installer_user_guide.md ("No-push source gate").
# A malicious edit that adds a raw `command git push` is caught by (a); a fully dynamic construct is caught by
# (a)'s ban on dynamic execution; a change of the wrapper itself is caught by (b) and (d). NOT covered: what
# an AGENT does inside its own run (the installer passes the prompt "push: never" but cannot police the agent),
# what setup.sh / post_update_hook.sh / jev bootstrap do (other files with their own gates), and the user's own
# alias file sourced for a provider alias (the user's code).
#
# ── Usage ─────────────────────────────────────────────────────────────────
#   cm_installer_no_push_no_force.sh [--file FILE]...   (default: the two scripts above)
# ── Exit codes ────────────────────────────────────────────────────────────
#   0 PASS · 1 FAIL (findings printed file:line) · 2 BLIND · 64 usage
# Read-only (runtime checks run in a mktemp -d sandbox with a fake git). Paired mutation test:
# cm_installer_no_push_no_force_mutation_test.sh. Classification: universal (§11.4.17).
set -uo pipefail
GATE="CM-INSTALLER-NO-PUSH-NO-FORCE"
const="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." && pwd)"
files=()
while [ $# -gt 0 ]; do
  case "$1" in
    --file) [ $# -ge 2 ] || { echo "$GATE: --file needs a value" >&2; exit 64; }; files+=("$2"); shift 2 ;;
    -h|--help) sed -n '2,/^set -uo pipefail$/p' "${BASH_SOURCE[0]:-$0}" | sed '$d'; exit 0 ;;
    *) echo "$GATE: unknown argument $1" >&2; exit 64 ;;
  esac
done
[ "${#files[@]}" -gt 0 ] || files=("$const/scripts/install_constitution.sh" "$const/scripts/update_constitution.sh")
for f in "${files[@]}"; do [ -r "$f" ] || { echo "⚠ $GATE: BLIND (exit 2) — cannot read $f"; exit 2; }; done
command -v python3 >/dev/null 2>&1 || { echo "⚠ $GATE: BLIND (exit 2) — python3 not found"; exit 2; }
exec python3 -I - "${files[@]}" <<'PYGATE'
import os, re, subprocess, sys, tempfile

GATE = "CM-INSTALLER-NO-PUSH-NO-FORCE"
ALLOW = {"rev-parse", "rev-list", "ls-files", "ls-tree", "ls-remote", "status", "show", "log", "diff",
         "merge-base", "for-each-ref", "cat-file", "check-ref-format", "clone", "fetch", "add", "checkout",
         "rm", "config", "remote", "submodule", "commit", "init"}
FORBIDDEN_SUB = {"push", "send-pack", "receive-pack", "reset", "rebase", "filter-branch", "filter-repo",
                 "update-ref", "clean", "tag", "branch", "switch", "restore", "merge", "pull", "gc", "prune",
                 "replace", "notes", "stash", "worktree", "am", "apply", "cherry-pick", "revert", "mv",
                 "symbolic-ref", "reflog", "fast-import", "daemon", "upload-pack", "http-push", "bundle",
                 "maintenance", "repack", "pack-refs", "sparse-checkout", "bisect", "*"}
SHELLS = {"bash", "sh", "dash", "zsh", "ksh", "mksh", "ash", "busybox", "fish", "tcsh", "csh"}
INTERP = {"perl", "ruby", "node", "nodejs", "php", "lua", "tclsh", "osascript"}
WRAPPERS = {"command", "builtin", "exec", "env", "timeout", "nice", "nohup", "setsid", "stdbuf", "ionice", "chrt",
            "taskset", "flock", "unbuffer", "sudo", "doas", "time", "xargs", "hi_user_umask", "watch", "parallel",
            "chroot", "runuser", "su", "script", "strace", "ltrace", "valgrind", "faketime", "unshare", "nsenter"}
WRAP_ARG = {"env": {"-u", "--unset", "-C", "--chdir", "-S"}, "timeout": {"-s", "--signal", "-k", "--kill-after"},
            "nice": {"-n", "--adjustment"}, "xargs": {"-I", "-n", "-P", "-L", "-d", "-a", "-E", "-s"},
            "ionice": {"-c", "-n", "-p"}, "flock": {"-w", "-E"}, "exec": {"-a"}, "chrt": set(), "sudo": {"-u", "-g"}}
GITWRAP = {"hi_gx", "hi_git", "hi_git_url"}
RESERVED = {"if", "then", "else", "elif", "fi", "do", "done", "while", "until", "!", "{", "}", "time", "esac"}
# The few dynamic executions the scripts need: (function, exact command text from the command word on).
EXEMPT = {
    "install_constitution.sh": [
        ("hi_ask", '"$__f" "$__a"', "runs the validator function named by the caller (literal hi_* names)"),
        ("hi_user_umask", '"$@"', "runs the caller's command; every caller is analysed as a wrapped command"),
        ("hi_version_of", '"$1" --version', "prints the version of a detected agent binary (command -v path)"),
        ("hi_run_agent", '"${cmd[@]}"', "runs the agent command array built from fixed literals in hi_run_agent"),
        ("hi_gx", '"$HI_GX_BIN" ${pre[@]+"${pre[@]}"} "$@"', "the allow-listed git call (absolute path, both forms)"),
        (None, 'bash "$0" "$@"', "re-executes this file under bash (POSIX header)"),
        ("hi_do_update", 'bash "$upd" "${a[@]}"', "runs the constitution's own updater script"),
        ("main", 'bash "$HI_SUB/scripts/setup.sh"', "runs the constitution's setup.sh (consented)"),
        ("hi_manifest_step", 'bash "$v" --scaffold . --write', "the constitution's own manifest scaffold (never overwrites)"),
        ("hi_manifest_step", 'bash "$v" --validate-file helix-deps.yaml', "the constitution's own manifest validator (read-only)"),
        ("main", 'bash "$S_SUBREL/scripts/jev/bootstrap.sh" "${jb[@]}"', "runs the Jev bootstrap (consented)"),
    ],
    "update_constitution.sh": [
        ("hi_gx", '"$HI_GX_BIN" ${pre[@]+"${pre[@]}"} "$@"', "the allow-listed git call (absolute path, both forms)"),
        (None, 'bash "$SUB/scripts/post_update_hook.sh" ${hook_args[@]+"${hook_args[@]}"}',
         "runs the constitution's post-update hook (args: --project-root \"$ROOT\" or nothing)"),
    ],
}

# Names whose value changes what git or the shell runs, or the wrapper's own switches. Writing one is allowed only
# at the EXACT places listed below (function, name, whole command text); any other write — plain or prefix
# assignment, export/declare/typeset/local/readonly, env NAME=, printf -v, read/mapfile, for NAME, (( NAME=… )),
# unset of a wrapper switch — is a finding. GIT_TERMINAL_PROMPT is the one GIT_* name a script may set freely.
PROTECTED = {"PATH", "BASH_ENV", "ENV", "LD_PRELOAD", "LD_LIBRARY_PATH", "LD_AUDIT", "SHELLOPTS", "BASHOPTS",
             "PROMPT_COMMAND", "PS4", "CDPATH", "GLOBIGNORE", "HI_GX_COMMIT_OK", "HI_GX_INIT_OK", "HI_GX_BIN"}
def protected(nm):
    return nm in PROTECTED or (nm.startswith("GIT_") and nm != "GIT_TERMINAL_PROMPT")
SANCTIONED_WRITES = {
    "install_constitution.sh": [
        ("hi_gx_bin", "HI_GX_BIN", 'HI_GX_BIN="$(command -v git 2>/dev/null)"'),
        ("hi_gx_bin", "HI_GX_BIN", 'HI_GX_BIN=""'),
        ("hi_gx", "GIT_SSH_COMMAND", 'export GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=10"'),
        ("hi_init_state", "HI_GX_COMMIT_OK", "HI_GX_COMMIT_OK=0"),
        ("hi_init_state", "HI_GX_INIT_OK", "HI_GX_INIT_OK=0"),
        ("hi_init_state", "HI_GX_BIN", 'HI_GX_BIN=""'),
        ("main", "HI_GX_INIT_OK", "HI_GX_INIT_OK=1"),
        ("main", "HI_GX_COMMIT_OK", "HI_GX_COMMIT_OK=1"),
    ],
    "update_constitution.sh": [
        ("hi_gx_bin", "HI_GX_BIN", 'HI_GX_BIN="$(command -v git 2>/dev/null)"'),
        ("hi_gx_bin", "HI_GX_BIN", 'HI_GX_BIN=""'),
        ("hi_gx", "GIT_SSH_COMMAND", 'export GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=10"'),
        (None, "HI_GX_COMMIT_OK", "HI_GX_COMMIT_OK=0"),
        (None, "HI_GX_INIT_OK", "HI_GX_INIT_OK=0"),
        (None, "HI_GX_BIN", 'HI_GX_BIN=""'),
        (None, "HI_GX_COMMIT_OK", "HI_GX_COMMIT_OK=1"),
    ],
}
# Raw occurrences of the wrapper switches in code outside the hi_gx block (comments removed): catches any write
# form the structural walk does not model (namerefs, ${!x}, …) by changing the count.
SWITCH_TOKENS = {"install_constitution.sh": {"HI_GX_COMMIT_OK": 2, "HI_GX_INIT_OK": 2, "HI_GX_BIN": 1},
                 "update_constitution.sh": {"HI_GX_COMMIT_OK": 2, "HI_GX_INIT_OK": 1, "HI_GX_BIN": 1}}
# The one dynamic variable name the scripts write: hi_ask stores the validated answer in the caller's variable.
DYN_NAME_EXEMPT = {"install_constitution.sh": [("hi_ask", 'printf -v "$__v" \'%s\' "$__a"')]}
# Every redirection that WRITES a file (> >> >| &> <> >&file): only /dev/null, an fd duplication, or one of
# these exact (function, operator, target) places — backups, staging, the lock, private logs and the report.
SANCTIONED_REDIRS = {
    "install_constitution.sh": [
        ("hi_open_tty", ">", '"$t"'),                          # exec 7>"$t": the terminal (/dev/tty or the test seam)
        ("hi_backup_dir", ">>", '"$ex"'),                       # .git/info/exclude: the backup root line
        ("hi_backup_file", ">>", '"$bk/manifest.txt"'), ("hi_backup_file", ">>", '"$bk/created.txt"'),
        ("hi_lock", ">", '"$tmp"'),                            # the private mktemp file later linked as the lock
        ("hi_write_docs", ">", '"$tmp"'),                      # the staged doc, then mv into place
        ("hi_gitmodules_user_dirty", ">", '"$ti"'), ("hi_gitmodules_user_dirty", ">", '"$ti"'),
        ("hi_gitmodules_user_dirty", ">", '"$th"'), ("hi_gitmodules_user_dirty", ">", '"$th"'),
        ("hi_run_agent", ">", '"$log"'), ("hi_run_agent", ">", '"$log.stderr"'),
        ("hi_run_agent", ">>", '"$log"'), ("hi_run_agent", ">>", '"$log.stderr"'),
        ("hi_write_report", ">", '"$f"'),
        ("hi_marker_set", ">", '"$pend"'),                      # the update-pending marker in the project's own git dir (as up_marker_set)
    ],
    "update_constitution.sh": [
        ("up_lock", ">", '"$tmp"'),                            # the private mktemp file later linked as the lock
        ("up_marker_set", ">", '"$PEND"'),                     # the resume marker in the project's own git dir
    ],
}
# W2 round 11 — VARIABLE SOURCES. The entries above pin the command TEXT, but "$pend" / "$tmp" / "$f" ... only name a
# variable: re-pointing it at .gitmodules or .git/config leaves the sanctioned text unchanged. Every variable that is
# the target of a SANCTIONED_REDIRS / SANCTIONED_FILE_CMDS / EXT_EXACT (rm, chmod, mkdir, rmdir) entry, plus the helper
# that computes the marker path, is therefore pinned: VAR_PIN_SPECS lists (function or None for file-wide, name) and
# VAR_PINS the exact (function, name, whole stripped line) of every line that BINDS it (assignment, += , local/declare/
# export/readonly/read/mapfile/unset, for NAME, printf -v NAME, (( NAME ... ))). Census: CM_NOPUSH_PINS=1 prints the
# current binding lines in this format for a reviewer to paste; any other binding line is a finding. LIMIT (also listed in
# the guide, section "No-push source gate"): a value that arrives as a function ARGUMENT ("$1") is pinned at its binding line, not at its callers.
VAR_PIN_GLOBALS = {"O_ROOT", "HI_SUB", "S_BK", "S_LOCK", "S_LOCK_RECLAIM", "S_LOCK_TMP", "PEND", "UP_LOCK", "UP_RECLAIM", "UP_TMP"}
VAR_PIN_SPECS = {
    "install_constitution.sh": [   ('hi_agent_step', 'S_BK'),
    ('hi_backup_dir', 'S_BK'),
    ('hi_backup_dir', 'ex'),
    ('hi_backup_file', 'O_ROOT'),
    ('hi_backup_file', 'bk'),
    ('hi_backup_file', 'rel'),
    ('hi_do_add', 'HI_SUB'),
    ('hi_do_add', 'O_ROOT'),
    ('hi_do_add', 'bk'),
    ('hi_do_add', 'fdst'),
    ('hi_do_add', 'stage'),
    ('hi_gitmodules_user_dirty', 'O_ROOT'),
    ('hi_gitmodules_user_dirty', 'th'),
    ('hi_gitmodules_user_dirty', 'ti'),
    ('hi_gitmodules_user_dirty', 'tw'),
    ('hi_lock', 'lockp'),
    ('hi_lock', 'tmp'),
    ('hi_manifest_step', 'm'),
    ('hi_marker_clear', 'pend'),
    ('hi_marker_path', 'p'),
    ('hi_marker_set', 'pend'),
    ('hi_move_aside', 'O_ROOT'),
    ('hi_move_aside', 'bk'),
    ('hi_move_aside', 'rel'),
    ('hi_open_tty', 't'),
    ('hi_recover_partial', 'HI_SUB'),
    ('hi_recover_partial', 'bk'),
    ('hi_recover_partial', 'gd'),
    ('hi_restore', 'dir'),
    ('hi_restore', 'norm'),
    ('hi_restore', 'rootabs'),
    ('hi_run_agent', 'log'),
    ('hi_unlock', 'S_LOCK'),
    ('hi_unlock_tmp', 'S_LOCK_RECLAIM'),
    ('hi_unlock_tmp', 'S_LOCK_TMP'),
    ('hi_write_docs', 'O_ROOT'),
    ('hi_write_docs', 'f'),
    ('hi_write_docs', 'tmp'),
    ('hi_write_report', 'f'),
    ('hi_write_report', 'path')],
    "update_constitution.sh": [   ('up_lock', 'lockp'),
    ('up_lock', 'tmp'),
    ('up_marker_clear', 'PEND'),
    ('up_marker_set', 'PEND'),
    ('up_unlock', 'UP_LOCK'),
    ('up_unlock_tmp', 'UP_RECLAIM'),
    ('up_unlock_tmp', 'UP_TMP')],
}
VAR_PINS = {
    "install_constitution.sh": [
        ('hi_backup_dir', 'S_BK', 'S_BK="$O_ROOT/$HI_BACKUP_ROOT/$stamp"'),
        ('hi_backup_dir', 'S_BK', 'mkdir -p "$S_BK/files" && chmod 700 "$S_BK" "$S_BK/files" || { hi_err "cannot create backup dir"; S_BK=""; return 1; }'),
        ('hi_backup_dir', 'ex', '[[ "$ex" == /* ]] || ex="$O_ROOT/$ex"'),
        ('hi_backup_dir', 'ex', 'ex="$(hi_gx -C "$O_ROOT" rev-parse --git-path info/exclude 2>/dev/null)"'),
        ('hi_backup_dir', 'ex', 'local stamp ex'),
        ('hi_backup_file', 'bk', 'hi_backup_dir >/dev/null || return 1; bk="$S_BK"'),
        ('hi_backup_file', 'bk', 'local rel="$1" bk'),
        ('hi_backup_file', 'rel', 'local rel="$1" bk'),
        ('hi_do_add', 'bk', 'hi_backup_dir >/dev/null || return 1; bk="$S_BK"'),
        ('hi_do_add', 'bk', 'local err sha bk stage rc mode=blobless live'),
        ('hi_do_add', 'fdst', 'local fdst="$bk/staging/failed-blobless-clone" fn=0'),
        ('hi_do_add', 'fdst', 'while [ -e "$fdst" ] || [ -L "$fdst" ]; do fn=$((fn+1)); fdst="$bk/staging/failed-blobless-clone-$fn"; done'),
        ('hi_do_add', 'stage', 'local err sha bk stage rc mode=blobless live'),
        ('hi_do_add', 'stage', 'stage="$bk/staging/constitution"'),
        ('hi_gitmodules_user_dirty', 'th', 'local tw ti th a b c'),
        ('hi_gitmodules_user_dirty', 'th', 'tw="$(mktemp)" && ti="$(mktemp)" && th="$(mktemp)" || return 0'),
        ('hi_gitmodules_user_dirty', 'ti', 'local tw ti th a b c'),
        ('hi_gitmodules_user_dirty', 'ti', 'tw="$(mktemp)" && ti="$(mktemp)" && th="$(mktemp)" || return 0'),
        ('hi_gitmodules_user_dirty', 'tw', 'local tw ti th a b c'),
        ('hi_gitmodules_user_dirty', 'tw', 'tw="$(mktemp)" && ti="$(mktemp)" && th="$(mktemp)" || return 0'),
        ('hi_init_state', 'O_ROOT', 'O_ROOT=""; O_UPSTREAM="github"; O_URLS=(); O_SSH=0; O_REF=""; O_AGENT=""; O_MODEL="sonnet"; O_EFFORT="medium"'),
        ('hi_init_state', 'S_BK', 'S_MODE=""; S_URL=""; S_KEY=""; S_REF=""; S_BEFORE=""; S_AFTER=""; S_BK=""; S_STATUS="failure"; S_RC=1'),
        ('hi_init_state', 'S_LOCK', 'S_STARTED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; S_LOCK=""; S_WRITTEN=(); S_NOTES=(); S_UPDATER=""; S_CLONE=""'),
        ('hi_init_state', 'S_LOCK_RECLAIM', 'S_LOCK_TMP=""; S_LOCK_RECLAIM=""; S_LAYOUT=""; S_SUBREL=""; S_TAGS=""; S_AGENT_LINE=""; S_TMP_PATHS=(); S_PRESTATUS=()'),
        ('hi_init_state', 'S_LOCK_TMP', 'S_LOCK_TMP=""; S_LOCK_RECLAIM=""; S_LAYOUT=""; S_SUBREL=""; S_TAGS=""; S_AGENT_LINE=""; S_TMP_PATHS=(); S_PRESTATUS=()'),
        ('hi_lock', 'S_LOCK', 'if ln -- "$tmp" "$lockp" 2>/dev/null; then S_LOCK="$lockp"; hi_unlock_tmp; return 0; fi'),
        ('hi_lock', 'S_LOCK_RECLAIM', 'S_LOCK_RECLAIM="$lockp.reclaim"'),
        ('hi_lock', 'S_LOCK_TMP', 'S_LOCK_TMP="$tmp"'),
        ('hi_lock', 'lockp', 'local gd pid pid2 tmp lockp'),
        ('hi_lock', 'lockp', 'lockp="$gd/helix-constitution-install.lock"'),
        ('hi_lock', 'tmp', 'local gd pid pid2 tmp lockp'),
        ('hi_lock', 'tmp', 'tmp="$(mktemp "$lockp.XXXXXX" 2>/dev/null)" || { hi_err "cannot create a temp file next to $lockp"; return 3; }'),
        ('hi_manifest_step', 'm', 'local m="$O_ROOT/helix-deps.yaml" v="$HI_SUB/scripts/deps_manifest/verify_helix_deps_manifests.sh" out rc'),
        ('hi_marker_clear', 'pend', 'local pend'),
        ('hi_marker_clear', 'pend', 'pend="$(hi_marker_path)" || return 0'),
        ('hi_marker_path', 'p', 'case "$p" in "") return 1 ;; /*) ;; *) p="$O_ROOT/$p" ;; esac'),
        ('hi_marker_path', 'p', 'local p'),
        ('hi_marker_path', 'p', 'p="$(hi_gx -C "$O_ROOT" rev-parse --git-path helix-update-pending 2>/dev/null)" || return 1'),
        ('hi_marker_set', 'pend', 'local pend'),
        ('hi_marker_set', 'pend', 'pend="$(hi_marker_path)" || return 0'),
        ('hi_move_aside', 'bk', 'hi_backup_dir >/dev/null || return 1; bk="$S_BK"'),
        ('hi_move_aside', 'bk', 'local rel="$1" bk'),
        ('hi_move_aside', 'rel', 'local rel="$1" bk'),
        ('hi_open_tty', 't', 'if [ "${HELIX_INSTALLER_TEST:-}" = 1 ]; then t="$HELIX_INSTALLER_TTY"'),
        ('hi_open_tty', 't', 'local t=/dev/tty'),
        ('hi_parse_args', 'O_ROOT', '--project-root) hi_validate_path "$v" || { hi_err "invalid --project-root"; return 2; }; O_ROOT="$v" ;;'),
        ('hi_recover_partial', 'bk', 'local bk; hi_backup_dir >/dev/null || return 1; bk="$S_BK"'),
        ('hi_recover_partial', 'gd', 'gd="$(hi_gx -C "$O_ROOT" rev-parse --absolute-git-dir)"'),
        ('hi_recover_partial', 'gd', 'local gd'),
        ('hi_restore', 'dir', 'dir="$(cd -P -- "$O_RESTORE" 2>/dev/null && pwd)" || { hi_err "backup dir not found"; return 2; }'),
        ('hi_restore', 'dir', 'local dir rootabs bkroot rel norm n=0 skipped=0 uid mode'),
        ('hi_restore', 'norm', 'local dir rootabs bkroot rel norm n=0 skipped=0 uid mode'),
        ('hi_restore', 'norm', 'norm="$(hi_restore_rel "$rel")" || { hi_warn "skipping unsafe manifest entry: $(printf \'%q\' "$rel")"; skipped=$((skipped+1)); continue; }'),
        ('hi_restore', 'rootabs', 'local dir rootabs bkroot rel norm n=0 skipped=0 uid mode'),
        ('hi_restore', 'rootabs', 'rootabs="$(cd -P -- "$O_ROOT" && pwd)" || { hi_err "project root not found"; return 2; }'),
        ('hi_run_agent', 'log', 'local prompt="$1" log="$2" smode="$3" sid="$4" budget="$5" id="$O_AGENT" k rc parsed'),
        ('hi_unlock', 'S_LOCK', 'S_LOCK=""'),
        ('hi_unlock_tmp', 'S_LOCK_RECLAIM', 'S_LOCK_RECLAIM=""'),
        ('hi_unlock_tmp', 'S_LOCK_TMP', 'S_LOCK_TMP=""'),
        ('hi_write_docs', 'f', 'local f tmp mode'),
        ('hi_write_docs', 'f', 'while read -r f; do'),
        ('hi_write_docs', 'tmp', 'local f tmp mode'),
        ('hi_write_docs', 'tmp', 'tmp="$(mktemp "$O_ROOT/.${f}.helix.XXXXXX")" || return 1'),
        ('hi_write_report', 'f', 'f="$(mktemp "$(dirname -- "$path")/.report.XXXXXX" 2>/dev/null)" || { hi_warn "cannot write report $path"; continue; }'),
        ('hi_write_report', 'f', 'local out="" x k v first f path'),
        ('hi_write_report', 'path', 'for path in "${S_BK:+$S_BK/report.json}" "$O_REPORT"; do'),
        ('hi_write_report', 'path', 'local out="" x k v first f path'),
        ('main', 'O_ROOT', 'O_ROOT="$(cd -P -- "$O_ROOT" 2>/dev/null && pwd)" || { hi_err "project root does not exist"; exit 2; }'),
        ('main', 'O_ROOT', '[ -n "$O_ROOT" ] || O_ROOT="$PWD"'),
        ('main', 'O_ROOT', '[ -n "$top" ] && O_ROOT="$(cd -P -- "$top" && pwd)"'),
        (None, 'HI_SUB', 'HI_SUB="submodules/constitution"'),
    ],
    "update_constitution.sh": [
        ('up_holder_pid', 'UP_LOCK', 'up_holder_pid() { local UP_LOCK="$UP_LOCK_FILE"; up_lock_pid; }'),
        ('up_lock', 'UP_LOCK', 'if ln -- "$tmp" "$lockp" 2>/dev/null; then UP_LOCK="$lockp"; up_unlock_tmp; return 0; fi'),
        ('up_lock', 'UP_RECLAIM', 'UP_RECLAIM="$lockp.reclaim"'),
        ('up_lock', 'UP_TMP', 'UP_TMP="$tmp"'),
        ('up_lock', 'lockp', 'local gd pid pid2 tmp lockp dlg="${HELIX_CONSTITUTION_LOCK_DELEGATED-}"'),
        ('up_lock', 'lockp', 'lockp="$gd/helix-constitution-install.lock"; UP_LOCK_FILE="$lockp"'),
        ('up_lock', 'tmp', 'local gd pid pid2 tmp lockp dlg="${HELIX_CONSTITUTION_LOCK_DELEGATED-}"'),
        ('up_lock', 'tmp', 'tmp="$(mktemp "$lockp.XXXXXX" 2>/dev/null)" || { say "cannot create a temp file next to $lockp"; return 3; }'),
        ('up_unlock', 'UP_LOCK', 'UP_LOCK=""'),
        ('up_unlock_tmp', 'UP_RECLAIM', 'UP_RECLAIM=""'),
        ('up_unlock_tmp', 'UP_TMP', 'UP_TMP=""'),
        (None, 'PEND', 'PEND="$(hi_gx -C "$ROOT" rev-parse --git-path helix-update-pending 2>/dev/null)"'),
        (None, 'PEND', 'case "$PEND" in /*|"") ;; *) PEND="$ROOT/$PEND" ;; esac'),
        (None, 'UP_LOCK', 'UP_LOCK=""; UP_ROOT=""; UP_LOCK_FILE=""'),
        (None, 'UP_RECLAIM', 'UP_TMP=""; UP_RECLAIM=""'),
        (None, 'UP_TMP', 'UP_TMP=""; UP_RECLAIM=""'),
    ],
}
BANNED_CMDS = {"truncate", "shred", "dd", "let", "hash", "enable", "bind", "tee", "install", "mkfifo", "mknod",
               "rsync", "scp", "sftp", "curl", "wget", "nc", "ncat", "socat", "ssh"}
# cp / ln / mv can overwrite or replace any file the user owns (cp /dev/null F, ln -sf X F, mv X F): each is
# allowed only at these exact (function, whole command text) places — backups, staging, the lock, docs.
SANCTIONED_FILE_CMDS = {
    "install_constitution.sh": [
        ("hi_backup_file", 'cp -pP "$O_ROOT/$rel" "$bk/files/$rel"'),            # copy INTO the private backup
        ("hi_move_aside", 'mv -- "$O_ROOT/$rel" "$bk/moved-aside/$rel"'),        # move INTO the private backup
        ("hi_write_docs", 'mv -f -- "$tmp" "$O_ROOT/$f"'),                       # the staged, backed-up doc
        ("hi_lock", 'ln -- "$tmp" "$lockp"'), ("hi_lock", 'ln -- "$tmp" "$lockp"'),  # link(2): never replaces
        ("hi_lock", 'ln -- "$tmp" "$lockp.reclaim"'),
        ("hi_gitmodules_user_dirty", 'cp -- "$O_ROOT/.gitmodules" "$tw"'),      # copy INTO a private mktemp file
        ("hi_recover_partial", 'mv -- "$gd/modules/$HI_SUB" "$bk/moved-aside/git-modules/"'),
        ("hi_do_add", 'mv -- "$stage" "$fdst"'),                        # into the private backup, under a name that does not exist yet
        ("hi_do_add", 'mv -- "$stage" "$O_ROOT/$HI_SUB"'),                     # only after the preflight
        ("hi_write_report", 'mv -f -- "$f" "$path"'),                           # the report file the user named
        ("hi_restore", 'cp -p -- "$dir/files/$norm" "$rootabs/$norm"'),         # --restore: backups back in place
    ],
    "update_constitution.sh": [
        ("up_lock", 'ln -- "$tmp" "$lockp"'), ("up_lock", 'ln -- "$tmp" "$lockp"'),
        ("up_lock", 'ln -- "$tmp" "$lockp.reclaim"'),
    ],
}

# ───────────────────── external-command allow-list ─────────────────────
# Shell builtins that cannot write a file or run code by themselves (redirections are policed separately).
SAFE_BUILTIN = {":", "true", "false", "echo", "printf", "test", "[", "[[", "cd", "exit", "return", "shift", "set",
                "umask", "wait", "break", "continue", "getopts", "type", "pwd", "jobs", "case", "for"}  # case/for: the lexer's markers
# Read-only utilities: any arguments, except the output-file options checked in read_ok().
READ_OK = {"cat", "head", "tail", "tr", "grep", "sort", "uniq", "wc", "cut", "date", "id", "stat", "getconf", "uname",
           "ls", "dirname", "basename", "readlink", "realpath", "sha256sum", "cksum", "od", "sleep", "tty", "cmp",
           "diff", "comm", "df", "du", "paste", "uuidgen", "jq"}
# Commands that change files or processes: allowed only as an exact (function, whole command text) pair.
EXACT_CMDS = {"rm", "mkdir", "rmdir", "mktemp", "chmod", "kill", "claude-list-accounts", "claude-providers"}
COLLECT = []   # CM_NOPUSH_COLLECT=1: the candidate sanction entries a reviewer reads before pasting them below
# python modules a literal program may import
PY_MODS = {"sys", "unicodedata", "re", "json", "uuid", "hashlib"}
PY_BAD_NAMES = {"exec", "eval", "compile", "__import__", "getattr", "setattr", "delattr", "globals", "locals", "vars",
                "input", "breakpoint", "memoryview"}
PY_BAD_ATTRS = {"system", "popen", "spawn", "unlink", "remove", "rmdir", "rmtree", "rename", "write_text",
                "write_bytes", "writelines", "truncate", "symlink", "link", "chmod", "chown", "kill", "killpg",
                "load_module", "import_module", "run", "call", "check_call", "check_output", "Popen"}
MUTATING_GIT = {"add", "rm", "checkout", "commit", "init", "clone", "fetch", "submodule"}
# Exact (function, command text) pairs for the file-changing commands and for mutating hi_gx/hi_git calls, and the
# literal sed/awk program words. Filled from the files' real, reviewed calls; editing a call makes it a finding
# until this list is updated by a reviewer.
EXT_EXACT = {
    'install_constitution.sh': [
        ('hi_agent_step', 'mkdir -p "$S_BK/agent"'),
        ('hi_backup_dir', 'chmod 700 "$S_BK" "$S_BK/files"'),
        ('hi_backup_dir', 'mkdir -p "$(dirname "$ex")"'),
        ('hi_backup_dir', 'mkdir -p "$S_BK/files"'),
        ('hi_backup_file', 'mkdir -p "$bk/files/$(dirname "$rel")"'),
        ('hi_detect_agents', 'claude-list-accounts'),
        ('hi_detect_agents', 'claude-providers list'),
        ('hi_do_add', 'mkdir -p "$O_ROOT/submodules"'),
        ('hi_do_add', 'mkdir -p "$bk/staging"'),
        ('hi_do_add', 'rmdir -- "$bk/staging"'),
        ('hi_gitmodules_user_dirty', 'mktemp'),
        ('hi_gitmodules_user_dirty', 'rm -f -- "$tw" "$ti" "$th"'),
        ('hi_holder_alive', 'kill -0 "$p"'),
        ('hi_lock', 'mktemp "$lockp.XXXXXX"'),
        ('hi_lock', 'rm -f -- "$lockp"'),
        ('hi_manifest_step', 'chmod "$(printf \'%o\' $(( 0666 & ~0${HI_UMASK0:-022} )))" "$m"'),
        ('hi_move_aside', 'mkdir -p "$bk/moved-aside/$(dirname "$rel")"'),
        ('hi_recover_partial', 'mkdir -p "$bk/moved-aside/git-modules"'),
        ('hi_restore', 'mkdir -p -- "$rootabs/$(dirname -- "$norm")"'),
        ('hi_run_agent', 'chmod 600 "$log" "$log.stderr"'),
        ('hi_stop_agent', 'kill -0 -- "-$pg"'),
        ('hi_stop_agent', 'kill -s KILL -- "-$pg"'),
        ('hi_stop_agent', 'kill -s TERM -- "$p"'),
        ('hi_unlock', 'rm -f -- "$S_LOCK"'),
        ('hi_marker_clear', 'rm -f -- "$pend"'),   # the update-pending marker only (as up_marker_clear in the updater)
        ('hi_unlock_tmp', 'rm -f -- "$S_LOCK_RECLAIM"'),
        ('hi_unlock_tmp', 'rm -f -- "$S_LOCK_TMP"'),
        ('hi_write_docs', 'chmod "$mode" "$tmp"'),
        ('hi_write_docs', 'mktemp "$O_ROOT/.${f}.helix.XXXXXX"'),
        ('hi_write_docs', 'rm -f -- "$tmp"'),
        ('hi_write_report', 'mktemp "$(dirname -- "$path")/.report.XXXXXX"'),
        ('hi_write_report', 'rm -f -- "$f"'),
    ],
    'update_constitution.sh': [
        ('hi_holder_alive', 'kill -0 "$p"'),
        ('up_lock', 'mktemp "$lockp.XXXXXX"'),
        ('up_lock', 'rm -f -- "$lockp"'),
        ('up_unlock', 'rm -f -- "$UP_LOCK"'),
        ('up_unlock_tmp', 'rm -f -- "$UP_RECLAIM"'),
        ('up_unlock_tmp', 'rm -f -- "$UP_TMP"'),
        ('up_marker_clear', 'rm -f -- "$PEND"'),
    ],
}
GX_EXACT = {
    'install_constitution.sh': [
        ('hi_builtin_update', 'hi_git add -- "$1"'),
        ('hi_builtin_update', 'hi_gx -C "$sub" checkout --quiet --detach "$tsha"'),
        ('hi_builtin_update', 'hi_gx -C "$sub" fetch --quiet --tags "$r"'),
        ('hi_complete_interrupted_add', 'hi_git add -- .gitmodules "$HI_SUB"'),
        ('hi_manifest_step', 'hi_git add -- helix-deps.yaml'),
        ('hi_complete_interrupted_add', 'hi_git_url "$S_URL" submodule update --init --quiet -- "$HI_SUB"'),
        ('hi_complete_interrupted_add', 'hi_gx -C "$O_ROOT/$HI_SUB" config --unset helix-installer.clone'),
        ('hi_complete_interrupted_add', 'hi_gx submodule absorbgitdirs -- "$HI_SUB"'),
        ('hi_do_add', 'hi_git add -- .gitmodules "$HI_SUB"'),
        ('hi_do_add', 'hi_git_url "$S_URL" -C "$stage" checkout --quiet --detach "$sha"'),
        ('hi_do_add', 'hi_git_url "$S_URL" clone --quiet --filter=blob:none --no-checkout -- "$(hi_clone_url "$S_URL")" "$stage"'),
        ('hi_do_add', 'hi_git_url "$S_URL" clone --quiet --no-checkout -- "$(hi_clone_url "$S_URL")" "$stage"'),
        ('hi_do_add', 'hi_git_url "$S_URL" submodule add --quiet -- "$S_URL" "$HI_SUB"'),
        ('hi_do_add', 'hi_git_url "$S_URL" submodule update --init --quiet -- "$HI_SUB"'),
        ('hi_do_add', 'hi_gx -C "$O_ROOT/$HI_SUB" config --unset helix-installer.clone'),
        ('hi_do_add', 'hi_gx -C "$stage" config helix-installer.clone true'),
        ('hi_do_add', 'hi_gx -C "$stage" remote set-url origin "$S_URL"'),
        ('hi_do_add', 'hi_gx submodule absorbgitdirs -- "$HI_SUB"'),
        ('hi_do_update', 'hi_git_url "$S_URL" submodule update --init --quiet -- "$sub"'),
        ('hi_gitmodules_user_dirty', 'hi_gx config -f "$c" --remove-section "submodule.$HI_SUB"'),
        ('hi_recover_partial', 'hi_git rm -q --cached -- "$HI_SUB"'),
        ('hi_recover_partial', 'hi_git rm -q --cached --ignore-unmatch -- .gitmodules'),
        ('hi_recover_partial', 'hi_gx -C "$O_ROOT" config --remove-section "submodule.$HI_SUB"'),
        ('hi_recover_partial', 'hi_gx -C "$O_ROOT" config -f "$O_ROOT/.gitmodules" --remove-section "submodule.$HI_SUB"'),
        ('hi_write_docs', 'hi_git add -- "$f"'),
        ('main', 'hi_git commit -q -m "chore(constitution): add/update Helix Constitution at $HI_SUB ($S_REF ${S_AFTER:0:12})" -- "${cpaths[@]}"'),
        ('main', 'hi_gx -C "$O_ROOT" init -q'),
    ],
    'update_constitution.sh': [
        (None, 'hi_gx -C "$ROOT" add -- "$REL"'),
        (None, 'hi_gx -C "$ROOT" commit -q -m "chore(constitution): update $REL to $TARGET (${TSHA:0:12})" -- "$REL"'),
        (None, 'hi_gx -C "$SUB" checkout --quiet --detach "$TSHA"'),
        (None, 'hi_gx -C "$SUB" fetch --quiet --tags "$r"'),
    ],
}
PROGS = {
    'install_constitution.sh': {
        "'$0 == b { on = 1 } on { print } $0 == e { on = 0 }'",
        '\'$1 == "V" && $2 == ENVIRON["HI_I"] { x = $0; sub(/^V [^ ]+ [^ ]+ /, "", x); if (x == ENVIRON["HI_U"]) { print $3; exit } }\'',
        '\'$1 == "D" && $2 == ENVIRON["HI_I"] { sub(/^D [^ ]+ /, ""); print; exit }\'',
        "'$1 == i { print $2 }'",
        "'$1 == n { print $2; exit }'",
        "'$1 ~ /^[0-9a-f]+$/ && (length($1) == 40 || length($1) == 64) { print $1 }'",
        "'BEGIN { exit !(l + 0 >= 0.01) }'",
        "'BEGIN { exit !(v + 0 > 0 && v + 0 <= m) }'",
        "'NF && !s[$0]++'",
        "'NR == 1 && /^---[[:space:]]*$/ { fm = 1; next } fm == 1 { if (/^---[[:space:]]*$/) fm = 2; next } { print }'",
        "'NR == 2 { print $4 }'",
        "'s#([Hh][Tt][Tt][Pp][Ss]?://)[^/?#[:space:]]*@#\\1#g; s#([A-Za-z][A-Za-z0-9+.-]*://)[^/?#[:space:]@:]*:[^/?#[:space:]]*@#\\1#g; s/([?&][^=&#[:space:]]*=)[^&#[:space:]]*/\\1REDACTED/g'",
        "'s/.* cost=\\([^ ]*\\).*/\\1/p'",
        "'s/.*evidence=\\([^ ]*\\).*/\\1/p'",
        "'s/.*session=\\([^ ]*\\).*/\\1/p'",
        "'s/\\.?0+$//; s/^$/0/'",
        "'s|(://)[^/?#[:space:]]*@|\\1|g; s/([?&][^=&#[:space:]]*=)[^&#[:space:]]*/\\1REDACTED/g'",
        "'{ print $1 }'",
        "'{ print $3; print $4 }'",
        '\'$1 != k { print $1 "|" $c }\'',
        '\'$1 == "160000" { print $2 }\'',
        '\'$1 == "btime" { print $2; exit }\'',
        '\'$1 == k { print $1 "|" $c }\'',
        '\'$1 ~ /^claude[0-9]+$/ { print $1 "|" $3 }\'',
        '\'$2 !~ /\\^\\{\\}$/ { n = $2; sub(/^refs\\/tags\\//, "", n); print n, $1 }\'',
        '\'BEGIN { printf "%.4f", a + c }\'',
        '\'BEGIN { r = b - s; if (r < 0) r = 0; printf "%.4f", r }\'',
        '\'NR == 1 && !/^---[[:space:]]*$/ { exit } NR > 1 && /^---[[:space:]]*$/ { exit }\n           NR > 1 && /^requires_previous_success:/ { sub(/^requires_previous_success:[[:space:]]*/, ""); print; exit }\'',
        '\'\n      /^##/ { exit } NR == 1 { next } NF >= 3 && $1 ~ /^[A-Za-z0-9][A-Za-z0-9._-]*$/ { print $1 "|" $3 }\'',
        '\'\n    BEGIN { st = 0; got = 0 }\n    st == 0 && /^## PROMPT[[:space:]]*$/ { st = 1; next }\n    st == 1 && /^## / { exit }\n    st == 1 && match($0, /^(```+|~~~+)/) { fch = substr($0, 1, 1); flen = RLENGTH; st = 2; next }\n    st == 2 {\n      line = $0; sub(/[[:space:]]+$/, "", line)\n      if (length(line) >= flen && substr(line, 1, 1) == fch) {\n        rest = line; if (fch == "`") gsub(/`/, "", rest); else gsub(/~/, "", rest)\n        if (rest == "") { got = 1; exit }\n      }\n      print; n++\n    }\n    END { exit (got && n > 0) ? 0 : 1 }\n  \'',
        '\'{ for (i = 1; i <= NF; i++) if ($i ~ /^cost=[0-9.]+([eE][-+]?[0-9]+)?$/) {   # jq prints 1e-05: normalise\n                 v = sprintf("%.6f", substr($i, 6) + 0); sub(/0+$/, "", v); sub(/\\.$/, "", v); $i = "cost=" v }\n             print }\'',
        '\'{ printf "%-36s %-15s %-12s %-6s %s\\n", $1, $2, $3, $4, $6 }\'',
        '\'{ r = $2; sub(/^refs\\/tags\\//, "", r); sub(/\\^\\{\\}$/, "", r); print r }\'',
    },
    'update_constitution.sh': {
        "'$1 == n { print $2; exit }'",
        "'$1 ~ /^[0-9a-f]+$/ && (length($1) == 40 || length($1) == 64) { print $1 }'",
        "'2,/^# Classification/p'",
        "'NF && !s[$0]++'",
        "'s/^# \\{0,1\\}//'",
        "'s/^+## /  changelog: /p'",
        "'s/^/  /'",
        "'s|(://)[^/?#[:space:]]*@|\\1|g; s/([?&][^=&#[:space:]]*=)[^&#[:space:]]*/\\1REDACTED/g'",
        "'{ print $1 }'",
        '\'$1 == "btime" { print $2; exit }\'',
        '\'$2 !~ /\\^\\{\\}$/ { n = $2; sub(/^refs\\/tags\\//, "", n); print n, $1 }\'',
    },
}

# ───────────────────────── lexer ─────────────────────────
OPS = (";;&", ";;", ";&", "&&", "||", "|&", "<<<", "<<-", "<<", ">>", ">&", "<&", "&>", "<>", ">|",
       ";", "&", "|", "<", ">", "(", ")")
REDIR = {"<<<", "<<-", "<<", ">>", ">&", "<&", "&>", "<>", ">|", "<", ">"}
SEP = {";", ";;", ";&", ";;&", "&", "&&", "||", "|", "|&", "(", ")", "\n"}


class Word:
    __slots__ = ("raw", "line", "subs")
    def __init__(self, raw, line, subs):
        self.raw, self.line, self.subs = raw, line, subs


def skip_squote(t, i):  # i at opening '
    j = t.find("'", i + 1)
    return len(t) if j < 0 else j + 1


def skip_ansi(t, i):  # i at $ of $'
    j = i + 2
    while j < len(t):
        if t[j] == "\\": j += 2; continue
        if t[j] == "'": return j + 1
        j += 1
    return len(t)


def skip_bq(t, i, subs, line):  # i at opening `
    j = i + 1
    while j < len(t):
        if t[j] == "\\": j += 2; continue
        if t[j] == "`":
            subs.append((t[i + 1:j], line + t.count("\n", 0, i) * 0)); return j + 1
        j += 1
    return len(t)


def skip_dquote(t, i, subs, line):  # i at opening "
    j = i + 1
    while j < len(t):
        c = t[j]
        if c == "\\": j += 2; continue
        if c == '"': return j + 1
        if c == "`": j = skip_bq(t, j, subs, line); continue
        if t.startswith("$(", j): j = skip_paren(t, j + 1, subs, line, record=not t.startswith("$((", j)); continue
        if t.startswith("${", j): j = skip_brace(t, j + 1, subs, line); continue
        j += 1
    return len(t)


def skip_paren(t, i, subs, line, record=True):  # i at "(" ; balanced to matching ")"
    depth, j = 0, i
    while j < len(t):
        c = t[j]
        if c == "\\": j += 2; continue
        if c == "'": j = skip_squote(t, j); continue
        if c == '"': j = skip_dquote(t, j, subs, line); continue
        if c == "`": j = skip_bq(t, j, subs, line); continue
        if c == "#" and (j == 0 or t[j - 1] in " \t\n;"):
            k = t.find("\n", j); j = len(t) if k < 0 else k; continue
        if c == "(": depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                if record: subs.append((t[i + 1:j], line))
                return j + 1
        j += 1
    return len(t)


def skip_brace(t, i, subs, line):  # i at "{" of ${
    depth, j = 0, i
    while j < len(t):
        c = t[j]
        if c == "\\": j += 2; continue
        if c == "'": j = skip_squote(t, j); continue
        if c == '"': j = skip_dquote(t, j, subs, line); continue
        if t.startswith("$(", j): j = skip_paren(t, j + 1, subs, line, record=not t.startswith("$((", j)); continue
        if c == "`": j = skip_bq(t, j, subs, line); continue
        if c == "{": depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0: return j + 1
        j += 1
    return len(t)


ASSIGN_ARR = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?\+?=$")


def tokenize(t, line0=1):
    toks, heredocs, i, n, line, pend = [], [], 0, len(t), line0, []
    while i < n:
        c = t[i]
        if c == "\n":
            toks.append(("OP", "\n", line)); line += 1; i += 1
            for d, strip, quoted, hline in pend:
                body = []
                while i < n:
                    k = t.find("\n", i); k = n if k < 0 else k
                    ln = t[i:k]; i = k + 1; line += 1
                    if (ln.lstrip("\t") if strip else ln) == d: break
                    body.append(ln)
                heredocs.append((d, quoted, "\n".join(body), hline))
            pend = []
            continue
        if c in " \t": i += 1; continue
        if c == "\\" and i + 1 < n and t[i + 1] == "\n": i += 2; line += 1; continue
        if c == "#": k = t.find("\n", i); i = n if k < 0 else k; continue
        if t.startswith("((", i):
            j = skip_paren(t, i, [], line, record=False); toks.append(("WORD", Word(t[i:j], line, []), line))
            line += t.count("\n", i, j); i = j; continue
        if c in "<>" and i + 1 < n and t[i + 1] == "(":  # process substitution
            subs = []; j = skip_paren(t, i + 1, subs, line)
            toks.append(("WORD", Word(t[i:j], line, subs), line)); line += t.count("\n", i, j); i = j; continue
        op = next((o for o in OPS if t.startswith(o, i)), None)
        if op:
            toks.append(("OP", op, line)); i += len(op)
            if op in ("<<", "<<-"):
                while i < n and t[i] in " \t": i += 1
                j = i
                while j < n and t[j] not in " \t\n;&|<>()": j += 1
                d = t[i:j]; quoted = any(q in d for q in "'\"\\")
                pend.append((d.replace("'", "").replace('"', "").replace("\\", ""), op == "<<-", quoted, line))
                toks.append(("WORD", Word(d, line, []), line)); i = j
            continue
        # a word
        j, subs, start = i, [], i
        while j < n:
            c = t[j]
            if c in " \t\n;&|<>()":
                if c == "(" and ASSIGN_ARR.match(t[start:j]):
                    j = skip_paren(t, j, [], line, record=False); continue
                break
            if c == "\\": j += 2; continue
            if c == "'": j = skip_squote(t, j); continue
            if t.startswith("$'", j): j = skip_ansi(t, j); continue
            if c == '"': j = skip_dquote(t, j, subs, line); continue
            if c == "`": j = skip_bq(t, j, subs, line); continue
            if t.startswith("$((", j): j = skip_paren(t, j + 1, subs, line, record=False); continue
            if t.startswith("$(", j): j = skip_paren(t, j + 1, subs, line); continue
            if t.startswith("${", j): j = skip_brace(t, j + 1, subs, line); continue
            j += 1
        toks.append(("WORD", Word(t[start:j], line, subs), line)); line += t.count("\n", start, j); i = j
    return toks, heredocs


def commands(toks):
    """yield (words, line, pipe_in, redirects) for every simple command."""
    out, cur, redirs, pipe_in, i, case_stack, mode = [], [], [], False, 0, [], "cmd"
    def flush(next_pipe=False):
        nonlocal cur, redirs, pipe_in
        if cur or redirs: out.append((cur, cur[0].line if cur else redirs[0][1].line, pipe_in, redirs))
        cur, redirs, pipe_in = [], [], next_pipe
    while i < len(toks):
        kind, v, line = toks[i]
        if mode == "pattern":  # case patterns: skip to ")" ; "esac" ends the case
            if kind == "WORD" and v.raw == "esac": case_stack.pop(); mode = "cmd"
            elif kind == "OP" and v == ")": mode = "cmd"
            i += 1; continue
        if kind == "OP":
            if v in REDIR:
                if i + 1 < len(toks) and toks[i + 1][0] == "WORD": redirs.append((v, toks[i + 1][1])); i += 2; continue
                i += 1; continue
            if v in (";;", ";&", ";;&") and case_stack:
                flush(); mode = "pattern"; i += 1; continue
            if v == "(" and cur and i + 1 < len(toks) and toks[i + 1][1] == ")" and len(cur) == 1:
                cur = []; i += 2; continue  # function definition name()
            flush(next_pipe=v in ("|", "|&")); i += 1; continue
        w = v
        if w.raw.isdigit() and i + 1 < len(toks) and toks[i + 1][0] == "OP" and toks[i + 1][1] in REDIR:
            i += 1; continue  # the fd number of a redirection (2>&1), not an argument
        if not cur and w.raw in RESERVED: i += 1; continue
        if not cur and w.raw == "case":
            case_stack.append(1); j = i + 1
            while j < len(toks) and not (toks[j][0] == "WORD" and toks[j][1].raw == "in"): j += 1
            for k in range(i + 1, j):  # the case word is data; only a $( ) inside it runs code
                if toks[k][0] == "WORD" and toks[k][1].subs: out.append(([Word("case", line, toks[k][1].subs)], line, False, []))
            mode = "pattern"; i = j + 1; continue
        if not cur and w.raw in ("for", "select"):
            j = i + 1
            while j < len(toks) and not (toks[j][0] == "OP" and toks[j][1] in (";", "\n")): j += 1
            if j > i + 1 and toks[i + 1][0] == "WORD":
                out.append(([Word("for", line, []), toks[i + 1][1]], line, False, []))
            for k in range(i + 1, j):
                if toks[k][0] == "WORD" and toks[k][1].subs: out.append(([Word("for", line, toks[k][1].subs)], line, False, []))
            i = j; continue
        if not cur and w.raw == "[[":
            j = i + 1; words = [w]
            while j < len(toks) and not (toks[j][0] == "WORD" and toks[j][1].raw == "]]"):
                if toks[j][0] == "WORD": words.append(toks[j][1])
                j += 1
            out.append((words, line, False, [])); i = j + 1; continue
        cur.append(w); i += 1
    flush()
    return out


def unquote(raw):
    o, i = [], 0
    while i < len(raw):
        c = raw[i]
        if c == "\\" and i + 1 < len(raw): o.append(raw[i + 1]); i += 2; continue
        if c == "'":
            j = raw.find("'", i + 1); j = len(raw) if j < 0 else j; o.append(raw[i + 1:j]); i = j + 1; continue
        if c == '"': i += 1; continue
        o.append(c); i += 1
    return "".join(o)


def dynamic(raw):
    i = 0
    while i < len(raw):
        c = raw[i]
        if c == "\\": i += 2; continue
        if c == "'": j = raw.find("'", i + 1); i = len(raw) if j < 0 else j + 1; continue
        if c in "$`": return True
        i += 1
    return False


ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?\+?=")


def func_map(text):
    m, cur, lines = {}, None, text.split("\n")
    fdef = re.compile(r"^\s*(?:function\s+)?([A-Za-z_][\w-]*)\s*\(\)\s*\{(.*)$")
    defs = []
    for n, l in enumerate(lines, 1):
        g = fdef.match(l)
        if g and cur is not None:
            defs.append((g.group(1), n))   # a definition nested in another body still counts (duplicate check)
        if g and cur is None:
            defs.append((g.group(1), n))
            rest = re.sub(r"\s+#\s.*$", "", g.group(2)).strip()
            if rest.endswith("}"):
                m[n] = g.group(1)  # one-line function
                continue
            cur = g.group(1); m[n] = cur; continue
        if cur is not None:
            m[n] = cur
            if l == "}": cur = None
        elif l.startswith("main "):
            m[n] = None
    return m, defs


def read_ok(u, args):
    """argument shape of a read-only utility: no output-file option, no clock setting"""
    if u == "sort" and any(a in ("-o", "--output") or a.startswith("--output=") or re.match(r"^-[A-Za-z]*o", a) for a in args if a != "--"):
        return "sort with an output file"
    if u == "uniq" and len([a for a in args if not a.startswith("-")]) > 1:
        return "uniq with an output file"
    if u == "date" and any(a in ("-s", "--set") or a.startswith("--set=") or a.startswith("-s") for a in args):
        return "date setting the clock"
    if u in ("diff", "cmp", "comm", "tail", "head") and any(a.startswith("--output") for a in args):
        return "output option"
    return None


def prog_of(u, words):
    """(program word raw text, problem) of a sed/awk call; options other than the plain read-only ones are problems"""
    i = 0
    plain = {"sed": {"-n", "-E", "-r", "-s", "-z", "-u", "--quiet", "--silent", "--regexp-extended", "--null-data",
                     "--separate", "--unbuffered"}, "awk": set()}[u]
    while i < len(words):
        a = unquote(words[i].raw)
        if a == "--":
            i += 1
            break
        if u == "sed" and a == "-e":
            if i + 1 >= len(words): return None, "sed -e without a program"
            return words[i + 1].raw, None
        if u == "sed" and (a == "--file" or a.startswith("--file") or a.startswith("--in-place") or a.startswith("--expression")
                           or re.match(r"^-[A-Za-z]*[ifl]", a)):
            return None, "sed with -f/-i/--expression/-l"
        if u == "awk" and (a.startswith("-f") or a.startswith("--file") or a.startswith("--source") or a.startswith("-e")
                           or a.startswith("-i") or a.startswith("--include")):
            return None, "awk with -f/-e/-i"
        if u == "awk" and a == "-v":
            i += 2
            continue
        if u == "awk" and (a.startswith("-F") or a.startswith("-v")):
            i += 2 if a == "-F" else 1
            continue
        if a.startswith("-") and len(a) > 1:
            if a in plain:
                i += 1
                continue
            return None, "unexpected %s option %s" % (u, a)
        break
    if i >= len(words): return None, "%s without a program" % u
    return words[i].raw, None


def py_problems(code):
    import ast
    try: tree = ast.parse(code)
    except SyntaxError: return ["not parseable python"]
    probs = []
    for n in ast.walk(tree):
        if isinstance(n, ast.Import):
            for a in n.names:
                if a.name.split(".")[0] not in PY_MODS: probs.append("import %s" % a.name)
        elif isinstance(n, ast.ImportFrom):
            if (n.module or "").split(".")[0] not in PY_MODS or n.level: probs.append("from %s import" % n.module)
        elif isinstance(n, ast.Name) and n.id in PY_BAD_NAMES: probs.append("name %s" % n.id)
        elif isinstance(n, ast.Attribute):
            if n.attr in PY_BAD_ATTRS or (n.attr.startswith("__") and n.attr.endswith("__")): probs.append("attribute %s" % n.attr)
            elif n.attr == "write" and ast.unparse(n.value) not in ("sys.stdout", "sys.stdout.buffer", "sys.stderr", "sys.stderr.buffer"):
                probs.append("write() on %s" % ast.unparse(n.value))
        elif isinstance(n, ast.Call) and isinstance(n.func, ast.Name) and n.func.id == "open":
            if len(n.args) != 1 or any(k.arg not in ("encoding", "errors") for k in n.keywords): probs.append("open() other than a plain read")
        elif isinstance(n, (ast.Global, ast.Nonlocal)): probs.append("global/nonlocal")
    return probs


def analyse(path, text, findings, exempt_used):
    base = os.path.basename(path)
    fmap, defs = func_map(text)
    exempt = EXEMPT.get(base, [])
    names = [d[0] for d in defs]
    fn_names = set(names) | (NEEDLE_FUNCS if base == "needle.sh" else set())
    for nm, ln in defs:
        if nm in READ_OK or nm in EXACT_CMDS or nm in SAFE_BUILTIN or nm in ("sed", "awk", "python3", "python", "find", "xargs"):
            findings.append((path, ln, "(a) function named %s hides a command" % nm))
    for nm in ("hi_gx", "hi_gx_check", "hi_gx_refuse"):
        if names.count(nm) != (1 if "# >>> hi_gx" in text else 0):
            findings.append((path, 0, "(a) %s must be defined exactly once (found %d)" % (nm, names.count(nm))))
    for nm, ln in defs:
        if nm in ("git", "command", "builtin", "exec", "command_not_found_handle"):
            findings.append((path, ln, "(a) function named %s overrides a command" % nm))
    writes, rwrites = [], []
    def arith(raw, line):
        for m in re.finditer(r"(\$\{?[^}\s=()]+\}?|[A-Za-z_][A-Za-z0-9_]*)\s*(?:\[[^]]*\])?\s*(?:[-+*/%&|^]|<<|>>)?=(?!=)", raw):
            if m.start() > 0 and raw[m.start() - 1] in "=!<>": continue
            nm = m.group(1)
            if nm.startswith("$"): findings.append((path, line, "(a) arithmetic assignment to a dynamic variable name"))
            elif protected(nm): writes.append((fmap.get(line), nm, raw))
        for m in re.finditer(r"(?:\+\+|--)\s*([A-Za-z_][A-Za-z0-9_]*)|([A-Za-z_][A-Za-z0-9_]*)\s*(?:\+\+|--)", raw):
            nm = m.group(1) or m.group(2)
            if protected(nm): writes.append((fmap.get(line), nm, raw))
    def walk(chunk, line0, depth=0):
        toks, heredocs = tokenize(chunk, line0)
        hd_quoted = {h[3]: h[1] for h in heredocs}
        hd_body = {h[3]: h[2] for h in heredocs}
        for words, line, pipe_in, redirs in commands(toks):
            for w in words:
                for sub, sl in w.subs:
                    walk(sub, sl, depth + 1)
                if re.match(r"^[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?\+?=\(", w.raw) and re.search(r"(^|[\s(])[\"']?git[\"']?(\s|\)|$)", w.raw):
                    findings.append((path, line, "(a) git word inside an array literal"))
            fn = fmap.get(line)
            cmdtext = " ".join(x.raw for x in words)
            def wrote(nm):
                if protected(nm): writes.append((fn, nm, cmdtext))
            for op, tw in redirs:
                if op not in (">", ">>", ">|", "&>", "<>", ">&"): continue
                tu = unquote(tw.raw)
                if op == ">&" and re.fullmatch(r"[0-9]+-?|-", tu): continue
                if tu == "/dev/null" and not dynamic(tw.raw): continue
                rwrites.append((fn, op, tw.raw, line))
            for w in words:  # arithmetic (( … )) / $(( … )) writes
                if "((" in w.raw: arith(w.raw, line)
            if words and words[0].raw == "for" and len(words) == 2:
                lv = words[1].raw
                if lv.startswith("(("): continue
                if dynamic(lv): findings.append((path, line, "(a) for loop with a dynamic variable name"))
                else: wrote(unquote(lv))
                continue
            k = 0
            while k < len(words) and ASSIGN.match(words[k].raw):
                wrote(re.match(r"[A-Za-z_][A-Za-z0-9_]*", words[k].raw).group(0))
                k += 1
            if k >= len(words): continue
            text_from = lambda a: " ".join(x.raw for x in words[a:])
            while k < len(words):
                w = words[k]
                if dynamic(w.raw):
                    t = text_from(k)
                    hit = [e for e in exempt if e[0] == fn and e[1] == t]
                    if hit: exempt_used.add((base, hit[0][0], hit[0][1])); break
                    findings.append((path, line, "(a) dynamic command word: %s" % t[:80])); break
                u = unquote(w.raw)
                if u in WRAPPERS:
                    if u == "command" and k + 1 < len(words) and unquote(words[k + 1].raw) in ("-v", "-V"): break
                    k += 1; took_duration = False
                    while k < len(words):
                        a = unquote(words[k].raw)
                        if a.startswith("-") and len(a) > 1:
                            k += 2 if (a in WRAP_ARG.get(u, set())) else 1; continue
                        if u == "env" and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", a): wrote(a.split("=", 1)[0]); k += 1; continue
                        if u == "timeout" and not took_duration: took_duration = True; k += 1; continue
                        if u in ("nice",) and re.match(r"^-?\d+$", a): k += 1; continue
                        break
                    continue
                args = [unquote(x.raw) for x in words[k + 1:]]
                t = text_from(k)
                if u == "git":
                    hit = [e for e in exempt if e[0] == fn and e[1] == t and fn == "hi_gx"]
                    if hit: exempt_used.add((base, "hi_gx", t + "#%d" % line))
                    else: findings.append((path, line, "(a) git run outside the hi_gx wrapper: %s" % t[:80]))
                elif u in ("eval", "source", "."):
                    findings.append((path, line, "(a) %s (dynamic code)" % u))
                elif u in SHELLS or (u.split("/")[-1] in SHELLS):
                    hit = [e for e in exempt if e[0] == fn and e[1] == t]
                    if hit and not pipe_in and not any(r[0] in ("<<<", "<<", "<<-") for r in redirs):
                        exempt_used.add((base, hit[0][0], hit[0][1]))
                    else:
                        findings.append((path, line, "(a) shell run (only the listed script runs are allowed): %s" % t[:80]))
                elif u in INTERP:
                    findings.append((path, line, "(a) %s interpreter run" % u))
                elif re.match(r"^python[0-9.]*$", u):
                    j = 0
                    while j < len(args) and args[j].startswith("-") and args[j] not in ("-", "-c", "-m"):
                        j += 2 if args[j] in ("-W", "-X", "--check-hash-based-pycs") else 1
                    if j >= len(args) or args[j] not in ("-", "-c"):
                        findings.append((path, line, "(a) python runs a script file, a module or the terminal (only -c LITERAL or - with a quoted heredoc)"))
                    if "-c" in args:
                        code = words[k + 1 + args.index("-c") + 1].raw if args.index("-c") + 1 < len(args) else ""
                        if not (code.startswith("'") and code.endswith("'")) or re.search(r"subprocess|os\.system|os\.popen|os\.exec|__import__", code):
                            findings.append((path, line, "(a) python -c with a non-literal or process-spawning program"))
                    if any(r[0] in ("<<", "<<-") and not any(q in r[1].raw for q in "'\"\\") for r in redirs):
                        findings.append((path, line, "(a) python fed by an unquoted (expanding) heredoc"))
                    prog_src = None
                    if "-c" in args and args.index("-c") + 1 < len(args):
                        cw = words[k + 1 + args.index("-c") + 1].raw
                        if cw.startswith("'") and cw.endswith("'") and "'" not in cw[1:-1]: prog_src = cw[1:-1]
                    else:
                        for r in redirs:
                            if r[0] in ("<<", "<<-") and r[1].line in hd_body and any(q in r[1].raw for q in "'\"\\"):
                                prog_src = hd_body[r[1].line]
                    if prog_src is None:
                        findings.append((path, line, "(a) python program is not a literal (-c 'LITERAL' or - with a quoted heredoc)"))
                    else:
                        for pr in py_problems(prog_src): findings.append((path, line, "(a) python program not allowed: %s" % pr))
                    if pipe_in: findings.append((path, line, "(a) program piped into python"))
                elif u == "find" and any(a in ("-exec", "-execdir", "-ok", "-okdir", "-delete") for a in args):
                    findings.append((path, line, "(a) find -exec/-delete"))
                elif u == "rm" and any(re.match(r"^-[A-Za-z]*[rR]", a) or a == "--recursive" for a in args if a != "--"):
                    findings.append((path, line, "(a) recursive rm"))
                elif u == "alias":
                    findings.append((path, line, "(a) alias definition"))
                elif u in ("export", "declare", "typeset", "local", "readonly"):
                    for x in words[k + 1:]:
                        xa = unquote(x.raw)
                        if xa.startswith("-") and not dynamic(x.raw):
                            if "n" in xa[1:] and xa.startswith("-") and not xa.startswith("--"):
                                findings.append((path, line, "(a) %s -n (nameref): a variable aliasing another name" % u))
                            continue
                        namepart = x.raw.split("=", 1)[0]
                        if dynamic(namepart): findings.append((path, line, "(a) %s with a dynamic variable name: %s" % (u, x.raw[:60]))); continue
                        m = re.match(r"[A-Za-z_][A-Za-z0-9_]*", unquote(namepart))
                        if m: wrote(m.group(0))
                elif u == "printf" and "-v" in args:
                    vi = k + 1 + args.index("-v") + 1
                    if vi >= len(words): findings.append((path, line, "(a) printf -v without a name"))
                    elif dynamic(words[vi].raw):
                        tx = text_from(k)
                        hit = [e for e in DYN_NAME_EXEMPT.get(base, []) if e[0] == fn and e[1] == tx]
                        if hit: exempt_used.add((base, fn, tx))
                        else: findings.append((path, line, "(a) printf -v with a dynamic variable name: %s" % tx[:80]))
                    else: wrote(unquote(words[vi].raw).split("[", 1)[0])
                elif u in ("read", "mapfile", "readarray"):
                    for x in words[k + 1:]:
                        xa = unquote(x.raw)
                        if xa.startswith("-"): continue
                        if dynamic(x.raw): findings.append((path, line, "(a) %s into a dynamic variable name" % u)); continue
                        if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", xa): wrote(xa)
                elif u == "unset":
                    for x in words[k + 1:]:
                        xa = unquote(x.raw)
                        if not dynamic(x.raw) and xa in ("PATH", "HI_GX_BIN", "HI_GX_COMMIT_OK", "HI_GX_INIT_OK"):
                            writes.append((fn, xa, cmdtext))
                elif u == "trap":
                    if args and args[0] not in ("-", "-p", "-l", "--"):
                        if dynamic(words[k + 1].raw):
                            findings.append((path, line, "(a) trap with a non-literal command: %s" % words[k + 1].raw[:60]))
                        else:
                            walk(unquote(words[k + 1].raw), line, depth + 1)
                elif u in ("cp", "ln", "mv", "link", "touch"):
                    t2 = text_from(k)
                    hit = [e for e in SANCTIONED_FILE_CMDS.get(base, []) if e[0] == fn and e[1] == t2]
                    if hit: exempt_used.add((base, "file:" + str(fn), t2))
                    else: findings.append((path, line, "(a) %s outside the sanctioned places: %s" % (u, t2[:80])))
                elif u in BANNED_CMDS:
                    findings.append((path, line, "(a) %s is not allowed in the installer/updater" % u))
                elif u in ("chmod", "chown", "chgrp") and any(re.match(r"^-[A-Za-z]*R", a) or a == "--recursive" for a in args):
                    findings.append((path, line, "(a) recursive %s" % u))
                elif u == "sed" and any(re.match(r"^-[A-Za-z]*i", a) or a.startswith("--in-place") for a in args):
                    findings.append((path, line, "(a) sed -i (in-place edit)"))
                elif u in GITWRAP:
                    a = list(words[k + 1:])
                    if u == "hi_git_url": a = a[1:]
                    j = 0; bad = None
                    while j < len(a):
                        x = unquote(a[j].raw)
                        if x == "-C": j += 2; continue
                        if x == "-c":
                            if j + 1 >= len(a) or dynamic(a[j + 1].raw) or unquote(a[j + 1].raw) != "protocol.file.allow=always":
                                bad = "-c other than protocol.file.allow=always"
                            j += 2; continue
                        if x == "--no-optional-locks": j += 1; continue
                        break
                    if bad is None:
                        if fn in ("hi_git", "hi_git_url") and j < len(a) and a[j].raw == '"$@"' and j == len(a) - 1:
                            pass  # the thin forwarders themselves
                        elif j >= len(a): bad = "no subcommand"
                        elif dynamic(a[j].raw): bad = "dynamic subcommand %s" % a[j].raw
                        elif unquote(a[j].raw) not in ALLOW: bad = "subcommand not on the allow-list: %s" % unquote(a[j].raw)
                        else: bad = gx_shape(unquote(a[j].raw), a[j + 1:])
                    if bad is None and j < len(a) and not dynamic(a[j].raw):
                        sub_ = unquote(a[j].raw); rest_ = [unquote(x.raw) for x in a[j + 1:]]
                        cfg_rd = (rest_[:1] in (["--get"], ["--get-all"], ["--get-regexp"], ["--list"])
                                  or (len(rest_) >= 3 and rest_[0] == "-f" and rest_[2] in ("--get", "--get-all", "--get-regexp", "--list")))
                        mut = (sub_ in MUTATING_GIT or (sub_ == "config" and not cfg_rd) or (sub_ == "remote" and rest_[:1] == ["set-url"]))
                        if mut and fn not in ("hi_git", "hi_git_url"):
                            hit = [e for e in GX_EXACT.get(base, []) if e[0] == fn and e[1] == t]
                            if hit: exempt_used.add((base, "gx:" + str(fn), t))
                            else: bad = "changes the repository outside the sanctioned places: %s" % t[:90]; COLLECT.append(("gx", base, fn, t))
                    if bad: findings.append((path, line, "(a) %s: %s" % (u, bad)))
                else:
                    t2 = text_from(k)
                    if u in fn_names and u not in READ_OK and u not in EXACT_CMDS and u not in ("sed", "awk"): pass
                    elif u in SAFE_BUILTIN: pass
                    elif u in READ_OK:
                        pb = read_ok(u, args)
                        if pb: findings.append((path, line, "(a) %s: %s" % (u, pb)))
                    elif u in ("sed", "awk"):
                        pw, pb = prog_of(u, words[k + 1:])
                        if pb: findings.append((path, line, "(a) %s" % pb))
                        elif pw in PROGS.get(base, set()): exempt_used.add((base, "prog", pw))
                        else: findings.append((path, line, "(a) %s program not on the allow-list: %s" % (u, (pw or "")[:80]))); COLLECT.append(("prog", base, fn, pw))
                    elif u in EXACT_CMDS:
                        hit = [e for e in EXT_EXACT.get(base, []) if e[0] == fn and e[1] == t2]
                        if hit: exempt_used.add((base, "ext:" + str(fn), t2))
                        else: findings.append((path, line, "(a) %s outside the sanctioned places: %s" % (u, t2[:80]))); COLLECT.append(("ext", base, fn, t2))
                    else:
                        findings.append((path, line, "(a) command not on the allow-list: %s" % t2[:80]))
                break
    walk(text, 1)
    return writes, rwrites


def gx_shape(sub, rest):
    """the exact argument shapes the scripts use for the subcommands that reach a remote or change refs/config"""
    lit = [(unquote(x.raw), dynamic(x.raw), x.raw) for x in rest]
    for uq, dyn, raw in lit:
        lead = raw.lstrip("\"'")
        if lead.startswith("+") or "::" in uq:
            return "forced refspec or transport helper (+… / …::…): %s" % raw[:60]
        if not dyn and re.match(r"--(refmap|update-head-ok|recursive|recurse-submodules|upload-pack|receive-pack|exec|config|template|separate-git-dir|reference|mirror|force|prune)", uq):
            return "option not allowed: %s" % uq
    v = [uq for uq, _, _ in lit]; d = [dy for _, dy, _ in lit]
    def lit_is(i, val): return i < len(v) and not d[i] and v[i] == val
    def word(i): return i < len(v) and not v[i].startswith("-")
    if sub == "fetch":
        return None if (len(v) == 3 and lit_is(0, "--quiet") and lit_is(1, "--tags") and word(2)) else "fetch must be exactly: fetch --quiet --tags REMOTE"
    if sub == "clone":
        if lit_is(1, "--filter=blob:none"): v = v[:1] + v[2:]; d = d[:1] + d[2:]
        return None if (len(v) == 5 and lit_is(0, "--quiet") and lit_is(1, "--no-checkout") and lit_is(2, "--") and word(3) and word(4)) else "clone must be: clone --quiet [--filter=blob:none] --no-checkout -- URL DIR"
    if sub == "submodule":
        if lit_is(0, "add") and len(v) == 5 and lit_is(1, "--quiet") and lit_is(2, "--"): return None
        if lit_is(0, "update") and len(v) == 5 and lit_is(1, "--init") and lit_is(2, "--quiet") and lit_is(3, "--"): return None
        if lit_is(0, "absorbgitdirs") and len(v) == 3 and lit_is(1, "--"): return None
        return "submodule must be: add --quiet -- URL PATH | update --init --quiet -- PATH | absorbgitdirs -- PATH"
    if sub == "remote":
        if not v or (lit_is(0, "get-url") and len(v) == 2) or (lit_is(0, "set-url") and len(v) == 3 and lit_is(1, "origin")): return None
        return "remote must be: remote | get-url NAME | set-url origin PATH"
    if sub == "commit":
        return None if (len(v) >= 5 and lit_is(0, "-q") and lit_is(1, "-m") and lit_is(3, "--")) else "commit must be: commit -q -m MSG -- PATH..."
    if sub == "init":
        return None if (v == ["-q"] and not d[0]) else "init must be: init -q"
    if sub == "add":
        return None if lit_is(0, "--") else "add must be: add -- PATH..."
    return None


# ───────────────────────── raw denylist (c) ─────────────────────────
RULES = [
    ("push", re.compile(r"\bpush\b")), ("send-pack", re.compile(r"send-pack")),
    ("--force", re.compile(r"--force\b")), ("reset", re.compile(r"\breset\b")), ("rebase", re.compile(r"\brebase\b")),
    ("filter-branch", re.compile(r"filter-branch")), ("update-ref", re.compile(r"update-ref")),
    ("clean -f", re.compile(r"\bclean\s+-[A-Za-z]*f")), ("checkout -f/-B", re.compile(r"\bcheckout\s+(-[A-Za-z]*[fB]|--force)")),
    ("branch -D", re.compile(r"\bbranch\s+-[A-Za-z]*D")), ("tag -f", re.compile(r"\btag\s+(-[A-Za-z]*f|--force)")),
    ("switch", re.compile(r"\bswitch\b")), ("--amend", re.compile(r"--amend\b")),
    ("recursive rm", re.compile(r"\brm\b[^;&|\n]*\s(-[A-Za-z]*[rR][A-Za-z]*|--recursive)\b")),
    ("-delete", re.compile(r"\s-delete\b")), ("-exec", re.compile(r"\s-exec(dir)?\b")),
    ("eval", re.compile(r"(^|[\s;&|(])eval\b")), ("awk system()", re.compile(r"\bsystem\s*\(")),
    ("awk getline", re.compile(r"\bgetline\b")), ("python spawn", re.compile(r"subprocess|os\.system|os\.popen|os\.exec")),
    ("ANSI-C escape", re.compile(r"\$'[^']*\\[0-7xuU]")),
    ("--refmap", re.compile(r"--refmap")), ("--update-head-ok", re.compile(r"--update-head-ok")),
    ("ext:: transport", re.compile(r"\bext::")),
    ("GIT_CONFIG_* injection", re.compile(r"GIT_CONFIG_(COUNT|KEY|VALUE|PARAMETERS)")),
    ("GIT_EXEC_PATH", re.compile(r"GIT_EXEC_PATH")),
    ("recursive chmod/chown", re.compile(r"\bch(mod|own|grp)\b[^;&|\n]*\s(-[A-Za-z]*R|--recursive)\b")),
    ("truncate", re.compile(r"\btruncate\b")), ("sed -i", re.compile(r"\bsed\b[^;&|\n]*\s(-[A-Za-z]*i|--in-place)\b")),
]
Q = r"""(?:"(?:[^"\\]|\\.)*"|'[^']*')"""
CARRIER_FN = re.compile(r"\b(?:hi_say|hi_warn|hi_err|say|warn|die|hi_ask\s+\w+)\b(?:\s+[0-9]+)?((?:\s+" + Q + r")+)")
CARRIER_PR = re.compile(r"\b(printf|echo)\b((?:\s+(?:" + Q + r"|-[A-Za-z]+))+)")
# policy text, not calls: the report's "push":"never", and the exact claude DENY list (the installer passes it
# to claude --disallowedTools so the agent cannot push); only these whole literals are exempt
POLICY = [re.compile(re.escape(x)) for x in ("grep -c '^update by push'", "'push: never\\n", '\\"push\\":\\"never\\"', "push: never",
                                              "HI_CLAUDE_DENY='WebFetch,WebSearch,Bash(git push *),Bash(git push),Bash(git * push *),Bash(git * push),Bash(*git push*),Bash(*git * push*),Bash(env git*),Bash(command git*),Bash(*send-pack*),Bash(gh *),Bash(glab *),Bash(curl *),Bash(wget *)'")]


def blank(seg):
    return re.sub(Q, lambda m: m.group(0) if (m.group(0)[0] == '"' and ("$(" in m.group(0) or "`" in m.group(0))) else '""', seg)


def prepare(l):
    for rx in POLICY: l = rx.sub("''", l)
    l = re.sub(r"=~\s+(?:\\.|[^\s\]]|\s(?!\]\]))*", "=~ ''", l)  # a [[ =~ ]] regex is data
    l = CARRIER_FN.sub(lambda m: m.group(0)[:m.start(1) - m.start(0)] + blank(m.group(1)), l)
    l = CARRIER_PR.sub(lambda m: m.group(1) + blank(m.group(2)), l)
    return l


def raw_scan(path, text, findings):
    fmap, _ = func_map(text)
    hd = None  # delimiter of a QUOTED (non-expanding) heredoc whose body is data, not code
    for n, line in enumerate(text.split("\n"), 1):
        s = line.strip()
        if hd is not None:
            if s == hd: hd = None
            continue
        m = re.search(r"<<-?\s*(['\"])([A-Za-z_][A-Za-z0-9_]*)\1", line)
        if m and not s.startswith("#"): hd = m.group(2); line = line[:m.start()]
        if s.startswith("#") or fmap.get(n) == "hi_gx_check": continue
        l = prepare(re.sub(r"(^|\s)#\s.*$", "", line))
        for name, rx in RULES:
            if rx.search(l): findings.append((path, n, "(c) forbidden: %s" % name))


# ───────────────────────── allow-list (b) ─────────────────────────
def block_of(text):
    m = re.search(r"^# >>> hi_gx.*?^# <<< hi_gx$", text, re.S | re.M)
    return m.group(0) if m else None


def allow_check(path, text, findings):
    blk = block_of(text)
    if blk is None:
        findings.append((path, 0, "(b) no '# >>> hi_gx … # <<< hi_gx' wrapper block")); return
    m = re.search(r"^hi_gx_check\(\) \{.*?^\}$", blk, re.S | re.M)
    if not m: findings.append((path, 0, "(b) hi_gx_check not found in the block")); return
    body = m.group(0)
    k = body.find('case "$sub" in')
    if k < 0: findings.append((path, 0, "(b) hi_gx_check has no case \"$sub\" in")); return
    labels = re.findall(r"^    ([^\s#(][^)\n]*)\)", body[k:], re.M)
    seen = set()
    for lab in labels:
        for x in lab.split("|"):
            x = x.strip(); seen.add(x)
            if x in FORBIDDEN_SUB - {"*"} or (x not in ALLOW and x != "*"):
                findings.append((path, 0, "(b) allow-list label not permitted: %s" % x))
    if "*" not in seen: findings.append((path, 0, "(b) hi_gx_check has no default *) branch"))
    d = re.search(r"^    \*\)(.*)$", body[k:], re.M)
    if not d or "hi_gx_refuse" not in d.group(1) or "return 3" not in d.group(1):
        findings.append((path, 0, "(b) the default *) branch does not refuse (hi_gx_refuse; return 3)"))
    return seen


# ───────────────────────── runtime (d) ─────────────────────────
RT_CASES = r'''
P=p; x=pu; y=sh; S=send-pack; F=--force
t refuse hi_gx push origin main
t refuse hi_gx -C "$W" push
t refuse hi_gx ${P}ush origin HEAD
t refuse hi_gx $'\x70ush'
t refuse hi_gx p\ush
t refuse hi_gx ${x}${y}
t refuse hi_gx "$(printf pu)sh"
t refuse hi_gx $S origin
t refuse hi_gx send-pack x
t refuse hi_gx checkout -qf main
t refuse hi_gx checkout -f 0123456789012345678901234567890123456789
t refuse hi_gx checkout -B main
t refuse hi_gx checkout --force --detach 0123456789012345678901234567890123456789
t refuse hi_gx checkout --quiet --detach main
t refuse hi_gx checkout --quiet 0123456789012345678901234567890123456789
t refuse hi_gx reset -q --hard
t refuse hi_gx reset --har
t refuse hi_gx reset
t refuse hi_gx rebase main
t refuse hi_gx filter-branch -f
t refuse hi_gx update-ref -m x -d refs/heads/main
t refuse hi_gx update-ref refs/heads/main HEAD~3
t refuse hi_gx branch -Df x
t refuse hi_gx switch --discard-changes main
t refuse hi_gx tag -f x
t refuse hi_gx clean -fdx
t refuse hi_gx stash
t refuse hi_gx worktree add x
t refuse hi_gx gc --prune=now
t refuse hi_gx merge x
t refuse hi_gx pull
t refuse hi_gx restore x
t refuse hi_gx mv a b
t refuse hi_gx am x
t refuse hi_gx apply x
t refuse hi_gx cherry-pick x
t refuse hi_gx revert x
t refuse hi_gx notes add
t refuse hi_gx replace a b
t refuse hi_gx symbolic-ref HEAD refs/heads/x
t refuse hi_gx reflog expire --all
t refuse hi_gx commit -m x
t refuse hi_gx_commit_amend
t refuse hi_gx init
t refuse hi_gx fetch --force origin
t refuse hi_gx fetch $F origin
t refuse hi_gx fetch -f origin
t refuse hi_gx fetch origin '+refs/heads/*:refs/heads/*'
t refuse hi_gx fetch --upload-pack=touch origin
t refuse hi_gx fetch --prune origin
t refuse hi_gx ls-remote --upload-pack=x origin
t refuse hi_gx clone --upload-pack=x u d
t refuse hi_gx clone -u x u d
t refuse hi_gx clone -c core.hooksPath=/tmp u d
t refuse hi_gx clone --config core.hooksPath=/tmp u d
t refuse hi_gx clone --template=/tmp u d
t refuse hi_gx clone --recurse-submodules u d
t refuse hi_gx add -f x
t refuse hi_gx add --force x
t refuse hi_gx config core.hooksPath /tmp
t refuse hi_gx config alias.p '!git push'
t refuse hi_gx config --unset core.x
t refuse hi_gx config -f f --remove-section core
t refuse hi_gx config -f f core.sshCommand x
t refuse hi_gx config --add x y
t refuse hi_gx rm -r --cached -- x
t refuse hi_gx rm -f --cached -- x
t refuse hi_gx rm -- x
t refuse hi_gx rm --cached x
t refuse hi_gx submodule foreach 'git push'
t refuse hi_gx submodule deinit -f x
t refuse hi_gx submodule update --force -- x
t refuse hi_gx submodule update --rebase -- x
t refuse hi_gx submodule update --merge -- x
t refuse hi_gx submodule update --remote -- x
t refuse hi_gx submodule sync
t refuse hi_gx remote add x u
t refuse hi_gx remote remove origin
t refuse hi_gx remote set-url --push origin u
t refuse hi_gx remote set-url other u
t refuse hi_gx diff --output=/tmp/x
t refuse hi_gx log --ext-diff
t refuse hi_gx -c alias.p='!git push' p
t refuse hi_gx -c core.sshCommand=x fetch
t refuse hi_gx -C "$W" -c core.hooksPath=/tmp status
t refuse hi_gx --git-dir=x push
t refuse hi_gx --exec-path=x status
t refuse hi_gx -C
t refuse hi_gx
t refuse hi_gx ''
t refuse hi_gx -Cx push
t refuse hi_gx daemon
t refuse hi_gx archive HEAD
t refuse hi_gx bundle create x
t refuse hi_gx fetch --quiet -- origin +refs/heads/main:refs/heads/main
t refuse hi_gx fetch --quiet --tags origin +refs/heads/main:refs/heads/main
t refuse hi_gx fetch --quiet --tags origin refs/heads/main:refs/heads/main
t refuse hi_gx fetch --quiet origin main --refmap=+refs/heads/*:refs/heads/*
t refuse hi_gx fetch --quiet --tags --refmap x origin
t refuse hi_gx fetch --update-head-ok --quiet --tags origin
t refuse hi_gx fetch --quiet --tags 'ext::sh -c touch% x'
t refuse hi_gx fetch origin
t refuse hi_gx submodule update --init --recursive
t refuse hi_gx submodule update --init --quiet -- --recursive
t refuse hi_gx submodule update --init --quiet --recursive -- p
t refuse hi_gx submodule add --quiet -- 'ext::sh -c x' p
t refuse hi_gx submodule status
t refuse hi_gx remote set-url origin 'ext::sh -c touch% /tmp/p'
t refuse hi_gx remote set-url origin https://x/y.git
t refuse hi_gx clone --quiet --no-checkout -- --upload-pack=touch d
t refuse hi_gx clone --quiet --no-checkout -- 'ext::sh -c x' d
t refuse hi_gx clone --quiet --no-checkout u d
t refuse hi_gx ls-remote -- 'ext::sh -c x'
t refuse hi_gx ls-remote -- --upload-pack=x
t refuse hi_gx add x
t refuse hi_gx init -q --template=/tmp
t refuse hi_gx rev-parse +HEAD
t refuse hi_gx_commit_short
t refuse hi_gx commit -q -m x -- p
t refuse hi_gx status --force
t refuse hi_gx log -f
t refuse hi_gx log --refmap=x
t refuse hi_gx ls-files --recursive
t refuse hi_gx show 'ext::sh -c x'
t refuse hi_gx status +x
t allow hi_gx rev-parse HEAD
t allow hi_gx_envclean
t allow hi_gx_pathswap
t allow hi_gx -C "$W" --no-optional-locks status --porcelain
t allow hi_gx -c protocol.file.allow=always ls-remote --tags -- u
t allow hi_gx clone --quiet --filter=blob:none --no-checkout -- u d
t allow hi_gx fetch --quiet --tags origin
t allow hi_gx checkout --quiet --detach 0123456789012345678901234567890123456789
t allow hi_gx rm -q --cached -- x
t allow hi_gx rm -q --cached --ignore-unmatch -- .gitmodules
t allow hi_gx config -f f --get submodule.x.path
t allow hi_gx config -f f --remove-section submodule.x
t allow hi_gx config --unset helix-installer.clone
t allow hi_gx config helix-installer.clone true
t allow hi_gx remote
t allow hi_gx remote set-url origin /x/up.git
t allow hi_gx remote get-url origin
t allow hi_gx submodule add --quiet -- u p
t allow hi_gx submodule update --init --quiet -- p
t allow hi_gx submodule absorbgitdirs -- p
t allow hi_gx add -- .gitmodules
t allow hi_gx log --oneline --no-decorate a..b
t allow hi_gx diff a b -- CHANGELOG.md
t allow hi_gx_commit_ok
t allow hi_gx_init_ok
t allow hi_gx_timeout
'''
RT_HEAD = r'''
set -u
W="$SANDBOX"
hi_gx_commit_amend() { HI_GX_COMMIT_OK=1 hi_gx commit --amend -m x; }
hi_gx_commit_ok() { HI_GX_COMMIT_OK=1 hi_gx commit -q -m x -- p; }
hi_gx_init_ok() { HI_GX_INIT_OK=1 hi_gx init -q; }
hi_gx_timeout() { HI_GX_TIMEOUT=5 hi_gx rev-parse HEAD; }
hi_gx_commit_short() { HI_GX_COMMIT_OK=1 hi_gx commit -qm x; }
hi_gx_envclean() { GIT_DIR=/evil GIT_WORK_TREE=/evil GIT_INDEX_FILE=/evil GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.fsmonitor \
  GIT_CONFIG_VALUE_0=evil GIT_CONFIG_PARAMETERS=evil GIT_EXEC_PATH=/evil GIT_SSH_COMMAND=evil GIT_SSH=/evil hi_gx rev-parse HEAD; }
hi_gx_pathswap() { hi_gx rev-parse HEAD && PATH="$SANDBOX/bin2:$PATH" hi_gx rev-parse HEAD; }
t() {
  local want="$1"; shift
  : >"$MARK"
  "$@" >/dev/null 2>"$SANDBOX/err" 9>"$SANDBOX/err9"; local rc=$?
  local called=0; [ -s "$MARK" ] && called=1
  printf '%s\t%s\t%s\t%s\n' "$want" "$rc" "$called" "$*"
}
'''


def runtime(path, findings):
    base = os.path.basename(path)
    with tempfile.TemporaryDirectory(prefix="cm_nopush_rt.") as sb:
        os.mkdir(os.path.join(sb, "bin"))
        fg = os.path.join(sb, "bin", "git")
        with open(fg, "w") as f:
            f.write('#!/bin/sh\n# FAKE git (gate-logic test double): records the call and the git-relevant environment\n'
                    'printf "%s\\n" "$*" >>"$MARK"\n'
                    'printf "%s|%s|%s|%s|%s|%s|%s|%s|%s\\n" "$GIT_DIR" "$GIT_WORK_TREE" "$GIT_INDEX_FILE" "$GIT_CONFIG_COUNT" '
                    '"$GIT_CONFIG_KEY_0" "$GIT_CONFIG_PARAMETERS" "$GIT_EXEC_PATH" "$GIT_SSH" "$GIT_SSH_COMMAND" >>"$ENVMARK"\nexit 0\n')
        os.chmod(fg, 0o755)
        os.mkdir(os.path.join(sb, "bin2"))
        with open(os.path.join(sb, "bin2", "git"), "w") as f:
            f.write('#!/bin/sh\n# FAKE git #2: must never run (git is resolved once)\nprintf "SWAPPED\\n" >>"$SWAPMARK"\nexit 0\n')
        os.chmod(os.path.join(sb, "bin2", "git"), 0o755)
        mode = "HELIX_UPDATER_LIB_MODE=1" if "update" in base else "HELIX_INSTALLER_LIB_MODE=1"
        script = "%s . %s >/dev/null 2>&1 || { echo SOURCE-FAILED; exit 9; }\n%s\n%s" % (mode, sh_quote(path), RT_HEAD, RT_CASES)
        env = {"PATH": os.path.join(sb, "bin") + ":/usr/bin:/bin", "MARK": os.path.join(sb, "mark"), "SANDBOX": sb,
               "HOME": sb, "LC_ALL": "C", "ENVMARK": os.path.join(sb, "envmark"), "SWAPMARK": os.path.join(sb, "swapmark")}
        r = subprocess.run(["bash", "-c", script], cwd=sb, env=env, capture_output=True, text=True, timeout=120)
        rows = [l.split("\t") for l in r.stdout.splitlines() if l.count("\t") == 3]
        if "SOURCE-FAILED" in r.stdout or len(rows) < RT_CASES.count("\nt "):
            findings.append((path, 0, "(d) runtime harness could not run every case (%d rows): %s" % (len(rows), (r.stdout + r.stderr)[-300:])))
            return None
        allowed_seen = 0
        for want, rc, called, cmd in rows:
            if want == "refuse" and not (rc == "3" and called == "0"):
                findings.append((path, 0, "(d) runtime: NOT refused (rc=%s, git reached=%s): %s" % (rc, called, cmd)))
            if want == "allow":
                if rc == "0" and called == "1": allowed_seen += 1
                else: findings.append((path, 0, "(d) runtime: allowed form did not reach git (rc=%s): %s" % (rc, cmd)))
        envs = open(os.path.join(sb, "envmark")).read().splitlines() if os.path.exists(os.path.join(sb, "envmark")) else []
        clean = "||||||||ssh -o BatchMode=yes -o ConnectTimeout=10"
        if not envs: findings.append((path, 0, "(d) runtime: the environment recorder saw no git call (blind)"))
        for e in sorted(set(envs)):
            if e != clean: findings.append((path, 0, "(d) runtime: git ran with an unsanitised environment: %s" % e[:120]))
        if os.path.exists(os.path.join(sb, "swapmark")):
            findings.append((path, 0, "(d) runtime: a PATH change after the first call swapped the git binary"))
        return allowed_seen


def sh_quote(s):
    return "'" + s.replace("'", "'\\''") + "'"


# ───────────────────────── control needles ─────────────────────────
def policy(path, text, writes, rwrites, findings, inventory=False):
    """protected-name writes, file-writing redirections and wrapper-switch token counts vs the exact lists"""
    from collections import Counter
    base = os.path.basename(path)
    got = Counter((fn, nm, t) for fn, nm, t in writes)
    want = Counter(SANCTIONED_WRITES.get(base, []))
    for key, c in (got - want).items():
        findings.append((path, 0, "(a) write to protected name %s outside the sanctioned places (in %s): %s" % (key[1], key[0], key[2][:90])))
    for key, c in (want - got).items():
        findings.append((path, 0, "(a) sanctioned write no longer present (update the gate): %s %s" % (key[0], key[2][:60])))
    got = Counter((fn, op, t) for fn, op, t, _ in rwrites)
    want = Counter(SANCTIONED_REDIRS.get(base) or [])
    if inventory: return sorted(got.elements(), key=str)
    for key, c in (got - want).items():
        ln = [l for fn, op, t, l in rwrites if (fn, op, t) == key]
        findings.append((path, ln[0] if ln else 0, "(a) redirection writes a file outside the sanctioned places: %s %s %s" % (key[0], key[1], key[2][:60])))
    for key, c in (want - got).items():
        findings.append((path, 0, "(a) sanctioned redirection no longer present (update the gate): %s %s %s" % key))
    if base in SWITCH_TOKENS:
        blk = block_of(text) or ""
        code = "\n".join(re.sub(r"(^|\s)#.*$", "", l) for l in text.replace(blk, "").split("\n"))
        for tok, n in SWITCH_TOKENS[base].items():
            c = len(re.findall(r"\b%s\b" % tok, code))
            if c != n: findings.append((path, 0, "(a) %s appears %d time(s) outside the hi_gx block (expected exactly %d)" % (tok, c, n)))


def var_bindings(text, specs):
    """[(function, name, stripped line)] of every line that binds one of the pinned variables"""
    fmap, _ = func_map(text)
    out = []
    for n, l in enumerate(text.split("\n"), 1):
        code = re.sub(r"(^|\s)#.*$", "", l).strip()
        if not code: continue
        fn = fmap.get(n)
        bare = re.sub(r"\$\{?\w+\}?", "", re.sub(r"\"[^\"]*\"|'[^']*'", '""', code))   # quoted text and expansions are not bindings
        for sfn, nm in specs:
            if sfn is not None and sfn != fn: continue
            q = re.escape(nm)
            if (re.search(r"(^|[\s;&|({\"'])%s\+?=" % q, code)
                    or re.search(r"\b(local|declare|typeset|export|readonly|read|mapfile|readarray|unset)\b[^;|&]*(?<![\w$])%s\b" % q, bare)
                    or re.search(r"\bfor\s+%s\b" % q, code) or re.search(r"printf\s+-v\s+%s\b" % q, code)
                    or re.search(r"\(\(\s*%s\b" % q, code)
                    or re.search(r"(^|[\s;&|({\"'])%s\[[^\]]*\]\+?=" % q, code)      # array element: NAME[0]=
                    or re.search(r"\$\{%s:?=" % q, code)):                               # ${NAME:=v} / ${NAME=v}
                out.append((fn, nm, code))
    return sorted(set(out), key=repr)


def var_pin_specs(base):
    sp = []
    for fn, nm in VAR_PIN_SPECS.get(base, []):
        sp.append((None if nm in VAR_PIN_GLOBALS else fn, nm))
    return sorted(set(sp), key=repr)


def dup_func_check(path, text, findings):
    """a function defined twice in one file (the later definition silently replaces the earlier, e.g. a second
    hi_marker_path before main()) is a finding for every function name"""
    from collections import Counter
    _, defs = func_map(text)
    for nm, c in Counter(d[0] for d in defs).items():
        if c > 1:
            ln = [n for d, n in defs if d == nm][1]
            findings.append((path, ln, "(a) function %s is defined %d times (a later definition replaces the reviewed one)" % (nm, c)))


def var_pin_check(path, text, findings):
    base = os.path.basename(path)
    if base not in VAR_PIN_SPECS: return
    from collections import Counter
    got = Counter(var_bindings(text, var_pin_specs(base))); want = Counter(map(tuple, VAR_PINS.get(base, [])))
    for key in (got - want):
        findings.append((path, 0, "(a) a pinned target variable is bound outside the reviewed places (in %s): %s: %s" % (key[0], key[1], key[2][:100])))
    for key in (want - got):
        findings.append((path, 0, "(a) a pinned target-variable binding is gone (update the gate): %s %s: %s" % (key[0], key[1], key[2][:80])))


NEEDLE_FUNCS = {"hi_say", "hi_warn", "hi_err", "die", "say", "hi_on_signal"}


def scan_text(text, name="needle.sh", sanction=False):
    """findings for a planted snippet; sanction=True lists each of its lines as a reviewed (function None) call, so a
    VALID shape can be shown to pass while the same line unsanctioned is a finding"""
    f = []; used = set()
    if sanction:
        lines = [re.sub(r"^([A-Za-z_]\w*=\S*\s+)+", "", l.strip()) for l in text.split("\n") if l.strip()]
        GX_EXACT[name] = [(None, l) for l in lines]; EXT_EXACT[name] = [(None, l) for l in lines]
    try:
        w, rw = analyse(name, text, f, used); raw_scan(name, text, f)
        policy(name, text, w, rw, f)
    finally:
        GX_EXACT.pop(name, None); EXT_EXACT.pop(name, None)
    return f


MUST_FIND = ["x=1\n  git push origin main\n", 'bash -c "hi_gx status"\n', 'cmd=(git status); "${cmd[@]}"\n',
             '"git" status\n', 'command git status\n', 'timeout 5 git status\n', 'env A=1 git status\n',
             'x="$(git rev-parse HEAD)"\n', 'printf "%s" x | bash\n', 'bash <<<"hi_gx status"\n', '$G status\n',
             '"$G" status\n', "$'\\x67it' status\n", 'hi_gx "$op" x\n', 'hi_gx -C "$d" ${P}ush\n', 'hi_gx p\\ush\n',
             'hi_git push\n', 'hi_git_url "$u" -C x fetch --force\n', 'f() { git "$@"; }\n', 'eval "$x"\n',
             '. "$f"\n', 'find . -delete\n', 'rm -f -r "$x"\n', 'xargs git status\n', 'echo `git status`\n',
             'a=$(printf pu); hi_gx ${a}sh\n', 'hi_gx -c alias.x=y status\n', 'perl -e 1\n',
             'python3 -c "$code"\n', "awk 'BEGIN { system(\"id\") }'\n", 'sh "$x"\n', 'alias g=git\n',
             'export GIT_DIR=x\n', 'PATH="$x:$PATH"\n', 'printf -v HI_GX_COMMIT_OK 1\n', 'printf -v "$v" 1\n',
             'declare -g HI_GX_INIT_OK=1\n', 'local -n r=HI_GX_COMMIT_OK\n', 'HI_GX_COMMIT_OK=1 hi_gx status\n',
             'env GIT_CONFIG_COUNT=1 hi_gx status\n', 'read -r PATH <f\n', 'for PATH in a; do :; done\n',
             '(( HI_GX_COMMIT_OK=1 ))\n', 'x=$(( ${v}=1 ))\n', 'trap "$x" EXIT\n', "trap 'git push' EXIT\n",
             'chmod -R 777 x\n', 'truncate -s0 f\n', ': >"$f"\n', '{ echo x; } >"$f"\n', 'echo x >>log\n',
             'exec 7>"$t"\n', 'sed -i s/a/b/ f\n', 'tee f </dev/null\n', 'hi_gx fetch --quiet -- origin +a:b\n',
             'hi_gx fetch --quiet --tags origin --refmap=x\n', 'hi_gx submodule update --init --recursive\n',
             'hi_gx remote set-url origin "ext::x"\n', 'hi_gx clone -- --upload-pack=x d\n', 'hi_gx commit -qm x\n',
             'rm -f -- "$f"\n', 'chmod 700 "$d"\n', 'tar -xf a -C b\n', 'patch -s f d\n', 'unlink "$f"\n', 'ex -sc x f\n',
             'sed -n "w out" in\n', "awk 'BEGIN { printf \"\" > \"f\" }'\n", "python3 -I -c 'open(\"f\", \"w\")'\n",
             'hi_gx -C "$s" fetch --quiet --tags "$r"\n', 'mkdir -p "$d"\n', 'kill -9 "$p"\n', 'cp /dev/null "$f"\n',
             'dd if=/dev/zero of=f\n', 'install -m 755 a b\n', 'ed -s f\n', 'cat /dev/null >"$f"\n',
             'python3 -I - <<\'PY\'\nimport os\nos.remove("f")\nPY\n']
MUST_PASS = ["# git push origin main\n", 'hi_say "the installer never pushes; git push yourself"\n',
             'die 3 "commit/push or stash first"\n', "printf 'step: git commit (local only)\\n'\n",
             'hi_err "never reset --hard" || return 1\n', "printf 'push: never\\nbackups: %s\\n' \"$x\"\n",
             '[[ "$u" =~ ^(https?|ssh|git|file)://x ]] && return 0\n', '[[ "$x" =~ ^git\\ push$ ]] && y=1\n', "cat <<'EOF'\ngit push origin main\nEOF\n",
             'hi_gx -C "$d" rev-parse HEAD\n', 'command -v git >/dev/null\n', 'x="$(hi_gx -C "$d" status)"\n',
             'case "$a" in "$x"|git) y=1 ;; esac\n', "python3 -I -c 'import uuid; print(uuid.uuid4())'\n",
             'HI_GX_TIMEOUT=60 hi_gx -c protocol.file.allow=always ls-remote -- "$u"\n',
             'echo x >/dev/null 2>&1\n', 'echo x >&2\n', 'exec 9>&2\n', 'IFS=/ read -r -a parts <<<"$x"\n',
             'export GIT_TERMINAL_PROMPT=0\n', "trap 'hi_on_signal INT' INT\n", "trap '' INT TERM\n",
             'n=$((n+1))\n', 'for ((i=0; i<3; i++)); do :; done\n', '[ $(( a == b )) = 1 ]\n', 'chmod 700 "$d"\n',
             'hi_gx -C "$s" fetch --quiet --tags "$r"\n', 'hi_gx submodule update --init --quiet -- "$p"\n',
             'HI_GX_TIMEOUT=9 hi_gx clone --quiet --filter=blob:none --no-checkout -- "$u" "$d"\n']


def main(files):
    blind = [x for x in MUST_FIND if not scan_text(x)] + [x for x in MUST_PASS if scan_text(x, sanction=True)]
    if blind:
        print("⚠ %s: BLIND (exit 2) — lexer failed its control needles: %r" % (GATE, blind)); return 2
    findings, used, blocks, allowed = [], set(), {}, 0
    for p in files:
        text = open(p, encoding="utf-8", errors="replace").read()
        w, rw = analyse(p, text, findings, used)
        raw_scan(p, text, findings)
        if os.environ.get("CM_NOPUSH_INVENTORY") == "1":
            for x in policy(p, text, w, rw, [], inventory=True): print("INVENTORY", os.path.basename(p), repr(x))
            for x in w: print("WRITE", os.path.basename(p), repr(x))
            if os.environ.get("CM_NOPUSH_SPECS") == "1":
                for sfn, snm in var_pin_specs(os.path.basename(p)): print("SPEC", os.path.basename(p), sfn or "-", snm)
            if os.environ.get("CM_NOPUSH_PINS") == "1":
                print("PINS", os.path.basename(p), repr(var_bindings(text, var_pin_specs(os.path.basename(p)))))
            continue
        policy(p, text, w, rw, findings)
        var_pin_check(p, text, findings)
        dup_func_check(p, text, findings)
        if "# >>> hi_gx" in text or os.path.basename(p) in EXEMPT:
            allow_check(p, text, findings)
            blocks[p] = block_of(text)
            a = runtime(p, findings)
            allowed += a or 0
    if os.environ.get("CM_NOPUSH_COLLECT") == "1":
        for kind, base, fn, t in sorted(set(COLLECT), key=repr): print("COLLECT", repr((kind, base, fn, t)))
        return 0
    if os.environ.get("CM_NOPUSH_INVENTORY") == "1":
        print("%s: INVENTORY MODE (no verdict)" % GATE); return 0
    distinct = {b for b in blocks.values() if b}
    if len(distinct) > 1:
        findings.append((" + ".join(blocks), 0, "(b) the hi_gx block differs between the scanned files"))
    for base, lst in list(EXEMPT.items()) + [(b, [(f, t, "") for f, t in l]) for b, l in DYN_NAME_EXEMPT.items()]:
        if not any(os.path.basename(p) == base for p in files): continue
        for fn, t, why in lst:
            if (base, fn, t) not in used:
                findings.append((base, 0, "(a) exemption no longer used (remove it from the gate): %s %s" % (fn, t)))
    for p, n, msg in findings:
        print("  FAIL %s:%d %s" % (p, n, msg))
    if findings:
        print("❌ %s: FAIL (%d finding(s))" % (GATE, len(findings))); return 1
    print("✅ %s: PASS (%d file(s); structure + allow-list + raw scan + runtime: %d allowed forms reached git, every "
          "forbidden form refused; control needles ok)" % (GATE, len(files), allowed))
    return 0


sys.exit(main(sys.argv[1:]))
PYGATE
