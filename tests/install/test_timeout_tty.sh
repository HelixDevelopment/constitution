#!/usr/bin/env bash
# test_timeout_tty.sh — every `timeout` reachable from the installer, the updater, the post-update hook and the
# Jev bootstrap (the file set is derived, see the census below) ignores SIGTTIN/SIGTTOU before timeout starts or
# is classified as unable to meet the terminal; the sites below are also run at a real terminal with GNU timeout
# and with uutils timeout (CON-PENDING-installer-followups; the CON-112 mechanism class).
#
# Mechanism (measured, docs/qa/installer_followups_2026_11_14/): timeout without --foreground moves itself and the
# command into a NEW process group, which is a BACKGROUND group of the terminal. A command that then touches the
# terminal (tcsetattr, a read of /dev/tty) makes the kernel send SIGTTOU/SIGTTIN to that whole group. GNU timeout
# ignores both signals and its timer still fires; uutils timeout (0.10.0 measured) does not ignore them, so it is
# stopped together with the command and never fires: the run hangs for ever, also with --kill-after. With
# SIGTTIN/SIGTTOU ignored when timeout starts (inherited SIG_IGN), both implementations end at the budget.
#
# Cases, each in a fresh pseudo-terminal whose session leader is the bash that sources the script (the topology of
# a script run from an interactive shell), with a stub command that changes the terminal mode and then sleeps:
#   T1 installer hi_gx (HI_GX_TIMEOUT) · T2 updater hi_gx · T3 hi_version_of (5 s) ·
#   T4 hi_detect_agents, claude-list-accounts (20 s) · T5 hi_detect_agents, claude-providers list (20 s) ·
#   T6 hi_run_agent (O_TIMEOUT 2, --kill-after 10) · T7 a stub that reads /dev/tty (installer hi_gx) ·
#   T8 post_update_hook.sh install_jev_bootstrap (JEV_HOOK_TIMEOUT 2: the run, then the --defer retry)
# Each case runs under each implementation found on the host; an implementation that is absent is reported as
# SKIP (never as PASS). A case passes only when the body really ran (its exit status is the expected number), it
# waited for the cut (at least budget - 0.5 s), it returned within budget + margin, and no process is left in the
# terminal's session. Control needle: the same stub under `timeout` WITHOUT the ignore (a direct call) must hang
# under uutils (if uutils is present), else this host cannot show the defect and the uutils legs are BLIND.
# Before the cases, a static census lists every `timeout` site (function, and whether SIGTTIN/SIGTTOU are ignored
# BEFORE it: an ignore after the timeout on the same line never counts) in every file reachable from the four entry
# scripts (a file name or a scripts/... path on a non-comment line, also scripts/x/$v.sh with $v from a `for v in`
# list; tests/, .git and submodules/ are not followed), and compares it with the reviewed list in this file: a new
# site fails until it is classified (control needles on a small tree: reachability, an ignored, a bare, a
# --foreground and an ignore-after-timeout site are told apart, else BLIND). Sites the census cannot see (a timeout
# reached only through a binary, or a file named only at run time) are outside this test.
#
# TEST-CLASS LABEL (§11.4.289): unit / gate-logic class. Stub commands, no network, no agent; the pty is real.
# Usage: bash tests/install/test_timeout_tty.sh   Exit 0 all pass · 1 a case failed · 2 blind.
# shellcheck disable=SC1090  # the files under test are sourced by variable
# shellcheck disable=SC2034  # T_NAME is read by finish() in lib.sh
T_NAME=timeout_tty
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
new_sandbox
command -v python3 >/dev/null 2>&1 || { echo "python3 is required (pty driver)"; exit 2; }

# ── implementations ──
GNU=""; UU=""
for c in gnutimeout timeout /usr/bin/gnutimeout /usr/bin/timeout /usr/lib/cargo/bin/coreutils/timeout; do
  p="$(command -v "$c" 2>/dev/null)" || continue
  v="$("$p" --version 2>&1 </dev/null)"
  case "$v" in
    *"GNU coreutils"*) [ -n "$GNU" ] || GNU="$p" ;;
    *uutils*) [ -n "$UU" ] || UU="$p" ;;
  esac
done
echo "  GNU timeout: ${GNU:-absent}   uutils timeout: ${UU:-absent}"

# ── stubs ──
STUB="$SB/stubs"; mkdir -p "$STUB"
tty_stub() { printf '#!/bin/sh\n# test stub: change the terminal mode, then sit\nstty -echo </dev/tty 2>/dev/null\nexec sleep 300\n' >"$STUB/$1"; chmod 755 "$STUB/$1"; }
tty_stub git; tty_stub agentx; tty_stub claude-list-accounts; tty_stub claude-providers; tty_stub kimi
printf '#!/bin/sh\nexec sleep 0\n' >"$STUB/claude"; chmod 755 "$STUB/claude"
printf '#!/bin/sh\n# test stub: read the terminal, then sit\nread x </dev/tty\nexec sleep 300\n' >"$STUB/git-read"; chmod 755 "$STUB/git-read"

# ── the pty driver: runs bash -c SCRIPT as the session leader of a new pseudo-terminal ──
# argv: CAP_SECONDS SCRIPT → prints "rc=N secs=S left=K" or "rc=CAPPED secs=S left=K"
# shellcheck disable=SC2016  # Python source
drv='import os, pty, re, select, signal, subprocess, sys, time
cap = float(sys.argv[1]); script = sys.argv[2]
def members(sid):
    o = subprocess.run(["ps", "-s", str(sid), "-o", "pid="], capture_output=True, text=True).stdout.split()
    return [int(p) for p in o if int(p) > 1 and int(p) != os.getpid()]
def kill_all(sid):
    if sid <= 1 or sid == os.getsid(0): return
    for p in members(sid):
        try: os.kill(p, signal.SIGKILL)
        except ProcessLookupError: pass
pid, fd = pty.fork()
if pid == 0:
    os.execvp("bash", ["bash", "-c", script + "\nprintf \"\\nDRV_RC=%s\\n\" \"$rc\""])
# pty.fork makes the child a session leader (setsid) before it execs bash: its session id is its pid. Reading the
# id by polling getsid() raced with that setsid, and a run that ended before a poll saw it counted nothing (F-2)
t0 = time.monotonic(); out = b""; rc = "CAPPED"; sid = pid
while True:
    r, _, _ = select.select([fd], [], [], 0.2)
    if r:
        try: out += os.read(fd, 65536)
        except OSError: pass
    w, st = os.waitpid(pid, os.WNOHANG)
    if w == pid:
        # read what the shell printed; bounded: a leftover that holds the terminal open would keep EOF away
        t2 = time.monotonic()
        try:
            while time.monotonic() - t2 < 2:
                r, _, _ = select.select([fd], [], [], 0.2)
                if not r: continue
                b = os.read(fd, 65536)
                if not b: break
                out += b
        except OSError: pass
        m = re.search(rb"DRV_RC=(\d+)", out); rc = m.group(1).decode() if m else "none"; break
    if time.monotonic() - t0 > cap:
        kill_all(sid)
        os.waitpid(pid, 0); break
el = time.monotonic() - t0
# a member killed together with the cut command can still be exiting when the shell returns (an orphaned stty
# of the stub, for one): drain for up to 3 s before counting; a real leftover (sleep 300) is still there then
left = members(sid)
t1 = time.monotonic()
while left and time.monotonic() - t1 < 3: time.sleep(0.1); left = members(sid)
if left: kill_all(sid)
if os.environ.get("TT_DEBUG") == "1": sys.stderr.write("DRV-OUT %r\n" % out[-400:])
print("rc=%s secs=%.1f left=%d" % (rc, el, len(left)))'
drive() { python3 -I -c "$drv" "$@"; }
# control needle: the "left" counter sees a process that stays in the session (else BLIND). It ignores SIGHUP: the
# kernel hangs up the terminal's foreground group when the session leader exits, which would end it at once
ndl_left="$(drive 10 'trap "" HUP; sleep 30 & rc=0')"
case "$ndl_left" in
  "rc=0 "*"left=1") ok "driver control needle: a process left in the session is counted ($ndl_left)" ;;
  *) echo "  BLIND driver: a process left in the session is not counted ($ndl_left)"; finish; exit 2 ;;
esac

# ── one case: label impl want-rc budget margin cap prologue body ──
# passes only when: the body really ran (rc is the expected number, never "src" or "none"), it waited for the
# timeout (at least budget - 0.5 s: the stub sat until it was cut), it returned within budget + margin, and no
# process is left in the terminal's session
leg() {
  local label="$1" impl="$2" want="$3" budget="$4" margin="$5" cap="$6" body="$7" out rc secs left
  out="$(drive "$cap" "$body")"
  rc="${out#rc=}"; rc="${rc%% *}"; secs="${out#*secs=}"; secs="${secs%% *}"; left="${out##*left=}"
  if [ "$rc" = "$want" ] && [ "$left" = 0 ] \
     && awk -v s="$secs" -v b="$budget" -v m="$margin" 'BEGIN { exit !(s + 0 >= b - 0.5 && s + 0 <= b + m) }'; then
    ok "$label [$impl]: rc=$rc after ${secs}s (budget ${budget}s), nothing left"
  else
    nok "$label [$impl]: $out (want rc=$want, ${budget}s to $((budget + margin))s, nothing left)"
  fi
}

# common prologue of every case: PATH with the stubs first, the script sourced in library mode
# (the text ends in "; " because $(...) strips a trailing newline; a failed source sets rc=src, which no leg accepts)
pro_i() { printf 'export PATH=%q:/usr/bin:/bin; rc=src; HELIX_INSTALLER_LIB_MODE=1 . %q >/dev/null 2>&1 && ' "$1" "$INSTALLER"; }
pro_u() { printf 'export PATH=%q:/usr/bin:/bin; rc=src; HELIX_UPDATER_LIB_MODE=1 . %q >/dev/null 2>&1 && ' "$1" "$UPDATER"; }

# ── static census: every `timeout` reachable from the entry scripts, and how each is protected ──
# A new timeout site fails this check until it is classified here (with the ignore, with --foreground, or with a
# reason it cannot touch the terminal). Function names, not line numbers. The file set is derived, not listed.
# shellcheck disable=SC2016  # Python source
census='import os, re, sys
# argv: ROOT ENTRY... -> one line per site: file<TAB>function<TAB>yes|fg|no<TAB>line<TAB>text
SITE = re.compile(r"(?<![\w.-])(?:/[\w.-]+)*/?g?timeout\s+(?=[-\d$\"\x27])")
FN = re.compile(r"^\s*(?:function\s+)?([A-Za-z_][\w:-]*)\s*\(\)\s*\{")
REF = re.compile(r"([A-Za-z0-9_.-]+\.(?:sh|bash|py))\b")
VREF = re.compile(r"\$\{?([A-Za-z_]\w*)\}?\.(sh|bash|py)\b")
LOOP = re.compile(r"\bfor\s+([A-Za-z_]\w*)\s+in\s+([^;&|]+?)\s*(?:;|$)")
IGN = "trap \x27\x27 TTIN TTOU"
SKIP = (".git", "submodules", "node_modules", "tests")
def closure(root, entries):
    base = {}
    for dp, dn, fn in os.walk(root):
        dn[:] = sorted(x for x in dn if x not in SKIP)
        rel = os.path.relpath(dp, root)
        for f in fn:
            if f.endswith((".sh", ".bash", ".py")):
                base.setdefault(f, []).append(os.path.normpath(os.path.join(rel, f)))
    seen, todo = set(), list(entries)
    while todo:
        f = todo.pop()
        if f in seen: continue
        seen.add(f)
        try: text = open(os.path.join(root, f), encoding="utf-8", errors="replace").read().splitlines()
        except OSError: continue
        code = [l for l in text if not l.lstrip().startswith("#")]
        loops = {}
        for line in code:
            for m in LOOP.finditer(line):
                loops.setdefault(m.group(1), []).extend(w for w in m.group(2).split() if re.fullmatch(r"[\w.-]+", w))
        def pick(name, tok):
            # a path written with scripts/... picks that file; else the same directory; else every file of the name
            cands = base.get(name, []); k = tok.rfind("scripts/")
            return [c for c in cands if k >= 0 and c.endswith(tok[k:])] \
                or [c for c in cands if os.path.dirname(c) == os.path.dirname(f)] or cands
        for line in code:
            for m in VREF.finditer(line):
                pre = line[max(0, m.start() - 200):m.start()]
                for w in loops.get(m.group(1), []):
                    n = w + "." + m.group(2); todo.extend(c for c in pick(n, pre + n) if c not in seen)
            for m in REF.finditer(line):
                todo.extend(c for c in pick(m.group(1), line[max(0, m.start() - 200):m.end()]) if c not in seen)
    return sorted(seen)
def scan(root, f):
    out = []; fn = "-"; seen_ign = False
    for n, line in enumerate(open(os.path.join(root, f), encoding="utf-8", errors="replace"), 1):
        here = fn; m = FN.match(line)
        if m and line.rstrip().endswith("}"): here = m.group(1)   # a one-line function covers its own line only
        elif m: fn = here = m.group(1); seen_ign = False
        elif line.startswith("}"): fn = "-"; seen_ign = False
        if line.lstrip().startswith("#"): continue
        for s in SITE.finditer(line):
            if line[s.end():].startswith("--foreground"): cls = "fg"
            elif IGN in line[:s.start()] or seen_ign: cls = "yes"   # an ignore AFTER the timeout never counts
            else: cls = "no"
            out.append((f, here, cls, n, line.strip()[:150]))
        if line.strip() == IGN: seen_ign = True   # only a statement of its own covers later lines of the function
    return out
root = sys.argv[1]
for f in closure(root, sys.argv[2:]):
    for r in scan(root, f): print("%s\t%s\t%s\t%d\t%s" % r)'
# control needles, a small tree: a.sh reaches lib/b.sh (a path) and scripts/x/c.sh (scripts/x/$g.sh, g from a for
# list); d.sh is named only in a comment and tests/e.sh is under tests/, so neither is followed. Sites: a standalone
# ignore covers a later site (fa yes), none (fb no), an ignore inside a group covers its own line only (fc yes, then
# no), an ignore AFTER the timeout on the same line is not credited (no), --foreground (fg), a timeout word list in
# a string (no), and the bare site of c.sh
CN="$SB/tcensus_tree"; mkdir -p "$CN/lib" "$CN/scripts/x" "$CN/tests"
printf '%s\n' "fa() {" "  trap '' TTIN TTOU" '  timeout 5 x' "}" "fb() {" '  timeout 5 y' "}" \
  '. "$(dirname "$0")/lib/b.sh"' 'bash tests/e.sh' '# d.sh is not run from here' >"$CN/a.sh"
printf '%s\n' "fc() {" "  { trap '' TTIN TTOU; timeout 5 z; } | cat" '  timeout 5 w | cat' \
  "  { timeout 5 v; trap '' TTIN TTOU; } | cat" '  timeout --foreground 5 f' '  _to="timeout 5"' "}" \
  'for g in c; do bash "$R/scripts/x/$g.sh"; done' >"$CN/lib/b.sh"
printf '%s\n' 'timeout 5 cc' >"$CN/scripts/x/c.sh"
printf '%s\n' 'timeout 5 dd' >"$CN/d.sh"
printf '%s\n' 'timeout 5 ee' >"$CN/tests/e.sh"
ndl_got="$( (cd "$CN" && python3 -I -c "$census" . a.sh) | awk -F'\t' '{ print $1 "|" $2 "|" $3 }')"
ndl_want="$(printf '%s\n' 'a.sh|fa|yes' 'a.sh|fb|no' 'lib/b.sh|fc|yes' 'lib/b.sh|fc|no' 'lib/b.sh|fc|no' \
  'lib/b.sh|fc|fg' 'lib/b.sh|fc|no' 'scripts/x/c.sh|-|no')"
ENTRIES=(scripts/install_constitution.sh scripts/update_constitution.sh scripts/post_update_hook.sh scripts/jev/bootstrap.sh)
if [ "$ndl_got" = "$ndl_want" ] && sites="$(cd "$REPO" && python3 -I -c "$census" . "${ENTRIES[@]}")" && [ -n "$sites" ]; then
  ok "timeout census control needles: reachability, ignored / bare / --foreground / ignore-after-timeout sites told apart"
  got="$(printf '%s\n' "$sites" | awk -F'\t' '{ print $1 "|" $2 "|" $3 }')"
  want="$(printf '%s\n' \
    'scripts/gates/cm_jev_detection.sh|-|yes' \
    'scripts/install_constitution.sh|hi_gx|yes' 'scripts/install_constitution.sh|hi_version_of|yes' \
    'scripts/install_constitution.sh|hi_detect_agents|yes' 'scripts/install_constitution.sh|hi_detect_agents|yes' \
    'scripts/install_constitution.sh|hi_lock_pid|no' 'scripts/install_constitution.sh|hi_run_agent|no' \
    'scripts/jev/bootstrap.sh|run_bounded|yes' 'scripts/jev/bootstrap.sh|run_gate|yes' \
    'scripts/jev/lib_decide.sh|jev_effective_mode|yes' 'scripts/jev/lib_keys.sh|_jev_key_value|yes' \
    'scripts/label-sync/hooks/label-sync-lib.sh|ls_ctl|yes' 'scripts/label-sync/render/statusline.sh|-|yes' \
    'scripts/multitrack/multitrack_balance.sh|mt_provider_operability_probe|no' \
    'scripts/multitrack/multitrack_cwd_hook.sh|_cwh_owner_busy|yes' \
    'scripts/post_update_hook.sh|install_jev_bootstrap|yes' 'scripts/post_update_hook.sh|install_jev_bootstrap|yes' \
    'scripts/update_constitution.sh|hi_gx|yes' 'scripts/update_constitution.sh|up_lock_pid|no')"
  eq "every timeout site reachable from the four entry scripts is classified (new sites must be added here)" "$want" "$got"
  # the four "no" sites: hi_lock_pid / up_lock_pid read a regular, non-symlink file with head (checked by -f and
  # ! -L before; head never reads the terminal); hi_run_agent builds the command in an array and runs it in a
  # background job that ignores the two signals first; multitrack_balance only builds the word list in a string,
  # and the substitution that runs it ignores the two signals first
  eq "hi_run_agent: the job that runs the timeout array ignores SIGTTIN/SIGTTOU" 1 \
    "$(grep -cF "(trap '' TTIN TTOU; cd \"\$O_ROOT\" && umask" "$INSTALLER")"
  eq "multitrack_balance: the substitution that runs the timeout word list ignores SIGTTIN/SIGTTOU" 1 \
    "$(grep -cF "_code=\$(trap '' TTIN TTOU; \$_to curl" "$REPO/scripts/multitrack/multitrack_balance.sh")"
  eq "hi_lock_pid and up_lock_pid only read a regular non-symlink file" 2 \
    "$(cat "$INSTALLER" "$UPDATER" | grep -cF -e '[ -f "$f" ] && [ ! -L "$f" ] || return 1' -e '[ -n "$f" ] && [ -f "$f" ] && [ ! -L "$f" ] || return 1')"
else
  echo "  BLIND timeout census: control needles failed (got: $ndl_got)"; finish; exit 2
fi
# T8 runs the hook's own function text (post_update_hook.sh runs main on load, so it is not sourced whole)
HOOKFN="$SB/install_jev_bootstrap.sh"
awk '/^install_jev_bootstrap\(\) \{/ { p = 1 } p { print } p && /^\}/ { exit }' "$REPO/scripts/post_update_hook.sh" >"$HOOKFN"
grep -q '"$boot" --non-interactive' "$HOOKFN" && grep -q '"$boot" --defer' "$HOOKFN" \
  || { echo "  BLIND T8: install_jev_bootstrap could not be extracted from post_update_hook.sh"; finish; exit 2; }

# the ignore is for timeout only: each timeout resets SIGTTIN/SIGTTOU for the program it runs, so the program (git,
# an agent) still stops when it touches the terminal and is killed at the limit. Control: without timeout in
# between, the ignored bits are seen (TTIN 0x100000, TTOU 0x200000), so a zero below is a reading, not blindness.
sigign() { bash -c 'trap "" TTIN TTOU; "$@" awk "/^SigIgn:/ { print \$2 }" /proc/self/status' _ "$@"; }
if [ "$(( 0x$(sigign env) & 0x300000 ))" = $(( 0x300000 )) ]; then
  for t in "$GNU" "$UU"; do
    [ -n "$t" ] || continue
    eq "the program under $(basename "$t") does not inherit the ignore (SIGTTIN/SIGTTOU reset)" 0 "$(( 0x$(sigign "$t" 5) & 0x300000 ))"
  done
else
  echo "  BLIND SigIgn control: the ignored bits are not seen without timeout ($(sigign env))"; finish; exit 2
fi

blind=0
for impl in gnu uutils; do
  if [ "$impl" = gnu ]; then t="$GNU"; else t="$UU"; fi
  if [ -z "$t" ]; then echo "  SKIP $impl timeout is not installed on this host (no verdict for it)"; continue; fi
  bin="$SB/bin-$impl"; mkdir -p "$bin"; cp "$STUB"/* "$bin/"; ln -s "$t" "$bin/timeout"
  if [ "$impl" = uutils ]; then   # control needle: the stub under this timeout, no ignore, must hang
    out="$(drive 12 "export PATH=$(printf %q "$bin"):/usr/bin:/bin; timeout 2 git; rc=\$?")"
    case "$out" in rc=CAPPED*) ok "control needle [uutils]: a direct timeout of the tty stub hangs ($out)" ;;
      *) echo "  BLIND [uutils]: a direct timeout of the tty stub did not hang ($out); this host cannot show the defect"; blind=1; continue ;; esac
  fi
  leg "T1 installer hi_gx, HI_GX_TIMEOUT=2" "$impl" 124 2 4 15 "$(pro_i "$bin"){ HI_GX_TIMEOUT=2 hi_gx status; rc=\$?; }"
  leg "T2 updater hi_gx, HI_GX_TIMEOUT=2" "$impl" 124 2 4 15 "$(pro_u "$bin"){ HI_GX_TIMEOUT=2 hi_gx status; rc=\$?; }"
  leg "T3 hi_version_of (5 s)" "$impl" 0 5 4 20 "$(pro_i "$bin"){ hi_version_of $(printf %q "$bin/agentx") >/dev/null; rc=\$?; }"
  leg "T4 hi_detect_agents: claude-list-accounts (20 s)" "$impl" 0 20 5 40 \
    "$(pro_i "$bin"){ hi_agent_table() { :; }; HI_DETECT_PROVIDERS=0 hi_detect_agents >/dev/null; rc=\$?; }"
  leg "T5 hi_detect_agents: claude-providers list (20 s)" "$impl" 0 20 5 40 \
    "$(pro_i "$bin"){ rm -f -- $(printf %q "$bin/claude-list-accounts"); hi_agent_table() { :; }; HI_DETECT_PROVIDERS=1 hi_detect_agents >/dev/null; rc=\$?; }"
  cp "$STUB/claude-list-accounts" "$bin/"
  mkdir -p "$SB/root-$impl"
  leg "T6 hi_run_agent (O_TIMEOUT=2, --kill-after=10)" "$impl" 1 2 12 30 \
    "$(pro_i "$bin"){ O_AGENT=kimi O_TIMEOUT=2 O_ROOT=$(printf %q "$SB/root-$impl"); hi_run_agent p $(printf %q "$SB/log-$impl") new s 1 >/dev/null 2>&1; rc=\$?; }"
  cp "$STUB/git-read" "$bin/git"
  leg "T7 installer hi_gx, a stub that reads /dev/tty" "$impl" 124 2 4 15 "$(pro_i "$bin"){ HI_GX_TIMEOUT=2 hi_gx status; rc=\$?; }"
  cp "$STUB/git" "$bin/git"
  hc="$SB/hc-$impl"; mkdir -p "$hc/scripts/jev" "$SB/hp-$impl"; cp "$STUB/git" "$hc/scripts/jev/bootstrap.sh"
  leg "T8 post_update_hook install_jev_bootstrap, JEV_HOOK_TIMEOUT=2 (run + --defer)" "$impl" 0 4 5 30 \
    "export PATH=$(printf %q "$bin"):/usr/bin:/bin; rc=src; header() { :; }; info() { :; }; warn() { :; }; arr_len() { echo 1; }; WARNINGS=(); CONSTITUTION_JEV_HOOK=on CONST_DIR=$(printf %q "$hc") PROJECT_ROOT=$(printf %q "$SB/hp-$impl") JEV_HOOK_TIMEOUT=2; . $(printf %q "$HOOKFN") && { install_jev_bootstrap; rc=\$?; }; "
done
[ "$blind" = 1 ] && [ "$T_FAIL" = 0 ] && { finish; echo "BLIND: the uutils legs did not run"; exit 2; }
finish
