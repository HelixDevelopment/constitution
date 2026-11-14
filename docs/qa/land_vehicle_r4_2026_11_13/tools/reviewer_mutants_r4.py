# reviewer_mutants_r4.py <src> <outdir>: the reviewer's round-3 mutants (MR*), copied from
# the review harness; only MR05's anchor is ported to the round-4 source.
# Each edit must apply exactly once, else NOAPPLY is printed and no mutant is written.
import sys, os
src, outdir = sys.argv[1], sys.argv[2]
s = open(src).read()
M = [
 ("MR01_push_url_first_only", [('push=$(g remote get-url --push --all "$name" 2>/dev/null)', 'push=$(g remote get-url --push "$name" 2>/dev/null)')]),
 ("MR02_only_mirror_key_checked", [('for key in mirror receivepack uploadpack; do', 'for key in mirror; do')]),
 ("MR03_id_in_text_substring", [('id_in_text() { grep -aEq -- "(^|[^A-Za-z0-9-])$1([^0-9]|\\$)" "$2"; }', 'id_in_text() { grep -aFq -- "$1" "$2"; }')]),
 ("MR04_no_branch_check_after_mint", [(' && [ "$(g rev-parse --abbrev-ref HEAD)" = main ] \\\n', ' \\\n')]),
 # PORTED (r4, by the round-4 fixer): the publish check now passes --untracked-files=all
 ("MR05_publish_dirty_ignores_untracked", [('[ -z "$(g status --porcelain --untracked-files=all)" ] || die 2', '[ -z "$(g status --porcelain --untracked-files=no)" ] || die 2')]),
 ("MR07_trailer_range_first_remote_only", [('check_trailers main --not "${before[@]}"', 'check_trailers main --not "${before[0]}"')]),
 ("MR08_pushed_is_pass_without_readback", [('if [ "$after" = "$local_main" ]; then result=PASS', 'if [ "${action[i]}" = pushed ] || [ "$after" = "$local_main" ]; then result=PASS')]),
 ("MR09_shared_lock", [('flock -n 9 || die 2', 'flock -n -s 9 || die 2')]),
 ("MR12_verify_id_substring", [('grep -Eq -- "(^|[^A-Za-z0-9-])$1([^0-9]|\\$)" <<<"$out"', 'grep -Fq -- "$1" <<<"$out"')]),
 ("MR15_newest_tip_keeps_older", [('elif g merge-base --is-ancestor "$tip" "$s"; then tip=$s', 'elif g merge-base --is-ancestor "$tip" "$s"; then :')]),
 ("MR20_rejected_reported_as_pushed", [("else action[i]='push-rejected'", "else action[i]=pushed")]),
 # PORTED (r4, by the round-4 fixer): the check is now split over two lines
 ("MR21_remotes_extra_field_ok", [('[ -n "$url" ] && [ -z "$rest" ] \\\n      || die 2', '[ -n "$url" ] \\\n      || die 2')]),
 ("MR22_url_prefix_match", [('[ "$got" = "$want" ] || die 2', '[[ "$got" == "$want"* ]] || die 2')]),
]
os.makedirs(outdir, exist_ok=True)
for name, edits in M:
    t = s
    ok = True
    for old, new in edits:
        if t.count(old) != 1:
            print(f"{name} NOAPPLY count={t.count(old)}: {old[:60]!r}"); ok = False; break
        t = t.replace(old, new)
    if not ok: continue
    d = os.path.join(outdir, name); os.makedirs(d, exist_ok=True)
    p = os.path.join(d, "land_vehicle.sh"); open(p, "w").write(t); os.chmod(p, 0o755)
    print(f"{name} OK")
