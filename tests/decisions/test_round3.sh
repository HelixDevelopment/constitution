#!/usr/bin/env bash
# test_round3.sh — regression tests for the round-2 independent review (B-1, I-1..I-8, MINOR items).
# Class: integration against REAL git projects and the REAL wizard; no test doubles. Every refusal that
# more than one layer could produce asserts the MESSAGE of the layer under test (layer oracle).
set -u
. "$(dirname "$0")/lib.sh"
new_sandbox; trap cleanup_sandbox EXIT
C="$DEC_CLI"
# tree fingerprint: every path, type, size and content hash under the given dirs (missing dirs are recorded)
tree() { local d; for d in "$@"; do if [ -e "$d" ]; then (cd "$d" && find . -printf '%p %y %s %m\n' | LC_ALL=C sort \
  && find . -type f -exec sha256sum {} + | LC_ALL=C sort); else echo "absent $d"; fi; done | sha256sum | cut -d' ' -f1; }
UD="$(dirname "$CONSTITUTION_DECISIONS_USER_FILE")"
no_leak() { # $1 name, $2 needle: needle must appear in no file under the sandbox and not in last.out/last.err
  if grep -rqF -- "$2" "$SB" --exclude=last.out --exclude=last.err --exclude=needle.out 2>/dev/null \
     || grep -qF -- "$2" "$SB/last.out" "$SB/last.err"; then bad "$1"; else ok "$1"; fi; }

echo "== B-1: secret-shaped key segments are refused and never persisted or echoed =="
P="$(new_project b1)"
S1="ab0123456789abcdef0123456789abcdef"   # 34 chars of token alphabet: a valid type-name shape
S2="ghp_abcdefghijklmnopqr"               # GitHub token prefix: also a valid type-name shape
for k in "question_types.$S1.mode=shadow" "question_types.$S2.mode=shadow" "question_types.$S2.mode=bogus" \
         "agents.$S2.wiring=consent" "$S2.mode=x" "question_types.$S2.mode=enforce"; do
  expect_rc "secret-shaped key refused ($k)" 4 "$C" --project-root "$P" --non-interactive --set "$k"
done
check "refusal names key material" grep -q 'looks like key material' "$SB/last.err"
no_leak "S1 never written or echoed" "$S1"
no_leak "S2 never written or echoed" "$S2"
printf 'decisions:\n  question_types.%s.mode: shadow\n' "$S2" >"$SB/ans_secret.yml"
expect_rc "secret-shaped key in answers refused" 4 "$C" --project-root "$P" --non-interactive --answers "$SB/ans_secret.yml"
check "answers refusal does not echo the key" bash -c "! grep -qF '$S2' '$SB/last.err'"
expect_rc "secret-shaped --unset refused" 4 "$C" --project-root "$P" --non-interactive --unset "question_types.$S2.mode"
check "--unset refusal does not echo the key" bash -c "! grep -qF '$S2' '$SB/last.err'"
expect_rc "secret-shaped --scope value refused without echo" 2 "$C" --project-root "$P" --scope "$S2" --show
check "argparse error does not echo the value" bash -c "! grep -qF '$S2' '$SB/last.err'"
expect_rc "secret-shaped --doc path refused" 3 "$C" --project-root "$P" --non-interactive --doc "$S2.md" --set hosted.allowed=false
check "--doc refusal does not echo the path" bash -c "! grep -qF '$S2' '$SB/last.err'"
check "no file named after the secret" test ! -e "$P/$S2.md"
# hand-written file with a secret-shaped key: refused by --check without echo
mkdir -p "$P/.constitution"; printf 'schema_version: 1\ninherits: submodules/constitution\ndecisions:\n  question_types.%s.mode: shadow\n' "$S1" >"$P/.constitution/decisions.yml"
sha256sum "$P/.constitution/decisions.yml" | cut -d' ' -f1 >"$P/.constitution/decisions.sha256"
expect_rc "secret-shaped key in file refused by --check" 4 "$C" --project-root "$P" --check
check "--check does not echo the key" bash -c "! grep -qF '$S1' '$SB/last.err' '$SB/last.out'"
expect_rc "--show refuses (no echo)" 4 "$C" --project-root "$P" --show
check "--show does not echo the key" bash -c "! grep -qF '$S1' '$SB/last.err' '$SB/last.out'"
printf 'schema_version: 1\ninherits: %s\ndecisions: {}\n' "$S1" >"$P/.constitution/decisions.yml"
sha256sum "$P/.constitution/decisions.yml" | cut -d' ' -f1 >"$P/.constitution/decisions.sha256"
expect_rc "secret-shaped inherits refused" 4 "$C" --project-root "$P" --check
check "inherits refusal does not echo" bash -c "! grep -qF '$S1' '$SB/last.err' '$SB/last.out'"
rm -f "$P/.constitution/decisions.yml" "$P/.constitution/decisions.sha256"
# positive control: an ordinary type name is still accepted (the check is not a blanket refusal)
expect_rc "ordinary type name accepted" 0 "$C" --project-root "$P" --non-interactive --set question_types.route.mode=shadow

echo "== I-1: --dry-run writes NOTHING in every mode =="
Pd="$(new_project dry)"
"$C" --project-root "$Pd" --non-interactive --set calibration.floor=0.95 >/dev/null 2>&1
printf 'old\n' >"$Pd/exists.yml"
printf 'decisions:\n  calibration.min_sample: 40\n' >"$SB/dry_ans.yml"
printf 'schema_version: 1\ninherits: submodules/constitution\ndecisions:\n  calibration.min_sample: 50\n' >"$SB/dry_imp.yml"
Pn="$SB/dry_fresh"; mkdir -p "$Pn"; mkdir -p "$Pn/submodules/constitution"; git -C "$Pn" init -q
for args in "--export new.yml" "--export exists.yml --force-export" "--export -" "--set calibration.floor=0.96" \
            "--unset calibration.floor" "--reset" "--answers $SB/dry_ans.yml" "--import $SB/dry_imp.yml" \
            "--scope user --set calibration.floor=0.97" "--doc EXTRA.md --set calibration.floor=0.96"; do
  for proj in "$Pd" "$Pn"; do
    t0="$(tree "$proj" "$UD")"
    # shellcheck disable=SC2086
    expect_rc "dry-run $args ($(basename "$proj"))" 0 "$C" --project-root "$proj" --non-interactive --dry-run $args
    check "dry-run $args wrote nothing ($(basename "$proj"))" test "$t0" = "$(tree "$proj" "$UD")"
  done
done
check "fresh project still has no .constitution" test ! -e "$Pn/.constitution"

echo "== I-2: managed block without decisions.yml is drift =="
Pb="$(new_project stale)"
"$C" --project-root "$Pb" --non-interactive --set calibration.floor=0.95 >/dev/null 2>&1
rm -f "$Pb/.constitution/decisions.yml" "$Pb/.constitution/decisions.sha256"
expect_rc "stale block, no yml -> check 4" 4 "$C" --project-root "$Pb" --check
check "drift message names the doc" grep -q 'CLAUDE.md' "$SB/last.err"
Pc="$(new_project clean)"
expect_rc "no yml, no block -> check 0 (control)" 0 "$C" --project-root "$Pc" --check

echo "== I-3: structure-aware markers =="
Pm="$(new_project markers)"
cat >"$Pm/CLAUDE.md" <<'EOF'
# Doc

Example of the managed block:

```markdown
<!-- BEGIN constitution-decisions (example) -->
example body kept
<!-- END constitution-decisions -->
```

User text after the fence.
EOF
cp "$Pm/CLAUDE.md" "$SB/fence.orig"
expect_rc "fenced example markers ignored" 0 "$C" --project-root "$Pm" --non-interactive --set calibration.floor=0.95
check "fenced example kept verbatim" bash -c "head -n \$(wc -l <'$SB/fence.orig') '$Pm/CLAUDE.md' | cmp -s - '$SB/fence.orig'"
check "real block appended after the fence" test "$(grep -c '^<!-- BEGIN constitution-decisions' "$Pm/CLAUDE.md")" = 2
expect_rc "re-run is a no-change with the fence present" 0 "$C" --project-root "$Pm" --non-interactive --set calibration.floor=0.95
check "no-change reported" grep -q 'no-change' "$SB/last.out"
expect_rc "check clean with fenced example" 0 "$C" --project-root "$Pm" --check
Pt="$(new_project trailing)"
printf '# T\n<!-- BEGIN constitution-decisions -->\nold\n<!-- END constitution-decisions --> user note\n' >"$Pt/AGENTS.md"
cp "$Pt/AGENTS.md" "$SB/trail.orig"
expect_rc "END line with trailing user text refused" 4 "$C" --project-root "$Pt" --non-interactive --set calibration.floor=0.95
check "user note not lost (file untouched)" cmp -s "$Pt/AGENTS.md" "$SB/trail.orig"
Pl="$(new_project legacy)"
printf '# L\n<!-- BEGIN constitution-decisions-legacy -->\nlegacy body\n<!-- END constitution-decisions-legacy -->\n' >"$Pl/AGENTS.md"
cp "$Pl/AGENTS.md" "$SB/legacy.orig"
expect_rc "legacy-named markers are not ours" 0 "$C" --project-root "$Pl" --non-interactive --set calibration.floor=0.95
check "legacy block kept verbatim" bash -c "head -n 4 '$Pl/AGENTS.md' | cmp -s - '$SB/legacy.orig'"
check "our block added once" test "$(grep -c '^<!-- BEGIN constitution-decisions (' "$Pl/AGENTS.md")" = 1

echo "== I-4: locked values are never stored; a provider-pin change cannot brick the wizard =="
Pk="$(new_project locked)"
expect_rc "set locked value equal to the lock (no-op)" 0 "$C" --project-root "$Pk" --non-interactive --set keys.var_names=LLMCTL_API_KEY,OPENROUTER_API_KEY,TYPESAFE_API_KEY --set hosted.enforce=false --set calibration.floor=0.95
check "keys.var_names not stored" bash -c "! grep -q 'keys.var_names' '$Pk/.constitution/decisions.yml'"
check "hosted.enforce not stored" bash -c "! grep -q 'hosted.enforce' '$Pk/.constitution/decisions.yml'"
# simulate a wizard-written file from before a provider-pin update (stored var_names no longer equal the pin)
printf 'schema_version: 1\ninherits: submodules/constitution\ndecisions:\n  calibration.floor: 0.95\n  keys.var_names: [OLD_PROVIDER_KEY]\n' >"$Pk/.constitution/decisions.yml"
sha256sum "$Pk/.constitution/decisions.yml" | cut -d' ' -f1 >"$Pk/.constitution/decisions.sha256"
expect_rc "stale locked value: --show still works" 0 "$C" --project-root "$Pk" --show
check "stale locked value is reported" grep -q 'keys.var_names' "$SB/last.err"
expect_rc "stale locked value: --reset recovers" 0 "$C" --project-root "$Pk" --non-interactive --reset
check "reset dropped the stale value" bash -c "! grep -q 'OLD_PROVIDER_KEY' '$Pk/.constitution/decisions.yml'"
expect_rc "check clean after recovery" 0 "$C" --project-root "$Pk" --check
# an invalid stored entry (e.g. a type that became excluded) blocks normal writes but --unset recovers
printf 'schema_version: 1\ninherits: submodules/constitution\ndecisions:\n  calibration.floor: 0.95\n  question_types.review.mode: shadow\n' >"$Pk/.constitution/decisions.yml"
sha256sum "$Pk/.constitution/decisions.yml" | cut -d' ' -f1 >"$Pk/.constitution/decisions.sha256"
expect_rc "invalid stored entry blocks unrelated writes" 4 "$C" --project-root "$Pk" --non-interactive --set calibration.min_sample=40
expect_rc "--unset of the invalid entry recovers" 0 "$C" --project-root "$Pk" --non-interactive --unset question_types.review.mode
check "valid entries survive recovery" grep -q 'calibration.floor: 0.95' "$Pk/.constitution/decisions.yml"
check "invalid entry removed" bash -c "! grep -q 'question_types.review' '$Pk/.constitution/decisions.yml'"
# a static lock weakened by hand is still refused (recovery is not a weakening path)
printf 'schema_version: 1\ninherits: submodules/constitution\ndecisions:\n  hosted.enforce: true\n' >"$Pk/.constitution/decisions.yml"
sha256sum "$Pk/.constitution/decisions.yml" | cut -d' ' -f1 >"$Pk/.constitution/decisions.sha256"
expect_rc "weakened static lock still refused by --check" 4 "$C" --project-root "$Pk" --check

echo "== I-5: printed bootstrap command neutralises ambient JEV_BOOTSTRAP_* =="
Pe="$(new_project envneut)"
"$C" --project-root "$Pe" --non-interactive --set calibration.floor=0.95 >"$SB/env.out" 2>&1
l="$(grep '^bootstrap' "$SB/env.out")"
for v in JEV_BOOTSTRAP_CONSENT JEV_BOOTSTRAP_ALLOW_CLONE JEV_BOOTSTRAP_INSTALL_TOOLS JEV_BOOTSTRAP_AGENTS \
         JEV_BOOTSTRAP_MODE JEV_BOOTSTRAP_DEFER JEV_BOOTSTRAP_DOWNLOAD_PROFILE; do
  check "printed command unsets $v" bash -c "grep -q -- '-u $v' <<<'$l'"
done
# run the printed command prefix with a stub argv to show ambient consent cannot reach the child
pre="$(sed -E 's/^bootstrap \([^)]*\): //; s/ bash .*$//' <<<"$l")"
out="$(env JEV_BOOTSTRAP_CONSENT=1 JEV_BOOTSTRAP_ALLOW_CLONE=1 JEV_BOOTSTRAP_MODE=enforce bash -c "$pre printenv" 2>&1)"
check "ambient consent does not reach bootstrap" bash -c "! grep -qE '^JEV_BOOTSTRAP_(CONSENT|ALLOW_CLONE|MODE)=' <<<'$out'"
Pe2="$(new_project envpin)"
"$C" --project-root "$Pe2" --non-interactive --set llmctl.download_profile=small-1 >"$SB/env2.out" 2>&1
check "download profile pinned explicitly" grep -q 'JEV_BOOTSTRAP_DOWNLOAD_PROFILE=small-1' "$SB/env2.out"

echo "== I-6: in-project symlinked doc is resolved and de-duplicated =="
Ps="$(new_project symdoc)"; rm -f "$Ps/AGENTS.md"; ln -s CLAUDE.md "$Ps/AGENTS.md"
expect_rc "in-project symlinked doc accepted" 0 "$C" --project-root "$Ps" --non-interactive --set calibration.floor=0.95
check "symlink kept as a symlink" test -L "$Ps/AGENTS.md"
check "one block in the shared target" test "$(grep -c '^<!-- BEGIN constitution-decisions' "$Ps/CLAUDE.md")" = 1
expect_rc "check clean with symlinked doc" 0 "$C" --project-root "$Ps" --check
"$C" --project-root "$Ps" --non-interactive --set calibration.floor=0.97 >"$SB/i6.out" 2>&1
check "shared target written exactly once (de-duplicated)" test "$(grep -c '^written: CLAUDE.md$' "$SB/i6.out")" = 1
mkdir -p "$Ps/.git/hooks"; printf 'x\n' >"$Ps/.git/hooks/doc.md"; rm -f "$Ps/AGENTS.md"; ln -s .git/hooks/doc.md "$Ps/AGENTS.md"
expect_rc "symlink into .git refused" 3 "$C" --project-root "$Ps" --non-interactive --set calibration.floor=0.96
check ".git target untouched" test "$(cat "$Ps/.git/hooks/doc.md")" = x

echo "== I-7: discriminating tests (re-read under lock, intent window, every excluded stem) =="
Pr="$(new_project reread)"
"$C" --project-root "$Pr" --non-interactive --set calibration.floor=0.95 >/dev/null 2>&1
CONSTITUTION_DECISIONS_TEST=1 CONSTITUTION_DECISIONS_TEST_PRELOCK_DELAY=2 "$C" --project-root "$Pr" --non-interactive --set calibration.min_sample=40 >"$SB/b.out" 2>&1 &
bpid=$!; sleep 0.5
"$C" --project-root "$Pr" --non-interactive --set calibration.cadence_days=3 >"$SB/a.out" 2>&1; arc=$?
wait "$bpid"; brc=$?
check "first writer done during the window (rc=$arc)" test "$arc" = 0
check "second writer done (rc=$brc)" test "$brc" = 0
check "both concurrent changes kept (state re-read under lock)" bash -c "grep -q 'calibration.cadence_days: 3' '$Pr/.constitution/decisions.yml' && grep -q 'calibration.min_sample: 40' '$Pr/.constitution/decisions.yml'"
Pi="$(new_project intent)"
"$C" --project-root "$Pi" --non-interactive --set calibration.floor=0.95 >/dev/null 2>&1
# crash window: new yml written, intent holds its sha, sidecar still the previous sha
printf 'schema_version: 1\ninherits: submodules/constitution\ndecisions:\n  calibration.floor: 0.96\n' >"$Pi/.constitution/decisions.yml"
sha256sum "$Pi/.constitution/decisions.yml" | cut -d' ' -f1 >"$Pi/.constitution/decisions.intent"
expect_rc "intent window is not a hand edit (writes allowed)" 0 "$C" --project-root "$Pi" --non-interactive --set calibration.min_sample=40
check "intent cleared after recovery" test ! -e "$Pi/.constitution/decisions.intent"
expect_rc "check clean after intent recovery" 0 "$C" --project-root "$Pi" --check
Px="$(new_project stems)"
for s in review merge conflict finding qa readiness ready evidence verif verdict; do
  expect_rc "bare excluded stem $s: enforce refused" 4 "$C" --project-root "$Px" --non-interactive --set layer.mode=enforce --set "question_types.$s.mode=enforce"
  expect_rc "bare excluded stem $s: shadow refused" 4 "$C" --project-root "$Px" --non-interactive --set "question_types.$s.mode=shadow"
  check "stem $s refused by the exclusion lock" grep -q 'locked by the constitution' "$SB/last.err"
done

echo "== I-8: JEV_BOOTSTRAP_MODE needs --accept-env =="
P8="$(new_project modeenv)"
expect_rc "env mode without --accept-env: not recorded" 0 env JEV_BOOTSTRAP_MODE=off "$C" --project-root "$P8" --non-interactive --set calibration.floor=0.95
check "layer.mode not recorded" bash -c "! grep -q 'layer.mode' '$P8/.constitution/decisions.yml'"
check "ignored mode is named" grep -q 'JEV_BOOTSTRAP_MODE' "$SB/last.err"
expect_rc "env mode with --accept-env recorded" 0 env JEV_BOOTSTRAP_MODE=off "$C" --project-root "$P8" --non-interactive --accept-env --set calibration.floor=0.95
check "layer.mode recorded" grep -q 'layer.mode: "off"' "$P8/.constitution/decisions.yml"

echo "== MINOR: clean refusals, contradictions, bounded backups, user backup outside the project =="
P9="$(new_project minor3)"
expect_rc "--export into missing dir refused" 3 "$C" --project-root "$P9" --export nodir/x.yml
check "no traceback (missing dir)" bash -c "! grep -q Traceback '$SB/last.err'"
check "missing-dir refusal names the --export target" grep -q -- '--export nodir/x.yml: the directory does not exist' "$SB/last.err"
expect_rc "--dry-run --export into missing dir refused too (no false 'would export')" 3 "$C" --project-root "$P9" --export nodir/x.yml --dry-run
mkdir -p "$P9/adir"
expect_rc "--export onto a directory refused" 3 "$C" --project-root "$P9" --export adir --force-export
check "no traceback (directory)" bash -c "! grep -q Traceback '$SB/last.err'"
mkdir -p "$P9/.constitution-install-backup"
expect_rc "--export into backup dir refused" 3 "$C" --project-root "$P9" --export .constitution-install-backup/x.yml
check "…by the forbidden-directory rule (the directory exists)" grep -q 'may not target' "$SB/last.err"
P10="$(new_project cfile)"; printf 'not a dir\n' >"$P10/.constitution"
expect_rc ".constitution as a regular file refused" 3 "$C" --project-root "$P10" --non-interactive --set calibration.floor=0.95
check "no traceback (.constitution file)" bash -c "! grep -q Traceback '$SB/last.err'"
check ".constitution file untouched" test "$(cat "$P10/.constitution")" = "not a dir"
expect_rc "--show with .constitution as a regular file refused" 3 "$C" --project-root "$P10" --show
check "--show names the broken layout" grep -q '.constitution exists and is not a directory' "$SB/last.err"
expect_rc "--check with .constitution as a regular file refused" 3 "$C" --project-root "$P10" --check
P11="$(new_project contra)"
expect_rc "hosted.allowed=false + explicit hosted endpoint refused" 4 "$C" --project-root "$P11" --non-interactive --set hosted.allowed=false --set endpoints.preference=local,hosted
expect_rc "hosted.allowed=false + default endpoints ok" 0 "$C" --project-root "$P11" --non-interactive --set hosted.allowed=false
expect_rc "effective endpoints drop hosted" 0 "$C" --project-root "$P11" --show --json
check "effective preference has no hosted" python3 -I -c "import json,sys;d=json.load(open(sys.argv[1]));sys.exit(0 if d['effective']['endpoints.preference']['value']==['local','lan'] else 1)" "$SB/last.out"
expect_rc "type enforce under shadow layer refused" 4 "$C" --project-root "$P11" --non-interactive --set question_types.gate.mode=enforce
check "refused as a contradiction" grep -q 'contradiction' "$SB/last.err"
expect_rc "type enforce under enforce layer ok" 0 "$C" --project-root "$P11" --non-interactive --set layer.mode=enforce --set question_types.gate.mode=enforce
P12="$(new_project bkcap)"
for i in 1 2 3 4 5 6; do CONSTITUTION_DECISIONS_BACKUP_KEEP=3 "$C" --project-root "$P12" --non-interactive --set "calibration.min_sample=4$i" >/dev/null 2>&1; done
check "backup count bounded (keep=3)" test "$(ls "$P12/.constitution-install-backup" | grep -c 'decisions')" = 3
check "newest backup kept" bash -c "grep -q 'calibration.min_sample: 45' \"\$(ls -d '$P12'/.constitution-install-backup/*decisions* | sort | tail -1)/.constitution/decisions.yml\""
mkdir -p "$P12/.constitution-install-backup/keepme"; printf 'x\n' >"$P12/.constitution-install-backup/keepme/f"
CONSTITUTION_DECISIONS_BACKUP_KEEP=1 "$C" --project-root "$P12" --non-interactive --set calibration.min_sample=99 >/dev/null 2>&1
check "foreign backup dirs never pruned" test -f "$P12/.constitution-install-backup/keepme/f"
P13="$(new_project ubk)"
"$C" --project-root "$P13" --scope user --non-interactive --set hosted.allowed=false >/dev/null 2>&1
expect_rc "user write with backup" 0 "$C" --project-root "$P13" --scope user --non-interactive --set hosted.allowed=true
check "user backup not inside the project" bash -c "! ls '$P13'/.constitution-install-backup/*/user >/dev/null 2>&1"
check "user backup beside the user file" bash -c "grep -q 'hosted.allowed: false' '$UD'/.decisions-backup/*.yml"
check "user backup location is printed" grep -q 'backup (user decisions file)' "$SB/last.out"
echo "== refactor survivors (MT4, MT6, N19): layers the round-3 refactor left as the only guard =="
Px="$(new_project survivors)"
"$C" --project-root "$Px" --non-interactive --set calibration.floor=0.95 >/dev/null 2>&1
printf 'keep\n' >"$Px/real.yml"; ln -s real.yml "$Px/link.yml"
expect_rc "--export onto a symlink refused (even with --force-export)" 3 "$C" --project-root "$Px" --export link.yml --force-export
check "--export symlink refusal names the symlink" grep -q 'link.yml is a symlink; refused' "$SB/last.err"
check "export symlink kept as a symlink" test -L "$Px/link.yml"
check "export symlink target untouched" test "$(cat "$Px/real.yml")" = keep
Pd="$(new_project dupmarkers)"
printf '<!-- BEGIN constitution-decisions -->\nx\n<!-- END constitution-decisions -->\n<!-- BEGIN constitution-decisions -->\ny\n<!-- END constitution-decisions -->\n' >>"$Pd/CLAUDE.md"
expect_rc "--check: duplicate markers with no decisions file refused" 4 "$C" --project-root "$Pd" --check
check "--check names the duplicate markers (not a stale-block verdict)" grep -q 'duplicate or unbalanced constitution-decisions markers' "$SB/last.err"
expect_rc "unknown non-secret key refused" 4 "$C" --project-root "$Px" --non-interactive --set 'zz.Unknown Visible=1'
check "unknown key is not echoed" bash -c "! grep -q 'Unknown Visible' '$SB/last.err' '$SB/last.out'"
check "unknown key shown as a hash label" grep -q 'key#' "$SB/last.err"
finish test_round3
