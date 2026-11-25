"""Mirrored-field allowlist, canonical content hash, and the pre-write gate (anchor 11.4.300(D),(E))."""
import hashlib
import json
import re

from . import redact

ALLOWED_FIELDS = ("atm_id", "type", "status", "title", "severity")   # the ONLY DB fields that are ever sent
GENERATED_FIELDS = ("description",)    # sent, but GENERATED from a fixed template: the DB's description / body text is never mirrored (operator decision 2026-11-25)
GENERATED_DESCRIPTION = "Generated public summary. The full record lives in the owning repository's workable-items database."
DOC_POINTER = "docs/workable_items.db"
PRIVATE_FIELDS = ("forensic_anchor", "body_md")   # never sent; their text is fingerprinted against every outgoing field (title above all)
RUN_WORDS = 7                                         # a verbatim run of this many words from a private field blocks the item


def build(item):
    if not item.get("atm_id") or not re.fullmatch(r"[A-Za-z0-9._-]+", str(item["atm_id"])):
        raise ValueError("item has no atm_id the mirror key can carry")
    pl = {f: ("" if item.get(f) is None else str(item.get(f))) for f in ALLOWED_FIELDS}
    pl["description"] = GENERATED_DESCRIPTION
    return pl


def content_hash(payload):
    return hashlib.sha256(json.dumps(payload, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()


def own_private_fingerprints(item, k=RUN_WORDS):
    """Fingerprints of the item's OWN non-allowlisted fields (operator quote, long body), computed per LINE so no shingle spans two lines:
    text that must never leave must not reappear, even partly, in an outgoing field, the title above all.
    The one allowance: when ONE LINE of the body repeats the item's WHOLE title (its heading, 'the question put to the operator was: <title>'), the title is
    public restated, and the title's own shingles are not counted as private. A title that is NOT repeated whole in the body gets no allowance, so
    a title that splices in 7 or more verbatim words of the body or the quote is blocked. `forensic_anchor` never gets the allowance.
    Fingerprints are taken per line AND over the joined words, so a run stitched across hard-wrapped or short lines is caught too. Residual, stated plainly: a title that is exactly a private body sentence is indistinguishable from a restated title and passes (so does a confusable-homoglyph title)."""
    title = " ".join(redact._words(str(item.get("title") or "")))
    fps, anchor, body = set(), set(), set()
    whole = False                      # is the WHOLE title on ONE body line? (a title stitched from adjacent lines gets no allowance)
    for field, dest in (("forensic_anchor", anchor), ("body_md", body)):
        for line in redact.normalise(str(item.get(field) or "")).split("\n"):
            w = " ".join(redact._words(line))
            if w:
                dest |= redact.fingerprints(w, k)
                if field == "body_md" and title and (" " + title + " ") in (" " + w + " "):
                    whole = True
    for field, dest in (("forensic_anchor", anchor), ("body_md", body)):    # plus the JOINED words, so a run that spans short or hard-wrapped lines is caught
        dest |= redact.fingerprints(" ".join(redact._words(redact.normalise(str(item.get(field) or "")))), k)
    if whole:
        body -= redact.fingerprints(title, k)
    return anchor | body


def prepare(item, fingerprint_set=None, k=RUN_WORDS):
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
