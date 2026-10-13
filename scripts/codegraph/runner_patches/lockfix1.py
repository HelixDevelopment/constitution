"""lockfix1 — a codegraph.lock is stale ONLY when its owner is not a live codegraph process.

Stock v1.6.0 FileLock.acquire (lib/dist/utils.js) treats any lock whose mtime is
older than STALE_TIMEOUT_MS (2 min) as stale REGARDLESS of whether the recorded
PID is alive, and unlinks it; nothing refreshes the mtime. A second
sync/index/init/serve started >2 min after a long index began therefore deletes
the live lock and writes the database concurrently (finding F1).

Chosen fix (smallest safe change, two anchors):
  * the acquire condition drops the age clause and requires, for a lock to be
    honoured, pid is an integer > 1, the process is alive (vendor
    isProcessAlive = kill(pid, 0)), AND its real identity is a codegraph
    process (/proc/<pid>/cmdline contains "codegraph") — a recycled PID that
    now belongs to an unrelated program is reaped as stale;
  * where /proc is not mounted (non-Linux) or the cmdline is unreadable for any
    reason other than ENOENT, the owner is treated as live (never steal a lock
    whose ownership cannot be disproven).

Rejected alternative — refreshing the lock mtime from a heartbeat timer: the
vendor's own comments (resolution/cooperative-yield.js, db/wal-valve.js) record
that synchronous parse/store/resolve spans block the event loop for minutes, so
a setInterval refresh would itself miss the 2-min window under exactly the load
that triggers the bug; it also would not fix the PID-reuse case.

Honest boundary: the lock file stores only a PID (no hostname), so a lock
written by a codegraph process on ANOTHER host over a shared filesystem is
judged against the local PID table — identical to stock's PID check; this patch
removes only the age-based override.
"""
from .common import NotNeeded, PatchPlan, Refuse

PATCH_ID = "lockfix1"
SUMMARY = "codegraph.lock stale only when its PID is not a live codegraph process (no 2-min age override)"
UTILS = "lib/dist/utils.js"

COND_ANCHOR = "if (lockAge < FileLock.STALE_TIMEOUT_MS && !isNaN(pid) && this.isProcessAlive(pid)) {"
COND_NEW = ("if (!isNaN(pid) && pid > 1 && this.isProcessAlive(pid) && "
            "__helixLockOwnerIsCodegraph(pid)) { // helix-lockfix1: no age override")
CLASS_ANCHOR = "class FileLock {"
HELPER = r'''// helix-lockfix1 (constitution/scripts/codegraph/runner_patches/lockfix1.py):
// the recorded owner is honoured only while it is a live CODEGRAPH process.
function __helixLockOwnerIsCodegraph(pid) {
    if (!Number.isInteger(pid) || pid <= 1)
        return false;
    if (!fs.existsSync('/proc/self/cmdline'))
        return true; // no procfs: identity cannot be disproven -> never steal
    let raw;
    try {
        raw = fs.readFileSync(`/proc/${pid}/cmdline`);
    }
    catch (e) {
        return !(e && e.code === 'ENOENT'); // ENOENT: owner exited; other errors: keep
    }
    return raw.toString('utf-8').includes('codegraph');
}
class FileLock {'''


def plan(view):
    text = view.read(UTILS)
    if text.count(COND_ANCHOR) == 0:
        if ("class FileLock" in text and "STALE_TIMEOUT_MS" not in text
                and "isProcessAlive(pid)" in text):
            raise NotNeeded("utils.js FileLock no longer has an age-based stale override "
                            "(STALE_TIMEOUT_MS gone, PID liveness still checked)")
        if "__helixLockOwnerIsCodegraph" in text:
            raise Refuse("lockfix1: source is ALREADY patched — --src must be the pristine package")
    p = PatchPlan(PATCH_ID)
    p.replace_once(view, UTILS, CLASS_ANCHOR, HELPER, "class FileLock {")
    p.replace_once(view, UTILS, COND_ANCHOR, COND_NEW, "FileLock.acquire age-override condition")
    p.detail = {"removed_clause": "lockAge < FileLock.STALE_TIMEOUT_MS",
                "owner_identity_check": "/proc/<pid>/cmdline contains 'codegraph'"}
    return p
