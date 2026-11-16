# Class census: a process feeds a child's stdin in full before draining its stdout

Date: 2026-11-16. Tree: clone of origin main at bbdf4ac1 (scripts/ only, §11.4.276(C)).

Instrument (rerunnable from the repository root):

    grep -rnI 'stdin\.write\|stdin=subprocess.PIPE\|stdin=PIPE\|coproc\|\.stdin\.close' scripts/
    grep -rnIl 'Popen' scripts/ | xargs grep -lnI 'stdin *= *\(subprocess\.\)\?PIPE'
    grep -rnIE 'open2|open3|IPC::' scripts/
    grep -rnIE '\.Stdin *=|StdinPipe' scripts/ --include='*.go'
    grep -rnI 'mkfifo\|exec [0-9]*<>' scripts/

Positive control: the first command finds the known site
`scripts/security/history_secret_scan.sh:181` (`p.stdin.write(...)`) on the
unfixed tree. Negative control: `grep -rnI 'stdin\.writeNOSUCH' scripts/`
returns nothing. Of 27 files under scripts/ that call `Popen(`, 5 pass a
stdin pipe; each is listed below.

| Site | Shape | Verdict |
|---|---|---|
| scripts/security/history_secret_scan.sh (exact-match matcher) | all blob ids written to `git cat-file --batch` stdin, then stdout read | IN CLASS, defect, FIXED here (ids come from a regular file; replies checked) |
| scripts/codegraph/codegraph_mcp_probe.py:130-192 | one small JSON-RPC line per send, then select/read of the reply before the next send | not in class (request/response lockstep; stderr goes to a file) |
| scripts/codegraph/codegraph_mcp_health.py:459-496 | same lockstep as above | not in class; adjacent risk recorded: stderr=PIPE is never read while the session runs, so a server writing more than one pipe buffer of stderr would block (UNCONFIRMED whether any server does; not fixed here, out of scope §11.4.293) |
| scripts/fastcycle/orchestration/custody_sweep.py:440 | `communicate(input=...)` | not in class (communicate writes and reads concurrently) |
| scripts/fastcycle/tokens/test_dispatch_stamp_r7_matrix.sh:120 | `communicate(payload)` | not in class |
| scripts/label-sync/mcp/label-mcp/server_test.go:572 | `StdinPipe` + four small lines, stdout to a bytes.Buffer | not in class (exec copies stdout in a goroutine) |
| scripts/multitrack/multitrack_fallback_monitor.sh:445 | `coproc` of `tail -F`, read only | not in class (nothing written) |
| scripts/fastcycle/tests/test_review_record_gate_authority_r3_regression.sh:423 | `exec 7<>fifo; cat ev.bytes >&7` before the reader starts | same shape, bounded: blocks only if ev.bytes exceeds one pipe buffer; ev.bytes is a small generated evidence file. Recorded, not fixed (out of scope §11.4.293) |
| other mkfifo hits (test_check_deps.sh:124, test_fc_safepath_v4r15.sh:156, two Python tests) | no bulk write before a reader | not in class |

Honest boundary (§11.4.6): a grep census finds the spellings above; a child
fed through another spelling (for example `os.write` on a raw pipe fd) would
not be found. No such spelling was seen in the files read.
