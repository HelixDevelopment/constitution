# SonarQube registry authentication - FAQ

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-12 |
| Last modified | 2026-11-12T12:00:00Z |
| Status | active |
| Status summary | Short answers about registry login for Sonar scans. |
| Authority | Tool documentation for `scripts/sonarqube/registry_login.sh`; extends §11.4.184 (clause (J)); no new anchor and no new CM-* token. §11.4.10 (credentials), §11.4.161 (rootless), §11.4.18 (script documentation) and §11.4.289 (evidence class) govern. |
| Scope | Universal (§11.4.17): any project that runs SonarQube scans which pull private container images. |
| Issues | none |
| Generated twins | .html / .pdf / .docx not regenerated for this revision (honestly stale, §11.4.106(E)). |

## Do I have to do anything for it to work?

Only supply your registry data once (env file or `DOCKER_*` variables). `sonarqube_container.sh up` logs in by itself before it pulls images. With nothing supplied it skips with a logged reason.

## Why Podman first?

Rootless policy (§11.4.161). Docker is used only when Podman is not on PATH, or when you set `SONAR_REGISTRY_ENGINE=docker`.

## Why did `up` stop with exit 2 before pulling?

The login step reported a configuration error: no usable container engine is installed (also when the env file exists but no engine does), the env file is accessible to group or others, is a symlink or is not yours, an explicitly set `SONAR_REGISTRY_ENV_FILE` does not exist, an option was given without a value, or `DOCKER_AUTH_CONFIG` is not an auths JSON with `auth` entries. Run `chmod 600` on the env file. The script never uses a loosely protected secret file. An engine that rejects the credentials also stops `up` (the script itself exits 1).

## Can I keep the password in `~/api_keys.sh`?

No. Use a secret store or the 0600 env file. Never hardcode it in the repository, a log or a command line.

## I use a credential helper. Does it work?

The engine calls the helper itself. `discover` reports that a helper is configured and does not read it.

## Does discover find my password?

No. It only reports whether an auth file exists. It cannot invent credentials.

## How do I know it works?

`registry_login.sh verify --probe-image <private-image>` pulls a private image. Without a probe image it says `SKIP probe_image_absent` and verifies nothing.

## Is it tested against a real registry?

No. The tests use a fake engine. Treat live behaviour as unconfirmed until you run `verify` with your credentials.

## Should I log out afterwards?

On shared hosts, yes: `registry_login.sh logout`. Prefer pull-only, short-lived tokens.
