#!/usr/bin/env python3
# ============================================================================
# fk_index_patch.py — build a private, version-keyed, PATCHED CodeGraph runner
# (constitution §11.4.78 / §11.4.80)
# ============================================================================
#
# Purpose
#   Creates a PRIVATE COPY of the CodeGraph platform package with a set of
#   composable, individually fail-closed patches applied. The shared global
#   install is NEVER modified (§11.4.74: consume, don't fork in place); the
#   private copy is disposable and regenerable (§11.4.30 / §11.4.77): delete the
#   directory and re-run. Patches (runner_patches/, applied in REGISTRY order):
#     fkidx1    keep the FK child-key indexes through the bulk-index windows so
#               `INSERT OR REPLACE INTO nodes` under foreign_keys=ON never
#               degrades into full cascade scans (oracle: fk_cascade_probe.py).
#               Keep-set DERIVED from the target's own schema.sql.
#     lockfix1  .codegraph/codegraph.lock is stale ONLY when its PID is not a
#               live codegraph process (/proc/<pid>/cmdline); the stock 2-min
#               age override that deletes a LIVE lock is removed.
#     datafrag1 raw number-fragment C headers (>=200 KiB, first significant
#               char a digit) and NUL-containing source files are stored as
#               skip rows (0 nodes, error code data_fragment_skipped /
#               binary_content_skipped) instead of timing out the parse pool.
#   Adding a future patch = one module in runner_patches/ + one REGISTRY entry.
#
# FAIL-CLOSED / upgrade behaviour
#   Every anchor a patch edits is asserted to occur EXACTLY once; any mismatch
#   (e.g. after a codegraph upgrade rewrote the code) exits 2 with the patch id
#   and anchor named, and NO runner is produced — never a silent mis-patch or a
#   silent drop of a fix. A patch whose hazard is POSITIVELY proven absent
#   upstream reports NOT_NEEDED and is skipped (its id leaves the runner key).
#   Only when EVERY selected patch is NOT_NEEDED does the tool exit 3.
#
# Usage
#   fk_index_patch.py [--src <platform package dir>] [--dst <runner dir>]
#                     [--patches id,id,...] [--force] [--print-bin]
#                     [--list-patches]
#   --src      defaults to the globally installed platform package (npm root -g)
#   --patches  subset of the registry (default: all). `--patches fkidx1`
#              reproduces the original single-patch runner (key <ver>-fkidx1).
#   --dst      defaults to ${HELIX_CODEGRAPH_RUNNER_DIR:-$HOME/.cache/helix/codegraph_runner}/<runner key>
#              where <runner key> = <version>-<applied ids joined by '-'>,
#              e.g. 1.6.0-fkidx1-lockfix1-datafrag1
#   --force    rebuild even when a valid receipt exists
#   --print-bin  print only the runner's `bin/codegraph` path on success
#
# Inputs    the platform package (read-only)
# Outputs   <dst>/ (patched copy) and <dst>/RUNNER_RECEIPT.json:
#             legacy fields (kept for existing consumers): patch_id ("fkidx1"
#             when fkidx1 is applied), codegraph_version, source, kept_indexes,
#             lists_before, lists_after, source_dbjs_sha256,
#             patched_dbjs_sha256, created_utc;
#             new fields: receipt_schema=2, runner_key, patch_set,
#             patches{id: status, summary, anchors, files{rel: source/patched
#             sha256}, detail | reason}
# Exit codes
#   0  runner ready (CREATED now, or REUSED with a valid receipt)
#   2  fail-closed: anchor/shape mismatch, unknown patch id, cannot read/write,
#      or the runner dir to be replaced is in use by a live process
#   3  NOT_NEEDED: every selected patch's hazard is absent upstream
#
# Side effects  writes only under <dst> (via <dst>.partial + rename); reads
#               /proc/*/cmdline to refuse replacing a runner dir in use
# Dependencies  python3 (stdlib), cp (GNU coreutils), npm (only for default --src)
# Cross-references
#   runner_patches/*.py, fk_cascade_probe.py (fkidx1 oracle),
#   tests/run_runner_patch_tests.sh (lockfix1/datafrag1 RED/GREEN + mutations),
#   docs/scripts/fk_index_patch.md, constitution §11.4.78/.80, §11.4.115,
#   §11.4.201, §11.4.74, §9.2 (nothing shared is modified).
# ============================================================================
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time

sys.dont_write_bytecode = True  # never litter the tracked tree with __pycache__
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import runner_patches  # noqa: E402
from runner_patches.common import FileView, NotNeeded, Refuse  # noqa: E402,F401
from runner_patches.fkidx1 import (  # noqa: E402,F401  (legacy re-exports)
    FK_RE, IDX_RE, LIST_RE, TABLE_RE, compute_patch, derive_keep_set, parse_lists, patch_text)

PATCH_ID = "fkidx1"  # legacy constant: the original (and first) patch id
RECEIPT_SCHEMA = 2
DBJS_REL = os.path.join("lib", "dist", "db", "index.js")


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def sha256_text(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def default_src():
    try:
        root = subprocess.check_output(["npm", "root", "-g"], text=True, timeout=60).strip()
    except Exception as exc:  # noqa: BLE001
        raise Refuse(f"npm root -g failed: {exc}")
    base = os.path.join(root, "@colbymchenry", "codegraph", "node_modules", "@colbymchenry")
    if not os.path.isdir(base):
        raise Refuse(f"no @colbymchenry/codegraph install under {base}")
    for name in sorted(os.listdir(base)):
        cand = os.path.join(base, name)
        if os.path.isfile(os.path.join(cand, "lib", "dist", "db", "index.js")):
            return cand
    raise Refuse(f"no platform package with lib/dist/db/index.js under {base}")


def package_version(src):
    try:
        return json.load(open(os.path.join(src, "package.json")))["version"]
    except Exception as exc:  # noqa: BLE001
        raise Refuse(f"cannot read package version: {exc}")


def plan_all(src, ids):
    """Plan every selected patch in REGISTRY order on one FileView."""
    view = FileView(src)
    applied, report = [], {}
    for mod in runner_patches.load(ids):
        try:
            p = mod.plan(view)
        except NotNeeded as exc:
            report[mod.PATCH_ID] = {"status": "NOT_NEEDED", "summary": mod.SUMMARY, "reason": str(exc)}
            continue
        files = {}
        for rel, new in p.new_text.items():
            before = view.read(rel)
            if new == before:
                raise Refuse(f"{mod.PATCH_ID}: planned edit of {rel} is a no-op — refusing")
            files[rel] = {"source_sha256": sha256_text(before), "patched_sha256": sha256_text(new)}
            view.edits[rel] = new
        report[mod.PATCH_ID] = {"status": "APPLIED", "summary": mod.SUMMARY, "anchors": p.anchors,
                                "files": files, "detail": p.detail}
        applied.append(mod.PATCH_ID)
    return view, applied, report


def runner_in_use(dst):
    """PIDs whose real /proc cmdline references dst (never bare pgrep, §11.4.201)."""
    users = []
    needle = (dst.rstrip("/") + "/").encode()
    for ent in os.listdir("/proc") if os.path.isdir("/proc") else []:
        if not ent.isdigit() or int(ent) <= 1 or int(ent) == os.getpid():
            continue
        try:
            with open(f"/proc/{ent}/cmdline", "rb") as fh:
                cmd = fh.read()
        except OSError:
            continue
        if needle in cmd:
            users.append(int(ent))
    return users


def receipt_valid(rc, src, dst, view, applied, key):
    """True when <dst> already holds exactly the runner this invocation would build."""
    if "patches" not in rc:  # legacy single-patch receipt (pre-registry tool)
        return (applied == ["fkidx1"] and rc.get("patch_id") == "fkidx1"
                and rc.get("source_dbjs_sha256") == sha256(os.path.join(src, DBJS_REL))
                and sha256(os.path.join(dst, DBJS_REL)) == rc.get("patched_dbjs_sha256"))
    if rc.get("runner_key") != key or rc.get("patch_set") != applied:
        return False
    for rel, text in view.edits.items():
        if sha256(os.path.join(dst, rel)) != sha256_text(text):
            return False
    return True


def main():
    ap = argparse.ArgumentParser(description="Build the patched private CodeGraph runner")
    ap.add_argument("--src")
    ap.add_argument("--dst")
    ap.add_argument("--patches", help="comma-separated subset of: " + ",".join(runner_patches.REGISTRY))
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--print-bin", action="store_true")
    ap.add_argument("--list-patches", action="store_true")
    args = ap.parse_args()
    try:
        if args.list_patches:
            for mod in runner_patches.load():
                print(f"{mod.PATCH_ID}\t{mod.SUMMARY}")
            return 0
        ids = None
        if args.patches is not None:
            ids = [x.strip() for x in args.patches.split(",") if x.strip()]
            if not ids:
                raise Refuse("--patches given but empty")
        src = os.path.abspath(args.src or default_src())
        ver = package_version(src)
        view, applied, report = plan_all(src, ids)
        if not applied:
            print(json.dumps({"status": "NOT_NEEDED", "reason": "; ".join(
                f"{k}: {v['reason']}" for k, v in report.items()), "patches": report}))
            return 3
        key = f"{ver}-{'-'.join(applied)}"
        base = os.environ.get("HELIX_CODEGRAPH_RUNNER_DIR") or os.path.join(
            os.path.expanduser("~"), ".cache", "helix", "codegraph_runner")
        dst = os.path.abspath(args.dst or os.path.join(base, key))
        binp = os.path.join(dst, "bin", "codegraph")
        receipt_path = os.path.join(dst, "RUNNER_RECEIPT.json")
        if os.path.isfile(receipt_path) and not args.force:
            rc = json.load(open(receipt_path))
            if receipt_valid(rc, src, dst, view, applied, key):
                print(binp if args.print_bin else json.dumps({"status": "REUSED", "runner": binp, **rc}, indent=2))
                return 0
        if os.path.exists(dst):
            users = runner_in_use(dst)
            if users:
                raise Refuse(f"runner dir {dst} is in use by live PID(s) {users} — refusing to replace it")
        tmp = dst + ".partial"
        if os.path.exists(tmp):
            shutil.rmtree(tmp)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        subprocess.check_call(["cp", "-a", "--reflink=auto", src, tmp])
        for rel, text in view.edits.items():
            with open(os.path.join(tmp, rel), "w", encoding="utf-8") as fh:
                fh.write(text)
        receipt = {"receipt_schema": RECEIPT_SCHEMA, "runner_key": key, "patch_set": applied,
                   "codegraph_version": ver, "source": src,
                   "source_dbjs_sha256": sha256(os.path.join(src, DBJS_REL)),
                   "patched_dbjs_sha256": sha256(os.path.join(tmp, DBJS_REL)),
                   "patches": report,
                   "created_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
        if "fkidx1" in applied:  # legacy top-level fields describe the fkidx1 patch
            receipt.update({"patch_id": PATCH_ID, **report["fkidx1"]["detail"]})
        with open(os.path.join(tmp, "RUNNER_RECEIPT.json"), "w", encoding="utf-8") as fh:
            json.dump(receipt, fh, indent=2)
            fh.write("\n")
        if os.path.exists(dst):
            shutil.rmtree(dst)
        os.rename(tmp, dst)
        if not os.access(binp, os.X_OK):
            raise Refuse(f"runner launcher not executable: {binp}")
        print(binp if args.print_bin else json.dumps({"status": "CREATED", "runner": binp, **receipt}, indent=2))
        return 0
    except NotNeeded as exc:  # defensive: plan_all converts per-patch NotNeeded
        print(json.dumps({"status": "NOT_NEEDED", "reason": str(exc)}))
        return 3
    except Refuse as exc:
        print(json.dumps({"status": "REFUSED", "reason": str(exc)}), file=sys.stderr)
        return 2
    except (OSError, subprocess.CalledProcessError, json.JSONDecodeError) as exc:
        print(json.dumps({"status": "REFUSED", "reason": f"{type(exc).__name__}: {exc}"}), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
