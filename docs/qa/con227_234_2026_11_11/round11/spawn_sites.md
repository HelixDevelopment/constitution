# Spawn-site inventory, round 11 (R10-1): every command position of the release scripts, by class

Generated from the census scanner (`tests/release/channel_census.py`, function `scan`) and the `env` column of
`tests/release/channels.tsv`, over `scripts/release/tag_and_release.sh`, `scripts/release/derive_release_facts.sh`,
`scripts/release_publish_gitea.sh` and `scripts/release/redact_cut.sh`. Regenerate with `make_spawn_sites.py` beside
this file (run from the repository root). The gate that keeps this true is `channel_census.py netgate` (part 2b of
`tests/release/test_channel_census.sh`); the table is a record, the gate is the check.

Classes:
- **network, through rc_net**: a network command (closed set `NETCMDS` of the netgate: git, ssh, curl, gh, glab,
  timeout and the other network tools), or the badge computer, started as `rc_net CMD` or through `nt` / `net`
  (their one-line definitions call `rc_net`). The child gets the network allow-list `_RC_NET_KEEP` and the constants
  only (`env` = `net-allowlist`).
- **local child**: a command of the closed local set `LOCAL_OK`; it gets the lockdown allow-list and the
  `RELEASE_ENV_KEEP` extras (`env` = `allowlist`; `allowlist+token` is the publisher, a bash script that reads the
  token on stdin and starts its own network children through `rc_net`).
- **re-execution (exec -c)**: `rc_env_clean`'s `exec -c -a MARK "$BASH" "$0" "$@"` (empty environment).

Totals: 128 sites; 52 through rc_net (51 network commands, the netgate's `network_through_rc_net=51`, and the badge
computer); 75 local children; 1 re-execution.

| Script | Class | Command | Reached via | Environment (channels.tsv) | Sites |
|---|---|---|---|---|---|
| derive_release_facts.sh | network, through rc_net | `git` | `rc_net` | `net-allowlist` | 12 |
| derive_release_facts.sh | local child | `awk` | `-` | `allowlist` | 3 |
| derive_release_facts.sh | local child | `cat` | `-` | `allowlist` | 1 |
| derive_release_facts.sh | local child | `chmod` | `-` | `allowlist` | 1 |
| derive_release_facts.sh | local child | `cut` | `-` | `allowlist` | 2 |
| derive_release_facts.sh | local child | `date` | `-` | `allowlist` | 1 |
| derive_release_facts.sh | local child | `grep` | `-` | `allowlist` | 7 |
| derive_release_facts.sh | local child | `mktemp` | `-` | `allowlist` | 1 |
| derive_release_facts.sh | local child | `rmdir` | `-` | `allowlist` | 1 |
| derive_release_facts.sh | local child | `sed` | `-` | `allowlist` | 7 |
| derive_release_facts.sh | local child | `sha256sum` | `-` | `allowlist` | 1 |
| derive_release_facts.sh | local child | `sort` | `-` | `allowlist` | 4 |
| derive_release_facts.sh | local child | `sqlite3` | `-` | `allowlist` | 2 |
| derive_release_facts.sh | local child | `tr` | `-` | `allowlist` | 5 |
| derive_release_facts.sh | local child | `unlink` | `-` | `allowlist` | 1 |
| derive_release_facts.sh | local child | `wc` | `-` | `allowlist` | 1 |
| redact_cut.sh | local child | `awk` | `-` | `allowlist` | 2 |
| redact_cut.sh | re-execution (exec -c) | `bash` | `exec` | `empty` | 1 |
| redact_cut.sh | local child | `tr` | `-` | `allowlist` | 2 |
| release_publish_gitea.sh | network, through rc_net | `curl` | `rc_net` | `net-allowlist` | 1 |
| release_publish_gitea.sh | network, through rc_net | `git` | `rc_net` | `net-allowlist` | 2 |
| release_publish_gitea.sh | local child | `awk` | `-` | `allowlist` | 1 |
| release_publish_gitea.sh | local child | `cat` | `-` | `allowlist` | 2 |
| release_publish_gitea.sh | local child | `chmod` | `-` | `allowlist` | 1 |
| release_publish_gitea.sh | local child | `cp` | `-` | `allowlist` | 1 |
| release_publish_gitea.sh | local child | `grep` | `-` | `allowlist` | 2 |
| release_publish_gitea.sh | local child | `jq` | `-` | `allowlist` | 4 |
| release_publish_gitea.sh | local child | `mktemp` | `-` | `allowlist` | 1 |
| release_publish_gitea.sh | local child | `rm` | `-` | `allowlist` | 1 |
| release_publish_gitea.sh | local child | `rmdir` | `-` | `allowlist` | 1 |
| release_publish_gitea.sh | local child | `sed` | `-` | `allowlist` | 1 |
| release_publish_gitea.sh | local child | `wc` | `-` | `allowlist` | 1 |
| tag_and_release.sh | network, through rc_net | `bash` | `rc_net` | `net-allowlist` | 1 |
| tag_and_release.sh | network, through rc_net | `gh` | `nt` | `net-allowlist` | 5 |
| tag_and_release.sh | network, through rc_net | `git` | `nt` | `net-allowlist` | 1 |
| tag_and_release.sh | network, through rc_net | `git` | `rc_net` | `net-allowlist` | 19 |
| tag_and_release.sh | network, through rc_net | `git` | `net` | `net-allowlist` | 6 |
| tag_and_release.sh | network, through rc_net | `glab` | `nt` | `net-allowlist` | 4 |
| tag_and_release.sh | network, through rc_net | `timeout` | `rc_net` | `net-allowlist` | 1 |
| tag_and_release.sh | local child | `awk` | `-` | `allowlist` | 7 |
| tag_and_release.sh | local child | `bash` | `-` | `allowlist+token` | 1 |
| tag_and_release.sh | local child | `chmod` | `-` | `allowlist` | 1 |
| tag_and_release.sh | local child | `cut` | `-` | `allowlist` | 1 |
| tag_and_release.sh | local child | `date` | `-` | `allowlist` | 2 |
| tag_and_release.sh | local child | `grep` | `-` | `allowlist` | 2 |
| tag_and_release.sh | local child | `mktemp` | `-` | `allowlist` | 1 |
| tag_and_release.sh | local child | `rm` | `-` | `allowlist` | 1 |
| tag_and_release.sh | local child | `rmdir` | `-` | `allowlist` | 1 |
