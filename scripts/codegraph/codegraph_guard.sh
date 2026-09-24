#!/usr/bin/env bash
# ============================================================================
# codegraph_guard.sh — mechanical gate CM-CODEGRAPH-SAFE-INDEX-PATH
# ============================================================================
# Purpose      Refuse any tracked script / hook / doc command that bypasses
#              codegraph_safe.sh: (a) a direct stock `codegraph init|index`
#              (also the `npx … @colbymchenry/codegraph index` and python
#              argv-list forms), and (b) `codegraph … || true` failure masking.
#              Both were the root of the 2026-09-23 incident (bulk-window FK-cascade hazard
#              reached through a legacy one-liner that masked every failure).
# Usage        codegraph_guard.sh [--root DIR]... [--self-test]
#              default roots: this constitution's scripts/ dir, plus the
#              consuming project's scripts/ dir when the constitution is a
#              submodule of it
# Inputs       files under each root: *.sh *.bash *.py *.js *.mjs *.ts *.yml
#              *.yaml *.md and extension-less files with a shebang. Markdown
#              is scanned ONLY inside ``` fences (prose is not a command);
#              full-line comments (#, //) are carriers, not commands.
#              Exemption: a line carrying `codegraph-guard: allow <reason>`
#              (a non-empty reason is mandatory — a bare marker is flagged).
# Outputs      one "<relpath>:<line>: <rule>: <text>" per offender on stdout,
#              then "GUARD PASS|FAIL files=<n> offenders=<n>"
# Exit codes   0 clean, 1 offenders found, 2 usage error / BLIND (0 files
#              scanned under a root — an empty scan proves nothing, §11.4.273)
# Side effects none (--self-test writes a fixture tree under $TMPDIR)
# Dependencies bash, python3
# Cross-refs   codegraph_safe.sh, tests/test_guard.sh, docs/scripts/codegraph_guard.md,
#              constitution §11.4.201 (golden-true + golden-false-with-carrier),
#              §11.4.273 (control needle), §11.4.75 (mechanical enforcement)
# ============================================================================
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOTS=()
SELFTEST=0
while [ $# -gt 0 ]; do
    case "$1" in
        --root) [ $# -ge 2 ] || { echo "codegraph_guard: --root needs a value" >&2; exit 2; }
                ROOTS+=("$2"); shift 2 ;;
        --self-test) SELFTEST=1; shift ;;
        -h|--help) sed -n '2,32p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "codegraph_guard: unknown argument: $1" >&2; exit 2 ;;
    esac
done

scan() {
    # scan <root>... — the scanner itself (python, stdlib only)
    python3 - "$@" <<'PY'
import os, re, sys

CMD = re.compile(r'(?:(?<![A-Za-z0-9_.-])|(?<=\\n))(?:npx\s+(?:-y\s+)?@colbymchenry/)?codegraph["\']?[\s,]+["\']?(init|index)(?=$|[\s"\'`;)|&])')
MASK_CMD = re.compile(r'(?:(?<![A-Za-z0-9_.-])|(?<=\\n))codegraph["\']?\s+[a-z]')
MASK = re.compile(r'\|\|\s*(true|:)(?![A-Za-z0-9_])')
ALLOW = re.compile(r'codegraph-guard:\s*allow[ \t]+(?=\S)(?!\\n)[A-Za-z0-9]')
EXTS = (".sh", ".bash", ".py", ".js", ".mjs", ".ts", ".yml", ".yaml", ".md")
SKIP_DIRS = {".git", "node_modules", ".codegraph", "__pycache__", ".compressed", "out"}

def candidates(root):
    for dp, dns, fns in os.walk(root):
        dns[:] = [d for d in dns if d not in SKIP_DIRS]
        for fn in fns:
            p = os.path.join(dp, fn)
            if not os.path.isfile(p) or os.path.islink(p):
                continue
            if fn.endswith(EXTS):
                yield p
            elif "." not in fn:
                try:
                    with open(p, "rb") as fh:
                        if fh.read(2) == b"#!":
                            yield p
                except OSError:
                    pass

total_files = 0
offenders = []
blind = []
for root in sys.argv[1:]:
    root = os.path.abspath(root)
    n = 0
    for p in candidates(root):
        n += 1
        rel = os.path.relpath(p, root)
        md = p.endswith(".md")
        try:
            lines = open(p, encoding="utf-8", errors="replace").read().split("\n")
        except OSError:
            continue
        fence = False
        for i, ln in enumerate(lines, 1):
            s = ln.strip()
            if md:
                if s.startswith("```"):
                    fence = not fence
                    continue
                if not fence:
                    continue
            elif s.startswith("#") or s.startswith("//"):
                continue
            if ALLOW.search(ln):
                continue
            if CMD.search(ln):
                offenders.append(f"{rel}:{i}: direct-stock-init-index: {s[:160]}")
            elif MASK_CMD.search(ln) and MASK.search(ln):
                offenders.append(f"{rel}:{i}: masked-codegraph-failure: {s[:160]}")
    total_files += n
    if n == 0:
        blind.append(root)
for o in offenders:
    print(o)
if blind:
    print("GUARD BLIND no candidate files under: " + ", ".join(blind))
    sys.exit(2)
print(f"GUARD {'FAIL' if offenders else 'PASS'} files={total_files} offenders={len(offenders)}")
sys.exit(1 if offenders else 0)
PY
}

if [ "$SELFTEST" -eq 1 ]; then
    base="${TMPDIR:-/tmp}/cg_guard_selftest"
    mkdir -p "$base"
    T="$(mktemp -d "$base/run.XXXXXX")"
    mkdir -p "$T/scripts" "$T/docs"
    cp "$HERE/codegraph_safe.sh" "$T/scripts/codegraph_safe.sh"
    ok=0
    # golden-false-with-carrier: launcher copy + comment/prose mentions -> clean
    printf '#!/bin/sh\n# codegraph index is only run via the launcher\necho ok\n' > "$T/scripts/carrier.sh"  # codegraph-guard: allow self-test fixture text
    printf 'Never run codegraph init by hand.\n' > "$T/docs/prose.md"  # codegraph-guard: allow self-test fixture text
    out="$(scan "$T")"; rc=$?
    if [ "$rc" -eq 0 ]; then echo "SELFTEST PASS clean tree (launcher + carriers) -> exit 0"
    else echo "SELFTEST FAIL clean tree flagged (rc=$rc): $out"; ok=1; fi
    # golden-true: planted direct call -> flagged with file:line
    printf '#!/bin/sh\necho x\ncodegraph index "$ROOT"\n' > "$T/scripts/planted.sh"  # codegraph-guard: allow self-test fixture text
    out="$(scan "$T")"; rc=$?
    if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'scripts/planted.sh:3'; then
        echo "SELFTEST PASS planted 'codegraph index' found at scripts/planted.sh:3"  # codegraph-guard: allow self-test fixture text
    else echo "SELFTEST FAIL planted violation missed (rc=$rc): $out"; ok=1; fi
    rm -f "$T/scripts/planted.sh"
    # golden-true: masking
    printf '#!/bin/sh\n(codegraph sync . || true)\n' > "$T/scripts/mask.sh"  # codegraph-guard: allow self-test fixture text
    out="$(scan "$T")"; rc=$?
    if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'scripts/mask.sh:2'; then
        echo "SELFTEST PASS masking '|| true' found at scripts/mask.sh:2"
    else echo "SELFTEST FAIL masking missed (rc=$rc): $out"; ok=1; fi
    # the launcher itself must not be flagged
    if printf '%s' "$out" | grep -q 'codegraph_safe.sh:'; then
        echo "SELFTEST FAIL launcher flagged: $out"; ok=1
    else echo "SELFTEST PASS codegraph_safe.sh not flagged"; fi
    rm -rf "$T"
    [ "$ok" -eq 0 ] && { echo "SELFTEST PASS"; exit 0; }
    echo "SELFTEST FAIL"; exit 1
fi

if [ "${#ROOTS[@]}" -eq 0 ]; then
    ROOTS=("$(cd "$HERE/.." && pwd)")
    parent="$(cd "$HERE/../../.." && pwd)"
    [ -d "$parent/scripts" ] && [ -d "$parent/constitution" ] && ROOTS+=("$parent/scripts")
fi
for r in "${ROOTS[@]}"; do [ -d "$r" ] || { echo "codegraph_guard: root not a directory: $r" >&2; exit 2; }; done
scan "${ROOTS[@]}"
