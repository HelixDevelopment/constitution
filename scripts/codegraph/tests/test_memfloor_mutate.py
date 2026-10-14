#!/usr/bin/env python3
# ============================================================================
# test_memfloor_mutate.py — mutant table for the consumer-data MemAvailable floor (resolve_mem_floor / preflight)
# ============================================================================
# Purpose      Single-edit (or, where noted, coordinated multi-edit) mutants of codegraph_safe.sh, each of which MUST turn the
#              named unit case(s) of test_unit_safe.sh (U47-U63) RED (paired §1.1 mutation: a test that cannot fail is
#              decoration). MF* = author mutants; R01-R15 = the independent reviewer's mutants (WF26 review of 2026-10-08)
#              re-expressed against the round-2 code (same semantic edit; anchors re-mapped because resolve_mem_floor was
#              rewritten); R16-R24 = round-2 additions for the S1-S10 classes; R26-R29 = the round-2 re-review's surviving mutants V02/V04/V15/V16 (T-A..T-C); R30-R35 = round-2.1 review WF31 (S-1 symlink size, db_bytes symlink, T-1 echo sanitiser on an existing file, T-2 TAB indentation, T-3 64 KiB boundary). NC = NEGATIVE CONTROL: an identity edit that
#              MUST leave every case green (proves the harness can tell a surviving edit from a killed one).
# Usage        test_memfloor_mutate.py --list                  (id<TAB>red-cases<TAB>what)
#              test_memfloor_mutate.py --apply <id> <copy-dir> (edits the copy in place)
# Inputs       a COPY of the codegraph tooling dir (never the real tree)
# Outputs      exit 0 applied (every anchor found EXACTLY once) / 1 anchor missing or ambiguous / 2 usage
# Side effects edits files under <copy-dir> only
# Dependencies python3 (stdlib)
# Cross-refs   test_unit_safe.sh U47-U63, ../codegraph_safe.sh, test_memfloor_mutations.sh
# ============================================================================
import os
import sys

SAFE = "codegraph_safe.sh"

# id, [(anchor, replacement), ...] (each anchor must occur exactly once), RED cases ("NONE" = must stay green), description
M = [
    ("MF1", [('if [ "${CG_SAFE_MIN_MEM_AVAIL_KB+x}" = x ]; then', 'if false; then')], "U50,U51,U52", "env knob ignored"),
    ("MF2", [('FLOOR_KB=$((10#$gib * 1048576));', 'FLOOR_KB=$((10#$gib * 1048576 / 2));')], "U49,U53", "limits-file GiB converted with the wrong factor"),
    ("MF3", [('if [ "$FLOOR_KB" -lt "$FLOOR_LOWER_KB" ]; then', 'if false; then')], "U54", "lower-bound check removed"),
    ("MF4", [('FLOOR_LOWER_KB=$((2 * HEAP_FLOOR_MB * 1024))', 'FLOOR_LOWER_KB=$((4 * 1048576))')], "U54", "lower bound back to 4 GiB (S3 heap invariant lost)"),
    ("MF5", [('[ -f "$lf" ] || { FLOOR_BAD="limits file is not a regular file', '[ -e "$lf" ] || { FLOOR_BAD="limits file is not a regular file')], "U56", "regular-file check weakened to exists (dir/devnull/FIFO)"),
    ("MF6", [('echo "min_mem_avail_kb=$FLOOR_KB"', 'echo "min_mem_avail_kb=$FLOOR_DEFAULT_KB"')], "U49,U50", "echoed floor stuck at the default"),
    ("MF7", [('if [ "$mem" -lt "$FLOOR_KB" ]; then', 'if false; then')], "U47,U49,U50", "memory floor not enforced"),
    ("MF8", [('    if [ -n "$lf" ]; then\n        [ -f "$lf" ]', '    if false; then\n        [ -f "$lf" ]')], "U49,U55,U56", "limits file never consulted"),
    ("R01", [('echo "PREFLIGHT FAIL memory-floor: refusing — $FLOOR_BAD"; ok=1', 'echo "PREFLIGHT FAIL memory-floor: refusing — $FLOOR_BAD"')], "U52", "refusal printed but not enforced (ok=1 dropped)"),
    ("R02", [('(floor: $FLOOR_SRC)"; fi\n            ok=1', '(floor: $FLOOR_SRC)"; fi\n            :')], "U47,U49", "memory FAIL printed but not enforced (ok=1 dropped)"),
    ("R03", [('if [ "$mem" -lt "$FLOOR_KB" ]; then', 'if [ "$mem" -le "$FLOOR_KB" ]; then')], "U48,U49", "equality boundary: mem == floor refused"),
    ("R04", [('if [ "$mem" -lt "$FLOOR_KB" ]; then', 'if true; then')], "U48,U49", "memory check ALWAYS fails (golden-TRUE absent)"),
    ("R05", [('if [ "${n:-0}" -gt 1 ]; then FLOOR_BAD="duplicate', 'if false; then FLOOR_BAD="duplicate')], "U55", "duplicate keys no longer refused"),
    ("R06", [('| grep -c "^$FLOOR_KEY:")"', '| grep -c "$FLOOR_KEY:")"')], "U57", "key anchor ^ dropped (a commented-out key is honoured)"),
    ("R07", [('if [ "${CG_SAFE_MIN_MEM_AVAIL_KB+x}" = x ]; then', 'if [ -z "$lf" ] && [ "${CG_SAFE_MIN_MEM_AVAIL_KB+x}" = x ]; then')], "U50", "precedence: env ignored whenever a limits file is named"),
    ("R08", [('FLOOR_LOWER_KB=$((2 * HEAP_FLOOR_MB * 1024))', 'FLOOR_LOWER_KB=$((2 * 1048576))')], "U54", "lower bound 2 GiB"),
    ("R09", [('[ -r "$lf" ] || { FLOOR_BAD="limits file is not readable', '[ -e "$lf" ] || { FLOOR_BAD="limits file is not readable')], "U56", "existing-but-unreadable file no longer refused as such"),
    ("R10", [('FLOOR_BAD="floor $FLOOR_KB kB ($FLOOR_SRC) is below the $FLOOR_LOWER_KB kB lower bound (2 x the $HEAP_FLOOR_MB MiB heap floor)"', 'FLOOR_KB=$FLOOR_DEFAULT_KB')], "U54", "below-bound value silently clamped to default instead of refused"),
    ("R11", [('< $((FLOOR_KB / 1048576)) GiB (floor:', '< $((FLOOR_KB / 1000000)) GiB (floor:')], "U50", "FAIL-message GiB conversion wrong"),
    ("R12", [("case \"$v\" in ''|*[!0-9]*) return 1 ;; esac", "case \"$v\" in *[!0-9]*) return 1 ;; esac")], "U52", "empty value accepted by the digit check"),
    ("R13", [('FLOOR_KB=$((10#$ekb)); FLOOR_SRC="env CG_SAFE_MIN_MEM_AVAIL_KB"', 'FLOOR_KB=$((10#$ekb * 10)); FLOOR_SRC="env CG_SAFE_MIN_MEM_AVAIL_KB"')], "U50", "env value scaled x10"),
    ("R14", [('FLOOR_DEFAULT_KB=$((32 * 1048576))', 'FLOOR_DEFAULT_KB=$((16 * 1048576))')], "U47", "default floor halved to 16 GiB"),
    ("R15", [("case \"$v\" in ''|*[!0-9]*) return 1 ;; esac", "case \"$v\" in ''|*[!0-9x ]*) return 1 ;; esac")], "U52", "digit class widened (\"20 x\" reaches arithmetic)"),
    ("R16", [("printf '%s' \"$1\" | LC_ALL=C tr -c '[:print:]' '?' | cut -c1-200", "printf '%s' \"$1\"")], "U58", "sanitiser removed (echo injection, S8)"),
    ("R17", [('if [ "$((10#$ekb))" -lt "$FLOOR_KB" ]; then', 'if false; then')], "U51", "env may lower the floor (S9)"),
    ("R18", [('gib="$(dec_int "$val" 4)"', 'gib="$(dec_int "$val" 40)"')], "U52", "GiB digit cap removed (overflow wraps to a low floor, S4)"),
    ("R19", [('[ "$size" -le 65536 ] ||', '[ "$size" -le 999999999 ] ||')], "U56", "size cap removed (S7)"),
    ("R20", [('[ "$size" -gt 0 ] ||', '[ "$size" -ge 0 ] ||')], "U56", "empty limits file accepted (S6)"),
    ("R21", [('[ "${n:-0}" -eq 0 ] || { FLOOR_BAD="$FLOOR_KEY must be a top-level', 'true || { FLOOR_BAD="$FLOOR_KEY must be a top-level')], "U56", "indented/nested key accepted (S6)"),
    ("R22", [('elif [ -e "$P/$FLOOR_CONV_FILE" ] || [ -L "$P/$FLOOR_CONV_FILE" ]; then', 'elif false; then')], "U59", "convention-path discovery dropped (S9)"),
    ("R23", [('v="${v#"${v%%[!0]*}"}"; [ -n "$v" ] || v=0', ':'), ('FLOOR_KB=$((10#$gib * 1048576));', 'FLOOR_KB=$((gib * 1048576));')], "U53,U61", "octal parsing reintroduced (S1/S2)"),
    ("R24", [('HEAP_FLOOR_MB=8192', 'HEAP_FLOOR_MB=4096')], "U54", "heap floor halved: derived lower bound shrinks, S3 invariant case catches it"),
    ("R26", [('elif [ -e "$P/$FLOOR_CONV_FILE" ] || [ -L "$P/$FLOOR_CONV_FILE" ]; then', 'elif [ -e "$P/$FLOOR_CONV_FILE" ]; then')], "U59", "dangling symlink at the convention path silently ignored (round-2 review V02/T-A)"),
    ("R27", [('[ "$((10#$ekb))" -eq "$FLOOR_KB" ] || { FLOOR_KB=$((10#$ekb)); FLOOR_SRC="env CG_SAFE_MIN_MEM_AVAIL_KB"; }', 'FLOOR_KB=$((10#$ekb)); FLOOR_SRC="env CG_SAFE_MIN_MEM_AVAIL_KB";')], "U50", "env == base value relabels the source as env (V04/T-B)"),
    ("R28", [('| grep -c "^$FLOOR_KEY:")"', '| grep -c "^$FLOOR_KEY")"')], "U62", "duplicate-count anchor drops the colon: prefix keys counted as duplicates (V15/T-C)"),
    ("R29", [('v="${v#"${v%%[!0]*}"}"; [ -n "$v" ] || v=0', ':')], "U62", "leading-zero strip removed: 00020 refused (V16/T-C)"),
    ("R30", [('size="$(stat -L -c %s -- "$lf" 2>/dev/null)"', 'size="$(stat -c %s -- "$lf" 2>/dev/null)"')], "U56", "size gates measure the symlink itself, not its target: symlink to an empty / oversize file accepted (WF31 S-1)"),
    ("R31", [('[ -f "$f" ] && db_bytes=$((db_bytes + $(stat -L -c %s "$f")))', '[ -f "$f" ] && db_bytes=$((db_bytes + $(stat -c %s "$f")))')], "U63", "db_bytes measures a symlinked codegraph.db by link size (S-1 class sibling)"),
    ("R32", [('FLOOR_SRC="$(san "$lf") $FLOOR_KEY"', 'FLOOR_SRC="$lf $FLOOR_KEY"')], "U58", "source path of an EXISTING limits file echoed unsanitised (WF31 N11/T-1)"),
    ("R33", [('grep -c "^[[:space:]]\\+$FLOOR_KEY:")"', 'grep -c "^ \\+$FLOOR_KEY:")"')], "U56", "nested/indented-key detection sees only space indentation, not TAB (WF31 N10/T-2)"),
    ("R34", [('[ "$size" -le 65536 ] ||', '[ "$size" -le 65537 ] ||')], "U56", "size cap off by one: 65537 bytes accepted (WF31 N12/T-3)"),
    ("R35", [('[ "$size" -le 65536 ] ||', '[ "$size" -lt 65536 ] ||')], "U56", "size cap off by one the other way: exactly 65536 bytes refused (T-3)"),
    ("R25", [("[ \"$tl\" != \"unlimited\" ]", "[ \"$tl\" != \"unlimited\" ]")], "NONE", "NEGATIVE CONTROL (identity edit): every case stays green"),
]

def main(argv):
    if len(argv) == 2 and argv[1] == "--list":
        for mid, _e, red, what in M:
            print("%s\t%s\t%s" % (mid, red, what))
        return 0
    if len(argv) == 4 and argv[1] == "--apply":
        for mid, edits, _red, _what in M:
            if mid != argv[2]:
                continue
            path = os.path.join(argv[3], SAFE)
            text = open(path, encoding="utf-8").read()
            for anchor, repl in edits:
                anchor = anchor.replace("\\n", "\n"); repl = repl.replace("\\n", "\n")
                n = text.count(anchor)
                if n != 1:
                    sys.stderr.write("anchor occurs %dx in %s: %r\n" % (n, SAFE, anchor[:90]))
                    return 1
                text = text.replace(anchor, repl, 1)
            open(path, "w", encoding="utf-8").write(text)
            return 0
        sys.stderr.write("unknown mutant %s\n" % argv[2])
        return 2
    sys.stderr.write("usage: --list | --apply <id> <copy-dir>\n")
    return 2

if __name__ == "__main__":
    sys.exit(main(sys.argv))
