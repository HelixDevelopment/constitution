#!/usr/bin/env bash
# F1 reproduction (CON-456 r5 review): a status writer rewrites a **Status:**
# line inside a fenced code block of the item's description and leaves the
# item's own Status line stale; validate still exits 0.
# Usage: repro_F1_fenced_status.sh <workable-items binary> <new empty dir>
set -u
B="${1:?binary}"; D="${2:?new dir}"
[ -e "$D" ] && { echo "exists $D" >&2; exit 64; }
mkdir -p "$D" && cd "$D" || exit 1
DESC="Reviewer probe description, long enough for the floor of the engine."
"$B" add Task Low --db seed --id CON-990 --title "Rev probe item" --description "$DESC" >/dev/null || exit 1
"$B" sync db-to-md --db seed --out-issues I.md --out-fixed F.md >/dev/null || exit 1
python3 -I - I.md "$DESC" <<'EOF'
import sys
p, d = sys.argv[1], sys.argv[2] + "\n"
s = open(p).read()
s = s.replace(d, d + "\nExample of the status line format:\n\n```\n**Status:** Queued\n```\n", 1)
open(p, "w").write(s)
EOF
"$B" sync md-to-db --db db --issues I.md --fixed F.md >/dev/null || exit 1
sqlite3 db "select body_md from items" > before
"$B" block --db db --id CON-990 --details d --why w --unblock "[A] keep · [B] drop" --who op >/dev/null; echo "block rc=$?"
sqlite3 db "select body_md from items" > after
echo "column status: $(sqlite3 db 'select status from items')"
echo "Status lines in body after:"; grep -n '^\*\*Status:\*\*' after
diff before after
"$B" validate --db db >/dev/null 2>&1; echo "validate rc=$?"
