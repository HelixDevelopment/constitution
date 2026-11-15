#!/bin/bash
# docs/qa/engine_created_at_2026_11_13/round2/test_apply_restore_plan.sh -- tests of apply_restore_plan.sh
# (CON-339 round 2, findings F2, F7, F8 of the round-1 review; round 3, R2-F1 item d of the round-2 review:
# cases B1-B4, the evidence-path matrix, the --root forms, BLIND inputs and a racing mkdir; round 4, R3-F2
# and R3-F4 of the round-3 review: cases B5-B7, the evidence_file path shapes, a non-executable engine and no
# temporary file left behind).
#
# Builds, in a private temporary directory: a tracker database made with the real engine (add), a git
# repository that commits a snapshot of it as the evidence, and plan files; then runs the applier and
# checks exit codes, output and the database rows (read with python3 sqlite3, read-only).
#
# Usage: bash test_apply_restore_plan.sh
# Environment:
#   APPLY_RESTORE_PLAN_SH  the applier under test (default: ../apply_restore_plan.sh); the round-2 mutation
#                          runner points it at a mutated copy
#   APPLY_TEST_ENGINE      the engine binary (default: scripts/workable-items/bin/workable-items of this repository)
# Exit: 0 every case passed; 1 a case failed; 3 BLIND (no engine, git, python3 or applier).
# Evidence class: gate-logic / unit (section 11.4.289): real engine, real git, real SQLite files; no mocks.
set -u
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
HERE=$(cd "$(dirname "$0")" && pwd) || exit 3
REPO_ROOT=$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null) || { echo "BLIND: not in a git checkout" >&2; exit 3; }
APPLIER=${APPLY_RESTORE_PLAN_SH:-$HERE/../apply_restore_plan.sh}
ENGINE=${APPLY_TEST_ENGINE:-$REPO_ROOT/scripts/workable-items/bin/workable-items}
[ -f "$APPLIER" ] || { echo "BLIND: applier not found: $APPLIER" >&2; exit 3; }
[ -x "$ENGINE" ] || { echo "BLIND: engine not executable: $ENGINE" >&2; exit 3; }
command -v python3 >/dev/null || { echo "BLIND: python3 not found" >&2; exit 3; }
command -v git >/dev/null || { echo "BLIND: git not found" >&2; exit 3; }
# shellcheck source=/dev/null
. "$REPO_ROOT/scripts/lib/safe_rm.sh" || exit 3

T=$(mktemp -d "${TMPDIR:-/tmp}/apply_plan_test.XXXXXX") || exit 3
cleanup() { safe_rm_rf "${T:?}"; }
trap cleanup EXIT

PASS=0 FAIL=0
ok() { PASS=$((PASS + 1)); echo "PASS $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL $1: $2"; }

sq() { # sq <db> <sql>: one value, read-only
  python3 -I -c 'import sqlite3,sys
c=sqlite3.connect("file:"+sys.argv[1]+"?mode=ro",uri=True)
r=c.execute(sys.argv[2]).fetchone()
print("" if r is None or r[0] is None else r[0])' "$1" "$2"
}
sqw() { # sqw <db> <sql>: fixture write on a scratch database
  python3 -I -c 'import sqlite3,sys
c=sqlite3.connect(sys.argv[1]); c.execute(sys.argv[2]); c.commit()
c.execute("PRAGMA wal_checkpoint(TRUNCATE)"); c.close()' "$1" "$2"
}

DESC="a sufficiently long description that clears the section 11.4.91 floor for the applier tests"
# --- the live tracker and the committed evidence
LIVE0=$T/live0.db
"$ENGINE" add --db "$LIVE0" --description "$DESC" --id WIT-010 --title "applier item ten" Bug High >/dev/null || { echo "BLIND: engine add failed" >&2; exit 3; }
"$ENGINE" add --db "$LIVE0" --description "$DESC" --id WIT-011 --title "applier item eleven" Task Low >/dev/null || exit 3
sqw "$LIVE0" "UPDATE item_history SET created_at='2026-01-01 10:00:00' WHERE event_type='Opened'"
sqw "$LIVE0" "UPDATE items SET created_at='2026-01-01 10:00:00'"
EVREPO=$T/evrepo
mkdir -p "$EVREPO/docs" && git -C "$EVREPO" init -q || exit 3
cp "$LIVE0" "$EVREPO/docs/workable_items.db" || exit 3
git -C "$EVREPO" add docs/workable_items.db && git -C "$EVREPO" -c user.name=test -c user.email=test@example.invalid commit -q -m evidence || exit 3
COMMIT=$(git -C "$EVREPO" rev-parse --short=12 HEAD) || exit 3
SHA=$(sha256sum "$EVREPO/docs/workable_items.db" | cut -c1-64)
# the defect: created_at rewritten after the snapshot
sqw "$LIVE0" "UPDATE items SET created_at='2026-01-05 12:00:00'"

EVF=evidence/snap.db
row() { # row <vid> <idmain> <idfix> <evidence_file> [sha]
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "2026-01-01 10:00:00" "$COMMIT" docs/workable_items.db "${5:-$SHA}" "$4" "Opened row" "applier test"
}
HDR=$(printf '# comment line\nvehicle_id\tid_main\tid_fix227\tvalue\tevidence_commit\tevidence_path_in_commit\tevidence_sha256\tevidence_file\tattests\treason')
PLAN=$T/plan.tsv
{ echo "$HDR"; row WIT-010 WIT-010 WIT-010 "$EVF"; row WIT-011 WIT-011 WIT-011 "$EVF"; } >"$PLAN"

fresh() { # fresh <name>: a fresh live copy and a fresh root
  cp "$LIVE0" "$T/$1.db" && mkdir -p "$T/root_$1" || exit 3
}
run() { # run <name> <args...>: stdout+stderr to $T/<name>.out, exit code in RC
  local n=$1; shift
  ( cd "$T/root_$n" && bash "$APPLIER" --engine "$ENGINE" --db "$T/$n.db" --repo "$EVREPO" --root "$T/root_$n" "$@" ) >"$T/$n.out" 2>&1
  RC=$?
}
ca() { sq "$T/$1.db" "SELECT created_at FROM items WHERE atm_id='$2'"; }

# A1: dry run is the default; nothing written
fresh a1; h0=$(sq "$T/a1.db" "SELECT COUNT(1) FROM item_history")
run a1 --landing main --plan "$PLAN"
if [ "$RC" = 0 ] && grep -q 'RESULT: rows=2 refused=0 mode=dry-run' "$T/a1.out" && [ "$(ca a1 WIT-010)" = "2026-01-05 12:00:00" ] && [ "$(sq "$T/a1.db" "SELECT COUNT(1) FROM item_history")" = "$h0" ]; then ok A1-dry-run-default; else bad A1-dry-run-default "rc=$RC $(tail -2 "$T/a1.out")"; fi

# A2: --apply restores both rows and writes two audit rows
fresh a2; run a2 --landing main --plan "$PLAN" --apply
if [ "$RC" = 0 ] && grep -q 'RESULT: rows=2 refused=0 mode=apply' "$T/a2.out" && [ "$(ca a2 WIT-010)" = "2026-01-01 10:00:00" ] && [ "$(ca a2 WIT-011)" = "2026-01-01 10:00:00" ] \
  && [ "$(sq "$T/a2.db" "SELECT COUNT(1) FROM item_history WHERE event_type='Updated' AND reason LIKE 'created-at-restored%'")" = 2 ]; then ok A2-apply; else bad A2-apply "rc=$RC $(tail -3 "$T/a2.out")"; fi

# A3: a second --apply answers already and writes nothing
h1=$(sq "$T/a2.db" "SELECT COUNT(1) FROM item_history"); run a2 --landing main --plan "$PLAN" --apply
if [ "$RC" = 0 ] && [ "$(grep -c 'already' "$T/a2.out")" = 2 ] && [ "$(sq "$T/a2.db" "SELECT COUNT(1) FROM item_history")" = "$h1" ]; then ok A3-idempotent; else bad A3-idempotent "rc=$RC"; fi

# A4 (F2): the last plan row has no trailing newline; it is still applied
PLAN_NONL=$T/plan_nonl.tsv
printf '%s' "$(cat "$PLAN")" >"$PLAN_NONL"
if [ "$(tail -c1 "$PLAN_NONL" | od -An -c | tr -d ' ')" = '\n' ]; then bad A4-control "plan still ends with a newline"; fi
fresh a4; run a4 --landing main --plan "$PLAN_NONL" --apply
if [ "$RC" = 0 ] && grep -q 'RESULT: rows=2 refused=0 mode=apply' "$T/a4.out" && [ "$(ca a4 WIT-011)" = "2026-01-01 10:00:00" ]; then ok A4-final-row-without-newline; else bad A4-final-row-without-newline "rc=$RC $(tail -2 "$T/a4.out")"; fi

# A5 (F7): an evidence directory that is a symlink out of --root is refused; nothing written outside root
fresh a5; mkdir -p "$T/outside" && ln -s "$T/outside" "$T/root_a5/evidence" || exit 3
run a5 --landing main --plan "$PLAN" --apply
if [ "$RC" = 3 ] && [ -z "$(ls -A "$T/outside")" ] && [ "$(ca a5 WIT-010)" = "2026-01-05 12:00:00" ]; then ok A5-symlinked-evidence-dir-refused; else bad A5-symlinked-evidence-dir-refused "rc=$RC outside=$(ls -A "$T/outside" | tr '\n' ' ')"; fi

# A5b (F7): the evidence FILE itself is a symlink out of --root: refused
fresh a5b; mkdir -p "$T/root_a5b/evidence" && cp "$EVREPO/docs/workable_items.db" "$T/outside_file.db" && ln -s "$T/outside_file.db" "$T/root_a5b/$EVF" || exit 3
run a5b --landing main --plan "$PLAN" --apply
if [ "$RC" = 3 ] && [ "$(ca a5b WIT-010)" = "2026-01-05 12:00:00" ]; then ok A5b-symlinked-evidence-file-refused; else bad A5b-symlinked-evidence-file-refused "rc=$RC"; fi

# A6: an evidence_file with .. is refused before anything is written
PLAN_DOTS=$T/plan_dots.tsv; { echo "$HDR"; row WIT-010 WIT-010 WIT-010 "evidence/../../escape.db"; } >"$PLAN_DOTS"
fresh a6; run a6 --landing main --plan "$PLAN_DOTS" --apply
if [ "$RC" = 3 ] && [ ! -e "$T/escape.db" ] && [ ! -e "$T/root_a6/escape.db" ]; then ok A6-dotdot-refused; else bad A6-dotdot-refused "rc=$RC"; fi

# A6b: an evidence_file with .. that would still land under --root is refused too (the plan names one path)
PLAN_DOTS2=$T/plan_dots2.tsv; { echo "$HDR"; row WIT-010 WIT-010 WIT-010 "evidence/../evidence/snap.db"; } >"$PLAN_DOTS2"
fresh a6b; run a6b --landing main --plan "$PLAN_DOTS2" --apply
if [ "$RC" = 3 ] && [ "$(ca a6b WIT-010)" = "2026-01-05 12:00:00" ]; then ok A6b-dotdot-inside-root-refused; else bad A6b-dotdot-inside-root-refused "rc=$RC"; fi

# A7: an absolute evidence_file is refused
PLAN_ABS=$T/plan_abs.tsv; { echo "$HDR"; row WIT-010 WIT-010 WIT-010 "$T/abs.db"; } >"$PLAN_ABS"
fresh a7; run a7 --landing main --plan "$PLAN_ABS" --apply
if [ "$RC" = 3 ] && [ ! -e "$T/abs.db" ]; then ok A7-absolute-refused; else bad A7-absolute-refused "rc=$RC"; fi

# A8: the plan's sha256 differs from the extracted file: BLIND, nothing written
PLAN_SHA=$T/plan_sha.tsv; { echo "$HDR"; row WIT-010 WIT-010 WIT-010 "$EVF" "$(printf '0%.0s' $(seq 64))"; } >"$PLAN_SHA"
fresh a8; run a8 --landing main --plan "$PLAN_SHA" --apply
if [ "$RC" = 3 ] && [ "$(ca a8 WIT-010)" = "2026-01-05 12:00:00" ]; then ok A8-sha-mismatch-blind; else bad A8-sha-mismatch-blind "rc=$RC"; fi

# A9: a pre-existing evidence file with other content: BLIND
fresh a9; mkdir -p "$T/root_a9/evidence" && echo "not the evidence" >"$T/root_a9/$EVF"
run a9 --landing main --plan "$PLAN" --apply
if [ "$RC" = 3 ] && [ "$(ca a9 WIT-010)" = "2026-01-05 12:00:00" ]; then ok A9-preexisting-wrong-file; else bad A9-preexisting-wrong-file "rc=$RC"; fi

# A10 (F8): a database without the second id: the first row is applied, the second refused, exit 1
fresh a10; sqw "$T/a10.db" "DELETE FROM items WHERE atm_id='WIT-011'"
run a10 --landing main --plan "$PLAN" --apply
if [ "$RC" = 1 ] && grep -q 'RESULT: rows=2 refused=1 mode=apply' "$T/a10.out" && [ "$(ca a10 WIT-010)" = "2026-01-01 10:00:00" ]; then ok A10-row-by-row; else bad A10-row-by-row "rc=$RC $(tail -2 "$T/a10.out")"; fi

# A11: --landing fix227 reads the id_fix227 column ('-' = no id for that landing: BLIND)
PLAN_FIX=$T/plan_fix.tsv; { echo "$HDR"; row WIT-010 WIT-010 - "$EVF"; } >"$PLAN_FIX"
fresh a11; run a11 --landing fix227 --plan "$PLAN_FIX" --apply
if [ "$RC" = 3 ] && grep -q 'has no id for --landing fix227' "$T/a11.out"; then ok A11-fix227-column; else bad A11-fix227-column "rc=$RC"; fi
PLAN_FIX2=$T/plan_fix2.tsv; { echo "$HDR"; row WIT-010 - WIT-011 "$EVF"; } >"$PLAN_FIX2"
fresh a11b; run a11b --landing fix227 --plan "$PLAN_FIX2" --apply
# WIT-011 is a different item than the evidence's WIT-010: the engine refuses the identity
if [ "$RC" = 1 ] && grep -q 'EVIDENCE-ITEM-MISMATCH' "$T/a11b.out" && grep -q -- '-> WIT-011 (fix227)' "$T/a11b.out"; then ok A11b-fix227-id-used; else bad A11b-fix227-id-used "rc=$RC $(tail -3 "$T/a11b.out")"; fi

# A11c: --landing main reads the id_main column even when id_fix227 names another item
PLAN_MAIN2=$T/plan_main2.tsv; { echo "$HDR"; row WIT-010 WIT-010 WIT-011 "$EVF"; } >"$PLAN_MAIN2"
fresh a11c; run a11c --landing main --plan "$PLAN_MAIN2" --apply
if [ "$RC" = 0 ] && grep -q -- '-> WIT-010 (main)' "$T/a11c.out" && [ "$(ca a11c WIT-010)" = "2026-01-01 10:00:00" ]; then ok A11c-main-column; else bad A11c-main-column "rc=$RC $(tail -3 "$T/a11c.out")"; fi

# A12: bad --landing is a usage error
fresh a12; run a12 --landing nowhere --plan "$PLAN"
if [ "$RC" = 2 ]; then ok A12-bad-landing; else bad A12-bad-landing "rc=$RC"; fi

# A13: git show of an absent commit: BLIND, no temporary file left
PLAN_GIT=$T/plan_git.tsv
{ echo "$HDR"; printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' WIT-010 WIT-010 WIT-010 "2026-01-01 10:00:00" deadbeefdead docs/workable_items.db "$SHA" "$EVF" x y; } >"$PLAN_GIT"
fresh a13; run a13 --landing main --plan "$PLAN_GIT" --apply
if [ "$RC" = 3 ] && [ -z "$(ls -A "$T/root_a13/evidence" 2>/dev/null)" ]; then ok A13-git-show-fails; else bad A13-git-show-fails "rc=$RC left=$(ls -A "$T/root_a13/evidence" 2>/dev/null | tr '\n' ' ')"; fi

# A14: a plan with no data rows: BLIND
PLAN_EMPTY=$T/plan_empty.tsv; echo "$HDR" >"$PLAN_EMPTY"
fresh a14; run a14 --landing main --plan "$PLAN_EMPTY"
if [ "$RC" = 3 ]; then ok A14-empty-plan; else bad A14-empty-plan "rc=$RC"; fi

# A15: a refused row in a DRY run also exits 1 and writes nothing
fresh a15; sqw "$T/a15.db" "DELETE FROM items WHERE atm_id='WIT-011'"
run a15 --landing main --plan "$PLAN"
if [ "$RC" = 1 ] && [ "$(ca a15 WIT-010)" = "2026-01-05 12:00:00" ]; then ok A15-dry-run-refusal; else bad A15-dry-run-refusal "rc=$RC"; fi

# A16: missing required argument is a usage error
( bash "$APPLIER" --engine "$ENGINE" --landing main ) >/dev/null 2>&1; RC=$?
if [ "$RC" = 2 ]; then ok A16-usage; else bad A16-usage "rc=$RC"; fi

# ---- round 3 (review R2-F1, item d): the evidence-path class, the --root forms, BLIND inputs, a racing mkdir
H0=$(sq "$LIVE0" "SELECT COUNT(1) FROM item_history")
plan1() { { echo "$HDR"; row WIT-010 WIT-010 WIT-010 "$1"; } >"$2"; }        # plan1 <evidence_file> <out>
unchanged() { [ "$(ca "$1" WIT-010)" = "2026-01-05 12:00:00" ] && [ "$(sq "$T/$1.db" "SELECT COUNT(1) FROM item_history")" = "$H0" ]; }
emptydir() { [ -d "$1" ] && [ -z "$(ls -A "$1")" ]; }
runx() { # runx <name> <cwd> <args...>: like run, but the caller names the working directory and every flag
  local n=$1 cwd=$2; shift 2
  ( cd "$cwd" && bash "$APPLIER" "$@" ) >"$T/$n.out" 2>&1
  RC=$?
}
restored() { [ "$(ca "$1" WIT-010)" = "2026-01-01 10:00:00" ]; }

# B1: path matrix. The evidence_file has N components (N-1 directories, then the file), N = 1..5. For every N
# a control without links is applied. Then for every depth d = 1..N the component at depth d is a symbolic
# link, once to a target inside --root and once to a target outside it. Every linked case must: exit 3, name
# the symbolic link, never run the engine, create nothing at the link target, leave the tracker unchanged.
for N in 1 2 3 4 5; do
  ev=""; for k in $(seq 1 $((N - 1))); do ev="${ev}d$k/"; done; ev="${ev}snap.db"
  P=$T/plan_m$N.tsv; plan1 "$ev" "$P"
  n=m${N}c; fresh "$n"; run "$n" --landing main --plan "$P" --apply
  if [ "$RC" = 0 ] && restored "$n" && [ -f "$T/root_$n/$ev" ] && [ ! -L "$T/root_$n/$ev" ]; then ok "B1-N$N-control"
  else bad "B1-N$N-control" "rc=$RC $(tail -2 "$T/$n.out")"; fi
  for d in $(seq 1 "$N"); do
    pre=""; for k in $(seq 1 $((d - 1))); do pre="${pre}d$k/"; done
    for where in in out; do
      n=m${N}d${d}$where; fresh "$n"; R=$T/root_$n
      mkdir -p "$R/$pre" || exit 3
      if [ "$d" = "$N" ]; then   # the file itself is the link; its target is a byte-correct copy of the evidence
        if [ "$where" = in ]; then tgt=$R/tgt_in.db; else tgt=$T/out_$n.db; fi
        cp "$EVREPO/docs/workable_items.db" "$tgt" && ln -s "$tgt" "$R/${pre}snap.db" || exit 3
        tsha=$(sha256sum "$tgt" | cut -c1-64)
        run "$n" --landing main --plan "$P" --apply
        if [ "$RC" = 3 ] && grep -q 'symbolic link' "$T/$n.out" && ! grep -q 'engine exit' "$T/$n.out" && unchanged "$n" \
          && [ "$(sha256sum "$tgt" | cut -c1-64)" = "$tsha" ]; then ok "B1-N$N-d$d-$where"
        else bad "B1-N$N-d$d-$where" "rc=$RC $(tail -2 "$T/$n.out")"; fi
      else                       # a directory component is the link
        if [ "$where" = in ]; then tgt=$R/tgt_in; else tgt=$T/out_$n; fi
        mkdir -p "$tgt" && ln -s "$tgt" "$R/${pre}d$d" || exit 3
        run "$n" --landing main --plan "$P" --apply
        if [ "$RC" = 3 ] && grep -q 'symbolic link' "$T/$n.out" && ! grep -q 'engine exit' "$T/$n.out" && unchanged "$n" \
          && emptydir "$tgt"; then ok "B1-N$N-d$d-$where"
        else bad "B1-N$N-d$d-$where" "rc=$RC created=$(ls -A "$tgt" | tr '\n' ' ') $(tail -1 "$T/$n.out")"; fi
      fi
    done
  done
done

# B2: the forms of --root. A --root reached through one or two symbolic links is resolved to its physical
# path: the evidence lands in the real directory and the audit row records the plan's relative path.
P1=$T/plan_b2.tsv; plan1 "$EVF" "$P1"
for form in link1 link2; do
  n=b2$form; fresh "$n"; real=$T/root_$n
  ln -s "$real" "$T/${n}_l1" || exit 3; rootarg=$T/${n}_l1
  if [ "$form" = link2 ]; then ln -s "$T/${n}_l1" "$T/${n}_l2" || exit 3; rootarg=$T/${n}_l2; fi
  runx "$n" "$T" --engine "$ENGINE" --db "$T/$n.db" --repo "$EVREPO" --root "$rootarg" --landing main --plan "$P1" --apply
  evp=$(sq "$T/$n.db" "SELECT evidence_path FROM item_history WHERE atm_id='WIT-010' AND event_type='Updated' ORDER BY id DESC LIMIT 1")
  if [ "$RC" = 0 ] && restored "$n" && [ -f "$real/$EVF" ] && [ ! -L "$real/evidence" ] && [ "$evp" = "$EVF" ]; then ok "B2-root-$form"
  else bad "B2-root-$form" "rc=$RC evidence_path=$evp $(tail -2 "$T/$n.out")"; fi
done
n=b2rel; fresh "$n"
runx "$n" "$T" --engine "$ENGINE" --db "$T/$n.db" --repo "$EVREPO" --root "root_$n" --landing main --plan "$P1" --apply
if [ "$RC" = 0 ] && restored "$n" && [ -f "$T/root_$n/$EVF" ]; then ok B2-root-relative; else bad B2-root-relative "rc=$RC $(tail -2 "$T/$n.out")"; fi
n=b2slash; fresh "$n"
runx "$n" "$T" --engine "$ENGINE" --db "$T/$n.db" --repo "$EVREPO" --root "$T/root_$n/" --landing main --plan "$P1" --apply
if [ "$RC" = 0 ] && restored "$n" && [ -f "$T/root_$n/$EVF" ]; then ok B2-root-trailing-slash; else bad B2-root-trailing-slash "rc=$RC $(tail -2 "$T/$n.out")"; fi
n=b2file; fresh "$n"; : >"$T/b2_root_is_a_file"
runx "$n" "$T" --engine "$ENGINE" --db "$T/$n.db" --repo "$EVREPO" --root "$T/b2_root_is_a_file" --landing main --plan "$P1" --apply
if [ "$RC" = 3 ] && grep -q 'root not a directory' "$T/$n.out" && unchanged "$n"; then ok B2-root-is-a-file; else bad B2-root-is-a-file "rc=$RC"; fi
n=b2missing; fresh "$n"
runx "$n" "$T" --engine "$ENGINE" --db "$T/$n.db" --repo "$EVREPO" --root "$T/b2_no_such_root" --landing main --plan "$P1" --apply
if [ "$RC" = 3 ] && grep -q 'root not a directory' "$T/$n.out" && unchanged "$n" && [ ! -e "$T/b2_no_such_root" ]; then ok B2-root-missing; else bad B2-root-missing "rc=$RC"; fi

# B3: BLIND and usage inputs. Missing engine, tracker or plan: exit 3; an unknown argument or an option with
# no value: exit 2. None of them runs the engine or writes evidence.
n=b3; fresh "$n"; R=$T/root_$n
b3() { # b3 <label> <want_rc> <args...>
  local label=$1 want=$2; shift 2
  runx "$n" "$R" "$@"
  if [ "$RC" = "$want" ] && ! grep -q 'engine exit' "$T/$n.out" && [ ! -e "$R/evidence" ] && unchanged "$n"; then ok "B3-$label"
  else bad "B3-$label" "rc=$RC want=$want $(tail -1 "$T/$n.out")"; fi
}
b3 engine-missing 3 --engine "$T/no_such_engine" --db "$T/$n.db" --repo "$EVREPO" --root "$R" --landing main --plan "$P1" --apply
b3 db-missing 3 --engine "$ENGINE" --db "$T/no_such.db" --repo "$EVREPO" --root "$R" --landing main --plan "$P1" --apply
b3 plan-missing 3 --engine "$ENGINE" --db "$T/$n.db" --repo "$EVREPO" --root "$R" --landing main --plan "$T/no_such_plan.tsv" --apply
b3 unknown-argument 2 --engine "$ENGINE" --db "$T/$n.db" --repo "$EVREPO" --root "$R" --landing main --plan "$P1" --apply --force
b3 option-without-value 2 --engine "$ENGINE" --repo "$EVREPO" --root "$R" --landing main --plan "$P1" --apply --db

# B4: a racing mkdir. A PATH shim for mkdir turns ROOT/evidence into a symbolic link AFTER the walk has seen
# a plain path and BEFORE the real mkdir runs: the deterministic stand-in for a concurrent change. The
# resolved-directory check must refuse it, both for a target outside --root and for a sibling whose path
# shares --root as a prefix. The shim logs every call (the control needle that the shim was really used).
REALMKDIR=$(command -v mkdir) || exit 3
SHIM=$T/shim; mkdir -p "$SHIM" || exit 3
{ echo '#!/bin/bash'
  echo 'echo "$*" >>"${SHIM_LOG:?}"'
  echo 'if [ -n "${SHIM_TARGET:-}" ] && [ ! -e "${SHIM_ROOT:?}/evidence" ]; then ln -s "$SHIM_TARGET" "$SHIM_ROOT/evidence" || exit 1; fi'
  echo "exec $REALMKDIR \"\$@\""; } >"$SHIM/mkdir" && chmod +x "$SHIM/mkdir" || exit 3
b4() { # b4 <name> <target or empty> <want_rc>
  local n=$1 tgt=$2 want=$3; fresh "$n"; local R=$T/root_$n
  [ -z "$tgt" ] || mkdir -p "$tgt" || exit 3
  ( cd "$R" && SHIM_LOG=$T/$n.shimlog SHIM_ROOT=$R SHIM_TARGET=$tgt PATH="$SHIM:$PATH" \
      bash "$APPLIER" --engine "$ENGINE" --db "$T/$n.db" --repo "$EVREPO" --root "$R" --landing main --plan "$P1" --apply ) >"$T/$n.out" 2>&1
  RC=$?
}
b4 b4out "$T/b4_outside" 3
if [ "$RC" = 3 ] && grep -q 'outside --root' "$T/b4out.out" && [ -s "$T/b4out.shimlog" ] && emptydir "$T/b4_outside" && unchanged b4out; then ok B4-racing-link-outside
else bad B4-racing-link-outside "rc=$RC shim=$(wc -l <"$T/b4out.shimlog" 2>/dev/null) $(tail -1 "$T/b4out.out")"; fi
b4 b4pre "$T/root_b4pre_x" 3
if [ "$RC" = 3 ] && grep -q 'outside --root' "$T/b4pre.out" && [ -s "$T/b4pre.shimlog" ] && emptydir "$T/root_b4pre_x" && unchanged b4pre; then ok B4-racing-link-prefix-sibling
else bad B4-racing-link-prefix-sibling "rc=$RC $(tail -1 "$T/b4pre.out")"; fi
b4 b4ctl "" 0
if [ "$RC" = 0 ] && [ -s "$T/b4ctl.shimlog" ] && restored b4ctl && [ -f "$T/root_b4ctl/$EVF" ]; then ok B4-shim-control
else bad B4-shim-control "rc=$RC $(tail -1 "$T/b4ctl.out")"; fi

# ---- round 4 (review R3-F2, R3-F4): the path-shape class of evidence_file, a non-executable engine, no
# temporary file left behind.
# B5: one case per path shape. Each case builds its own root, records the tree of the root (type, path, link
# target) before the run, and runs with --apply. A "blind" case must: exit 3, never run the engine, leave the
# tracker unchanged, and leave the trees of the root and of the outside directory exactly as they were. An "ok" case must: exit 0, restore the row, and leave
# exactly one regular evidence file at the real path (no temporary file beside it).
treeof() { (cd "$1" && find . -mindepth 1 -printf '%y %p -> %l\n' | LC_ALL=C sort); }
b5() { # b5 <shape> <evidence_file> <want: ok|blind> [ok: real path of the file | blind: text the BLIND reason must contain]
  local shape=$1 ev=$2 want=$3 realp=${4:-} n R out before outbefore P dir
  n=b5_$shape; fresh "$n"; R=$T/root_$n; out=$T/out_$n; mkdir -p "$out" || exit 3
  case "$shape" in
    dslash-link-in) mkdir -p "$R/a" "$R/tgt_in" && ln -s "$R/tgt_in" "$R/a/b" ;;
    dslash-link-out) mkdir -p "$R/a" && ln -s "$out" "$R/a/b" ;;
    dslash-link-first) mkdir -p "$R/tgt_in" && ln -s "$R/tgt_in" "$R/a" ;;
    dslash-link-file) mkdir -p "$R/a/b" && cp "$EVREPO/docs/workable_items.db" "$out/f.db" && ln -s "$out/f.db" "$R/a/b/snap.db" ;;
    lead-dot-link) mkdir -p "$R/tgt_in" && ln -s "$R/tgt_in" "$R/evidence" ;;
    mid-dot-link) mkdir -p "$R/evidence" "$R/tgt_in" && ln -s "$R/tgt_in" "$R/evidence/x" ;;
    triple-slash-link) ln -s "$out" "$R/evidence" ;;
    dir-dot|dir-slash) mkdir -p "$R/evidence" ;;
    dest-is-dir) mkdir -p "$R/evidence/snap.db" ;;
    dest-is-fifo) mkdir -p "$R/evidence" && mkfifo "$R/evidence/snap.db" ;;
    loop-first) ln -s "$R/evidence" "$R/evidence" ;;
    loop-mid) mkdir -p "$R/evidence" && ln -s "$R/evidence/x" "$R/evidence/x" ;;
    dangling-dir) ln -s "$R/nowhere" "$R/evidence" ;;
    dangling-file) mkdir -p "$R/evidence" && ln -s "$R/nowhere.db" "$R/evidence/snap.db" ;;
    dangling-file-out) mkdir -p "$R/evidence" && ln -s "$out/nowhere.db" "$R/evidence/snap.db" ;;
  esac || exit 3
  before=$(treeof "$R"); outbefore=$(treeof "$out")
  P=$T/plan_$n.tsv; plan1 "$ev" "$P"
  run "$n" --landing main --plan "$P" --apply
  if [ "$want" = blind ]; then
    if [ "$RC" = 3 ] && ! grep -q 'engine exit' "$T/$n.out" && unchanged "$n" && [ "$(treeof "$R")" = "$before" ] \
      && [ "$(treeof "$out")" = "$outbefore" ] && { [ -z "$realp" ] || grep -qF -- "$realp" "$T/$n.out"; }; then ok "B5-$shape"
    else bad "B5-$shape" "rc=$RC tree-unchanged=$([ "$(treeof "$R")" = "$before" ] && echo yes || echo no) $(tail -1 "$T/$n.out")"; fi
  else
    dir=$(dirname "$R/$realp")
    if [ "$RC" = 0 ] && restored "$n" && [ -f "$R/$realp" ] && [ ! -L "$R/$realp" ] \
      && [ "$(ls -A "$dir")" = "$(basename "$realp")" ]; then ok "B5-$shape"
    else bad "B5-$shape" "rc=$RC dir=$(treeof "$dir" 2>/dev/null | tr '\n' ' ') $(tail -1 "$T/$n.out")"; fi
  fi
}
b5 dslash-control 'a//b/snap.db' ok a/b/snap.db
b5 dslash-link-in 'a//b/snap.db' blind
b5 dslash-link-out 'a//b/snap.db' blind
b5 dslash-link-first 'a//b/snap.db' blind
b5 dslash-link-file 'a//b/snap.db' blind
b5 lead-dot-control './evidence/snap.db' ok evidence/snap.db
b5 lead-dot-link './evidence/snap.db' blind
b5 mid-dot-control 'evidence/./snap.db' ok evidence/snap.db
b5 mid-dot-link 'evidence/./x/snap.db' blind
b5 triple-slash-control 'evidence///snap.db' ok evidence/snap.db
b5 triple-slash-link 'evidence///snap.db' blind
# The shape cases also check the reason: a later check (the existing entry is a directory) would stop some of
# them too, so only the reason tells whether the shape check itself refused the row.
b5 dot '.' blind 'must end in a file name'
b5 dot-dot '..' blind
b5 dot-dot-mid 'evidence/../snap.db' blind
b5 dir-dot 'evidence/.' blind 'must end in a file name'
b5 dir-slash 'evidence/' blind 'must end in a file name'
b5 file-slash 'evidence/snap.db/' blind 'must end in a file name'
b5 newdir-dot 'newdir/.' blind 'must end in a file name'
b5 newdir-slash 'newdir/' blind 'must end in a file name'
b5 abs-double-slash '//evidence/snap.db' blind
b5 dest-is-dir 'evidence/snap.db' blind
b5 dest-is-fifo 'evidence/snap.db' blind
b5 loop-first 'evidence/snap.db' blind
b5 loop-mid 'evidence/x/snap.db' blind
b5 dangling-dir 'evidence/snap.db' blind
b5 dangling-file 'evidence/snap.db' blind
b5 dangling-file-out 'evidence/snap.db' blind
# A row with fewer than 8 columns leaves evidence_file empty (read fills the missing fields with nothing).
n=b5_empty; fresh "$n"; R=$T/root_$n; before=$(treeof "$R")
P=$T/plan_$n.tsv; { echo "$HDR"; printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' WIT-010 WIT-010 WIT-010 "2026-01-01 10:00:00" "$COMMIT" docs/workable_items.db "$SHA"; } >"$P"
run "$n" --landing main --plan "$P" --apply
if [ "$RC" = 3 ] && ! grep -q 'engine exit' "$T/$n.out" && unchanged "$n" && [ "$(treeof "$R")" = "$before" ] \
  && grep -qF 'must end in a file name' "$T/$n.out"; then ok B5-empty-evidence-file
else bad B5-empty-evidence-file "rc=$RC $(tail -1 "$T/$n.out")"; fi

# B6 (R3S02): an engine that exists but is not executable is BLIND (exit 3); the engine is never run.
n=b6; fresh "$n"; R=$T/root_$n; cp "$ENGINE" "$T/b6_engine" && chmod 0644 "$T/b6_engine" || exit 3
runx "$n" "$R" --engine "$T/b6_engine" --db "$T/$n.db" --repo "$EVREPO" --root "$R" --landing main --plan "$P1" --apply
if [ "$RC" = 3 ] && grep -q 'engine not executable' "$T/$n.out" && ! grep -q 'engine exit' "$T/$n.out" && unchanged "$n" && [ ! -e "$R/evidence" ]; then ok B6-engine-not-executable
else bad B6-engine-not-executable "rc=$RC $(tail -1 "$T/$n.out")"; fi

# B7 (R3S05): after a successful extraction the root holds the evidence directory and the evidence file and
# nothing else (the temporary file is renamed, not copied); in a dry run and with --apply.
for mode in dry apply; do
  n=b7$mode; fresh "$n"; R=$T/root_$n
  if [ "$mode" = apply ]; then run "$n" --landing main --plan "$P1" --apply; else run "$n" --landing main --plan "$P1"; fi
  if [ "$RC" = 0 ] && [ "$(treeof "$R")" = "$(printf '%s\n' 'd ./evidence -> ' 'f ./evidence/snap.db -> ')" ]; then ok "B7-no-temp-file-$mode"
  else bad "B7-no-temp-file-$mode" "rc=$RC left=$(treeof "$R" 2>/dev/null | tr '\n' ' ')"; fi
done

echo "RESULT: pass=$PASS fail=$FAIL"
[ "$FAIL" = 0 ] || exit 1
exit 0
