#!/usr/bin/env bash
# test_round11.sh — regression tests for the round-10 review findings A (moved-parent + symlink at the old name),
# B (stale-temp cleanup deleted user look-alike files), C (relative XDG_CONFIG_HOME honoured), E (invalid
# CONSTITUTION_DECISIONS_BACKUP_KEEP fallback) plus the class census (relative HOME). Each test runs the REAL wizard
# (must pass) and a sandbox MUTANT copy of the engine (must differ). Sandboxes are mktemp -d; deletes use safe_rm_rf;
# the shell's HOME is never reassigned (children get a sandbox HOME through env).
set -u
. "$(dirname "$0")/lib.sh"
new_sandbox; trap 'cleanup_sandbox' EXIT
C="$DEC_CLI"; ENGINE_DIR="$(dirname "$C")"
export CONSTITUTION_DECISIONS_TEST=1

mutant_cli() { # $1 name, then pairs "old" "new"; every old text must occur exactly once
  local name="$1"; shift; local m="$SB/mut_$name"; mkdir -p "$m"
  cp "$ENGINE_DIR/constitution_decisions.sh" "$ENGINE_DIR/decisions_engine.py" "$m/" || return 1
  python3 -I - "$m/decisions_engine.py" "$@" <<'PY' || return 1
import sys
p = sys.argv[1]; s = open(p).read(); a = sys.argv[2:]
for i in range(0, len(a), 2):
    if s.count(a[i]) != 1: sys.exit(1)
    s = s.replace(a[i], a[i + 1], 1)
open(p, "w").write(s)
PY
  printf '%s' "$m/constitution_decisions.sh"
}
mkproj() { local p="${SB:?}/$1"; mkdir -p "$p/submodules/constitution"
  git -C "$p" init -q -b main 2>/dev/null || git -C "$p" init -q; printf '# P\n' >"$p/CLAUDE.md"; printf '%s' "$p"; }

# ---- A: parent MOVED into a plain directory inside the project, symlink left at the old name -----------------------
move_case() { # $1 = cli; sets MRC, HIT (x.md landed in nested/sub)
  local cli="$1" p; p="$(mkproj "mv$RANDOM$RANDOM")"; mkdir -p "$p/sub" "$p/nested"
  "$cli" --project-root "$p" --non-interactive --doc sub/x.md --set calibration.floor=0.95 >"$p.out" 2>"$p.err" &
  local pid=$! i
  for i in $(seq 1 80); do ls "$p"/sub/.x.md.tmp.* >/dev/null 2>&1 && break; sleep 0.1; done  # the descriptor is open, the write window is running
  mv "$p/sub" "$p/nested/sub" && ln -s nested/sub "$p/sub"
  wait "$pid"; MRC=$?
  HIT=0; [ -e "$p/nested/sub/x.md" ] && HIT=1; MP="$p"
}
echo "== A: parent moved, symlink at the old name (inode unchanged) =="
export CONSTITUTION_DECISIONS_TEST_WRITE_DELAY=2
move_case "$C"
check "real engine: nothing lands in the moved directory (hit=$HIT)" test "$HIT" = 0
check "real engine: exits 3 (rc=$MRC)" test "$MRC" -eq 3
check "real engine: the refusal says the parent changed" grep -qi 'changed while this run was working' "$MP.err"
MA="$(mutant_cli ra '            if os.path.realpath(d) != d or not self.contains(d):' '            if not self.contains(d):')"
check "mutant A (realpath not compared) built" test -n "$MA"
move_case "$MA"
check "mutant A is caught: x.md lands in the moved directory (hit=$HIT rc=$MRC)" test "$HIT" = 1
unset CONSTITUTION_DECISIONS_TEST_WRITE_DELAY

# ---- B: stale-temp cleanup removes only the wizard's own temp form --------------------------------------------
echo "== B: user files that merely start like a wizard temp survive; a genuine stale wizard temp is cleaned =="
stale_case() { # $1 = cli, $2 = scope (project|user); sets survivors left, STALE_GONE
  local cli="$1" sc="$2" p; p="$(mkproj "st$RANDOM$RANDOM")"; mkdir -p "$p/sub" "$p/.constitution"
  local ud="${SB:?}/ucfg$RANDOM"; mkdir -p "$ud"
  local uf="$ud/decisions.yml"
  LOOK=(".CLAUDE.md.tmp.notes" ".AGENTS.md.tmp.x" ".CLAUDE.md.tmp.0123456789abc" ".CLAUDE.md.tmp.0123456789AB"
        ".CLAUDE.md.tmp.")
  : >"$p/AGENTS.md"
  local f
  for f in "${LOOK[@]}"; do : >"$p/$f"; done
  : >"$p/.constitution/.decisions.yml.tmp.keepme"; : >"$p/sub/.x.md.tmp.notes"
  : >"$p/.CLAUDE.md.tmp.0123456789ab"; : >"$p/sub/.x.md.tmp.0123456789ab"; : >"$p/.constitution/.decisions.yml.tmp.0123456789ab"
  : >"$ud/.decisions.yml.tmp.notes"; : >"$ud/.decisions.yml.tmp.0123456789ab"
  if [ "$sc" = user ]; then
    CONSTITUTION_DECISIONS_USER_FILE="$uf" "$cli" --project-root "$p" --scope user --non-interactive --set calibration.floor=0.95 >/dev/null 2>&1
  else
    CONSTITUTION_DECISIONS_USER_FILE="$uf" "$cli" --project-root "$p" --non-interactive --doc sub/x.md --set calibration.floor=0.95 >/dev/null 2>&1
  fi
  SURV=0
  for f in "${LOOK[@]}"; do [ -e "$p/$f" ] && SURV=$((SURV+1)); done
  if [ "$sc" = user ]; then
    [ -e "$ud/.decisions.yml.tmp.notes" ] && SURV=$((SURV+1)); [ -e "$ud/.decisions.yml.tmp.0123456789ab" ] && STALE_GONE=0 || STALE_GONE=1
  else
    [ -e "$p/.constitution/.decisions.yml.tmp.keepme" ] && SURV=$((SURV+1)); [ -e "$p/sub/.x.md.tmp.notes" ] && SURV=$((SURV+1))
    if [ ! -e "$p/.CLAUDE.md.tmp.0123456789ab" ] && [ ! -e "$p/sub/.x.md.tmp.0123456789ab" ] \
       && [ ! -e "$p/.constitution/.decisions.yml.tmp.0123456789ab" ]; then STALE_GONE=1; else STALE_GONE=0; fi
  fi
}
stale_case "$C" project
check "real engine (project run): all 5 root + 2 dir look-alike files survive (survivors=$SURV, want 7)" test "$SURV" = 7
check "real engine (project run): genuine stale wizard temps (root, doc dir, .constitution) are cleaned" test "$STALE_GONE" = 1
stale_case "$C" user
check "real engine (user run): look-alike files survive (survivors=$SURV, want 6)" test "$SURV" = 6
check "real engine (user run): a genuine stale wizard temp in the user-file dir is cleaned" test "$STALE_GONE" = 1
MB="$(mutant_cli rb 'if rx.fullmatch(e) and os.path.isfile(fp)' 'if e.startswith("." + name + ".tmp.") and os.path.isfile(fp)')"
check "mutant B (prefix match) built" test -n "$MB"
stale_case "$MB" project
check "mutant B is caught (project run): look-alikes are deleted (survivors=$SURV)" test "$SURV" -lt 7
stale_case "$MB" user
check "mutant B is caught (user run): the look-alike is deleted (survivors=$SURV)" test "$SURV" -lt 6
MB2="$(mutant_cli rb2 'r"\.tmp\.[0-9a-f]{12}")' 'r"\.tmp\.[0-9a-f]{0,12}")')"
check "mutant B2 (hex length loosened) built" test -n "$MB2"
stale_case "$MB2" project
check "mutant B2 is caught: a 13-hex / short look-alike is deleted (survivors=$SURV)" test "$SURV" -lt 7
# the pattern equals what atomic_write creates (a real run leaves no temp, so assert the form by construction)
check "atomic_write's temp form is '.<name>.tmp.<12 hex>' (matches the cleanup pattern)" python3 -I -c '
import sys, re; sys.dont_write_bytecode = True; sys.path.insert(0, sys.argv[1])
import decisions_engine as E, inspect
src = inspect.getsource(E.atomic_write)
assert "\".%s.tmp.%s\" % (name, secrets.token_hex(6))" in src
assert re.fullmatch(r"\.x\.md\.tmp\.[0-9a-f]{12}", ".x.md.tmp." + __import__("secrets").token_hex(6))' "$ENGINE_DIR"

# ---- C: relative XDG_CONFIG_HOME is ignored ---------------------------------------------------------------------
echo "== C: a relative XDG_CONFIG_HOME is ignored (user layer must not land in the caller's cwd) =="
xdg_case() { # $1 = cli; sets LANDED (a decisions file under the cwd repo B), XHOME (written under the sandbox home)
  local cli="$1" a b h; a="$(mkproj "xa$RANDOM$RANDOM")"; b="${SB:?}/xb$RANDOM$RANDOM"; h="${SB:?}/xh$RANDOM$RANDOM"
  mkdir -p "$b/constitution" "$h"; git -C "$b" init -q
  ( cd "$b" && env -u CONSTITUTION_DECISIONS_USER_FILE "XDG_CONFIG_HOME=." "HOME=$h" \
      "$cli" --project-root "$a" --scope user --non-interactive --set calibration.floor=0.95 >"$a.out" 2>"$a.err" )
  LANDED=0; { [ -e "$b/constitution/decisions.yml" ] || [ -e "$b/constitution/.decisions.lock" ]; } && LANDED=1
  XHOME=0; [ -e "$h/.config/constitution/decisions.yml" ] && XHOME=1
}
xdg_case "$C"
check "real engine: nothing written into the cwd repository (landed=$LANDED)" test "$LANDED" = 0
check "real engine: the user file went to \$HOME/.config (home=$XHOME)" test "$XHOME" = 1
MC="$(mutant_cli rc 'if not base or not os.path.isabs(base):' 'if not base:')"
check "mutant C (relative XDG honoured) built" test -n "$MC"
xdg_case "$MC"
check "mutant C is caught: the cwd repository receives the file (landed=$LANDED home=$XHOME)" bash -c "[ '$LANDED' = 1 ] || [ '$XHOME' = 0 ]"
echo "== C census: relative HOME is never trusted (user_file fallback and home_dirs) =="
homerel() { python3 -I -c '
import sys, os, tempfile; sys.dont_write_bytecode = True; sys.path.insert(0, sys.argv[1])
import decisions_engine as E
d = tempfile.mkdtemp(dir=sys.argv[2]); os.chdir(d)
os.environ["HOME"] = "."; os.environ.pop("XDG_CONFIG_HOME", None); os.environ.pop("CONSTITUTION_DECISIONS_USER_FILE", None)
errs = []
if os.path.realpath(d) in E.home_dirs(): errs.append("home_dirs trusts a relative HOME")
u = E.user_file()
if not os.path.isabs(u) or os.path.realpath(u).startswith(os.path.realpath(d) + os.sep): errs.append("user_file under cwd: " + u)
print("OK" if not errs else "; ".join(errs)); sys.exit(1 if errs else 0)' "$1" "$SB"; }
check "real engine: relative HOME ignored" homerel "$ENGINE_DIR"
MH="$(mutant_cli rh 'if h and os.path.isabs(h):' 'if h:')"
check "mutant H (relative HOME trusted) built" test -n "$MH"
homerel "$(dirname "$MH")" >/dev/null 2>&1; hr=$?
check "mutant H is caught (rc=$hr)" test "$hr" -ne 0

# ---- E: invalid BACKUP_KEEP falls back to 20 ----------------------------------------------------------------------
echo "== E: CONSTITUTION_DECISIONS_BACKUP_KEEP 0 / negative / non-numeric falls back to 20 =="
keep_case() { # $1 = cli, $2 = value; sets NB (backups kept after 4 changing runs)
  local cli="$1" p f; p="$(mkproj "bk$RANDOM$RANDOM")"
  for f in 0.91 0.92 0.93 0.94; do
    CONSTITUTION_DECISIONS_BACKUP_KEEP="$2" "$cli" --project-root "$p" --non-interactive --set calibration.floor=$f >/dev/null 2>&1
  done
  NB="$(find "$p/.constitution-install-backup" -maxdepth 1 -name '*-decisions*' 2>/dev/null | wc -l)"
}
for v in 0 -3 abc ""; do keep_case "$C" "$v"; check "real engine: BACKUP_KEEP='$v' keeps >= 3 backups (kept=$NB)" test "$NB" -ge 3; done
keep_case "$C" 2; check "real engine: BACKUP_KEEP=2 prunes to 2 (kept=$NB)" test "$NB" = 2
ME="$(mutant_cli re 'r"[1-9][0-9]{0,3}", v)' 'r"[0-9]{1,4}", v)')"
check "mutant E (0 accepted) built" test -n "$ME"
keep_case "$ME" 0
check "mutant E is caught: BACKUP_KEEP=0 prunes everything (kept=$NB)" test "$NB" -le 1

finish "test_round11"
