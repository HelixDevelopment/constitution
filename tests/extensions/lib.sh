#!/usr/bin/env bash
# shellcheck disable=SC2034  # T_NAME, OUT and RC are shared with lib.sh
# tests/extensions/lib.sh — shared helpers for the extension-engine test suites (sourced, never executed).
#
# ── Purpose ───────────────────────────────────────────────────────────────
# Sandbox creation (explicit `mktemp -d`, cleaned with safe_rm_rf restricted to the sandbox), git
# isolation (GIT_CONFIG_GLOBAL inside the sandbox), assertion counters, and builders:
#   make_root DIR      a minimal constitution root (Constitution.md, find_constitution.sh, git repo)
#   make_project DIR   a consumer git repo with one commit
#   copy_fixture NAME DEST   copies tests/extensions/fixtures/NAME (labelled TEST FIXTURES)
#   eng ARGS...        runs the engine under test; output in $OUT, exit code in $RC
# The engine under test is $CONSTITUTION_EXT_ENGINE when set (mutation tests point it at a mutated
# copy), else scripts/constitution_ext/constitution_ext.sh of this working tree.
#
# ── Safety ────────────────────────────────────────────────────────────────
#   * $HOME is never reassigned and never written; the real repository is only read.
#   * Every recursive delete goes through safe_rm_rf with SAFE_RM_ALLOWED_ROOTS set to the sandbox.
#   * Jev disabled (CONSTITUTION_JEV_HOOK=off); no LLM calls anywhere.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIX="$REPO/tests/extensions/fixtures"
ENGINE="${CONSTITUTION_EXT_ENGINE:-$REPO/scripts/constitution_ext/constitution_ext.sh}"
# shellcheck source=../../scripts/lib/safe_rm.sh
. "$REPO/scripts/lib/safe_rm.sh"
export CONSTITUTION_JEV_HOOK=off
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=ext-test GIT_AUTHOR_EMAIL=t@example.invalid
export GIT_COMMITTER_NAME=ext-test GIT_COMMITTER_EMAIL=t@example.invalid
export GIT_TERMINAL_PROMPT=0
export CONSTITUTION_EXT_NO_TTY=1
unset ANTHROPIC_API_KEY CONSTITUTION_DIR CONSTITUTION_EXT_TEST_MODE CONSTITUTION_EXT_TEST_KILL_AT 2>/dev/null || true

T_PASS=0; T_FAIL=0; T_NAME="${T_NAME:-ext-tests}"
ok()   { T_PASS=$((T_PASS+1)); printf '  ok   %s\n' "$*"; }
nok()  { T_FAIL=$((T_FAIL+1)); printf '  FAIL %s\n' "$*"; }
check() { local d="$1"; shift; if "$@"; then ok "$d"; else nok "$d"; fi; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else nok "$1 (expected [$2] got [$3])"; fi; }
has() { case "$3" in *"$2"*) ok "$1";; *) nok "$1 (missing [$2] in: $(printf '%s' "$3" | head -c 600))";; esac; }
hasnt() { case "$3" in *"$2"*) nok "$1 (unexpected [$2])";; *) ok "$1";; esac; }
finish() { printf '%s: PASS %d FAIL %d\n' "$T_NAME" "$T_PASS" "$T_FAIL"; [ "$T_FAIL" -eq 0 ]; }

new_sandbox() {
  SB="$(mktemp -d "${TMPDIR:-/tmp}/helix-ext-test.XXXXXX")" || { echo "mktemp failed" >&2; exit 2; }
  # T1: a TMPDIR that is a symlink or contains '..' must not change any path the suites compare; the sandbox is
  # resolved once, here, and every later path is built from the canonical form
  SB="$(realpath -e "$SB")" || { echo "realpath failed" >&2; exit 2; }
  export SAFE_RM_ALLOWED_ROOTS="$SB"
  export GIT_CONFIG_GLOBAL="$SB/gitconfig"
  printf '[init]\n\tdefaultBranch = main\n[advice]\n\tdetachedHead = false\n[protocol "file"]\n\tallow = always\n' >"$GIT_CONFIG_GLOBAL"
  # Test-harness proof (R19): the engine honours its test seams (kill points, version override) only
  # when CONSTITUTION_EXT_TEST_NONCE equals <parent of the project>/.constitution-ext-test-nonce (0600).
  # Projects in these tests live directly under $SB.
  CONSTITUTION_EXT_TEST_NONCE="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
  export CONSTITUTION_EXT_TEST_NONCE
  ( umask 077; printf '%s\n' "$CONSTITUTION_EXT_TEST_NONCE" >"$SB/.constitution-ext-test-nonce" )
  trap 'cleanup_sandbox' EXIT
}
cleanup_sandbox() {
  [ -n "${SB:-}" ] && [ -d "$SB" ] || return 0
  chmod -R u+w "${SB:?}" 2>/dev/null || true
  safe_rm_rf "${SB:?}"
}

# make_root DIR — minimal constitution root: Constitution.md naming two anchors, a tool target,
# an empty extensions/ dir, committed in its own git repo tagged helixconstitution-v72.1.
make_root() {
  local r="${1:?}"
  mkdir -p "$r/extensions" "$r/scripts/lib" || return 1
  printf '# TEST FIXTURE constitution root\n\n### §11.4.228 — fixture anchor\n### §11.4.287 — fixture anchor\n' >"$r/Constitution.md"
  printf '#!/usr/bin/env bash\necho fixture\n' >"$r/find_constitution.sh"
  printf 'keep\n' >"$r/extensions/.keep"
  git -C "$r" init -q && git -C "$r" add -A && git -C "$r" commit -q -m "fixture root" \
    && git -C "$r" tag -a helixconstitution-v72.1 -m t
}
make_project() {
  local p="${1:?}"
  mkdir -p "$p" && git -C "$p" init -q && printf '# demo\n' >"$p/README.md" \
    && git -C "$p" add README.md && git -C "$p" commit -q -m init
}
copy_fixture() { mkdir -p "${2:?}" && cp -R "$FIX/${1:?}/." "$2/"; }

# eng ARGS... — runs the engine; stdout+stderr in $OUT, exit code in $RC. Never reads a TTY.
eng() { OUT="$(bash "$ENGINE" "$@" </dev/null 2>&1)"; RC=$?; }
# engj ARGS... — stdout only (for --json parsing) in $OUT, rc in $RC.
engj() { OUT="$(bash "$ENGINE" "$@" </dev/null 2>/dev/null)"; RC=$?; }
jget() { python3 -I -c 'import json,sys; v=json.loads(sys.argv[1])
for k in sys.argv[2].split("."):
    v = v[int(k)] if isinstance(v, list) else v[k]
print(json.dumps(v) if isinstance(v,(dict,list,bool)) or v is None else v)' "$1" "$2"; }

# tree_fp DIR — sha256 over every path + content + mode + link target, sorted (excludes .git).
tree_fp() {
  python3 -I - "${1:?}" <<'PY'
import hashlib, os, stat, sys
root = sys.argv[1]; h = hashlib.sha256()
if not os.path.exists(root):
    print("absent"); sys.exit(0)
for dp, dns, fns in os.walk(root):
    dns[:] = sorted(d for d in dns if d != ".git")
    for n in sorted(dns + fns):
        p = os.path.join(dp, n); st = os.lstat(p)
        h.update(os.path.relpath(p, root).encode() + b"\0" + oct(st.st_mode).encode() + b"\0")
        if stat.S_ISREG(st.st_mode):
            with open(p, "rb") as f: h.update(hashlib.sha256(f.read()).digest())
        elif stat.S_ISLNK(st.st_mode):
            h.update(os.readlink(p).encode())
print(h.hexdigest())
PY
}

# ext_git_repo SRC DEST — turns a copy of extension dir SRC into a git repo at DEST; prints HEAD sha.
ext_git_repo() {
  local s="${1:?}" d="${2:?}"
  mkdir -p "$d" && cp -R "$s/." "$d/" && git -C "$d" init -q && git -C "$d" add -A \
    && git -C "$d" commit -q -m "fixture extension" && git -C "$d" rev-parse HEAD
}

# fake_token KIND — builds secret-SHAPED strings at run time from fragments so no literal
# credential shape is stored in this repository (credscan stays clean). Not real credentials.
fake_token() {
  case "${1:?}" in
    gh) printf '%s%s%s' 'gh' 'p_' 'Zq7Rk2Lm9Xw4Tb8Vn1Hc6Jd3Fs5Gy0Pa2Qe7' ;;
    aws) printf '%s%s' 'AK' 'IAZQ7RK2LM9XW4TB8V' ;;
    sk) printf '%s%s' 's' 'k-Zq7Rk2Lm9Xw4Tb8Vn1Hc6Jd3Fs5Gy0Pa2Qe7Wu' ;;
    pem) printf '%s%s' '-----BEG' 'IN PRIVATE KEY-----' ;;
  esac
}

# sign_journal FILE PROJECT — rewrite a handwritten journal with the project's own HMAC (round 11), so a test can
# present a journal this project could have written
sign_journal() {
  python3 -I - "$1" "$2" <<'PY'
import hashlib, hmac, json, sys
f, proj = sys.argv[1:3]
j = json.load(open(f)); j.pop("mac", None)
key = open(proj + "/.constitution/extensions.state/key", "rb").read().strip()
msg = b"journal-" + str(j["op"]).encode() + b"\0" + json.dumps(j, sort_keys=True, separators=(",", ":")).encode()
j["mac"] = hmac.new(key, msg, hashlib.sha256).hexdigest()
json.dump(j, open(f, "w"))
PY
}
