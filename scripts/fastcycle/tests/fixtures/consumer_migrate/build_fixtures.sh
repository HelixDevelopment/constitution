#!/bin/sh
# build_fixtures.sh - real local git fixtures for consumers/migrate.sh RED
# testing (T168, plan T-G05; contract consumer-audit-and-migration.md).
# Purpose: build, under $1 (a fresh/empty dir), three real bare-remote +
#   checkout pairs standing in for consumers, per the contract's RED
#   fixtures table: ca_good_migrate, ca_bad_dirty_local,
#   ca_bad_rejecting_remote -- each with a real 'constitution' gitlink
#   entry (pointing at a real, tiny, 2-commit local "mini constitution"
#   history) so migrate.sh's gitlink-bump step has a genuine before/after
#   to operate on, without the cost of a full constitution clone.
# Usage: build_fixtures.sh <target_dir>
# Output: <target_dir>/manifest.json {mini_constitution, old_sha, new_sha,
#   fixtures: {name: {remote, checkout}}}
# Exit: 0 on success; 1 on any git failure (set -e surfaces it).
set -eu

TARGET=${1:?"usage: build_fixtures.sh <target_dir>"}
mkdir -p "$TARGET"

export GIT_AUTHOR_NAME="fastcycle-fixture" GIT_AUTHOR_EMAIL="fixture@example.invalid"
export GIT_COMMITTER_NAME="fastcycle-fixture" GIT_COMMITTER_EMAIL="fixture@example.invalid"
export GIT_CONFIG_NOSYSTEM=1

# --- mini "constitution" bare repo: two real commits, old (what every
# fixture consumer starts pointed at) and new (the migration target).
MINI_CONST_BARE="$TARGET/mini_constitution.git"
rm -rf "$MINI_CONST_BARE"
git init --bare -q -b main "$MINI_CONST_BARE"
MC_WORK=$(mktemp -d)
git init -q -b main "$MC_WORK" >/dev/null
git -C "$MC_WORK" config user.name fastcycle-fixture
git -C "$MC_WORK" config user.email fixture@example.invalid
echo "old constitution state" > "$MC_WORK/CLAUDE.md"
git -C "$MC_WORK" add CLAUDE.md
git -C "$MC_WORK" commit -q -m "old constitution state"
git -C "$MC_WORK" remote add origin "$MINI_CONST_BARE"
git -C "$MC_WORK" push -q origin main
OLD_SHA=$(git -C "$MC_WORK" rev-parse HEAD)
echo "new constitution state (migration target)" >> "$MC_WORK/CLAUDE.md"
git -C "$MC_WORK" add CLAUDE.md
git -C "$MC_WORK" commit -q -m "new constitution state (migration target)"
git -C "$MC_WORK" push -q origin main
NEW_SHA=$(git -C "$MC_WORK" rev-parse HEAD)
rm -rf "$MC_WORK"

build_one() {
    name=$1
    fixdir="$TARGET/$name"
    rm -rf "$fixdir"
    mkdir -p "$fixdir"
    bare="$fixdir/remote.git"
    git init --bare -q -b main "$bare"
    work=$(mktemp -d)
    git init -q -b main "$work" >/dev/null
    git -C "$work" config user.name fastcycle-fixture
    git -C "$work" config user.email fixture@example.invalid
    cat > "$work/CLAUDE.md" <<'EOF'
## INHERITED FROM constitution/CLAUDE.md

Fixture consumer for consumers/migrate.sh RED testing (T168, plan T-G05).
Not a real project; every commit here is synthetic.

## Commit Policy

Commit wrapper: none (plain git permitted)
EOF
    cat > "$work/.gitmodules" <<EOF
[submodule "constitution"]
	path = constitution
	url = $MINI_CONST_BARE
EOF
    git -C "$work" add CLAUDE.md .gitmodules
    git -C "$work" update-index --add --cacheinfo 160000,"$OLD_SHA",constitution
    git -C "$work" commit -q -m "initial consumer state (constitution gitlink=old)"
    git -C "$work" remote add origin "$bare"
    git -C "$work" push -q origin main
    rm -rf "$work"

    git clone -q --no-hardlinks "$bare" "$fixdir/checkout"
    git -C "$fixdir/checkout" config user.name fastcycle-fixture
    git -C "$fixdir/checkout" config user.email fixture@example.invalid
    echo "$bare"
}

build_one ca_good_migrate
build_one ca_bad_dirty_local
echo "uncommitted local edit -- must never be touched by migrate.sh" > "$TARGET/ca_bad_dirty_local/checkout/dirty.txt"

build_one ca_bad_rejecting_remote
cat > "$TARGET/ca_bad_rejecting_remote/remote.git/hooks/pre-receive" <<'EOF'
#!/bin/sh
echo "rejected by fixture pre-receive hook" >&2
exit 1
EOF
chmod +x "$TARGET/ca_bad_rejecting_remote/remote.git/hooks/pre-receive"

python3 - "$TARGET" "$MINI_CONST_BARE" "$OLD_SHA" "$NEW_SHA" <<'PYEOF'
import json, sys
target, mini, old_sha, new_sha = sys.argv[1:5]
manifest = {
    "schema": "consumer-migrate-fixtures/v1",
    "mini_constitution": mini,
    "old_sha": old_sha,
    "new_sha": new_sha,
    "fixtures": {
        n: {"remote": f"{target}/{n}/remote.git", "checkout": f"{target}/{n}/checkout"}
        for n in ("ca_good_migrate", "ca_bad_dirty_local", "ca_bad_rejecting_remote")
    },
}
with open(f"{target}/manifest.json", "w") as fh:
    json.dump(manifest, fh, indent=2, sort_keys=True)
    fh.write("\n")
PYEOF

echo "built fixtures under $TARGET (old_sha=$OLD_SHA new_sha=$NEW_SHA)"
