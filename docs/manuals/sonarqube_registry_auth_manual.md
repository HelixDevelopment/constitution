# SonarQube registry authentication - Manual

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-12 |
| Last modified | 2026-11-12T12:00:00Z |
| Status | active |
| Status summary | Reference for modes, variables, exit codes, files and limits of registry_login.sh. |
| Authority | Tool documentation for `scripts/sonarqube/registry_login.sh`; extends §11.4.184 (clause (J)); no new anchor and no new CM-* token. §11.4.10 (credentials), §11.4.161 (rootless), §11.4.18 (script documentation) and §11.4.289 (evidence class) govern. |
| Scope | Universal (§11.4.17): any project that runs SonarQube scans which pull private container images. |
| Issues | none |
| Generated twins | .html / .pdf / .docx not regenerated for this revision (honestly stale, §11.4.106(E)). |

## Variables

| Name | Meaning |
|---|---|
| `DOCKER_REGISTRY` | Registry host (consumer data; also `--registry`). |
| `DOCKER_USERNAME` | User. |
| `DOCKER_PASSWORD`, `DOCKER_TOKEN` | Secret; `DOCKER_PASSWORD` wins. |
| `DOCKER_AUTH_CONFIG` | The usual auths JSON; used when no username/password is given. Decoded in-process, engine login through stdin. |
| `SONAR_REGISTRY_ENV_FILE` | Env file path. Default `${XDG_CONFIG_HOME:-$HOME/.config}/helix/sonar_registry.env`. |
| `SONAR_REGISTRY_ENGINE` | `podman` or `docker`. Default: podman, then docker. |
| `SONAR_REGISTRY_PROBE_IMAGE` | Probe image for `verify`. |
| `SONAR_REGISTRY_LOGIN` | `off` skips the scan-time login. |
| `REGISTRY_AUTH_FILE` | Honoured by Podman only (Docker uses `DOCKER_CONFIG`); `discover` reports it. |

## Behaviour

- Engine choice: `--engine` wins over `SONAR_REGISTRY_ENGINE`; a forced engine that is invalid or not on PATH is exit 2 (no fallback); unset: Podman, else Docker; none on PATH is exit 2.
- Env file: must be a regular file (not a symlink) owned by you with no group/other permission bits (`mode & 077 == 0`, so 0600 or 0400 only); sourced in a subshell with auto-export and tracing disabled (`set +x`, `BASH_XTRACEFD` to `/dev/null`, re-asserted after sourcing); sourcing failure is exit 2. An explicitly given `--env-file` or `SONAR_REGISTRY_ENV_FILE` that does not exist is exit 2, not SKIP.
- Login: `printf '%s' "$PASS" | <engine> login --username U --password-stdin REG`. Output is passed through a literal masker for the password and `user:password`.
- Auth file (`--auth-file-only`, Podman only): `${XDG_RUNTIME_DIR:-$HOME/.cache}/helix_sonar_registry/auth.json`, private directory 0700 created by the tool, file created under `umask 077`. The registry host is restricted to `[A-Za-z0-9._:/-]` so the JSON cannot be broken.
- Field handling (round-5 extension): user and password are kept in separate arrays and never split by `IFS`; the decoded `auth` value is cut at the first colon by parameter expansion only. A username or password that is empty, whitespace-only, or contains a control character (TAB, newline, CR, DEL, or a NUL byte in an `auth` value) is exit 2 for both plain and `DOCKER_AUTH_CONFIG` credentials; a trailing newline is not stripped (so `u:p` plus newline is rejected, not trimmed). The username is passed as `--username=VALUE`, so a name starting with `-` is never an option; the password only on stdin. Inventory of secret/user pass-through points: tab-joined triples and the three `IFS=$'\t' read` sites (replaced), the `host<TAB>auth` pair read (replaced), command-substitution newline stripping (sentinel), NUL dropping (length check), the engine argv (`--username=`), `rl_mask` (`IFS=` read, no split, unchanged), env-file sourcing (executes a 0600 file you own, out of scope by design), `sonarqube_lib.sh` export loop (no splitting, unchanged), `--auth-file-only` (values already validated). `--registry R` with no credentials is exit 2, like `DOCKER_REGISTRY` alone.
- Wiring: `sq_registry_login_auto` in `sonarqube_lib.sh` is called by `sonarqube_container.sh up` before `compose up -d`, the only image pull in this directory (`sonarqube_run_scan.sh` runs the host scanner and pulls nothing). It exports any non-exported `DOCKER_*` set by a sourced `.env` for the child. It runs the login only when any of `DOCKER_USERNAME`, `DOCKER_PASSWORD`, `DOCKER_TOKEN`, `DOCKER_REGISTRY`, `DOCKER_AUTH_CONFIG`, an explicit `SONAR_REGISTRY_ENV_FILE` or the default env file is present; otherwise it logs `SKIP credentials_absent` and returns 0. Exit 3 from the script (credentials absent, or a valid `DOCKER_AUTH_CONFIG` with helper or identity-token entries only) is a logged SKIP; a malformed `DOCKER_AUTH_CONFIG`, incomplete plain credentials (any of username / password-or-token / registry missing while another is set), a registry with no credential, and an env file that loads but yields no usable login are exit 2; exits 1 or 2 stop `up` with exit 2.

## Exit codes

0 ok, 1 failed, 2 BLIND/config error, 3 SKIP (`credentials_absent`, `probe_image_absent`, `registry_absent`; names variables only).

## Tests

`scripts/sonarqube/tests/test_registry_login.sh` (logic, fake engine), `test_registry_login_wiring.sh` (login before the compose pull in `up`, fail-closed), `test_registry_login_mutation_test.sh` (57 mutants of the script, library and container script must each fail the matching test; sources are cmp-verified unchanged). All are unit-class: the engine is a fake that records argv and stdin.

## Limits

Secrets are never expanded under `bash -x` on the library path: `sq_registry_login_auto` switches tracing off for its body and restores it, and tests set-ness with `${!v+x}`, not the value.

Secrets are never expanded under `bash -x` on the library path (`sq_registry_login_auto` switches tracing off for its body and restores it, and tests set-ness with `${!v+x}`). Not proven live. Credential-helper files are reported, not exercised. The masker is literal-substring: a secret transformed by the engine (encoded) is not masked. No Windows support.
