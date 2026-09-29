#!/usr/bin/env python3
"""Canonical sorted dump of resolution results. usage: dump.py <db> <outprefix>"""
import hashlib, sqlite3, sys
db, out = sys.argv[1], sys.argv[2]
c = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
edges = c.execute("""SELECT e.source, e.target, e.kind, IFNULL(e.line,''), IFNULL(e.col,''), IFNULL(e.provenance,''), IFNULL(e.metadata,''),
  s.file_path, s.kind, s.name, s.start_line, t.file_path, t.kind, t.name, t.start_line
  FROM edges e JOIN nodes s ON s.id=e.source JOIN nodes t ON t.id=e.target""").fetchall()
refs = c.execute("""SELECT from_node_id, reference_name, reference_kind, line, col, IFNULL(candidates,''), file_path, language, status, name_tail
  FROM unresolved_refs""").fetchall()
nodes = c.execute("SELECT count(*) FROM nodes").fetchone()[0]
res = {}
for name, rows in (("edges", edges), ("refs", refs)):
    lines = sorted("\t".join(str(x) for x in r) for r in rows)
    blob = ("\n".join(lines) + "\n").encode()
    open(f"{out}.{name}.tsv", "wb").write(blob)
    res[name] = (len(lines), hashlib.sha256(blob).hexdigest())
st = c.execute("SELECT status, count(*) FROM unresolved_refs GROUP BY status").fetchall()
print(f"nodes={nodes} edges={res['edges'][0]} edges_sha={res['edges'][1][:16]} refs={res['refs'][0]} refs_sha={res['refs'][1][:16]} status={st}")
