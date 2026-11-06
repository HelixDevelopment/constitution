#!/bin/bash
# fastcycle-timeout-s: 600
# Purpose : CON-108 regression guard for
#           `constitution/scripts/fastcycle/orchestration/custody_sweep.py`:
#           the stash patch (inventory hash + verify-proposal live hash) is
#           derived with `git diff <CANONICAL_PATCH_OPTS> <ref>^1 <ref>`, never
#           `git stash show -p`; EVERY `diff --git` header (each side bare or
#           C-quoted, carrying the a/ b/ prefixes) is checked and a patch with
#           one bad header is reported as UNMEASURED (never hashed), naming the
#           real cause. CON-119: the display-only file list names both paths
#           of a rename and C-quoted, spaced and non-ASCII paths correctly.
# Forensic: measured on git 2.53.0, `git stash show -p --src-prefix=a/
#           --dst-prefix=b/` printed `diff --git f sf`, `diff --git f |f`
#           (different on every run), so every stash `land` was REFUSED as a
#           stale backup (r11 B2, r13 G7, r15 G3 RED on that host).
# Usage   : bash test_custody_sweep_stash_patch_r22_regression.sh
#           Exit 0 when every check passes, 1 otherwise. The last line is the
#           summary line.
# Method  : REAL throwaway git repositories under a temp dir (never this
#           project's repo); the REAL tool's `inventory` and `verify-proposal`
#           CLIs. Host independence: PATH shims around the real git make the
#           result the same on any git version. `stashshow` mangles the headers
#           of `git stash show` output (models the 2.53.0 bug); `diffpos`
#           rewrites ONE chosen `diff --git` header (or all, or makes the diff
#           fail) of `git diff ... <ref>^1 <ref>` output.
#           Fixture axes (CON-108 review round 2, finding R2-F1-A: a fixture
#           on which a partial implementation gives the same answer as the
#           correct one proves nothing): header POSITION (first, middle, last
#           of a three-header stash), garble QUOTING (bare `f xf`, quoted with
#           no prefixes `"f" "xf"`), git diff FAILURE (cause text), a correct
#           MIXED-quoting header (bare a/ side, quoted b/ side), file-list
#           SHAPES (rename, spaces, `x b/y.txt`, quotes, non-ASCII, binary,
#           mode change, delete, add). Paired mutations on a copy of the tool:
#           each must fail at least the functional check named for it (the
#           partial implementation it models disagrees with the correct one on
#           that fixture); a mutation that only breaks an anchor is reported
#           as an anchor failure, never as caught.
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
IMPL="$FC/orchestration/custody_sweep.py"
LIB="$FC/lib/fc_common.py"
EXLIB="$FC/lib/fc_entry.py"

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES \
      GIT_CONFIG GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS GIT_CEILING_DIRECTORIES GIT_NAMESPACE GIT_PREFIX \
      GIT_COMMON_DIR CUSTODY_SWEEP_GIT_TIMEOUT_S SHIM_POS SHIM_TEXT SHIM_FAIL
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

g() { git -c commit.gpgsign=false -c core.hooksPath=/dev/null -c init.defaultBranch=main "$@"; }
CANON=(--binary --no-color --no-ext-diff --no-textconv --no-relative --src-prefix=a/ --dst-prefix=b/ --ignore-submodules=none)
TAB=$'\t'

fail=0
pass=0
ok() { pass=$((pass + 1)); echo "ok $*"; }
notok() { fail=$((fail + 1)); echo "NOT ok $*"; }

TMP=$(mktemp -d)
trap 'rm -rf "${TMP:?}"' EXIT

for p in "$IMPL" "$LIB" "$EXLIB"; do [ -f "$p" ] || notok "control needle: $p not found"; done
REALGIT=$(command -v git) || notok "control needle: git not on PATH"
[ "$fail" = 0 ] && ok "control needle: implementation + libs resolve, git at $REALGIT"

sha() { sha256sum "$1" | cut -d' ' -f1; }

# --- shims (each forwards to the real git; only the named output changes) ---
mkdir -p "$TMP/shim_stashshow" "$TMP/shim_diffpos"
cat > "$TMP/shim_stashshow/git" <<EOF
#!/bin/bash
real=$REALGIT
case " \$* " in *" stash show "*)
  set -o pipefail
  "\$real" "\$@" | sed -e 's#^diff --git .*#diff --git f xf#'
  exit \$? ;;
esac
exec "\$real" "\$@"
EOF
# diffpos: only a call that has the argument `diff` AND an argument ending in
# `^1` (the stash patch derivation). SHIM_FAIL=1: print nothing, exit 3.
# Otherwise SHIM_POS = 1, 2, 3, ... or all: that `diff --git` header is
# replaced by SHIM_TEXT; every other byte is passed through.
cat > "$TMP/shim_diffpos/git" <<EOF
#!/bin/bash
real=$REALGIT
d=0; c=0
for a in "\$@"; do case \$a in diff) d=1 ;; *'^1') c=1 ;; esac; done
if [ \$d = 1 ] && [ \$c = 1 ]; then
  [ "\${SHIM_FAIL:-0}" = 1 ] && { echo "shim: forced git diff failure" >&2; exit 3; }
  if [ -n "\${SHIM_POS:-}" ]; then
    set -o pipefail
    "\$real" "\$@" | SHIM_POS="\$SHIM_POS" SHIM_TEXT="\${SHIM_TEXT:-diff --git f xf}" awk '
      /^diff --git / { n++; if (ENVIRON["SHIM_POS"] == "all" || n == ENVIRON["SHIM_POS"] + 0) { print ENVIRON["SHIM_TEXT"]; next } }
      { print }'
    exit \$?
  fi
fi
exec "\$real" "\$@"
EOF
chmod +x "$TMP/shim_stashshow/git" "$TMP/shim_diffpos/git"

# --- repo R: one plain stash (one tracked change) and its faithful backup ---
R="$TMP/r"
g init --quiet "$R"
printf 'one\n' > "$R/f"; g -C "$R" add f; g -C "$R" commit --quiet -m init
printf 'two\n' > "$R/f"; g -C "$R" stash --quiet
g -C "$R" diff "${CANON[@]}" 'stash@{0}^1' 'stash@{0}' > "$TMP/st.patch"
if head -1 "$TMP/st.patch" | grep -qx 'diff --git a/f b/f'; then
  ok "control needle: the test's own backup has canonical a/ b/ headers"
else
  notok "control needle: backup header is '$(head -1 "$TMP/st.patch")'"
fi
WANT_SHA=$(sha "$TMP/st.patch")

# --- repo R3: a THREE-header stash; the MIDDLE header mixes a bare and a
# C-quoted path (git quotes each path on its own; a rename to a name with a
# TAB prints `diff --git a/b2.txt "b/b2 sp\ttab.txt"`, measured on git 2.53.0).
R3="$TMP/r3"
g init --quiet "$R3"
for f in a1 b2 c3; do printf '%s\n' "$f" > "$R3/$f.txt"; done
g -C "$R3" add a1.txt b2.txt c3.txt; g -C "$R3" commit --quiet -m init
g -C "$R3" mv b2.txt "b2 sp${TAB}tab.txt"; printf 'a1x\n' > "$R3/a1.txt"; printf 'c3x\n' > "$R3/c3.txt"
g -C "$R3" stash --quiet
g -C "$R3" diff "${CANON[@]}" 'stash@{0}^1' 'stash@{0}' > "$TMP/st3.patch"
H3=$(grep '^diff --git ' "$TMP/st3.patch" | tr '\n' '|')
if [ "$H3" = 'diff --git a/a1.txt b/a1.txt|diff --git a/b2.txt "b/b2 sp\ttab.txt"|diff --git a/c3.txt b/c3.txt|' ]; then
  ok "control needle: repo 3 patch = plain, mixed-quoting, plain header"
else
  notok "control needle: repo 3 headers are '$H3'"
fi
WANT_SHA3=$(sha "$TMP/st3.patch")

# Shim self-checks (control needles): the stashshow shim mangles `stash show`
# only; diffpos rewrites exactly the chosen header and nothing else.
if PATH="$TMP/shim_stashshow:$PATH" git -C "$R" stash show -p "${CANON[@]}" 'stash@{0}' | head -1 | grep -qx 'diff --git f xf' \
   && PATH="$TMP/shim_stashshow:$PATH" git -C "$R" diff "${CANON[@]}" 'stash@{0}^1' 'stash@{0}' | cmp -s - "$TMP/st.patch"; then
  ok "shim self-check: stashshow mangles 'stash show' headers only"
else
  notok "shim self-check: stashshow shim does not behave as designed"
fi
selfcheck_pos() {  # POS TEXT -> 0 when only header POS of the R3 patch changed to TEXT
  local got want
  got=$(SHIM_POS=$1 SHIM_TEXT=$2 PATH="$TMP/shim_diffpos:$PATH" git -C "$R3" diff "${CANON[@]}" 'stash@{0}^1' 'stash@{0}') || return 1
  want=$(awk -v p="$1" -v t="$2" '/^diff --git /{n++; if (p == "all" || n == p + 0) {print t; next}} {print}' "$TMP/st3.patch")
  [ "$got" = "$want" ] && [ "$got" != "$(cat "$TMP/st3.patch")" ]
}
sc=ok
for p in 1 2 3 all; do selfcheck_pos "$p" 'diff --git f xf' || sc="pos $p bare"; done
for p in 1 2 3; do selfcheck_pos "$p" 'diff --git "f" "xf"' || sc="pos $p quoted"; done
if SHIM_FAIL=1 PATH="$TMP/shim_diffpos:$PATH" git -C "$R3" diff "${CANON[@]}" 'stash@{0}^1' 'stash@{0}' >/dev/null 2>&1; then sc="fail mode exits 0"; fi
if PATH="$TMP/shim_diffpos:$PATH" git -C "$R3" diff "${CANON[@]}" 'stash@{0}^1' 'stash@{0}' | cmp -s - "$TMP/st3.patch"; then :; else sc="pass-through changed the patch"; fi
if SHIM_FAIL=1 PATH="$TMP/shim_diffpos:$PATH" git -C "$R3" rev-parse 'stash@{0}^1' >/dev/null 2>&1; then :; else sc="fail mode hit a non-diff call"; fi
if [ "$sc" = ok ]; then ok "shim self-check: diffpos rewrites only the chosen header (1, 2, 3, all; bare and quoted), fails only git diff"
else notok "shim self-check: diffpos does not behave as designed ($sc)"; fi
# Host evidence only (never decides PASS): is this host's `stash show -p` canonical?
echo "info: host $(git --version): 'git stash show -p' first header = '$(git -C "$R" stash show -p "${CANON[@]}" 'stash@{0}' | head -1)'"

# --- repo R4 (CON-119): file-list shapes ---
R4="$TMP/r4"
g init --quiet "$R4"
mkdir -p "$R4/x b"
printf '1\n' > "$R4/x b/y.txt"; printf 'u\n' > "$R4/ünï.txt"; printf 'd\n' > "$R4/del.txt"; printf 'm\n' > "$R4/mode.sh"
printf '\000\001' > "$R4/bin.dat"; printf 'q\n' > "$R4/q\"\\.txt"; printf 'r\n' > "$R4/old.txt"
g -C "$R4" add -A; g -C "$R4" commit --quiet -m init
printf '2\n' > "$R4/x b/y.txt"; printf 'u2\n' > "$R4/ünï.txt"; g -C "$R4" rm --quiet del.txt; chmod +x "$R4/mode.sh"
printf '\000\002' > "$R4/bin.dat"; printf 'q2\n' > "$R4/q\"\\.txt"; printf 'new\n' > "$R4/new file.txt"
g -C "$R4" add "new file.txt"; g -C "$R4" mv old.txt "new name.txt"
g -C "$R4" stash --quiet
# Expected list, built from git's own -z name-status (unambiguous, raw bytes):
# both paths of a rename, every other path once, in patch order.
WANT_FILES4=$(g -C "$R4" diff -z --name-status --no-color 'stash@{0}^1' 'stash@{0}' | python3 -c '
import sys
t = sys.stdin.buffer.read().split(b"\0")
out, i = [], 0
while i < len(t) and t[i]:
    st = t[i].decode()
    if st[0] in "RC":
        out += [t[i + 1], t[i + 2]] if st[0] == "R" else [t[i + 2]]; i += 3
    else:
        out.append(t[i + 1]); i += 2
print(",".join(p.decode("utf-8", "surrogateescape") for p in out))')
case "$WANT_FILES4" in
  *"x b/y.txt"*"ünï.txt"*) ok "control needle: repo 4 expected file list built from git -z name-status ($WANT_FILES4)" ;;
  *) notok "control needle: repo 4 expected file list unexpected: '$WANT_FILES4'" ;;
esac
WANT_FILES3="a1.txt,b2.txt,b2 sp${TAB}tab.txt,c3.txt"

run_vp() {  # IMPL REPO PATCH [ENV...] -> "VERDICT<TAB>DETAIL"
  local impl="$1" repo="$2" patch="$3" pj="$TMP/prop.$RANDOM$RANDOM.json" oj="$TMP/out.$RANDOM$RANDOM.json"
  shift 3
  python3 - "$pj" "$(sha "$patch")" "$patch" <<'PYEOF'
import json, sys
p, h, path = sys.argv[1:]
json.dump({"entry_kind": "stash", "entry_id": "stash@{0}", "action": "land",
           "backup_hash": h, "backup_artifact_path": path}, open(p, "w"))
PYEOF
  env "$@" python3 "$impl" verify-proposal --proposal "$pj" --repo-root "$repo" --out "$oj" >/dev/null 2>&1
  python3 - "$oj" <<'PYEOF'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    print("%s\t%s" % (d.get("verdict"), d.get("verdict_detail")))
except Exception as e:
    print("NO_DOC\t%s" % e)
PYEOF
}
run_inv() {  # IMPL REPO [ENV...] -> "STATUS<TAB>SHA256<TAB>FILES"
  local impl="$1" repo="$2" oj="$TMP/inv.$RANDOM$RANDOM.json"
  shift 2
  env "$@" python3 "$impl" inventory --repo-root "$repo" --backup-root "$TMP/nobackups" --out "$oj" >/dev/null 2>&1
  python3 - "$oj" <<'PYEOF'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    e = [x for x in d.get("entries", []) if x.get("entry_id") == "stash@{0}"][0]
    h = e["dirty_file_hash"]
    print("%s\t%s\t%s" % (h.get("status"), h.get("sha256"), ",".join(e.get("files_touched") or [])))
except Exception as ex:
    print("NO_DOC\t%s\t" % ex)
PYEOF
}
verdict() { printf '%s' "${1%%$'\t'*}"; }
detail() { printf '%s' "${1#*$'\t'}"; }
status() { printf '%s' "${1%%$'\t'*}"; }

SS="PATH=$TMP/shim_stashshow:$PATH"
DP="PATH=$TMP/shim_diffpos:$PATH"
QG='diff --git "f" "xf"'

# battery IMPL MODE: every functional check. MODE=report prints ok/NOT ok per
# check; MODE=collect prints only the ids of the checks that FAILED.
battery() {
  local impl=$1 mode=$2 V I k id
  BF=""
  chk() {  # ID RESULT(0=pass) MESSAGE
    if [ "$2" = 0 ]; then [ "$mode" = report ] && ok "$1 $3"
    else BF="$BF $1"; [ "$mode" = report ] && notok "$1 $3"; fi
  }
  V=$(run_vp "$impl" "$R" "$TMP/st.patch" "PATH=$PATH")
  [ "$(verdict "$V")" = ALLOWED ]; chk G1 $? "plain stash, faithful backup, host git -> ALLOWED (got $(verdict "$V"))"
  I=$(run_inv "$impl" "$R" "PATH=$PATH")
  [ "$I" = "dirty${TAB}$WANT_SHA${TAB}f" ]; chk G2 $? "inventory: dirty, sha256 = sha256 of 'git diff CANON ref^1 ref', files=f (got '$I')"
  V=$(run_vp "$impl" "$R" "$TMP/st.patch" "$SS")
  [ "$(verdict "$V")" = ALLOWED ]; chk G3 $? "a git whose 'stash show -p' ignores the prefixes -> still ALLOWED (got $(verdict "$V"))"
  V=$(run_vp "$impl" "$R" "$TMP/st.patch" "$DP" SHIM_POS=all)
  [ "$(verdict "$V")" = REFUSED ] && [[ "$(detail "$V")" == *"could not be read"* ]] \
    && [[ "$(detail "$V")" == *"diff --git header"* ]] && [[ "$(detail "$V")" != *"git status/diff failed"* ]]
  chk B1 $? "every header non-canonical -> REFUSED as unmeasured, naming the bad diff --git header (got $(verdict "$V"): $(detail "$V" | cut -c1-160))"
  I=$(run_inv "$impl" "$R" "$DP" SHIM_POS=all)
  [ "$(status "$I")" = UNMEASURED ]; chk B2 $? "inventory with non-canonical headers -> UNMEASURED, never hashed (got '$I')"
  I=$(run_inv "$impl" "$R3" "PATH=$PATH")
  [ "$I" = "dirty${TAB}$WANT_SHA3${TAB}$WANT_FILES3" ]
  chk G4 $? "three-header stash with a mixed-quoting middle header -> dirty, sha256 = backup, files = both rename paths (got '$I')"
  V=$(run_vp "$impl" "$R3" "$TMP/st3.patch" "PATH=$PATH")
  [ "$(verdict "$V")" = ALLOWED ]; chk G5 $? "three-header mixed-quoting stash, faithful backup -> ALLOWED (got $(verdict "$V"))"
  for k in 1 2 3; do
    I=$(run_inv "$impl" "$R3" "$DP" SHIM_POS=$k)
    [ "$(status "$I")" = UNMEASURED ]; chk "P$k" $? "only header $k of 3 garbled bare ('diff --git f xf') -> UNMEASURED (got '$(status "$I")')"
    I=$(run_inv "$impl" "$R3" "$DP" SHIM_POS=$k "SHIM_TEXT=$QG")
    [ "$(status "$I")" = UNMEASURED ]; chk "Q$k" $? "only header $k of 3 quoted with no prefixes ('$QG') -> UNMEASURED (got '$(status "$I")')"
  done
  V=$(run_vp "$impl" "$R3" "$TMP/st3.patch" "$DP" SHIM_POS=2)
  [ "$(verdict "$V")" = REFUSED ] && [[ "$(detail "$V")" == *"diff --git header"* ]] && [[ "$(detail "$V")" == *"diff --git f xf"* ]]
  chk V2 $? "verify-proposal, middle header garbled -> REFUSED naming that header (got $(verdict "$V"): $(detail "$V" | cut -c1-160))"
  V=$(run_vp "$impl" "$R3" "$TMP/st3.patch" "$DP" SHIM_POS=3 "SHIM_TEXT=$QG")
  [ "$(verdict "$V")" = REFUSED ] && [[ "$(detail "$V")" == *'"f" "xf"'* ]]
  chk V3 $? "verify-proposal, last header quoted without prefixes -> REFUSED naming that header (got $(verdict "$V"): $(detail "$V" | cut -c1-160))"
  V=$(run_vp "$impl" "$R3" "$TMP/st3.patch" "$DP" SHIM_FAIL=1)
  [ "$(verdict "$V")" = REFUSED ] && [[ "$(detail "$V")" == *'git diff stash@{0}^1 stash@{0} failed (rc=3)'* ]]
  chk F1 $? "git diff of the stash fails (rc 3) -> REFUSED naming 'git diff ... failed (rc=3)' (got $(verdict "$V"): $(detail "$V" | cut -c1-160))"
  I=$(run_inv "$impl" "$R3" "$DP" SHIM_FAIL=1)
  [ "$(status "$I")" = UNMEASURED ]; chk F2 $? "git diff of the stash fails -> inventory UNMEASURED (got '$(status "$I")')"
  I=$(run_inv "$impl" "$R4" "PATH=$PATH")
  [ "$(status "$I")" = dirty ] && [ "${I##*$'\t'}" = "$WANT_FILES4" ]
  chk L1 $? "CON-119 file list: rename both paths, spaces, 'x b/y.txt', quotes, non-ASCII, binary, mode, delete, add (got '${I##*$'\t'}')"
  [ "$mode" = collect ] && printf '%s' "$BF"
  return 0
}

battery "$IMPL" report

# --- paired mutations: each a copy of the tool; each must fail its named check ---
mk_mutant() {  # NAME OLD NEW -> prints the mutant path, or "" when the anchor is not unique
  local d="$TMP/mut_$1"
  mkdir -p "$d/orchestration" "$d/lib"
  cp "$IMPL" "$d/orchestration/custody_sweep.py"; cp "$LIB" "$d/lib/fc_common.py"; cp "$EXLIB" "$d/lib/fc_entry.py"
  if python3 - "$d/orchestration/custody_sweep.py" "$2" "$3" <<'PYEOF'
import sys
p, old, new = sys.argv[1:]
c = open(p, encoding="utf-8").read()
if c.count(old) != 1:
    sys.exit(1)
open(p, "w", encoding="utf-8").write(c.replace(old, new))
PYEOF
  then echo "$d/orchestration/custody_sweep.py"; fi
}
mutation() {  # NAME "EXPECTED IDS" OLD NEW
  local m got e miss=""
  m=$(mk_mutant "$1" "$3" "$4")
  if [ -z "$m" ]; then notok "mutation $1: anchor not unique in the tool (not a catch)"; return; fi
  got=$(battery "$m" collect)
  for e in $2; do case " $got " in *" $e "*) ;; *) miss="$miss $e" ;; esac; done
  if [ -z "$got" ]; then notok "mutation $1 SURVIVED every functional check"
  elif [ -n "$miss" ]; then notok "mutation $1: caught by$got but NOT by its named check(s)$miss"
  else ok "mutation $1: caught by$got (named: $2)"; fi
}
HDRS='[l for l in out.split(b"\n") if l.startswith(b"diff --git ")]'
LOOP_A='    for raw_line in '
LOOP_B=':
        if raw_line.startswith(b"diff --git ") and not _CANONICAL_DIFF_HEADER_RE.match(raw_line):'
LOOP="${LOOP_A}"'out.split(b"\n")'"${LOOP_B}"
IFL='        if raw_line.startswith(b"diff --git ") and not _CANONICAL_DIFF_HEADER_RE.match(raw_line):'
PAT="_CANONICAL_DIFF_HEADER_RE = re.compile(rb'^diff --git (?:a/.*|\"a/.*\") (?:b/.*|\"b/.*\")\$')"

# M1: derive the stash patch with `git stash show -p` again (the pre-fix code).
mutation M1_stash_show "G3" \
  '["git", "-C", root, "diff"] + list(CANONICAL_PATCH_OPTS)
                            + ["%s^1" % ref, ref]' \
  '["git", "-C", root, "stash", "show", "-p"] + list(CANONICAL_PATCH_OPTS)
                            + [ref]'
# M2: drop the header self-check.
mutation M2_no_header_check "B2 P1 P2 P3" "$IFL" '        if False:'
# M3: report a failed derivation as measured again.
mutation M3_measured_true "B1" \
  'dirty_submodules=[], has_unmerged=False, measured=patch_bytes is not None)' \
  'dirty_submodules=[], has_unmerged=False, measured=True)'
# M4 (round-1 reviewer R1g): check only the FIRST header.
mutation M4_first_header_only "P2 P3" "$LOOP" "${LOOP_A}${HDRS}[:1]${LOOP_B}"
# M5: the pre-F1-1 header pattern (both paths bare, or both quoted).
mutation M5_no_mixed_quoting "G4 G5" "$PAT" \
  "_CANONICAL_DIFF_HEADER_RE = re.compile(rb'^diff --git (a/.* b/.*|\"a/.*\" \"b/.*\")\$')"
# RV1 (round-2 reviewer): check only the LAST header.
mutation RV1_last_only "P1 P2" "$LOOP" "${LOOP_A}${HDRS}[-1:]${LOOP_B}"
# RV2: check only the first and the last header.
mutation RV2_first_and_last "P2" "$LOOP" "${LOOP_A}(lambda h: h[:1] + h[-1:])(${HDRS})${LOOP_B}"
# RV6: check only the first two headers.
mutation RV6_first_two_only "P3" "$LOOP" "${LOOP_A}${HDRS}[:2]${LOOP_B}"
# RV3: trust any header that holds a quote.
mutation RV3_quoted_trusted "Q1 Q2 Q3" "$IFL" "        if b'\"' in raw_line:
            continue
$IFL"
# RV4: a looser pattern -- any quoted token counts as prefixed.
mutation RV4_loose_regex "Q1 Q2 Q3" "$PAT" \
  "_CANONICAL_DIFF_HEADER_RE = re.compile(rb'^diff --git (?:a/.*|\".*\") (?:b/.*|\".*\")\$')"
# RV5: a failed git diff returns no cause text.
mutation RV5_rc_why_dropped "F1" \
  '        return None, "git diff %s^1 %s failed (rc=%s)" % (ref, ref, rc)' \
  '        return None, None'
# L1 (CON-119): the pre-fix file list (first path of each header, DIFF_FILE_RE).
mutation L1_old_file_list "G4 L1" \
  '    files = _patch_file_paths(out)' \
  '    files = []
    for raw_line in out.split(b"\n"):
        if raw_line.startswith(b"diff --git "):
            m = DIFF_FILE_RE.match(raw_line.decode("utf-8", "surrogateescape"))
            if m:
                files.append(m.group(1))'

echo "=== stash patch regression guard (CON-108): pass=$pass fail=$fail ==="
[ "$fail" = 0 ]
