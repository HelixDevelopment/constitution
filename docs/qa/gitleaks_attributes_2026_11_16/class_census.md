# Class census: read-time hiding of git history from secret scanners (2026-11-16)

Scope (§11.4.276(C)): every script under `scripts/` that scans git history or file
content for secrets. The class is "something git applies while READING makes a secret
invisible to the scanner, and the scan still exits as if it were clean".

Instrument: `grep -rlE 'gitleaks|log -p|cat-file|git show :|git grep' scripts`
(non-test files), then ranked by `secret|credential|leak|token` hits and read by hand.
Positive control: the instrument finds both known scanners
(`scripts/gitleaks/gitleaks_run_scan.sh`, `scripts/security/history_secret_scan.sh`).
Negative control: the scripts it lists that do not scan for secrets (release, gates,
installers) were read and use `cat-file` / `ls-files` for other purposes.

## Scripts that scan for secrets

| Script | How it reads content | Exposed before | After this change |
|---|---|---|---|
| `scripts/gitleaks/gitleaks_run_scan.sh` (S) | gitleaks `detect` on the checkout, which runs `git log -p -U0 ...` | Yes: every attribute shape, textconv, grafts, fake shallow, evil merge, a git error read as clean | Fixed (see below) |
| `scripts/security/history_secret_scan.sh` (H) | gitleaks on a fresh bare mirror, `--log-opts="--all -m"` | Partly: caller attribute files (`core.attributesFile`, XDG, `GIT_ATTR_SOURCE`), caller textconv, a shallow remote. Committed `.gitattributes` and the source's `info/attributes` / `info/grafts` do not reach the bare mirror (measured, git 2.53.0) | Fixed |
| `scripts/hooks/credential_scan_lib.sh` | A consumer pre-commit hook reads the staged blob with `git show :FILE` | No: `git show` of a blob prints raw content and applies no textconv unless `--textconv` is given (measured). Attributes do not filter it | Unchanged |
| `scripts/fastcycle/review/lib/precheck_pack_run.py` | `git cat-file blob` and files on disk | No: raw blob reads | Unchanged |

## Shapes, and the primitive that closes each one

| Shape | S before | H before | Primitive |
|---|---|---|---|
| Committed `.gitattributes` `-diff` / `binary` | false PASS | not reachable (bare mirror) | `--text` (overrides every attribute source) |
| `.git/info/attributes` | false PASS | not copied by `clone --mirror` | `--text` |
| `core.attributesFile` (repo, global, system through `GIT_CONFIG_SYSTEM`, `GIT_CONFIG_PARAMETERS`) | false PASS | false PASS | `--text` |
| `$XDG_CONFIG_HOME/git/attributes` | false PASS | false PASS | `--text` |
| `GIT_ATTR_SOURCE` | false PASS | false PASS | `--text` |
| textconv that prints nothing | false PASS | caller global textconv only applies to attributes it sees | `--no-textconv` |
| `diff.<driver>.binary`, `core.bigFileThreshold` | covered by `--text` | covered by `--text` | `--text` |
| Caller `--log-opts` replacing the defaults | the caller's opts dropped the protection | n/a (fixed opts) | S appends `-m --text --no-textconv` LAST to every `--log-opts` |
| Evil merge (secret only in a merge commit) | missed (no `-m`) | already had `-m` | `-m` |
| `.git/info/grafts` | missed (`GIT_NO_REPLACE_OBJECTS` does not disable grafts) | not copied by `clone --mirror` | `GIT_GRAFT_FILE=/dev/null/no-grafts` (an impossible path: `/dev/null` itself prints a deprecation hint, gitleaks then reads nothing) |
| Fake `.git/shallow` (parents present) | missed | copied by `clone --mirror`: missed | S: `GIT_SHALLOW_FILE=/dev/null`; H: refuses a shallow mirror |
| Really shallow clone (parents absent) | gitleaks' git errors, gitleaks exits 0 with 0 leaks | same | S: git pre-flight; H: shallow refusal. Both end INCONCLUSIVE / BLIND exit 3 |
| `refs/replace` | fixed by CON-435 | fixed by CON-435 | `GIT_NO_REPLACE_OBJECTS=1` (unchanged) |

## Positive evidence layer (fails closed)

- S runs a self-check before the scan. It builds a throw-away repository that has a `-diff`
  needle, a textconv needle, a merge-only needle and a plain negative file. It scans that
  repository with the same gitleaks binary and the same forced options. If any needle is
  missed or the negative is found, S exits 3 (INCONCLUSIVE), never a PASS.
- H adds two needles of its own to the mirror (`info/attributes` `-diff` and a textconv
  driver in the mirror config). If either is missed, H exits 3 (BLIND).

## Not covered (honest limits)

- The system attributes file (`$(prefix)/etc/gitattributes`) needs root to write. It was not
  tested. `--text` overrides every attribute source by git's documentation, but this source
  was not measured.
- The self-check uses fixed log-opts, not the caller's. A caller who passes, for example, a
  narrower revision range gets the forced flags appended. The self-check does not prove
  that range.
- Shapes outside git attributes, replace refs, grafts and shallow state are not claimed:
  for example a filter that rewrites on checkout (only relevant to `--no-git` scans, which
  read files on disk), or objects missing from a partial clone (not tested; UNCONFIRMED
  whether the pre-flight sees it).
