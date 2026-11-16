#!/usr/bin/env bash
# repro.sh BIN REALDB OUTDIR — class-exhaustive id-shape reproduction on scratch DB copies.
# For each id shape: add accepted? rendered heading; md-to-db round trip keeps it?; validate; diff.
set -u
BIN="${1:?bin}"; REAL="${2:?realdb}"; OUT="${3:?outdir}"
mkdir -p "$OUT"
DESC="Reproduction item for the id grammar class sweep, long enough for the floor."
LONG="CON-$(printf '9%.0s' $(seq 1 300))"
shapes=(
  "golden|CON-999"
  "golden_alnum_suffix|CON-14b"
  "golden_4digit|CON-0999"
  "second_hyphen|CON-PENDING-x2"
  "second_hyphen_digits|CON-033-001"
  "lowercase_prefix|con-998"
  "mixedcase_prefix|Con-997"
  "two_letter_key|AB-001"
  "four_letter_key|CATS-001"
  "digits_only|123"
  "letters_only|CONX"
  "empty_suffix|CON-"
  "leading_hyphen|-001"
  "unicode_prefix|ČON-001"
  "unicode_suffix|CON-00ž"
  "inner_space|CON 001"
  "outer_space|  CON-996  "
  "tab_inside|CON-9$(printf "\\t")9"
  "very_long|$LONG"
  "dot_inside|CON-1.2"
  "legacy_letter_code|G01"
  "legacy_code_hyphen|GS-2"
  "hash_suffix|CON-995#2"
  "bracket|[CON-994]"
  "section_sign|§FL"
  "paren|CON-993(x)"
  "emdash|CON—992"
  "underscore|CON_991"
  "prefix_4letter|PREFIX:CATS"
  "prefix_lower|PREFIX:cat"
  "prefix_2letter|PREFIX:AB"
  "prefix_hyphen|PREFIX:CON-X"
  "subtask_child|SUBTASK:CON-033"
)
printf 'shape\tid\tadd_rc\tdb_has\tmd_heading\trt_kept\trt_same_id\tvalidate_rc\tdiff_rc\n' > "$OUT/table.tsv"
for s in "${shapes[@]}"; do
  name="${s%%|*}"; id="${s#*|}"
  d="$OUT/$name"; mkdir -p "$d"
  cp "$REAL" "$d/db.sqlite"
  case "$id" in
    PREFIX:*) "$BIN" add Task Low --db "$d/db.sqlite" --title "idshape $name" --description "$DESC" --prefix "${id#PREFIX:}" >"$d/add.out" 2>&1; addrc=$?
              key=$(sqlite3 "$d/db.sqlite" "select atm_id from items where title like '%idshape $name';");;
    SUBTASK:*) "$BIN" subtask-add "${id#SUBTASK:}" --db "$d/db.sqlite" --session "idshape $name" --description "$DESC" >"$d/add.out" 2>&1; addrc=$?
              key=$(sqlite3 "$d/db.sqlite" "select atm_id from items where title like '%idshape $name';");;
    *) "$BIN" add Task Low --db "$d/db.sqlite" --title "idshape $name" --description "$DESC" --id "$id" >"$d/add.out" 2>&1; addrc=$?
       key="$(printf '%s' "$id" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')";;
  esac
  dbhas=$(sqlite3 "$d/db.sqlite" "select count(*) from items where atm_id=CAST(x'$(printf '%s' "$key" | xxd -p | tr -d '\n')' AS TEXT);")
  "$BIN" sync db-to-md --db "$d/db.sqlite" --out-issues "$d/Issues.md" --out-fixed "$d/Fixed.md" >"$d/dbtomd.out" 2>&1
  head=$(grep -n "idshape $name\$" "$d/Issues.md" | head -1 | cut -c1-80 | tr '\t' ' ')
  "$BIN" diff --db "$d/db.sqlite" --issues "$d/Issues.md" --fixed "$d/Fixed.md" >"$d/diff.out" 2>&1; diffrc=$?
  cp "$d/db.sqlite" "$d/db_rt.sqlite"
  "$BIN" sync md-to-db --db "$d/db_rt.sqlite" --issues "$d/Issues.md" --fixed "$d/Fixed.md" >"$d/mdtodb.out" 2>&1
  kept=$(sqlite3 "$d/db_rt.sqlite" "select count(*) from items where title like '%idshape $name';")
  keptid=$(sqlite3 "$d/db_rt.sqlite" "select count(*) from items where title like '%idshape $name' and atm_id=CAST(x'$(printf '%s' "$key" | xxd -p | tr -d '\n')' AS TEXT);")
  ( cd "${VALCWD:?}" && "$BIN" validate --db "$d/db.sqlite" ) >"$d/validate.out" 2>&1; valrc=$?
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$(printf '%s' "$id" | cut -c1-24 | tr "\t" "~")" "$addrc" "$dbhas" "${head:-<none>}" "$kept" "$keptid" "$valrc" "$diffrc" >> "$OUT/table.tsv"
done
cat "$OUT/table.tsv"
