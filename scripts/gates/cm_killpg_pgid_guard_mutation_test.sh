#!/usr/bin/env bash
# cm_killpg_pgid_guard_mutation_test.sh — §1.1 paired-mutation meta-test for
# CM-KILLPG-PGID-GUARD (anchor §11.4.263).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Proves CM-KILLPG-PGID-GUARD is NOT a bluff gate: it must FAIL on the exact
# BOB-126 forensic shape (an unguarded process-group signal call — the literal
# defect that SIGKILLed the operator's desktop session seven times over 48h),
# and it must PASS on the anchor's own prescribed guard idiom applied across
# every language class §11.4.263(B) names, PLUS the legitimate ordinary
# single-process `kill -9 $pid` shell idiom (which MUST NEVER be flagged —
# clause 3 of the gate's header design rationale).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_killpg_pgid_guard_mutation_test.sh
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Creates + removes a temp fixture dir under $TMPDIR (trap-cleaned on EXIT).
#   No network, no commit, no real killpg/kill syscall ever executed — every
#   fixture is inert source TEXT the gate's scanner reads, never runs.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, the sibling gate script. Parses clean under bash -n.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §1.1 (paired mutation), §11.4.263 (the anchor enforced), §11.4.201(1)
#   (false-positive refusal is a FAIL-bluff exactly as a false-negative pass —
#   both directions are tested here), §11.4.28 (gate driven via --root, no
#   hardcoded project path).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — gate FAILs-on-mutation AND PASSes-on-clean for every fixture pair
#       (the §1.1 proof holds).
#   1 — a fixture did not produce its expected verdict (bluff gate, or a
#       false-positive refusal).
#   2 — environment error (gate script missing).
#
# Classification: universal (§11.4.17).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE="${SCRIPT_DIR}/cm_killpg_pgid_guard.sh"

[ -f "$GATE" ] || { echo "META: gate script missing: $GATE" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/killpg_mut.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

rc=0
expect_fail() { # $1=desc  $2=dir
    local desc="$1" dir="$2"
    if bash "$GATE" --root "$dir" >/dev/null 2>&1; then
        echo "❌ META FAIL: ${desc} — gate PASSed on a planted violation (bluff gate!)"
        rc=1
    else
        echo "✅ META OK:   ${desc} — gate correctly FAILed on the mutation"
    fi
}
expect_pass() { # $1=desc  $2=dir
    local desc="$1" dir="$2"
    if bash "$GATE" --root "$dir" >/dev/null 2>&1; then
        echo "✅ META OK:   ${desc} — gate correctly PASSed on clean fixture"
    else
        echo "❌ META FAIL: ${desc} — gate FAILed on a clean fixture (false-positive refusal, §11.4.201(1))"
        rc=1
    fi
}

echo "======================================================================"
echo "§1.1 paired-mutation meta-test for CM-KILLPG-PGID-GUARD (§11.4.263)"
echo "fixtures under: $TMP"
echo "======================================================================"

# ===================================================================
# 1. The literal BOB-126 shape — bare os.killpg(os.getpgid(proc.pid), ...)
# ===================================================================
MUT1="$TMP/bob126"
mkdir -p "$MUT1"
cat > "$MUT1/reaper.py" <<'PY'
import os, signal

def kill_process_tree(proc):
    # BOB-126: proc.pid was an unset AsyncMock().pid, defaulting via
    # MagicMock.__int__() to 1 -> os.getpgid(1) == 1 -> os.killpg(1, SIGKILL)
    # == kill(-1, SIGKILL) == SIGKILL every process the caller's UID owns.
    os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
PY
expect_fail "BOB-126 literal shape (unguarded os.killpg)" "$MUT1"

CLEAN1="$TMP/bob126_fixed"
mkdir -p "$CLEAN1"
cat > "$CLEAN1/reaper.py" <<'PY'
import os, signal

def kill_process_tree(proc):
    pid = getattr(proc, "pid", None)
    if not isinstance(pid, int) or pid <= 1:
        raise ValueError(f"refusing to signal unsafe pid: {pid!r}")
    pgid = os.getpgid(pid)
    if not isinstance(pgid, int) or pgid <= 1:
        raise ValueError(f"refusing to signal unsafe pgid: {pgid!r}")
    os.killpg(pgid, signal.SIGKILL)
PY
expect_pass "BOB-126 fixed shape (guarded pid+pgid>1 before killpg)" "$CLEAN1"

# ===================================================================
# 2. Go — syscall.Kill(-pgid, sig) unguarded vs guarded
# ===================================================================
MUT2="$TMP/go_bad"
mkdir -p "$MUT2"
cat > "$MUT2/reaper.go" <<'GO'
package main

import "syscall"

func killTree(pgid int) {
	syscall.Kill(-pgid, syscall.SIGKILL)
}
GO
expect_fail "Go unguarded syscall.Kill(-pgid,...)" "$MUT2"

CLEAN2="$TMP/go_good"
mkdir -p "$CLEAN2"
cat > "$CLEAN2/reaper.go" <<'GO'
package main

import (
	"fmt"
	"syscall"
)

func killTree(pgid int) error {
	if pgid <= 1 {
		return fmt.Errorf("refusing to signal unsafe pgid: %d", pgid)
	}
	return syscall.Kill(-pgid, syscall.SIGKILL)
}
GO
expect_pass "Go guarded (pgid>1 checked before syscall.Kill)" "$CLEAN2"

# ===================================================================
# 3. Shell — pkill -g <pgid> unguarded vs guarded
# ===================================================================
MUT3="$TMP/sh_bad"
mkdir -p "$MUT3"
cat > "$MUT3/reaper.sh" <<'SH'
#!/usr/bin/env bash
reap_tree() {
    local pgid="$1"
    pkill -g "$pgid"
}
SH
expect_fail "shell unguarded pkill -g \$pgid" "$MUT3"

CLEAN3="$TMP/sh_good"
mkdir -p "$CLEAN3"
cat > "$CLEAN3/reaper.sh" <<'SH'
#!/usr/bin/env bash
reap_tree() {
    local pgid="$1"
    case "$pgid" in
        ''|*[!0-9]*) echo "refusing to signal non-integer pgid: $pgid" >&2; return 1 ;;
    esac
    if [ "$pgid" -le 1 ]; then
        echo "refusing to signal unsafe pgid <=1: $pgid" >&2
        return 1
    fi
    pkill -g "$pgid"
}
SH
expect_pass "shell guarded pgid (pgid>1 checked before pkill -g)" "$CLEAN3"

# ===================================================================
# 3b. Wrong-variable guard — a CORRECT `pid > 1` guard sits in the window
#     but the value actually PASSED to killpg (`pgid`) was only checked
#     `> 0`, so a pgid of 1 still reaches the disaster syscall. A gate
#     whose guard check is not scoped to the call's OWN target clears
#     this on the unrelated `pid > 1` — a false-negative PASS on the
#     exact §11.4.263 defect class.
# ===================================================================
MUT4="$TMP/wrong_variable_guard"
mkdir -p "$MUT4"
cat > "$MUT4/reaper.py" <<'PY'
import contextlib
import os
import signal


async def cleanup(proc):
    if proc.returncode is None:
        pid = proc.pid
        if isinstance(pid, int) and pid > 1:
            with contextlib.suppress(Exception):
                pgid = os.getpgid(pid)
                if isinstance(pgid, int) and pgid > 0:
                    os.killpg(pgid, signal.SIGKILL)
PY
expect_fail "wrong-variable guard (pid>1 present, target pgid only checked >0)" "$MUT4"

# ===================================================================
# 3c. Shell negated-target broadcast — `kill -9 -1` is the shell spelling
#     of the disaster syscall and MUST be flagged; a scanner that only
#     matches `kill -"$pgid"` is blind to the literal form.
# ===================================================================
MUT5="$TMP/sh_literal_broadcast"
mkdir -p "$MUT5"
cat > "$MUT5/reap_all.sh" <<'SH'
#!/usr/bin/env bash
reap_everything() {
    kill -9 -1
}
SH
expect_fail "shell literal broadcast 'kill -9 -1'" "$MUT5"

# ===================================================================
# 4. Negative control — ordinary single-process `kill -9 $pid` MUST NEVER
#    be flagged: kill(2)'s process-GROUP form requires a NEGATIVE pgid, and
#    this is the single-process form. A gate that flags this is itself a
#    §11.4.201(1) false-positive refusal (FAIL-bluff).
# ===================================================================
NEG1="$TMP/ordinary_single_kill"
mkdir -p "$NEG1"
cat > "$NEG1/tidy.sh" <<'SH'
#!/usr/bin/env bash
stop_one() {
    local pid="$1"
    kill -9 "$pid"
}
SH
expect_pass "negative control: ordinary single-process 'kill -9 \$pid' never flagged" "$NEG1"

# ===================================================================
# 5. A `def` line naming killpg, and a call to the guarded safe_killpg
#    primitive with an identifier target, are NOT unguarded signal calls
#    (negative controls); a numeric-literal safe_killpg target and an
#    unguarded raw os.killpg beside such a def are STILL caught.
# ===================================================================
NEG2="$TMP/def_and_wrapper"
mkdir -p "$NEG2"
cat > "$NEG2/w.py" <<'PY'
import os
def safe_killpg(pgid, sig):
    if isinstance(pgid, int) and pgid > 1:
        os.killpg(pgid, sig)
def reap(proc):
    safe_killpg(proc.pid, 9)
PY
expect_pass "negative control: def line + safe_killpg(identifier) wrapper call not flagged" "$NEG2"
MUT6="$TMP/wrapper_literal"
mkdir -p "$MUT6"
printf 'def reap():\n    safe_killpg(1, 9)\n' > "$MUT6/w.py"
expect_fail "safe_killpg with numeric-literal target still flagged" "$MUT6"
MUT7="$TMP/unguarded_beside_def"
mkdir -p "$MUT7"
printf 'import os\ndef safe_killpg(pgid, sig):\n    os.killpg(pgid, sig)\n' > "$MUT7/w.py"
expect_fail "raw unguarded os.killpg inside a safe_killpg def still flagged" "$MUT7"

# ===================================================================
# 6. Review round 1 (NO-GO) bypass shapes: each MUST FAIL; golden-FALSE MUST PASS.
# ===================================================================
mkfix() { # $1=name $2=file $3=content (printf %b)
    mkdir -p "$(dirname "$TMP/$1/$2")"; printf '%b' "$3" > "$TMP/$1/$2"; echo "$TMP/$1"
}
expect_fail "F1a alias '_safe_killpg = os.killpg' then call" \
    "$(mkfix f1a w.py 'import os\n_safe_killpg = os.killpg\ndef r(p):\n    _safe_killpg(p.pid, 9)\n')"
expect_fail "F1b third-party 'not_safe_killpg(p, 9)'" \
    "$(mkfix f1b w.py 'from thirdparty import not_safe_killpg\nnot_safe_killpg(p, 9)\n')"
expect_fail "F1c vendor safe_killpg with arithmetic target (p - 1)" \
    "$(mkfix f1c w.py 'from vendor_lib import safe_killpg\nsafe_killpg(p - 1, 9)\n')"
expect_fail "F1d vendor safe_killpg(pgid, 9) from a non-fc_common import" \
    "$(mkfix f1d w.py 'from vendor_lib import safe_killpg\nsafe_killpg(pgid, 9)\n')"
expect_fail "F2a wrapper call plus raw os.killpg on one line" \
    "$(mkfix f2a w.py 'import os\nimport fc_common\nfc_common.safe_killpg(pgid, 9); os.killpg(other, 9)\n')"
expect_fail "F2b one-line def with a raw os.killpg body" \
    "$(mkfix f2b w.py 'import os\ndef my_killpg(p): os.killpg(p, 9)\n')"
expect_fail "F3a heredoc python raw os.killpg(os.getpgid(proc.pid)) in a tests/*.sh" \
    "$(mkfix f3a scripts/fastcycle/tests/t.sh 'python3 - <<PY\nimport os\nproc = mock.AsyncMock(); os.killpg(os.getpgid(proc.pid), 9)\nPY\n')"
expect_fail "F3b 'bash -c \"kill -9 -1\"' string handed to a shell is code" \
    "$(mkfix f3b scripts/x.sh '#!/bin/bash\nbash -c "kill -9 -1"\n')"
expect_pass "GF1 legit fc_common.safe_killpg wrapper call" \
    "$(mkfix gf1 w.py 'import fc_common\ndef r(proc):\n    fc_common.safe_killpg(proc.pid, 9)\n')"
expect_pass "GF3 audited marker with a reason skips a deliberate test call" \
    "$(mkfix gf3 tests/w.py 'import os\nos.killpg(p, 9)  # killpg-gate:allow test hands the guard a bad pgid\n')"
expect_fail "F7 marker WITHOUT a reason does not exempt" \
    "$(mkfix f7 w.py 'import os\nos.killpg(p, 9)  # killpg-gate:allow\n')"
expect_pass "GF2 fixture/spec strings and docstring prose are not call sites" \
    "$(mkfix gf2 scripts/fastcycle/tests/t.sh 'echo "kill -9 -1"\nspecs=("kill-wide" "#!/bin/sh\\nkill -9 -1")\ncat <<PY\nx = """\nos.killpg(p, 9)\nkillpg(1, 9)\n"""\nPY\n')"

# ===================================================================
# 7. Review round 2 (NO-GO on 9cf915e): bypasses of the string/comment blanking and the wrapper
#    exemption. Each R* MUST FAIL (the BASE gate 3ad667a, which blanked nothing, caught the
#    blanking-class ones); each GF* MUST PASS. Fixtures are inert text.
# ===================================================================
# 7.1 strings handed to a shell are code
expect_fail "R1a subprocess.run(\"kill -9 -\$PGID\", shell=True)" \
    "$(mkfix r1a w.py 'import subprocess\nsubprocess.run("kill -9 -$PGID", shell=True)\n')"
expect_fail "R1b subprocess.Popen(\"kill -TERM -\${pg}\", shell=True)" \
    "$(mkfix r1b w.py 'import subprocess\nsubprocess.Popen("kill -TERM -${pg}", shell=True)\n')"
expect_fail "R1c list form [\"sh\",\"-c\",\"kill -9 -\$pg\"]" \
    "$(mkfix r1c w.py 'import subprocess\nsubprocess.run(["sh","-c","kill -9 -$pg"])\n')"
expect_fail "R1d os.system(f\"kill -9 -\$pg\")" \
    "$(mkfix r1d w.py 'import os\nos.system(f"kill -9 -$pg")\n')"
expect_fail "R1e Go exec.Command(\"sh\",\"-c\",\"kill -9 -1\")" \
    "$(mkfix r1e w.go 'package main\nfunc f() {\n\texec.Command("sh", "-c", "kill -9 -1").Run()\n}\n')"
expect_fail "R1f shell: ssh host \"kill -9 -1\"" \
    "$(mkfix r1f w.sh '#!/bin/bash\nssh host "kill -9 -1"\n')"
expect_fail "R1g shell: sh -c 'kill -9 -\$pg'" \
    "$(mkfix r1g w.sh '#!/bin/bash\nsh -c '"'"'kill -9 -$pg'"'"'\n')"
expect_fail "R1h shell: echo \"kill -9 -1\" | sh" \
    "$(mkfix r1h w.sh '#!/bin/bash\necho "kill -9 -1" | sh\n')"
expect_fail "R1i shell: x=\"\$(kill -9 -1)\" command substitution inside double quotes" \
    "$(mkfix r1i w.sh '#!/bin/bash\nx="$(kill -9 -1)"\n')"
expect_fail "R1j shell: eval \"kill -TERM -\$pg\"" \
    "$(mkfix r1j w.sh '#!/bin/bash\neval "kill -TERM -$pg"\n')"
expect_fail "R1k shell: unknown helper given a kill string (fail closed)" \
    "$(mkfix r1k w.sh '#!/bin/bash\nrun_it "kill -9 -1"\n')"
# 7.2 triple-quote state must not leak across heredoc / raw-string / language boundaries
expect_fail "R2a .sh heredoc body with an odd triple-quote must not blank the real kill below it" \
    "$(mkfix r2a w.sh '#!/bin/bash\ncat <<EOF\nx = """\nEOF\nkill -TERM -"$pg"\n')"
expect_fail "R2b .go raw string containing a triple-quote must not blank the real Kill below it" \
    "$(mkfix r2b w.go 'package main\nfunc f(pg int) {\n\ts := `a """ b`\n\t_ = s\n\tsyscall.Kill(-pg, 9)\n}\n')"
expect_fail "R2c .sh python3 heredoc, then a real shell kill after the terminator" \
    "$(mkfix r2c w.sh '#!/bin/bash\npython3 - <<PY\nx = 1\nPY\nkill -9 -1\n')"
# 7.3 shell single quotes take NO backslash escapes
expect_fail "R3 echo 'a\\'; kill -9 -\$pg; echo 'z'" \
    "$(mkfix r3 w.sh "#!/bin/bash\necho 'a\\\\'; kill -9 -\$pg; echo 'z'\n")"
# 7.4 f-string replacement fields are code
expect_fail "R4 f-string field hides os.killpg(1, 9)" \
    "$(mkfix r4 w.py 'import os\nx = f"{os.killpg(1, 9)}"\n')"
expect_fail "R4b triple-quoted f-string field" \
    "$(mkfix r4b w.py 'import os\nx = f"""\n{os.killpg(1, 9)}\n"""\n')"
# 7.5 allow marker only in a real trailing comment, only on test paths
expect_fail "R5a marker text inside a string literal does not suppress" \
    "$(mkfix r5a w.py 'import os\ny = "killpg-gate:allow zzz"; os.killpg(1, 9)\n')"
expect_fail "R5b marker with a reason on a NON-test path does not suppress" \
    "$(mkfix r5b w.py 'import os\nos.killpg(p, 9)  # killpg-gate:allow because\n')"
# 7.6 wrapper exemption is bound to the real import
expect_fail "R6a 'import evil as fc_common' then fc_common.safe_killpg(pg, 9)" \
    "$(mkfix r6a w.py 'import evil as fc_common\nfc_common.safe_killpg(pg, 9)\n')"
expect_fail "R6b star import + token mention, then safe_killpg(pg, 9)" \
    "$(mkfix r6b w.py 'from evil import *\nx = fc_common_shim\nsafe_killpg(pg, 9)\n')"
expect_fail "R6c 'safe_killpg = evil.boom' + 'fc_common = None' then safe_killpg(pg, 9)" \
    "$(mkfix r6c w.py 'safe_killpg = evil.boom\nfc_common = None\nsafe_killpg(pg, 9)\n')"
expect_fail "R6d _safe_killpg alias bound to a foreign object" \
    "$(mkfix r6d w.py 'import fc_common\n_safe_killpg = evil.boom\n_safe_killpg(pg, 9)\n')"
expect_fail "R6e fc_common merely mentioned (not imported), then fc_common.safe_killpg(pg, 9)" \
    "$(mkfix r6e w.py 'x = "fc_common"\nfc_common.safe_killpg(pg, 9)\n')"
# 7.7 alias / reference class: any non-call reference to killpg outside the wrapper is a finding
expect_fail "R7a from os import killpg as k; k(pg, 9)" \
    "$(mkfix r7a w.py 'from os import killpg as k\nk(pg, 9)\n')"
expect_fail "R7b getattr(os, \"killpg\")" \
    "$(mkfix r7b w.py 'import os\nf = getattr(os, "killpg")\nf(pg, 9)\n')"
expect_fail "R7c k, j = os.killpg, os.kill" \
    "$(mkfix r7c w.py 'import os\nk, j = os.killpg, os.kill\nk(pg, 9)\n')"
expect_fail "R7d k = (os.killpg)" \
    "$(mkfix r7d w.py 'import os\nk = (os.killpg)\nk(pg, 9)\n')"
expect_fail "R7e dict holding os.killpg" \
    "$(mkfix r7e w.py 'import os\nd = {"k": os.killpg}\nd["k"](pg, 9)\n')"
expect_fail "R7f default argument kill=os.killpg" \
    "$(mkfix r7f w.py 'import os\ndef f(pg, kill=os.killpg):\n    kill(pg, 9)\n')"
expect_fail "R7g os.__dict__[\"killpg\"]" \
    "$(mkfix r7g w.py 'import os\nos.__dict__["killpg"](pg, 9)\n')"
# 7.8 further spellings of the group kill
expect_fail "R8a kill -9 -- -1" "$(mkfix r8a w.sh '#!/bin/bash\nkill -9 -- -1\n')"
expect_fail "R8b kill -- -1" "$(mkfix r8b w.sh '#!/bin/bash\nkill -- -1\n')"
expect_fail "R8c kill -s KILL -\"\$pg\" unguarded" "$(mkfix r8c w.sh '#!/bin/bash\nkill -s KILL -"$pg"\n')"
expect_fail "R8d kill -9 -- -\"\$pg\" unguarded" "$(mkfix r8d w.sh '#!/bin/bash\nkill -9 -- -"$pg"\n')"
expect_fail "R8e kill -9 \"-\$pg\" unguarded" "$(mkfix r8e w.sh '#!/bin/bash\nkill -9 "-$pg"\n')"
expect_fail "R8f os.kill(0 - pg, 9)" "$(mkfix r8f w.py 'import os\nos.kill(0 - pg, 9)\n')"
expect_fail "R8g Go unix.Kill(-p, 9)" "$(mkfix r8g w.go 'package main\nfunc f(p int) {\n\tunix.Kill(-p, 9)\n}\n')"
expect_fail "R8h Go syscall.Kill(0-p, 9)" "$(mkfix r8h w.go 'package main\nfunc f(p int) {\n\tsyscall.Kill(0-p, 9)\n}\n')"
expect_fail "R8i Rust kill(Pid::from_raw(-p), sig)" \
    "$(mkfix r8i w.rs 'fn f(p: i32) {\n    nix::sys::signal::kill(Pid::from_raw(-p), Signal::SIGKILL);\n}\n')"
expect_fail "R8j subprocess.run([\"kill\",\"-9\",\"-1\"])" \
    "$(mkfix r8j w.py 'import subprocess\nsubprocess.run(["kill", "-9", "-1"])\n')"
# golden-FALSE (MUST PASS)
expect_pass "GFa python docstring prose naming os.killpg(1, 9)" \
    "$(mkfix gfa w.py 'def f():\n    """Never call os.killpg(1, 9).\n    kill -9 -1 is the disaster.\n    """\n    return 1\n')"
expect_pass "GFb cat <<EOF body (inert consumer) names killpg(1, 9) and kill -9 -1" \
    "$(mkfix gfb w.sh '#!/bin/bash\ncat > /dev/null <<'"'"'EOF'"'"'\nos.killpg(1, 9)\nkill -9 -1\nEOF\n')"
expect_pass "GFc printf / echo / grep / for-loop carrying kill text" \
    "$(mkfix gfc w.sh "#!/bin/bash\nprintf '%s\\\\n' 'kill -9 -1'\necho 'os.killpg(1, 9)'\ngrep -q 'kill -9 -1' /dev/null\nfor spec in 'a|os.killpg(1, 9)|b' 'c'; do :; done\n")"
expect_pass "GFd guarded shell group kills (-s KILL / -- forms)" \
    "$(mkfix gfd w.sh '#!/bin/bash\nf() {\n    local pgid="$1"\n    if [ "$pgid" -le 1 ]; then return 1; fi\n    kill -s KILL -"$pgid"\n    kill -9 -- -"$pgid"\n}\n')"
expect_pass "GFe print()/logging strings and a benign f-string carrying kill text" \
    "$(mkfix gfe w.py 'import logging\nprint("os.killpg(1, 9)")\nlogging.info("kill -9 -1")\nx = f"{pid} killpg"\n')"
expect_pass "GFf from fc_common import safe_killpg; safe_killpg(proc.pid, 9)" \
    "$(mkfix gff w.py 'from fc_common import safe_killpg\ndef r(proc):\n    safe_killpg(proc.pid, 9)\n')"
expect_pass "GFg _safe_killpg alias bound once to fc_common.safe_killpg" \
    "$(mkfix gfg w.py 'import fc_common\n_safe_killpg = fc_common.safe_killpg\ndef r(proc):\n    _safe_killpg(proc.pid, 9)\n')"
expect_pass "GFh ordinary kill forms: kill -9 -- \"\$pid\", kill -TERM \"\$pid\", kill -0 \"\$pid\"" \
    "$(mkfix gfh w.sh '#!/bin/bash\nkill -9 -- "$pid"\nkill -TERM "$pid"\nkill -0 "$pid"\n')"
expect_pass "GFi Go raw multi-line string naming syscall.Kill(-1, 9), no execution sink" \
    "$(mkfix gfi w.go 'package main\nvar s = `\nsyscall.Kill(-1, 9)\nkill -9 -1\n`\n')"
expect_pass "GFj audited marker on a TEST path with a reason suppresses (reported as ALLOWED)" \
    "$(mkfix gfj tests/test_w.py 'import os\nos.killpg(p, 9)  # killpg-gate:allow test hands the guard a bad pgid\n')"
expect_pass "GFk python3 heredoc data tuple + docstring inside a tests/*.sh" \
    "$(mkfix gfk tests/t.sh 'python3 - <<PY\nspecs = [("kill-wide", "#!/bin/sh\\nkill -9 -1\\n", True)]\ndef f():\n    """doc: os.killpg(1, 9)"""\nPY\n')"
expect_pass "GFl monkeypatch X.killpg = fake; def _fake_killpg(...) double (definition/replace, no signal)" \
    "$(mkfix gfl w.py 'import os\ndef _fake_killpg(pgid, sig):\n    return None\nos.killpg = _fake_killpg\nos.killpg = lambda pg, sig: None; x = 1\n')"
expect_pass "GFm test reporter helpers ok/bad carrying the word killpg + kill -9 -1 text" \
    "$(mkfix gfm w.sh '#!/bin/bash\nbad "B2: killpg FAILED, kill -9 -1 is the disaster"\nok "B2: killpg killed the whole group"\n')"
expect_pass "GFn env-prefixed python3 heredoc after 2>&1 (docstring + guarded call stay inert/guarded)" \
    "$(mkfix gfn w.sh '#!/bin/bash\nR=$(FOO="$X" python3 - "$A" >"$T/o" 2>\&1 <<'"'"'PY'"'"'\ndef f():\n    """doc: os.killpg(1, 9) is the disaster"""\n    return 1\nPY\n)\n')"
expect_pass "GFo shell group kill guarded by a >1 test on a non-pid-family variable name (j)" \
    "$(mkfix gfo w.sh '#!/bin/bash\nwhile read -r j; do\n    if [ "$j" -gt 1 ]; then kill -s KILL -- "-$j"; fi\ndone\n')"
expect_fail "R9a alias on the RIGHT side of an X.killpg assignment (y = os.killpg)" \
    "$(mkfix r9a w.py 'import os\nj = os.killpg\nj(-3, 9)\n')"
expect_fail "R9b self-assignment os.killpg = os.killpg keeps the alias finding" \
    "$(mkfix r9b w.py 'import os\nos.killpg = os.killpg\n')"
expect_fail "R9c def _fake_killpg(kill=os.killpg): parameter default holds the real function" \
    "$(mkfix r9c w.py 'import os\ndef _fake_killpg(pg, kill=os.killpg):\n    kill(pg, 9)\n')"
expect_fail "R9d helper-word string that is really a shell: ok \$(kill -9 -1) command substitution" \
    "$(mkfix r9d w.sh '#!/bin/bash\nok "$(kill -9 -1)"\n')"
expect_fail "R9e >1 test on a DIFFERENT variable does not guard the killed one" \
    "$(mkfix r9e w.sh '#!/bin/bash\nj=$1; k=$2\nif [ "$j" -gt 1 ]; then kill -s KILL -- "-$k"; fi\n')"
expect_fail "R9f env-prefixed python3 heredoc after 2>&1 with a live os.killpg(1, 9) call" \
    "$(mkfix r9f w.sh '#!/bin/bash\nR=$(FOO="$X" python3 - "$A" >"$T/o" 2>\&1 <<'"'"'PY'"'"'\nimport os\nos.killpg(1, 9)\nPY\n)\n')"

# ===================================================================
# LARGE-WINDOW — SIGPIPE x pipefail (§11.4.276(C) class member). The guard sits on
# an EARLY line of the call's window and a ~350 KB code line follows it. With
# `printf "$window_text" | grep -qE` under `set -o pipefail`, grep exits at the
# guard line while printf is still writing; printf takes SIGPIPE and pipefail
# turns a GUARDED call into a false "UNGUARDED" FAIL (both the GUARD_ERE
# pre-check and target_guarded read the window). Repeated: the race is
# deterministic only well above the ~131 KB knee. Paired with the same large
# window WITHOUT the guard, which must still FAIL — the PASS is the guard's.
# ===================================================================
mk_large_window() { # $1=dir  $2=guarded 1|0
    local d="$1" pad
    mkdir -p "$d"
    pad="$(head -c 350000 /dev/zero | tr '\0' 'A')"
    {
        echo 'import os, signal'
        echo 'def stop_group(pgid):'
        if [ "$2" = 1 ]; then
            echo '    if not isinstance(pgid, int) or pgid <= 1:'
            echo '        raise ValueError("refusing to signal an unsafe pgid")'
        fi
        printf '    blob = "%s"\n' "$pad"
        echo '    os.killpg(pgid, signal.SIGKILL)'
    } > "$d/large_window.py"
}
LW="$TMP/large_window"; mk_large_window "$LW" 1
lw_sz="$(wc -c < "$LW/large_window.py")"
[ "$lw_sz" -ge 300000 ] || { echo "❌ META FAIL: LARGE-WINDOW fixture is only $lw_sz bytes (needs >= 300000)"; rc=1; }
for it in 1 2 3 4 5; do
    expect_pass "LARGE-WINDOW guarded call, $lw_sz B window (SIGPIPE x pipefail) — iteration $it" "$LW"
done
LWN="$TMP/large_window_unguarded"; mk_large_window "$LWN" 0
expect_fail "LARGE-WINDOW same window WITHOUT the guard" "$LWN"

echo "======================================================================"
if [ "$rc" -eq 0 ]; then
    echo "✅ META PASS — CM-KILLPG-PGID-GUARD FAILs-on-mutation AND PASSes-on-clean for every fixture (§1.1 proof holds)"
else
    echo "❌ META FAIL — CM-KILLPG-PGID-GUARD is a bluff gate (see findings above)"
fi
exit "$rc"
