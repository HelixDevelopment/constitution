// test_resolve2_probe.js <dist> <db-copy> <projectRoot> — mechanism probe for runner patch resolve2.
// Opens the DB immutable/read-only, builds the real ReferenceResolver + context, then drives the
// swift-objc-bridge framework resolver for Swift call names that can only resolve cross-language.
// stdout: one JSON object:
//   methodMaterialized  queries.getNodesByKind('method') was called (stock/resolve1: true)
//   methodCached        resolver.nodesByKindCache holds 'method' afterwards
//   targets             name -> "file|name" of the chosen ObjC target (order-sensitive: 3 .m files define each)
'use strict';
const [,, dist, dbPath, root] = process.argv;
const { QueryBuilder } = require(dist + '/db/queries.js');
const { ReferenceResolver } = require(dist + '/resolution/index.js');
const { swiftObjcBridgeResolver } = require(dist + '/resolution/frameworks/swift-objc.js');
const { DatabaseSync } = require('node:sqlite');
const mod = require(dist + '/db/sqlite-adapter.js');
const raw = new DatabaseSync(new URL('file://' + dbPath + '?immutable=1&mode=ro'), { readOnly: true });
const tmp = mod.createDatabase(':memory:', {}); tmp.db._db.close(); tmp.db._db = raw;
const q = new QueryBuilder(tmp.db);
const kinds = [];
const orig = q.getNodesByKind.bind(q);
q.getNodesByKind = (k) => { kinds.push(k); return orig(k); };
const r = new ReferenceResolver(root, q);
r.initialize();
r.warmCaches();
const ctx = r.getResolutionContext();
const targets = {};
for (const name of ['p.play', 'fetch', 'p.send', 'render', 'p.load', 'nosuchthing']) {
  const res = swiftObjcBridgeResolver.resolve({ referenceName: name, language: 'swift', filePath: 'swift/Caller.swift', referenceKind: 'calls' }, ctx);
  const n = res ? q.getNodeById(res.targetNodeId) : null;
  targets[name] = n ? `${n.filePath}|${n.name}|${res.resolvedBy}|${res.confidence}` : null;
}
console.log(JSON.stringify({ methodMaterialized: kinds.includes('method'), methodCached: r.nodesByKindCache.has('method'), kinds, targets }));
