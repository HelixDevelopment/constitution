#!/usr/bin/env bash
# partial_write_planted.sh BIN DB_SRC OUT — derived from the reviewer probe partial_write.sh (CON-456 review): does a Fixed-side
# md-to-db refusal leave the Issues leg already committed? An item whose block the
# operator moved from Issues.md to Fixed.md is then deleted from Issues and never
# inserted into Fixed.
set -u
BIN="${1:?bin}"; SRC="${2:?db}"; OUT="${3:?out}"
mkdir -p "$OUT"; cd "$OUT" || exit 2
cp "$SRC" db.sqlite
log() { printf '%s\n' "$*" >> steps.log; }
: > steps.log
D="Reviewer partial-write probe item, long enough for the description floor."
"$BIN" add Task Low --db db.sqlite --id G77 --title "  leading partial-write probe" --description "$D" >add.out 2>&1; log "add G77 rc=$?"
"$BIN" move --db db.sqlite --id G77 --to Fixed --status Fixed --why "reviewer probe: put a stored-unreadable heading in Fixed" >move.out 2>&1; log "move G77 to Fixed rc=$?"
# Round-2 variant: round 2 trims the title, so plant the unreadable heading by SQL,
# as a database written before round 2 could hold it.
sqlite3 db.sqlite "update items set title='  leading partial-write probe', body_md=replace(body_md,'## G77. leading partial-write probe','## G77.   leading partial-write probe') where atm_id='G77';"
log "planted G77 heading by SQL rc=$?"
log "G77 row: $(sqlite3 db.sqlite "select atm_id||'|'||current_location||'|'||status||'|'||substr(body_md,1,60) from items where atm_id='G77';")"
"$BIN" sync db-to-md --db db.sqlite --out-issues Issues.md --out-fixed Fixed.md >dbtomd.out 2>&1; log "db-to-md rc=$?"
# operator moves the first canonical Issues item block from Issues.md to the end of Fixed.md
X=$(python3 -I - Issues.md Fixed.md <<'PY'
import re, sys
iss, fix = sys.argv[1], sys.argv[2]
s = open(iss, encoding="utf-8").read()
lines = s.splitlines(keepends=True)
start = None
for i, ln in enumerate(lines):
    if re.match(r"^## [A-Z]{3}-[0-9A-Za-z]+ — ", ln):
        start = i; break
end = start + 1
while end < len(lines) and not lines[end].startswith("## "):
    end += 1
block = "".join(lines[start:end])
xid = re.match(r"^## ([A-Z]{3}-[0-9A-Za-z]+) ", lines[start]).group(1)
open(iss, "w", encoding="utf-8").write("".join(lines[:start] + lines[end:]))
f = open(fix, encoding="utf-8").read()
if not f.endswith("\n"):
    f += "\n"
open(fix, "w", encoding="utf-8").write(f + "\n" + block)
print(xid)
PY
)
log "moved block of $X from Issues.md to Fixed.md"
log "before md-to-db: items=$(sqlite3 db.sqlite 'select count(*) from items;') X=$(sqlite3 db.sqlite "select atm_id||'|'||current_location from items where atm_id='$X';")"
"$BIN" sync md-to-db --db db.sqlite --issues Issues.md --fixed Fixed.md >mdtodb.out 2>&1; rc=$?
log "md-to-db rc=$rc"
log "after md-to-db: items=$(sqlite3 db.sqlite 'select count(*) from items;') X=[$(sqlite3 db.sqlite "select atm_id||'|'||current_location from items where atm_id='$X';")] G77=[$(sqlite3 db.sqlite "select atm_id||'|'||current_location from items where atm_id='G77';")]"
log "md-to-db stderr: $(head -c 300 mdtodb.out)"
cat steps.log
