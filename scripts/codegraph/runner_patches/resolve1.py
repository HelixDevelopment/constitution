"""resolve1 — memoize the resolution context's file-path list per cache generation.

Stock v1.6.0 `ReferenceResolver.createContext().getAllFiles` (lib/dist/resolution/
index.js) runs `SELECT path FROM files ORDER BY path` + `rows.map` on EVERY call.
Several per-reference paths call it — most importantly the vue framework's
`resolveComponent`, reached for EVERY `calls` ref whose name is PascalCase in ANY
language once vue is detected (a single .vue file anywhere suffices). On a
584,603-file index each call measured ~350 ms, 93.4% of resolve wall time
(measured in a real-repository profile of the resolve phase), i.e. O(#refs x #files).

Fix (one field, three anchors):
  * getAllFiles returns `this.helixAllFilesMemo`, filled on first use with the
    unchanged query result (same ORDER BY path order) and Object.freeze()d, so
    every caller sees ONE stable array (identity-keyed caches hit) and any
    in-place mutation would throw instead of silently corrupting the memo
    (audited 2026-09-24: no stock caller mutates the returned array);
  * the memo is dropped in clearCaches() — the SAME invalidation point stock
    uses for knownFiles/nameCache/the import-resolver memos, i.e. the resolver's
    existing contract that the file set only changes across clearCaches();
  * the memo is ALSO dropped at the top of initialize(), because stock
    initialize() runs detectFrameworks() BEFORE its clearCaches() call and
    detect() reads getAllFiles() — without this, a re-initialize after new files
    were indexed could detect frameworks against a stale list.

Honest boundary: between two clearCaches() calls the list is a snapshot. Stock
re-queried; every stock code path that changes the files table (index, sync,
removal) reaches clearCaches()/initialize() before resolving (index.js:514-517,
769-779 in 1.6.0), and the resolver never writes the files table itself.
"""
from .common import PatchPlan, Refuse

PATCH_ID = "resolve1"
SUMMARY = "memoize resolution-context getAllFiles per cache generation (no O(#files) query per ref)"
RES = "lib/dist/resolution/index.js"
MARK = "helixAllFilesMemo"

GAF_ANCHOR = """            getAllFiles: () => {
                return this.queries.getAllFilePaths();
            },"""
GAF_NEW = """            getAllFiles: () => {
                // helix-resolve1 (constitution/scripts/codegraph/runner_patches/resolve1.py):
                // one frozen, ORDER BY path snapshot per cache generation.
                if (this.helixAllFilesMemo == null) {
                    this.helixAllFilesMemo = Object.freeze(this.queries.getAllFilePaths());
                }
                return this.helixAllFilesMemo;
            },"""
CLEAR_ANCHOR = """        this.knownFiles = null;
        this.cachesWarmed = false;"""
CLEAR_NEW = """        this.knownFiles = null;
        this.helixAllFilesMemo = null; // helix-resolve1
        this.cachesWarmed = false;"""
INIT_ANCHOR = """    initialize() {
        this.frameworks = (0, frameworks_1.detectFrameworks)(this.context);"""
INIT_NEW = """    initialize() {
        this.helixAllFilesMemo = null; // helix-resolve1: detect() must see the current file set
        this.frameworks = (0, frameworks_1.detectFrameworks)(this.context);"""


# --- vue.js resolveComponent: derive the .vue subset ONCE per file-list identity ----------
# Even with a memoized list, stock resolveComponent() walks EVERY file (endsWith('.vue'))
# for EVERY PascalCase `calls` ref of ANY language once vue is detected: O(#refs x #files).
# The list is now identity-stable per generation, so a WeakMap keyed on it caches the
# subset; a new array (new generation, or an un-memoized list) simply re-derives it, so
# the cache can never serve a stale subset. `filter` preserves list order, hence `matches`
# (and every downstream tie-break) is element-for-element what stock computed.
VUE = "lib/dist/resolution/frameworks/vue.js"
VUE_MARK = "helixVueSubsetCache"
VUE_FN_ANCHOR = """/**
 * Resolve a Vue component reference to its .vue file
 */
function resolveComponent(name, fromFile, context) {"""
VUE_FN_NEW = """// helix-resolve1 (constitution/scripts/codegraph/runner_patches/resolve1.py): the .vue subset
// of the (identity-stable, per-generation) file list, derived once, list order preserved.
const helixVueSubsetCache = new WeakMap();
function helixVueFiles(all) {
    let sub = helixVueSubsetCache.get(all);
    if (sub === undefined) {
        sub = all.filter((f) => f.endsWith('.vue'));
        helixVueSubsetCache.set(all, sub);
    }
    return sub;
}
/**
 * Resolve a Vue component reference to its .vue file
 */
function resolveComponent(name, fromFile, context) {"""
VUE_LOOP_ANCHOR = """    for (const file of context.getAllFiles()) {
        if (!file.endsWith('.vue'))
            continue;
        const fileName = file.split(/[/\\\\]/).pop() || '';
        if (fileName.replace(/\\.vue$/, '') === name)
            matches.push(file);
    }"""
VUE_LOOP_NEW = """    for (const file of helixVueFiles(context.getAllFiles())) { // helix-resolve1
        const fileName = file.split(/[/\\\\]/).pop() || '';
        if (fileName.replace(/\\.vue$/, '') === name)
            matches.push(file);
    }"""


def plan(view):
    text = view.read(RES)
    if MARK in text or VUE_MARK in view.read(VUE):
        raise Refuse("resolve1: source is ALREADY patched — --src must be the pristine package")
    p = PatchPlan(PATCH_ID)
    p.replace_once(view, RES, GAF_ANCHOR, GAF_NEW, "createContext getAllFiles -> getAllFilePaths()")
    p.replace_once(view, RES, CLEAR_ANCHOR, CLEAR_NEW, "clearCaches knownFiles/cachesWarmed reset")
    p.replace_once(view, RES, INIT_ANCHOR, INIT_NEW, "initialize() detectFrameworks entry")
    p.replace_once(view, VUE, VUE_FN_ANCHOR, VUE_FN_NEW, "vue resolveComponent: .vue subset helper")
    p.replace_once(view, VUE, VUE_LOOP_ANCHOR, VUE_LOOP_NEW, "vue resolveComponent: iterate cached subset")
    p.detail = {"memo_field": MARK, "invalidated_in": ["clearCaches()", "initialize() entry"],
                "order_preserved": "SELECT path FROM files ORDER BY path (unchanged query)",
                "frozen": True,
                "vue_subset": "WeakMap keyed on the frozen file-list array (order preserved)"}
    return p
