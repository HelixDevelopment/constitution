"""Mirrored-field allowlist, canonical content hash, and the pre-write gate (anchor 11.4.300(D),(E))."""
import hashlib
import json
import re

from . import redact

ALLOWED_FIELDS = ("atm_id", "type", "status", "title", "severity", "description")
PRIVATE_FIELDS = ("forensic_anchor", "body_md")      # never sent; their text is fingerprinted against the outgoing fields


def build(item):
    if not item.get("atm_id") or not re.fullmatch(r"[A-Za-z0-9._-]+", str(item["atm_id"])):
        raise ValueError("item has no atm_id the mirror key can carry")
    return {f: ("" if item.get(f) is None else str(item.get(f))) for f in ALLOWED_FIELDS}


def content_hash(payload):
    return hashlib.sha256(json.dumps(payload, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()


def own_private_fingerprints(item, k=8):
    """Fingerprints of the item's OWN non-allowlisted fields (operator quote, long body): text that must never leave must not reappear,
    even partly, in the title or description that DOES leave."""
    text = " ".join(str(item.get(f) or "") for f in PRIVATE_FIELDS)
    return redact.fingerprints(text, k) if text.strip() else set()


def prepare(item, fingerprint_set=None, k=8):
    """{'verdict': 'OK', 'payload', 'hash'} or {'verdict': 'BLOCKED', 'item': id, 'hits': [...]} (id and kinds only; an id that is itself
    the hit is withheld)."""
    try:
        pl = build(item)
    except ValueError:      # an id the footer/title key cannot carry would be re-created on every run: refuse it, naming nothing
        return {"verdict": "BLOCKED", "item": "[redacted-id]", "hits": [{"field": "atm_id", "kind": "unkeyable-id"}]}
    fps = set(fingerprint_set or ()) | own_private_fingerprints(item, k)
    hits = redact.scan(pl, fps or None, k)
    if hits:
        shown = "[redacted-id]" if any(h["field"] == "atm_id" for h in hits) else pl["atm_id"]
        return {"verdict": "BLOCKED", "item": shown, "hits": hits}
    return {"verdict": "OK", "payload": pl, "hash": content_hash(pl)}
