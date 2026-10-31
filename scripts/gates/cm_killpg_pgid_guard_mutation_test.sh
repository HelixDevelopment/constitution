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
expect_fail "R4-reclass (strings are code-bearing now) GF2 fixture/spec strings and docstring prose are not call sites" \
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
expect_fail "R4-reclass (strings are code-bearing now) GFa python docstring prose naming os.killpg(1, 9)" \
    "$(mkfix gfa w.py 'def f():\n    """Never call os.killpg(1, 9).\n    kill -9 -1 is the disaster.\n    """\n    return 1\n')"
expect_fail "R4-reclass (strings are code-bearing now) GFb cat <<EOF body (inert consumer) names killpg(1, 9) and kill -9 -1" \
    "$(mkfix gfb w.sh '#!/bin/bash\ncat > /dev/null <<'"'"'EOF'"'"'\nos.killpg(1, 9)\nkill -9 -1\nEOF\n')"
expect_fail "R4-reclass (strings are code-bearing now) GFc printf / echo / grep / for-loop carrying kill text" \
    "$(mkfix gfc w.sh "#!/bin/bash\nprintf '%s\\\\n' 'kill -9 -1'\necho 'os.killpg(1, 9)'\ngrep -q 'kill -9 -1' /dev/null\nfor spec in 'a|os.killpg(1, 9)|b' 'c'; do :; done\n")"
expect_pass "GFd guarded shell group kills (-s KILL / -- forms)" \
    "$(mkfix gfd w.sh '#!/bin/bash\nf() {\n    local pgid="$1"\n    if [ "$pgid" -le 1 ]; then return 1; fi\n    kill -s KILL -"$pgid"\n    kill -9 -- -"$pgid"\n}\n')"
expect_fail "R4-reclass (strings are code-bearing now) GFe print()/logging strings and a benign f-string carrying kill text" \
    "$(mkfix gfe w.py 'import logging\nprint("os.killpg(1, 9)")\nlogging.info("kill -9 -1")\nx = f"{pid} killpg"\n')"
expect_pass "GFf from fc_common import safe_killpg; safe_killpg(proc.pid, 9)" \
    "$(mkfix gff w.py 'from fc_common import safe_killpg\ndef r(proc):\n    safe_killpg(proc.pid, 9)\n')"
expect_pass "GFg _safe_killpg alias bound once to fc_common.safe_killpg" \
    "$(mkfix gfg w.py 'import fc_common\n_safe_killpg = fc_common.safe_killpg\ndef r(proc):\n    _safe_killpg(proc.pid, 9)\n')"
expect_pass "GFh ordinary kill forms: kill -9 -- \"\$pid\", kill -TERM \"\$pid\", kill -0 \"\$pid\"" \
    "$(mkfix gfh w.sh '#!/bin/bash\nkill -9 -- "$pid"\nkill -TERM "$pid"\nkill -0 "$pid"\n')"
expect_fail "R4-reclass (strings are code-bearing now) GFi Go raw multi-line string naming syscall.Kill(-1, 9), no execution sink" \
    "$(mkfix gfi w.go 'package main\nvar s = `\nsyscall.Kill(-1, 9)\nkill -9 -1\n`\n')"
expect_pass "GFj audited marker on a TEST path with a reason suppresses (reported as ALLOWED)" \
    "$(mkfix gfj tests/test_w.py 'import os\nos.killpg(p, 9)  # killpg-gate:allow test hands the guard a bad pgid\n')"
expect_fail "R4-reclass (strings are code-bearing now) GFk python3 heredoc data tuple + docstring inside a tests/*.sh" \
    "$(mkfix gfk tests/t.sh 'python3 - <<PY\nspecs = [("kill-wide", "#!/bin/sh\\nkill -9 -1\\n", True)]\ndef f():\n    """doc: os.killpg(1, 9)"""\nPY\n')"
expect_pass "GFl monkeypatch X.killpg = fake; def _fake_killpg(...) double (definition/replace, no signal)" \
    "$(mkfix gfl w.py 'import os\ndef _fake_killpg(pgid, sig):\n    return None\nos.killpg = _fake_killpg\nos.killpg = lambda pg, sig: None; x = 1\n')"
expect_fail "R4-reclass (strings are code-bearing now) GFm test reporter helpers ok/bad carrying the word killpg + kill -9 -1 text" \
    "$(mkfix gfm w.sh '#!/bin/bash\nbad "B2: killpg FAILED, kill -9 -1 is the disaster"\nok "B2: killpg killed the whole group"\n')"
expect_fail "R4-reclass (strings are code-bearing now) GFn env-prefixed python3 heredoc after 2>&1 (docstring + guarded call stay inert/guarded)" \
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
# 8. Review round 3 (NO-GO on 2315d04) -> round 4 STRUCTURAL: strings are CODE-BEARING by default.
#    Any literal (except a real comment) that spells a group kill is a finding; the audited marker on a
#    test path is the only exemption. Guard comparator DIRECTION is checked. Each R4* MUST FAIL, each
#    GF4* MUST PASS.
# ===================================================================
# 8.1 F3: comparator direction (a guard must establish pgid > 1, not >= 1 and not < 1)
expect_fail "R4-F3a 'if pgid >= 1' is not a guard" \
    "$(mkfix r4f3a w.py 'import os\ndef f(pgid):\n    if pgid >= 1:\n        os.killpg(pgid, 9)\n')"
expect_fail "R4-F3b 'if pgid < 1: return' leaves pgid == 1 reachable" \
    "$(mkfix r4f3b w.py 'import os\ndef f(pgid):\n    if pgid < 1:\n        return\n    os.killpg(pgid, 9)\n')"
expect_fail "R4-F3c shell [ \"\$pg\" -ge 1 ] is not a guard" \
    "$(mkfix r4f3c w.sh '#!/bin/bash\nf() {\n    if [ "$pg" -ge 1 ]; then kill -s KILL -- "-$pg"; fi\n}\n')"
expect_fail "R4-F3d shell [ \"\$pg\" -lt 1 ] is not a guard" \
    "$(mkfix r4f3d w.sh '#!/bin/bash\nf() {\n    [ "$pg" -lt 1 ] && return\n    kill -s KILL -- "-$pg"\n}\n')"
expect_fail "R4-F3e mirrored '1 <= pgid' is not a guard" \
    "$(mkfix r4f3e w.py 'import os\ndef f(pgid):\n    if 1 <= pgid:\n        os.killpg(pgid, 9)\n')"
expect_pass "GF4-F3f guard 'pgid > 1'" \
    "$(mkfix gf4f3f w.py 'import os\ndef f(pgid):\n    if pgid > 1:\n        os.killpg(pgid, 9)\n')"
expect_pass "GF4-F3g guard 'pgid >= 2'" \
    "$(mkfix gf4f3g w.py 'import os\ndef f(pgid):\n    if pgid >= 2:\n        os.killpg(pgid, 9)\n')"
expect_pass "GF4-F3h raise-early 'pgid <= 1'" \
    "$(mkfix gf4f3h w.py 'import os\ndef f(pgid):\n    if pgid <= 1:\n        raise ValueError(pgid)\n    os.killpg(pgid, 9)\n')"
expect_pass "GF4-F3i raise-early 'pgid < 2'" \
    "$(mkfix gf4f3i w.py 'import os\ndef f(pgid):\n    if pgid < 2:\n        raise ValueError(pgid)\n    os.killpg(pgid, 9)\n')"
expect_pass "GF4-F3j mirrored '1 < pgid' and '2 > qgid'" \
    "$(mkfix gf4f3j w.py 'import os\ndef f(pgid, qgid):\n    if 1 < pgid:\n        os.killpg(pgid, 9)\n    if 2 > qgid:\n        return\n    os.killpg(qgid, 9)\n')"
expect_pass "GF4-F3k shell -gt 1 / -le 1 / -ge 2 / -lt 2 guards" \
    "$(mkfix gf4f3k w.sh '#!/bin/bash\nf() {\n    [ "$pg" -gt 1 ] && kill -s KILL -- "-$pg"\n    [ "$qg" -le 1 ] && return\n    kill -9 -- "-$qg"\n    [ "$rg" -ge 2 ] && kill -9 -"$rg"\n    [ "$sg" -lt 2 ] && return\n    kill -TERM -"$sg"\n}\n')"
# 8.2 F4: signal given as a quoted variable
expect_fail "R4-F4a kill -s \"\$sig\" -- \"-\$pg\"" \
    "$(mkfix r4f4a w.sh '#!/bin/bash\nkill -s "$sig" -- "-$pg"\n')"
expect_fail "R4-F4b kill -s \"\$sig\" \"-\$pg\"" \
    "$(mkfix r4f4b w.sh '#!/bin/bash\nkill -s "$sig" "-$pg"\n')"
expect_fail "R4-F4c kill -s \${sig} -\$pg" \
    "$(mkfix r4f4c w.sh '#!/bin/bash\nkill -s ${sig} -$pg\n')"
expect_pass "GF4-F4d single-process kill -s \"\$sig\" \"\$p\" and a >1-guarded group form" \
    "$(mkfix gf4f4d w.sh '#!/bin/bash\nkill -s "$sig" "$p"\nkill -s "$sig" -- "$p"\nf() {\n    [ "$pg" -gt 1 ] || return 1\n    kill -s "$sig" -- "-$pg"\n}\n')"
# 8.3 F5: a string comparison with the name is not an alias
expect_pass "GF4-F5a x == \"killpg\" / x != 'killpg' comparisons" \
    "$(mkfix gf4f5a w.py 'def f(x):\n    if x == "killpg":\n        return 1\n    if x != '"'"'killpg'"'"':\n        return 2\n    return 3\n')"
expect_pass "GF4-F5b x==\"killpg\" without spaces" \
    "$(mkfix gf4f5b w.py 'def f(x):\n    return x=="killpg"\n')"
expect_fail "R4-F5c getattr(os, \"killpg\") is still an alias" \
    "$(mkfix r4f5c w.py 'import os\nk = getattr(os, "killpg")\n')"
# 8.4 strings are code-bearing by default (the reversal): each spelling inside any literal is a finding
expect_fail "R4-S1 python string literal spelling a group kill" \
    "$(mkfix r4s1 w.py 'cmd = "kill -9 -1"\nrun_later(cmd)\n')"
expect_fail "R4-S2 string handed to an unknown shell wrapper" \
    "$(mkfix r4s2 w.sh '#!/bin/bash\nok() { eval "$1"; }\nok "kill -9 -1"\n')"
expect_fail "R4-S3 docstring naming os.killpg( with a numeric target" \
    "$(mkfix r4s3 w.py 'def f():\n    """calls os.killpg(1, 9) on purpose"""\n')"
expect_fail "R4-S4 non-shell callee carrying shell=True" \
    "$(mkfix r4s4 w.py 'helper("kill -9 -$pg", shell=True)\n')"
expect_fail "R4-S5 Go raw string carrying syscall.Kill(-1, 9)" \
    "$(mkfix r4s5 w.go 'package main\nvar s = `\nsyscall.Kill(-1, 9)\n`\n')"
expect_pass "GF4-S6 same literal with the audited marker on a TEST path" \
    "$(mkfix gf4s6 tests/test_w.py 'cmd = "kill -9 -1"  # killpg-gate:allow fixture text for the gate under test\n')"
expect_fail "R4-S7 same literal with the marker on a NON-test path" \
    "$(mkfix r4s7 w.py 'cmd = "kill -9 -1"  # killpg-gate:allow fixture text\n')"
# 8.5 comments are exact: '#' inside a python string does not start a comment
expect_fail "R4-C1 '#' inside a python string does not hide the call after it" \
    "$(mkfix r4c1 w.py 'import os\ns = "a # b"; os.killpg(pg, 9)\n')"
expect_pass "GF4-C2 real comments naming os.killpg(1, 9) / kill -9 -1" \
    "$(mkfix gf4c2 w.py 'import os\n# never os.killpg(1, 9); kill -9 -1 is the disaster\nx = 1  # os.killpg(pg, 9)\n')"
# 8.6 F8 mutant M2: shell '#' starts a comment only at a word start
expect_fail "R4-M2 shell 'x=a#b; kill -9 -\"\$pg\"' ('#' mid-word is not a comment)" \
    "$(mkfix r4m2 w.sh '#!/bin/bash\nx=a#b; kill -9 -"$pg"\n')"
expect_fail "R4-M2b shell \$# / \${#x} do not start a comment" \
    "$(mkfix r4m2b w.sh '#!/bin/bash\necho $# ${#x}; kill -9 -1\n')"
expect_pass "GF4-M2c shell trailing comment at a word start hides only its own text" \
    "$(mkfix gf4m2c w.sh '#!/bin/bash\nls  # kill -9 -1 would be bad\nkill -0 "$pid"\n')"
# 8.7 F8 mutant M3: a shell=True line carrying a group-kill string is never inert
expect_fail "R4-M3 unknown callee with a group-kill string and shell=True" \
    "$(mkfix r4m3 w.py 'import subprocess\nmy_helper("kill -9 -$PGID", shell=True)\n')"
expect_fail "R4-M3b shell=True on a continuation line" \
    "$(mkfix r4m3b w.py 'import subprocess\ndo(\n    "kill -9 -$PGID",\n    shell=True)\n')"
# 8.8 F6: KILLPG_GUARD_ALLOW_PATHS globs must not be expanded against the cwd
GLOBCWD="$TMP/globcwd"; mkdir -p "$GLOBCWD"; : > "$GLOBCWD/zzz_present"
GLOBFIX="$(mkfix f6 lib/w.py 'import os\nos.killpg(p, 9)  # killpg-gate:allow reviewed exception for the glob test\n')"
if (cd "$GLOBCWD" && KILLPG_GUARD_ALLOW_PATHS='lib/*' bash "$GATE" --root "$GLOBFIX" >/dev/null 2>&1); then
    echo "✅ META OK:   R4-F6 allow-paths glob 'lib/*' honoured with a populated cwd (no pathname expansion)"
else
    echo "❌ META FAIL: R4-F6 allow-paths glob was expanded against the cwd (marker on lib/w.py ignored)"
    rc=1
fi
if (cd "$GLOBCWD" && KILLPG_GUARD_ALLOW_PATHS='*' bash "$GATE" --root "$GLOBFIX" >/dev/null 2>&1); then
    echo "✅ META OK:   R4-F6b allow-paths '*' honoured in a non-empty cwd"
else
    echo "❌ META FAIL: R4-F6b allow-paths '*' expanded against the non-empty cwd"
    rc=1
fi
# 8.10 reclassified prose/fixture text: the audited marker (real comment, test path, reason) is the exemption
expect_pass "R4-GFa2 one-line docstring prose + audited marker on a test path" \
    "$(mkfix r4gfa2 tests/test_w.py 'def f():\n    """Never call os.killpg(1, 9)."""  # killpg-gate:allow docstring prose\n    return 1\n')"
expect_pass "R4-GFb2 sh heredoc body line carrying a marker comment (python-in-sh) on a test path" \
    "$(mkfix r4gfb2 tests/t.sh 'python3 - <<PY\ndef f():\n    return "kill -9 -1"  # killpg-gate:allow fixture text only\nPY\n')"
expect_pass "R4-GFc2 shell echo of kill text + trailing marker on a test path" \
    "$(mkfix r4gfc2 tests/t.sh '#!/bin/bash\necho "kill -9 -1"  # killpg-gate:allow reporter text\n')"
expect_pass "R4-GFi2 Go string naming syscall.Kill(-1, 9) + marker on a test path" \
    "$(mkfix r4gfi2 tests/w_test.go 'package main\nvar s = "syscall.Kill(-1, 9)" // killpg-gate:allow fixture text\n')"
expect_fail "R4-GFi3 same Go line on a NON-test path is still a finding" \
    "$(mkfix r4gfi3 w.go 'package main\nvar s = "syscall.Kill(-1, 9)" // killpg-gate:allow fixture text\n')"

expect_pass "R4-GFo2 two kills on one guarded line (group kill first, single-process kill second)" \
    "$(mkfix r4gfo2 w.sh '#!/bin/bash\nwhile read -r j; do\n    if [ "$j" -gt 1 ]; then kill -s KILL -- "-$j" 2>/dev/null; kill -s KILL "$j" 2>/dev/null; fi\ndone\n')"
expect_fail "R4-MUT-o2 same two-kill line WITHOUT the guard" \
    "$(mkfix r4muto2 w.sh '#!/bin/bash\nwhile read -r j; do\n    kill -s KILL -- "-$j" 2>/dev/null; kill -s KILL "$j" 2>/dev/null\ndone\n')"

# 8.9 the independent reviewer's 188-shape corpus: every reachable group-kill shape MUST FAIL
CORPUS_GEN="${SCRIPT_DIR}/fixtures/killpg_reviewer_corpus.py"
if [ -f "$CORPUS_GEN" ] && command -v python3 >/dev/null 2>&1; then
    CORPUS="$TMP/corpus"; mkdir -p "$CORPUS"
    python3 -I "$CORPUS_GEN" "$CORPUS"
    mapfile -t KNOWN_GAP_IDS < <(python3 -I "$CORPUS_GEN" --known-gap)
    mapfile -t BENIGN_IDS < <(python3 -I "$CORPUS_GEN" --benign)
    corpus_bad=0; corpus_n=0
    for cd_ in "$CORPUS"/*/; do
        cid="$(basename "$cd_")"
        case " ${KNOWN_GAP_IDS[*]} " in *" $cid "*) continue ;; esac
        case " ${BENIGN_IDS[*]} " in *" $cid "*)
            if ! bash "$GATE" --root "$cd_" >/dev/null 2>&1; then
                echo "❌ META FAIL: reviewer corpus benign control ${cid} (sanctioned wrapper) — gate FAILed (false-positive refusal, §11.4.201(1))"
                corpus_bad=$(( corpus_bad + 1 ))
            fi
            continue ;; esac
        corpus_n=$(( corpus_n + 1 ))
        if bash "$GATE" --root "$cd_" >/dev/null 2>&1; then
            echo "❌ META FAIL: reviewer corpus shape ${cid} — gate PASSed on a dangerous shape (false negative)"
            corpus_bad=$(( corpus_bad + 1 ))
        fi
    done
    if [ "$corpus_bad" -eq 0 ]; then
        echo "✅ META OK:   reviewer corpus — all ${corpus_n} asserted shapes FAILed (${#KNOWN_GAP_IDS[@]} indirect shapes recorded as KNOWN_GAP, not asserted)"
    else
        echo "❌ META FAIL: reviewer corpus — ${corpus_bad}/${corpus_n} dangerous shapes were not flagged"
        rc=1
    fi
else
    echo "❌ META FAIL: reviewer corpus generator or python3 missing (${CORPUS_GEN})"
    rc=1
fi

# ===================================================================
# 8.10 ROUND 5: output integrity + shell operand grammar + python decoding + META cases.
# Every case asserts the exit status; the marker / heredoc cases ALSO assert the gate's
# OUTPUT (ALLOWED / IGNORED lines and the suppressed-site count), so a deleted echo or a
# dropped last record (marker file without trailing newline) is detected.
# ===================================================================
R5GEN="${SCRIPT_DIR}/fixtures/killpg_round5_cases.py"
if [ -f "$R5GEN" ] && command -v python3 >/dev/null 2>&1; then
    R5="$TMP/round5"; mkdir -p "$R5"
    python3 -I "$R5GEN" "$R5"
    r5_n=0; r5_bad=0
    while IFS=$'\t' read -r cid crc creq || [ -n "$cid" ]; do
        [ -n "$cid" ] || continue
        r5_n=$(( r5_n + 1 ))
        cout="$(bash "$GATE" --root "$R5/$cid" 2>&1)"; crc_got=$?
        if [ "$crc_got" -ne "$crc" ]; then
            echo "❌ META FAIL: round-5 case ${cid} — expected rc=${crc}, got rc=${crc_got}"
            r5_bad=$(( r5_bad + 1 )); continue
        fi
        IFS='|' read -r -a reqs <<< "$creq"
        for rq in "${reqs[@]}"; do
            [ -n "$rq" ] || continue
            if ! grep -qF -- "$rq" <<< "$cout"; then
                echo "❌ META FAIL: round-5 case ${cid} — gate output lacks '${rq}'"
                r5_bad=$(( r5_bad + 1 ))
            fi
        done
    done < "$R5/MANIFEST.tsv"
    if [ "$r5_bad" -eq 0 ]; then
        echo "✅ META OK:   round-5 cases — ${r5_n} cases hold (exit status and gate output)"
    else
        echo "❌ META FAIL: round-5 cases — ${r5_bad} assertion(s) failed of ${r5_n} cases"
        rc=1
    fi
else
    echo "❌ META FAIL: round-5 case generator or python3 missing (${R5GEN})"
    rc=1
fi

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
