#!/usr/bin/env python3
"""credscan_hook.py - Claude Code hook (UserPromptSubmit / PostToolUse / SessionStart).
Counts-only. Never echoes a value. Fails OPEN (exit 0) on any error.
CREDSCAN_HOOK_MODE=block (default) | warn.  block applies to UserPromptSubmit and only
for high-confidence classes; everything else warns via additionalContext.
HONEST LIMIT: the harness cannot redact what is persisted; a block stops the prompt
reaching the model but the text may still reach local transcript/history (see docs)."""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    import credscan
    ev = json.load(sys.stdin)
    name = ev.get("hook_event_name", "")
    if name == "UserPromptSubmit":
        text = ev.get("prompt", "")
    elif name == "PostToolUse":
        text = json.dumps(ev.get("tool_response", ""), ensure_ascii=False)
    else:
        sys.exit(0)
    c = credscan.scan_text(text.replace("\\n", "\n"))
    if not c:
        sys.exit(0)
    summ = ", ".join("%s=%d" % kv for kv in sorted(c.items()))
    mode = os.environ.get("CREDSCAN_HOOK_MODE", "block")
    if name == "UserPromptSubmit" and mode == "block" and set(c) & credscan.HIGH_CONF:
        print(json.dumps({"decision": "block",
            "reason": "Credential-shaped value(s) detected in prompt (%s). Prompt not sent. Use an env var or file reference; rotate the credential if it was real." % summ,
            "hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "suppressOriginalPrompt": True}}))
    else:
        print(json.dumps({"hookSpecificOutput": {"hookEventName": name,
            "additionalContext": "credscan: credential-shaped value(s) present (%s). Do not repeat them; the local transcript now holds them, so rotate if real." % summ}}))
except SystemExit:
    raise
except Exception:
    sys.exit(0)
