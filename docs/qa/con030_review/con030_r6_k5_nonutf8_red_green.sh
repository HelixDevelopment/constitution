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
case $w in "${TMPDIR:-/tmp}"/*) rm -rf -- "${w:?}";; esac
