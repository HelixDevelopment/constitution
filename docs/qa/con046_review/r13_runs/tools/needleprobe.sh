#!/usr/bin/env bash
# needleprobe.sh: re-run the three site-lint control needles of the CON-046 mutation test outside the suite
set -u; cd /mnt/DATA1TB/claude-work/scratch/fx13.mtpm/repo/scripts/gates || exit 2
gate=cm_submodule_pin_not_downgraded.sh; hook=../hooks/pre-commit-submodule-pin-not-downgraded; s11tab=cm_submodule_pin_not_downgraded_sites.tsv
inv=cm_submodule_pin_not_downgraded_inventory.tsv; s11py=cm_submodule_pin_not_downgraded_sites.py; me=cm_submodule_pin_not_downgraded_mutation_test.sh
tmp=$(mktemp -d /mnt/DATA1TB/claude-work/tmp/np.XXXX)
s11lint() { python3 -I "$s11py" lint "$1" "${s11g:-$gate}" "$hook" "${s11t:-$s11tab}" "$me" "$inv" "${@:2}"; }
awk '{print} /^ *\[ "\$bs" = "\$basec" \] \|\|/{print "    [ \"$bs\" = \"$basec\" ] || :"}' "$gate" >"$tmp/s11g.sh"
awk -F'\t' -v OFS='\t' '$5=="path" && $3=="$1\"\"==p\"\"" && !d {d=1; next} {print}' "$s11tab" >"$tmp/s11t1.tsv"
awk -F'\t' -v OFS='\t' '$5=="sha" && !d {$6="-"; d=1} {print}' "$s11tab" >"$tmp/s11t2.tsv"
so1="$(s11g="$tmp/s11g.sh" s11lint static 2>&1)"; sr1=$?; so2="$(s11t="$tmp/s11t1.tsv" s11lint static 2>&1)"; sr2=$?; so3="$(s11t="$tmp/s11t2.tsv" s11lint static 2>&1)"; sr3=$?
grep -q 'BAD  site lint S1 gate line' <<<"$so1"; g1=$?; grep -q "BAD  site lint S1 gate line .* token '\$1\"\"==p\"\"'" <<<"$so2"; g2=$?; grep -q 'BAD  site lint S3 S[0-9][0-9]*[a-z]*: data row without a fixture key' <<<"$so3"; g3=$?
echo "rc $sr1/$sr2/$sr3 grep $g1/$g2/$g3 LC_ALL=${LC_ALL-unset}"; printf '%s\n---\n' "$so3"
rm -rf -- "${tmp:?}"
