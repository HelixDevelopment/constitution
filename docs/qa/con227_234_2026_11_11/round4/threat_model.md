# CON-234 class, round 4 (structural): threat model, design and census

| Field | Value |
|---|---|
| Item | CON-234 (n-4 class), with CON-228 and CON-233 touched; vehicle `vehicle/fix227` |
| Round | 4 (§11.4.276(E)(3) structural round: fresh fixer instance; the same class recurred in rounds 1, 2 and 3 as F1, G2, H1) |
| Class name | credential text in the output of an external command, and the temp files that hold it |
| RED head | `34bbeb4e` (the round-3 head); RED and GREEN files beside this one |
| Author | Claude Opus 5.5 subagent (fixer). Effort not verifiable from inside the dispatch (§11.4.231(F.2)) |
| Correction | `round3.txt` line 97 said "git and curl percent-encode URLs; a raw `/` is not seen in any message". That is false: git 2.53 prints the configured URL verbatim (reproduced by the round-3 review and by case C25 here). The round-3 file is kept unchanged as the record; this line corrects it (§11.4.6). |

## 1. Threat model (what can carry a secret)

The release scripts run `git fetch`, `git push`, `git ls-remote`, `gh`, `glab`, `curl` (through
`release_publish_gitea.sh`), `sqlite3` and `jq`. Their stderr (and in a few places their stdout) is the
only external text the scripts print. A secret can be in that text as:

1. URL userinfo of any scheme: `https`, `http`, `ssh`, `git`, `ftp`, `svn+ssh`, upper-case schemes. The
   password can hold any byte, because git prints the configured remote URL verbatim: a raw `/`, `@`, `?`,
   `#`, a quote, a space, percent-encodings, an invalid UTF-8 byte, a NUL. Userinfo can be long (an
   unencoded base64 token is 40-200 bytes). A user part alone (`https://TOKEN@host`) is a secret too.
2. A scheme-less `user:password@host:path` form.
3. The value of a query, fragment or form parameter named like a credential: `access_token`, `token`,
   `private_token`, `private-token`, `key`, `api_key`, `apikey`, `password`, `passwd`, `pwd`, `secret`,
   `client_secret`, `sig`, `signature`, `auth`, `X-Amz-Signature`, `X-Amz-Credential`,
   `X-Amz-Security-Token`, `refresh_token`, `id_token`, `session`, `jwt`, in any case.
4. HTTP header lines, printed by git when an operator sets `GIT_TRACE_CURL` / `GIT_CURL_VERBOSE` with
   `GIT_TRACE_REDACT=0`, or by `curl -v`: `Authorization`, `Proxy-Authorization`, `PRIVATE-TOKEN`,
   `X-*-Token`, `X-Api-Key`, `Cookie`; and a bare `Bearer <token>`.
5. Known token shapes anywhere: `ghp_`/`gho_`/`ghu_`/`ghs_`/`ghr_`, `github_pat_`, `glpat-`.

Where the text can go: (a) stdout of the scripts; (b) their stderr; (c) temp files they create, while the
run lasts and after it (normal exit, `exit` on an error, SIGHUP, SIGINT, SIGTERM, SIGKILL); (d) a
`bash -x` trace; (e) logs (the scripts write none of their own). Truncation adds one more way: a cut that
falls inside a secret prints its prefix unless redaction runs first.

## 2. Design (closes the class by construction)

1. **One helper, whole-line rules.** `scripts/release/redact_cut.sh` (`rc_redact_cut N [mark]`) is the only
   place where external text becomes printable. Rules R1-R6 (header, bearer, URL userinfo from the FIRST
   `://` to the LAST `@` of the line, scheme-less userinfo, credential-named parameters, token shapes) are
   applied per line, so no character inside a password can end a match early; then at most N bytes are
   printed. It sets `LC_ALL=C` itself and drops NUL bytes. Over-redaction (a later path `@`, a second
   URL's host) is accepted: an error line loses detail, never a secret. POSIX awk only (passes under gawk
   5.3.2 and mawk: `green_redact_cut_mawk.txt`).
2. **No raw stderr in a file where avoidable.** The stderr of fetch, push, the non-atomic fallback pushes
   and the gitea publisher is captured into a shell variable (`$(cmd 2>&1 >/dev/null)`), never a file,
   and printed only through the helper, after the script's own one-line reason with the exit code
   (`ABORT fetch of r1 main failed (git exit 128)`, `PUSH r2 main push failed; tag NOT pushed (git exit 1): ...`).
3. **One private run directory.** `tag_and_release.sh` creates one `mktemp -d` directory (0700) for its only
   two files (`exterr`, the uncaptured stderr collected for the exit flush, and `notes`); the publisher
   and `derive_release_facts.sh` already had one each (0700). Each is removed in the EXIT trap; HUP, INT
   and TERM traps end the run through it. Only SIGKILL leaves the directory (0700, same uid).
4. **Defence in depth.** `GIT_TRACE_REDACT=1` is exported by all three scripts (git redacts its own traces
   even if the caller set 0); `set +x` at the top of all three; the publisher validates the server-returned
   release id as a number before printing it.

## 3. What is left (honest limits, also in the helper header)

- A parameter VALUE holding a raw blank or one of `& # ; ' " < >` prints the part after that character.
- A credential split over two lines (a raw newline inside it).
- A secret printed in none of the five shapes (a bare word).
- R2/R4/R5/R6 scan the first N+4096 bytes of a line (enough for every printed byte except a scheme-less
  userinfo longer than 4096 bytes); R1 and R3 scan the whole line.
- SIGKILL leaves the 0700 run directory with the uncaptured-stderr file (and, for the publisher, the
  0600 curl config holding the token: unchanged since before this vehicle).
- The tag script prints the GitHub repository id returned by `gh api` without checking it is a number
  (server-controlled, not a credential); registered as a follow-up, not fixed here.

## 4. Census (§11.4.273, control needles)

Static census: `census_static.txt` (positive needle `rc_redact_cut` found in every script; fabricated
negative needle `ZZNOSUCHNEEDLE` 0 in every file). Every stderr redirection is one of: `2>/dev/null` on a
command whose output is not printed; `2>&1 >/dev/null` into a variable that is printed only through the
helper; `2>"$W/err.out"` (publisher curl, inside the 0700 run dir, printed through the helper, removed in
cleanup); the `exec 2>` into the run directory's exterr (flushed through the helper). The only cutter
outside the helper is `cut -c1-120` of a CHANGELOG heading (repository content, not external output).
Temp creation is `mktemp -d` only (three run directories; case C24b checks no plain `mktemp "`).

Dynamic census, each a case with a positive control (proof the instrument sees the text or the files):

| path | case(s) | control needle |
|---|---|---|
| stdout + stderr, real git, raw `/` password | C25 | `<redacted>@host.invalid` printed |
| stdout + stderr, real git, query token | C25b | `access_token=<redacted>` printed |
| fetch / push / fallback / gitea stderr | C21, C21b, C21c, C28, C19-C23 | redacted line printed |
| exit-time flush (tar, publisher, derive) | C21d, C29, publisher 12, derive suite | redacted line / truncation line printed |
| files after exit: success, fetch fail, push fail, fallback fail, all gitea rcs | C26 | the run dir is seen under TMPDIR during the run |
| files after SIGTERM / SIGHUP (tar, publisher) | C27, publisher 14 | "start" line printed / run started |
| files after publisher success, curl failure, refusal | publisher 13 | `rpg.` seen under TMPDIR during the run |
| `bash -x` trace | C30 | redacted git message printed |
| header lines (I-2) | helper A1-A9, publisher 16 | `Authorization: <redacted>` printed |
| GIT_TRACE_REDACT forced | C26 | git double sees `redact=1` when the caller set 0 |
| server-returned id (I-4) | publisher 15 | rc 4 |

Not covered by a run: SIGINT is not exercised (a background job ignores SIGINT in a non-interactive
shell; the INT trap is the same `exit` path as HUP and TERM); SIGKILL (by definition nothing runs).

## 5. Mutation run

`mutations.txt`: the full run of 60 mutants (reviewer T2-T6, D1, D5, Q1-Q12; earlier rounds' O, F, R, N, P mutants;
own S1-S16) gave killed=56 survived=4. S7 (the helper drops its own `LC_ALL=C`) and S8 (NUL bytes kept) were real
gaps of the helper test: cases C11 (byte budget under a UTF-8 caller locale: the mutant prints 800 bytes for a
400-byte budget) and C12 (no NUL byte in the output) were added and kill them. Q12 and S11 (the HUP/INT/TERM traps
of the publisher and of the tag script removed) are recorded EQUIVALENT for the property the tests check (no file
left after a signal): `equivalence_probe_q12_s11.txt` shows that bash 5.3.9 runs the EXIT trap on an untrapped
TERM or HUP too, with a control proving the leftover count sees a directory. The only observable difference is
that without the traps the script dies by the signal instead of exiting 129/143 through its own path. They are
kept in the harness as `meq` lines, re-run every time and reported if they ever become killable. The four were
re-run alone after the change (S7, S8 killed; Q12, S11 equivalent); the full 60-mutant run was not repeated.

Found after the full mutation run: the mutation harness ran each mutated script in the caller's TMPDIR, so
mutants that keep files (S10, Q3, Q7-Q9, R5, ...) left 137 `tar_run.*` / `rpg.*` directories there (only
fixture needles, no real credential). The four suites alone leave none (`TMPDIR=<fresh dir> bash
tests/release/test_tag_and_release.sh` left 0 entries). The harness now gives every suite run its own TMPDIR
inside its work directory, removed with it (checked with `--only S10`, a mutant that keeps its run directory:
the shared TMPDIR count was the same before and after). The 137 directories of this run were removed with
`safe_rm_rf`; 7 older ones (16:46Z, from an earlier development run of the harness, not attributable with
certainty) were left for the conductor.
