#!/usr/bin/env bash
# tests/layout/test_layout_mutations.sh — paired §1.1 mutations for the layout
# hardening. Each mutation reverts ONE fix (the file's HEAD version, or a
# targeted one-line edit) inside a sandbox COPY of the tree, runs the layout
# suite that guards that fix with LAYOUT_SRC_ROOT pointing at the copy, and
# requires that suite to FAIL. A surviving mutation is a FAIL of this file.
# A control run of every suite on the unmutated copy must PASS first.
# The real tree is never modified.
# Usage: bash tests/layout/test_layout_mutations.sh
#
# Kinds of mutation (mutate ID SUITE KIND PATH ...):
#   pre  PATH           revert PATH to its PRE-HARDENING content (git rev PRE_REV, default
#                       a0609ec^ = the parent of the commit that landed the layout hardening).
#                       A plain 'git show HEAD:PATH' is a no-op: HEAD already holds the fixes.
#   sed  PATH EXPR      sed edit of the sandbox copy
#   repl PATH OLD NEW   literal replacement of exactly ONE occurrence
# Every mutant MUST differ from the unmutated sandbox copy; an unchanged mutant is reported
# 'BROKEN <id> NOOP' and counts as a FAIL (never a silent 'survived').
#
# Knobs (environment):
#   MUT_ONLY=<ERE>      run only the mutations whose id matches (e.g. 'M0[2-9]|M1[0-2]').
#   MUT_SHARD=<i>/<n>   run only every n-th selected mutation, starting at index i (0-based);
#                       lets one logical run be split over several short jobs.
#   CONTROL_ALL=1       run the control of EVERY suite up front (default: lazily, once per
#                       distinct guarding suite, cached for the whole run).
#   MUT_SUITE_TIMEOUT=<s>  per-suite-run timeout (default 900); a timeout is a non-attributable FAIL.
#   PRE_REV=<rev>       pre-hardening revision for kind 'pre' (default a0609ec^).
# Cost: test_round7_ambient ~380 s and test_round8_git_env ~200 s PER RUN; the full set
# (every mutation x its suite) therefore does NOT fit one 1500 s job: split it with MUT_ONLY
# or MUT_SHARD. The mutants of the template/hook/script group (M01-M12) fit one job.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REAL="$(cd "$HERE/../.." && pwd)"
. "$REAL/scripts/lib/safe_rm.sh"
SB="$(mktemp -d "${TMPDIR:-/tmp}/layout_mut.XXXXXX")"
[ -n "$SB" ] && [ -d "$SB" ] || { echo "mktemp failed"; exit 2; }
# Cleanup must also run on TERM/INT/HUP (a bash killed by an untrapped signal skips the EXIT
# trap and leaks the sandbox). safe_rm_rf is never weakened; if it refuses, say so loudly and
# fall back to a guarded delete of exactly our own mktemp name.
cleanup() {
    local sb="${SB:?}"
    safe_rm_rf "$sb" 2>/dev/null && return 0
    case "$sb" in
        "${TMPDIR:-/tmp}"/layout_mut.??????) [ -d "$sb" ] && [ ! -L "$sb" ] && rm -rf -- "${sb:?}" ;;
        *) echo "cleanup: refusing to delete unexpected path $sb" >&2 ;;
    esac
}
trap cleanup EXIT
# Stop OUR OWN suite process group (setsid below makes pgid == pid) before exiting, so a TERM
# does not wait for a ~380 s suite. §11.4.263: only a pgid that is an int > 1 AND equals the pid
# we started is ever signalled.
SUITE_PID=""
stop_suite() {
    local pid="${SUITE_PID:-}" pg
    [ -n "$pid" ] && [ "$pid" -gt 1 ] 2>/dev/null || return 0
    pg="$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')"
    if [ -n "$pg" ] && [ "$pg" -gt 1 ] 2>/dev/null && [ "$pg" = "$pid" ]; then kill -TERM -- "-$pg" 2>/dev/null; fi
}
trap 'stop_suite; exit 143' TERM
trap 'stop_suite; exit 130' INT HUP
SRC="$SB/src"
mkdir -p "$SRC/tests"
for p in scripts templates .claude-plugin plugins actions skills Constitution.md CLAUDE.md AGENTS.md; do
    cp -a "$REAL/$p" "$SRC/$p"
done
cp -a "$REAL/tests/layout" "$SRC/tests/layout"
safe_rm_rf "$SRC/scripts/fastcycle/consumers/__pycache__" 2>/dev/null || true

PASS=0; FAIL=0; MUT_IDX=0
PRE_REV="${PRE_REV:-a0609ec^}"
SUITE_TO="${MUT_SUITE_TIMEOUT:-900}"
run_suite() {
    local rc
    LAYOUT_SRC_ROOT="$SRC" setsid timeout -k 10 "$SUITE_TO" nice -n 15 bash "$SRC/tests/layout/$1.sh" >"$SB/last.out" 2>&1 &
    SUITE_PID=$!
    wait "$SUITE_PID"; rc=$?
    SUITE_PID=""
    return "$rc"
}

# --- control: the guarding suite passes on the unmutated copy (once per suite, cached) ---
declare -A CONTROL=()
control() { # control SUITE -> 0 when green
    local s="$1"
    if [ -z "${CONTROL[$s]:-}" ]; then
        if run_suite "$s"; then CONTROL[$s]=ok; PASS=$((PASS+1)); echo "PASS control $s"
        else CONTROL[$s]=red; FAIL=$((FAIL+1)); echo "FAIL control $s (its mutations below are meaningless)"; tail -5 "$SB/last.out"; fi
    fi
    [ "${CONTROL[$s]}" = ok ]
}
SUITES="test_constitution_layout_lib test_setup_layout test_post_merge_layout test_guard_evidence_layout
test_canonical_root_layout test_fastcycle_layout test_multitrack_sync_layout test_plugin_hint_layout test_templates_layout
test_pending_update_layout test_deps_manifest_layout test_consumer_trust_lock test_round4_hardening test_round6_hardening test_round7_ambient test_round8_git_env"
if [ "${CONTROL_ALL:-0}" = 1 ] && [ -z "${MUT_ONLY:-}" ]; then for s in $SUITES; do control "$s"; done; fi

# selected ID -> 0 when this mutation should run (MUT_ONLY filter, then MUT_SHARD split)
selected() {
    if [ -n "${MUT_ONLY:-}" ] && ! [[ "$1" =~ $MUT_ONLY ]]; then return 1; fi
    if [ -n "${MUT_SHARD:-}" ]; then
        local i="${MUT_SHARD%/*}" n="${MUT_SHARD#*/}" k=$MUT_IDX
        MUT_IDX=$((MUT_IDX+1))
        [ $((k % n)) -eq "$i" ] || return 1
    fi
    return 0
}

# mutate ID SUITE KIND ARG... ; KIND = pre PATH | sed PATH EXPR | repl PATH OLD NEW
mutate() {
    local id="$1" suite="$2" kind="$3" path="$4" bak="$SB/bak"
    selected "$id" || return 0
    control "$suite" || { echo "SKIP $id (control of $suite is red)"; return 0; }
    cp -a "$SRC/$path" "$bak"
    case "$kind" in
        pre)  if ! git -C "$REAL" show "$PRE_REV:$path" > "$SRC/$path" 2>/dev/null; then
                  FAIL=$((FAIL+1)); echo "BROKEN $id: $path not present at $PRE_REV"; cp -a "$bak" "$SRC/$path"; return; fi ;;
        sed)  sed -i "$5" "$SRC/$path" ;;
        repl) # literal replacement of exactly ONE occurrence of $5 by $6
              if ! python3 - "$SRC/$path" "$5" "$6" <<'PYREPL'
import sys
p, old, new = sys.argv[1:4]
s = open(p).read()
if s.count(old) != 1:
    sys.exit(1)
open(p, "w").write(s.replace(old, new))
PYREPL
              then FAIL=$((FAIL+1)); echo "BROKEN $id: replacement text not found exactly once in $path"; cp -a "$bak" "$SRC/$path"; return; fi ;;
    esac
    if cmp -s "$bak" "$SRC/$path"; then
        FAIL=$((FAIL+1)); echo "BROKEN $id NOOP: the mutant is identical to the unmutated $path"; cp -a "$bak" "$SRC/$path"; return; fi
    if run_suite "$suite"; then
        FAIL=$((FAIL+1)); echo "FAIL $id SURVIVED ($suite still green)"
    else
        # A kill is valid only when the suite ran to its summary line and a NAMED
        # assertion failed; a crash / empty summary is not attributable (§11.4.102).
        sumline="$(grep -E ': PASS=[0-9]+ FAIL=[0-9]+$' "$SB/last.out" | tail -1)"
        firstfail="$(grep -E '^FAIL: ' "$SB/last.out" | head -1 | cut -c7-70)"
        if [ -n "$sumline" ] && [ -n "$firstfail" ]; then
            PASS=$((PASS+1)); echo "PASS $id killed by [$firstfail] ($sumline)"
        else
            FAIL=$((FAIL+1)); echo "FAIL $id NOT-ATTRIBUTABLE (suite failed without a summary line or a named FAIL: crash/timeout)"
            tail -3 "$SB/last.out" | cut -c1-200
        fi
    fi
    cp -a "$bak" "$SRC/$path"
}

mutate M01-lib-legacy-only   test_constitution_layout_lib sed scripts/lib/constitution_layout.sh \
    's|^CONSTITUTION_LAYOUT_RELS=.*|CONSTITUTION_LAYOUT_RELS="constitution"|'
mutate M02-setup-revert      test_setup_layout          pre scripts/setup.sh
HL=scripts/lib/hook_install.sh   # the shared install/backup/scope implementation (round 4)
mutate M03-setup-no-backup   test_setup_layout          repl "$HL" \
    'cp -p "$dst" "$bpath" && cmp -s "$dst" "$bpath" || return 1' 'true'
mutate M04-postmerge-revert  test_post_merge_layout     pre scripts/hooks/post-merge
mutate M05-postmerge-silent  test_post_merge_layout     sed  scripts/hooks/post-merge 's/^warn() { printf .*/warn() { :; }/'
mutate M06-guard-revert      test_guard_evidence_layout pre scripts/hooks/guard-evidence-store-write.sh
mutate M07-gate-auto-standalone test_canonical_root_layout repl scripts/gates/cm_canonical_root_clarity.sh \
    'if [ -z "$consumer_root" ] && [ "$standalone_decl" = "1" ]; then' 'if [ -z "$consumer_root" ]; then'
mutate M07b-gate-heuristic-standalone test_canonical_root_layout repl scripts/gates/cm_canonical_root_clarity.sh \
    'if [ -z "$consumer_root" ] && [ "$standalone_decl" = "1" ]; then' 'if [ -z "$consumer_root" ] && { [ "$standalone_decl" = "1" ] || [ ! -f "$(dirname "$const_dir")/CLAUDE.md" ]; }; then'
mutate M08-enumerate-re      test_fastcycle_layout      pre scripts/fastcycle/consumers/_enumerate_impl.py
mutate M09-migrate-revert    test_fastcycle_layout      pre scripts/fastcycle/consumers/migrate.sh
mutate M10-multitrack-revert test_multitrack_sync_layout pre scripts/multitrack/multitrack_constitution_sync.sh
mutate M11-plugin-hint       test_plugin_hint_layout    pre scripts/install_cli_agent_plugins.sh
for t in CLAUDE.project.md AGENTS.project.md Constitution.project.md helix-deps.yaml; do
    mutate "M12-template-$t"  test_templates_layout     pre "templates/$t.template"
done

# --- review round fixes (B1, I1-I6, M2) -------------------------------------
mutate M13-setup-no-collision-refusal test_setup_layout repl scripts/setup.sh \
    'if [ "$label" = project ]; then' 'if false; then'
mutate M14-setup-backup-overwrites    test_setup_layout repl "$HL" \
    'while [ -e "$bpath" ] || [ -L "$bpath" ]; do' 'while false; do'
mutate M15-postmerge-R1-HEAD1         test_post_merge_layout repl scripts/hooks/post-merge \
    '"ORIG_HEAD:${REL}"' '"HEAD^1:${REL}"'
mutate M16-postmerge-run-when-stale   test_post_merge_layout repl scripts/hooks/post-merge \
    'if [ "$_sub_head" = "$NEW_LINK" ]; then' 'if true; then'
mutate M17-postmerge-override-wins    test_post_merge_layout repl scripts/hooks/post-merge \
    'if is_gitlink "$_p"; then CONST_DIR="${PROJECT_ROOT}/${_p}"; REL="$_p"; break; fi' 'if is_gitlink "$_p"; then CONST_DIR="${CONSTITUTION_DIR:-${PROJECT_ROOT}/${_p}}"; REL="$_p"; break; fi'
mutate M18-postmerge-no-range-env     test_post_merge_layout repl scripts/hooks/post-merge \
    'CONSTITUTION_UPDATE_OLD_REF="$RANGE_OLD" CONSTITUTION_UPDATE_NEW_REF="$NEW_LINK" \' '\'
mutate M19-postmerge-space-split      test_post_merge_layout repl scripts/hooks/post-merge \
    "_val=\"\${_rec#*\$'\\n'}\"" '_val="${_rec#* }"'
mutate M20-lib-space-split            test_constitution_layout_lib repl scripts/lib/constitution_layout.sh \
    '_cl_gp="${_cl_gl#*"$_cl_gt"}"' '_cl_gp="${_cl_gl#* }"'
mutate M21-multitrack-override-wins   test_multitrack_sync_layout repl scripts/multitrack/multitrack_constitution_sync.sh \
    'cdir="$(cl_find_in_project_no_override "$wt" 2>/dev/null || true)"' 'cdir="$(cl_find_in_project "$wt" 2>/dev/null || true)"'
mutate M22-gate-any-pointer-path      test_canonical_root_layout repl scripts/gates/cm_canonical_root_clarity.sh \
    'a_total=$((a_head + a_imp))' 'a_total=$((a_head + a_imp + $(crc_count "$consumer_claude" "$RE_INHERIT_HEADING" "$head_lines") + $(crc_count "$consumer_claude" "$RE_INHERIT_IMPORT" "$head_lines")))'
mutate M23-enumerate-first-page-only  test_fastcycle_layout repl scripts/fastcycle/consumers/_enumerate_impl.py \
    '        if len(tree) < GITLAB_PAGE_SIZE:
            return False, "ok"' '        if True:
            return False, "ok"'

# --- review round 2 (I-1..I-5, M-a..M-f) ------------------------------------
H=scripts/hooks/post-merge; C=scripts/hooks/constitution-submodule-post-checkout
mutate M24-setup-no-chmod-x          test_setup_layout repl "$HL" \
    'if cp "$src" "$tmp" && chmod +x "$tmp" && mv -f "$tmp" "$dst"; then' 'if cp "$src" "$tmp" && mv -f "$tmp" "$dst"; then'
mutate M25-setup-ignore-backup-fail  test_setup_layout repl "$HL" \
    'if ! chi_backup_hook "$dst" "$name" "$label" "$broot" "$bstamp"; then' 'if ! chi_backup_hook "$dst" "$name" "$label" "$broot" "$bstamp" && false; then'
mutate M26-setup-deref-symlink       test_setup_layout repl "$HL" \
    '    if [ -L "$dst" ]; then
        target=' '    if false; then
        target='
mutate M27-setup-backup-in-hooksdir  test_setup_layout repl scripts/setup.sh \
    'BACKUP_ROOT="$COMMON_DIR/constitution-hook-backup"' 'BACKUP_ROOT="$GIT_HOOKS_DST/.constitution-hook-backup"'
mutate M28-setup-no-consumer         test_pending_update_layout repl scripts/setup.sh \
    'elif ! install_one_hook "$CONSUMER_SRC" post-checkout submodule "$SUB_HOOKS_DST"; then' 'elif false; then'
mutate M29-setup-no-stamp-consume    test_setup_layout repl scripts/setup.sh \
    '      RANGE_NEW="$SUB_HEAD"; CONSUME_STAMP=1' '      RANGE_NEW="$SUB_HEAD"; CONSUME_STAMP=0'
mutate M30-postmerge-no-stamp        test_pending_update_layout repl "$H" \
    '> "$t" && mv -f -- "$t" "$STAMP"; then' '> "$t" && false; then'
mutate M31-postmerge-latest-old      test_pending_update_layout repl "$H" \
    'if [ "$HAVE_STAMP" = 1 ]; then RANGE_OLD="$S_OLD"' 'if false; then RANGE_OLD="$S_OLD"'
mutate M33-postmerge-keep-GIT_DIR    test_pending_update_layout repl "$H" \
    'unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR \' 'unset GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR \'
mutate M34-postmerge-noisy-noop      test_post_merge_layout repl "$H" \
    '[ "${#CHANGED[@]}" -gt 0 ] || exit 0' 'CHANGED+=(submodules/constitution)'
mutate M35-postmerge-warn-per-path   test_pending_update_layout repl "$H" \
    '        looks_like_constitution "$c" || continue' '        :'
mutate M36-consumer-keep-GIT_DIR     test_pending_update_layout repl "$C" \
    'unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR \' 'unset GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR \'
mutate M37-consumer-no-record        test_pending_update_layout repl "$C" \
    'record_applied || say "WARNING: could not record $APPLIED"' ':'
mutate M38-consumer-ignore-applied   test_pending_update_layout sed "$C" \
    's/elif \[ -n "\$A_REF" \]; then OLD="\$A_REF"/elif false; then OLD="$A_REF"/'
mutate M39-consumer-no-stamp-rm      test_pending_update_layout repl "$C" \
    '    rm -f -- "$STAMP"
else
    # failure: NOTHING' '    :
else
    # failure: NOTHING'
mutate M40-gate-no-trailing-text     test_canonical_root_layout repl scripts/gates/cm_canonical_root_clarity.sh \
    '"^## INHERITED FROM ${a_esc}([[:space:]].*)?\$"' '"^## INHERITED FROM ${a_esc}[[:space:]]*\$"'
mutate M41-gate-claude-import-only   test_canonical_root_layout repl scripts/gates/cm_canonical_root_clarity.sh \
    '/(CLAUDE|AGENTS|Constitution)\\.md[[:space:]]*\$"' '/CLAUDE\\.md[[:space:]]*\$"'
mutate M42-gate-trailing-anything    test_canonical_root_layout repl scripts/gates/cm_canonical_root_clarity.sh \
    '"^## INHERITED FROM ${a_esc}([[:space:]].*)?\$"' '"^## INHERITED FROM ${a_esc}"'
mutate M43-deps-legacy-hub-only      test_deps_manifest_layout repl scripts/deps_manifest/helix_deps_manifest.py \
    'HUB_RELS = ("submodules/constitution", "constitution")' 'HUB_RELS = ("constitution",)'
mutate M44-deps-no-hub-subscan       test_deps_manifest_layout repl scripts/deps_manifest/helix_deps_manifest.py \
    'bases = [("submodules", ".")] + [(os.path.join(h, "submodules"), h) for h, _, _ in hubs[1:]]' \
    'bases = [("submodules", ".")]'
# --- review round 3 (I1..I6, RM1..RM7, m1..m7) ------------------------------
T=test_consumer_trust_lock; SU=test_setup_layout; PM=scripts/hooks/post-merge; ST=scripts/setup.sh
mutate M45-RM1-consumer-no-CUR-eq-LINK  $T repl "$C" '[ -n "$LINK" ] && [ "$CUR" = "$LINK" ] || exit 0' '[ -n "$LINK" ] || exit 0'
mutate M46-RM2-consumer-no-stamp-ROOT   $T repl "$C" \
    'if [ "$(kv "$STAMP" ROOT)" = "$PROJECT_ROOT" ] && [ "$(kv "$STAMP" REL)" = "$REL" ]; then' 'if [ "$(kv "$STAMP" REL)" = "$REL" ]; then'
mutate M47-RM3-reclaim-live-lock        $T repl "$C" 'LOCK_HOLDER="live pid $pid"; return 1' 'stale="live (mutant)"'
mutate M48-RM4-setup-logical-root       $SU repl "$ST" \
    'if [ "$(kv "$PENDING_STAMP" ROOT || true)" = "$_proot_phys" ]' 'if [ "$(kv "$PENDING_STAMP" ROOT || true)" = "$PROJECT_ROOT" ]'
mutate M49-RM5-setup-no-NEW-check       $SU repl "$ST" \
    '     [ -n "$SUB_HEAD" ] && [ "$(kv "$PENDING_STAMP" NEW || true)" = "$SUB_HEAD" ]; then' '     [ -n "$SUB_HEAD" ]; then'
mutate M50-RM6-consumer-file-checkout   $T repl "$C" '[ "${3:-0}" = 1 ] || exit 0' ':'
mutate M51-RM7-consumer-reentrant       $T repl "$C" '[ "${CONSTITUTION_PENDING_UPDATE_RUNNING:-}" = 1 ] && exit 0' ':'
mutate M52-I1-setup-exit0-on-failure    $SU repl "$ST" \
    'if [ "$HOOK_ERRORS" -ne 0 ] || [ "$PU_RC" -ne 0 ]; then' 'if [ "$HOOK_ERRORS" -ne 0 ]; then'
mutate M53-I1-setup-set-e-stops         $SU sed "$ST" 's/ || PU_RC=\$?$//'
mutate M54-I2-consumer-common-dir       $T repl "$C" \
    'STATE="$(G rev-parse --absolute-git-dir 2>/dev/null)" || exit 0' 'STATE="$(G rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || exit 0'
mutate M55-I2-postmerge-common-dir      $T repl "$PM" \
    'STATE="$(G rev-parse --absolute-git-dir 2>/dev/null || true)"' 'STATE="$(G rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"'
mutate M56-I2-setup-common-dir          $T repl "$ST" \
    'STATE_DIR="$(git -C "$PROJECT_ROOT" rev-parse --absolute-git-dir 2>/dev/null || true)"' 'STATE_DIR="$COMMON_DIR"'
mutate M57-I3-dead-pid-is-live          $T repl "$C" 'if ! alive "$pid"; then' 'if false; then'
mutate M58-I3-fresh-empty-reclaimed     $T repl "$C" 'if [ "$age" -gt "$LOCK_STALE_AGE" ]; then' 'if true; then'
mutate M59-I3-reused-pid-is-live        $T repl "$C" 'if [ -n "$st" ] && [ -n "$cur" ] && [ "$st" != "$cur" ]; then' 'if false; then'
mutate M60-I3-symlink-lock-not-stale    $T repl "$C" \
    '            L:*) stale="it is a symlink (never followed)" ;;' '            L:*) stale="" ;;'
mutate M61-I3-contention-silent         $T repl "$C" \
    '    say "WARNING: the propagation lock $LOCK is held by $LOCK_HOLDER;' '    : "WARNING: the propagation lock $LOCK is held by $LOCK_HOLDER;'
mutate M62-m6-takeover-not-atomic       $T repl "$C" \
    '        mv -- "$LOCK" "$u" 2>/dev/null || continue' '        rm -rf -- "$LOCK"; mkdir -p "$u"'
mutate M63-I6-consumer-no-reachability  $T repl "$C" 'git -C "$c" merge-base --is-ancestor "$new" "$up" 2>/dev/null || \' 'true || \'
mutate M64-I6-consumer-downgrade-ok     $T repl "$C" 'git -C "$c" merge-base --is-ancestor "$old" "$new" 2>/dev/null || \' 'true || \'
mutate M65-I6-consumer-env-optout-off   $T repl "$C" '        off|0|false|no) AP_WHY=' '        zzz) AP_WHY='
mutate M66-I6-consumer-config-optout-off $T repl "$C" '        if [ "$v" != true ]; then' '        if false; then'
mutate M67-I6-postmerge-no-trust        $T repl "$PM" \
    'if ! auto_propagate_allowed "$CONST_DIR" "$RANGE_OLD" "$NEW_LINK"; then' 'if false; then'
mutate M68-I6-setup-no-trust-print      $SU repl "$ST" 'info "Trust model of auto-propagation (§11.4.164):"' ':'
mutate M69-I6-setup-no-record           $SU repl "$ST" \
    '  git -C "$PROJECT_ROOT" config --local constitution.autoPropagate "$AUTO_PROP" || {' '  true || {'
mutate M70-I4-setup-global-scope-ok     $SU repl "$HL" '    local|worktree) ;;' '    local|worktree|global) ;;'
mutate M71-I4-setup-shared-dir-ok       $SU repl "$HL" \
    '    if chi_under "$p" "$(chi_phys "$gd")" || chi_under "$p" "$(chi_phys "$cd")"; then
        return 0' '    if true; then
        return 0'
mutate M72-I4-consumer-into-shared-dir  $SU repl "$ST" 'elif [ "$SUB_HOOKS_OK" -ne 1 ]; then' 'elif false; then'
mutate M73-m3-no-link-file              $SU repl "$HL" '"$target" "$abs" "$bpath" "$dst" > "$bpath.link" || {' '"$target" "$abs" "$bpath" "$dst" > /dev/null || {'
mutate M74-m3-link-file-relative        $SU repl "$HL" \
    '        case "$target" in /*) ;; *) abs="$(chi_phys "$(dirname -- "$dst")")/$target" ;; esac' '        :'
mutate M75-m4-checkonly-no-drift        $SU repl "$ST" '    elif cmp -s "$2" "$3"; then' '    elif true; then'
mutate M76-m4-checkonly-always-0        $SU repl "$ST" '  exit "$CHK_ERR"' '  exit 0'
# --- review round 4 (I-A, I-B, I-C, m-A, m-C) -------------------------------
R4=test_round4_hardening; PU=scripts/post_update_hook.sh
R6=test_round6_hardening
R7=test_round7_ambient
mutate M77-IA-lock-not-exclusive        $R6 repl "$C" '    ( set -o noclobber' '    ( set +o noclobber'
mutate M78-IA-lock-create-no-precheck   $R4 repl "$C" \
    'lock_path_taken() { [ -e "$LOCK" ] || [ -L "$LOCK" ]; }' 'lock_path_taken() { return 1; }'
mutate M79-IA-file-lock-owner-ignored   $R4 repl "$C" \
    '            D:*|F:*) txt="${sig#?:}"; mt="${txt%%:*}"; txt="${txt#*:}" ;;' '            D:*|F:*) txt=""; mt=0 ;;'
mutate M80-IC-logical-not-physical      $R6 repl "$HL" '    p="$(chi_phys "$hd")" || {' '    p="$hd" || {'
mutate M81-IC-sub-symlink-not-refused   $R4 repl "$ST" \
    '  [ "$ALLOW_GLOBAL_HOOKS" -eq 1 ] || _refuse+=("constitution submodule: $_sub_why")' '  :'
mutate M82-IB-step4-no-scope-policy     $R4 repl "$PU" \
    '    if ! chi_hooks_dir_check "$PROJECT_ROOT" "$hooks_dst" repo; then
        if [ "${CONSTITUTION_ALLOW_GLOBAL_HOOKS_PATH:-}" = 1 ]; then' '    if false; then
        if [ "${CONSTITUTION_ALLOW_GLOBAL_HOOKS_PATH:-}" = 1 ]; then'
mutate M83-IB-step4-plain-cp            $R4 repl "$PU" \
    'if chi_install_hook "$src_file" "$hook_name" post-update "$hooks_dst" "$common_dir/constitution-hook-backup" "$bstamp"; then' \
    'if cp "$src_file" "$dst_file" && chmod +x "$dst_file"; then'
mutate M84-IB-step4-allow-env-ignored   $R4 repl "$PU" \
    '        if [ "${CONSTITUTION_ALLOW_GLOBAL_HOOKS_PATH:-}" = 1 ]; then' '        if false; then'
mutate M85-mA-postmerge-sources-lib     $R4 repl "$PM" \
    'in_changed "$REL" || exit 0' '. "$CONST_DIR/scripts/lib/constitution_layout.sh"; in_changed "$REL" || exit 0'
mutate M86-mC-X01-direct-downgrade-ok   $R4 repl "$PM" \
    'git -C "$c" merge-base --is-ancestor "$old" "$new" 2>/dev/null || \' 'true || \'
mutate M87-mB-setup-no-limitation-text  $R4 repl "$ST" \
    'info "  or --recurse-submodules runs NO hook and prints nothing; re-run setup.sh (or post_update_hook.sh) after it."' ':'
# --- review round 5 -> round-6 fixes ----------------------------------------
SL=scripts/lib/constitution_layout.sh
mutate M88-L1-reclaim-no-signature-check $R6 repl "$C" '        if [ "$sig2" != "$sig" ]; then' '        if false; then'
mutate M90-L2-R04-no-recheck-before-run  $R6 repl "$C" 'if ! lock_is_mine; then
    say "WARNING: the propagation lock $LOCK is no longer' 'if false; then
    say "WARNING: the propagation lock $LOCK is no longer'
mutate M91-L4-postmerge-ignores-lock     $R6 repl "$PM" '    if [ "$pm_got" != 1 ]; then' '    if false; then'
mutate M92-S1-R03-abbreviated-sha        $R6 repl "$C" \
    'is_sha() { [[ "$1" =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]]; }' 'is_sha() { [[ "$1" =~ ^[0-9a-f]{7,64}$ ]]; }'
# M93/M94 retargeted in round 7: the ambient-root rule now lives at the top of
# each entry point (owner wins over an ambient PROJECT_ROOT, every step).
mutate M93-P1-setup-ambient-root-honoured $R7 repl "$ST" \
    '  if [ -n "$_owner" ]; then' '  if false; then'
mutate M94-P2-all-steps-ambient-root-honoured $R7 repl "$PU" \
    'elif [ -n "$_pu_owner" ]; then' 'elif false; then'
mutate M95-T1-tracked-warn-only-with-hooksPath $R6 repl "$ST" \
    'if chi_tracked_hooks_dir "$PROJECT_ROOT" "$GIT_HOOKS_DST"; then' \
    'if [ -n "$(git -C "$PROJECT_ROOT" config --get core.hooksPath 2>/dev/null || true)" ] && chi_tracked_hooks_dir "$PROJECT_ROOT" "$GIT_HOOKS_DST"; then'
mutate M98-T1-tracked-helper-never       $R6 repl "$HL" \
    '    CHI_TRACKED_PHYS="$p"
    return 0' '    return 1'
mutate M96-D1-postmerge-no-gitlink-pass  $R6 repl "$PM" \
    'for _p in submodules/constitution constitution "${GITMODULE_PATHS[@]}"; do   # 1. a holder that IS a gitlink' \
    'for _p in ; do   # 1. a holder that IS a gitlink'
mutate M97-D1-lib-no-gitlink-pass        $R6 repl "$SL" '    if command -v git >/dev/null 2>&1; then
        _cl_cands=' '    if false; then
        _cl_cands='
# --- review round 6 -> round-7 fixes (I-1 ambient class, M-2..M-4, X1..X9) ---
mutate M99-I1-setup-env-const-dir-honoured $R7 sed "$ST" \
    's|^if \[ -n "\${CONST_DIR:-}" \] \&\& ! cl_same_dir "\$CONST_DIR" "\$_SELF_CONST"; then|if false; then|; s|^CONST_DIR="\$_SELF_CONST"$|CONST_DIR="${CONST_DIR:-$_SELF_CONST}"|'
mutate M100-I1-pu-env-const-dir-not-refused $R7 repl "$PU" \
    'if [ -n "${CONST_DIR:-}" ] && [ "$(pu_phys "$CONST_DIR")"' 'if false && [ "$(pu_phys "$CONST_DIR")"'
mutate M101-I1-pu-explicit-root-ignored    $R7 repl "$PU" \
    '    PROJECT_ROOT="$ARG_PROJECT_ROOT"' '    :'
mutate M102-I1-setup-cwd-picks-root       $R7 repl "$ST" \
    '    PROJECT_ROOT="$_owner"' '    PROJECT_ROOT="${PROJECT_ROOT:-$_owner}"'
mutate M103-M4-lib-gitmodules-not-gitlink-first $R7 repl "$SL" \
    '                     cl__gitmodules_paths "$_cl_r")"' '                     :)"'
mutate M104-M4-postmerge-gitmodules-plain-first $R7 repl "$PM" \
    'for _p in submodules/constitution constitution "${GITMODULE_PATHS[@]}"; do   # 1. a holder that IS a gitlink' \
    'for _p in submodules/constitution constitution; do   # 1. a holder that IS a gitlink'
mutate M105-M2-setup-ignores-lock         $R6 repl "$ST" '    PU_LOCK_BUSY=1' '    :'
mutate M106-M3-lockheld-no-stamp          $R6 repl "$PM" \
    '        if write_stamp; then
            warn "a pending stamp is recorded' '        if false; then
            warn "a pending stamp is recorded'
mutate M107-X1-putback-overwrites         $R6 repl "$C" \
    'ln -- "$u" "$LOCK" 2>/dev/null && rm -f -- "$u"' 'mv -f -- "$u" "$LOCK"'
mutate M108-X1-dir-putback-into-dir       $R6 repl "$C" \
    '        { [ -e "$LOCK" ] || [ -L "$LOCK" ]; } && return 1
        mv -T -n -- "$u" "$LOCK" 2>/dev/null' '        mv -f -- "$u" "$LOCK" 2>/dev/null'
mutate M109-X2-consumer-unknown-old-runs  $R6 repl "$C" \
    'git -C "$c" cat-file -e "${old}^{commit}" 2>/dev/null || \' 'true || \'
mutate M110-X3-consumer-optout-case-sensitive $R6 repl "$C" \
    "case \"\$(printf '%s' \"\${CONSTITUTION_AUTO_PROPAGATE:-}\" | tr 'A-Z' 'a-z')\" in" 'case "${CONSTITUTION_AUTO_PROPAGATE:-}" in'
mutate M111-X3-postmerge-optout-case-sensitive $R6 repl "$PM" \
    "case \"\$(printf '%s' \"\${CONSTITUTION_AUTO_PROPAGATE:-}\" | tr 'A-Z' 'a-z')\" in" 'case "${CONSTITUTION_AUTO_PROPAGATE:-}" in'
mutate M112-X6-chi_under-prefix-no-slash  $R6 repl "$HL" \
    'chi_under() { [ -n "$2" ] || return 1; case "$1/" in "${2%/}"/*) return 0 ;; esac; return 1; }' \
    'chi_under() { [ -n "$2" ] || return 1; case "$1" in "${2%/}"*) return 0 ;; esac; return 1; }'
mutate M113-X8-postmerge-lockheld-falls-through $R6 repl "$PM" \
    '        warn "or, when no other propagation is running (remove a stale lock first): $HINT"
        exit 0' '        warn "or, when no other propagation is running (remove a stale lock first): $HINT"
        :'
mutate M114-X9-postmerge-stamp-logical-root $R6 repl "$PM" \
    "printf 'ROOT=%s\\nREL=%s\\nOLD=%s\\nNEW=%s\\n' \"\$ROOT_PHYS\"" "printf 'ROOT=%s\\nREL=%s\\nOLD=%s\\nNEW=%s\\n' \"\$PROJECT_ROOT\""
# N6 promoted to a counted mutant in round 7 (killed by round7 G5): post-merge
# pass 2 using a plain holder as the checkout.
mutate M115-N6-postmerge-plain-holder-used $R7 repl "$PM" \
    'if is_gitlink "$_p"; then CONST_DIR="${PROJECT_ROOT}/${_p}"; REL="$_p"; fi' 'CONST_DIR="${PROJECT_ROOT}/${_p}"; REL="$_p"'
# W2 contract: the hook runs under the updater's held install lock whatever
# HELIX_CONSTITUTION_LOCK_DELEGATED says; it must never refuse on, or touch, it.
PU_AFTER_ROOT='else
    PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
fi
'
mutate M116-PL-pu-refuses-on-install-lock $R7 repl "$PU" "$PU_AFTER_ROOT" "$PU_AFTER_ROOT"'[ -e "$(git -C "$PROJECT_ROOT" rev-parse --absolute-git-dir 2>/dev/null)/helix-constitution-install.lock" ] && { echo "[ERROR] the install lock is held" >&2; exit 1; }
'
mutate M117-PL-pu-removes-install-lock    $R7 repl "$PU" "$PU_AFTER_ROOT" "$PU_AFTER_ROOT"'rm -f -- "$(git -C "$PROJECT_ROOT" rev-parse --absolute-git-dir 2>/dev/null)/helix-constitution-install.lock"
'
# Known low-probability survivor candidates (run, reported, not counted):
info_mut() { # ID SUITE PATH OLD NEW
    selected "$1" || return 0
    control "$2" || return 0
    cp -a "$SRC/$3" "$SB/bak"
    python3 - "$SRC/$3" "$4" "$5" <<'PYI' || { echo "INFO $1: text not found"; cp -a "$SB/bak" "$SRC/$3"; return; }
import sys
p, old, new = sys.argv[1:4]; s = open(p).read()
if s.count(old) != 1: sys.exit(1)
open(p, "w").write(s.replace(old, new))
PYI
    if run_suite "$2"; then echo "INFO $1 SURVIVED (expected: race window not driven by the suite)"; else echo "INFO $1 killed"; fi
    cp -a "$SB/bak" "$SRC/$3"
}
info_mut N4-release-foreign-lock     $T "$C" '    lock_is_mine || return 0' '    :'

# Expected EQUIVALENT (defence in depth, reported, not counted as a failure):
# the traversal/absolute filter in post-merge is shadowed by is_gitlink (git
# refuses pathspecs outside the repository), so removing it changes nothing.
if selected N2-traversal-filter && control test_pending_update_layout; then
cp -a "$SRC/$H" "$SB/bak"
python3 - "$SRC/$H" <<'PYEQ'
import sys
p = sys.argv[1]; s = open(p).read()
old = "safe_rel() { case \"$1\" in ''|/*|..|../*|*/..|*/../*|*$'\\n'*) return 1 ;; esac; return 0; }"
assert s.count(old) == 1, "N2 text not found"
open(p, "w").write(s.replace(old, "safe_rel() { return 0; }"))
PYEQ
if run_suite test_pending_update_layout; then echo "INFO N2-traversal-filter EQUIVALENT (survives: is_gitlink also refuses ../ and absolute paths)"
else echo "INFO N2-traversal-filter killed"; fi
cp -a "$SB/bak" "$SRC/$H"
fi

# --- review round 8: ambient git environment, locks, stamps, applied ref ---
R8=test_round8_git_env; SC=scripts
mutate R8-01-lib-cl__git-unscrubbed       $R8 repl $SC/lib/constitution_layout.sh 'cl__git() { ( cl_scrub_git_env quiet; exec git "$@" ); }' 'cl__git() { ( exec git "$@" ); }'
mutate R8-02-setup-no-scrub               $R8 repl $SC/setup.sh $'\ncl_scrub_git_env\n' $'\n:\n'
mutate R8-03-pu-hook-no-scrub             $R8 sed  $SC/post_update_hook.sh 's/^for _pu_v in GIT_DIR /for _pu_v in GIT_NOSUCH_VAR /'
mutate R8-04-postmerge-no-scrub           $R8 sed  $SC/hooks/post-merge 's/^unset GIT_DIR GIT_WORK_TREE/unset GIT_NOSUCH_VAR GIT_WORK_TREE/'
mutate R8-05-consumer-no-scrub            $R8 sed  $SC/hooks/constitution-submodule-post-checkout 's/^unset GIT_DIR GIT_WORK_TREE/unset GIT_NOSUCH_VAR GIT_WORK_TREE/'
mutate R8-06-multitrack-no-scrub          $R8 sed  $SC/multitrack/multitrack_constitution_sync.sh 's/for _v in GIT_DIR GIT_WORK_TREE/for _v in GIT_NOSUCH_VAR GIT_WORK_TREE/'
mutate R8-07-guard-no-scrub               $R8 repl $SC/hooks/guard-evidence-store-write.sh '  cl_scrub_git_env quiet' '  :'
mutate R8-08-install-plugins-no-scrub     $R8 repl $SC/install_cli_agent_plugins.sh $'\n  cl_scrub_git_env\n' $'\n  :\n'
mutate R8-09-fastcycle-layout-env         $R8 repl $SC/fastcycle/consumers/_layout.py 'timeout=timeout, env=git_env(),' 'timeout=timeout,'
mutate R8-10-fastcycle-enum-env           $R8 repl $SC/fastcycle/consumers/_enumerate_impl.py 'timeout=5, env=git_env(),' 'timeout=5,'
mutate R8-11-deps-engine-env              $R8 repl $SC/deps_manifest/helix_deps_manifest.py 'cwd=cwd, env=git_env(), stdout' 'cwd=cwd, stdout'
mutate R8-12-glob-expansion-restored      $R8 repl $SC/lib/constitution_layout.sh 'set -f                          # a path such as' ':                               # a path such as'
mutate R8-13-setup-lock-not-exclusive     $R8 repl $SC/setup.sh '( set -o noclobber; printf' '( printf'
mutate R8-14-setup-no-stale-reclaim       $R8 repl $SC/setup.sh 'pu_lock_create || { pu_lock_reclaim_dead && pu_lock_create; }' 'pu_lock_create'
mutate R8-15-postmerge-no-stale-reclaim   $R8 repl $SC/hooks/post-merge 'pm_lock_create || { pm_lock_reclaim_dead && pm_lock_create; }' 'pm_lock_create'
mutate R8-16-setup-consume-any-root       $R8 repl $SC/setup.sh '[ "$(kv "$PENDING_STAMP" ROOT || true)" = "$_proot_phys" ] && ' ''
mutate R8-17-postmerge-applied-on-failure $R8 sed  $SC/hooks/post-merge 's/NOT recorded as applied; the pending stamp is kept/recorded as applied/'
mutate R8-18-consumer-applied-on-failure  $R8 sed  $SC/hooks/constitution-submodule-post-checkout 's/NOT recorded as applied; the pending stamp is kept/recorded as applied/'
mutate R8-19-postmerge-msg-lies          $R8 repl $SC/hooks/post-merge '\`git submodule update\` does NOT consume it' '\`git submodule update\` consumes it'
mutate R8-20-enum-degraded-sticks        $R8 sed  $SC/fastcycle/consumers/_enumerate_impl.py 's/if not repo_found:/if True:/'
mutate R8-21-pu-hook-capability-marker   $R8 sed  $SC/post_update_hook.sh 's/^# HELIX_HOOK_CAPABILITIES: project-root$/# HELIX_HOOK_CAPABILITIES: none/'

mutate R8-22-scrub-caller-ifs          $R8 sed  $SC/lib/constitution_layout.sh '/_cl_sIFS="$IFS"; IFS=/{N;s/.*/    _cl_sIFS="$IFS"/}'
mutate R8-23-step5-chmods-tracked        $R8 repl $SC/post_update_hook.sh 'ls-files --error-unmatch -- "${script#' 'ls-files --error-unmatch-X -- "${script#'
# --- reviewer mutants (round 8 review): RM1-RM4 + the two inline helpers -----------
mutate RM1-hookinstall-inline-drops-index-file $R8 sed scripts/lib/hook_install.sh 's/unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE /unset GIT_DIR GIT_WORK_TREE /'
mutate RM2-step5-ls-files-no-error-unmatch     $R8 sed $SC/post_update_hook.sh 's/ls-files --error-unmatch -- /ls-files -- /'
mutate RM4-setup-no-putback-of-live-lock       $R8 repl $SC/setup.sh 'ln -- "$u" "$PU_LOCK" 2>/dev/null && rm -f -- "$u"      # a live holder' ': # (mutant: no put-back)'
mutate O8a-setup-putback-ln-force              $R8 repl $SC/setup.sh 'ln -- "$u" "$PU_LOCK" 2>/dev/null && rm -f -- "$u"      # a live holder' 'ln -f -- "$u" "$PU_LOCK" 2>/dev/null && rm -f -- "$u"      # a live holder'
mutate O8b-postmerge-putback-ln-force          $R8 repl $SC/hooks/post-merge 'ln -- "$u" "$PM_LOCK" 2>/dev/null && rm -f -- "$u"' 'ln -f -- "$u" "$PM_LOCK" 2>/dev/null && rm -f -- "$u"'
mutate O6-postcheckout-drops-literal-pathspecs $R8 repl $SC/hooks/constitution-submodule-post-checkout 'G() { git -C "$PROJECT_ROOT" --literal-pathspecs "$@"; }' 'G() { git -C "$PROJECT_ROOT" "$@"; }'
mutate O9-bootstrap-child-installer-unscrubbed $R8 repl $SC/jev/bootstrap.sh '    jb__scrubbed bash "$TK_SETUP" --agents' '    bash "$TK_SETUP" --agents'
mutate O10-migrate-comment-claims-original      $R8 repl $SC/fastcycle/consumers/migrate.sh 'GIT_CONFIG_PARAMETERS and GIT_NO_LAZY_FETCH restored. NOT original for' 'GIT_CONFIG_PARAMETERS and GIT_NO_LAZY_FETCH restored. Original for'
mutate RM5-jevbootstrap-inline-drops-git-dir   $R8 sed $SC/jev/bootstrap.sh 's/( unset GIT_DIR GIT_WORK_TREE /( unset GIT_WORK_TREE /'
mutate RM6-labelsync-inline-drops-common-dir   $R8 sed $SC/label-sync/install_label_sync.sh 's/GIT_PREFIX GIT_COMMON_DIR /GIT_PREFIX /'
mutate RM7-hookinstall-inline-drops-last-var   $R8 sed scripts/lib/hook_install.sh 's/ GIT_INTERNAL_SUPER_PREFIX 2>\/dev\/null; exec git/ 2>\/dev\/null; exec git/'
# RM3: one variable renamed CONSISTENTLY in every scrub list (all copies edited alike; only a literal list kept in the
# test can see it). Multi-file, so not via mutate().
rm3_files="$SC/lib/constitution_layout.sh scripts/lib/hook_install.sh $SC/post_update_hook.sh $SC/hooks/post-merge $SC/hooks/constitution-submodule-post-checkout $SC/multitrack/multitrack_constitution_sync.sh $SC/fastcycle/consumers/migrate.sh $SC/fastcycle/consumers/audit.py $SC/deps_manifest/helix_deps_manifest.py $SC/jev/bootstrap.sh $SC/label-sync/install_label_sync.sh"
rm3_n=0
if selected RM3 && control "$R8"; then
for f in $rm3_files; do cp -a "$SRC/$f" "$SB/rm3.$(echo "$f" | tr / _)"; grep -q 'GIT_COMMON_DIR' "$SRC/$f" && { sed -i 's/\bGIT_COMMON_DIR\b/GIT_COMMON_DIRX/g' "$SRC/$f"; rm3_n=$((rm3_n+1)); }; done
if [ "$rm3_n" -lt 9 ]; then FAIL=$((FAIL+1)); echo "FAIL RM3: only $rm3_n files carried GIT_COMMON_DIR (expected >= 9)"
elif run_suite "$R8"; then FAIL=$((FAIL+1)); echo "FAIL RM3-consistent-rename-all-lists SURVIVED ($rm3_n files, $R8 still green)"
else
    sumline="$(grep -E ': PASS=[0-9]+ FAIL=[0-9]+$' "$SB/last.out" | tail -1)"; firstfail="$(grep -E '^FAIL: ' "$SB/last.out" | head -1 | cut -c7-70)"
    if [ -n "$sumline" ] && [ -n "$firstfail" ]; then PASS=$((PASS+1)); echo "PASS RM3-consistent-rename-all-lists killed by [$firstfail] ($sumline; $rm3_n files)"
    else FAIL=$((FAIL+1)); echo "FAIL RM3 NOT-ATTRIBUTABLE"; fi
fi
for f in $rm3_files; do cp -a "$SB/rm3.$(echo "$f" | tr / _)" "$SRC/$f"; done
fi
printf -- '----\nlayout_mutations: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
