"""Shared contract for fk_index_patch.py runner patches (see __init__.py).

Every patch module exposes:
    PATCH_ID  : short stable id, lowercase [a-z0-9]+, also the runner-key token
    SUMMARY   : one-line purpose
    plan(view): return a PatchPlan, or raise NotNeeded / Refuse

`view` is a FileView over the (possibly already-patched-by-earlier-patches)
package text. A plan is fail-closed by construction: `replace_once` asserts
the anchor occurs EXACTLY once, otherwise Refuse (exit 2, no runner).
"""
import hashlib


class Refuse(Exception):
    """Fail-closed: shape mismatch or environment problem (exit 2)."""


class NotNeeded(Exception):
    """Hazard provably absent upstream (this patch is skipped)."""


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


class FileView:
    """Read-through view of package files with pending edits layered on top."""

    def __init__(self, src):
        self.src = src
        self.edits = {}  # rel -> text

    def read(self, rel):
        if rel in self.edits:
            return self.edits[rel]
        import os
        try:
            with open(os.path.join(self.src, rel), encoding="utf-8") as fh:
                return fh.read()
        except OSError as exc:
            raise Refuse(f"cannot read {rel}: {exc}")


class PatchPlan:
    def __init__(self, patch_id):
        self.patch_id = patch_id
        self.new_text = {}   # rel -> patched text (this patch's result)
        self.anchors = []    # [{"file", "anchor", "occurrences"}]
        self.detail = {}

    def replace_once(self, view, rel, anchor, replacement, label):
        text = self.new_text.get(rel, view.read(rel))
        occ = text.count(anchor)
        if occ != 1:
            raise Refuse(f"{self.patch_id}: anchor '{label}' occurs {occ}x in {rel} "
                         f"(expected exactly 1) — upstream shape changed, re-derive the patch")
        self.new_text[rel] = text.replace(anchor, replacement, 1)
        self.anchors.append({"file": rel, "anchor": label, "occurrences": 1})
