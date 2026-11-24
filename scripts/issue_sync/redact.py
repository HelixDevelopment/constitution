"""Redaction gate (anchor 11.4.300(D)): scans an outgoing payload; findings carry field and kind only, never the matched text."""
import hashlib
import re
import unicodedata

_ZERO_WIDTH = re.compile("[\u00ad\u200b-\u200f\u202a-\u202e\u2060-\u2064\ufeff]")


def normalise(text):
    """NFKC + zero-width/format characters removed, so a homoglyph or an invisible joiner cannot hide a secret shape from the scan."""
    return _ZERO_WIDTH.sub("", unicodedata.normalize("NFKC", text))

_PATTERNS = [
    ("github-token", re.compile(r"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}\b|\bgithub_pat_[A-Za-z0-9_]{20,}\b")),
    ("gitlab-token", re.compile(r"\bglpat-[A-Za-z0-9_-]{16,}\b")),
    ("aws-key", re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b")),
    ("private-key", re.compile(r"-----BEGIN (?:[A-Z]+ )*PRIVATE KEY-----")),
    ("bearer", re.compile(r"\bBearer\s+[A-Za-z0-9._~+/=-]{16,}")),
    ("assignment-secret", re.compile(r"(?i)\b(?:pass(?:word|wd|phrase)?|pwd|secret|client[ _-]?secret|api[ _-]?key|access[ _-]?key|auth[ _-]?token|token)['\"]?\s*(?:[:=]|=>|\bis\b)\s*['\"]?[^\s'\"]{6,}")),
    ("slack-token", re.compile(r"\bxox[abprs]-[A-Za-z0-9-]{10,}")),
    ("jwt", re.compile(r"\beyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{4,}")),
    ("stripe-key", re.compile(r"\b[sr]k_(?:live|test)_[A-Za-z0-9]{10,}")),
    ("google-key", re.compile(r"\bAIza[0-9A-Za-z_-]{30,}")),
    ("sendgrid-key", re.compile(r"\bSG\.[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}")),
    ("url-credentials", re.compile(r"\b[a-z][a-z0-9+.-]*://[^\s/:@]+:[^\s/@]+@")),
    ("llm-key", re.compile(r"\bsk-(?:ant-)?[A-Za-z0-9_-]{20,}")),
    ("npm-token", re.compile(r"\bnpm_[A-Za-z0-9]{30,}")),
    ("email", re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b")),
    ("phone", re.compile(r"(?<!\w)\+\d[\d\s().-]{8,}\d")),
    ("operator-quote", re.compile(r"(?i)forensic anchor|verbatim operator|operator (?:quote|directive)\s*:")),
]


def _words(text):
    return re.sub(r"[^a-z0-9]+", " ", normalise(text).lower()).split()


def fingerprints(corpus, k=8):
    """Set of hashes of k-word shingles of a private corpus (hashes only are kept)."""
    w = _words(corpus)
    return {hashlib.sha256(" ".join(w[i:i + k]).encode()).hexdigest()[:24] for i in range(max(0, len(w) - k + 1))}


def scan(payload, fingerprint_set=None, k=8):
    hits = []
    for field, val in sorted(payload.items()):
        if not isinstance(val, str):
            continue
        val = normalise(val)
        for kind, rx in _PATTERNS:
            if rx.search(val):
                hits.append({"field": field, "kind": kind})
        if fingerprint_set:
            w = _words(val)
            if any(hashlib.sha256(" ".join(w[i:i + k]).encode()).hexdigest()[:24] in fingerprint_set for i in range(max(0, len(w) - k + 1))):
                hits.append({"field": field, "kind": "private-corpus"})
    return hits
