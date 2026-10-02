#!/usr/bin/env python3
"""io_trace_parse.py - parses a raw `strace -f -e trace=openat,stat,
newfstatat,lstat,execve,chdir -o <log>` log into {"reads":[...],"writes":[...]}.

Invoked ONLY by gates/io_trace.sh's `do_trace()` -- not a standalone CLI
contract of its own. See gates/io_trace.sh's own header comment for the
full design rationale (empirically-verified on this host: `[ -f "$path" ]`
in POSIX sh compiles to `newfstatat`, NEVER plain `stat`, on this glibc/
kernel combination -- confirmed by a real probe before writing this parser,
per §11.4.201(7)(c) "the path is part of the instrument").

Usage: io_trace_parse.py <strace-log-path>

T085 Round 1 remediation (2026-09-30, I5): the pre-remediation parser
unconditionally dropped EVERY syscall with a negative return code
(`if int(rc) < 0: continue`), so a gate branching on an ABSENT file (e.g.
`[ -f marker ] && exit 1`) never listed `marker` as an observed input --
creating the file would flip the gate's outcome with no corresponding
change ever detected in its recorded input set. It also recorded a
relative path (e.g. after `cd sub`, `rel.txt`) bare, with no cwd context,
so two gates reading files with the same basename in different
directories were indistinguishable. Both reproduced live before this fix
(§11.4.199): a fixture running `cd sub; [ -f rel.txt ]` traced to
`newfstatat(AT_FDCWD, "rel.txt", ...) = -1 ENOENT`, and the old parser
emitted `{"reads": [], "writes": []}` for it -- both the negative rc and
the missing cwd context caused the same silent loss for this one line.

Two cooperating fixes:

  (1) NEGATIVE lookups are no longer blanket-dropped. A failed
      openat/stat/newfstatat/lstat is skipped ONLY when it is genuine
      $PATH-command-search or dynamic-linker/locale noise (see
      `_is_noise()` below, now including a DYNAMIC check against the
      live `$PATH` environment variable's own directories -- verified
      live, 2026-09-30: on this host, a shell's own command-name lookup
      for a nonexistent command produces failed newfstatat/openat calls
      whose containing directory is *always* a literal `$PATH` entry;
      hardcoding a fixed prefix list is fragile across hosts/users with
      different `$PATH` values, so the noise set is now derived from the
      REAL `$PATH` this process inherited, plus a small STATIC prefix
      list for interpreter-startup noise that is never part of `$PATH`
      -- dynamic linker, `/proc`, `/dev`, `/sys`, locale files). A failed
      lookup that is NOT noise is recorded as a read -- the gate
      genuinely probed for that path and it was absent, which the
      module's own long-standing design philosophy already states is a
      real input ("a gate deciding on file existence has consumed that
      file as an input").
  (2) Relative paths are resolved to ABSOLUTE using per-PID cwd tracking
      seeded from this process's own `os.getcwd()` (the SAME cwd
      `do_trace()`'s `sh "$gate_script"` invocation started from -- no
      chdir happens between io_trace.sh's own start and the strace
      invocation) and updated on every observed `chdir("<path>")` syscall
      (io_trace.sh now traces `chdir` alongside the four existing
      syscalls). Verified live, 2026-09-30: this host's `/bin/sh`
      (dash) always passes an ALREADY-ABSOLUTE path to the `chdir(2)`
      syscall itself regardless of whether the shell script wrote
      `cd sub` (relative) or `cd /abs/path` -- so tracking is a simple
      per-PID "last chdir target" with a relative-argument fallback
      (`os.path.normpath(os.path.join(cwd, path))`) for any other shell
      implementation that might pass a relative chdir argument.
"""
import json
import os
import re
import sys

# Syscalls whose FIRST quoted-string argument is a path this tool observes.
# openat(AT_FDCWD, "<path>", <flags>, ...) = <rc>
# stat("<path>", ...) = <rc>                       (older glibc)
# newfstatat(AT_FDCWD, "<path>", ...) = <rc>        (this host, verified)
# lstat("<path>", ...) = <rc>
# faccessat(AT_FDCWD, "<path>", <mode>, ...) = <rc> (T085 Round 2 I-R2-5:
#   `[ -r marker ]`/`[ -x marker ]` permission-probe absence-branches were
#   previously invisible -- only `-e`-shaped existence checks (stat/
#   newfstatat) were covered; `access("<path>", <mode>) = <rc>` (the older
#   glibc name for the same check) is traced alongside it, and
#   `faccessat2` -- the modern kernel syscall dash's own `[ -r ... ]`
#   builtin was empirically verified (2026-09-30) to actually emit on
#   this host/kernel, NOT plain `faccessat` -- is traced too.
_SYSCALL_LINE = re.compile(
    r'^(?:(?P<pid>\d+)\s+)?(?P<syscall>openat|stat|newfstatat|lstat|faccessat2|faccessat|access)\((?P<args>.*)\)\s*=\s*(?P<rc>-?\d+)'
)

# chdir("<path>") = <rc> -- traced (io_trace.sh) specifically to resolve
# relative reads/writes against the CORRECT per-process cwd (I5 fix (2)).
_CHDIR_LINE = re.compile(
    r'^(?:(?P<pid>\d+)\s+)?chdir\("(?P<path>(?:[^"\\]|\\.)*)"\)\s*=\s*(?P<rc>-?\d+)'
)

# T085 Round 2 I-R2-4: <ppid> clone(...) = <cpid> (and the fork()/vfork()/
# clone3() equivalents, plus strace -f's own "<... clone resumed>) = <cpid>"
# shape when a clone's entry and exit land on different log lines) --
# traced (io_trace.sh now adds clone,fork,vfork,clone3 to its -e trace=
# list) specifically so a NEWLY-forked child's cwd is seeded from its
# PARENT's tracked cwd at fork time, not unconditionally from this
# process's own start_cwd (reproduced live before this fix: `cd sub;
# cat data.txt` inside a subshell recorded a non-existent
# "<start_cwd>/data.txt", missing the real "<start_cwd>/sub/data.txt", an
# extra `sh -c '...'` fork between io_trace.sh's start and the read). Real
# strace -f output on this host verified live, 2026-09-30: a plain
# un-split "<ppid> clone(...) = <cpid>" line -- the resumed-line
# alternative is matched defensively for hosts/loads where strace splits
# the entry and exit across lines.
#
# T085 Round 3 m4 (MINOR, investigated, NOT independently reproduced by
# either this round's reviewer or this fix -- honestly documented per
# §11.4.6 rather than silently claimed closed): on a host/load where
# strace genuinely splits a clone/fork/vfork/clone3 entry and exit across
# TWO lines (the "<... resumed>)= <child>" form above), the CHILD's own
# early syscalls can, under real kernel-scheduling preemption, be logged
# to this file BEFORE its parent's completing "<... resumed>" line --
# i.e. file order is not guaranteed to match "parent's fork call
# completes, then the child's own syscalls begin" whenever strace's own
# entry/exit lines for that ONE clone are split. In that specific
# interleaving, this parser (a strict single top-to-bottom pass) would
# not yet have `cwd_by_pid[child_pid]` populated when it reaches the
# child's own early lines, and `cwd_for()` falls back to `start_cwd` --
# which is only WRONG if the real parent had ALREADY `chdir()`'d away
# from `start_cwd` before forking that child. A fix closing this
# completely would need either a PID-topology pre-pass (cheap, but only
# gives parent-child identity, not a parent's cwd AT THE LOGICAL MOMENT
# of fork, since a parent's own later chdir()s must still resolve in
# this-pid's-own file-order relative to ITS OWN later syscalls) or a
# full two-pass per-pid timeline reconstruction -- both carry real
# regression risk to the ALREADY-correct same-pid-ordering guarantee
# this module depends on elsewhere, for a race NEITHER this fix nor the
# T085 Round 3 review's own investigation could reproduce on this host.
# Left as an honestly-documented, tracked, not-yet-closed edge case
# (never silently claimed fixed) rather than risk a same-day structural
# rewrite of path-resolution ordering with unverified correctness.
_FORK_LINE = re.compile(
    r'^(?:(?P<pid>\d+)\s+)?'
    r'(?:(?:clone|clone3|fork|vfork)\(.*|<\.\.\.\s*(?:clone|clone3|fork|vfork)\s+resumed>.*)'
    r'\)\s*=\s*(?P<child>\d+)\s*$'
)

# The path is the first double-quoted string in the argument list, whether
# or not it's preceded by an AT_FDCWD/dirfd argument.
_PATH_ARG = re.compile(r'"((?:[^"\\]|\\.)*)"')

# STATIC noise this tracer must filter (dynamic linker / libc / kernel-
# pseudo-fs / device / locale paths the traced `sh` + gate-script pair
# opens as ordinary interpreter startup -- these are NEVER part of a
# user's $PATH, so they are not covered by the DYNAMIC $PATH-derived
# filter below and must stay as a static list).
_NOISE_PREFIXES = (
    "/lib/", "/lib64/", "/usr/lib/", "/usr/lib64/",
    "/proc/", "/dev/", "/sys/",
    "/usr/share/locale/",  # I5 fix: confirmed live (glibc locale.alias
                            # probe), was previously masked entirely by
                            # the blanket rc<0 drop this file removes.
)
_NOISE_EXACT = (
    "/etc/ld.so.cache", "/etc/ld.so.preload",
    "/etc/nsswitch.conf", "/etc/localtime",
)


def _path_search_dirs():
    """The live $PATH's own directory components -- I5 fix (1): a failed
    lookup whose containing directory is a literal $PATH entry is
    $PATH-command-search noise (verified live on this host: every
    candidate-directory probe for a nonexistent external command produces
    exactly this shape), never a gate's own declared input. Derived from
    the REAL environment this process inherited (never a hardcoded,
    host-specific directory list -- §11.4.6)."""
    raw = os.environ.get("PATH", "")
    return {d for d in raw.split(os.pathsep) if d}


_PATH_DIRS = _path_search_dirs()


def _is_noise(path, negative):
    if path in _NOISE_EXACT:
        return True
    if any(path.startswith(p) for p in _NOISE_PREFIXES):
        return True
    if negative:
        # $PATH-command-search noise only applies to FAILED lookups (a
        # SUCCESSFUL open under a $PATH directory is a real read of a
        # real command file, e.g. a gate that genuinely execs a tool
        # living in one of those directories -- never filtered).
        parent = os.path.dirname(path)
        if parent in _PATH_DIRS:
            return True
    return False


def _unescape(raw):
    # strace C-escapes its quoted strings (\n, \", \\, \xHH, ...); Python's
    # own string-escape decoding handles the common cases strace emits.
    try:
        return raw.encode("utf-8").decode("unicode_escape").encode(
            "latin-1", errors="ignore"
        ).decode("utf-8", errors="replace")
    except (UnicodeDecodeError, UnicodeEncodeError):
        return raw


# openat() flags implying a WRITE-capable open. A bare O_RDONLY (or its
# absence when strace abbreviates it) is a read. This is a syscall-argument
# classification, not a heuristic on the path string.
_WRITE_FLAGS = ("O_WRONLY", "O_RDWR", "O_CREAT")


def main(argv):
    if len(argv) != 2:
        sys.stderr.write("usage: io_trace_parse.py <strace-log-path>\n")
        return 2

    reads = set()
    writes = set()

    # I5 fix (2): per-PID cwd tracking, seeded from THIS process's own cwd
    # (the same cwd do_trace()'s `sh "$gate_script"` invocation started
    # from -- no chdir happens between io_trace.sh's own start and the
    # strace invocation, so this is the correct starting point for every
    # traced pid, including ones strace never PID-prefixes because only a
    # single process was ever forked).
    start_cwd = os.getcwd()
    cwd_by_pid = {}

    def cwd_for(pid):
        return cwd_by_pid.get(pid, start_cwd)

    with open(argv[1], "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            fm = _FORK_LINE.match(line)
            if fm:
                # T085 Round 2 I-R2-4: seed the child's cwd from its
                # PARENT's CURRENTLY-TRACKED cwd at the moment of fork,
                # never from this process's global start_cwd -- a parent
                # that already chdir'd before forking a child must pass
                # that cwd on, exactly like the real kernel semantics of
                # fork/clone (a child's cwd is inherited, not reset).
                parent_pid = fm.group("pid")
                child_pid = fm.group("child")
                cwd_by_pid[child_pid] = cwd_for(parent_pid)
                continue

            cm = _CHDIR_LINE.match(line)
            if cm:
                try:
                    if int(cm.group("rc")) == 0:
                        raw_path = _unescape(cm.group("path"))
                        pid = cm.group("pid")
                        cur = cwd_for(pid)
                        new_cwd = raw_path if os.path.isabs(raw_path) else os.path.normpath(os.path.join(cur, raw_path))
                        cwd_by_pid[pid] = new_cwd
                except ValueError:
                    pass
                continue

            m = _SYSCALL_LINE.match(line)
            if not m:
                continue
            syscall = m.group("syscall")
            args = m.group("args")
            rc = m.group("rc")
            pid = m.group("pid")

            try:
                rc_int = int(rc)
            except ValueError:
                continue
            negative = rc_int < 0

            path_m = _PATH_ARG.search(args)
            if not path_m:
                continue
            path = _unescape(path_m.group(1))
            if not path:
                continue

            # I5 fix (2): resolve a relative path against this pid's
            # tracked cwd BEFORE noise-filtering/recording, so a read like
            # "rel.txt" after `cd sub` is reported with full context
            # instead of bare (losing which directory it actually names).
            if not os.path.isabs(path):
                path = os.path.normpath(os.path.join(cwd_for(pid), path))

            if _is_noise(path, negative):
                continue

            if syscall == "openat" and any(f in args for f in _WRITE_FLAGS):
                writes.add(path)
            else:
                # stat/newfstatat/lstat are always reads (a gate deciding
                # on file existence -- present OR absent -- has consumed
                # that file as an input); an openat with no write flag
                # present is a read, whether it succeeded or the gate was
                # probing for absence (I5 fix (1): negative rc no longer
                # blanket-dropped).
                reads.add(path)

    result = {"reads": sorted(reads), "writes": sorted(writes)}
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
