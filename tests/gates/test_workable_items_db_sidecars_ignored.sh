#!/usr/bin/env bash
# tests/gates/test_workable_items_db_sidecars_ignored.sh — ATM-1809 follow-up: the SQLite WAL sidecars of the TRACKED
# workable-items database are gitignored and never tracked.
#
# Anchor 11.4.95: docs/workable_items.db is TRACKED (never gitignored, a deliberate carve-out) and is a WAL-mode database
# (header bytes 18 and 19 are 2; `PRAGMA journal_mode` answers `wal`), so every process that opens it creates
# docs/workable_items.db-shm and docs/workable_items.db-wal beside it, and they stay on disk while a connection is open or
# after a non-clean exit. The same anchor says those two sidecars "ARE gitignored"; the repository's root .gitignore had no
# such entry (only scripts/workable-items/.gitignore has one, and it covers that directory only), so a committer that stages
# the whole worktree (`git add -A`; the history holds 49 commits titled "Auto-commit [<epoch ms>]") committed both on
# 2026-11-06 (844ab543: a 32 KiB -shm and an empty -wal).
#
# Cases (a real git repository per case, no test doubles; the connection is a real sqlite3 connection held open while git runs):
#   S1  control: the database itself is tracked and NOT ignored (anchor 11.4.95 must stay true).
#   S2  both sidecars are ignored by the root .gitignore (evaluated with --no-index: by the rules alone, not by index state).
#   S3  neither sidecar is tracked.
#   S4  the Auto-commit shape: a scratch repository holding this repository's .gitignore and a copy of the database, a sqlite3
#       connection held open (control: both sidecars exist on disk at that moment), `git add -A` run meanwhile: no sidecar is
#       staged, and an unrelated new file IS staged (control: `git add -A` sees what it should).
#   M1  paired mutation: the same S4 run with the two sidecar entries removed from the .gitignore stages both sidecars.
#   M2  paired mutation: S3's predicate reports a sidecar that was force-added to a scratch index.
#
# Usage: tests/gates/test_workable_items_db_sidecars_ignored.sh [<repo root>]   (default: the repository holding this file)
# Exit: 0 all cases hold, 1 a case failed, 2 environment error. Side effects: a private mktemp -d, removed on exit.
set -uo pipefail
here="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
repo="${1:-$(CDPATH='' cd -- "$here/../.." && pwd)}"
DB=docs/workable_items.db; SHM="$DB-shm"; WAL="$DB-wal"
if ! command -v git >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then echo "environment: git and python3 are required" >&2; exit 2; fi
if [ ! -f "$repo/.gitignore" ] || [ ! -f "$repo/$DB" ]; then echo "environment: $repo has no .gitignore or no $DB" >&2; exit 2; fi
sb="$(mktemp -d "${TMPDIR:-/tmp}/wi_sidecars.XXXXXX")" || exit 2
trap 'rm -rf -- "${sb:?}"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
G() { git -c core.hooksPath=/dev/null -c init.defaultBranch=main "$@"; }
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "PASS $1"; }
bad() { fail=$((fail+1)); echo "FAIL $1"; }

tracked_sidecars() { G -C "$1" ls-files -- "$SHM" "$WAL"; }          # $1=repo : prints the tracked sidecars
is_ignored() { G -C "$1" check-ignore -q --no-index -- "$2"; }       # $1=repo $2=path : 0 when the ignore rules cover the path

# staged_by_add_all <gitignore-file> <label> : builds a scratch repo (that .gitignore + the database), opens the database
# (sqlite3, WAL) and keeps the connection open while `git add -A` runs; prints "SIDECARS_ON_DISK=<n>" then the staged names
staged_by_add_all() {
    local d="$sb/add_$2"
    mkdir -p "$d/docs" && cp "$1" "$d/.gitignore" && cp "$repo/$DB" "$d/$DB" || return 1
    G -C "$d" init -q . && G -C "$d" add -A >/dev/null && G -C "$d" commit -q -m base || return 1
    printf 'unrelated\n' > "$d/docs/unrelated_note.md"
    python3 -I - "$d/$DB" "$d" <<'PYEOF' || return 1
import os, sqlite3, subprocess, sys
db, repo = sys.argv[1], sys.argv[2]
con = sqlite3.connect(db)
con.execute("select count(*) from sqlite_master").fetchone()   # a plain read is enough to create the sidecars
print("SIDECARS_ON_DISK=%d" % sum(os.path.exists(db + s) for s in ("-shm", "-wal")))
subprocess.run(["git", "-C", repo, "add", "-A"], check=True)    # the committer's step, with the connection still open
con.close()
PYEOF
    G -C "$d" diff --cached --name-only
}

# S1 control
if G -C "$repo" ls-files --error-unmatch -- "$DB" >/dev/null 2>&1 && ! G -C "$repo" check-ignore -q --no-index -- "$DB"; then
    ok "S1: $DB is tracked and not ignored (anchor 11.4.95 holds)"
else bad "S1: $DB is not tracked, or it is ignored (anchor 11.4.95 broken)"; fi
# S2
if is_ignored "$repo" "$SHM" && is_ignored "$repo" "$WAL"; then ok "S2: $SHM and $WAL are ignored by the root .gitignore"
else bad "S2: a sidecar of the tracked database is not ignored by the root .gitignore"; fi
# S3
t="$(tracked_sidecars "$repo")"
if [ -z "$t" ]; then ok "S3: no sidecar of the tracked database is tracked"
else bad "S3: tracked sidecar(s): $(tr '\n' ' ' <<<"$t")"; fi
# S4
out="$(staged_by_add_all "$repo/.gitignore" real)"
if grep -qx 'SIDECARS_ON_DISK=2' <<<"$out" && grep -qx 'docs/unrelated_note.md' <<<"$out" \
   && ! grep -qx "$SHM" <<<"$out" && ! grep -qx "$WAL" <<<"$out"; then
    ok "S4: with both sidecars on disk and the connection open, 'git add -A' stages the unrelated file and no sidecar"
else bad "S4: 'git add -A' with an open connection staged a sidecar, missed the control file, or the sidecars were not on disk: $(tr '\n' ' ' <<<"$out")"; fi
# M1 : the same run without the two entries must stage both sidecars (the mutation S4 has to be able to see)
grep -v -F -e "$SHM" -e "$WAL" "$repo/.gitignore" > "$sb/gitignore_without"
out="$(staged_by_add_all "$sb/gitignore_without" mutant)"
if grep -qx 'SIDECARS_ON_DISK=2' <<<"$out" && grep -qx "$SHM" <<<"$out" && grep -qx "$WAL" <<<"$out"; then
    ok "M1: mutation (the two entries removed from .gitignore) is caught: both sidecars get staged"
else bad "M1: the mutated .gitignore did not stage both sidecars, so S4 cannot detect a missing entry: $(tr '\n' ' ' <<<"$out")"; fi
# M2 : a force-added sidecar is reported by the predicate S3 uses
mkdir -p "$sb/m2/docs" && printf 'x' > "$sb/m2/$SHM" && G -C "$sb/m2" init -q . && G -C "$sb/m2" add -f -- "$SHM" >/dev/null 2>&1
if [ "$(tracked_sidecars "$sb/m2")" = "$SHM" ]; then ok "M2: mutation (a force-added sidecar) is caught by the S3 predicate"
else bad "M2: the S3 predicate did not report a force-added sidecar"; fi

echo "== $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
