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
| `DOCKER_AUTH_CONFIG` | Any non-empty value: write the auths JSON file instead of calling the engine. |
| `SONAR_REGISTRY_ENV_FILE` | Env file path. Default `${XDG_CONFIG_HOME:-$HOME/.config}/helix/sonar_registry.env`. |
| `SONAR_REGISTRY_ENGINE` | `podman` or `docker`. Default: podman, then docker. |
| `SONAR_REGISTRY_PROBE_IMAGE` | Probe image for `verify`. |
| `SONAR_REGISTRY_LOGIN` | `off` skips the scan-time login. |
| `REGISTRY_AUTH_FILE` | Honoured by the engines; `discover` reports it. |

## Behaviour

- Engine choice: forced engine if set and on PATH, else Podman, else Docker; none on PATH is exit 2.
- Env file: must be a regular file (not a symlink) owned by you with mode 0600 or 0400; sourced in a subshell with auto-export; sourcing failure is exit 2.
- Login: `printf '%s' "$PASS" | <engine> login --username U --password-stdin REG`. Output is passed through a literal masker for the password and `user:password`.
- Auth file: `${XDG_RUNTIME_DIR:-$HOME/.cache}/helix/sonar_registry_auth.json`, directory 0700, file 0600.
- Scan wiring: `sq_registry_login_auto` in `sonarqube_lib.sh` runs only when `DOCKER_USERNAME`, `DOCKER_AUTH_CONFIG` or the env file is present; otherwise it logs `SKIP credentials_absent` and returns 0. Exit 3 from the script is a logged SKIP; exits 1 or 2 stop the scan with exit 2.

## Exit codes

0 ok, 1 failed, 2 BLIND/config error, 3 SKIP (`credentials_absent`, `probe_image_absent`, `registry_absent`; names variables only).

## Tests

`scripts/sonarqube/tests/test_registry_login.sh` (logic, fake engine), `test_registry_login_wiring.sh` (scan order and fail-closed), `test_registry_login_mutation_test.sh` (mutants must fail the logic test). All are unit-class: the engine is a fake that records argv and stdin.

## Limits

Not proven live. Credential-helper files are reported, not exercised. The masker is literal-substring: a secret transformed by the engine (encoded) is not masked. No Windows support.
