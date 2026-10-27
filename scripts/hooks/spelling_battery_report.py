#!/usr/bin/env python3
"""spelling_battery_report.py - replay the committed option-SPELLING battery against the destructive-path guard
and print one line per spelling with the real exit code, plus totals (machine evidence for the CHANGELOG numbers).

Purpose : the SPELLINGS list lives in test_guard_bypasses.py (the review-round-2 F3 class). This script reads that
          list (ast, no import side effects), runs each spelling through guard-destructive-paths.py twice (once
          wrapping a destructive command, once wrapping `echo hi`) and reports block / allow counts.
Usage   : spelling_battery_report.py            exit 0 when every destructive row is blocked (rc 2) and every
          benign row is allowed (rc 0); exit 1 otherwise. Output is deterministic (no timestamps).
Side effects: none (the guard only reads the payload). Tests: its totals are asserted equal to the bypass suite's.
"""
import ast, json, os, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
GUARD = os.path.join(HERE, "guard-destructive-paths.py")
tree = ast.parse(open(os.path.join(HERE, "test_guard_bypasses.py"), encoding="utf-8").read())
spell = None
for node in tree.body:
    if isinstance(node, ast.Assign) and getattr(node.targets[0], "id", "") == "SPELLINGS":
        spell = ast.literal_eval(node.value)
if not spell:
    print("BLIND: SPELLINGS not found"); sys.exit(2)
D3 = "%s %s %s" % ("r" + "m", "-r" + "f", "/ho" + "me")

def rc(cmd):
    p = json.dumps({"tool_name": "Bash", "tool_input": {"command": cmd}, "cwd": "/home/tester/Projects/work"})
    return subprocess.run([sys.executable, "-I", GUARD], input=p, capture_output=True, text=True).returncode

blocked = allowed = 0
bad = []
print("# spelling | destructive rc (want 2) | benign rc (want 0)")
for sp in spell:
    a, b = rc(sp % D3), rc(sp % "echo hi")
    blocked += a == 2
    allowed += b == 0
    if a != 2 or b != 0:
        bad.append(sp)
    print("%s | %d | %d" % (sp.replace("%s", "<S>"), a, b))
print("TOTAL spellings=%d destructive_blocked=%d benign_allowed=%d violations=%d" % (len(spell), blocked, allowed, len(bad)))
sys.exit(1 if bad else 0)
