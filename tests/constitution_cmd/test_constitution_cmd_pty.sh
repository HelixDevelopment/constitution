#!/usr/bin/env bash
# shellcheck disable=SC2034  # T_NAME, OUT and RC are shared with tests/extensions/lib.sh
# tests/constitution_cmd/test_constitution_cmd_pty.sh -- the /constitution dispatcher's INTERACTIVE routes,
# driven at a REAL pty (python pty.fork) with the REAL extension engine. Review round 3 of ownership wave 2
# (finding N1): the dispatcher ran the engine under `timeout` without --foreground, so the engine was not in
# the terminal's foreground process group, its /dev/tty read got SIGTTIN and the command never finished
# (uutils timeout) or ended at its budget with nothing done (GNU timeout). The stub-engine argv tests of
# test_constitution_cmd.sh could not see that (section 11.4.289: a stub run is not evidence).
#
# Class enumerated (section 11.4.276(C)): every dispatcher route that reaches an engine /dev/tty prompt.
# The engine opens /dev/tty in exactly two places (consent() and _confirm_adopt()); consent() is reached by
# `add` (and its alias `install-extension`) and `enable`, _confirm_adopt() by `adopt-install`. Every dispatch form (argv,
# one blank-split string, --args-file) ends in cmd_extensions, so these four routes are the whole class. The dispatcher's allow list never forwards --yes, so
# all three routes ALWAYS prompt when run through the dispatcher. Each route is driven here: right answer
# (rc 0 and the effect), wrong answer (rc 3, no effect), a short budget with no answer (rc 124, bounded,
# no effect), and no controlling terminal at all (rc 3 at once). Every case runs once per installed
# `timeout` implementation (the system one, and GNU coreutils when present as gnutimeout), because the two
# behaved differently on the defect.
#
# Evidence class: LIVE for the dispatcher-to-engine path (real dispatcher, real engine, real git, real pty);
# the extension trees are the labelled TEST FIXTURES of tests/extensions/fixtures.
# Safety: one mktemp sandbox (tests/extensions/lib.sh new_sandbox), deleted with safe_rm_rf; HOME is never
# reassigned; the pty child's process group is killed only after checking its pid is an int > 1 (11.4.263).
#
# Env: CMD_SRC_ROOT = tree whose dispatcher is under test (default: this repo; the paired mutation leg at the
#      end points it at mutated copies). PTY_MUTATION_LEG=0 skips that leg (the leg runs this file again).
# Exit: 0 all pass, 1 any failure.
set -u
T_NAME=constitution-cmd-pty
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_ROOT="$(cd "$HERE/../.." && pwd)"
SRC="${CMD_SRC_ROOT:-$REAL_ROOT}"
# shellcheck source=../extensions/lib.sh
. "$REAL_ROOT/tests/extensions/lib.sh"
new_sandbox
: "${SB:?}"

# ---- a consumer project whose constitution submodule carries the dispatcher of SRC and the real engine ----
mk_constitution() {   # $1 = dir
  local d="${1:?}"
  mkdir -p "$d/scripts/constitution_cmd" "$d/scripts/constitution_ext" "$d/scripts/lib" "$d/extensions" || return 1
  cp "$SRC/scripts/constitution_cmd/constitution_cmd.sh" "$d/scripts/constitution_cmd/" || return 1
  cp "$REAL_ROOT/scripts/constitution_cmd/args_file_read.py" "$d/scripts/constitution_cmd/" || return 1
  cp "$REAL_ROOT"/scripts/constitution_ext/*.sh "$REAL_ROOT"/scripts/constitution_ext/*.py "$d/scripts/constitution_ext/" || return 1
  cp "$REAL_ROOT/scripts/lib/constitution_layout.sh" "$REAL_ROOT/scripts/lib/safe_rm.sh" \
     "$REAL_ROOT/scripts/lib/protected_paths.list" "$d/scripts/lib/" || return 1
  printf '# TEST FIXTURE constitution root\n\n### §11.4.228 — fixture anchor\n' >"$d/Constitution.md"
  printf '#!/usr/bin/env bash\necho fixture\n' >"$d/find_constitution.sh"
  printf 'keep\n' >"$d/extensions/.keep"
  copy_fixture hello-fixture "$d/extensions/hello-fixture" || return 1   # bundled: hooks-fixture requires it
  git -C "$d" init -q && git -C "$d" add -A && git -C "$d" commit -q -m vendored \
    && git -C "$d" tag -a helixconstitution-v72.1 -m t
}
mk_consumer() {   # $1 = project dir; sets C (constitution checkout) and ENG (its engine)
  local p="${1:?}" up="$1.const"
  mk_constitution "$up" || return 1
  make_project "$p" || return 1
  git -C "$p" submodule add -q "$up" constitution >/dev/null 2>&1 && git -C "$p" commit -q -m "add constitution" \
    && git -C "$p/constitution" fetch -q --tags || return 1
  C="$p/constitution"; ENG="$C/scripts/constitution_ext/constitution_ext.sh"
}

# ptyrun PROMPT_MARK TYPED DEADLINE CMD... -> runs CMD with a controlling pty in cwd $P (CONSTITUTION_EXT_NO_TTY
# unset); when PROMPT_MARK appears it types TYPED (TYPED = "-" types nothing). Sets OUT, RC (exit code; 255 when
# the driver had to kill it), PTY_PROMPT (prompt seen), PTY_KILLED (driver killed it at DEADLINE), PTY_SECS.
ptyrun() {
  local res
  res="$(cd "$P" && env -u CONSTITUTION_EXT_NO_TTY PATH="$TPATH" python3 -I - "$@" <<'PY'
import os, pty, select, signal, sys, time
mark, typed, deadline, argv = sys.argv[1].encode(), sys.argv[2], float(sys.argv[3]), sys.argv[4:]
t0 = time.time()
pid, fd = pty.fork()
if pid == 0:
    os.execvp(argv[0], argv)
buf, sent, st = b"", False, None
while time.time() - t0 < deadline:
    r, _, _ = select.select([fd], [], [], 0.2)
    if r:
        try:
            d = os.read(fd, 4096)
        except OSError:
            d = b""
        if d:
            buf += d
            if not sent and mark in buf:
                sent = True
                if typed != "-":
                    time.sleep(0.2); os.write(fd, (typed + "\n").encode())
            continue
    w, s = os.waitpid(pid, os.WNOHANG)
    if w:
        st = s
        break
killed = st is None
if killed:
    assert isinstance(pid, int) and pid > 1
    try:
        os.killpg(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    _, st = os.waitpid(pid, 0)
rc = 255 if killed else os.waitstatus_to_exitcode(st)
sys.stdout.write(buf.decode("utf-8", "replace").replace("\r", ""))
print("\nPTY_PROMPT=%s PTY_KILLED=%s PTY_SECS=%d PTY_RC=%d" % (sent, killed, int(time.time() - t0), rc))
PY
)"
  OUT="$res"
  RC="$(printf '%s\n' "$res" | sed -n 's/.*PTY_RC=\(-\{0,1\}[0-9]*\)$/\1/p' | tail -1)"
  PTY_PROMPT="$(printf '%s\n' "$res" | sed -n 's/^PTY_PROMPT=\([A-Za-z]*\) .*/\1/p' | tail -1)"
  PTY_KILLED="$(printf '%s\n' "$res" | sed -n 's/.* PTY_KILLED=\([A-Za-z]*\) .*/\1/p' | tail -1)"
  PTY_SECS="$(printf '%s\n' "$res" | sed -n 's/.* PTY_SECS=\([0-9]*\) .*/\1/p' | tail -1)"
}
DISP() { printf '%s\n' bash "$C/scripts/constitution_cmd/constitution_cmd.sh"; }
lock_enabled() { grep -A12 "id: $1\$\|id: \"$1\"" "$P/.constitution/extensions.lock.yml" 2>/dev/null | grep -q 'enabled: true'; }
engine_procs_left() { ps -eo args 2>/dev/null | grep -F "$P" | grep -F ext_engine.py | grep -vc grep; }
# notty LABEL WANT_RC ROUTE... -> the dispatcher route with no controlling terminal at all (setsid, stdin /dev/null,
# CONSTITUTION_EXT_NO_TTY unset): must refuse at once, never wait
notty() {
  local label="$1" want="$2" t0=$SECONDS; shift 2
  OUT="$(cd "$P" && env -u CONSTITUTION_EXT_NO_TTY PATH="$TPATH" setsid -w "${D[@]}" extensions "$@" </dev/null 2>&1)"; RC=$?
  eq "$label without a controlling terminal: rc $want" "$want" "$RC"
  check "$label without a controlling terminal: returned within 20 s" test $((SECONDS - t0)) -le 20
}

# ---- timeout implementations to exercise (a PATH directory whose `timeout` is the one under test) -------------
IMPLS=()
mkdir -p "$SB/bin_sys" "$SB/bin_gnu"
if SYS_T="$(command -v timeout)"; then
  ln -s "$SYS_T" "$SB/bin_sys/timeout"
  IMPLS+=("sys:$("$SYS_T" --version 2>/dev/null | head -1 | tr -s ' ' | cut -c1-40)")
fi
if GNU_T="$(command -v gnutimeout)" && [ "$(readlink -f "$GNU_T")" != "$(readlink -f "${SYS_T:-/nonexistent}")" ]; then
  ln -s "$GNU_T" "$SB/bin_gnu/timeout"; IMPLS+=("gnu:$("$GNU_T" --version 2>/dev/null | head -1 | tr -s ' ' | cut -c1-40)")
fi
[ ${#IMPLS[@]} -gt 0 ] || { nok "no timeout implementation found (the dispatcher's tmo would run unbounded)"; finish; exit $?; }
printf '  info timeout implementations under test: %s\n' "${IMPLS[*]}"
[ -n "${GNU_T:-}" ] || printf '  SKIP GNU timeout leg: gnutimeout not installed (topology_unsupported)\n'

H="$SB/hooks-src"; copy_fixture hooks-fixture "$H"
H_SHA="$(bash "$REAL_ROOT/scripts/constitution_ext/constitution_ext.sh" --root "$REAL_ROOT" validate "$H" </dev/null 2>/dev/null \
          | grep -o '[0-9a-f]\{64\}' | head -1)"
[ -n "$H_SHA" ] || nok "setup: validate printed the hooks-fixture content sha256"
FACT=extensions.state/hooks-fixture.added.json

for impl in "${IMPLS[@]}"; do
  tag="${impl%%:*}"; TPATH="$SB/bin_$tag:$PATH"
  echo "### [$tag] ${impl#*:}"
  P="$SB/p_$tag"; mk_consumer "$P" || { nok "[$tag] setup: consumer project with a constitution submodule"; continue; }
  mapfile -t D < <(DISP)
  INST_H="$C/extensions/_installed/hooks-fixture"

  # -- add (consent at install; the dispatcher never forwards --yes, so it always prompts) ---------------------
  notty "[$tag] add" 3 add "$H" --sha256 "$H_SHA"
  check "[$tag] add without a terminal: nothing installed" test ! -e "$INST_H"
  ptyrun "Grant these capabilities" n 60 "${D[@]}" extensions add "$H" --sha256 "$H_SHA"
  eq "[$tag] add via dispatcher, answer n: rc 3" 3 "$RC"
  eq "[$tag] add n: prompt shown" True "$PTY_PROMPT"
  eq "[$tag] add n: not killed by the driver (no hang)" False "$PTY_KILLED"
  check "[$tag] add n: nothing installed" test ! -e "$INST_H"
  ptyrun "Grant these capabilities" n 60 "${D[@]}" install-extension "$H" --sha256 "$H_SHA"
  eq "[$tag] install-extension (alias of add) via dispatcher, answer n: rc 3" 3 "$RC"
  eq "[$tag] install-extension n: prompt shown" True "$PTY_PROMPT"
  eq "[$tag] install-extension n: not killed by the driver (no hang)" False "$PTY_KILLED"
  check "[$tag] install-extension n: nothing installed" test ! -e "$INST_H"
  ptyrun "Grant these capabilities" y 60 "${D[@]}" extensions add "$H" --sha256 "$H_SHA"
  eq "[$tag] add via dispatcher, answer y: rc 0" 0 "$RC"
  eq "[$tag] add y: prompt shown" True "$PTY_PROMPT"
  eq "[$tag] add y: not killed by the driver (no hang)" False "$PTY_KILLED"
  check "[$tag] add y: hooks-fixture installed" test -d "$INST_H"
  check "[$tag] add y: install fact written" test -f "$P/.constitution/$FACT"

  # -- adopt-install (_confirm_adopt): an install made before install facts existed has no fact ----------------
  rm -f "$P/.constitution/$FACT"
  notty "[$tag] adopt-install" 3 adopt-install hooks-fixture --waiver-id OPS-9
  check "[$tag] adopt-install without a terminal: no fact" test ! -e "$P/.constitution/$FACT"
  ptyrun "Type the extension id" not-the-id 60 "${D[@]}" extensions adopt-install hooks-fixture --waiver-id OPS-9
  eq "[$tag] adopt-install via dispatcher, wrong id: rc 3" 3 "$RC"
  eq "[$tag] adopt-install wrong id: prompt shown" True "$PTY_PROMPT"
  eq "[$tag] adopt-install wrong id: not killed by the driver (no hang)" False "$PTY_KILLED"
  check "[$tag] adopt-install wrong id: no fact" test ! -e "$P/.constitution/$FACT"
  ptyrun "Type the extension id" hooks-fixture 60 "${D[@]}" extensions adopt-install hooks-fixture --waiver-id OPS-9
  eq "[$tag] adopt-install via dispatcher, right id: rc 0" 0 "$RC"
  eq "[$tag] adopt-install right id: prompt shown" True "$PTY_PROMPT"
  eq "[$tag] adopt-install right id: not killed by the driver (no hang)" False "$PTY_KILLED"
  check "[$tag] adopt-install right id: fact written" test -f "$P/.constitution/$FACT"
  has "[$tag] adopt-install right id: the engine's result reaches the operator" "adopted hooks-fixture" "$OUT"
  check "[$tag] adopt-install: no engine process left behind" test "$(engine_procs_left)" -eq 0

  # -- enable (consent) ----------------------------------------------------------------------------------------
  notty "[$tag] enable" 3 enable hooks-fixture
  check "[$tag] enable without a terminal: lock not enabled" bash -c "! grep -q 'enabled: true' '$P/.constitution/extensions.lock.yml'"
  ptyrun "Grant these capabilities" n 60 "${D[@]}" extensions enable hooks-fixture
  eq "[$tag] enable via dispatcher, answer n: rc 3" 3 "$RC"
  eq "[$tag] enable n: prompt shown" True "$PTY_PROMPT"
  eq "[$tag] enable n: not killed by the driver" False "$PTY_KILLED"
  check "[$tag] enable n: lock not enabled" bash -c "! grep -q 'enabled: true' '$P/.constitution/extensions.lock.yml'"
  ptyrun "Grant these capabilities" y 60 "${D[@]}" extensions enable hooks-fixture
  eq "[$tag] enable via dispatcher, answer y: rc 0" 0 "$RC"
  eq "[$tag] enable y: prompt shown" True "$PTY_PROMPT"
  eq "[$tag] enable y: not killed by the driver" False "$PTY_KILLED"
  check "[$tag] enable y: lock says enabled" grep -q 'enabled: true' "$P/.constitution/extensions.lock.yml"

  # -- the budget still bounds an interactive route (nobody answers) -------------------------------------------
  OUT="$(bash "$ENG" --project-root "$P" disable hooks-fixture </dev/null 2>&1)"; RC=$?
  eq "[$tag] setup: disable hooks-fixture for the budget case" 0 "$RC"
  CONSTITUTION_CMD_EXT_TIMEOUT=4 ptyrun "Grant these capabilities" - 40 "${D[@]}" extensions enable hooks-fixture
  eq "[$tag] enable, nobody answers, budget 4 s: rc 124 (timed out)" 124 "$RC"
  eq "[$tag] budget case: prompt shown" True "$PTY_PROMPT"
  eq "[$tag] budget case: ended by the budget, not by the driver" False "$PTY_KILLED"
  check "[$tag] budget case: ended within 20 s" test "${PTY_SECS:-99}" -le 20
  check "[$tag] budget case: lock not enabled" bash -c "! grep -q 'enabled: true' '$P/.constitution/extensions.lock.yml'"
  check "[$tag] budget case: no engine process left behind" test "$(engine_procs_left)" -eq 0

done

# ---- budget knob validation -----------------------------------------------------------------------------------
P="$SB/p_knob"; mk_consumer "$P" || nok "knob setup"
for bad in 0 601 abc -1; do
  OUT="$(cd "$P" && CONSTITUTION_CMD_EXT_TIMEOUT="$bad" bash "$C/scripts/constitution_cmd/constitution_cmd.sh" extensions list </dev/null 2>&1)"; RC=$?
  eq "CONSTITUTION_CMD_EXT_TIMEOUT=$bad is refused (rc 2)" 2 "$RC"
done

# ---- paired section 1.1 mutation leg: each mutant of the dispatcher must make this suite FAIL -----------------
if [ "${PTY_MUTATION_LEG:-1}" = 1 ] && [ -z "${CMD_SRC_ROOT:-}" ]; then
  echo "### paired mutations of the dispatcher's interactive routing"
  mut() {   # name old new
    local d="$SB/mut_$1"; mkdir -p "$d/scripts/constitution_cmd"
    python3 -I - "$REAL_ROOT/scripts/constitution_cmd/constitution_cmd.sh" "$d/scripts/constitution_cmd/constitution_cmd.sh" "$2" "$3" <<'PY' || { nok "mutant $1: anchor not found exactly once"; return; }
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src, encoding="utf-8").read()
if s.count(old) != 1:
    sys.exit(1)
open(dst, "w", encoding="utf-8").write(s.replace(old, new))
PY
    if CMD_SRC_ROOT="$d" PTY_MUTATION_LEG=0 bash "$HERE/test_constitution_cmd_pty.sh" >"$d.out" 2>&1; then
      nok "mutant $1 SURVIVED"
    else
      ok "mutant $1 killed ($(grep -c '  FAIL' "$d.out") failures)"
    fi
  }
  mut PM1_no_foreground 'timeout --foreground "$t"' 'timeout "$t"'
  mut PM2_adopt_not_interactive 'add|enable|adopt-install) interactive=1' 'add|enable) interactive=1'
  mut PM3_enable_not_interactive 'add|enable|adopt-install) interactive=1' 'add|adopt-install) interactive=1'
  mut PM4_add_not_interactive 'add|enable|adopt-install) interactive=1' 'enable|adopt-install) interactive=1'
  mut PM5_budget_knob_ignored 't="${CONSTITUTION_CMD_EXT_TIMEOUT:-300}"' 't=300'
fi
finish
