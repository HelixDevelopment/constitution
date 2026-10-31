#!/usr/bin/env bash
# test_integration.sh — INTEGRATION + IDEMPOTENCY tests: the REAL installer and updater against a REAL
# local bare clone of this repository (the upstream), with a real `git submodule add` into throwaway
# consumer projects. No agent is run here (--agent none); no network; no $HOME writes.
# Usage: bash tests/install/test_integration.sh   Exit 0 all pass · 1 a case failed · 2 env error.
T_NAME=integration
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
new_sandbox
mkdir -p "$SB/up"; make_upstream "$SB/up" || { echo "upstream setup failed" >&2; exit 2; }
UP="$SB/up/upstream.git"; V0="$(tagsha "$SB/up" helixconstitution-v999.0)"
BASE=(--non-interactive --agent none --run-setup off --upstream-url "$UP")

echo "# ADD into a fresh project"
P="$SB/p1"; new_project "$P"; head0="$(git -C "$P" rev-parse HEAD)"
run_installer "$P" "${BASE[@]}" --report-json "$SB/r1.json"
eq "ADD exit 0" 0 "$RC"; [ "$RC" = 0 ] || printf '%s\n' "$OUT" | tail -25
eq ".gitmodules path" "submodules/constitution" "$(git -C "$P" config -f .gitmodules submodule.submodules/constitution.path)"
eq ".gitmodules url" "$UP" "$(git -C "$P" config -f .gitmodules submodule.submodules/constitution.url)"
eq "gitlink = newest tag commit" "$V0" "$(gitlink "$P")"
eq "submodule HEAD = newest tag commit" "$V0" "$(git -C "$P/submodules/constitution" rev-parse HEAD)"
check "CLAUDE.md imports submodules/constitution/CLAUDE.md" grep -qx '@submodules/constitution/CLAUDE.md' "$P/CLAUDE.md"
check "CLAUDE.md inheritance heading" grep -qx '## INHERITED FROM submodules/constitution/CLAUDE.md' "$P/CLAUDE.md"
check "AGENTS.md base-rules pointer" grep -qx '> Base agent rules: submodules/constitution/AGENTS.md' "$P/AGENTS.md"
check "no legacy ./constitution path in written files" eval '! grep -hE "(^|[^/A-Za-z_])constitution/" "$P/CLAUDE.md" "$P/AGENTS.md" | grep -v "submodules/constitution/" | grep -q .'
check "nested hub engines NOT initialised (non-recursive)" eval '[ -z "$(ls -A "$P/submodules/constitution/submodules/llmctl" 2>/dev/null)" ]'
eq "not committed by default" "$head0" "$(git -C "$P" rev-parse HEAD)"
check "backup dir excluded via .git/info/exclude" grep -qx '/.constitution-install-backup/' "$P/.git/info/exclude"
eq "report status" success "$(report_field "$SB/r1.json" status)"
eq "report mode" add "$(report_field "$SB/r1.json" mode)"
eq "report commit_after" "$V0" "$(report_field "$SB/r1.json" commit_after)"
eq "report verify.overall" pass "$(report_field "$SB/r1.json" verify.overall)"
echo "# ADD is a blobless partial clone with the full commit graph and tags (I1)"
SUBP="$P/submodules/constitution"
eq "promisor remote configured" true "$(git -C "$SUBP" config --get remote.origin.promisor)"
eq "partial clone filter blob:none" blob:none "$(git -C "$SUBP" config --get remote.origin.partialclonefilter)"
nmiss="$(git -C "$SUBP" rev-list --objects --missing=print --all 2>/dev/null | grep -c '^?')"
check "blobs really omitted (missing objects: $nmiss)" eval '[ "$nmiss" -gt 100 ]'
eq "not shallow (no --depth: updater needs the commit graph)" false "$(git -C "$SUBP" rev-parse --is-shallow-repository)"
check "full commit graph: v72.1 is an ancestor of HEAD" git -C "$SUBP" merge-base --is-ancestor helixconstitution-v72.1 HEAD
check "tags kept" eval '[ -n "$(git -C "$SUBP" tag -l helixconstitution-v999.0)" ]'
check "gitdir absorbed into the project (.git is a gitfile)" test -f "$SUBP/.git"
check "installer marker removed after a complete add" eval '! git -C "$SUBP" config --get helix-installer.clone'
# before its checkout the blobless clone misses every blob of the target commit: that count is the input size the
# missing-object probe reads (the reader must consume it all; a reader that exits early kills the writer: SIGPIPE)
nmiss1="$(git -C "$UP" ls-tree -r "$V0" | grep -c ' blob ')"
check "fixture really has MANY blobs missing before checkout (SIGPIPE precondition: $nmiss1 >= 300)" eval '[ "$nmiss1" -ge 300 ]'
eq "report.clone = blobless (no SIGPIPE-driven false 'full')" blobless "$(report_field "$SB/r1.json" clone)"
check "no false 'does not support partial clone' warning" eval '! grep -q "does not support partial clone" <<<"$OUT"'
check "final message says blobless clone" grep -q 'blobless clone)' <<<"$OUT"
check "submodule worktree is clean (lazy blob fetch worked)" eval '[ -z "$(git -C "$SUBP" status --porcelain)" ]'
umask_probe="$SB/umask.probe"; : >"$umask_probe"
eq "submodule files keep the user's umask (not the installer's private 077)" "$(stat -c %a "$umask_probe")" "$(stat -c %a "$SUBP/README.md")"
echo "# private backups and reports (I7)"
bd="$(report_field "$SB/r1.json" backup_dir)"
eq "backup dir mode 700" 700 "$(stat -c %a "$bd")"
eq "report.json in backup mode 600" 600 "$(stat -c %a "$bd/report.json")"
eq "--report-json file mode 600" 600 "$(stat -c %a "$SB/r1.json")"
unexpected="$(git -C "$P" status --porcelain | awk '{print $2}' | grep -vxE '\.gitmodules|submodules/constitution|CLAUDE\.md|AGENTS\.md')"
eq "git status shows only expected paths" "" "$unexpected"

echo "# idempotency: second run is a no-op that says so"
s1="$(project_state "$P")"
run_installer "$P" "${BASE[@]}" --report-json "$SB/r2.json"
eq "second run exit 0" 0 "$RC"
case "$OUT" in *"already up to date"*) ok "second run says already up to date" ;; *) nok "second run says already up to date"; printf '%s\n' "$OUT" | tail -15 ;; esac
eq "second run changes nothing" "$s1" "$(project_state "$P")"
eq "second run report mode" update "$(report_field "$SB/r2.json" mode)"

echo "# UPDATE after the upstream advances (fast-forward)"
advance_upstream "$SB/up" helixconstitution-v999.1 || { echo "advance failed" >&2; exit 2; }
V1="$(tagsha "$SB/up" helixconstitution-v999.1)"
run_installer "$P" "${BASE[@]}" --report-json "$SB/r3.json"
eq "UPDATE exit 0" 0 "$RC"; [ "$RC" = 0 ] || printf '%s\n' "$OUT" | tail -25
eq "submodule fast-forwarded to new tag" "$V1" "$(git -C "$P/submodules/constitution" rev-parse HEAD)"
eq "gitlink staged in parent" "$V1" "$(gitlink "$P")"
check "V0 is an ancestor of V1 (fast-forward)" git -C "$P/submodules/constitution" merge-base --is-ancestor "$V0" "$V1"
case "$OUT" in *"$V0"*"$V1"*) ok "before/after sha printed" ;; *) nok "before/after sha printed" ;; esac
eq "report mode update" update "$(report_field "$SB/r3.json" mode)"
eq "report commit_before" "$V0" "$(report_field "$SB/r3.json" commit_before)"
eq "updater ran (delegated) on the blobless clone" delegated "$(report_field "$SB/r3.json" updater)"
check "after the update the blobless worktree is clean" eval '[ -z "$(git -C "$P/submodules/constitution" status --porcelain)" ]'
check "after the update a file of the new commit is readable" grep -q 'advance helixconstitution-v999.1' "$P/submodules/constitution/docs/prompts/setup/advance_marker.txt"
run_installer "$P" "${BASE[@]}"; eq "re-run after update exit 0" 0 "$RC"
case "$OUT" in *"already up to date"*) ok "re-run after update is a no-op" ;; *) nok "re-run after update is a no-op" ;; esac

echo "# --commit on"
P2="$SB/p2"; new_project "$P2"; h="$(git -C "$P2" rev-parse HEAD)"
run_installer "$P2" "${BASE[@]}" --commit on
eq "commit run exit 0" 0 "$RC"
eq "exactly one new commit" 1 "$(git -C "$P2" rev-list --count "$h..HEAD")"
check "commit message names submodules/constitution" eval 'git -C "$P2" log -1 --format=%B | grep -q "submodules/constitution"'
eq "worktree clean after commit" "" "$(git -C "$P2" status --porcelain)"
check "nothing pushed: project has no remote" eval '[ -z "$(git -C "$P2" remote)" ]'

echo "# dry run: zero writes"
P3="$SB/p3"; new_project "$P3"; f0="$(tree_fingerprint "$P3")"
run_installer "$P3" "${BASE[@]}" --dry-run
eq "dry run exit 0" 0 "$RC"
case "$OUT" in *"DRY RUN"*"git submodule add"*) ok "dry run prints the plan" ;; *) nok "dry run prints the plan"; printf '%s\n' "$OUT" | tail -10 ;; esac
eq "dry run wrote nothing (incl .git)" "$f0" "$(tree_fingerprint "$P3")"

echo "# preconditions"
mkdir -p "$SB/notgit"; f0="$(tree_fingerprint "$SB/notgit")"
run_installer "$SB/notgit" "${BASE[@]}"; eq "not a git repo -> exit 3" 3 "$RC"
eq "not a git repo: nothing written" "$f0" "$(tree_fingerprint "$SB/notgit")"
mkdir -p "$SB/initme"; run_installer "$SB/initme" "${BASE[@]}" --git-init
eq "--git-init then ADD exit 0" 0 "$RC"; eq "--git-init gitlink" "$V1" "$(gitlink "$SB/initme")"
P4="$SB/p4"; new_project "$P4"; printf 'x\n' >"$P4/CLAUDE.md"; git -C "$P4" add CLAUDE.md; git -C "$P4" commit -qm c
printf 'local edit\n' >>"$P4/CLAUDE.md"; s0="$(project_state "$P4")"
run_installer "$P4" "${BASE[@]}"; eq "dirty touched path (CLAUDE.md) -> exit 3" 3 "$RC"
eq "dirty refusal wrote nothing" "$s0" "$(project_state "$P4")"
P5="$SB/p5"; new_project "$P5"; printf 'unrelated\n' >"$P5/other.txt"
run_installer "$P5" "${BASE[@]}"; eq "unrelated dirty file does not block (exit 0)" 0 "$RC"
check "unrelated dirty file untouched" grep -qx unrelated "$P5/other.txt"
P6="$SB/p6"; new_project "$P6"; printf '# Mine\n\nproject rules\n' >"$P6/CLAUDE.md"; git -C "$P6" add CLAUDE.md; git -C "$P6" commit -qm c
run_installer "$P6" "${BASE[@]}"; eq "existing CLAUDE.md: exit 0" 0 "$RC"
check "existing CLAUDE.md content preserved" grep -qx 'project rules' "$P6/CLAUDE.md"
bk="$(find "$P6/.constitution-install-backup" -name CLAUDE.md -path '*files*' | head -1)"
check "original CLAUDE.md backed up" eval '[ -n "$bk" ] && cmp -s "$bk" <(git -C "$P6" show HEAD:CLAUDE.md)'

echo "# interrupted 'git submodule add' of THIS installer: gitlink staged, .gitmodules not yet written (chaos repro)"
half_add() { # dir marker(0|1)
  new_project "$1"
  git -C "$1" -c protocol.file.allow=always submodule add -q "$UP" submodules/constitution >/dev/null 2>&1
  git -C "$1" config -f "$1/.gitmodules" --remove-section submodule.submodules/constitution
  [ -s "$1/.gitmodules" ] || { rm -f -- "$1/.gitmodules"; git -C "$1" rm -q --cached --ignore-unmatch .gitmodules; }
  [ "$2" = 1 ] && git -C "$1/submodules/constitution" config helix-installer.clone true
  return 0
}
PH0="$SB/ph0"; half_add "$PH0" 0; f0="$(tree_fingerprint "$PH0")"
run_installer "$PH0" "${BASE[@]}"; eq "user-staged gitlink without .gitmodules entry: refused (exit 3)" 3 "$RC"
check "refusal explains how to unstage" grep -q 'git rm --cached' <<<"$OUT"
eq "user-staged gitlink: nothing touched (full tree incl .git and index)" "$f0" "$(tree_fingerprint "$PH0")"
check "user-staged gitlink: no backup dir created" test ! -e "$PH0/.constitution-install-backup"
EM="$SB/embedded"; new_project "$EM"; mkdir -p "$EM/submodules/constitution"; git -C "$EM/submodules/constitution" init -q
printf 'x\n' >"$EM/submodules/constitution/x"; git -C "$EM/submodules/constitution" add x; git -C "$EM/submodules/constitution" commit -qm x
git -C "$EM" add submodules/constitution 2>/dev/null; f0="$(tree_fingerprint "$EM")"
run_installer "$EM" "${BASE[@]}"; eq "embedded repo staged: refused with exit 3 (not 1)" 3 "$RC"
eq "embedded repo staged: nothing touched" "$f0" "$(tree_fingerprint "$EM")"
PH1="$SB/ph1"; half_add "$PH1" 1
check "precondition: gitlink staged" eval 'git -C "$PH1" ls-files -s -- submodules/constitution | grep -q "^160000 "'
check "precondition: no .gitmodules entry" eval '! git -C "$PH1" config -f "$PH1/.gitmodules" --get submodule.submodules/constitution.path'
eq "half-added layout detected as partial" partial "$(cd "$PH1" && bash "$INSTALLER" --detect-layout 2>/dev/null)"
run_installer "$PH1" "${BASE[@]}"; eq "half-added (installer marker): re-run exit 0" 0 "$RC"
eq "half-added: registered in .gitmodules" submodules/constitution "$(git -C "$PH1" config -f "$PH1/.gitmodules" --get submodule.submodules/constitution.path)"
eq "half-added: gitlink at newest tag (v999.1)" "$(tagsha "$SB/up" helixconstitution-v999.1)" "$(gitlink "$PH1")"
PH2="$SB/ph2"; new_project "$PH2"
git -C "$PH2" -c protocol.file.allow=always submodule add -q "$UP" submodules/constitution >/dev/null 2>&1
git -C "$PH2" config -f "$PH2/.gitmodules" --remove-section submodule.submodules/constitution; git -C "$PH2" add .gitmodules
git -C "$PH2" commit -qm "user commits a gitlink without .gitmodules"
s_ph2="$(project_state "$PH2")"
run_installer "$PH2" "${BASE[@]}"; eq "committed gitlink w/o .gitmodules: refused (exit 3)" 3 "$RC"
eq "committed gitlink w/o .gitmodules: nothing written" "$s_ph2" "$(project_state "$PH2")"
check "refusal names the inconsistency" eval 'printf "%s" "$OUT" | grep -q "not registered in .gitmodules"'

echo "# refusal paths leave no backup dir and no exclude edit"
RF="$SB/rf"; new_project "$RF"; mkdir -p "$RF/submodules/constitution"; printf 'mine\n' >"$RF/submodules/constitution/notes.txt"
f0="$(tree_fingerprint "$RF")"
run_installer "$RF" "${BASE[@]}"; eq "user content at submodules/constitution: refused (exit 3)" 3 "$RC"
eq "user content refusal: full tree (incl .git) unchanged" "$f0" "$(tree_fingerprint "$RF")"
check "user content refusal: no backup dir" test ! -e "$RF/.constitution-install-backup"
check "user content refusal: exclude not edited" eval '! grep -q constitution-install-backup "$RF/.git/info/exclude"'

echo "# partial layout: .gitmodules carrying the user's own uncommitted edits is refused"
GM="$SB/gm"; new_project "$GM"; printf '[submodule "other"]\n\tpath = other\n\turl = https://example.org/other.git\n' >"$GM/.gitmodules"
git -C "$GM" add .gitmodules; git -C "$GM" commit -qm gm
git -C "$GM" config -f "$GM/.gitmodules" submodule.submodules/constitution.path submodules/constitution
git -C "$GM" config -f "$GM/.gitmodules" submodule.submodules/constitution.url "$UP"
eq "our section only: layout partial" partial "$(cd "$GM" && bash "$INSTALLER" --detect-layout 2>/dev/null)"
git -C "$GM" config -f "$GM/.gitmodules" submodule.other.url https://example.org/CHANGED.git
f0="$(tree_fingerprint "$GM")"
run_installer "$GM" "${BASE[@]}"; eq "partial + user edits in .gitmodules: refused (exit 3)" 3 "$RC"
eq "partial + user edits: nothing touched" "$f0" "$(tree_fingerprint "$GM")"
git -C "$GM" config -f "$GM/.gitmodules" submodule.other.url https://example.org/other.git
run_installer "$GM" "${BASE[@]}"; eq "partial with only our own section: recovered (exit 0)" 0 "$RC"
eq "other submodule entry preserved" https://example.org/other.git "$(git -C "$GM" config -f "$GM/.gitmodules" submodule.other.url)"

echo "# run inside a submodule"
SPR="$SB/superp"; new_project "$SPR"; INNER="$SB/innerup"; new_project "$INNER"
git -C "$SPR" -c protocol.file.allow=always submodule add -q "$INNER" lib/inner >/dev/null 2>&1; git -C "$SPR" commit -qm sub
f0="$(tree_fingerprint "$SPR")"
run_installer "$SPR/lib/inner" "${BASE[@]}"; eq "inside a submodule without --project-root: refused (exit 3)" 3 "$RC"
check "inside-submodule refusal names --project-root" grep -q -- '--project-root' <<<"$OUT"
eq "inside-submodule refusal: superproject untouched" "$f0" "$(tree_fingerprint "$SPR")"
run_installer "$SB" "${BASE[@]}" --project-root "$SPR/lib/inner" --dry-run; eq "inside a submodule with --project-root: allowed (dry-run exit 0)" 0 "$RC"
check "inside-submodule: warned" grep -q 'is itself a submodule' <<<"$OUT"

echo "# --restore never writes through a symlinked parent directory"
RS="$SB/rs"; new_project "$RS"; mkdir -p "$SB/outside_dir"; printf 'outside\n' >"$SB/outside_dir/a.md"; ln -s "$SB/outside_dir" "$RS/sub"
mkdir -p "$RS/.constitution-install-backup/X/files/sub"; printf 'from backup\n' >"$RS/.constitution-install-backup/X/files/sub/a.md"; chmod 700 "$RS/.constitution-install-backup" "$RS/.constitution-install-backup/X" "$RS/.constitution-install-backup/X/files"
printf 'sub/a.md\n' >"$RS/.constitution-install-backup/X/manifest.txt"
run_installer "$RS" --restore "$RS/.constitution-install-backup/X"; eq "--restore with symlinked parent: exit 0" 0 "$RC"
eq "outside file untouched" outside "$(cat "$SB/outside_dir/a.md")"
check "symlinked parent reported" grep -q 'symlink' <<<"$OUT"

echo "# blobless clone falls back to a full clone when the server refuses filtering"
NF="$SB/nofilter.git"; git clone -q --bare "$UP" "$NF"; git -C "$NF" config uploadpack.allowFilter false
PF="$SB/pf"; new_project "$PF"
run_installer "$PF" --non-interactive --agent none --run-setup off --upstream-url "$NF"
eq "no-filter server: ADD exit 0" 0 "$RC"; [ "$RC" = 0 ] || printf '%s\n' "$OUT" | tail -8
check "no-filter server: warned about the full clone" grep -q 'full clone' <<<"$OUT"
eq "no-filter server: no missing objects (full clone)" 0 "$(git -C "$PF/submodules/constitution" rev-list --objects --missing=print --all 2>/dev/null | grep -c '^?')"

echo "# upstream fallback + unreachable"
P7="$SB/p7"; new_project "$P7"
run_installer "$P7" --non-interactive --agent none --run-setup off --upstream-url "$SB/does-not-exist.git" --upstream-url "$UP" --report-json "$SB/r7.json"
eq "fallback to second upstream exit 0" 0 "$RC"
eq "report used the reachable upstream" "$UP" "$(report_field "$SB/r7.json" upstream_url)"
P8="$SB/p8"; new_project "$P8"; s0="$(project_state "$P8")"
run_installer "$P8" --non-interactive --agent none --run-setup off --upstream-url "$SB/nope1.git" --upstream-url "http://127.0.0.1:9/x.git"
eq "http:// upstream without --allow-insecure-url -> exit 2" 2 "$RC"
run_installer "$P8" --non-interactive --agent none --run-setup off --upstream-url "$SB/nope1.git" --upstream-url "http://127.0.0.1:9/x.git" --allow-insecure-url
eq "no reachable upstream -> exit 3" 3 "$RC"; eq "unreachable: nothing written" "$s0" "$(project_state "$P8")"
check "insecure URL allowed with a warning" grep -q 'insecure upstream URL' <<<"$OUT"

echo "# legacy ./constitution layout"
P9="$SB/p9"; new_project "$P9"
git -C "$P9" -c protocol.file.allow=always submodule add -q "$UP" constitution >/dev/null 2>&1 && git -C "$P9" commit -qm legacy
s0="$(project_state "$P9")"
run_installer "$P9" "${BASE[@]}" --report-json "$SB/r9.json"
eq "legacy: exit 0" 0 "$RC"; eq "legacy: report mode" legacy "$(report_field "$SB/r9.json" mode)"
case "$OUT" in *"git mv constitution submodules/constitution"*) ok "legacy: manual migration steps printed" ;; *) nok "legacy: manual migration steps printed" ;; esac
eq "legacy: nothing moved automatically" "$s0" "$(project_state "$P9")"

echo "# pinned old ref without the updater -> built-in fast-forward fallback"
P10="$SB/p10"; new_project "$P10"
run_installer "$P10" "${BASE[@]}" --ref helixconstitution-v72.1
eq "ADD at v72.1 exit 0" 0 "$RC"; eq "gitlink at v72.1" "$(tagsha "$SB/up" helixconstitution-v72.1)" "$(gitlink "$P10")"
check "v72.1 has no update_constitution.sh" eval '[ ! -e "$P10/submodules/constitution/scripts/update_constitution.sh" ]'
git -C "$P10" commit -qm "add constitution"
run_installer "$P10" "${BASE[@]}"
eq "built-in update exit 0" 0 "$RC"; eq "built-in update reached newest tag" "$V1" "$(gitlink "$P10")"
case "$OUT" in *"built-in"*) ok "built-in updater announced" ;; *) nok "built-in updater announced" ;; esac

echo "# report json is valid JSON with required keys"
check "report parses + has keys" python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); missing=[k for k in ("installer_version","status","exit_code","mode","project_root","submodule_path","upstream_url","ref","commit_before","commit_after","agent","verify","backup_dir","dry_run","started_at","finished_at") if k not in d]; sys.exit(1 if missing else 0)' "$SB/r1.json"

echo "# built-in updater picks the newest tag by VERSION order (v9 < v10 < v100), not by text order"
# Runs last: it adds tags to the shared upstream. Tags are created out of order (100, then 9, then 10) so
# neither the newest commit nor text order (sort) gives the right answer; only version order does.
P11="$SB/p11"; new_project "$P11"
run_installer "$P11" "${BASE[@]}" --ref helixconstitution-v72.1
git -C "$P11" commit -qm "add constitution"
advance_upstream "$SB/up" helixconstitution-v999.100 && advance_upstream "$SB/up" helixconstitution-v999.9 \
  && advance_upstream "$SB/up" helixconstitution-v999.10 || { nok "advance upstream"; finish; exit; }
run_installer "$P11" "${BASE[@]}"
eq "built-in version-order update exit 0" 0 "$RC"
case "$OUT" in *"built-in"*) ok "built-in updater used" ;; *) nok "built-in updater used" ;; esac
eq "built-in update chose v999.100 (version order)" "$(tagsha "$SB/up" helixconstitution-v999.100)" "$(gitlink "$P11")"
echo "# built-in updater: a target no remote has is refused; --ref main means the REMOTE main (I-1, I-2)"
P12="$SB/p12"; new_project "$P12"
run_installer "$P12" "${BASE[@]}" --ref helixconstitution-v72.1
git -C "$P12" commit -qm "add constitution"; S12="$P12/submodules/constitution"; v72="$(tagsha "$SB/up" helixconstitution-v72.1)"
git -C "$S12" checkout -q -b localonly "$v72"; git -C "$S12" commit -q --allow-empty -m "local only"
lo="$(git -C "$S12" rev-parse HEAD)"; git -C "$S12" checkout -q --detach "$v72"
for tref in localonly "$lo"; do
  run_installer "$P12" "${BASE[@]}" --ref "$tref"
  check "built-in --ref $tref (no remote has it) -> refused (exit $RC)" eval '[ "$RC" -ne 0 ]'
  check "built-in --ref $tref: the built-in updater was used" grep -q 'built-in' <<<"$OUT"
  check "built-in --ref $tref: the refusal says the target is not on a remote" grep -q 'is not on any remote' <<<"$OUT"
  eq "built-in --ref $tref: gitlink unchanged" "$v72" "$(gitlink "$P12")"
  eq "built-in --ref $tref: HEAD unchanged" "$v72" "$(git -C "$S12" rev-parse HEAD)"
done
git -C "$S12" branch -f main "$v72"   # a stale LOCAL main
um="$(git -C "$UP" rev-parse main)"
run_installer "$P12" "${BASE[@]}" --ref main
eq "built-in --ref main: exit 0" 0 "$RC"; check "built-in --ref main: the built-in updater was used" grep -q 'built-in' <<<"$OUT"
eq "built-in --ref main reached the upstream main (not the stale local branch)" "$um" "$(gitlink "$P12")"
echo "# a run killed after 'git submodule add' (installer marker still set) is completed by the next run (M-5)"
P14="$SB/p14"; new_project "$P14"
git clone -q "$UP" "$P14/submodules/constitution"
git -C "$P14/submodules/constitution" config helix-installer.clone true
(cd "$P14" && git -c protocol.file.allow=always submodule add --quiet -- "$UP" submodules/constitution) >/dev/null 2>&1
check "control: the state is a registered submodule with its own .git directory and the marker" \
  eval '[ -d "$P14/submodules/constitution/.git" ] && [ "$(git -C "$P14/submodules/constitution" config --get helix-installer.clone)" = true ]'
run_installer "$P14" "${BASE[@]}"
eq "interrupted add: the next run exits 0" 0 "$RC"
check "interrupted add: announced" grep -q 'completing an interrupted add' <<<"$OUT"
check "interrupted add: the gitdir was absorbed (.git is a file)" eval '[ -f "$P14/submodules/constitution/.git" ]'
check "interrupted add: the marker is gone" eval '[ -z "$(git -C "$P14/submodules/constitution" config --get helix-installer.clone)" ]'
check "interrupted add: gitlink and .gitmodules entry present" eval '[ -n "$(gitlink "$P14")" ] && git -C "$P14" config -f .gitmodules --get submodule.submodules/constitution.path >/dev/null'

echo "# changed paths are read NUL-separated: spaces, quotes, non-ASCII and renames are reported as they are (M-7)"
P13="$SB/p13"; new_project "$P13"
printf 'x\n' >"$P13/sp ace \"q\" ü.txt"; git -C "$P13" mv README.md "READ ME.md"
run_installer "$P13" "${BASE[@]}" --report-json "$SB/r13.json"
eq "pre-existing odd names: exit 0" 0 "$RC"
check "changed_paths holds the names verbatim (no C quoting, no 'a -> b')" python3 -I -c '
import json, sys
d = json.load(open(sys.argv[1])); c = d["changed_paths"]
want = {"sp ace \"q\" ü.txt", "READ ME.md", "README.md"}
bad = [x for x in c if " -> " in x or x.startswith("\"")]
sys.exit(0 if want <= set(c) and not bad else 1)' "$SB/r13.json"
eq "pre-existing odd names: verify.overall = pass" pass "$(report_field "$SB/r13.json" verify.overall)"

finish
