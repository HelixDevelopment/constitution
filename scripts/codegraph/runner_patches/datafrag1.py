"""datafrag1 — record data-fragment / binary files as skip rows instead of parsing them.

Stock v1.6.0 hands three raw number-fragment C headers (comma-separated byte
lists with no enclosing declaration) to tree-sitter, where each burns the
3 x 20 s hard-kill window plus a retry, and parses binary MPEG-TS `.ts` files as
TypeScript (finding F6). The single-file path used by `sync`
(indexFileWithContent) parses on the main thread with no timeout at all.

Rule (S1 measurement, matched exactly the 3 timing-out files across 584,604):
  * DATA FRAGMENT: path ends in .h/.c/.cc/.cpp/.hpp/.inc/.cxx/.hxx, size >=
    200 KiB, and the first character after leading whitespace and C comments
    (within the first 20,000 characters) is a digit  -> data_fragment_skipped
  * BINARY: any selected source file whose decoded content contains a NUL
    character -> binary_content_skipped
Numeric-ratio heuristics were REJECTED (869 false candidates, 866 parse fine).

Matching files are stored exactly like the vendor's `size_exceeded` path: the
file row is present with 0 nodes and one warning-severity error carrying the
code, so the file stays IN the index (constitution §11.4.78) and the vendor's
healZeroNodeRows keeps it (zero nodes WITH errors = deliberate skip marker).
Both extraction paths are patched: the bulk parse loop (index/init) and
indexFileWithContent (sync / single-file re-index).
"""
from .common import NotNeeded, PatchPlan, Refuse

PATCH_ID = "datafrag1"
SUMMARY = "store data-fragment / NUL-binary source files as skip rows (no parse, no timeout)"
EXTRACT = "lib/dist/extraction/index.js"

CONST_ANCHOR = "const MAX_FILE_SIZE = 1024 * 1024;"
BULK_ANCHOR = "                await feed(filePath, content, stats);"
SINGLE_ANCHOR = ("        const result = (0, tree_sitter_1.extractFromSource)"
                 "(relativePath, content, language, frameworkNames);")

HELPER = r'''const MAX_FILE_SIZE = 1024 * 1024;
// helix-datafrag1 (constitution/scripts/codegraph/runner_patches/datafrag1.py)
const __HELIX_DF_EXT = /\.(h|c|cc|cpp|hpp|inc|cxx|hxx)$/;
const __HELIX_DF_MIN_BYTES = 200 * 1024;
const __HELIX_DF_WINDOW = 20000;
function __helixDataFragClassify(filePath, content, size) {
    if (typeof content !== 'string')
        return null;
    if (content.indexOf('\u0000') !== -1)
        return { code: 'binary_content_skipped', message: `File contains NUL bytes; binary content not parsed (${size} bytes)` };
    if (!(size >= __HELIX_DF_MIN_BYTES) || !__HELIX_DF_EXT.test(filePath))
        return null;
    const n = Math.min(content.length, __HELIX_DF_WINDOW);
    let i = 0;
    while (i < n) {
        const ch = content[i];
        if (/\s/.test(ch)) {
            i++;
        }
        else if (content.startsWith('/*', i)) {
            const j = content.indexOf('*/', i + 2);
            if (j < 0 || j >= n)
                return null;
            i = j + 2;
        }
        else if (content.startsWith('//', i)) {
            const j = content.indexOf('\n', i + 2);
            if (j < 0 || j >= n)
                return null;
            i = j + 1;
        }
        else {
            break;
        }
    }
    if (i >= n)
        return null;
    const c = content.charCodeAt(i);
    if (c >= 48 && c <= 57)
        return { code: 'data_fragment_skipped', message: `Raw number data fragment (first significant char is a digit, ${size} bytes); not parsed` };
    return null;
}'''

BULK_NEW = r'''                const __hdf = __helixDataFragClassify(filePath, content, stats.size); // helix-datafrag1
                if (__hdf) {
                    await storeResult(filePath, content, stats, {
                        nodes: [],
                        edges: [],
                        unresolvedReferences: [],
                        errors: [{ message: __hdf.message, filePath, severity: 'warning', code: __hdf.code }],
                        durationMs: 0,
                    });
                    continue;
                }
                await feed(filePath, content, stats);'''

SINGLE_NEW = r'''        const __hdf = __helixDataFragClassify(relativePath, content, stats.size); // helix-datafrag1
        if (__hdf) {
            const skipped = {
                nodes: [],
                edges: [],
                unresolvedReferences: [],
                errors: [{ message: __hdf.message, filePath: relativePath, severity: 'warning', code: __hdf.code }],
                durationMs: 0,
            };
            await this.storeExtractionResult(relativePath, content, language, stats, skipped, (0, cooperative_yield_1.createYielder)());
            return skipped;
        }
        const result = (0, tree_sitter_1.extractFromSource)(relativePath, content, language, frameworkNames);'''


def plan(view):
    text = view.read(EXTRACT)
    if "__helixDataFragClassify" in text:
        raise Refuse("datafrag1: source is ALREADY patched — --src must be the pristine package")
    if "data_fragment_skipped" in text and "binary_content_skipped" in text:
        raise NotNeeded("extraction/index.js already records data_fragment_skipped / binary_content_skipped")
    if "cooperative_yield_1.createYielder" not in text:
        raise Refuse("datafrag1: extraction/index.js no longer references cooperative_yield_1.createYielder")
    p = PatchPlan(PATCH_ID)
    p.replace_once(view, EXTRACT, CONST_ANCHOR, HELPER, "const MAX_FILE_SIZE")
    p.replace_once(view, EXTRACT, BULK_ANCHOR, BULK_NEW, "bulk loop: await feed(...)")
    p.replace_once(view, EXTRACT, SINGLE_ANCHOR, SINGLE_NEW, "indexFileWithContent: extractFromSource(...)")
    p.detail = {"extensions": "h|c|cc|cpp|hpp|inc|cxx|hxx", "min_bytes": 200 * 1024, "window_chars": 20000,
                "codes": ["data_fragment_skipped", "binary_content_skipped"]}
    return p
