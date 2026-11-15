# Incident J7: an unscoped `pkill` in the round-4 fixer's session

| Field | Value |
|---|---|
| Found by | the conductor; recorded as finding J7 of the round-4 review (`scratchpad/review_fix227_r4.md`, section J7) |
| Round | 4 of the CON-227..234 release-tooling work, vehicle `vehicle/fix227` |
| Recorded by | the round-5 fixer (Claude Opus 5.5 subagent), 2026-11-11; this fixer did not run the command and did not observe its effect |
| Severity | UNKNOWN (§11.4.6). The review classes the finding "important"; whether any process of another agent was actually ended is not known: no record of the signalled PIDs exists |
| Rules | §11.4.174 (verify a process is ours before signalling it), §11.4.263 (process-group signal safety, in spirit), §12 |

## What happened

During round 4 the fixer ran `pkill -f "sleep 30" -P 1` to end `sleep 30` processes its own test
doubles had left behind. That command signals EVERY process of the same uid whose parent is PID 1 and
whose command line contains `sleep 30`, not only the ones the fixer started. On a host where several
agents run, that includes every orphaned or detached `sleep 30` of every other session.

## Why it matters

A common watchdog shape is `( sleep 30; kill "$job" ) &`. Ending its `sleep` early makes the watchdog
fire at once and end the job it watches. So the command could have ended other agents' work early,
not only shortened a wait.

## What is known and what is not

* Known: the command was run (reported by the conductor).
* Not known: which PIDs it matched, whose they were, and whether any job was ended early. There is no
  record, so the effect cannot be reconstructed.

## The rule, restated for every dispatch

Signal only a PID the agent itself started (captured from `$!`, a pid file the agent's own double
wrote, or `Popen.pid`), greater than 1, after reading its real command line from
`/proc/<pid>/cmdline` where the PID could have been reused. Never `pkill`, `killall` or a `-f` pattern
match; never a negative PID or a process group the agent did not create.

## What round 5 did differently

* The suites signal only PIDs they started: `kill -s SIG "$sp"` / `p.send_signal` on the child the
  test spawned; the SIGKILL case of the publisher suite (case 18) ends its curl double through the
  PID that double wrote to its own pid file, checked to be a number greater than 1.
* The hanging test doubles `exec sleep`, so `timeout(1)` in the script under test ends exactly that
  process, and no orphaned `sleep` is left for anyone to clean up.

Tracked item CON-273 asks for a guard (or gate) that refuses `pkill` / `killall` / `pgrep -f`
driven signals in agent sessions; it is a follow-up, not claimed done here. The
incident itself is recorded as CON-274 (severity UNKNOWN).

Re-mint note (round 6, 2026-11-12): at the merge of main `66ad6efe` into vehicle/fix227 the vehicle ids CON-269 to CON-276 used in this file were re-minted as CON-300 to CON-307 in the same order (section 11.4.214; main uses CON-269 to CON-272 for other items). Map: `../round6/remint_map.txt`. The text above is kept as written.
