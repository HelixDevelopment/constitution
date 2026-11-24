"""Token lookup by variable NAME (anchor 11.4.300; credentials rules of scripts/forge/lib/credentials.sh): process environment first,
then the operator keys file PARSED (never sourced), refused unless a regular non-symlink file owned by this user with no group/other bits.
A value is returned to the caller only; nothing here prints, logs or formats a value."""
import os
import re
import stat

_VALID = re.compile(r"^[A-Za-z0-9._~+/=-]{8,400}$")
_ASSIGN = re.compile(r"""^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(?:"([^"]*)"|'([^']*)'|([^\s#]*))""")
_PLACEHOLDER = ("changeme", "change-me", "replace-me", "placeholder", "your-", "your_", "xxx", "dummy", "example")


def _placeholder(v):
    l = v.lower()
    return len(v) < 8 or any(p in l for p in _PLACEHOLDER) or len(set(v)) == 1


def _file_safe(path):
    try:
        st = os.lstat(path)
    except OSError:
        return False
    return stat.S_ISREG(st.st_mode) and st.st_uid == os.getuid() and (st.st_mode & 0o077) == 0


def _keys_file_value(path, name):
    if not _file_safe(path):
        return None
    val = None
    with open(path, errors="replace") as f:
        for line in f:
            m = _ASSIGN.match(line)
            if m and m.group(1) == name:
                val = next((g for g in m.groups()[1:] if g is not None), None)
    return val


def resolve(names, env=None, keys_file=None):
    """Return (state, name, value): state in found | absent | invalid. value is None unless found."""
    env = os.environ if env is None else env
    keys_file = keys_file or os.environ.get("FORGE_KEYS_FILE") or os.path.expanduser("~/api_keys.sh")
    for source in ("env", "file"):
        for n in names:
            v = env.get(n) if source == "env" else _keys_file_value(keys_file, n)
            if not v or _placeholder(v):
                continue
            if not _VALID.match(v):
                return ("invalid", n, None)
            return ("found", n, v)
    return ("absent", None, None)
