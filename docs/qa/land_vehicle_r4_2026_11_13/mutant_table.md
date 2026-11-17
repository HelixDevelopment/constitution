| Set | Mutant | Verdict | Killed by (first FAIL) |
|---|---|---|---|
| producer | M01_no_sha_check | KILLED | T6 wrong bundle sha256 refused |
| producer | M02_no_headref_check | KILLED | T7 head not a ref tip in the bundle refused |
| producer | M03_no_diverge_refusal | KILLED | T9 diverged remote mains refused |
| producer | M04_no_clonename_check | KILLED | T10 mint outside a 'constitution' dir refused |
| producer | M05_no_dirty_check | KILLED | T11 dirty tree refused |
| producer | M06_no_ff_precheck | KILLED | T4 non-ff remote refused at preflight |
| producer | M07_drop_author_date | KILLED | T1 prepare exits 0 |
| producer | M08_drop_author_name | KILLED | S5d author name, email and date preserved |
| producer | M09_no_append_when_missing | KILLED | S2-S5 prepare exits 0 |
| producer | M10_no_parent_remap | KILLED | T2 independent tree re-check |
| producer | M11_loose_id_re | KILLED | M11 mint whose last line is not an id refused |
| producer | M12_no_already_on_main | KILLED | M12 vehicle already on main refused |
| producer | M13b_no_exactly_once | KILLED | M13 duplicate remote name refused |
| producer | M13_no_remote_set_check | KILLED | M13 extra remote name refused |
| producer | M14_merge_drops_main | KILLED | T1 prepare exits 0 |
| producer | M15_no_base_check_publish | KILLED | M15 publish refuses a main without the prepared base |
| producer | M16_mint_no_commit | KILLED | T1 prepare exits 0 |
| producer | M17_drop_coauthored | KILLED | S5a missing trailer appended, Co-Authored-By kept |
| producer | N01_force_via_var | KILLED | SH1 T1 publish made 9 plain pushes |
| producer | N02_preflight_ancestry_reversed | KILLED | T1 publish exits 0 |
| producer | N08_whole_msg_is_trailer_block | KILLED | S2-S5 prepare exits 0 |
| producer | N11_author_date_unix_no_tz | KILLED | S5d author name, email and date preserved |
| producer | N13_mint_runs_in_workdir | KILLED | T1 prepare exits 0 |
| producer | N15_no_existing_clone_refusal | KILLED | S7 re-run of prepare message |
| producer | N17_newest_tip_not_chosen | KILLED | T9 diverged remote mains refused |
| producer | N20_no_space_before_colon | KILLED | S2-S5 prepare exits 0 |
| producer | N21_placeholder_unanchored | KILLED | S5g real id CON-0501 kept |
| producer | N22_no_on_main_check_publish | KILLED | U18 publish refuses a clone not on main |
| producer | N24_readback_nonempty_is_pass | KILLED | T3 rejecting remote reported FAIL |
| producer | N26_push_stderr_shown | KILLED | U19 push stderr |
| producer | N27_lsremote_stderr_shown | KILLED | U19 ls-remote stderr |
| producer | N38_parent_change_ignored | KILLED | S2-S5 prepare exits 0 |
| producer | N41_bundle_verify_ignored | KILLED | U20 bundle with a missing prerequisite refused by git bundle verify |
| producer | N48_divider_honoured | KILLED | S5h --- line in body |
| producer | N52_state_key_default_silent_publish_any | KILLED | L6 publish with a key prefix other than the prepared one refused |
| producer | N53_landed_head_from_vehicle_head | KILLED | T1 publish exits 0 |
| producer | N54_mint_noop_commit_skipped_silently | KILLED | U4 mint that prints an id but changes nothing is refused |
| producer | X01_no_cr_strip | KILLED | S3 CRLF trailer replaced, CR stripped |
| producer | X02_no_to_be_minted | KILLED | S2-S5 prepare exits 0 |
| producer | X03_case_sensitive_key | KILLED | S2-S5 prepare exits 0 |
| producer | X04_no_dedupe | KILLED | S2-S5 prepare exits 0 |
| producer | X05_no_publish_trailer_check | KILLED | S12 untrailered commit refused at publish |
| producer | X06_no_landed_check | KILLED | S6 publish refuses when the landed vehicle is not on main |
| producer | X07_push_despite_preflight | KILLED | T4 no remote moved |
| producer | X08_ignore_interpret_failure | KILLED | X8b interpret-trailers append failure aborts prepare |
| producer | X09b_merge_with_hooks | KILLED | S10 ambient hooks |
| producer | X09_mint_commit_with_hooks | KILLED | S10 ambient hooks |
| producer | X10_no_need_val | KILLED | L4 missing option value is a usage error |
| producer | X11_fetch_stderr_shown | KILLED | L5 failing fetch names the remote, not its URL |
| producer | X12_key_prefix_ignored | KILLED | L6 --key-prefix ABC |
| producer | X13_rewrite_anywhere | KILLED | S2-S5 prepare exits 0 |
| producer | X14_no_prepare_post_check | KILLED | X14 two distinct ids in one commit refused at prepare |
| producer | X15_signature_never_recorded | KILLED | S5d dropped signature recorded in evidence |
| producer | X16_publish_key_mismatch_allowed | KILLED | L6 publish with a key prefix other than the prepared one refused |
| producer | X17_key_prefix_unvalidated | KILLED | L6 malformed key prefix refused |
| producer | X18_rerun_hint_dropped | KILLED | S7 re-run of prepare message |
| producer | X19_empty_mirror_msg_dropped | KILLED | S11 empty mirror refused at prepare |
| producer | X20_no_main_counts_as_ok | KILLED | P1 remote without main refused at preflight |
| producer | Y01_no_fetch_url_check | KILLED | U1 publish refuses a clone whose origin URL differs from --remotes-file |
| producer | Y02_no_push_url_check | KILLED | U3 publish refuses a push URL other than the declared one |
| producer | Y03_publish_skips_url_check | KILLED | U1 publish refuses a clone whose origin URL differs from --remotes-file |
| producer | Y04_verify_skips_url_check | KILLED | U1 verify refuses the URL mismatch too |
| producer | Y05_no_mirror_key_check | KILLED | U3b publish refuses remote.<name>.mirror |
| producer | Y06_untracked_mint_files_ignored | KILLED | T1 prepare exits 0 |
| producer | Y07_no_id_in_change_check | KILLED | U6 mint whose changes do not contain the id is refused |
| producer | Y08_no_head_moved_check | KILLED | U7 mint that commits by itself is refused |
| producer | Y09_verify_cmd_status_ignored | KILLED | U8b --item-id the engine does not know is refused |
| producer | Y10_verify_cmd_output_ignored | KILLED | U8c an engine read that does not print the id is refused |
| producer | Y11_range_from_state_file | KILLED | U9b untrailered commit refused even with state and ref edited |
| producer | Y12_no_main_before_ref_check | KILLED | U9 an edited prepare state is refused |
| producer | Y13_no_landed_ref_check | KILLED | U9c edited landed_vehicle_head refused |
| producer | Y14_no_vehicle_ref_check | KILLED | U9d edited vehicle_head refused |
| producer | Y15_no_landed_tree_check | KILLED | U9e landed head whose tree is not the vehicle tree refused |
| producer | Y16_no_lock | KILLED | U11 prepare refused while another run holds the workdir lock |
| producer | Y17_lock_per_process_file | KILLED | U11 prepare refused while another run holds the workdir lock |
| producer | Y18_clone_name_slash_allowed | KILLED | U12 --clone-name 'a/b' refused |
| producer | Y19_clone_name_dotdot_allowed | KILLED | U12 --clone-name 'a..b' refused |
| producer | Y20_g_without_hookspath | KILLED | U13 ambient hooks |
| producer | Y21_push_without_no_verify | KILLED | SH1 T1 publish made 9 plain pushes |
| producer | Y22_extra_delete_push | KILLED | SH1 T1 publish made 9 plain pushes |
| producer | Y23_init_without_hookspath | KILLED | U13 ambient hooks |
| producer | Y24_mint_keeps_lock_fd | KILLED | U21 mint child holds the lock |
| producer | Y25_verify_needs_no_state | KILLED | U15 verify without prepare state refused |
| producer | Y26_help_only_as_first_arg | KILLED | U14 prepare --help |
| producer | Y27_trailer_check_skipped_when_up_to_date | KILLED | S12 untrailered commit refused at publish |
| producer | Z01_no_env_scrub | KILLED | V2a exported GIT_DIR |
| producer | Z02_namespace_kept | KILLED | V2d exported GIT_NAMESPACE |
| producer | Z03_trace_kept | KILLED | V2g GIT_TRACE |
| producer | Z04_config_count_kept | KILLED | V2e env config injection |
| producer | Z05_g_keeps_lock_fd | KILLED | V5 lock fd inherited by a git child |
| producer | Z06_push_follows_tags | KILLED | SH1 T1 publish made 9 plain pushes |
| producer | Z07_publish_hides_untracked | KILLED | V7 an untracked file is seen although status.showUntrackedFiles=no |
| producer | Z08_no_tracker_path_check | KILLED | V8b a mint that writes outside LANDER_TRACKER_PATHS is refused |
| producer | Z09_deletion_allowed | KILLED | V8d deleting a file that IS a tracker path is still refused as a deletion |
| producer | Z10_no_absence_check | KILLED | V3a a mint that prints a PRE-EXISTING id is refused |
| producer | Z11_binary_absence_token_only | KILLED | V3e binary tracker: CON-777 inside CON-7775 counts as already there (fail closed) |
| producer | Z12_remotes_line_echoed | KILLED | V1 credential token leaked |
| producer | Z13_no_remote_name_check | KILLED | V1 a remote name that is not a plain name is refused by line number |
| producer | Z14_no_LANDER_REMOTES_name_check | KILLED | V14 LANDER_REMOTES holding 'a/b' is refused |
| producer | Z15_dangling_symlink_allowed | KILLED | V12 a dangling symlink at the clone path is refused (exit 2, not a raw git code) |
| producer | Z16_workdir_dash_allowed | KILLED | V11 --workdir '-' refused |
| producer | Z17_cdpath_kept | KILLED | V11 CDPATH |
| producer | Z18_no_warn_rows | KILLED | V4 U10 WARN rows |
| producer | Z19_no_mode_check | KILLED | V8c a mint that leaves the tracker path as a symlink is refused |
| producer | Z20_no_commit_namestatus_check | KILLED | V15 a mint commit that differs from the recorded mint changes is refused |
| producer | Z21_no_exit_status_mapping | KILLED | V13 a failing git call exits 1 (not git's 128) with a message |
| producer | Z22_mint_changes_not_recorded | KILLED | V8c T1 mint changes recorded in evidence |
| producer | Z23_presence_on_worktree_not_index | KILLED | V16 an id that a clean filter strips from the staged tracker is refused |
| producer | Z24_url_dash_allowed | KILLED | V1e a URL starting with '-' is refused by line number |
| producer | Z25_warn_from_intersection | KILLED | V4 U10 WARN rows |
| reviewer | MR01_push_url_first_only | KILLED | V9a a second push URL after the declared one is refused |
| reviewer | MR02_only_mirror_key_checked | KILLED | V9b remote.origin.receivepack set in the clone is refused |
| reviewer | MR03_id_in_text_substring | KILLED | V3c id CON-77 is not found inside CON-777 (token match) |
| reviewer | MR04_no_branch_check_after_mint | KILLED | V9c a mint that switches the branch is refused |
| reviewer | MR05_publish_dirty_ignores_untracked | KILLED | T11 dirty tree refused |
| reviewer | MR07_trailer_range_first_remote_only | KILLED | U10 already-published commit |
| reviewer | MR08_pushed_is_pass_without_readback | KILLED | V9d post-receive rewind |
| reviewer | MR09_shared_lock | KILLED | U11b concurrent prepares (got 0/1) |
| reviewer | MR12_verify_id_substring | KILLED | V3d an engine read printing CON-7770 does not confirm CON-777 |
| reviewer | MR15_newest_tip_keeps_older | KILLED | T9 diverged remote mains refused |
| reviewer | MR20_rejected_reported_as_pushed | KILLED | T3 rejecting remote reported FAIL |
| reviewer | MR21_remotes_extra_field_ok | KILLED | V1 a remotes line with a third field is refused (line 10) |
| reviewer | MR22_url_prefix_match | KILLED | V9e a clone URL that merely starts with the declared URL is refused |
