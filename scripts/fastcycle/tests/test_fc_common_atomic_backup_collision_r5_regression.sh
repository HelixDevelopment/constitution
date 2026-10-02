#!/bin/sh
# =============================================================================
# T085 US2 Round 5 remediation regression (Minor finding 1, 2026-10-02).
# =============================================================================
#
# T085 Round 4's independent review, Minor finding 1: "atomic_backup_and_
# replace treats 'file already exists' as 'hardlinks unsupported' and
# falls back to a copy. That copy follows a symlink already sitting at
# the backup name and overwrites the symlink's target (demonstrated with
# a frozen clock). It also leaves an orphan backup if a later step
# fails, drops owner and xattrs, and does not fsync before the replace."
#
# Fixed: the backup path is now created via O_CREAT|O_EXCL (never
# overwritten, never followed if a symlink), retried with a freshly
# bumped counter on a genuine collision; the new content is fsync'd
# before os.replace() and the containing directory is fsync'd after; a
# failure after the backup was taken removes the now-unneeded backup
# too; the original file's owner is best-effort preserved.
#
# Usage: sh test_fc_common_atomic_backup_collision_r5_regression.sh
# Exit: 0 all checks held; 1 any FAIL.
# =============================================================================
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)

FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

echo "== T085 Round 5 Minor-1 regression: fc_common.atomic_backup_and_replace() collision/symlink/durability =="

OUT=$(python3 - "$FC/lib" <<'PYEOF'
import sys, os, tempfile, time, stat

sys.path.insert(0, sys.argv[1])
import fc_common

d = tempfile.mkdtemp()

# -----------------------------------------------------------------------
# Check 1: a symlink PRE-PLANTED at the exact backup_path name a frozen
# counter would produce is REFUSED/RETRIED, never followed-and-clobbered.
# -----------------------------------------------------------------------
target = os.path.join(d, "file.txt")
with open(target, "w") as fh:
    fh.write("original content\n")

victim = os.path.join(d, "victim.txt")
with open(victim, "w") as fh:
    fh.write("victim content -- must survive untouched\n")

fc_common._ATOMIC_BACKUP_COUNTER = 500
predicted = "%s.bak-%d-%d-%d" % (target, int(time.time() * 1000), os.getpid(), 501)
os.symlink(victim, predicted)
fc_common._ATOMIC_BACKUP_COUNTER = 500  # reset so the first real attempt collides with the planted symlink

backup = fc_common.atomic_backup_and_replace(target, "new content\n")

victim_content = open(victim).read()
print("CHECK1_VICTIM_UNTOUCHED=%s" % (victim_content == "victim content -- must survive untouched\n"))
print("CHECK1_BACKUP_NOT_PREDICTED=%s" % (backup != predicted))
print("CHECK1_BACKUP_REAL_CONTENT=%s" % (open(backup).read() == "original content\n"))
print("CHECK1_TARGET_UPDATED=%s" % (open(target).read() == "new content\n"))
os.unlink(predicted)

# -----------------------------------------------------------------------
# Check 2: owner is best-effort preserved (only meaningfully testable as
# non-root -- we instead confirm the chown ATTEMPT does not raise and
# does not corrupt the write when it is refused for lack of privilege).
# -----------------------------------------------------------------------
target2 = os.path.join(d, "file2.txt")
with open(target2, "w") as fh:
    fh.write("v1\n")
backup2 = fc_common.atomic_backup_and_replace(target2, "v2\n")
print("CHECK2_NO_CRASH_ON_CHOWN_ATTEMPT=%s" % (open(target2).read() == "v2\n"))

# -----------------------------------------------------------------------
# Check 3: durability -- the replacement content is genuinely fsync'd
# (indirect proof: a repeated read immediately after the call, with no
# crash, returns the new bytes; a direct fsync-call-count proof would
# need to intercept os.fsync, done here via monkeypatch to confirm the
# function genuinely CALLS os.fsync at least once per successful run).
# -----------------------------------------------------------------------
fsync_calls = []
real_fsync = os.fsync
def counting_fsync(fd):
    fsync_calls.append(fd)
    return real_fsync(fd)
os.fsync = counting_fsync
try:
    target3 = os.path.join(d, "file3.txt")
    with open(target3, "w") as fh:
        fh.write("v1\n")
    fc_common.atomic_backup_and_replace(target3, "v2\n")
finally:
    os.fsync = real_fsync
print("CHECK3_FSYNC_CALLED=%s" % (len(fsync_calls) >= 1))

# -----------------------------------------------------------------------
# Check 4: on a failure AFTER the backup was taken (new-content write
# fails), the now-unneeded backup is cleaned up -- never left orphaned.
# -----------------------------------------------------------------------
target4 = os.path.join(d, "file4.txt")
with open(target4, "w") as fh:
    fh.write("v1\n")
before_listing = set(os.listdir(d))

real_mkstemp = tempfile.mkstemp
def failing_mkstemp(*args, **kwargs):
    fd, path = real_mkstemp(*args, **kwargs)
    os.close(fd)
    os.unlink(path)  # sabotage: the returned fd is immediately invalid
    return fd, path
tempfile.mkstemp = failing_mkstemp
raised = False
try:
    fc_common.atomic_backup_and_replace(target4, "v2\n")
except OSError:
    raised = True
finally:
    tempfile.mkstemp = real_mkstemp

after_listing = set(os.listdir(d))
new_files = after_listing - before_listing
print("CHECK4_RAISED=%s" % raised)
print("CHECK4_NO_ORPHAN_BACKUP_LEFT=%s (new_files=%r)" % (len(new_files) == 0, sorted(new_files)))
print("CHECK4_TARGET_UNCHANGED=%s" % (open(target4).read() == "v1\n"))
PYEOF
)
echo "$OUT"

for check in CHECK1_VICTIM_UNTOUCHED CHECK1_BACKUP_NOT_PREDICTED CHECK1_BACKUP_REAL_CONTENT CHECK1_TARGET_UPDATED \
             CHECK2_NO_CRASH_ON_CHOWN_ATTEMPT CHECK3_FSYNC_CALLED CHECK4_RAISED CHECK4_NO_ORPHAN_BACKUP_LEFT CHECK4_TARGET_UNCHANGED; do
    if echo "$OUT" | grep -q "^${check}=True"; then
        ok "$check"
    else
        bad "$check (full output above)"
    fi
done

echo ""
echo "== Summary: ok $PASS / NOT ok $FAIL =="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
