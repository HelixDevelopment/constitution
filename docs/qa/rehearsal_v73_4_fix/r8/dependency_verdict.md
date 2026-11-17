# Dependency-existence verdicts: markdown-it-py and ICU (CON-PENDINGpvl8 r8, section 11.4.270)

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-11-17 |
| Status | recorded (gate-logic, PROVISIONAL, section 11.4.290) |
| Replaces | nothing; `../r7/dependency_verdict.md` is kept as recorded (its line "refuses every raw HTML block or inline tag other than a complete comment" no longer holds: round 8 refuses comments too) |

## markdown-it-py: unchanged from round 7

The checker still reads the body with markdown-it-py 3.0.0 (`MDIT_TESTED = ("3.0.0",)`).
Round 8 reads it twice:

- with the `commonmark` preset;
- with the same preset plus `table` and `strikethrough` enabled ("gfm").

The active rules of both readings are listed in `census/reader_rules_census.txt`. If the
package is missing, or its version is not tested, the run is BLIND. That behaviour is the same
as in round 7.

Review r7 F7 (reviewer mutant R7M05) found that a check of the version prefix would let 3.0.1
run. `tests/release/pvl_mutate.py` (`api_r7`) now lists 3.0.1 among the versions that must give
BLIND.

## ICU: a build-time dependency only, not a run-time one

**Why ICU is used.** Review r7 F2 and F4 showed that a hand-kept look-alike list and a
format-character filter miss characters a reader shows as `Verification:`. Round 8 does not
keep such a list. It reads characters the way ICU reads them:

- the UTS #39 confusable skeleton;
- NFKD;
- full case folding;
- the `Default_Ignorable_Code_Point` property and the general category.

**The generator.** `scripts/validation/pvl_reading_table.py` builds a reading table from ICU
(section 11.4.77). The checker carries that table as text, with its sha256, so the checker does
not load ICU at run time.

**Verdict on this host: VERIFIED.** Captured on 2026-11-17:

| Check | Result |
|---|---|
| `dpkg -s libicu78` | `Status: install ok installed`, `Version: 78.2-2ubuntu1`, `Source: icu` |
| `ctypes.util.find_library` | `libicuuc.so.78`, `libicui18n.so.78` |
| sha256 of `libicuuc.so.78.2` | `1eb54ce8839e953fbaa755522f3488039d879be3a61b272df3cabd6c00f08d2d` |
| sha256 of `libicui18n.so.78.2` | `14b42ecb935cb21758a24a61052e7b4cd410553e4deae37736cd8c748a1511f4` |
| sha256 of `libicudata.so.78.2` | `3a08c11ef1d168a1edc3b0437cecb8b42e621f67706980a0502c97364bf744a7` |
| `python3 -I scripts/validation/pvl_reading_table.py --check` | `READING-TABLE OK sha256=02a3ad6a0fc3ce69ca645e687d8c6da9d59e48e674dd6119df7d1d04652f47c7 drop_ranges=806 readings=3457 icu=78.2 unicode=17.0` |
| table header (first line of `--print`) | `# pvl reading table: icu 78.2 unicode 17.0; built by scripts/validation/pvl_reading_table.py; do not edit` |

**Proof that the table equals ICU's reading.** Two runs compare the checker's `fold()` (which
reads the embedded table) with the reference `fold()` (which calls ICU live), code point by
code point:

- `tests/release/pvl_inventory.py`, run by the suite (P9), which prints `code_points=1114112`;
- `tools/fold_all.py` (evidence `green/fold_all.txt`), which prints `code_points=1112063`: every
  code point the reference generator yields (surrogates are not among them), minus `&`.

Both report 0 mismatches. `&` is left out of `fold_all.py` because `fold()` decodes character
references first, so a lone `&` is not one code point's reading. Before it counts, `fold_all.py`
changes one reading in its copy of the table (U+13D9) and requires exactly that one mismatch
(`CONTROL changed=U+13D9 mismatches=1`), so its zero is not the zero of a blind comparison.

## What happens elsewhere

| Situation | Behaviour |
|---|---|
| ICU absent on another host | The checker does not need it. Only `--check` and `--write` of the generator, and the test harnesses that call the reference `fold()`, need it. Without ICU they exit 2 (BLIND), never a pass. `tests/release/pvl_blockstate.py` then prints `BLOCKSTATE-BLIND`. |
| Another ICU version | It gives another table, so `--check` fails (exit 1). To move to it: rebuild with `--write`, review the difference, and update `READING_TABLE_SHA256` in the checker. |
| The embedded table edited by hand, truncated or removed | The sha256 differs or the table is missing, so the checker is BLIND: "the reading table is not intact" or "no table". `pvl_mutate.py` `api_r8` tests both, and own mutants O68 and O69 guard them. |

## Not claimed

- **Fonts and renderers.** A font or a rendering engine may draw a character differently from
  Unicode 17.0. That case is out of scope (class inventory S5).
- **Characters with no ASCII skeleton.** Such a character is read as itself. So a label written
  only in non-Latin letters with no ASCII skeleton is not read as `Verification`. Such a label
  does not look like `Verification` either.
- **The pandoc version** (`pandoc 3.11`, a test oracle only) is unchanged from round 7.
