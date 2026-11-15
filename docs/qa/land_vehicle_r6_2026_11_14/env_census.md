# land_vehicle.sh round 6: shell startup and option channels (class C, R5-C)

Status: PROVISIONAL. Evidence class: gate logic only (§11.4.289 clause C(2)).

## The finding

The round-5 review (R5-C) measured that tracing turned on by the caller prints every
remote URL, and any credential in it, to stderr: `SHELLOPTS=xtrace` (114 lines with the
stand-in token), a `BASH_ENV` file running `set -x` (30 lines). `bash -x` was named but
not run by the reviewer.

## The class

Every way the caller's environment or command line can change how the bash running the
lander behaves, before or while the first line runs. Members, enumerated from the bash
manual (census below) plus the bash command line:

| Member | How it enters | Effect if kept | Round 6 |
|---|---|---|---|
| `bash -x`, `bash -v` | command line | traces every command, URLs included | `set +x +v` is the first statement; the clean re-run does not pass any option |
| `bash -O <shopt>`, `bash -o <opt>` | command line | for example `nocasematch` makes the tracker-path match case-insensitive | clean re-run (options are not passed on) |
| `SHELLOPTS` | environment | sets `set -o` options at startup (xtrace) | removed before the re-run |
| `BASHOPTS` | environment | sets `shopt` options at startup (nocasematch) | removed |
| `BASH_ENV` | environment | a file run before the script and before every `bash -c` the script starts (mint, id-verify) | removed; the first run still executes it (caller's own code, see the boundary) |
| `ENV` | environment | the startup file in POSIX mode | removed |
| `POSIXLY_CORRECT` | environment | POSIX mode | removed |
| `BASH_COMPAT` | environment | older semantics | removed |
| `BASH_XTRACEFD`, `PS4` | environment | where and how a trace is written (PS4 can run a command substitution) | removed |
| `GLOBIGNORE`, `GLOBSORT` | environment | globbing | removed |
| `EXECIGNORE` | environment | command search | removed |
| `FUNCNEST` | environment | function depth limit | removed |
| `TMOUT` | environment | `read` timeouts | removed |
| `CHILD_MAX` | environment | child status bookkeeping | removed |
| `BASH_LOADABLES_PATH` | environment | `enable -f` search path | removed |
| `BASH_CMDS`, `BASH_ALIASES` | environment | imported by bash (measured); seed the command hash table and the alias table | removed |
| exported functions (`BASH_FUNC_<name>%%`) | environment | a function named `git`, `grep`, `awk` ... shadows the command | every `BASH_FUNC_*` entry removed (read from `env -0`, so every exported function, valid or not) |
| functions, aliases, traps, options set by a `BASH_ENV` file | the first run | same as above | gone in the clean re-run, which reads no startup file |
| `CDPATH` | environment | `cd` | already unset (round 4) |
| `LANG`, `LC_*` | environment | regex and grep semantics | already pinned: `LC_ALL=C` |
| `IFS` | environment | word splitting | NOT imported by bash (measured: `env IFS=: bash -c 'printf %q "$IFS"'` prints `$' \t\n'`) |
| `BASH_ARGV0` | environment | `$0` | NOT imported by bash (measured) |

Not in the class, with the reason:

* read-only or dynamic variables bash sets itself (`BASH`, `BASH_SOURCE`, `BASHPID`,
  `LINENO`, `RANDOM`, `SECONDS`, `EPOCH*`, `PPID`, `UID`, `EUID`, `GROUPS`, `PIPESTATUS`,
  `BASH_REMATCH`, `BASH_VERSINFO`, ...): an environment value does not change them;
* interactive-only variables (`HIST*`, `PS0`-`PS3`, `PROMPT_COMMAND`, `PROMPT_DIRTRIM`,
  `MAIL*`, `COMP_*`, `COMPREPLY`, `READLINE_*`, `INPUTRC`, `IGNOREEOF`, `HOSTFILE`, `FCEDIT`,
  `FIGNORE`, `EMACS`, `INSIDE_EMACS`, `COLUMNS`, `LINES`): a non-interactive script never
  reads them;
* left to the caller on purpose: `PATH` (it selects `git`; the header states the caller's
  config and tools are trusted), `HOME` (git's global config), `TMPDIR`, `SHELL`, `PWD`,
  `OLDPWD`, `HOSTNAME`, `HOSTTYPE`, `MACHTYPE`, `OSTYPE`, `OPTERR`, `OPTIND`, `OPTARG`,
  `REPLY`, `MAPFILE`, `DIRSTACK`, `COPROC`, `SHLVL`, `TIMEFORMAT`.

## Census (control-needled)

`census/bash_shell_variables.txt` is every name in the `Shell Variables` section of
`man bash` (GNU bash 5.3.9), 109 names. Control needles (`census/bash_shell_variables_needles.txt`):
the known members `SHELLOPTS` and `BASH_ENV` are found (2), the fabricated `ZZFAKEVAR` is
not (0). The coverage is machine-checked, not asserted: `census/classification.tsv`
assigns every one of the 109 names one class (the removal list is read from the lander's
`LV_DIRTY` line), and `census/classification_check.txt` records 0 unclassified names and 0
removal-list names outside the census.

## Mechanism

1. `set +x +v` before anything else.
2. If `LAND_VEHICLE_EXEC` is not this PID: `exec env -u <each member> LAND_VEHICLE_EXEC=$$
   "$BASH" --norc --noprofile -- <script> <args>`. `exec` keeps the PID, so the marker
   identifies this run only; a marker forged by the caller differs from the PID and only
   causes the re-run.
3. In the re-run: unset the marker; if any member is still present, exit 2.

## Tests (round 6)

R6-C0 (control: a traced shell that reads the remotes file prints the token), R6-C-shellopts,
R6-C-bashenv, R6-C-bashx (0 token lines in all output, 0 evidence files, all 9 remotes
landed), R6-C4 and R6-C4b (an exported function and a `BASH_ENV` function named `git` never
run; control: the exported function does run in a plain bash), R6-C5-dashO and
R6-C5-bashopts (`nocasematch` from the caller does not let a mint write `docs/TRACKER.FAKE`).

## Honest boundary

A `BASH_ENV` file runs the caller's code with the caller's rights before the first line of
the lander. It can do anything (redefine `set`, `exec` or `env`, write files). This is not a
security boundary: the lander protects against accidental leaks from tracing and against
inherited options and functions, not against a hostile caller environment.
