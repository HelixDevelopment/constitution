"""resolve2 — stream (never materialize) the `method` node set in the Swift->ObjC bridge.

Stock v1.6.0 `frameworks/swift-objc.js` buildObjcMap() — reached the first time a
Swift `calls` ref survives to the framework stage — does

    context.getNodesByKind('method').filter((n) => n.language === 'objc')

`context.getNodesByKind` (resolution/index.js createContext) runs
`SELECT * FROM nodes WHERE kind = ?` with `.all()`, maps EVERY row to a node object
and PINS the array in the unbounded per-resolver `nodesByKindCache` for the rest of
the pass. On the ATMOSphere index that is 3,478,494 method nodes (46,158 of them
objc): the single call exhausts the default 4,288 MB V8 heap
(FATAL "Reached heap limit", native frame StatementSync::All) — reproduced on the
real snapshot for refs from rowid 9,970,865 (first pending Swift ref) and matching
the crash of the conductor's bulk resolve run (ATM-1030 S-RESOLVE2 evidence:
probe_method.out, swift_probe.err, sync_bulk_20260924T105017Z.log). Resolver pool
workers each own a resolver, so every worker that meets a Swift ref dies the same way.

Fix (one anchor): iterate `context.iterateNodesByKind('method')` — the SAME SQL text
(`SELECT * FROM nodes WHERE kind = ?`, queries.js iterateNodesByKind), rows mapped
by the same rowToNode, yielded lazily in the same statement order — and keep only
the objc rows. Memory becomes O(#objc methods) instead of O(#methods), and nothing
is pinned in nodesByKindCache. Filter semantics (`language === 'objc'`) and element
order are unchanged, so `candidates[0]` (the chosen target) is unchanged.

Fail-closed: the context MUST expose iterateNodesByKind (asserted on index.js), else
Refuse — never a silent fallback to the materializing path.
"""
from .common import PatchPlan, Refuse

PATCH_ID = "resolve2"
SUMMARY = "swift-objc bridge: stream method nodes (no 3.5M-row getNodesByKind materialization -> heap OOM)"
SOB = "lib/dist/resolution/frameworks/swift-objc.js"
RES = "lib/dist/resolution/index.js"
MARK = "helix-resolve2"
CTX_ITER = "            iterateNodesByKind: (kind) => this.queries.iterateNodesByKind(kind),"

OBJC_ANCHOR = """    const objcMethods = context
        .getNodesByKind('method')
        .filter((n) => n.language === 'objc');"""
OBJC_NEW = """    // helix-resolve2 (constitution/scripts/codegraph/runner_patches/resolve2.py): stream the
    // method rows (same SQL + order as getNodesByKind) and keep only objc; never
    // materialize/pin every method node (3.5M rows -> V8 heap OOM on large repos).
    const objcMethods = [];
    for (const n of context.iterateNodesByKind('method')) {
        if (n.language === 'objc')
            objcMethods.push(n);
    }"""


def plan(view):
    sob = view.read(SOB)
    if MARK in sob:
        raise Refuse("resolve2: source is ALREADY patched — --src must be the pristine package")
    if view.read(RES).count(CTX_ITER) != 1:
        raise Refuse("resolve2: resolution context lacks the expected iterateNodesByKind member "
                     "(index.js shape changed) — re-derive the patch")
    p = PatchPlan(PATCH_ID)
    p.replace_once(view, SOB, OBJC_ANCHOR, OBJC_NEW, "buildObjcMap getNodesByKind('method').filter(objc)")
    p.detail = {"materialized_before": "SELECT * FROM nodes WHERE kind='method' (.all + nodesByKindCache pin)",
                "after": "context.iterateNodesByKind('method') (same SQL, lazy, unpinned) + objc filter",
                "order_preserved": True, "filter_preserved": "n.language === 'objc'"}
    return p
