#!/usr/bin/env bash
# CON-030 review r5 F10: the K5 RED/GREEN, replayable. gen_fingerprint() of an engine, on a root whose generated set
# holds a file named with the byte 0xff (not UTF-8). Usage: bash this.sh <engine.py>...  (one line of output each)
set -u
w=$(mktemp -d); : "${w:?}"
python3 -I - "$w" <<'PY'
import os, sys
w = os.fsencode(sys.argv[1])
d = os.path.join(w, b"actions", b"generated"); os.makedirs(d)
open(os.path.join(d, b"name_\xff.txt"), "wb").write(b"x\n")
PY
for e in "$@"; do
  printf '== %s\n' "$e"
  python3 -I - "$e" "$w" <<'PY' 2>&1 | tail -3
import importlib.util, sys
s = importlib.util.spec_from_file_location("e", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
print("GENERATED_SETS has actions/generated:", "actions/generated" in m.GENERATED_SETS)
print(repr(m.gen_fingerprint(sys.argv[2])))
PY
done
# CON-030 r7 (review r6 G7): the scratch directory is removed only through safe_rm_rf (constitution section 11.4.287);
# if the helper cannot be loaded, the directory is left in place and named
lib="$(cd "$(dirname "$0")/../../.." && pwd)/scripts/lib/safe_rm.sh"
if [ -r "$lib" ] && . "$lib" && command -v safe_rm_rf >/dev/null 2>&1; then
  safe_rm_rf "${w:?}" || echo "left in place: $w (safe_rm_rf refused it)" >&2
else
  echo "left in place: $w (scripts/lib/safe_rm.sh not found)" >&2
fi
