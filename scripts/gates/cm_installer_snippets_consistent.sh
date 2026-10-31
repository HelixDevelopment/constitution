#!/usr/bin/env bash
# cm_installer_snippets_consistent.sh — CM-INSTALLER-SNIPPETS-CONSISTENT gate.
#
# ── Purpose ───────────────────────────────────────────────────────────────
# `install_constitution.sh --print-snippets` is the single source of the copy-paste install commands.
# The gate RUNS it and compares the output with an oracle written here independently of the installer's
# own table (§11.4.245): exactly the five upstream raw URLs below, each line of the form
#   curl -fsSL '<https url>' | bash
# no duplicates, nothing else. With --docs-root DIR it also requires every installer raw URL that appears
# in DIR/**/*.md to be one of the five (a doc pointing at a stale or invented URL FAILs).
# Control needle: the oracle's own first URL must be found in the output; a run that prints nothing is BLIND.
#
# ── Usage ─────────────────────────────────────────────────────────────────
#   cm_installer_snippets_consistent.sh [--installer FILE] [--docs-root DIR]
# ── Exit codes ────────────────────────────────────────────────────────────
#   0 PASS · 1 FAIL · 2 BLIND (installer missing or printed nothing) · 64 usage
# Read-only. Paired mutation test: cm_installer_snippets_consistent_mutation_test.sh. Classification: universal.
set -uo pipefail
GATE="CM-INSTALLER-SNIPPETS-CONSISTENT"
const="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." && pwd)"
inst="$const/scripts/install_constitution.sh"; docs=""
while [ $# -gt 0 ]; do
  case "$1" in
    --installer) [ $# -ge 2 ] || { echo "$GATE: --installer needs a value" >&2; exit 64; }; inst="$2"; shift 2 ;;
    --docs-root) [ $# -ge 2 ] || { echo "$GATE: --docs-root needs a value" >&2; exit 64; }; docs="$2"; shift 2 ;;
    -h|--help) sed -n 2,18p "${BASH_SOURCE[0]:-$0}"; exit 0 ;;
    *) echo "$GATE: unknown argument $1" >&2; exit 64 ;;
  esac
done
[ -r "$inst" ] || { echo "⚠ $GATE: BLIND (exit 2) — installer not found: $inst"; exit 2; }
[ -z "$docs" ] || [ -d "$docs" ] || { echo "⚠ $GATE: BLIND (exit 2) — docs root not found: $docs"; exit 2; }
work="$(mktemp -d "${TMPDIR:-/tmp}/cm_snip.XXXXXX")" || exit 2
trap 'rm -f -- "${work:?}/out"; rmdir -- "${work:?}"' EXIT
(cd "$work" && bash "$inst" --print-snippets) >"$work/out" 2>/dev/null; rc=$?
python3 -I - "$work/out" "$rc" "$docs" <<'PY'
import os, re, sys
G = "CM-INSTALLER-SNIPPETS-CONSISTENT"
ORACLE = [
    "https://raw.githubusercontent.com/HelixDevelopment/HelixConstitution/main/scripts/install_constitution.sh",
    "https://gitlab.com/helixdevelopment1/helixconstitution/-/raw/main/scripts/install_constitution.sh",
    "https://gitlab.com/vasic-digital/HelixConstitution/-/raw/main/scripts/install_constitution.sh",
    "https://gitflic.ru/project/helixdevelopment/helixconstitution/blob/raw?file=scripts/install_constitution.sh&branch=main",
    "https://gitverse.ru/api/repos/helixdevelopment/HelixConstitution/raw/branch/main/scripts/install_constitution.sh",
]
out, rc, docs = open(sys.argv[1], encoding="utf-8", errors="replace").read(), sys.argv[2], sys.argv[3]
lines = [l for l in out.splitlines() if l.strip()]
if not lines or ORACLE[0] not in out:
    if lines:
        print("  FAIL output present but the first oracle URL is missing")
        print("❌ %s: FAIL" % G); sys.exit(1)
    print("⚠ %s: BLIND (exit 2) — --print-snippets printed nothing (rc=%s)" % (G, rc)); sys.exit(2)
fails = []
if rc != "0": fails.append("--print-snippets exit %s (want 0)" % rc)
fmt = re.compile(r"^curl -fsSL '(https://[^'\s]+)' \| bash$")
urls = []
for l in lines:
    m = fmt.match(l)
    if not m: fails.append("malformed line: %s" % l); continue
    urls.append(m.group(1))
if len(set(urls)) != len(urls): fails.append("duplicate URL in snippets")
for u in ORACLE:
    if u not in urls: fails.append("missing upstream: %s" % u)
for u in urls:
    if u not in ORACLE: fails.append("unexpected URL: %s" % u)
ndocs = 0
if docs:
    rx = re.compile(r"https?://[^\s'\"<>)`]*install_constitution\.sh[^\s'\"<>)`]*")
    for d, _, fs in os.walk(docs):
        for f in fs:
            if not f.endswith(".md"): continue
            p = os.path.join(d, f); ndocs += 1
            for n, l in enumerate(open(p, encoding="utf-8", errors="replace"), 1):
                for u in rx.findall(l):
                    if "/raw" not in u and "raw." not in u: continue  # web pages, not raw downloads
                    if u not in ORACLE: fails.append("doc %s:%d uses non-canonical raw URL %s" % (p, n, u))
for f in fails: print("  FAIL " + f)
if fails: print("❌ %s: FAIL (%d finding(s))" % (G, len(fails))); sys.exit(1)
print("✅ %s: PASS (%d snippet lines match the 5-URL oracle%s)" % (G, len(urls), "; %d doc file(s) scanned" % ndocs if docs else ""))
PY
