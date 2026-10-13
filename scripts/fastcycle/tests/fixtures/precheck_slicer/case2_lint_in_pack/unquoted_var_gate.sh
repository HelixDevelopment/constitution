#!/bin/sh
# T061 case-2 fixture: a genuine, planted shellcheck SC2086 issue (an
# expanded variable used unquoted where word-splitting/globbing can alter
# its value). This is deliberately real, not a description of one --
# `shellcheck` against this exact file must report SC2086 for real
# (confirmed by this RED test's own Section B before any claim is made
# about the absent precheck_pack.sh), matching the SAME classifier signal
# source T018's review_record fixtures already use for "mechanical"
# findings (rule: "SC2086").
STAGE_DIR="/tmp/t061 case2 stage"
mkdir -p "$STAGE_DIR"
echo "hello" > "$STAGE_DIR/file.txt"
cat $STAGE_DIR/file.txt
