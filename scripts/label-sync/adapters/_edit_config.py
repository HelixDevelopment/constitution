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
Side-effects: apply/remove only: backup `<file>.label-sync.bak.<UTCstamp>` (only
          when the file exists and its content changes), then atomic write
          (temp file in the same directory + fsync + rename). A symlinked config
          is edited at its target (the symlink survives). Modes: new files 0600,
          existing mode preserved. dry-run/remove-dry never write.
Deps    : python3 >= 3.11 (tomllib).
Cross-refs: §11.4.228(D)(5) idempotent + dry-run-capable, §11.4.18, §11.4.10,
          docs/label-sync/ADAPTERS.md.
Classification: universal (§11.4.17).
"""
import argparse
import datetime
import json
import os
import re
import sys
import tempfile

try:
    import tomllib
except ImportError:  # python < 3.11
    print("cannot-determine: python3 >= 3.11 (tomllib) required", file=sys.stderr)
    sys.exit(2)

BEGIN = "# >>> label-sync adapters (constitution §11.4.228) — managed block, do not edit >>>"
END = "# <<< label-sync adapters <<<"
EVENTS_KIMI = ["SessionStart", "UserPromptSubmit", "Stop", "SessionEnd", "SubagentStart", "SubagentStop"]
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


def edit_opencode(d, adir, remove):
    url = "file://" + os.path.join(adir, "opencode", "label-sync.mjs")
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
    d.setdefault("$schema", "https://opencode.ai/config.json")
    d["plugin"] = kept + [url]
    return d


def edit_crush(d, adir, remove):
    cmd = "bash " + os.path.join(adir, "crush", "crush-hook.sh")
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
        cmd = "bash " + os.path.join(adir, script)
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
BLOCK_RE = re.compile(re.escape(BEGIN) + r".*?" + re.escape(END) + r"\n?", re.S)


def strip_block(text):
    return BLOCK_RE.sub("", text)


def block_kimi(adir):
    cmd = "bash " + os.path.join(adir, "kimi", "kimi-hook.sh")
    lines = [BEGIN]
    for ev in EVENTS_KIMI:
        lines += ["[[hooks]]", f"event = {tq(ev)}", f"command = {tq(cmd)}", "timeout = 10", ""]
    lines.append(END)
    return "\n".join(lines) + "\n"


def block_codex(adir):
    cmd = os.path.join(adir, "codex", "codex-notify.sh")
    return f'{BEGIN}\nnotify = ["bash", {tq(cmd)}]\n{END}\n'


def block_aider(adir, remainder):
    cmd = "bash " + os.path.join(adir, "aider", "aider-notify.sh")
    lines = [BEGIN]
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
        if kind == "kimi":
            blk = block_kimi(adir)
            new = remainder + ("" if remainder == "" or remainder.endswith("\n") else "\n") + ("\n" if remainder.strip() else "") + blk
        elif kind == "codex":
            blk = block_codex(adir)  # top-level key: MUST precede every [table]
            new = blk + ("\n" if remainder.strip() else "") + remainder
        else:
            blk = block_aider(adir, remainder)
            new = remainder + ("" if remainder == "" or remainder.endswith("\n") else "\n") + blk
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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--kind", required=True, choices=["kimi", "opencode", "crush", "aider", "codex", "gemini", "qwen"])
    ap.add_argument("--file", required=True)
    ap.add_argument("--adapters-dir", required=True)
    ap.add_argument("--mode", default="dry-run", choices=["dry-run", "apply", "remove-dry", "remove"])
    a = ap.parse_args()
    kind, adir = a.kind, os.path.abspath(a.adapters_dir)
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
        else:
            new = edit_text(kind, text, adir, remove)
    except Refused as r:
        out(kind, r.status, a.file, r.detail)
        return 1
    if remove and text is None:
        out(kind, "absent", a.file)
        return 0
    if text is not None and new == text:
        out(kind, "unchanged", a.file)
        return 0
    if remove and text is not None and kind in ("opencode", "crush", "gemini", "qwen") and new.strip() in ("{}",):
        pass  # leave an empty-object config rather than deleting a user file
    status = ("removed" if remove else ("created" if text is None else "updated"))
    if not write:
        out(kind, "would-" + status, a.file)
        return 0
    try:
        mode = 0o600
        if text is not None:
            mode = os.stat(path).st_mode & 0o7777
            stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
            bak = f"{path}.label-sync.bak.{stamp}"
            with open(bak, "w", encoding="utf-8") as f:
                f.write(text)
            os.chmod(bak, mode)
        atomic_write(path, new, mode)
    except OSError as e:
        out(kind, "skip", a.file, f"write failed: {e}")
        return 2
    out(kind, status, a.file)
    return 0


if __name__ == "__main__":
    sys.exit(main())
