#!/bin/bash
# Purpose : Regression for canon self-scan item 3 (docs/design/canon_self_scan_triage_2026_10_31.md):
#           guard-destructive-paths.py ignored NUL bytes, but a shell reading stdin DROPS them, so
#           `rm -rf /ho<NUL>me` (JSON \u0000) executes as `rm -rf /home` while the guard allowed it
#           (measured RED: rc=0 for Bash and for a Write of a script). realpath() raising ValueError on a
#           NUL was swallowed by `except Exception: return None`, the silent default under review.
#           Contract: the NUL-stripped text the shell would run is analysed too; a destructive command
#           under NUL padding is blocked (rc 2); benign NUL text is not (no false positive); an
#           unexpected exception inside realpath handling fails closed (rc 2) instead of silently allowing.
# Test types: unit-ish (direct real_alias), e2e (real hook invocation), security, chaos (NUL placements),
#           determinism x3, idempotency, paired §1.1 mutation (strip line removed; broad except restored+fault).
# Usage   : bash test_guard_nul_regression.sh   exit 0 = all hold.
set -u
export CONSTITUTION_JEV_HOOK=off
HERE=$(cd "$(dirname "$0")" && pwd)
G="$HERE/guard-destructive-paths.py"
TMP=$(mktemp -d); trap 'rm -rf "${TMP:?}"' EXIT
fail=0
chk() { if [ "$2" = 1 ]; then echo "ok $1"; else echo "NOT ok $1"; fail=1; fi; }
rc_of() { # guard-path json -> rc
  printf '%s' "$2" | nice -n 15 python3 "$1" >/dev/null 2>&1; echo $?
}
bash_json() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"/tmp"}' "$1"; }
write_json() { printf '{"tool_name":"Write","tool_input":{"file_path":"/tmp/z.sh","content":"#!/bin/bash\\n%s\\n"}}' "$1"; }

# security: destructive command under NUL padding is blocked
for c in 'rm -rf /ho\u0000me' 'rm -rf /home\u0000/' 'rm -rf \u0000/home' 'rm -rf /h\u0000o\u0000me'; do
  chk "bash block [$c]" "$([ "$(rc_of "$G" "$(bash_json "$c")")" = 2 ] && echo 1)"
  chk "write block [$c]" "$([ "$(rc_of "$G" "$(write_json "$c")")" = 2 ] && echo 1)"
done
# chaos / false-positive guard: benign NUL text and NUL-free baseline
chk "benign NUL text allowed" "$([ "$(rc_of "$G" "$(bash_json 'echo hi\u0000there')")" = 0 ] && echo 1)"
chk "benign NUL in tmp delete allowed" "$([ "$(rc_of "$G" "$(bash_json 'rm -rf /tmp/zz\u0000/build')")" = 0 ] && echo 1)"
chk "baseline rm -rf /home still blocked" "$([ "$(rc_of "$G" "$(bash_json 'rm -rf /home')")" = 2 ] && echo 1)"
# determinism x3 + idempotency (same payload, same verdict, no state)
d=1; for i in 1 2 3; do [ "$(rc_of "$G" "$(bash_json 'rm -rf /ho\u0000me')")" = 2 ] || d=0; done
chk "determinism x3" "$d"
# fail-closed on an unexpected realpath exception (integration through a real hook run with a fault injected
# in a sandbox copy of the guard: realpath raises RuntimeError -> must BLOCK, not silently allow)
cp "$G" "$TMP/g.py"; cp "$HERE"/*.list "$TMP/" 2>/dev/null; cp "$HERE/../lib/protected_paths.list" "$TMP/" 2>/dev/null
python3 - "$TMP/g.py" <<'P'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("import sys", "import sys\nimport os as _os\n_real = _os.path.realpath\ndef _boom(*a, **k):\n    raise RuntimeError('injected')\n", 1)
s = s.replace("def real_alias(path):", "def real_alias(path):\n    _os.path.realpath = _boom\n", 1)
open(p, "w").write(s)
P
chk "unexpected realpath exception fails closed (rc 2)" "$([ "$(rc_of "$TMP/g.py" "$(bash_json 'rm -rf /tmp/inject')")" = 2 ] && echo 1)"
# paired mutation 1: remove the NUL-strip line -> the NUL attack is allowed again (detected)
python3 - "$G" "$TMP/m1.py" <<'P'
import sys
s = open(sys.argv[1]).read()
a = 'texts = texts + [t.replace("\\0", "") for t in texts if "\\0" in t]'
assert a in s
open(sys.argv[2], "w").write(s.replace(a, "pass"))
P
cp "$HERE/../lib/protected_paths.list" "$TMP/" 2>/dev/null
chk "mutation: strip line removed -> NUL attack allowed (mutant killed by this suite)" "$([ "$(rc_of "$TMP/m1.py" "$(bash_json 'rm -rf /ho\u0000me')")" = 0 ] && echo 1)"
# paired mutation 2: broad except restored -> injected fault silently allowed (mutant killed)
python3 - "$G" "$TMP/m2.py" <<'P'
import sys
s = open(sys.argv[1]).read()
n = s.count("except (ValueError, OSError):")
assert n >= 2
s = s.replace("except (ValueError, OSError):", "except Exception:")
s = s.replace("import sys", "import sys\nimport os as _os\ndef _boom(*a, **k):\n    raise RuntimeError('injected')\n", 1)
s = s.replace("def real_alias(path):", "def real_alias(path):\n    _os.path.realpath = _boom\n", 1)
open(sys.argv[2], "w").write(s)
P
chk "mutation: broad except restored -> injected fault silently allowed" "$([ "$(rc_of "$TMP/m2.py" "$(bash_json 'rm -rf /tmp/inject')")" = 0 ] && echo 1)"
[ $fail = 0 ] && echo "ALL OK" || echo "FAILED"
exit $fail
