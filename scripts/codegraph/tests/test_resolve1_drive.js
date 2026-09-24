// usage: node drive.js <distDir> <projectRoot>   (fresh init+indexAll via the library; no CLI side effects)
'use strict';
const [,, dist, root] = process.argv;
const CodeGraph = require(dist + '/index.js').default || require(dist + '/index.js').CodeGraph;
(async () => {
  const t0 = Date.now(); let tRes = null, tEnd = null, total = 0;
  const cg = await CodeGraph.init(root);
  await cg.indexAll({ onProgress: (p) => {
    if (p.phase === 'resolving') { if (tRes === null) tRes = Date.now(); total = p.total; }
    else if (tRes !== null && tEnd === null) tEnd = Date.now();
  } });
  if (tEnd === null) tEnd = Date.now();
  const st = cg.getStats ? cg.getStats() : {};
  console.log(JSON.stringify({ totalMs: Date.now() - t0, resolveMs: tRes ? tEnd - tRes : null, refsAtResolveStart: total,
    frameworks: cg.getDetectedFrameworks(), state: cg.getIndexState ? cg.getIndexState() : null, stats: st }));
  cg.close();
})().catch((e) => { console.error('DRIVE-ERROR', e && e.stack || e); process.exit(3); });
