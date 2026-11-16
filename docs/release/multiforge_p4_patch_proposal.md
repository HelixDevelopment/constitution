# P4 proposal: wire scripts/forge/forge.sh into scripts/release/tag_and_release.sh

| Field | Value |
|---|---|
| Revision | 2 (2026-11-12: exit 5 UNVERIFIED-COMMIT and INTERRUPTED rows added) |
| Created | 2026-11-12 |
| Status | PROPOSAL, NOT APPLIED, NOT TESTED. Written against the fix227 vehicle's `tag_and_release.sh` (vehicle/fix227 round 7, merge commit b13d2c97). Apply only after fix227 lands on `main`, re-base the hunks on the landed text, test-first. |
| Authority | Phase P4 of the multi-forge design; no new anchor. §11.4.288 (lands on `main`), §11.4.224 (test first), §11.4.142 / §11.4.209 (independent review) apply. |

## Goal

One new `--release` spec form, `forge:REMOTE`, that publishes the platform release of the tag on the
forge behind REMOTE through `scripts/forge/forge.sh release-ensure`, for every forge of
`config/forge/hosts.tsv` (GitHub, GitLab, Codeberg, git.m3w.org, GitFlic, GitVerse). The existing
`github:`, `gitlab:` and `gitea:` forms stay unchanged (no silent removal, §11.4.122); retiring them is
a separate operator decision once `forge:` is LIVE-proven on each forge.

## Mapping of forge.sh results

| forge.sh | tag_and_release line | counts as |
|---|---|---|
| exit 0, `ACTION: created` / `updated` | `RELEASE forge:R CREATED` / `UPDATED` | ok |
| exit 0, `ACTION: kept` | `RELEASE forge:R already exists (kept)` | ok |
| exit 3 `credentials_absent:*` | `GAP RELEASE forge:R SKIPPED-NO-TOKEN (<names>)` | gap |
| exit 3 `releases_disabled`, `releases_unsupported_or_empty`, `not_accessible`, `readback_page_cap` | `GAP RELEASE forge:R NOT-RELEASED (<reason>)` | gap (never "released") |
| exit 3 `tag_absent_on_forge` | `FAIL` (the push just read the tag back; absence here is a contradiction) | fail |
| exit 3 any other reason (`credentials_invalid:*`, `unknown_forge`, `tool_missing`, ...) | `FAIL RELEASE forge:R REFUSED (<reason>)` | fail |
| exit 1 (`readback_mismatch`, `present_mismatch`, `tag_sha_mismatch`, ...) | `FAIL RELEASE forge:R <reason>` | fail |
| exit 5 `commit_unverified` (UNVERIFIED-COMMIT) | `GAP RELEASE forge:R COMMIT-UNVERIFIED` (the release exists but nothing ties it to the tagged commit; never "released") | gap |
| exit 129 / 130 / 143 (INTERRUPTED) | `FAIL RELEASE forge:R interrupted` (state unknown: re-run `release-get`) | fail |
| exit 2, 4, or no `RESULT:` line | `FAIL RELEASE forge:R <reason or "no result">` | fail |

Only the `REASON:` and `ACTION:` lines of forge.sh are read (closed vocabularies, no values); its
stderr is discarded like every other network child. `--enable-releases` and
`--try-create-on-ambiguous` are NOT passed by default: the conductor adds them per remote with the
new options `--forge-enable-releases REMOTE` and `--forge-try-ambiguous REMOTE` (each a recorded
decision for that cut).

## Environment

forge.sh finds its token by NAME (environment, then `~/api_keys.sh` mode 0600, then the project
`.env`) and re-executes itself with a clean environment. `rc_env_lockdown` therefore needs to pass
nothing new: forge.sh reads the keys file itself. If the operator keeps tokens only in the
environment, the lockdown must carry the names `config/forge/hosts.tsv` lists for that host to the
forge.sh child only (the pattern `pub()` already uses for `M3W_GITEA_TOKEN`).

## Hunks (sketch against the fix227 text)

```diff
@@ usage header
 #       [--release gitea:REMOTE:BASE_URL:OWNER/REPO]... \
+#       [--release forge:REMOTE]... [--forge-enable-releases REMOTE]... [--forge-try-ambiguous REMOTE]... \
@@ option parsing
     --release) need $# "$1"; RELEASES+=("$2"); shift 2 ;;
+    --forge-enable-releases) need $# "$1"; FORGE_ENABLE+=" $2 "; shift 2 ;;
+    --forge-try-ambiguous) need $# "$1"; FORGE_TRYAMB+=" $2 "; shift 2 ;;
@@ spec validation
-  [[ $spec =~ $RE_GH || $spec =~ $RE_GL || $spec =~ $RE_GT ]] || die_usage "bad --release spec ..."
+  RE_FG="^forge:$SEG\$"
+  [[ $spec =~ $RE_GH || $spec =~ $RE_GL || $spec =~ $RE_GT || $spec =~ $RE_FG ]] || die_usage "bad --release spec ..."
@@ platform releases loop (new case before esac)
+    forge)
+      fargs=(release-ensure --remote "$r" --tag "$TAG" --sha "$SHA" --notes-file "$NOTES" --title "$PRE_TITLE")
+      [ "$PRERELEASE" -eq 1 ] && fargs+=(--prerelease)
+      case "$FORGE_ENABLE" in *" $r "*) fargs+=(--enable-releases) ;; esac
+      case "$FORGE_TRYAMB" in *" $r "*) fargs+=(--try-create-on-ambiguous) ;; esac
+      fout="$(nt bash scripts/forge/forge.sh "${fargs[@]}" 2>/dev/null)"; rc=$?
+      freason="$(printf '%s\n' "$fout" | sed -n 's/^REASON: \([a-z_]*\).*/\1/p' | tail -1)"
+      faction="$(printf '%s\n' "$fout" | sed -n 's/^ACTION: \([a-z-]*\)$/\1/p' | tail -1)"
+      case "$rc:$freason" in
+        0:) case "$faction" in kept) printf 'RELEASE %s already exists (kept)\n' "$spec" ;;
+                               created|updated) printf 'RELEASE %s %s\n' "$spec" "${faction^^}" ;;
+                               *) fail "RELEASE $spec no ACTION line (not counted)" ;; esac ;;
+        3:credentials_absent) gap "RELEASE $spec SKIPPED-NO-TOKEN" ;;
+        3:releases_disabled|3:releases_unsupported_or_empty|3:not_accessible|3:readback_page_cap)
+           gap "RELEASE $spec NOT-RELEASED ($freason)" ;;
+        *) fail "RELEASE $spec rc=$rc reason=${freason:-none}" ;;
+      esac ;;
```

Note: forge.sh's reason for a missing token is `credentials_absent:<NAMES>`; the sed above keeps
`[a-z_]*`, so it compares as `credentials_absent`. `credentials_invalid:<NAME>` falls through to FAIL.

## Tests owed with the patch (test first)

1. `tests/release/test_tag_and_release.sh`: a `forge:` spec against the forge tool's loopback fixture
   (FORGE_HOSTS_FILE pointing at it, `FORGE_TEST_ALLOW_HTTP_LOOPBACK=1`): created, kept, each GAP reason,
   each FAIL reason, and a missing `RESULT:` line; RED before the hunks.
2. A spec naming a remote not in `--remotes` is USAGE (existing rule, extended to `forge:`).
3. Paired mutants: treat `releases_disabled` as created; treat a missing ACTION as OK; drop
   `--prerelease`; each must fail a test.

## Tracker items the lander registers (no ids minted here)

- P4 wiring of `forge:` into `tag_and_release.sh` (this proposal), after fix227 lands.
- LIVE proof of each write path on the first real cut (create + read-back per forge).
- Codeberg: the operator decision to switch the Releases unit on (or `--forge-enable-releases codeberg`).
- GitVerse: investigate the 404 `REPO_NOT_FOUND` of the release API (support ticket or docs), then
  decide whether `--forge-try-ambiguous gitverse` is used.
