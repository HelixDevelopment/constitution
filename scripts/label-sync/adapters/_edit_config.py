#!/usr/bin/env python3
"""scripts/label-sync/adapters/_edit_config.py

Purpose : Config editor behind install_adapters.sh (called once per agent).
          Idempotently adds/removes the label-sync adapter wiring in ONE agent
          config file, validating BEFORE and AFTER (it refuses to touch a file it
          cannot parse and refuses to write a result it cannot parse), never
          clobbering existing user settings, always backing up first.
Usage   : _edit_config.py --kind KIND --file PATH --adapters-dir DIR
                          [--mode dry-run|apply|remove-dry|remove]
          KIND = kimi | opencode | crush | aider | codex | gemini | qwen
Inputs  : the config file (may be absent). JSON via json, TOML via tomllib,
          YAML via PyYAML (aider only; absent PyYAML => exit 2, never a guess).
Outputs : ONE status line on stdout:
            <kind> <status> <path> [detail]
          status = created|updated|unchanged|removed|absent|conflict|invalid|skip
Exit    : 0 ok (created/updated/unchanged/removed/absent/skip)
          1 refused: invalid existing file or conflicting user setting (file
            untouched)
          2 cannot determine (missing python module, unreadable path, bad usage)
Side-effects: apply/remove only: backup `<file>.label-sync.bak.<UTCstamp>` — only
          when the file exists, its content changes AND no existing backup of
          that file already holds the same bytes (re-applying never piles up
          copies; configs may hold API keys). Backups are created 0600 FROM
          BIRTH (O_EXCL, mode passed to open: no umask window). Then atomic write
          (temp file in the same directory + fsync + rename). A symlinked config
          is edited at its target (the symlink survives). Modes: new files 0600,
          existing mode preserved. dry-run/remove-dry never write.
          IDEMPOTENT + EXACT ROLLBACK (review-2 finding A): a second --apply is
          byte-identical; --remove restores the ORIGINAL bytes — TOML/YAML via
          the managed block (which records the separator it inserted), JSON
          via the backup whose parsed content equals the un-wired result; a
          config the installer CREATED is deleted again by --remove.
          Paths in hook commands are shell-quoted; an adapters dir containing
          a shell metacharacter ($, backquote, double quote, backslash, newline)
          is refused (exit 2).
Deps    : python3 >= 3.11 (tomllib).
Cross-refs: §11.4.228(D)(5) idempotent + dry-run-capable, §11.4.18, §11.4.10,
          docs/label-sync/ADAPTERS.md.
Classification: universal (§11.4.17).
"""
import argparse
import datetime
import json
import os
import pathlib
import re
import shlex
import sys
import tempfile

try:
    import tomllib
except ImportError:  # python < 3.11
    print("cannot-determine: python3 >= 3.11 (tomllib) required", file=sys.stderr)
    sys.exit(2)

BEGIN = "# >>> label-sync adapters (constitution §11.4.228) — managed block, do not edit >>>"
END = "# <<< label-sync adapters <<<"
SEP = "# label-sync-sep: pre={pre} post={post}"
SEP_RE = re.compile(r"# label-sync-sep: pre=(\d+) post=(\d+)\n")
UNSAFE = set('$`"\\\n')
EVENTS_KIMI = ["SessionStart", "UserPromptSubmit", "Stop", "SessionEnd", "SubagentStart", "SubagentStop"]
OPENCODE_SCHEMA = "https://opencode.ai/config.json"
EVENTS_GEMINI = ["SessionStart", "BeforeAgent", "AfterAgent", "SessionEnd"]


class Refused(Exception):
    def __init__(self, status, detail):
        super().__init__(detail)
        self.status, self.detail = status, detail


def out(kind, status, path, detail=""):
    print(f"{kind} {status} {path}" + (f" {detail}" if detail else ""))


def tq(s):  # TOML basic string
    return json.dumps(s, ensure_ascii=False)


def read_text(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return f.read()
    except FileNotFoundError:
        return None


# ── JSON kinds ───────────────────────────────────────────────────────────────
def load_json(path, text):
    if text is None or text.strip() == "":
        return {}
    try:
        d = json.loads(text)
    except json.JSONDecodeError as e:
        raise Refused("invalid", f"existing file is not valid JSON ({e.msg} at line {e.lineno}); refusing to touch it")
    if not isinstance(d, dict):
        raise Refused("invalid", "existing JSON is not an object; refusing to touch it")
    return d


def dump_json(d):
    return json.dumps(d, indent=2, ensure_ascii=False) + "\n"


def shcmd(*argv):  # a shell command string; every word quoted (paths may hold spaces)
    return " ".join(shlex.quote(a) for a in argv)


def edit_opencode(d, adir, remove):
    url = pathlib.Path(adir, "opencode", "label-sync.mjs").as_uri()  # percent-encodes spaces
    plugins = d.get("plugin", [])
    if not isinstance(plugins, list):
        raise Refused("conflict", '"plugin" exists but is not an array; refusing')
    def managed(x):
        s = x[0] if isinstance(x, list) and x else x
        return isinstance(s, str) and "/adapters/opencode/label-sync." in s
    kept = [x for x in plugins if not managed(x)]
    if remove:
        if kept:
            d["plugin"] = kept
        else:
            d.pop("plugin", None)
        return d
    d.setdefault("$schema", OPENCODE_SCHEMA)
    d["plugin"] = kept + [url]
    return d


def edit_crush(d, adir, remove):
    cmd = shcmd("bash", os.path.join(adir, "crush", "crush-hook.sh"))
    hooks = d.get("hooks", {})
    if not isinstance(hooks, dict):
        raise Refused("conflict", '"hooks" exists but is not an object; refusing')
    pre = hooks.get("PreToolUse", [])
    if not isinstance(pre, list):
        raise Refused("conflict", '"hooks.PreToolUse" exists but is not an array; refusing')
    kept = [h for h in pre if not (isinstance(h, dict) and "adapters/crush/crush-hook.sh" in str(h.get("command", "")))]
    if not remove:
        kept.append({"name": "label-sync", "command": cmd, "timeout": 10})
    if kept:
        hooks["PreToolUse"] = kept
    else:
        hooks.pop("PreToolUse", None)
    if hooks:
        d["hooks"] = hooks
    else:
        d.pop("hooks", None)
    return d


def edit_gemini_like(kind):
    script = {"gemini": "gemini/gemini-hook.sh", "qwen": "qwen/qwen-hook.sh"}[kind]
    def fn(d, adir, remove):
        cmd = shcmd("bash", os.path.join(adir, script))
        hooks = d.get("hooks", {})
        if not isinstance(hooks, dict):
            raise Refused("conflict", '"hooks" exists but is not an object; refusing')
        for ev in EVENTS_GEMINI:
            lst = hooks.get(ev, [])
            if not isinstance(lst, list):
                raise Refused("conflict", f'"hooks.{ev}" exists but is not an array; refusing')
            def ours(g):
                return isinstance(g, dict) and any(
                    isinstance(h, dict) and ("adapters/" + script) in str(h.get("command", ""))
                    for h in (g.get("hooks") or []) if isinstance(h, dict))
            kept = [g for g in lst if not ours(g)]
            if not remove:
                kept.append({"matcher": "*", "hooks": [{"type": "command", "name": "label-sync", "command": cmd, "timeout": 10000}]})
            if kept:
                hooks[ev] = kept
            else:
                hooks.pop(ev, None)
        if hooks:
            d["hooks"] = hooks
        else:
            d.pop("hooks", None)
        return d
    return fn


# ── managed-text kinds (TOML / YAML) ─────────────────────────────────────────
BLOCK_RE = re.compile(re.escape(BEGIN) + r"\n(?:" + SEP_RE.pattern + r")?.*?" + re.escape(END) + r"\n?", re.S)


def strip_block(text):
    """Remove the managed block AND exactly the separator newlines it recorded
    (pre = inserted before it, post = inserted after it), so the remainder is
    byte-identical to the file before the block was added."""
    m = BLOCK_RE.search(text)
    if not m:
        return text
    sep = SEP_RE.search(m.group(0))
    pre, post = (int(sep.group(1)), int(sep.group(2))) if sep else (0, 0)
    a, b = m.start(), m.end()
    if pre and text[a - pre:a] == "\n" * pre:   # MUT:sepstrip
        a -= pre
    if post and text[b:b + post] == "\n" * post:
        b += post
    return strip_block(text[:a] + text[b:])


def block_kimi(adir, pre=0, post=0):
    cmd = shcmd("bash", os.path.join(adir, "kimi", "kimi-hook.sh"))
    lines = [BEGIN, SEP.format(pre=pre, post=post)]
    for ev in EVENTS_KIMI:
        lines += ["[[hooks]]", f"event = {tq(ev)}", f"command = {tq(cmd)}", "timeout = 10", ""]
    lines.append(END)
    return "\n".join(lines) + "\n"


def block_codex(adir, pre=0, post=0):
    cmd = os.path.join(adir, "codex", "codex-notify.sh")  # an argv array: no shell, no quoting
    return f'{BEGIN}\n{SEP.format(pre=pre, post=post)}\nnotify = ["bash", {tq(cmd)}]\n{END}\n'


def block_aider(adir, remainder, pre=0, post=0):
    cmd = shcmd("bash", os.path.join(adir, "aider", "aider-notify.sh"))
    lines = [BEGIN, SEP.format(pre=pre, post=post)]
    if not re.search(r"(?m)^notifications\s*:", remainder):
        lines.append("notifications: true")
    lines.append(f"notifications-command: {json.dumps(cmd)}")
    lines.append(END)
    return "\n".join(lines) + "\n"


def parse_toml(text, what):
    try:
        return tomllib.loads(text)
    except tomllib.TOMLDecodeError as e:
        raise Refused("invalid", f"{what} is not valid TOML ({e}); refusing")


def parse_yaml(text, what):
    try:
        import yaml
    except ImportError:
        print("cannot-determine: PyYAML required to validate aider YAML", file=sys.stderr)
        sys.exit(2)
    try:
        d = yaml.safe_load(text) if text.strip() else {}
    except yaml.YAMLError as e:
        raise Refused("invalid", f"{what} is not valid YAML ({str(e).splitlines()[0]}); refusing")
    if d is None:
        d = {}
    if not isinstance(d, dict):
        raise Refused("invalid", f"{what} YAML is not a mapping; refusing")
    return d


def edit_text(kind, text, adir, remove):
    cur = text or ""
    remainder = strip_block(cur)
    if kind in ("kimi", "codex"):
        base = parse_toml(remainder, "existing file")
        if kind == "codex" and "notify" in base:
            raise Refused("conflict", 'a top-level "notify" is already configured outside the managed block; refusing to overwrite it')
    else:
        base = parse_yaml(remainder, "existing file")
        if "notifications-command" in base or "notifications_command" in base:
            raise Refused("conflict", '"notifications-command" is already configured outside the managed block; refusing to overwrite it')
    if remove:
        new = remainder
    else:
        # the separator newlines added around the block are RECORDED in it, so
        # strip_block() takes back exactly what was added (exact rollback, and
        # a re-apply reproduces the same bytes: idempotent)
        nl = 0 if remainder == "" or remainder.endswith("\n") else 1
        if kind == "kimi":
            pre = nl + (1 if remainder.strip() else 0)
            new = remainder + "\n" * pre + block_kimi(adir, pre, 0)
        elif kind == "codex":
            post = 1 if remainder.strip() else 0  # top-level key: MUST precede every [table]
            new = block_codex(adir, 0, post) + "\n" * post + remainder
        else:
            new = remainder + "\n" * nl + block_aider(adir, remainder, nl, 0)
    # validate the RESULT
    if kind in ("kimi", "codex"):
        d = parse_toml(new, "resulting file")
        if not remove and kind == "codex" and d.get("notify", [None, None])[0:1] != ["bash"]:
            raise Refused("invalid", "internal: codex notify did not land at top level")
        if not remove and kind == "kimi" and len(d.get("hooks", [])) < len(EVENTS_KIMI):
            raise Refused("invalid", "internal: kimi hooks missing from result")
    else:
        d = parse_yaml(new, "resulting file")
        if not remove and "notifications-command" not in d:
            raise Refused("invalid", "internal: aider notifications-command missing from result")
    return new


# ── driver ───────────────────────────────────────────────────────────────────
def atomic_write(path, data, mode):
    d = os.path.dirname(path) or "."
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".label-sync.", dir=d)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def backups_of(path):
    d, b = os.path.split(path)
    pre = b + ".label-sync.bak."
    try:
        return sorted(os.path.join(d or ".", n) for n in os.listdir(d or ".") if n.startswith(pre))
    except OSError:
        return []


def write_backup(path, text):
    """0600 FROM BIRTH, never a second copy of identical bytes."""
    for b in backups_of(path):
        try:
            if read_text(b) == text:
                return b  # MUT:bakdedupe
        except OSError:
            pass
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    for n in range(100):
        bak = f"{path}.label-sync.bak.{stamp}" + (f".{n}" if n else "")
        try:
            # created 0600 (minus the umask: never wider) — no chmod-after-write window
            fd = os.open(bak, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)  # MUT:bakmode
        except FileExistsError:
            continue
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
            f.flush()
            os.fsync(f.fileno())
        return bak
    raise OSError("no free backup name")


def json_exact_restore(path, new_text):
    """For a JSON --remove: the bytes of the newest backup whose parsed content
    equals the un-wired result (the user's exact original formatting), else None."""
    try:
        want = json.loads(new_text)
    except json.JSONDecodeError:
        return None
    alt = None  # the un-wired result minus a "$schema" the installer itself added (opencode)
    if isinstance(want, dict) and want.get("$schema") == OPENCODE_SCHEMA:
        alt = {k: v for k, v in want.items() if k != "$schema"}
    for b in reversed(backups_of(path)):
        t = read_text(b)
        if t is None:
            continue
        try:
            got = json.loads(t) if t.strip() else {}
        except json.JSONDecodeError:
            continue
        if got == want or (alt is not None and "$schema" not in got and got == alt):
            return t
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--kind", required=True, choices=["kimi", "opencode", "crush", "aider", "codex", "gemini", "qwen"])
    ap.add_argument("--file", required=True)
    ap.add_argument("--adapters-dir", required=True)
    ap.add_argument("--mode", default="dry-run", choices=["dry-run", "apply", "remove-dry", "remove"])
    a = ap.parse_args()
    kind, adir = a.kind, os.path.abspath(a.adapters_dir)
    if UNSAFE & set(adir):  # MUT:unsafe
        out(kind, "skip", a.file, "unsafe adapters dir (contains $ ` \" \\ or a newline that a hook command would interpret): refused")
        return 2
    remove = a.mode.startswith("remove")
    write = a.mode in ("apply", "remove")
    path = a.file
    if os.path.islink(path):
        path = os.path.realpath(path)
    try:
        text = read_text(path)
    except OSError as e:
        out(kind, "skip", a.file, f"unreadable: {e}")
        return 2
    delete = False
    try:
        if kind in ("opencode", "crush", "gemini", "qwen"):
            d = load_json(path, text)
            fn = {"opencode": edit_opencode, "crush": edit_crush}.get(kind) or edit_gemini_like(kind)
            d = fn(d, adir, remove)
            new = dump_json(d)
            json.loads(new)  # validate the result
            if remove and text is None:
                out(kind, "absent", a.file)
                return 0
            if remove and new != text:
                orig = json_exact_restore(path, new)
                if orig is not None:
                    new = orig  # the user's exact original bytes
                elif not backups_of(path):
                    # no backup => the installer CREATED this file: an un-wired
                    # result equal to what remains from an empty config is deleted
                    empty = dump_json(fn(fn({}, adir, False), adir, True))
                    delete = (new == empty)
        else:
            new = edit_text(kind, text, adir, remove)
            if remove and text is not None and new == "" and not backups_of(path):
                delete = True  # created by the installer: rollback = absent again
    except Refused as r:
        out(kind, r.status, a.file, r.detail)
        return 1
    if remove and text is None:
        out(kind, "absent", a.file)
        return 0
    if text is not None and new == text and not delete:
        out(kind, "unchanged", a.file)
        return 0
    status = ("removed" if remove else ("created" if text is None else "updated"))
    if not write:
        out(kind, "would-" + status, a.file)
        return 0
    try:
        mode = 0o600
        if text is not None:
            mode = os.stat(path).st_mode & 0o7777
            if not delete:  # a file the installer created holds nothing of the user's
                write_backup(path, text)
        if delete:
            os.unlink(path)
        else:
            atomic_write(path, new, mode)
    except OSError as e:
        out(kind, "skip", a.file, f"write failed: {e}")
        return 2
    out(kind, status, a.file)
    return 0


if __name__ == "__main__":
    sys.exit(main())
