#!/usr/bin/env python3
"""Helix Constitution MCP server (stdio, JSON-RPC 2.0) — real, not a mock.

Tools (typed schemas, capability declaration, per-call accounting):

  search_constitution(query, limit?) -> ranked anchor hits
  load_rule(anchor_id)               -> exact rule body + hash verification
  list_anchors(tag?)                 -> id/title pairs
  verify_anchor(anchor_id)           -> stored vs recomputed sha256

It imports the SAME functions the validator tests, so a behavioural PASS is a
statement about this server, not about a parallel implementation.

Transport: newline-delimited JSON-RPC 2.0 on stdin/stdout (MCP stdio framing for
single messages). Accounting is written to stderr as one JSON line per call and,
when --accounting is given, appended to that file.

Usage:
  python3 progressive/mcp_server.py              # serve on stdio
  python3 progressive/mcp_server.py --selftest   # end-to-end tool round-trip
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import validate_behavior as vb  # noqa: E402  (same functions under test)

NAME = "helix-constitution"
VERSION = "1.0.0"
ACCOUNTING: Path | None = None
CALL_SEQ = 0

TOOLS = [
    {
        "name": "search_constitution",
        "description": "Search the constitution anchor catalog. Returns ranked anchor ids with one-line descriptions.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "keywords or an anchor id"},
                "limit": {"type": "integer", "minimum": 1, "maximum": 20, "default": 5},
            },
            "required": ["query"],
        },
    },
    {
        "name": "load_rule",
        "description": "Load the exact text of one constitutional rule by anchor id (e.g. '§11.4.141').",
        "inputSchema": {
            "type": "object",
            "properties": {"anchor_id": {"type": "string"}},
            "required": ["anchor_id"],
        },
    },
    {
        "name": "list_anchors",
        "description": "List anchors, optionally filtered by tag.",
        "inputSchema": {
            "type": "object",
            "properties": {"tag": {"type": "string"}},
        },
    },
    {
        "name": "verify_anchor",
        "description": "Verify a rule file still matches the hash recorded in the catalog.",
        "inputSchema": {
            "type": "object",
            "properties": {"anchor_id": {"type": "string"}},
            "required": ["anchor_id"],
        },
    },
]


def account(tool: str, args: dict, result_chars: int) -> None:
    global CALL_SEQ
    CALL_SEQ += 1
    rec = {"seq": CALL_SEQ, "tool": tool, "arg_keys": sorted(args),
           "result_chars": result_chars,
           # honest proxy: characters of the result the caller must pay for
           "result_token_estimate": (result_chars + 3) // 4}
    line = json.dumps(rec, sort_keys=True)
    print(f"[accounting] {line}", file=sys.stderr)
    if ACCOUNTING is not None:
        ACCOUNTING.parent.mkdir(parents=True, exist_ok=True)
        with ACCOUNTING.open("a", encoding="utf-8") as fh:
            fh.write(line + "\n")


def call(name: str, args: dict) -> dict:
    cat = vb.load_catalog()
    if name == "search_constitution":
        q = str(args.get("query", ""))
        limit = int(args.get("limit", 5) or 5)
        hits = vb.search(cat, q, max(1, min(20, limit)))
        return {"content": [{"type": "text", "text": json.dumps(hits, ensure_ascii=False, indent=1)}]}
    if name == "load_rule":
        aid = str(args.get("anchor_id", ""))
        body = vb.load_rule(cat, aid)
        if body is None:
            return {"isError": True, "content": [{"type": "text", "text": f"unknown anchor: {aid}"}]}
        v = vb.verify_anchor(cat, aid)
        return {"content": [{"type": "text",
                             "text": json.dumps({"anchor_id": aid, "verified": v.get("ok", False),
                                                 "body": body}, ensure_ascii=False)}]}
    if name == "list_anchors":
        tag = args.get("tag")
        items = vb.list_anchors(cat, str(tag) if tag else None)
        return {"content": [{"type": "text", "text": json.dumps(items, ensure_ascii=False)}]}
    if name == "verify_anchor":
        aid = str(args.get("anchor_id", ""))
        return {"content": [{"type": "text", "text": json.dumps(vb.verify_anchor(cat, aid))}]}
    raise KeyError(name)


def handle(req: dict) -> dict | None:
    mid = req.get("id")
    method = req.get("method")
    if method == "initialize":
        res = {"protocolVersion": "2024-11-05",
               "capabilities": {"tools": {"listChanged": False}},
               "serverInfo": {"name": NAME, "version": VERSION}}
    elif method == "notifications/initialized":
        return None
    elif method == "tools/list":
        res = {"tools": TOOLS}
    elif method == "tools/call":
        params = req.get("params") or {}
        name = params.get("name", "")
        args = params.get("arguments") or {}
        try:
            res = call(name, args)
        except KeyError:
            return {"jsonrpc": "2.0", "id": mid,
                    "error": {"code": -32602, "message": f"unknown tool: {name}"}}
        text = json.dumps(res, ensure_ascii=False)
        account(name, args, len(text))
    elif method == "ping":
        res = {}
    else:
        return {"jsonrpc": "2.0", "id": mid,
                "error": {"code": -32601, "message": f"method not found: {method}"}}
    return {"jsonrpc": "2.0", "id": mid, "result": res}


def serve() -> int:
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except Exception:
            print(json.dumps({"jsonrpc": "2.0", "id": None,
                              "error": {"code": -32700, "message": "parse error"}}), flush=True)
            continue
        out = handle(req)
        if out is not None:
            print(json.dumps(out, ensure_ascii=False), flush=True)
    return 0


def selftest() -> int:
    """Round-trip every tool through the real dispatch path."""
    seq = [
        {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}},
        {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
        {"jsonrpc": "2.0", "id": 3, "method": "tools/call",
         "params": {"name": "search_constitution", "arguments": {"query": "token efficiency", "limit": 3}}},
        {"jsonrpc": "2.0", "id": 4, "method": "tools/call",
         "params": {"name": "load_rule", "arguments": {"anchor_id": "§11.4.141"}}},
        {"jsonrpc": "2.0", "id": 5, "method": "tools/call",
         "params": {"name": "list_anchors", "arguments": {"tag": "host-safety"}}},
        {"jsonrpc": "2.0", "id": 6, "method": "tools/call",
         "params": {"name": "verify_anchor", "arguments": {"anchor_id": "§11.4.141"}}},
        {"jsonrpc": "2.0", "id": 7, "method": "tools/call",
         "params": {"name": "no_such_tool", "arguments": {}}},
    ]
    ok = True
    for req in seq:
        out = handle(req)
        if out is None:
            continue
        if "error" in out:
            expected = req["id"] == 7
            print(f"{'PASS' if expected else 'FAIL'}: id={req['id']} → error {out['error']['message']}")
            ok = ok and expected
            continue
        text = json.dumps(out["result"])
        print(f"PASS: id={req['id']} → {len(text)} chars")
    # semantic assertions, not just "no crash"
    r3 = json.loads(handle(seq[2])["result"]["content"][0]["text"])
    r4 = json.loads(handle(seq[3])["result"]["content"][0]["text"])
    checks = [
        ("search returns §11.4.141 first", bool(r3) and r3[0]["id"] == "§11.4.141"),
        ("load_rule returns the verified body", r4["verified"] is True and "§11.4.141" in r4["body"]),
    ]
    for label, good in checks:
        print(f"{'PASS' if good else 'FAIL'}: {label}")
        ok = ok and good
    print(f"SELFTEST: {'PASS' if ok else 'FAIL'}")
    return 0 if ok else 1


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        sys.exit(selftest())
    if "--accounting" in sys.argv:
        ACCOUNTING = Path(sys.argv[sys.argv.index("--accounting") + 1])
    sys.exit(serve())
