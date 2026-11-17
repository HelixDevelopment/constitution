#!/bin/bash
# Ground truth: which lock files does real git create for each engine write shape (strace openat O_CREAT|O_EXCL).
set -eu
SB=$(mktemp -d "${TMPDIR:?}/glp.XXXX")
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$SB/gc" GIT_AUTHOR_NAME=p GIT_AUTHOR_EMAIL=p@x.invalid GIT_COMMITTER_NAME=p GIT_COMMITTER_EMAIL=p@x.invalid
printf '[init]\n\tdefaultBranch = main\n[protocol "file"]\n\tallow = always\n' > "$SB/gc"
g(){ git -c core.hooksPath=/dev/null "$@"; }
cd "$SB"; g init -q --bare up.git; g init -q seed; echo 1 > seed/f; g -C seed add f; g -C seed commit -qm 1
g -C seed remote add origin "$SB/up.git"; g -C seed push -q origin main
g clone -q up.git work; echo 2 > seed/f; g -C seed commit -qam 2; g -C seed push -q origin main; g -C work fetch -q origin
T=$(g -C work rev-parse origin/main); B=$(g -C work rev-parse HEAD)
tr(){ local name=$1; shift; strace -f -e trace=%file -o "$SB/$name.st" "$@" >/dev/null 2>&1 || true
  echo "== $name"; grep -oE '"[^"]*\.lock"' "$SB/$name.st" | sort -u | sed "s#$SB/##" || true; }
tr ff git -C work merge --ff-only "$T"
g -C work checkout -q --detach "$B"; tr detach git -C work checkout --quiet --detach "$T"
# add of a gitlink in a parent
g init -q par; g -C par commit -q --allow-empty -m 0; g -C par -c protocol.file.allow=always submodule -q add "$SB/up.git" sub; g -C par commit -qm s
g -C par/sub checkout -q --detach "$B"; tr add git -C par add -- sub
# linked worktree ff
g -C work checkout -q main; g -C work branch -q wtb "$B"; g -C work worktree add -q "$SB/wt" wtb; tr wt_ff git -C "$SB/wt" merge --ff-only "$T"
echo "git: $(git --version)"; echo SANDBOX $SB
