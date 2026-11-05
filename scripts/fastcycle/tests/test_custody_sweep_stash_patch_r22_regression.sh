#!/bin/bash
# Purpose : CON-108 regression guard for
#           `constitution/scripts/fastcycle/orchestration/custody_sweep.py`:
#           the stash patch (inventory hash + verify-proposal live hash) is
#           derived with `git diff <CANONICAL_PATCH_OPTS> <ref>^1 <ref>`, never
#           `git stash show -p`, and a patch whose `diff --git` headers lack
#           the a/ b/ prefixes is reported as UNMEASURED (never hashed).
# Forensic: measured on git 2.53.0, `git stash show -p --src-prefix=a/
#           --dst-prefix=b/` printed `diff --git f sf`, `diff --git f |f`
#           (different on every run), so every stash `land` was REFUSED as a
#           stale backup (r11 B2, r13 G7, r15 G3 RED on that host).
# Usage   : bash test_custody_sweep_stash_patch_r22_regression.sh
#           Exit 0 when every check passes, 1 otherwise.
# Method  : REAL throwaway git repositories under a temp dir (never this
#           project's repo); the REAL tool's `inventory` and `verify-proposal`
#           CLIs. Host independence: two PATH shims around the real git make
#           the result the same on any git version -- one mangles the headers
#           of `git stash show` output (models the 2.53.0 bug), the other
#           mangles the headers of `git diff ... <ref>^1 <ref>` output (models
#           a git whose diff ignores the prefixes). Paired mutations on a copy
#           of the tool prove each part of the fix is load-bearing.
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
IMPL="$FC/orchestration/custody_sweep.py"
LIB="$FC/lib/fc_common.py"
EXLIB="$FC/lib/fc_entry.py"

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES \
      GIT_CONFIG GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS GIT_CEILING_DIRECTORIES GIT_NAMESPACE GIT_PREFIX \
      GIT_COMMON_DIR CUSTODY_SWEEP_GIT_TIMEOUT_S
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

g() { git -c commit.gpgsign=false -c core.hooksPath=/dev/null -c init.defaultBranch=main "$@"; }
CANON=(--binary --no-color --no-ext-diff --no-textconv --no-relative --src-prefix=a/ --dst-prefix=b/ --ignore-submodules=none)

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

# Shims. Each forwards to the real git; only the named output is rewritten.
mkshim() {  # DIR MODE   MODE = stashshow | diffparent
  mkdir -p "$1"
  cat > "$1/git" <<EOF
#!/bin/bash
mode=$2
real=$REALGIT
hit=0
for a in "\$@"; do
  case \$mode:\$a in
    stashshow:show) hit=1 ;;
    diffparent:*'^1') hit=1 ;;
  esac
done
[ "\$mode" = stashshow ] && { case " \$* " in *" stash "*) ;; *) hit=0 ;; esac; }
if [ \$hit = 1 ]; then
  set -o pipefail
  "\$real" "\$@" | sed -e 's#^diff --git .*#diff --git f xf#'
  exit \$?
fi
exec "\$real" "\$@"
EOF
  chmod +x "$1/git"
}
mkshim "$TMP/shim_stashshow" stashshow
mkshim "$TMP/shim_diffparent" diffparent

# Repo with one plain stash (one tracked change) and its faithful backup.
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
# Shim self-checks: each shim really mangles what it targets and nothing else.
if PATH="$TMP/shim_stashshow:$PATH" git -C "$R" stash show -p "${CANON[@]}" 'stash@{0}' | head -1 | grep -qx 'diff --git f xf' \
   && PATH="$TMP/shim_stashshow:$PATH" git -C "$R" diff "${CANON[@]}" 'stash@{0}^1' 'stash@{0}' | cmp -s - "$TMP/st.patch"; then
  ok "shim self-check: stashshow mangles 'stash show' headers only"
else
  notok "shim self-check: stashshow shim does not behave as designed"
fi
if PATH="$TMP/shim_diffparent:$PATH" git -C "$R" diff "${CANON[@]}" 'stash@{0}^1' 'stash@{0}' | head -1 | grep -qx 'diff --git f xf'; then
  ok "shim self-check: diffparent mangles 'diff <ref>^1 <ref>' headers"
else
  notok "shim self-check: diffparent shim does not behave as designed"
fi
# Host evidence only (never decides PASS): is this host's `stash show -p` canonical?
HS=$(git -C "$R" stash show -p "${CANON[@]}" 'stash@{0}' | head -1)
echo "info: host $(git --version): 'git stash show -p' first header = '$HS'"

run_vp() {  # IMPL [PATHPREFIX] -> "VERDICT<TAB>DETAIL"
  local impl="$1" pre="${2:-}" pj="$TMP/prop.$RANDOM.json" oj="$TMP/out.$RANDOM.json"
  python3 - "$pj" "$(sha "$TMP/st.patch")" "$TMP/st.patch" <<'PYEOF'
import json, sys
p, h, path = sys.argv[1:]
json.dump({"entry_kind": "stash", "entry_id": "stash@{0}", "action": "land",
           "backup_hash": h, "backup_artifact_path": path}, open(p, "w"))
PYEOF
  PATH="$pre${pre:+:}$PATH" python3 "$impl" verify-proposal --proposal "$pj" --repo-root "$R" --out "$oj" >/dev/null 2>&1
  python3 - "$oj" <<'PYEOF'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    print("%s\t%s" % (d.get("verdict"), d.get("verdict_detail")))
except Exception as e:
    print("NO_DOC\t%s" % e)
PYEOF
}
run_inv() {  # IMPL [PATHPREFIX] -> "STATUS<TAB>SHA256<TAB>FILES"
  local impl="$1" pre="${2:-}" oj="$TMP/inv.$RANDOM.json"
  PATH="$pre${pre:+:}$PATH" python3 "$impl" inventory --repo-root "$R" --backup-root "$TMP/nobackups" --out "$oj" >/dev/null 2>&1
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

WANT_SHA=$(sha "$TMP/st.patch")

# --- real tool ---
V=$(run_vp "$IMPL")
if [ "$(verdict "$V")" = ALLOWED ]; then ok "G1 plain stash, faithful backup, host git -> ALLOWED"
else notok "G1 expected ALLOWED, got $(verdict "$V"): $(detail "$V" | cut -c1-300)"; fi
I=$(run_inv "$IMPL")
if [ "$I" = "dirty	$WANT_SHA	f" ]; then ok "G2 inventory: status dirty, sha256 = sha256 of 'git diff CANON ref^1 ref', files=f"
else notok "G2 inventory expected 'dirty $WANT_SHA f', got '$I'"; fi
V=$(run_vp "$IMPL" "$TMP/shim_stashshow")
if [ "$(verdict "$V")" = ALLOWED ]; then ok "G3 a git whose 'stash show -p' ignores the prefixes -> still ALLOWED (tool never uses it)"
else notok "G3 expected ALLOWED under the stashshow shim, got $(verdict "$V"): $(detail "$V" | cut -c1-300)"; fi
V=$(run_vp "$IMPL" "$TMP/shim_diffparent")
if [ "$(verdict "$V")" = REFUSED ] && [[ "$(detail "$V")" == *"could not be read"* ]]; then
  ok "B1 non-canonical stash patch headers -> REFUSED as unmeasured ('could not be read')"
else
  notok "B1 expected REFUSED naming 'could not be read', got $(verdict "$V"): $(detail "$V" | cut -c1-300)"
fi
I=$(run_inv "$IMPL" "$TMP/shim_diffparent")
if [ "${I%%$'\t'*}" = UNMEASURED ]; then ok "B2 inventory with non-canonical headers -> status UNMEASURED (never hashed)"
else notok "B2 inventory expected status UNMEASURED, got '$I'"; fi

# --- paired mutations (each on a fresh copy of the tool) ---
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
# M1: derive the stash patch with `git stash show -p` again (the pre-fix code).
M=$(mk_mutant M1_stash_show \
  '["git", "-C", root, "diff"] + list(CANONICAL_PATCH_OPTS)
                            + ["%s^1" % ref, ref]' \
  '["git", "-C", root, "stash", "show", "-p"] + list(CANONICAL_PATCH_OPTS)
                            + [ref]')
if [ -z "$M" ]; then notok "mutation M1_stash_show: anchor not unique in the tool"
else
  V=$(run_vp "$M" "$TMP/shim_stashshow")
  if [ "$(verdict "$V")" = ALLOWED ]; then notok "mutation M1_stash_show SURVIVED (mutant ALLOWED under the stashshow shim)"
  else ok "mutation M1_stash_show: caught -- mutant $(verdict "$V") under the stashshow shim"; fi
fi
# M2: drop the header self-check.
M=$(mk_mutant M2_no_header_check \
  'if raw_line.startswith(b"diff --git ") and not _CANONICAL_DIFF_HEADER_RE.match(raw_line):' \
  'if False:')
if [ -z "$M" ]; then notok "mutation M2_no_header_check: anchor not unique in the tool"
else
  I=$(run_inv "$M" "$TMP/shim_diffparent")
  if [ "${I%%$'\t'*}" = UNMEASURED ]; then notok "mutation M2_no_header_check SURVIVED (still UNMEASURED)"
  else ok "mutation M2_no_header_check: caught -- mutant inventory status '${I%%$'\t'*}'"; fi
fi
# M3: report a failed derivation as measured again.
M=$(mk_mutant M3_measured_true \
  'dirty_submodules=[], has_unmerged=False, measured=patch_bytes is not None)' \
  'dirty_submodules=[], has_unmerged=False, measured=True)')
if [ -z "$M" ]; then notok "mutation M3_measured_true: anchor not unique in the tool"
else
  V=$(run_vp "$M" "$TMP/shim_diffparent")
  if [[ "$(detail "$V")" == *"could not be read"* ]]; then notok "mutation M3_measured_true SURVIVED"
  else ok "mutation M3_measured_true: caught -- mutant detail no longer names 'could not be read' ($(verdict "$V"))"; fi
fi

echo "=== stash patch regression guard (CON-108): pass=$pass fail=$fail ==="
[ "$fail" = 0 ]
