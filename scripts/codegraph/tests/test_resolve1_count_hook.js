// Counts QueryBuilder.getAllFilePaths calls per thread; appends "<tid> getAllFilePaths=<n> ms=<t>" to $COUNT_OUT on exit.
'use strict';
const Module = require('module'); const orig = Module.prototype.require; let q = 0, ms = 0; let done = false;
const tid = (() => { try { return require('worker_threads').threadId; } catch { return -1; } })();
Module.prototype.require = function (id) { const m = orig.apply(this, arguments);
  if (!done && m && m.QueryBuilder && m.QueryBuilder.prototype && m.QueryBuilder.prototype.getAllFilePaths) { done = true;
    const o = m.QueryBuilder.prototype.getAllFilePaths;
    m.QueryBuilder.prototype.getAllFilePaths = function () { const t = process.hrtime.bigint(); try { return o.apply(this, arguments); } finally { q++; ms += Number(process.hrtime.bigint() - t) / 1e6; } }; }
  return m; };
process.on('exit', () => { if (process.env.COUNT_OUT) require('fs').appendFileSync(process.env.COUNT_OUT, `tid=${tid} getAllFilePaths=${q} ms=${ms.toFixed(1)}\n`); });
