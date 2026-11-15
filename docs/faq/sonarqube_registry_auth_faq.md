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

The login step reported a configuration error: no usable container engine is installed (also when the env file exists but no engine does), the env file is accessible to group or others, is a symlink or is not yours, an explicitly set `SONAR_REGISTRY_ENV_FILE` does not exist, an option was given without a value, the credentials are set up but incomplete or unusable (e.g. a username without a password, or a misspelled variable name in the env file), or `DOCKER_AUTH_CONFIG` is malformed (not JSON, no `auths`, wrong types, a mistyped entry key, empty, or bad base64). Run `chmod 600` on the env file. The script never uses a loosely protected secret file. An engine that rejects the credentials also stops `up` (the script itself exits 1).

## Why is my username or password rejected with exit 2?

A username or password that is empty, whitespace-only, or contains a TAB, newline, carriage return or other control character is refused (for both plain variables and decoded `DOCKER_AUTH_CONFIG` entries), so a value can never be split into another field or sent to the engine as an option. A space or colon inside a password is fine. A username starting with `-` is passed as `--username=NAME`.

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

## Known limits

- A password containing a newline is cut at the first line when read from an env file or decoded from `DOCKER_AUTH_CONFIG`; such passwords are not supported.
- `verify` pulls the probe image and leaves whatever login state the engine already has (including an `auth.json` written earlier by `--auth-file-only`); it does not clean up.
- The env file is checked and then sourced; between the two a local attacker who owns the directory could swap the file (time-of-check/time-of-use). Keep the directory private (0700).
- `DOCKER_AUTH_CONFIG` that parses and holds only credential helpers or identity tokens is skipped (`SKIP credentials_absent`), not decoded. A malformed one (not JSON, no `auths`, wrong types, mistyped keys, empty, bad base64, `username`/`password` fields) is exit 2, not a skip.
