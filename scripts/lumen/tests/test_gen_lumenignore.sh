#!/usr/bin/env bash
# Black-box test for gen_lumenignore.py, validated through the REAL lumen walker.
# Builds a fixture repo, generates .lumenignore, runs `lumen index` against a
# stub embedder, and asserts the exact set of files lumen indexed.
# Usage: LUMEN_BIN=/path/to/lumen bash test_gen_lumenignore.sh   (exit 0 = PASS)
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
GEN="$HERE/../gen_lumenignore.py"
LUMEN_BIN=${LUMEN_BIN:-$(ls -d "$HOME"/.claude-shared/plugins/cache/claude-plugins-official/lumen/*/bin/lumen-linux-amd64 2>/dev/null | tail -1)}
[ -x "$LUMEN_BIN" ] || { echo "SKIP: lumen binary not found"; exit 2; }
W=$(mktemp -d "${TMPDIR:-/tmp}/lumenignore_test.XXXXXX"); FP=""
cleanup() { [ -n "$FP" ] && kill "$FP" 2>/dev/null; rm -rf "$W"; }
trap cleanup EXIT
fail=0; ok() { echo "PASS: $*"; }; bad() { echo "FAIL: $*"; fail=1; }

R=$W/repo; mkdir -p "$R"/{src_first,third,dev/keep/big_data,dev/drop,docs/qa}
echo "# readme" > "$R/README.md"
printf 'package a\nfunc A() int { return 1 }\n' > "$R/src_first/a.go"
printf 'package b\nfunc B() int { return 2 }\n' > "$R/third/b.go"
printf 'def c():\n    return 3\n' > "$R/dev/keep/c.py"
printf 'def d():\n    return 4\n' > "$R/dev/drop/d.py"
echo '{"k": 1}' > "$R/dev/keep/big_data/e.json"
echo 'function f(){return 5}' > "$R/dev/keep/gen.min.js"
echo "# x" > "$R/docs/x.md"; echo '{"r": 1}' > "$R/docs/qa/r.json"; echo "# n" > "$R/docs/qa/n.md"
cat > "$W/scope.json" <<'EOF'
{"allow": ["src_first", "dev/keep", "docs"],
 "deny": ["dev/keep/big_data/", "**/*.min.js", "docs/qa/**/*.json"],
 "root_files": true}
EOF

# 1. generator runs and is deterministic
python3 "$GEN" --repo "$R" --scope "$W/scope.json" --out "$W/a.ignore" || bad "generator exit"
python3 "$GEN" --repo "$R" --scope "$W/scope.json" --out "$W/b.ignore"
cmp -s "$W/a.ignore" "$W/b.ignore" && ok "deterministic output" || bad "non-deterministic output"
cp "$W/a.ignore" "$R/.lumenignore"

# 2. no catch-all pattern (lumen would refuse the root)
grep -qxE '\*|\*\*|\*\*/\*|/\*' "$R/.lumenignore" && bad "catch-all pattern emitted" || ok "no catch-all pattern"

# 3. real lumen walk: exact indexed set
PORT=$((20000 + RANDOM % 20000))
python3 "$HERE/fake_ollama.py" "$PORT" testmodel 8 >/dev/null 2>&1 & FP=$!
for _ in $(seq 50); do curl -s "http://127.0.0.1:$PORT/api/tags" >/dev/null && break; sleep 0.1; done
env XDG_DATA_HOME="$W/xdg" XDG_CONFIG_HOME="$W/cfg" OLLAMA_HOST="http://127.0.0.1:$PORT" \
    LUMEN_EMBED_MODEL=testmodel LUMEN_EMBED_DIMS=8 LUMEN_EMBED_CTX=512 \
    "$LUMEN_BIN" index "$R" > "$W/index.out" 2>&1 || { bad "lumen index failed: $(tail -2 "$W/index.out")"; }
DB=$(find "$W/xdg" -name index.db | head -1)
python3 -c "import sqlite3,sys;[print(r[0]) for r in sqlite3.connect(sys.argv[1]).execute('select relative_path from project_files order by 1')]" "$DB" > "$W/got.txt" 2>/dev/null
printf '%s\n' README.md dev/keep/c.py docs/qa/n.md docs/x.md src_first/a.go | sort > "$W/want.txt"
sort -o "$W/got.txt" "$W/got.txt"
# control needle: the instrument must see a file we know is indexed
grep -qx src_first/a.go "$W/got.txt" && ok "control needle visible" || bad "control needle missing (instrument blind)"
if cmp -s "$W/want.txt" "$W/got.txt"; then ok "lumen indexed exactly the scoped set"; else bad "indexed set differs: $(diff "$W/want.txt" "$W/got.txt" | tr '\n' ' ')"; fi
[ $fail -eq 0 ] && echo "RESULT: PASS" || echo "RESULT: FAIL"
exit $fail
