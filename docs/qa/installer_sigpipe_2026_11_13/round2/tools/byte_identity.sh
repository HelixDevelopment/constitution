#!/usr/bin/env bash
# byte_identity.sh BASE_ROOT NEW_ROOT — every here-document of the base became a single-quoted literal in round 2;
# this shows the text the scripts produce or run is byte for byte the same. Read-only: runs only --help, --version
# and --print-snippets of the installer (no network, nothing written), sources the installer in library mode to call
# two table functions, and compares the two embedded Python programs as text (they are not run).
# Output: one line per item, SAME or DIFFERS (with sizes). Exit 0 when every item is SAME, 1 otherwise, 2 on a usage
# or read error.
set -u
base="${1:?BASE_ROOT}"; new="${2:?NEW_ROOT}"
sb="$(mktemp -d "${TMPDIR:-/tmp}/bid.XXXXXX")" || exit 2
bad=0
same() { # label file-a file-b
  if cmp -s "$2" "$3"; then printf 'SAME     %-58s %s bytes\n' "$1" "$(wc -c <"$2" | tr -d ' ')"
  else printf 'DIFFERS  %-58s base %s bytes, new %s bytes\n' "$1" "$(wc -c <"$2" | tr -d ' ')" "$(wc -c <"$3" | tr -d ' ')"; bad=1; fi
}
for flag in --help --version --print-snippets; do
  for side in base new; do
    if [ "$side" = base ]; then r="$base"; else r="$new"; fi
    (cd "$sb" && env -i PATH="$PATH" HOME="$sb" LC_ALL=C.UTF-8 bash "$r/scripts/install_constitution.sh" "$flag" >"$sb/$side.out" 2>&1; echo "rc=$?" >>"$sb/$side.out")
  done
  same "install_constitution.sh $flag (output and exit status)" "$sb/base.out" "$sb/new.out"
done
for fn in hi_upstream_table hi_agent_table; do
  for side in base new; do
    if [ "$side" = base ]; then r="$base"; else r="$new"; fi
    env -i PATH="$PATH" HOME="$sb" LC_ALL=C.UTF-8 HELIX_INSTALLER_LIB_MODE=1 \
      bash -c '. "$1" >/dev/null 2>&1 || exit 9; "$2"' _ "$r/scripts/install_constitution.sh" "$fn" >"$sb/$side.out" 2>&1
    echo "rc=$?" >>"$sb/$side.out"
  done
  same "install_constitution.sh $fn (library mode)" "$sb/base.out" "$sb/new.out"
done
# The two Python programs. The base reads them from a here-document. Round 2 passes them as an argument: the
# action-prefix program is the single-quoted literal assigned to prog (unquoted the way bash does); the installer's
# hi_parse_stream program is the literal after `python3 -I -c '` (commit 3: no quote character inside, so the gate can
# read it). A program whose text differs is also RUN, base and new, on a fixture corpus (fixed files and 400 lines
# generated with a fixed seed); its line counts as SAME OUTPUT only when every output and exit status is equal, and
# the differing lines are printed. The action-prefix program is compared as text only (it writes files).
python3 -I - "$base" "$new" "$sb" <<'PY' || bad=1
import difflib, os, random, subprocess, sys
base, new, sb = sys.argv[1:4]

def heredoc_body(path, opener, tag):
    t = open(path, encoding="utf-8").read()
    i = t.index(opener)
    i = t.index("\n", i) + 1
    j = t.index("\n" + tag + "\n", i)
    return t[i:j + 1]

def unquote_from(t, i):
    out, q = [], False
    while True:
        c = t[i]
        if not q and c in "\n ":
            break
        if c == "'":
            q = not q
            i += 1
            continue
        if not q and c == "\\":
            out.append(t[i + 1])
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)

def prog_literal(path):
    t = open(path, encoding="utf-8").read()
    return unquote_from(t, t.index("prog=", t.index("local prog")) + len("prog="))

def c_literal(path, fn):
    t = open(path, encoding="utf-8").read()
    k = t.index("python3 -I -c '", t.index(fn + "() {")) + len("python3 -I -c ")
    return unquote_from(t, k)

def corpus():
    d = os.path.join(sb, "corpus"); os.makedirs(d, exist_ok=True)
    fixed = [
        b"",
        b'{"type":"system","subtype":"init","session_id":"s1"}\n{"type":"result","subtype":"success","is_error":false,"session_id":"s1","total_cost_usd":0.1234567}\n',
        b'{"type":"result","subtype":"error_max_turns","is_error":true,"session_id":"s2","total_cost_usd":3}\n',
        b'{"api_error_status": 429}\n', b'{"apiErrorStatus":429}\n', b'{"api_errorStatus" : 429}\n',
        b'{"api_error_status":  4290}\n', b'{\\"api_error_status\\": 429}\n', b"{'api_error_status': 429}\n",
        b'{"API_ERROR_STATUS": 429}\n', b'x "api_error_status"\t:\n429\n', b'[1,2]\n"str"\n{\n',
        b'{"type":"result","is_error":false,"subtype":"success","total_cost_usd":true}\n',
        b'{"type":"result","is_error":false,"subtype":"success","total_cost_usd":-1}\n',
        b'{"type":"result","is_error":false,"subtype":"success","total_cost_usd":1e-9}\n',
        b'{"type":"result","is_error":false,"subtype":"success","total_cost_usd":"0.5"}\n',
        b'\xff\xfe{"type":"result"}\n{"type":"system","subtype":"init","session_id":null}\n',
        b'{"type":"result","is_error":false,"subtype":"success","session_id":"late"}\n' * 3,
        (b'{"type":"assistant","message":"x"}\n' * 20000) + b'{"apiErrorStatus": 429}\n',
    ]
    names = []
    for n, data in enumerate(fixed):
        p = os.path.join(d, "fixed_%02d.jsonl" % n); open(p, "wb").write(data); names.append(p)
    rnd = random.Random(20261114)
    parts = ['"api_error_status"', '"apiErrorStatus"', '"api_errorStatus"', '"APIerrorStatus"', ":", " : ", "429", "4290",
             "428", '\\"', "'", '{"type":"result"', '{"type":"system","subtype":"init"', ',"session_id":"r"', ',"is_error":false',
             ',"subtype":"success"', ',"total_cost_usd":0.25', "}", "[", "]", "null", " ", "\t"]
    for n in range(4):
        lines = ["".join(rnd.choice(parts) for _ in range(rnd.randint(1, 8))) for _ in range(100)]
        p = os.path.join(d, "random_%d.jsonl" % n); open(p, "w", encoding="utf-8").write("\n".join(lines) + "\n"); names.append(p)
    return names

def run(prog, f):
    r = subprocess.run([sys.executable, "-I", "-c", prog, f], stdin=subprocess.DEVNULL, capture_output=True)
    return r.returncode, r.stdout, r.stderr

bad = 0
files = None
for label, rel, opener, tag, fn in (
        ("install_constitution.sh hi_parse_stream Python program", "scripts/install_constitution.sh", "<<'PY'", "PY", "hi_parse_stream"),
        ("install_action_prefix.sh merge_with_python program", "scripts/install_action_prefix.sh", "<<'PYEOF'", "PYEOF", None)):
    a = heredoc_body(base + "/" + rel, opener, tag)
    b = c_literal(new + "/" + rel, fn) if fn else prog_literal(new + "/" + rel)
    if a == b:
        print("SAME     %-58s %d bytes" % (label, len(a.encode("utf-8"))))
        continue
    diff = [l.rstrip("\n") for l in difflib.unified_diff(a.splitlines(True), b.splitlines(True), "base", "new", n=0)
            if l[:1] in "+-" and not l.startswith(("+++", "---"))]
    if fn is None:
        bad = 1
        print("DIFFERS  %-58s base %d bytes, new %d bytes" % (label, len(a), len(b)))
        for l in diff: print("         " + l)
        continue
    files = files or corpus()
    diffs = [f for f in files if run(a, f) != run(b, f)]
    if diffs:
        bad = 1
        print("DIFFERS  %-58s text differs and the output differs on %d of %d fixtures: %s"
              % (label, len(diffs), len(files), ", ".join(os.path.basename(x) for x in diffs)))
    else:
        print("SAME OUTPUT %-55s text differs in %d line(s); output and exit status equal on all %d fixtures"
              % (label, len(diff) // 2, len(files)))
    for l in diff: print("         " + l)
sys.exit(bad)
PY
rm -rf -- "${sb:?}"
exit "$bad"
