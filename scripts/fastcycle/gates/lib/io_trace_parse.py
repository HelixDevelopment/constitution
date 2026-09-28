#!/usr/bin/env python3
"""io_trace_parse.py - parses a raw `strace -f -e trace=openat,stat,
newfstatat,lstat,execve -o <log>` log into {"reads":[...],"writes":[...]}.

Invoked ONLY by gates/io_trace.sh's `do_trace()` -- not a standalone CLI
contract of its own. See gates/io_trace.sh's own header comment for the
full design rationale (empirically-verified on this host: `[ -f "$path" ]`
in POSIX sh compiles to `newfstatat`, NEVER plain `stat`, on this glibc/
kernel combination -- confirmed by a real probe before writing this parser,
per §11.4.201(7)(c) "the path is part of the instrument").

Usage: io_trace_parse.py <strace-log-path>
"""
import json
import re
import sys

# Syscalls whose FIRST quoted-string argument is a path this tool observes.
# openat(AT_FDCWD, "<path>", <flags>, ...) = <rc>
# stat("<path>", ...) = <rc>                       (older glibc)
# newfstatat(AT_FDCWD, "<path>", ...) = <rc>        (this host, verified)
# lstat("<path>", ...) = <rc>
_SYSCALL_LINE = re.compile(
    r'(?:^\d+\s+)?(openat|stat|newfstatat|lstat)\((?P<args>.*)\)\s*=\s*(?P<rc>-?\d+)'
)

# The path is the first double-quoted string in the argument list, whether
# or not it's preceded by an AT_FDCWD/dirfd argument.
_PATH_ARG = re.compile(r'"((?:[^"\\]|\\.)*)"')

# Noise this tracer must filter (dynamic linker / libc / kernel-pseudo-fs /
# device / common system-config paths the traced `sh` + gate-script pair
# opens as ordinary interpreter startup, never a gate's own declared input
# -- documented in io_trace.sh's own header, reproduced here as the single
# source of truth the parser actually enforces).
_NOISE_PREFIXES = (
    "/lib/", "/lib64/", "/usr/lib/", "/usr/lib64/",
    "/proc/", "/dev/", "/sys/",
)
_NOISE_EXACT = (
    "/etc/ld.so.cache", "/etc/ld.so.preload",
    "/etc/nsswitch.conf", "/etc/localtime",
)

# openat() flags implying a WRITE-capable open. A bare O_RDONLY (or its
# absence when strace abbreviates it) is a read. This is a syscall-argument
# classification, not a heuristic on the path string.
_WRITE_FLAGS = ("O_WRONLY", "O_RDWR", "O_CREAT")


def _is_noise(path):
    if path in _NOISE_EXACT:
        return True
    return any(path.startswith(p) for p in _NOISE_PREFIXES)


def _unescape(raw):
    # strace C-escapes its quoted strings (\n, \", \\, \xHH, ...); Python's
    # own string-escape decoding handles the common cases strace emits.
    try:
        return raw.encode("utf-8").decode("unicode_escape").encode(
            "latin-1", errors="ignore"
        ).decode("utf-8", errors="replace")
    except (UnicodeDecodeError, UnicodeEncodeError):
        return raw


def main(argv):
    if len(argv) != 2:
        sys.stderr.write("usage: io_trace_parse.py <strace-log-path>\n")
        return 2

    reads = set()
    writes = set()

    with open(argv[1], "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            m = _SYSCALL_LINE.search(line)
            if not m:
                continue
            syscall = m.group(1)
            args = m.group("args")
            rc = m.group("rc")

            # A negative return code (strace prints e.g. "= -1 ENOENT (No
            # such file or directory)") means the syscall FAILED -- the
            # path was PROBED and found absent, never actually read. The
            # dominant source of this in a traced `sh`+gate-script pair is
            # the shell's own $PATH search for external commands (cat, sh):
            # every non-existent PATH-directory candidate produces a failed
            # newfstatat/openat that is NOT a gate input and MUST NOT be
            # reported (this is what the own_dir_only_gate.sh exact-set
            # fixture actually catches -- a naive "every syscall path is a
            # read" parser fails it with dozens of leaked $PATH probes).
            try:
                if int(rc) < 0:
                    continue
            except ValueError:
                continue

            path_m = _PATH_ARG.search(args)
            if not path_m:
                continue
            path = _unescape(path_m.group(1))
            if not path or _is_noise(path):
                continue

            if syscall == "openat" and any(f in args for f in _WRITE_FLAGS):
                writes.add(path)
            else:
                # stat/newfstatat/lstat are always reads (a gate deciding
                # on file existence has consumed that file as an input);
                # an openat with no write flag present is a read.
                reads.add(path)

    result = {"reads": sorted(reads), "writes": sorted(writes)}
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
