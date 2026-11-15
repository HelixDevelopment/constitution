#!/usr/bin/env python3
"""Print-site census of the release scripts (CON-234 class, round 5, §11.4.276(C)).

Usage: python3 -I census_print_sites.py ROOT
Lists every line of the four release scripts that writes to stdout, stderr, fd 3 or a file
(printf, echo, cat, tee, kv, die, die_usage, abort, fail, gap, a redirection to a file) together
with every shell expansion the line contains ($name, ${name...}, $(...)). It is an inventory, not a
verdict: each expansion is then classified by hand in threat_model.md section 4.
Control needles (§11.4.273): a positive needle (a site known to exist) must be listed for every
script, and a fabricated needle must be found in no file; the run fails (exit 1) when either is off.
"""
import os as _ge_os  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
for _ge_v in "GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX".split(): _ge_os.environ.pop(_ge_v, None)
import re
import sys

ROOT = sys.argv[1]
FILES = {
    "scripts/release/tag_and_release.sh": "RESULT: ",
    "scripts/release/derive_release_facts.sh": "kv base",
    "scripts/release_publish_gitea.sh": "SKIPPED-NO-TOKEN:",
    "scripts/release/redact_cut.sh": "printf",
}
SITE = re.compile(r"\b(printf|echo|cat|tee|kv|die|die_usage|abort|fail|gap)\b|>&[23]|>\s*\"?\$")
EXP = re.compile(r"\$\{?[A-Za-z_][A-Za-z0-9_]*|\$\(|\$[0-9@*#?]")
NEG = "ZZNOSUCHNEEDLEZZ"
bad = 0
total = 0
for rel, pos in FILES.items():
    text = open(f"{ROOT}/{rel}", encoding="utf-8").read().split("\n")
    sites = []
    for n, line in enumerate(text, 1):
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        if SITE.search(s):
            exps = sorted(set(EXP.findall(s)))
            sites.append((n, s, exps))
    print(f"== {rel}: {len(sites)} print/write sites")
    for n, s, exps in sites:
        print(f"{rel}:{n}: [{' '.join(exps) or '-'}] {s[:160]}")
    total += len(sites)
    if not any(pos in s for _, s, _ in sites):
        print(f"CONTROL FAIL positive needle {pos!r} not listed for {rel}")
        bad += 1
    if any(NEG in l for l in text):
        print(f"CONTROL FAIL fabricated needle found in {rel}")
        bad += 1
print(f"RESULT: sites={total} control_failures={bad}")
sys.exit(1 if bad else 0)
