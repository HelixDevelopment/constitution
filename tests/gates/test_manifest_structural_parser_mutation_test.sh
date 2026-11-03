#!/usr/bin/env bash
# Paired 1.1 mutation test for tests/gates/test_manifest_structural_parser.sh: each mutant is applied to a
# sandbox COPY of the real files and the suite (TEST_CANON=<copy>) MUST fail; the unmutated copy MUST pass.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
canon="$(cd "$here/../.." && pwd)"
sb="$(mktemp -d)"; : "${sb:?}"; trap 'rm -rf -- "${sb:?}"' EXIT
rc=0
fresh() { # name -> copy dir
    local d="$sb/$1"; mkdir -p "$d/scripts/gates" "$d/scripts/lib" "$d/scripts/deps_manifest"
    cp "$canon/scripts/gates/cm_helix_deps_ref_matches_gitlink.sh" "$d/scripts/gates/"
    cp "$canon/scripts/lib/third_party_prune.sh" "$d/scripts/lib/"
    cp "$canon"/scripts/deps_manifest/helix_deps_tsv.* "$canon/scripts/deps_manifest/override_guard.sh" "$canon/scripts/deps_manifest/helix_deps_manifest.py" "$d/scripts/deps_manifest/"
    echo "$d"
}
run() { TEST_CANON="$1" nice -n 15 bash "$here/test_manifest_structural_parser.sh" >"$sb/out.txt" 2>&1; }
d="$(fresh clean)"; if run "$d"; then echo "OK   control (unmutated copy passes)"; else echo "FAIL control"; tail -5 "$sb/out.txt"; rc=1; fi
kill_check() { # name dir
    if run "$2"; then echo "FAIL mutant $1 SURVIVED"; rc=1; else echo "OK   mutant $1 killed ($(grep -c '^FAIL' "$sb/out.txt") failing checks)"; fi
}
# M1: reader reverts to a hand line parser (opener `- key:` only, fields credited to previous dep)
d="$(fresh m1)"; cat > "$d/scripts/deps_manifest/helix_deps_tsv.py" <<'PY'
import re, sys
cur = None; out = []
for line in open(sys.argv[1], encoding="utf-8", errors="replace").read().splitlines():
    m = re.match(r"^  - ([A-Za-z_]+):\s*(.*)$", line) or re.match(r"^    ([A-Za-z_]+):\s*(.*)$", line)
    if re.match(r"^  - [A-Za-z_]+:", line):
        cur = {}; out.append(cur)
    if m and cur is not None:
        cur[m.group(1)] = m.group(2).strip().strip("\"'")
for d in out:
    print("\x1f".join([d.get("name",""), d.get("path",""), d.get("ssh_url",""), d.get("ref",""), "1" if d.get("third_party")=="true" else "0"]))
PY
kill_check "M1 hand-parse" "$d"
# M2: duplicate-key rejection dropped
d="$(fresh m2)"; sed -i 's/if key in seen:/if False:/' "$d/scripts/deps_manifest/helix_deps_manifest.py"
grep -q 'if False:' "$d/scripts/deps_manifest/helix_deps_manifest.py" || { echo "FAIL M2 not applied"; rc=1; }
kill_check "M2 dup-key accepted" "$d"
# M3: independent cross-check dropped
d="$(fresh m3)"; sed -i 's/if \[ "\$cheap" != "\$n" \]; then/if false; then/' "$d/scripts/deps_manifest/helix_deps_tsv.sh"
grep -q 'if false; then' "$d/scripts/deps_manifest/helix_deps_tsv.sh" || { echo "FAIL M3 not applied"; rc=1; }
kill_check "M3 no cross-check" "$d"
# M4: reader ignores PyYAML-unavailable (switch) and keeps going = PASS on parser failure
d="$(fresh m4)"; sed -i 's/if os.environ.get("HELIX_DEPS_TSV_FORCE_NO_YAML") == "1" and os.environ.get("HELIX_TEST_MODE") == "1":/if False:/' "$d/scripts/deps_manifest/helix_deps_tsv.py"
grep -q 'if False:' "$d/scripts/deps_manifest/helix_deps_tsv.py" || { echo "FAIL M4 not applied"; rc=1; }
kill_check "M4 ignores parser unavailability" "$d"
# M5: ref gate treats a reader failure as success (empty entries fall through to a PASS-shaped result)
d="$(fresh m5)"; sed -i 's/^entries="\$(cm_hdeps_tsv "\$man")"; hrc=\$?/entries="$(cm_hdeps_tsv "$man")"; hrc=0/' "$d/scripts/gates/cm_helix_deps_ref_matches_gitlink.sh"
sed -i 's/^\[ -n "\$entries" \] || {.*$/[ -n "$entries" ] || { echo "PASS-on-failure"; exit 0; }/' "$d/scripts/gates/cm_helix_deps_ref_matches_gitlink.sh"
kill_check "M5 PASS on parser failure" "$d"
# M6: US/LF/CR rejection removed (only NUL/DEL still rejected) -> multi-line / separator values slip through
d="$(fresh m6)"; python3 - "$d/scripts/deps_manifest/helix_deps_tsv.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = "return any(ord(c) < 0x20 or ord(c) == 0x7f for c in v)"
assert old in s
open(p, "w").write(s.replace(old, "return any(ord(c) in (0, 0x7f) for c in v)"))
PY
kill_check "M6 US/LF/CR rejection removed" "$d"
# M7: back to the old reject set (US/LF/CR only) -> NUL / DEL / other C0 slip through
d="$(fresh m7)"; python3 - "$d/scripts/deps_manifest/helix_deps_tsv.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = "return any(ord(c) < 0x20 or ord(c) == 0x7f for c in v)"
assert old in s
open(p, "w").write(s.replace(old, 'return any(c in ("\\x1f", "\\n", "\\r") for c in v)'))
PY
kill_check "M7 only US/LF/CR rejected (NUL slips)" "$d"
# M8: override guard drops the HELIX_TEST_MODE requirement -> production env var swaps the parser
d="$(fresh m8)"; sed -i 's/\[ "\${HELIX_TEST_MODE:-}" = "1" \] && //' "$d/scripts/deps_manifest/override_guard.sh"
grep -qF '"${HELIX_TEST_MODE:-}" = "1"' "$d/scripts/deps_manifest/override_guard.sh" && { echo "FAIL M8 not applied"; rc=1; }
kill_check "M8 override honoured without test mode" "$d"
# M9: FORCE_NO_YAML honoured without HELIX_TEST_MODE
d="$(fresh m9)"; sed -i 's/ and os.environ.get("HELIX_TEST_MODE") == "1":/:/' "$d/scripts/deps_manifest/helix_deps_tsv.py"
grep -qF 'and os.environ.get("HELIX_TEST_MODE")' "$d/scripts/deps_manifest/helix_deps_tsv.py" && { echo "FAIL M9 not applied"; rc=1; }
kill_check "M9 FORCE_NO_YAML honoured without test mode" "$d"
# M10 (F5): reader promotes ANY nested `- name:` item (a list inside a dep) to a dep of its own
d="$(fresh m10)"; cat > "$d/scripts/deps_manifest/helix_deps_tsv.py" <<'PY'
import re, sys
out = []; cur = None
for line in open(sys.argv[1], encoding="utf-8", errors="replace").read().splitlines():
    if re.match(r"^\s*- name:", line):
        cur = {}; out.append(cur)
    m = re.match(r"^\s+-?\s*([A-Za-z_]+):\s*(.*)$", line)
    if m and cur is not None:
        cur[m.group(1)] = m.group(2).strip().strip("\"'")
for d in out:
    print("\x1f".join([d.get("name",""), d.get("path",""), d.get("ssh_url",""), d.get("ref",""), "1" if d.get("third_party")=="true" else "0"]))
PY
kill_check "M10 nested list item promoted to a dep" "$d"
[ "$rc" = 0 ] && echo "== all mutants killed ==" || echo "== MUTATION TEST FAILED =="
exit "$rc"
