"""Redaction gate (anchor 11.4.300(D)): scans an outgoing payload; findings carry field and kind only, never the matched text."""
import hashlib
import re

_PATTERNS = [
    ("github-token", re.compile(r"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}\b|\bgithub_pat_[A-Za-z0-9_]{20,}\b")),
    ("gitlab-token", re.compile(r"\bglpat-[A-Za-z0-9_-]{16,}\b")),
    ("aws-key", re.compile(r"\bAKIA[0-9A-Z]{16}\b")),
    ("private-key", re.compile(r"-----BEGIN (?:[A-Z]+ )*PRIVATE KEY-----")),
    ("bearer", re.compile(r"\bBearer\s+[A-Za-z0-9._~+/=-]{16,}")),
    ("assignment-secret", re.compile(r"(?i)\b(?:password|passwd|secret|api[_-]?key|token)\b\s*[:=]\s*['\"]?[^\s'\"]{8,}")),
    ("email", re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b")),
    ("phone", re.compile(r"(?<!\w)\+\d[\d\s().-]{8,}\d")),
    ("operator-quote", re.compile(r"(?i)forensic anchor|verbatim operator|operator (?:quote|directive)\s*:")),
]


def _words(text):
    return re.sub(r"[^a-z0-9]+", " ", text.lower()).split()


def fingerprints(corpus, k=8):
    """Set of hashes of k-word shingles of a private corpus (hashes only are kept)."""
    w = _words(corpus)
    return {hashlib.sha256(" ".join(w[i:i + k]).encode()).hexdigest()[:24] for i in range(max(0, len(w) - k + 1))}


def scan(payload, fingerprint_set=None, k=8):
    hits = []
    for field, val in sorted(payload.items()):
        if not isinstance(val, str):
            continue
        for kind, rx in _PATTERNS:
            if rx.search(val):
                hits.append({"field": field, "kind": kind})
        if fingerprint_set:
            w = _words(val)
            if any(hashlib.sha256(" ".join(w[i:i + k]).encode()).hexdigest()[:24] in fingerprint_set for i in range(max(0, len(w) - k + 1))):
                hits.append({"field": field, "kind": "private-corpus"})
    return hits
