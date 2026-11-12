# SonarQube registry authentication - User Guide

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-12 |
| Last modified | 2026-11-12T12:00:00Z |
| Status | active |
| Status summary | How to give a Sonar scan non-interactive Docker or Podman registry login with no secret in the repository. |
| Authority | Tool documentation for `scripts/sonarqube/registry_login.sh`; extends §11.4.184 (clause (J)); no new anchor and no new CM-* token. §11.4.10 (credentials), §11.4.161 (rootless), §11.4.18 (script documentation) and §11.4.289 (evidence class) govern. |
| Scope | Universal (§11.4.17): any project that runs SonarQube scans which pull private container images. |
| Issues | none |
| Generated twins | .html / .pdf / .docx not regenerated for this revision (honestly stale, §11.4.106(E)). |

## What it is for

A SonarQube scan that pulls container images from a private registry fails with `unauthorized` unless the engine is logged in first. `registry_login.sh` does that login non-interactively, for Podman (preferred, rootless per §11.4.161) or Docker. The only place the shared tooling pulls images is `sonarqube_container.sh up` (the compose stack); it calls the login automatically right before the pull. `sonarqube_run_scan.sh` runs the host `sonar-scanner` and pulls nothing, so it does not log in. Any other pull site of yours (a scanner image, a CI step) must call `registry_login.sh login` itself first. Nothing about your project is built into the constitution: registry host, user and secret are your data.

## Quick start (out of the box)

1. Create the env file, mode 0600, outside the repository:
   `mkdir -p ~/.config/helix && install -m 600 /dev/null ~/.config/helix/sonar_registry.env`
2. Put these lines in it (values from your secret store; a pull-only, short-lived token is best):
   `DOCKER_REGISTRY=registry.example.com`, `DOCKER_USERNAME=ci-reader`, `DOCKER_PASSWORD=...` (or `DOCKER_TOKEN=...`)
3. Start the server as usual: `bash scripts/sonarqube/sonarqube_container.sh up`. Login happens first, then the compose pull. Then scan with `sonarqube_run_scan.sh` as before.

No env file and no `DOCKER_*` variables: `up` prints `SKIP credentials_absent` and continues (a stack that needs no private image is unaffected). `SONAR_REGISTRY_LOGIN=off` disables the step. A different env-file location: `SONAR_REGISTRY_ENV_FILE=/path`; if you set it and the file does not exist that is a configuration error (exit 2), not a SKIP. A login that the engine rejects, or a config error, stops `up` with exit 2 before any pull.

## Modes

| Mode | Use |
|---|---|
| `login` | Log in from the environment or `--env-file F`. |
| `login` with `DOCKER_AUTH_CONFIG` | The usual `{"auths":{host:{"auth":base64(user:pass)}}}` JSON, used when no username/password is given: each entry is decoded inside the script and logged in through the engine with `--password-stdin`. Credential-helper or identity-token JSON is refused (exit 2), not faked. |
| `login --auth-file-only` | Podman only: write the auths JSON built from the username/password to a private 0600 file; says plainly it is not verified; export `REGISTRY_AUTH_FILE` from `auth-file-path` and run `verify`. Refused for Docker (exit 2). |
| `discover` | Report which auth files exist (`REGISTRY_AUTH_FILE`, `$XDG_RUNTIME_DIR/containers/auth.json`, `~/.config/containers/auth.json`, `~/.docker/config.json`) and whether a credential helper is configured. Presence only. |
| `verify --probe-image IMG` | Pull a private image to prove the stored auth works. |
| `logout` | `engine logout` for `DOCKER_REGISTRY` / `--registry`. |

Exit codes: 0 ok, 1 engine rejected, 2 config error (no engine, bad option, env file readable by group or others), 3 SKIP.

## Security rules (operator checklist)

- Never put the registry password or token in `~/api_keys.sh`, in the repository, in logs, or in a command line. Use a secret store or the 0600 env file.
- The password goes to the engine through `--password-stdin` only. The env file is refused if group or others have any access (mode must be 0600 or 0400, owned by you, not a symlink). Tracing is forced off while the file is sourced, so a `set -x` inside it cannot leak.
- No secret is printed; engine output is masked. `set +x` is enforced inside the script.
- When a credential helper (`credsStore`/`credHelpers`) is configured the file holds no secret; `discover` says so and the engine calls the helper. The script does not parse it.
- `discover` can only reuse credentials that already exist; it cannot create them.
- Login must precede the first pull; `sonarqube_container.sh up` runs it before the compose pull. Use pull-only, short-lived tokens, and run `logout` after a one-off scan on a shared host.
- Verify with `verify --probe-image <private image>` before relying on it.

## Honest limits

The shipped tests use a fake engine (unit-class, §11.4.289(C)(2)). They prove the script's decisions, not that your registry accepts the login. A live check with real credentials is yours to run (`verify`).
