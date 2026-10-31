#!/usr/bin/env bash
# test_tty_e2e.sh — e2e: drives the REAL wizard interactively through a real pseudo-terminal
# (python pty), then checks the files. No test double: the program under test is the real one.
set -u
. "$(dirname "$0")/lib.sh"
new_sandbox; [ -n "${KEEP:-}" ] || trap cleanup_sandbox EXIT
P="$(new_project tty)"
cat >"$SB/drive.py" <<'PY'
import os, pty, sys, time, select
cli, proj, answers, out = sys.argv[1], sys.argv[2], sys.argv[3].split("|"), sys.argv[4]
pid, fd = pty.fork()
if pid == 0:
    os.execv(cli, [cli, "--project-root", proj])
buf = b""; i = 0; last = 0; deadline = time.time() + 20
while time.time() < deadline:
    r, _, _ = select.select([fd], [], [], 0.2)
    if r:
        try:
            chunk = os.read(fd, 4096)
        except OSError:
            break
        if not chunk:
            break
        buf += chunk
    pending = buf[last:]
    if i < len(answers) and pending.endswith(b": "):
        os.write(fd, (answers[i] + "\n").encode()); i += 1; last = len(buf)
_, st = os.waitpid(pid, 0)
open(out, "wb").write(buf)
sys.exit(os.waitstatus_to_exitcode(st))
PY
# Prompt order = catalogue order minus locked keys, then agents. Answer: layer.mode=shadow, an invalid
# floor (refused, re-asked) then 0.96, Enter for the rest, claude wiring=consent, then confirm y.
n_prompts=$(python3 -I -c "
import sys; sys.dont_write_bytecode = True; sys.path.insert(0,'$DEC_REPO/scripts/decisions'); import decisions_engine as d
print(sum(1 for k in d.CATALOGUE if 'locked' not in d.CATALOGUE[k][2]))")
# static answers: layer.mode, exclusions (Enter), floor 0.5 (refused), retry 0.96, then Enter for the rest;
# agents claude=consent, kimi/pi Enter, opencode=declined; confirm y.
ans="$(python3 -I -c "n=$n_prompts; a=['shadow','','0.5','0.96']+['']*(n-3)+['consent','','','declined','y']; print('|'.join(a))")"
python3 -I "$SB/drive.py" "$DEC_CLI" "$P" "$ans" "$SB/tty.out"; rc=$?
check "interactive run rc0" test "$rc" = 0
check "invalid answer refused and re-asked" grep -q 'refused: calibration.floor' "$SB/tty.out"
check "floor written" grep -q 'calibration.floor: 0.96' "$P/.constitution/decisions.yml"
check "claude consent written" grep -q 'agents.claude.wiring: consent' "$P/.constitution/decisions.yml"
check "opencode declined written" grep -q 'agents.opencode.wiring: declined' "$P/.constitution/decisions.yml"
check "locked keys never asked" bash -c "! grep -q 'hosted.enforce \[' '$SB/tty.out'"
# decline at the confirmation: nothing changes
h="$(sha "$P/.constitution/decisions.yml")"
ans2="$(python3 -I -c "n=$n_prompts; a=['enforce']+['']*(n-1)+['','','','','n']; print('|'.join(a))")"
python3 -I "$SB/drive.py" "$DEC_CLI" "$P" "$ans2" "$SB/tty2.out"; rc=$?
check "declined confirmation rc0" test "$rc" = 0
check "declined confirmation wrote nothing" test "$(sha "$P/.constitution/decisions.yml")" = "$h"
finish test_tty_e2e
