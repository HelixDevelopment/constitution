# mutants_r4.py <src> <outdir>: one mutated copy of land_vehicle.sh per mutant.
# Round 4: the 85 round-3 producer mutants (R2 + N + Y) with anchors ported to the
# round-4 source where it moved (each PORTED (r4) note says why), then group Z:
# new round-4 mutants on the round-4 checks.
# Every edit must apply exactly once, else the mutant is reported NOAPPLY (never
# silently skipped). Three groups:
#   R2  the 39 round-2 fixer mutants (evidence/mutants.py of round 2), anchors kept
#       verbatim where the source text is unchanged; PORTED (same mutation, new
#       anchor) where round 3 moved the mutated code - each port says why.
#   N   the 19 reviewer mutants of review round 2 (review_lander_r2_artifacts/mutants.py),
#       same rule.
#   Y   new round-3 mutants on the new checks.
import sys, os
src, outdir = sys.argv[1], sys.argv[2]
s = open(src).read()
# PORTED (r4): the push now runs with -c push.followTags=false -c push.recurseSubmodules=no and --no-follow-tags
PUSH_NEW = 'elif g -c push.followTags=false -c push.recurseSubmodules=no push -q --no-verify --no-follow-tags "${R_NAMES[$i]}" "main:refs/heads/main" 2>>"$ERRLOG"; then'
M = [
 # ---------------------------------------------------------------- R2 (39)
 ("M01_no_sha_check", [('[ "$actual" = "${SHA,,}" ] || die 1', 'true || die 1')]),
 ("M02_no_headref_check", [('[ -n "$ref" ] || die 1 "head $HEAD_SHA is not a ref tip in the bundle"', ':')]),
 ("M03_no_diverge_refusal", [('else die 3 "remote mains have diverged ($s vs $tip): integrate them first, by merge"', 'else :')]),
 ("M04_no_clonename_check", [('if [ -n "$MINT_CMD" ] && [ "$CLONE_NAME" != constitution ]; then', 'if false; then')]),
 # PORTED (r4): the publish dirty check now passes --untracked-files=all
 ("M05_no_dirty_check", [('[ -z "$(g status --porcelain --untracked-files=all)" ] || die 2 "clone has uncommitted', 'true || die 2 "clone has uncommitted')]),
 ("M06_no_ff_precheck", [('&& g merge-base --is-ancestor "${before[i]}" "$local_main"; then action[i]=push', '; then action[i]=push')]),
 ("M07_drop_author_date", [('GIT_AUTHOR_DATE=$(g log -1 --format=%aD "$c")', 'GIT_AUTHOR_DATE=@0')]),
 ("M08_drop_author_name", [('GIT_AUTHOR_NAME=$(g log -1 --format=%an "$c")', 'GIT_AUTHOR_NAME=Someone')]),
 ("M09_no_append_when_missing", [('if [ "$found" = 0 ]; then', 'if false; then')]),
 ("M10_no_parent_remap", [('pargs+=(-p "${MAP[$p]}")', 'pargs+=(-p "$p")')]),
 ("M11_loose_id_re", [('ID_RE="^${KEY_PREFIX}-[0-9]+\\$"', "ID_RE='.*'")]),
 ("M12_no_already_on_main", [('then die 3 "vehicle head is already on main: nothing to land"; fi', 'then :; fi')]),
 ("M13_no_remote_set_check", [('[ "${#R_NAMES[@]}" -eq "$(wc -w <<<"$LANDER_REMOTES")" ] || die 2', 'true || die 2')]),
 ("M13b_no_exactly_once", [('[ "$n" -eq 1 ] || die 2 "remotes file must declare', 'true || die 2 "remotes file must declare')]),
 ("M14_merge_drops_main", [('merge --no-verify -q --no-ff --no-edit \\\n         -m "Merge vehicle $HEAD_SHA onto main" -m "Roadmap-Item: $id" "$new_head"', 'checkout -q -B main "$new_head"')]),
 ("M15_no_base_check_publish", [('g merge-base --is-ancestor "$main_before" main || die 1 "local main no longer contains the prepared base"', ':')]),
 # PORTED: the add moved out of an if block (indent 6 -> 4)
 # PORTED (r4): the add now carries || die
 ("M16_mint_no_commit", [('    g add -A || die 1 "git add of the mint changes failed"\n', '    :\n')]),
 ("M17_drop_coauthored", [('    out+=("$line")\n  done', '    [[ "${line,,}" == co-authored-by:* ]] || out+=("$line")\n  done')]),
 ("X01_no_cr_strip", [("  msg=${msg//$'\\r'/}\n  local -a L=()", "  local -a L=()")]),
 ("X02_no_to_be_minted", [('|<TO-BE-MINTED[^>]*>)\\$"}', ')\\$"}')]),
 ("X03_case_sensitive_key", [('[[ "${key,,}" =~ ^roadmap-item', '[[ "${key}" =~ ^Roadmap-Item')]),
 ("X04_no_dedupe", [('[ "$seen" = 1 ] || out+=("$canon")', 'out+=("$canon")')]),
 # PORTED: the publish trailer check moved from do_publish into the preflight (range from remote tips)
 ("X05_no_publish_trailer_check", [('    check_trailers main --not "${before[@]}"\n', '    :\n')]),
 ("X06_no_landed_check", [('g merge-base --is-ancestor "$landed" main || die 1', 'true || die 1')]),
 ("X07_push_despite_preflight", [('if [ "$PREFLIGHT_BLOCKED" -gt 0 ]; then action[i]=not-pushed-preflight', 'if false; then action[i]=not-pushed-preflight')]),
 # PORTED (r4): interpret-trailers now closes the lock fd
 ("X08_ignore_interpret_failure", [('''--trailer "Roadmap-Item: $id" 9>&-) || {''', '''--trailer "Roadmap-Item: $id" 9>&-) || true; false && {''')]),
 # PORTED: hooks are now disabled in g(); the mutation runs the mint commit through plain git with hooks
 ("X09_mint_commit_with_hooks", [('    g commit --no-verify -q \\\n', '    git -C "$CLONE" commit -q \\\n')]),
 ("X09b_merge_with_hooks", [('if ! g merge --no-verify -q', 'if ! git -C "$CLONE" merge -q')]),
 ("X10_no_need_val", [('  need_val "$@"\n', '  [ $# -ge 2 ] || exit 1\n')]),
 ("X11_fetch_stderr_shown", [('"refs/heads/main:refs/remotes/${R_NAMES[$i]}/main" 2>>"$ERRLOG"', '"refs/heads/main:refs/remotes/${R_NAMES[$i]}/main"')]),
 ("X12_key_prefix_ignored", [('KEY_PREFIX=${KEY_PREFIX:-CON}\n', 'KEY_PREFIX=CON\n')]),
 ("X13_rewrite_anywhere", [('if [ "$start" -ge 1 ] && [ "$i" -ge "$start" ] && is_ri_line "$line"; then', 'if is_ri_line "$line"; then')]),
 ("X14_no_prepare_post_check", [('  g merge-base --is-ancestor "$before" main || die 1 "internal: main was rewritten"\n  check_trailers "$main_before..main"', '  g merge-base --is-ancestor "$before" main || die 1 "internal: main was rewritten"')]),
 ("X15_signature_never_recorded", [('then sig=yes; else sig=no; fi', 'then sig=no; else sig=no; fi')]),
 ("X16_publish_key_mismatch_allowed", [('if [ "$KEY_GIVEN" = 1 ] && [ "$KEY_PREFIX" != "$key" ]; then', 'if false; then')]),
 ("X17_key_prefix_unvalidated", [('[[ "$KEY_PREFIX" =~ ^[A-Z][A-Z0-9]*$ ]] || die 2', 'true || die 2')]),
 ("X18_rerun_hint_dropped", [(' (prepare pushes nothing; to retry, remove that scratch clone with a guarded delete and run prepare again)', '')]),
 ("X19_empty_mirror_msg_dropped", [(' (unreachable, or it has no main branch: an empty mirror must be seeded first; git\'s message is in $ERRLOG)', '')]),
 ("X20_no_main_counts_as_ok", [('elif [ -z "${before[i]}" ]; then action[i]=refused-no-main-or-unreadable; PREFLIGHT_BLOCKED=$((PREFLIGHT_BLOCKED + 1))', 'elif [ -z "${before[i]}" ]; then action[i]=push')]),
 # ---------------------------------------------------------------- N (19 reviewer mutants)
 # PORTED (N01, N26): the push line now carries --no-verify
 ("N01_force_via_var", [(PUSH_NEW, 'elif PL=+; g -c push.followTags=false -c push.recurseSubmodules=no push -q --no-verify --no-follow-tags "${R_NAMES[$i]}" "${PL}main:refs/heads/main" 2>>"$ERRLOG"; then')]),
 ("N02_preflight_ancestry_reversed", [('&& g merge-base --is-ancestor "${before[i]}" "$local_main"; then action[i]=push', '&& g merge-base --is-ancestor "$local_main" "${before[i]}"; then action[i]=push')]),
 ("N08_whole_msg_is_trailer_block", [('      if [[ "${L[i]}" =~ ^[[:space:]]*$ ]]; then start=$((i + 1)); break; fi', '      start=1; break')]),
 ("N11_author_date_unix_no_tz", [('GIT_AUTHOR_DATE=$(g log -1 --format=%aD "$c")', 'GIT_AUTHOR_DATE=@$(g log -1 --format=%at "$c")')]),
 ("N13_mint_runs_in_workdir", [('out=$(cd "$CLONE" && bash -c "$MINT_CMD"', 'out=$(cd "$WORKDIR" && bash -c "$MINT_CMD"')]),
 # PORTED (r4): the check also refuses a (dangling) symlink
 ("N15_no_existing_clone_refusal", [('[ ! -e "$CLONE" ] && [ ! -L "$CLONE" ] || die 2 "clone path already exists', 'true || die 2 "clone path already exists')]),
 ("N17_newest_tip_not_chosen", [('elif g merge-base --is-ancestor "$tip" "$s"; then tip=$s', 'elif g merge-base --is-ancestor "$tip" "$s"; then :')]),
 ("N20_no_space_before_colon", [('^roadmap-item[[:space:]]*$', '^roadmap-item$')]),
 ("N21_placeholder_unanchored", [('PLACEHOLDER_RE=${PLACEHOLDER_RE:-"^(${KEY_PREFIX}-050|${KEY_PREFIX}-PENDING-[A-Za-z0-9._-]*|<TO-BE-MINTED[^>]*>)\\$"}', 'PLACEHOLDER_RE=${PLACEHOLDER_RE:-"(${KEY_PREFIX}-050|${KEY_PREFIX}-PENDING-[A-Za-z0-9._-]*|<TO-BE-MINTED[^>]*>)"}')]),
 ("N22_no_on_main_check_publish", [('[ "$(g rev-parse --abbrev-ref HEAD)" = main ] || die 2 "clone is not on main"', 'true')]),
 ("N24_readback_nonempty_is_pass", [('if [ "$after" = "$local_main" ]; then result=PASS', 'if [ -n "$after" ]; then result=PASS')]),
 ("N26_push_stderr_shown", [(PUSH_NEW, 'elif g -c push.followTags=false -c push.recurseSubmodules=no push -q --no-verify --no-follow-tags "${R_NAMES[$i]}" "main:refs/heads/main"; then')]),
 ("N27_lsremote_stderr_shown", [('remote_main() { { g ls-remote --heads "$1" refs/heads/main 2>>"$ERRLOG" || true; }', 'remote_main() { { g ls-remote --heads "$1" refs/heads/main || true; }')]),
 ("N38_parent_change_ignored", [('[ "${MAP[$p]}" = "$p" ] || parents_changed=1', 'true')]),
 ("N41_bundle_verify_ignored", [('g bundle verify -q "$BUNDLE" >/dev/null 2>&1 || die 1 "git bundle verify failed"', 'true')]),
 ("N48_divider_honoured", [('git interpret-trailers --no-divider --parse', 'git interpret-trailers --parse'), ('git interpret-trailers --no-divider --trailer', 'git interpret-trailers --trailer')]),
 ("N52_state_key_default_silent_publish_any", [('  if [ "$KEY_GIVEN" = 1 ] && [ "$KEY_PREFIX" != "$key" ]; then', '  if false; then')]),
 ("N53_landed_head_from_vehicle_head", [('landed=$(state_get landed_vehicle_head)', 'landed=$(state_get main_before)')]),
 # PORTED: the "commit only if something changed" branch is gone; the mutation drops the empty-mint refusal
 ("N54_mint_noop_commit_skipped_silently", [('    [ -n "$(g status --porcelain --untracked-files=all)" ] \\\n      || die 1', '    true \\\n      || die 1')]),
 # ---------------------------------------------------------------- Y (new, round 3)
 ("Y01_no_fetch_url_check", [('[ "$got" = "$want" ] || die 2', 'true || die 2')]),
 ("Y02_no_push_url_check", [('[ "$push" = "$want" ] || die 2', 'true || die 2')]),
 ("Y03_publish_skips_url_check", [('do_publish() {\n  need_state\n  assert_remote_urls\n', 'do_publish() {\n  need_state\n')]),
 ("Y04_verify_skips_url_check", [('do_verify() {\n  need_state\n  assert_remote_urls\n', 'do_verify() {\n  need_state\n')]),
 ("Y05_no_mirror_key_check", [('for key in mirror receivepack uploadpack; do', 'for key in; do')]),
 # PORTED (r4): the anchor also occurs in publish now; the mint check is selected
 ("Y06_untracked_mint_files_ignored", [('[ -n "$(g status --porcelain --untracked-files=all)" ]', '[ -n "$(g status --porcelain --untracked-files=no)" ]')]),
 ("Y07_no_id_in_change_check", [('[ "$found_id" = 1 ] || die 1', 'true || die 1')]),
 ("Y08_no_head_moved_check", [('[ "$(g rev-parse HEAD)" = "$head0" ] && [ "$(g rev-parse --abbrev-ref HEAD)" = main ] \\\n      || die 1', 'true \\\n      || die 1')]),
 ("Y09_verify_cmd_status_ignored", [('|| die 1 "id verify command failed for $1 (the engine does not confirm the id)"', '|| true')]),
 ("Y10_verify_cmd_output_ignored", [('|| die 1 "id verify command did not print $1 (the engine does not confirm the id)"', '|| true')]),
 ("Y11_range_from_state_file", [('    check_trailers main --not "${before[@]}"\n', '    check_trailers "$(state_get main_before)..main"\n')]),
 ("Y12_no_main_before_ref_check", [('[ "$r" = "$main_before" ] || die 2', 'true || die 2')]),
 ("Y13_no_landed_ref_check", [('[ "$r" = "$landed" ] || die 2', 'true || die 2')]),
 ("Y14_no_vehicle_ref_check", [('[ "$r" = "$vehicle" ] || die 2', 'true || die 2')]),
 ("Y15_no_landed_tree_check", [('''    || die 2 "prepare state does not match git: the landed head's tree differs from the vehicle tree"''', '''    || true''')]),
 ("Y16_no_lock", [('flock -n 9 || die 2', 'true || die 2')]),
 ("Y17_lock_per_process_file", [('exec 9>>"$WORKDIR/.land_vehicle.lock"', 'exec 9>>"$WORKDIR/.land_vehicle.lock.$$"')]),
 ("Y18_clone_name_slash_allowed", [('[[ "$CLONE_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]', '[[ "$CLONE_NAME" =~ ^[A-Za-z0-9./_-]+$ ]]')]),
 ("Y19_clone_name_dotdot_allowed", [(' && [[ "$CLONE_NAME" != *..* ]] \\\n', ' \\\n')]),
 # PORTED (r4): g() now closes the lock fd
 ("Y20_g_without_hookspath", [('g() { git -c core.hooksPath=/dev/null -c core.fsmonitor=false -C "$CLONE" "$@" 9>&-; }', 'g() { git -c core.fsmonitor=false -C "$CLONE" "$@" 9>&-; }')]),
 ("Y21_push_without_no_verify", [(PUSH_NEW, 'elif g -c push.followTags=false -c push.recurseSubmodules=no push -q --no-follow-tags "${R_NAMES[$i]}" "main:refs/heads/main" 2>>"$ERRLOG"; then')]),
 ("Y22_extra_delete_push", [(PUSH_NEW, 'elif g push -q --no-verify "${R_NAMES[$i]}" ":refs/heads/stale" 2>>"$ERRLOG" || true; g -c push.followTags=false -c push.recurseSubmodules=no push -q --no-verify --no-follow-tags "${R_NAMES[$i]}" "main:refs/heads/main" 2>>"$ERRLOG"; then')]),
 ("Y23_init_without_hookspath", [('git -c core.hooksPath=/dev/null init -q -b main "$CLONE"', 'git init -q -b main "$CLONE"')]),
 ("Y24_mint_keeps_lock_fd", [('out=$(cd "$CLONE" && bash -c "$MINT_CMD" 9>&-)', 'out=$(cd "$CLONE" && bash -c "$MINT_CMD")')]),
 ("Y25_verify_needs_no_state", [('do_verify() {\n  need_state\n', 'do_verify() {\n  [ -d "$CLONE/.git" ] || die 2 "no clone at $CLONE"\n')]),
 ("Y26_help_only_as_first_arg", [('for a in "$@"; do case "$a" in -h|--help) usage ;; esac; done', 'case "${1:-}" in -h|--help) usage ;; esac')]),
 ("Y27_trailer_check_skipped_when_up_to_date", [('  if [ "$mode" = push ] && [ "$PREFLIGHT_BLOCKED" -eq 0 ]; then', '  if [ "$mode" = push ] && [ "$PREFLIGHT_BLOCKED" -eq 0 ] && [ "${#R_NAMES[@]}" -lt 0 ]; then')]),
 # ---------------------------------------------------------------- Z (new, round 4)
 ("Z01_no_env_scrub", [('lander_scrub_git_env\nlander_exit() {', 'lander_exit() {')]),
 ("Z02_namespace_kept", [('GIT_NAMESPACE GIT_QUARANTINE_PATH GIT_CURL_VERBOSE', 'GIT_QUARANTINE_PATH GIT_CURL_VERBOSE')]),
 ("Z03_trace_kept", [('GIT_PUSH_OPTION_*|GIT_TRACE*) unset', 'GIT_PUSH_OPTION_*) unset')]),
 ("Z04_config_count_kept", [('GIT_CONFIG_KEY_*|GIT_CONFIG_VALUE_*|', ''), ('GIT_CONFIG GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT', 'GIT_CONFIG GIT_CONFIG_PARAMETERS'), ('[[ "$v" =~ ^GIT_[A-Z_]+$ ]] && unset "$v"', '[[ "$v" =~ ^GIT_[A-Z_]+$ ]] && [ "$v" != GIT_CONFIG_COUNT ] && unset "$v"')]),
 ("Z05_g_keeps_lock_fd", [('-C "$CLONE" "$@" 9>&-; }', '-C "$CLONE" "$@"; }')]),
 ("Z06_push_follows_tags", [(PUSH_NEW, 'elif g push -q --no-verify "${R_NAMES[$i]}" "main:refs/heads/main" 2>>"$ERRLOG"; then')]),
 ("Z07_publish_hides_untracked", [('[ -z "$(g status --porcelain --untracked-files=all)" ] || die 2', '[ -z "$(g status --porcelain)" ] || die 2')]),
 ("Z08_no_tracker_path_check", [('&& tracker_path "$f"; }', '; }')]),
 ("Z09_deletion_allowed", [('[[ "$st" == [AM] ]]', '[[ "$st" == [AMD] ]]')]),
 ("Z10_no_absence_check", [('        if id_seen_before "$id" "$blob"; then', '        if false; then')]),
 ("Z11_binary_absence_token_only", [('    grep -aFq -- "$1" "$2"\n', '    grep -aEq -- "$1([^0-9]|\\$)" "$2"\n')]),
 ("Z12_remotes_line_echoed", [("want exactly two fields 'name url' (the line is not shown, it may hold a credential)", "bad line '$name $url $rest'")]),
 ("Z13_no_remote_name_check", [('    [[ "$name" =~ $NAME_RE ]] \\\n      || die 2', '    true \\\n      || die 2')]),
 ("Z14_no_LANDER_REMOTES_name_check", [('[[ "$_n" =~ $NAME_RE ]] || die 2', 'true || die 2')]),
 ("Z15_dangling_symlink_allowed", [(' && [ ! -L "$CLONE" ] || die 2', ' || die 2')]),
 ("Z16_workdir_dash_allowed", [('[[ "$WORKDIR" != -* ]] || die 2', 'true || die 2')]),
 ("Z17_cdpath_kept", [('\nunset CDPATH\n', '\n')]),
 ("Z18_no_warn_rows", [('        warns+=("${R_NAMES[$i]}"', '        : || warns+=("${R_NAMES[$i]}"')]),
 ("Z19_no_mode_check", [('[[ "$mode" == 100644 || "$mode" == 100755 ]] || die 1', 'true || die 1')]),
 ("Z20_no_commit_namestatus_check", [('cmp -s "$chz" "$blob" || die 1', 'true || die 1')]),
 ("Z21_no_exit_status_mapping", [('\ntrap lander_exit EXIT\n', '\n')]),
 ("Z22_mint_changes_not_recorded", [("    printf 'status\\tpath\\n' > \"$EVIDENCE_DIR/mint_changes.tsv\"\n", "    :\n")]),
 ("Z23_presence_on_worktree_not_index", [('g cat-file blob ":$f" > "$blob" || die 1 "cannot read the staged $f"', 'cp "$CLONE/$f" "$blob" || die 1 "cannot read the staged $f"')]),
 ("Z24_url_dash_allowed", [('[[ "$url" != -* ]] || die 2', 'true || die 2')]),
 ("Z25_warn_from_intersection", [('      rows=$(untrailered main --not "${before[i]}")', '      rows=$(untrailered main --not "${before[@]}")')]),
]
os.makedirs(outdir, exist_ok=True)
names = []
for name, edits in M:
    t = s
    okk = True
    for a, b in edits:
        if t.count(a) != 1:
            print(f"NOAPPLY {name} count={t.count(a)} anchor={a[:60]!r}"); okk = False; break
        t = t.replace(a, b)
    if not okk:
        continue
    d = os.path.join(outdir, name); os.makedirs(d, exist_ok=True)
    p = os.path.join(d, "land_vehicle.sh"); open(p, "w").write(t); os.chmod(p, 0o755)
    names.append(name)
print(f"GENERATED {len(names)} of {len(M)}")
