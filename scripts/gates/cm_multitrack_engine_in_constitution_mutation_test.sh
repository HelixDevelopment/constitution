#!/usr/bin/env bash
# cm_multitrack_engine_in_constitution_mutation_test.sh — §1.1 paired-mutation
# meta-test for CM-MULTITRACK-ENGINE-IN-CONSTITUTION (§11.4.187).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Proves CM-MULTITRACK-ENGINE-IN-CONSTITUTION is NOT a bluff gate across all
# three of its invariants (presence / decoupling / parseability), AND proves
# its narrow self-referential-comment exemption (documented in the gate's own
# header) does NOT mask a real violation:
#
#   1a. CLEAN fixture (generic scripts, incl. a comment that self-documents
#       "no atmosphere literal here" — exercising the exemption) → PASS.
#   1b. Too-few-scripts fixture (below --min-scripts) → PRESENCE FAILs.
#   2a. Real-literal-in-code fixture (a NON-comment line embeds a
#       track-mount+basename coupling literal in actual code) → DECOUPLING FAILs.
#   2b. Comment-only "atmosphere" mention (mirroring the real
#       multitrack_bootstrap.sh:107 case) → still PASSes (proves the
#       exemption fires correctly and is not itself a bluff-through).
#   3.  Parse-broken fixture (unbalanced quote) → PARSEABILITY FAILs.
#   4a. A python-declaring script whose content is valid python but INVALID
#       shell (the exact shape of the real agent_label_frontmatter_check.py:
#       `MODELS = ("sonnet", "opus")`) → PASSes (RED before the gate learned
#       python: `sh -n` was demanded of a declared-python script).
#   4b. A python-declaring script with a python syntax error → FAILs (the
#       python parse is a real parse, not a skip).
#   4c. Negative control: a bash-declaring script carrying that same
#       python-only content → still FAILs (the python rule did not relax the
#       bash/sh rule), and a `#!/bin/sh` one likewise.
#   4d. `#!/usr/bin/env -S python3 -I` (env options) is read as python; a
#       python-declaring script on a host with NO python3 FAILs (fail closed,
#       never a silent skip).
#   5.  (independent review round 1) COMPILE-stage errors that `ast.parse` accepts but
#       python3 itself refuses before running a line (top-level return / break /
#       continue / yield / await, a bad nonlocal, global-after-use, a misplaced or
#       impossible `from __future__`, `def f(a, a)`) FAIL with exit 1; each fixture
#       carries a control needle (ast.parse accepts it, compile() rejects it).
#   6.  env options that take an ARGUMENT (-u X, -C X, -P X, --unset X, --chdir X) are
#       skipped before the interpreter word is read; the python match is exactly
#       python | pythonN | pythonN.M... (not python3-config, not pythonista, not a
#       `# python` comment on a `#!/bin/sh` line).
#   7.  The python leg is isolated: a PYTHONPATH sitecustomize and a planted ast.py
#       in the working directory are never executed (each with a control needle
#       proving the vector works on this host).
#   8.  A temp file that cannot be created (TMPDIR unusable) is exit 2 with a
#       message, never a false parse failure (exit 1).
#   9.  GATE-MUTANT discrimination: a mutated copy of the gate (parser back to
#       ast.parse; -I dropped; `python*` or `python[0-9]*` widened; any-shebang-mentions-
#       python; env argument skip removed; mktemp failure ignored) must be caught by
#       at least one case above. A surviving mutant is a META FAIL.
#  10.  The harness: expect_fail itself refuses exit 0, exit 2 and a crash code (stub gates).
#   Every expect_fail asserts exit 1 exactly (the documented "invariant violated"):
#   exit 2 or a crash is not a correct FAIL.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_multitrack_engine_in_constitution_mutation_test.sh
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Creates + removes a temp fixture dir under $TMPDIR (trap-cleaned on EXIT).
#   No network, no commit, no mutation of the real engine tree.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, sh, the sibling cm_multitrack_engine_in_constitution.sh gate script.
#   Parses clean under bash -n.
#
# ── Cross-references ──────────────────────────────────────────────────────────
#   §1.1 (paired mutation), §11.4.187, §11.4.28(B)/§11.4.177 (decoupling),
#   §11.4.67 (target-shell-parseability).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — every sub-case produced the expected PASS/FAIL verdict.
#   1 — at least one sub-case produced the wrong verdict (bluff or false alarm).
#   2 — environment error (the gate script missing).
#
# Classification: universal (§11.4.17).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE="${SCRIPT_DIR}/cm_multitrack_engine_in_constitution.sh"

[ -f "$GATE" ] || { echo "META: gate script missing: $GATE" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cm_mtec_mut.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

rc=0
note() { echo "$@"; }
expect_fail() {   # the gate must exit 1 EXACTLY (invariant violated): exit 0 is a bluff, exit 2 / a crash is another failure
    local desc="$1" r; shift
    "$@" >/dev/null 2>&1; r=$?
    if [ "$r" -eq 1 ]; then
        note "✅ META OK:   ${desc} — gate correctly FAILed on the mutation"
    elif [ "$r" -eq 0 ]; then
        note "❌ META FAIL: ${desc} — gate PASSed on a planted violation (bluff gate!)"
        rc=1
    else
        note "❌ META FAIL: ${desc} — gate exited ${r}, not the documented 1 (environment error or crash, not a verdict)"
        rc=1
    fi
}
expect_pass() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        note "✅ META OK:   ${desc} — gate correctly PASSed"
    else
        note "❌ META FAIL: ${desc} — gate FAILed unexpectedly (false alarm!)"
        rc=1
    fi
}

echo "======================================================================"
echo "§1.1 paired-mutation meta-test for CM-MULTITRACK-ENGINE-IN-CONSTITUTION"
echo "fixtures under: $TMP"
echo "======================================================================"

# --- 1a/2b. CLEAN fixture: generic scripts + a self-referential exemption
#            comment (mirrors the real multitrack_bootstrap.sh:107 case) ---
CLEAN="$TMP/engine_clean"
mkdir -p "$CLEAN"
cat > "$CLEAN/multitrack_config.sh" <<'SH'
#!/usr/bin/env bash
# Generic config loader — project-agnostic (no project literal here;
# consuming projects supply config/multitrack/<hostname>.yaml as DATA).
set -euo pipefail
echo "load config"
SH
cat > "$CLEAN/multitrack_resolve_worktree.sh" <<'SH'
#!/usr/bin/env bash
# §11.4.28(B) / §11.4.177 (project-agnostic — no `atmosphere` literal here;
# this comment exists purely to exercise the gate's exemption clause).
set -euo pipefail
echo "resolve"
SH
cat > "$CLEAN/multitrack-up" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "up"
SH
chmod +x "$CLEAN"/multitrack_config.sh "$CLEAN"/multitrack_resolve_worktree.sh "$CLEAN"/multitrack-up
expect_pass "clean fixture (3 scripts, exemption comment present)" \
    bash "$GATE" --engine-dir "$CLEAN" --quiet

# --- 1b. Too-few-scripts fixture ---
FEW="$TMP/engine_few"
mkdir -p "$FEW"
cat > "$FEW/multitrack_config.sh" <<'SH'
#!/usr/bin/env bash
echo "only one script here"
SH
chmod +x "$FEW/multitrack_config.sh"
expect_fail "too-few-scripts fixture (1 < min-scripts 3)" \
    bash "$GATE" --engine-dir "$FEW" --min-scripts 3 --quiet

# --- 2a. Real-literal-in-code fixture: a NON-comment line embeds the
#         project-coupled mount+basename combination ---
MUT_LIT="$TMP/engine_literal_mut"
mkdir -p "$MUT_LIT"
cp -r "$CLEAN"/. "$MUT_LIT"/
# Build the 2a payload from split tokens so THIS test script does not itself
# statically embed the coupling literal (the §11.4.28(B) audit would flag it) —
# the assembled literal lands in the FIXTURE, which the gate under test must
# still catch on a non-comment code line.
_mut_lit="/mnt/track1/atmo""sphere-t1"
{
    printf '%s\n' '# MUTATION: a real (non-comment) project path'
    printf 'ROOT_OVERRIDE="%s"\n' "$_mut_lit"
    printf '%s\n' 'echo "$ROOT_OVERRIDE"'
} >> "$MUT_LIT/multitrack_config.sh"
expect_fail "real-literal-in-code fixture (/mnt/track1/atmosphere-t1 hardcoded)" \
    bash "$GATE" --engine-dir "$MUT_LIT" --quiet

# --- 3. Parse-broken fixture (unbalanced quote) ---
MUT_PARSE="$TMP/engine_parse_mut"
mkdir -p "$MUT_PARSE"
cp -r "$CLEAN"/. "$MUT_PARSE"/
cat >> "$MUT_PARSE/multitrack-up" <<'SH'
echo "unbalanced quote
SH
expect_fail "parse-broken fixture (unbalanced quote)" \
    bash "$GATE" --engine-dir "$MUT_PARSE" --quiet

# --- 4a. python-declaring script: valid python, INVALID shell ---
PY_OK="$TMP/engine_py_ok"
mkdir -p "$PY_OK"
cp -r "$CLEAN"/. "$PY_OK"/
cat > "$PY_OK/agent_label_check.py" <<'PYSRC'
#!/usr/bin/env python3
"""generic python helper shipped in the engine directory."""
MODELS = ("sonnet", "opus")
print(MODELS)
PYSRC
chmod +x "$PY_OK/agent_label_check.py"
# the control needle for 4a: the SAME content under `sh -n` really fails, so the PASS below is the interpreter choice, not a blind check
if sh -n "$PY_OK/agent_label_check.py" >/dev/null 2>&1; then
    note "❌ META FAIL: 4a control needle — sh -n accepted the python content (the fixture cannot discriminate)"
    rc=1
else
    note "✅ META OK:   4a control needle — sh -n rejects the python-only content (the fixture discriminates)"
fi
expect_pass "python-declaring script (valid python, invalid shell) is parsed as python" \
    bash "$GATE" --engine-dir "$PY_OK" --quiet

# --- 4b. python-declaring script with a python syntax error ---
PY_BAD="$TMP/engine_py_bad"
mkdir -p "$PY_BAD"
cp -r "$PY_OK"/. "$PY_BAD"/
printf '%s\n' 'def broken(:' >> "$PY_BAD/agent_label_check.py"
expect_fail "python-declaring script with a python syntax error" \
    bash "$GATE" --engine-dir "$PY_BAD" --quiet

# a file that FAILED to parse never gets a "clean" line (non-quiet run; control needle: the python-ok fixture prints one)
pybad_out="$(bash "$GATE" --engine-dir "$PY_BAD" 2>&1 || true)"
pyok_out="$(bash "$GATE" --engine-dir "$PY_OK" 2>&1 || true)"
if grep -qF '✅ PARSEABILITY: agent_label_check.py clean' <<<"$pyok_out" \
   && ! grep -qF '✅ PARSEABILITY: agent_label_check.py clean' <<<"$pybad_out"; then
    note "✅ META OK:   a file that failed to parse gets no 'clean' line (and a clean one does)"
else
    note "❌ META FAIL: 'clean' line missing for a clean file, or printed for a file that failed to parse"
    rc=1
fi

# --- 4c. negative controls: the python rule does not relax bash / sh ---
for decl in '#!/usr/bin/env bash' '#!/bin/sh'; do
    NEG="$TMP/engine_neg_$(printf '%s' "$decl" | tr -c 'a-z' '_')"
    mkdir -p "$NEG"
    cp -r "$CLEAN"/. "$NEG"/
    { printf '%s\n' "$decl"; printf '%s\n' 'MODELS = ("sonnet", "opus")'; } > "$NEG/not_really_python.sh"
    chmod +x "$NEG/not_really_python.sh"
    expect_fail "negative control: '${decl}' script carrying python-only content still FAILs" \
        bash "$GATE" --engine-dir "$NEG" --quiet
done

# --- 4d. env options before the interpreter word; fail closed when python3 is absent ---
PY_ENV="$TMP/engine_py_env"
mkdir -p "$PY_ENV"
cp -r "$CLEAN"/. "$PY_ENV"/
{ printf '%s\n' '#!/usr/bin/env -S python3 -I'; printf '%s\n' 'MODELS = ("sonnet", "opus")'; } > "$PY_ENV/env_option_check.py"
chmod +x "$PY_ENV/env_option_check.py"
expect_pass "'#!/usr/bin/env -S python3 -I' is read as python" \
    bash "$GATE" --engine-dir "$PY_ENV" --quiet
NOPY="$TMP/nopy_path"
mkdir -p "$NOPY"
for t in bash sh head find grep sort tr sed cat rm mktemp dirname basename readlink; do
    p="$(command -v "$t" 2>/dev/null)" && [ -n "$p" ] && ln -sf "$p" "$NOPY/$t"
done
# control needle for the next case: the SAME minimal PATH runs the gate green on the python-free CLEAN fixture, so the
# FAIL below is the missing python3 and nothing else
expect_pass "minimal no-python3 PATH still runs the gate green on a python-free engine (control needle)" \
    env PATH="$NOPY" "$NOPY/bash" "$GATE" --engine-dir "$CLEAN" --quiet
expect_fail "python-declaring script on a host with no python3 fails closed" \
    env PATH="$NOPY" "$NOPY/bash" "$GATE" --engine-dir "$PY_OK" --quiet
# ... and it fails FOR THAT REASON (the verdict line names the missing interpreter), not by chance
# (output captured first and matched with a here-string: `cmd | grep -q` under pipefail is the SIGPIPE class, 11.4.276(C))
nopy_out="$(env PATH="$NOPY" "$NOPY/bash" "$GATE" --engine-dir "$PY_OK" --quiet 2>&1 || true)"
if grep -qF 'cannot verify a python-declaring script' <<<"$nopy_out"; then
    note "✅ META OK:   no-python3 failure names the missing interpreter (cannot verify a python-declaring script)"
else
    note "❌ META FAIL: no-python3 failure does not name the missing interpreter (failed for another reason, or silently)"
    rc=1
fi

# --- 5. compile-stage errors: ast.parse accepts them, python3 refuses them before running a line ---
py_ast_accepts() { python3 -I -c 'import ast, sys; ast.parse(open(sys.argv[1], "rb").read(), sys.argv[1])' "$1" >/dev/null 2>&1; }
py_compile_rejects() { ! python3 -I -c 'import sys; compile(open(sys.argv[1], "rb").read(), sys.argv[1], "exec", dont_inherit=True)' "$1" >/dev/null 2>&1; }
CS_NAMES="ret brk cont yld awt nonl glob fut brace dup"
cs_body() {
    case "$1" in
        ret)   printf '%s\n' 'return 1' ;;
        brk)   printf '%s\n' 'break' ;;
        cont)  printf '%s\n' 'continue' ;;
        yld)   printf '%s\n' 'yield 1' ;;
        awt)   printf '%s\n' 'await foo()' ;;
        nonl)  printf '%s\n' 'def f():' '    nonlocal q' ;;
        glob)  printf '%s\n' 'x = 1' 'def f():' '    x = 2' '    global x' ;;
        fut)   printf '%s\n' 'import os' 'from __future__ import annotations' ;;
        brace) printf '%s\n' 'from __future__ import braces' ;;
        dup)   printf '%s\n' 'def f(a, a):' '    pass' ;;
    esac
}
for n in $CS_NAMES; do
    D="$TMP/engine_cs_$n"; mkdir -p "$D"; cp -r "$CLEAN"/. "$D"/
    { printf '%s\n' '#!/usr/bin/env python3'; cs_body "$n"; } > "$D/cs_$n.py"; chmod +x "$D/cs_$n.py"
done
# the control needle of every fixture: the parser alone accepts it, the compiler rejects it (so only a compile() leg can catch it)
cs_needle_ok=1
for n in $CS_NAMES; do
    if ! py_ast_accepts "$TMP/engine_cs_$n/cs_$n.py" || ! py_compile_rejects "$TMP/engine_cs_$n/cs_$n.py"; then
        note "❌ META FAIL: 5 control needle '$n' — ast.parse must accept and compile() must reject the fixture"; rc=1; cs_needle_ok=0
    fi
done
[ "$cs_needle_ok" -eq 0 ] || note "✅ META OK:   5 control needles — all $(wc -w <<<"$CS_NAMES") compile-stage fixtures: ast.parse accepts, compile() rejects"
cs_one() { # $1=gate $2=name : exit 1 and a PARSEABILITY failure naming the compile leg
    local o r; o="$(bash "$1" --engine-dir "$TMP/engine_cs_$2" --quiet 2>&1)"; r=$?
    [ "$r" -eq 1 ] && grep -qF "PARSEABILITY: cs_$2.py fails python3 -I compile" <<<"$o"
}
c_compile_stage() { local n; for n in $CS_NAMES; do cs_one "$1" "$n" || return 1; done; }
for n in $CS_NAMES; do
    if cs_one "$GATE" "$n"; then note "✅ META OK:   5 compile-stage fixture '$n' — gate FAILs with exit 1 on the python compile leg"
    else note "❌ META FAIL: 5 compile-stage fixture '$n' — gate did not FAIL with exit 1 naming the compile leg"; rc=1; fi
done

# --- 6. env options with an argument; the exact python match ---
SB_PY='MODELS = ("sonnet", "opus")'
mk_sb() { # $1=name $2=shebang line : CLEAN + one script carrying python-only content under that shebang
    local D="$TMP/engine_sb_$1"; mkdir -p "$D"; cp -r "$CLEAN"/. "$D"/
    { printf '%s\n' "$2"; printf '%s\n' "$SB_PY"; } > "$D/sb_script"; chmod +x "$D/sb_script"
}
sb_run() { bash "$1" --engine-dir "$TMP/engine_sb_$2" --quiet >/dev/null 2>&1; echo $?; }   # prints the exit code
SB_PASS="envu envunset envC envchdir envP py312 envpy312 envpy py3 envvar envSvar envSatt envSattI envScluster envSsplit envSsplitI envSquote envSsplitvar envSsep envuatt envclusteru"
SB_FAIL="envCbash envUbash py3cfg pythonista shpy envSbash envSpycfg envSsplitpycfg envuSbash"
mk_sb envu '#!/usr/bin/env -u FOO python3'
mk_sb envunset '#!/usr/bin/env --unset FOO python3'
mk_sb envC '#!/usr/bin/env -C /tmp python3'
mk_sb envchdir '#!/usr/bin/env --chdir /tmp python3'
mk_sb envP '#!/usr/bin/env -P /usr/bin python3'
mk_sb py312 '#!/usr/bin/python3.12'
mk_sb envpy312 '#!/usr/bin/env python3.12'
mk_sb envpy '#!/usr/bin/env python'
mk_sb py3 '#!/usr/bin/python3'
mk_sb envCbash '#!/usr/bin/env -C python3 bash'
mk_sb envUbash '#!/usr/bin/env -u python3 bash'
mk_sb py3cfg '#!/usr/bin/env python3-config'
mk_sb pythonista '#!/usr/bin/env pythonista'
mk_sb shpy '#!/bin/sh # python'
# (review round 2, L2) a VAR=value word before the interpreter, and the two spellings of env's split-string option that carry the
# interpreter INSIDE the option word: the attached short form (-Spython3, also in a cluster: -iSpython3) and --split-string=...
mk_sb envvar '#!/usr/bin/env FOO=1 python3'
mk_sb envSvar '#!/usr/bin/env -S FOO=1 BAR=2 python3 -I'
mk_sb envSatt '#!/usr/bin/env -Spython3'
mk_sb envSattI '#!/usr/bin/env -Spython3 -I'
mk_sb envScluster '#!/usr/bin/env -iSpython3'
mk_sb envSsplit '#!/usr/bin/env --split-string=python3'
mk_sb envSsplitI '#!/usr/bin/env --split-string=python3 -I'
mk_sb envSquote "#!/usr/bin/env -S'python3 -I'"
mk_sb envSsplitvar '#!/usr/bin/env --split-string=FOO=1 python3'
mk_sb envSsep '#!/usr/bin/env --split-string python3'
mk_sb envuatt '#!/usr/bin/env -uFOO python3'
mk_sb envSbash '#!/usr/bin/env -Sbash'
mk_sb envSpycfg '#!/usr/bin/env -Spython3-config'
mk_sb envSsplitpycfg '#!/usr/bin/env --split-string=python3-config'
mk_sb envuSbash '#!/usr/bin/env -uSpython3 bash'
mk_sb envclusteru '#!/usr/bin/env -iu FOO python3'
# control needles: the content is valid python, and the shells the FAIL cases are read under reject it (so the verdict is the interpreter choice)
printf '%s\n' "$SB_PY" > "$TMP/sb_content.py"
if python3 -I -c 'import sys; compile(open(sys.argv[1], "rb").read(), sys.argv[1], "exec", dont_inherit=True)' "$TMP/sb_content.py" >/dev/null 2>&1 \
   && ! sh -n "$TMP/sb_content.py" >/dev/null 2>&1 && ! bash -n "$TMP/sb_content.py" >/dev/null 2>&1; then
    note "✅ META OK:   6 control needle — the python-only content compiles as python and is rejected by sh -n and bash -n"
else
    note "❌ META FAIL: 6 control needle — the shebang fixtures do not discriminate (python content must compile; sh -n and bash -n must reject it)"; rc=1
fi
c_shebangs() { local n; for n in $SB_PASS; do [ "$(sb_run "$1" "$n")" = 0 ] || return 1; done
    for n in $SB_FAIL; do [ "$(sb_run "$1" "$n")" = 1 ] || return 1; done; }
for n in $SB_PASS; do
    if [ "$(sb_run "$GATE" "$n")" = 0 ]; then note "✅ META OK:   6 shebang '$(head -n 1 "$TMP/engine_sb_$n/sb_script")' is read as python — gate PASSes"
    else note "❌ META FAIL: 6 shebang '$(head -n 1 "$TMP/engine_sb_$n/sb_script")' is not read as python (false refusal)"; rc=1; fi
done
for n in $SB_FAIL; do
    if [ "$(sb_run "$GATE" "$n")" = 1 ]; then note "✅ META OK:   6 shebang '$(head -n 1 "$TMP/engine_sb_$n/sb_script")' is NOT read as python — gate FAILs with exit 1 under the shell it declares"
    else note "❌ META FAIL: 6 shebang '$(head -n 1 "$TMP/engine_sb_$n/sb_script")' was read as python (or crashed)"; rc=1; fi
done

# --- 7. the python leg is isolated ---
HOOK="$TMP/hook_sitecustomize"; mkdir -p "$HOOK"
M_SITE="$TMP/marker_sitecustomize"; M_AST="$TMP/marker_ast"
printf 'open(%s, "w").write("ran")\n' "\"$M_SITE\"" > "$HOOK/sitecustomize.py"
PLANT="$TMP/plant_cwd"; mkdir -p "$PLANT"
printf 'open(%s, "w").write("ran")\nparse = lambda *a, **k: None\n' "\"$M_AST\"" > "$PLANT/ast.py"
rm -f "$M_SITE" "$M_AST"
env PYTHONPATH="$HOOK" python3 -c 'pass' >/dev/null 2>&1
( cd "$PLANT" && python3 -c 'import ast' >/dev/null 2>&1 )
if [ -e "$M_SITE" ] && [ -e "$M_AST" ]; then
    note "✅ META OK:   7 control needles — a PYTHONPATH sitecustomize and a cwd ast.py DO execute under a plain python3 on this host"
else
    note "❌ META FAIL: 7 control needles — the isolation vectors are blind on this host (sitecustomize marker: $([ -e "$M_SITE" ] && echo yes || echo no), ast.py marker: $([ -e "$M_AST" ] && echo yes || echo no))"; rc=1
fi
rm -f "$M_SITE" "$M_AST"
c_isolated() { # $1=gate : the gate still passes and executed neither planted file
    rm -f "$M_SITE" "$M_AST"
    env PYTHONPATH="$HOOK" bash "$1" --engine-dir "$PY_OK" --quiet >/dev/null 2>&1 || return 1
    [ ! -e "$M_SITE" ] || return 1
    ( cd "$PLANT" && bash "$1" --engine-dir "$PY_OK" --quiet >/dev/null 2>&1 ) || return 1
    [ ! -e "$M_AST" ]
}
if c_isolated "$GATE"; then note "✅ META OK:   7 python leg ran isolated — no PYTHONPATH sitecustomize and no cwd ast.py was executed (gate PASSed)"
else note "❌ META FAIL: 7 python leg executed a planted PYTHONPATH sitecustomize or cwd ast.py (or the gate failed)"; rc=1; fi

# --- 8. a temp file that cannot be created is exit 2 ---
c_tmpfail() { local o r; o="$(env TMPDIR=/nonexistent_dir_for_cm_mtec bash "$1" --engine-dir "$CLEAN" --quiet 2>&1)"; r=$?
    [ "$r" -eq 2 ] && grep -qF 'cannot create a temporary file' <<<"$o"; }
# control needle: the same engine with a usable TMPDIR is green, so the exit 2 below is the temp-file failure and nothing else
expect_pass "8 control needle — the same engine with a usable TMPDIR passes" env TMPDIR="$TMP" bash "$GATE" --engine-dir "$CLEAN" --quiet
if c_tmpfail "$GATE"; then note "✅ META OK:   8 unusable TMPDIR — exit 2 with 'cannot create a temporary file' (not a false parse failure)"
else note "❌ META FAIL: 8 unusable TMPDIR did not give exit 2 with the temp-file message"; rc=1; fi

# --- 9. GATE-MUTANT discrimination: each mutated copy of the gate must be caught by at least one case above ---
mk_gate_mutant() { # $1=label $2..=sed expressions : a mutated copy of the gate next to the guard lib; sets GM_PATH (empty, and rc 1, when no line changed)
    local D="$TMP/gm_$1" l="$1" e; shift
    GM_PATH=""
    mkdir -p "$D/gates" "$D/lib"; cp "$GATE" "$D/gates/gate.sh"; [ ! -r "$SCRIPT_DIR/../lib/gate_env_override.sh" ] || cp "$SCRIPT_DIR/../lib/gate_env_override.sh" "$D/lib/"
    for e in "$@"; do sed -i "$e" "$D/gates/gate.sh"; done
    if cmp -s "$D/gates/gate.sh" "$GATE"; then note "❌ META FAIL: 9 mutant $l did not apply (anchor drift)"; rc=1; return 1; fi
    GM_PATH="$D/gates/gate.sh"
}
mutant_caught() { # $1=label $2=case function (it must hold on the real gate and fail on the mutant) $3...=sed expressions
    local l="$1" fn="$2"; shift 2
    if ! "$fn" "$GATE"; then note "❌ META FAIL: 9 mutant $l: case $fn does not hold on the real gate"; rc=1; return; fi
    mk_gate_mutant "$l" "$@" || return
    if "$fn" "$GM_PATH"; then note "❌ META FAIL: 9 mutant $l SURVIVED ($fn is not load-bearing for it)"; rc=1
    else note "✅ META OK:   9 mutant $l caught by $fn"; fi
}
SED_COMPILE='s/compile(open(sys.argv\[1\], "rb").read(), sys.argv\[1\], "exec", dont_inherit=True)/__import__("ast").parse(open(sys.argv[1], "rb").read(), sys.argv[1])/'
SED_NOI='s/python3 -I -c/python3 -c/'
mutant_caught parser_only_ast_parse c_compile_stage "$SED_COMPILE"
mutant_caught no_isolation_flag c_isolated "$SED_NOI"
mutant_caught ast_parse_without_isolation c_isolated "$SED_COMPILE" "$SED_NOI"
mutant_caught any_shebang_mentioning_python c_shebangs 's/\*bash\*) echo bash ;; \*) echo sh ;; esac/*python*) echo python ;; *bash*) echo bash ;; *) echo sh ;; esac/'
mutant_caught python_star_widened c_shebangs 's/python|python\[0-9\]|python\[0-9\]\.\[0-9\]\*) echo python/python*) echo python/'
mutant_caught python_digit_star_widened c_shebangs 's/python|python\[0-9\]|python\[0-9\]\.\[0-9\]\*) echo python/python|python[0-9]*) echo python/'
mutant_caught env_argument_not_skipped c_shebangs 's/--unset|--chdir)  _skip=1; continue ;;/--NEVER_MATCHES_ZZ)  _skip=1; continue ;;/' 's/u|C|P) \[ -n "\$_c" \] || _skip=1; _c="" ;;/u|C|P) _c="" ;;/'
mutant_caught mktemp_failure_ignored c_tmpfail 's/^        exit 2$/        :/'
# (review round 2, L2) the VAR=value skip and the split-string forms, one mutant each
mutant_caught varassign_not_skipped c_shebangs 's/-|\*=\*)/-)/'
mutant_caught split_string_long_ignored c_shebangs 's/--split-string=\*) _pend=/--NEVER_MATCHES_ZZ) _pend=/'
mutant_caught split_string_short_ignored c_shebangs 's/S) *_pend=/Z)     _pend=/'
mutant_caught cluster_read_first_letter_only c_shebangs 's/_o="\${_c:0:1}"; _c="\${_c:1}"/_o="${_c:0:1}"; _c=""/'
mutant_caught attached_argument_read_as_cluster c_shebangs 's/u|C|P) \[ -n "\$_c" \] || _skip=1; _c="" ;;/u|C|P) [ -n "$_c" ] || _skip=1 ;;/'

# --- 10. the harness itself: expect_fail accepts exit 1 and nothing else (control: the 1 case is accepted) ---
ef_out() { ( expect_fail "stub" bash -c "exit $1" ) 2>&1; }   # a stub gate with a chosen exit code; rc changes stay inside the subshell
if grep -q 'META OK' <<<"$(ef_out 1)" && grep -q 'META FAIL' <<<"$(ef_out 0)" && grep -q 'META FAIL' <<<"$(ef_out 2)" && grep -q 'META FAIL' <<<"$(ef_out 139)"; then
    note "✅ META OK:   10 expect_fail accepts exit 1 only (exit 0, exit 2 and a crash code are all refused)"
else
    note "❌ META FAIL: 10 expect_fail accepts an exit code other than 1"; rc=1
fi


echo "======================================================================"
if [ "$rc" -eq 0 ]; then
    echo "✅ META PASS: CM-MULTITRACK-ENGINE-IN-CONSTITUTION is a genuine (non-bluff) gate"
else
    echo "❌ META FAIL: CM-MULTITRACK-ENGINE-IN-CONSTITUTION failed the §1.1 discriminator"
fi
echo "======================================================================"
exit "$rc"
