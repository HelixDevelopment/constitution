#!/usr/bin/env bash
# lumen_verify.sh — golden-query verification of a real Lumen semantic-search index.
#
# Purpose: run every golden natural-language query through the REAL `lumen search`
#   CLI (same index, model and freshness path the MCP tool uses) and assert that
#   each expected (gold) file appears in the top-k DISTINCT files. Queries whose
#   gold file has an extension Lumen cannot index (type "unsupported") must NOT
#   be found — they prove the documented capability gap instead of hiding it.
# Usage: lumen_verify.sh --golden <file.json> --project <root> [--k 5] [--n 20]
#          [--lumen <bin>] [--out <dir>] [--scope-key in_tierA]
#          [--min-recall 0.85] [--baseline <known_misses.json>] [--no-update-baseline]
# Inputs: golden JSON = list of {id, type(conceptual|structural|unsupported), q,
#   gold:[rel paths; a trailing "/" means any file under that dir], optional
#   <scope-key>: false => query is out of the index scope and is SKIPPED}.
#   Environment (XDG_DATA_HOME, OLLAMA_HOST, LUMEN_*) is passed through unchanged,
#   so the index/embedder used is exactly the caller's.
# Threshold policy (DATA, not code): recall = PASS/(PASS+FAIL) over in-scope
#   indexable queries. Verdict PASS iff recall >= --min-recall AND every FAIL is a
#   KNOWN miss listed in the baseline ({"known_misses":{id:{reason,observed_rank}}}).
#   A FAIL not in the baseline is a NEW_MISS. A known miss that now passes is
#   removed from the baseline file (monotone ratchet: the tool only ever shrinks
#   it; adding a miss is a deliberate human edit); --no-update-baseline only
#   reports TIGHTEN. 'unsupported' queries are never eligible as known misses.
# Outputs: <out>/results.tsv (id, verdict, rank, gold, top-k) sorted by id, no
#   timestamps (deterministic); <out>/summary.txt. Exit 0 = all PASS, 1 = at least
#   one FAIL, 2 = usage error or any search that errored / returned nothing
#   (an empty result is "could not look", never "absent" — §11.4.273).
# Side-effects: `lumen search` runs EnsureFresh, i.e. it incrementally re-indexes
#   changed files of <project> into the index selected by XDG_DATA_HOME. Point
#   XDG_DATA_HOME at a copy if the shared index must not be touched.
# Dependencies: bash, python3, the lumen binary (default: newest plugin cache copy).
set -u
GOLDEN= PROJECT= K=5 N=20 OUT= SCOPE_KEY=in_tierA MINREC=0.85 BASELINE= UPDATE=1
LUMEN=$(ls -1d "$HOME"/.claude*/plugins/cache/claude-plugins-official/lumen/*/bin/lumen-linux-amd64 2>/dev/null | sort -V | tail -1)
while [ $# -gt 0 ]; do
  case "$1" in
    --golden) GOLDEN=$2; shift 2 ;; --project) PROJECT=$2; shift 2 ;;
    --k) K=$2; shift 2 ;; --n) N=$2; shift 2 ;; --lumen) LUMEN=$2; shift 2 ;;
    --out) OUT=$2; shift 2 ;; --scope-key) SCOPE_KEY=$2; shift 2 ;;
    --min-recall) MINREC=$2; shift 2 ;; --baseline) BASELINE=$2; shift 2 ;;
    --no-update-baseline) UPDATE=0; shift ;;
    -h|--help) sed -n '2,32p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -f "$GOLDEN" ] && [ -d "$PROJECT" ] && [ -x "$LUMEN" ] || { echo "usage: need --golden FILE --project DIR and an executable lumen (got '$LUMEN')" >&2; exit 2; }
[ -n "$OUT" ] || OUT=$(mktemp -d)
mkdir -p "$OUT"
[ -z "$BASELINE" ] || [ -f "$BASELINE" ] || { echo "baseline not found: $BASELINE" >&2; exit 2; }
exec python3 - "$GOLDEN" "$PROJECT" "$K" "$N" "$LUMEN" "$OUT" "$SCOPE_KEY" "$MINREC" "$BASELINE" "$UPDATE" <<'PY'
import json, re, subprocess, sys
golden, project, k, n, lumen, out, scope_key, minrec, baseline, update = sys.argv[1:11]
k, n, minrec = int(k), int(n), float(minrec)
known = json.load(open(baseline))['known_misses'] if baseline else {}
fre = re.compile(r'<result:file filename="([^"]+)">')
rows, fails, errors = [], 0, 0
for q in sorted(json.load(open(golden)), key=lambda x: x['id']):
    gold = q['gold']
    if q.get(scope_key) is False and q['type'] != 'unsupported':
        rows.append((q['id'], 'SKIP', '-', ','.join(gold), 'out-of-scope')); continue
    p = subprocess.run([lumen, 'search', '-n', str(n), '--summary', '--min-score', '-1', '-p', project, q['q']],
                       capture_output=True, text=True, cwd=project, timeout=600)
    files = []
    for line in p.stdout.splitlines():
        m = fre.search(line)
        if m and m.group(1) not in files:
            files.append(m.group(1))
    if p.returncode != 0 or not files:
        errors += 1
        rows.append((q['id'], 'ERROR', '-', ','.join(gold), f'rc={p.returncode} results={len(files)} {p.stderr.strip()[:120]}'))
        continue
    hit = lambda f: any(f == g or (g.endswith('/') and f.startswith(g)) for g in gold)
    rank = next((i + 1 for i, f in enumerate(files) if hit(f)), None)
    if q['type'] == 'unsupported':
        verdict = 'PASS' if rank is None else 'FAIL'
    else:
        verdict = 'PASS' if rank is not None and rank <= k else 'FAIL'
    fails += verdict == 'FAIL'
    rows.append((q['id'], verdict, str(rank) if rank else '-', ','.join(gold), ' '.join(files[:k])))
with open(f'{out}/results.tsv', 'w') as fh:
    for r in rows:
        fh.write('\t'.join(r) + '\n')
cnt = {v: sum(1 for r in rows if r[1] == v) for v in ('PASS', 'FAIL', 'SKIP', 'ERROR')}
summ = f"k={k} " + ' '.join(f'{a}={b}' for a, b in cnt.items())
open(f'{out}/summary.txt', 'w').write(summ + '\n')
scored = [r for r, q in zip(rows, sorted(json.load(open(golden)), key=lambda x: x['id'])) if q['type'] != 'unsupported' and r[1] in ('PASS', 'FAIL')]
recall = sum(1 for r in scored if r[1] == 'PASS') / len(scored) if scored else None  # None: no indexable in-scope query -> threshold n/a
types = {q['id']: q['type'] for q in json.load(open(golden))}
new_miss = [r for r in rows if r[1] == 'FAIL' and (r[0] not in known or types[r[0]] == 'unsupported')]
tighten = sorted(i for i in known if any(r[0] == i and r[1] == 'PASS' for r in rows))
summ += f" recall={'n/a' if recall is None else format(recall, '.3f')} min_recall={minrec} known_misses={len(known)} new_misses={len(new_miss)} tighten={len(tighten)}"
open(f'{out}/summary.txt', 'w').write(summ + '\n')
print(summ)
for r in rows:
    if r[1] in ('FAIL', 'ERROR'):
        tag = 'NEW_MISS' if r in new_miss else ('KNOWN_MISS' if r[1] == 'FAIL' else 'ERROR')
        print(tag, '\t'.join(r[:4]), known.get(r[0], {}).get('reason', ''), sep='\t')
for i in tighten:
    print('TIGHTEN', i, 'known miss now passes -> removed from baseline' if update == '1' else 'known miss now passes (read-only; rerun without --no-update-baseline)', sep='\t')
if tighten and update == '1':
    b = json.load(open(baseline))
    for i in tighten:
        del b['known_misses'][i]
    with open(baseline, 'w') as fh:
        json.dump(b, fh, indent=1, sort_keys=True); fh.write('\n')
if errors:
    sys.exit(2)
sys.exit(0 if (recall is None or recall >= minrec) and not new_miss else 1)
PY
