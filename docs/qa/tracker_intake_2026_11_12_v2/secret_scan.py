#!/usr/bin/env python3
"""Secret scan of a git diff (added lines only) with control needles.
usage: secret_scan.py <diff-file> <real_by_path.txt>
Prints pattern names and counts only, never a match; checks that none of the per-file scan paths
(CON-333) appears in the diff. Control needles: each pattern must match its planted needle, and a
planted scan path must be found."""
import re, sys
import os as _ge_os
for _ge_v in "GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX".split(): _ge_os.environ.pop(_ge_v, None)
diff, paths_file = sys.argv[1], sys.argv[2]
P = [
    ("aws-access-key-id", r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"),
    ("github-pat", r"\bgh[pousr]_[A-Za-z0-9]{36,}\b"),
    ("github-fine-grained-pat", r"\bgithub_pat_[A-Za-z0-9_]{40,}\b"),
    ("gcp-api-key", r"\bAIza[0-9A-Za-z_-]{35}\b"),
    ("private-key-block", r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    ("huggingface-token", r"\bhf_[A-Za-z0-9]{30,}\b"),
    ("jwt", r"\beyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]+"),
    ("slack-token", r"\bxox[abposr]-[A-Za-z0-9-]{10,}\b"),
    ("openai-style-key", r"\bsk-[A-Za-z0-9_-]{32,}\b"),
    ("url-userinfo-password", r"[a-z][a-z0-9+.-]*://[^/\s:@]+:[^/\s@]{6,}@"),
]
NEEDLE = {
    "aws-access-key-id": "AKIA" + "Q" * 16, "github-pat": "ghp_" + "a" * 36,
    "github-fine-grained-pat": "github_pat_" + "a" * 40, "gcp-api-key": "AIza" + "a" * 35,
    "private-key-block": "-----BEGIN " + "RSA PRIVATE KEY-----", "huggingface-token": "hf_" + "a" * 30,
    "jwt": "eyJ" + "a" * 8 + ".eyJ" + "a" * 8 + ".x", "slack-token": "xoxb-" + "1" * 10,
    "openai-style-key": "sk-" + "a" * 32, "url-userinfo-password": "https://u:" + "p" * 8 + "@h",
}
added = [l[1:] for l in open(diff, errors="replace").read().split("\n") if l.startswith("+") and not l.startswith("+++")]
text = "\n".join(added)
bad = 0
for name, rx in P:
    r = re.compile(rx)
    if not r.search(NEEDLE[name]):
        print("NEEDLE-FAIL", name); bad = 1
    n = len(r.findall(text))
    print("pattern %-26s hits %d" % (name, n))
paths = [l.split("\t")[1].strip() for l in open(paths_file, errors="replace") if l.strip()]
paths = [p for p in set(paths) if len(p) >= 12 and "/" in p]
hits = sum(1 for p in paths if p in text)
planted = text + "\n" + paths[0] if paths else text
ctrl = sum(1 for p in paths if p in planted) > hits
print("scan paths checked %d, found in diff %d, control (one planted path found) %s" % (len(paths), hits, "yes" if ctrl else "NO"))
if not ctrl:
    bad = 1
print("added lines scanned %d" % len(added))
sys.exit(bad)
