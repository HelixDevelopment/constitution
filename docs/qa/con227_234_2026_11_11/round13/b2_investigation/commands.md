# B2 investigation (2026-11-14): commands

All runs on the host `anton`, after the reboot of 2026-11-14 12:32 CET, against the standing tree (a detached
worktree at `8e0ef48b`, commit A). `<D>` is the round-13 scratch directory, `<E>` the investigation directory
under it (`mktemp -d`), `<H>` a `mktemp -d` HOME under `<E>`, checked non-empty and under `<E>` before use.
PATH in every run: `<D>/sqlbin:/usr/local/bin:/usr/bin:/bin`. Nothing here touched a network.

## Files

| File | What it is |
|---|---|
| `mutant_diff.txt` | the B2 mutant: `redact_cut.sh` with the loop-guard line removed (written by a Python replacement, the same text the harness line `mp B2` replaces) |
| `mk_probe.sh` | writes `p5.sh`; its `mkprobe` is line 245 of `tests/release/test_redact_cut.sh`, byte for byte, called as on line 293 |
| `run_probe.sh` | runs `p5.sh` as line 294 does and samples the scope's `pids.current` |
| `run_probe2.sh` | the same without the sampler (minimal task count) |
| `run_probe3.sh` | starts `p5.sh` and samples the looping bash's descriptor count every 2 s |
| `harness_b2.sh` | runs the standing harness with `--only B2` on the standing tree, with its own TMPDIR |
| `probe_t3000.txt`, `probe_t3000_pids_samples.txt` | `run_probe.sh` in a scope, TasksMax=3000, soft NOFILE 524288 |
| `probe_low_tasksmax.txt` | `run_probe2.sh` in scopes with TasksMax 4, 5, 6, 7 |
| `probe_fd_growth.txt` | `run_probe3.sh` in a scope, soft NOFILE 524288 |
| `probe_nofile_toggle.txt` | the mutant probe in a scope with `ulimit -n 1024`, then 524288 |
| `probe_service_mutant.txt` | the mutant probe as a transient service (the launcher's form) |
| `probe_control_unmutated.txt` | the unmodified library, same probe, soft NOFILE 1024 and 524288 |
| `harness_b2_both.txt` | the harness `--only B2`, twice as a transient service, twice as a scope |
| `repro_scope_partial.txt` | the pre-reboot repro (2026-11-14 07:35-11:05 CET): a scope run with `ONLY=B2` in the environment; the harness reads `--only B2`, not `ONLY`, so it ran the whole harness, and the host reboot stopped it after 314 lines; its B2 line is "killed by its property (FAIL K8 N2 loop guard: rc 124 ( ))" |

## Commands (as run)

```
# the mutant probe in a scope, TasksMax=3000
nice -n 10 systemd-run --user --scope --quiet -p TasksMax=3000 /usr/bin/env -i PATH=... HOME=<E> LANG=C.UTF-8 \
  bash <E>/run_probe.sh <E> t3000
# low task limits
for tm in 4 5 6 7; do timeout 60 nice -n 10 systemd-run --user --scope --quiet -p TasksMax=$tm \
  /usr/bin/env -i PATH=... HOME=<E> LANG=C.UTF-8 bash <E>/run_probe2.sh <E>; done
# descriptor growth
nice -n 10 systemd-run --user --scope --quiet -p TasksMax=3000 /usr/bin/env -i PATH=... HOME=<E> LANG=C.UTF-8 \
  bash <E>/run_probe3.sh <E>
# the toggle: soft NOFILE 1024 and 524288, the mutant
for n in 1024 524288; do nice -n 10 systemd-run --user --scope --quiet -p TasksMax=3000 /usr/bin/env -i PATH=... \
  HOME=<E> LANG=C.UTF-8 bash -c 'ulimit -n "$1"; bash "$2/run_probe2.sh" "$2"' _ "$n" <E>; done
# the mutant as a transient service (launch_standing13.sh's form)
systemd-run --user --quiet --collect --wait --pipe -p TasksMax=3000 /usr/bin/env -i PATH=... HOME=<E> \
  LANG=C.UTF-8 /usr/bin/nice -n 10 /bin/bash -c '...; bash "$1/run_probe2.sh" "$1"' _ <E>
# the control: the unmodified library under both limits (same scope form as the toggle, directory <E>/ctl)
# the harness, --only B2, twice per environment
systemd-run --user --quiet --collect --wait --pipe -p TasksMax=3000 /usr/bin/env -i PATH=... HOME=<H> \
  LANG=C.UTF-8 USER=zzfixer LOGNAME=zzfixer /usr/bin/nice -n 10 /bin/bash <E>/harness_b2.sh <D>/standing/tree <E> svcN
systemd-run --user --scope --quiet -p TasksMax=3000 /usr/bin/env -i PATH=... HOME=<H> LANG=C.UTF-8 USER=zzfixer \
  LOGNAME=zzfixer /usr/bin/nice -n 10 /bin/bash <E>/harness_b2.sh <D>/standing/tree <E> scopeN
```

`systemctl --user show -p DefaultLimitNOFILE -p DefaultLimitNOFILESoft` gave `DefaultLimitNOFILE=524288` and
`DefaultLimitNOFILESoft=1024` on this host.

The scripts are kept byte for byte as they ran. `shellcheck -S warning` reports SC2148 on `mk_probe.sh` (no
shebang; it is run with `bash mk_probe.sh`) and SC2011 on line 12 of `run_probe3.sh` (`ls | xargs` over
`/proc/PID/task/*/children`, whose names are numbers). Neither changes an output above.
