"""Mirrored-field allowlist, canonical content hash, and the pre-write gate (anchor 11.4.300(D),(E))."""
import hashlib
import json

from . import redact

ALLOWED_FIELDS = ("atm_id", "type", "status", "title", "severity", "description")


def build(item):
    if not item.get("atm_id"):
        raise ValueError("item has no atm_id")
    return {f: ("" if item.get(f) is None else str(item.get(f))) for f in ALLOWED_FIELDS}


def content_hash(payload):
    return hashlib.sha256(json.dumps(payload, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()


def prepare(item, fingerprint_set=None, k=8):
    """{'verdict': 'OK', 'payload', 'hash'} or {'verdict': 'BLOCKED', 'item': id, 'hits': [...]} (id and kinds only)."""
    pl = build(item)
    hits = redact.scan(pl, fingerprint_set, k)
    if hits:
        return {"verdict": "BLOCKED", "item": pl["atm_id"], "hits": hits}
    return {"verdict": "OK", "payload": pl, "hash": content_hash(pl)}
