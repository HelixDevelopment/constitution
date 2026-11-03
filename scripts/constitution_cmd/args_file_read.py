#!/usr/bin/env python3
"""scripts/constitution_cmd/args_file_read.py -- safe one-shot reader for `constitution_cmd.sh --args-file`.

Usage: args_file_read.py PATH            (prints the file text on stdout, then deletes the file)
Exit codes: 0 ok; 2 rejected (reason on stderr); never reads or deletes anything but the verified file.

Accepted PATH shape, checked LEXICALLY first (no resolution yet):
    <DIR>/constitution_args_<id>.txt     DIR in {"/tmp", $TMPDIR (absolute, canonical: no ".." / "." / empty segment, realpath(TMPDIR)==TMPDIR, so no symlink in it)}
    <id> = [a-z0-9]{8,64}                no other "/" anywhere after DIR, no "..".
Then: realpath(DIR) must be a real directory; the file is opened RELATIVE to a directory fd with
O_NOFOLLOW|O_NONBLOCK (a symlink leaf or a symlinked middle component cannot be followed); the
opened descriptor must be a regular file, st_nlink == 1, owned by the effective uid, size <= MAX_BYTES;
the directory entry (lstat via the dir fd) must be the very same inode (device+inode) as the open
descriptor; only then it is read and unlinked THROUGH THE DIR FD. A rename-swap between the identity
check and the unlink is narrowed, not closed (documented limit): it can only remove a file named
constitution_args_<id>.txt inside the allowed temp dir, never anything else.
Cross-references: section 11.4.287, 11.4.10 (no credential printed).
"""
import os
import re
import stat
import sys

MAX_BYTES = 8001
ID_RE = re.compile(r"constitution_args_[a-z0-9]{8,64}\.txt\Z")


def reject(msg):
    sys.stderr.write("constitution: --args-file %s\n" % msg)
    sys.exit(2)


def allowed_dirs(env_tmpdir):
    out = ["/tmp"]
    if env_tmpdir:
        t = env_tmpdir[:-1] if env_tmpdir.endswith("/") and len(env_tmpdir) > 1 else env_tmpdir
        # Only a canonical absolute TMPDIR is accepted: no "." / ".." / empty segment, and no symlink
        # anywhere in it (realpath(TMPDIR) must equal TMPDIR). Anything else is silently not allowed,
        # so a path under it is rejected by the "directory must be exactly" rule.
        segs = t.split("/")[1:]
        if (t.startswith("/") and "\0" not in t and t not in out
                and not any(x in ("", ".", "..") for x in segs)
                and os.path.realpath(t) == t):
            out.append(t)
    return out


def read_and_consume(path, dirs, euid=None, after_open=None):
    """Return the file text (str). Raises SystemExit(2) via reject() on any violation.

    after_open: optional callable(dir_fd, name) invoked between open and identity check. It is a
    code-level parameter for in-process tests only (main() never passes one); there is no
    environment-controlled behaviour in this module."""
    if euid is None:
        euid = os.geteuid()
    if not isinstance(path, str) or "\0" in path:
        reject("path must be a plain string")
    parent, sep, name = path.rpartition("/")
    if not sep or not ID_RE.match(name):
        reject("path must be <tmpdir>/constitution_args_<id>.txt with id [a-z0-9]{8,64}")
    if parent not in dirs:
        reject("directory must be exactly /tmp or $TMPDIR (no extra path components, no '..')")
    try:
        real_parent = os.path.realpath(parent)
        dfd = os.open(real_parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    except OSError:
        reject("allowed directory is not usable")
    try:
        try:
            fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC, dir_fd=dfd)
        except OSError:
            reject("file missing, unreadable or a symlink")
        try:
            st = os.fstat(fd)
            if not stat.S_ISREG(st.st_mode):
                reject("must be a regular file")
            if st.st_nlink != 1:
                reject("must have exactly one hard link")
            if st.st_uid != euid:
                reject("must be owned by the calling user")
            if st.st_size > MAX_BYTES:
                reject("file too large (more than 8001 bytes)")
            if after_open is not None:
                after_open(dfd, name)
            try:
                ls = os.stat(name, dir_fd=dfd, follow_symlinks=False)
            except OSError:
                reject("file vanished")
            if (ls.st_dev, ls.st_ino) != (st.st_dev, st.st_ino):
                reject("file identity changed while opening")
            data = os.read(fd, MAX_BYTES + 1)
            os.unlink(name, dir_fd=dfd)
        finally:
            os.close(fd)
    finally:
        os.close(dfd)
    if b"\0" in data:
        reject("file contains a NUL byte")
    return data.decode("utf-8", "surrogateescape")


def main(argv):
    if len(argv) != 2:
        reject("needs exactly one path")
    text = read_and_consume(argv[1], allowed_dirs(os.environ.get("TMPDIR", "")))
    sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
