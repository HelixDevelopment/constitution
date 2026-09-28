#!/usr/bin/env python3
"""Reference bisector for T056's batch_bisect RED fixtures.

This is NOT gates/batch_bisect.py (the T-C06 implementation task's real
tool, still absent). It is a standalone, from-scratch reference used ONLY
to prove the fixtures under fixtures/batch_bisect/ are non-vacuous BEFORE
any claim is made about what the real (absent) tool should do with them --
the same role dec07_key_ref.py plays for T051 (never informs the real
implementation; written before it exists so it cannot have been
reverse-engineered from it).

Usage:
    bb_ref_bisect.py <batch.json> <base_tree_dir> <patches_dir> <gate.sh>

Prints one JSON object to stdout:
    {"batch_verdict": "PASS"|"FAIL", "per_change": {id: "PASS"|"FAIL", ...},
     "culprits": [id, ...]}

Algorithm (deliberately the simplest correct one -- exhaustive
single-change isolation, not a real log(n) bisection search; correctness
of the REPORTED per-change verdicts is what this reference exists to
prove, not search efficiency):
  1. Build a disposable tree from base_tree_dir, apply EVERY change in the
     batch (copy each change's patch file over base_tree/<target_file> in
     the disposable copy), run gate.sh -> batch_verdict.
  2. If batch_verdict == PASS: every change's per_change verdict is PASS,
     culprits = [].
  3. If batch_verdict == FAIL: for EACH change individually, build a FRESH
     disposable tree from base_tree_dir, apply ONLY that one change, run
     gate.sh -> that change's per_change verdict. culprits = every change
     whose individual verdict is FAIL.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile


def build_tree(base_tree_dir, patches_dir, changes):
    tmp = tempfile.mkdtemp(prefix="bb_ref_bisect_")
    for entry in os.listdir(base_tree_dir):
        shutil.copy2(os.path.join(base_tree_dir, entry), os.path.join(tmp, entry))
    for ch in changes:
        src = os.path.join(patches_dir, ch["patch"])
        dst = os.path.join(tmp, ch["target_file"])
        shutil.copy2(src, dst)
    return tmp


def run_gate(gate_sh, tree_dir):
    proc = subprocess.run([gate_sh, tree_dir], capture_output=True, text=True)
    return "PASS" if proc.returncode == 0 else "FAIL"


def main():
    if len(sys.argv) != 5:
        print("usage: bb_ref_bisect.py <batch.json> <base_tree_dir> <patches_dir> <gate.sh>", file=sys.stderr)
        return 2
    batch_path, base_tree_dir, patches_dir, gate_sh = sys.argv[1:5]
    with open(batch_path) as f:
        batch = json.load(f)
    changes = batch["changes"]

    full_tree = build_tree(base_tree_dir, patches_dir, changes)
    try:
        batch_verdict = run_gate(gate_sh, full_tree)
    finally:
        shutil.rmtree(full_tree, ignore_errors=True)

    per_change = {}
    culprits = []
    if batch_verdict == "PASS":
        for ch in changes:
            per_change[ch["change_id"]] = "PASS"
    else:
        for ch in changes:
            solo_tree = build_tree(base_tree_dir, patches_dir, [ch])
            try:
                v = run_gate(gate_sh, solo_tree)
            finally:
                shutil.rmtree(solo_tree, ignore_errors=True)
            per_change[ch["change_id"]] = v
            if v == "FAIL":
                culprits.append(ch["change_id"])

    print(json.dumps({"batch_verdict": batch_verdict, "per_change": per_change, "culprits": culprits}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
