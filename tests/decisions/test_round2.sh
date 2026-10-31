#!/usr/bin/env bash
# test_round2.sh — regression tests for the round-1 independent review (B1-B4, I1-I8, reviewer survivors,
# minor items). Class: integration against REAL git projects and the REAL wizard; no test doubles.
set -u
. "$(dirname "$0")/lib.sh"
new_sandbox; trap cleanup_sandbox EXIT
C="$DEC_CLI"
P="$(new_project r2)"; D="$P/.constitution/decisions.yml"
"$C" --project-root "$P" --non-interactive --set calibration.floor=0.95 >/dev/null 2>&1
h0="$(sha "$D")"
echo "== B1: trailing newline in keys (regex \$ class) =="
expect_rc "key with trailing newline refused (qtype)" 4 "$C" --project-root "$P" --non-interactive --set "question_types.gate.mode
=shadow"
# layer oracle: the key-shape check must refuse it (later YAML/catalogue layers would also refuse it)
check "qtype newline key refused at the key-shape layer" grep -q 'invalid decision key' "$SB/last.err"
expect_rc "key with trailing newline refused (agent)" 4 "$C" --project-root "$P" --non-interactive --set "agents.claude.wiring
=consent"
expect_rc "key with trailing newline refused (static)" 4 "$C" --project-root "$P" --non-interactive --set "calibration.floor
=0.96"
printf 'decisions:\n  "question_types.gate.mode\\n": shadow\n' >"$SB/nl_key.yml"
expect_rc "answers key with newline refused" 4 "$C" --project-root "$P" --non-interactive --answers "$SB/nl_key.yml"
check "answers newline key refused at the key-shape layer" grep -q 'invalid decision key' "$SB/last.err"
printf 'decisions:\n  llmctl.download_profile: "abc\\n"\n' >"$SB/nl_val.yml"
expect_rc "answers value with newline refused" 4 "$C" --project-root "$P" --non-interactive --answers "$SB/nl_val.yml"
check "decisions.yml unchanged after B1 attempts" test "$(sha "$D")" = "$h0"
expect_rc "check still clean" 0 "$C" --project-root "$P" --check
echo "== B2: --export confinement =="
c0="$(sha "$P/CLAUDE.md")"; g0="$(sha "$P/.git/config")"
expect_rc "export onto existing CLAUDE.md refused" 3 "$C" --project-root "$P" --export CLAUDE.md
check "CLAUDE.md untouched" test "$(sha "$P/CLAUDE.md")" = "$c0"
expect_rc "export into .git refused" 3 "$C" --project-root "$P" --export .git/config
expect_rc "export into .git (new file) refused" 3 "$C" --project-root "$P" --export .git/newfile
check ".git/config untouched" test "$(sha "$P/.git/config")" = "$g0"
check ".git/newfile not created" test ! -e "$P/.git/newfile"
expect_rc "export into .constitution refused" 3 "$C" --project-root "$P" --export .constitution/copy.yml
expect_rc "export new file ok" 0 "$C" --project-root "$P" --export exported.yml
check "export written" grep -q 'calibration.floor: 0.95' "$P/exported.yml"
expect_rc "export onto existing export refused" 3 "$C" --project-root "$P" --export exported.yml
expect_rc "export with --force-export" 0 "$C" --project-root "$P" --export exported.yml --force-export
check "force export backed up" bash -c "ls '$P'/.constitution-install-backup/*/exported.yml >/dev/null 2>&1"
echo "== B3/R22: printed bootstrap command implies exactly the recorded consents =="
bline() { "$C" --project-root "$1" --plan 2>/dev/null | grep '^bootstrap'; }
mkp() { local p; p="$(new_project "$1")"; shift; "$C" --project-root "$p" --non-interactive "$@" >/dev/null 2>&1; printf '%s' "$p"; }
p1="$(mkp b3a --set agents.claude.wiring=consent)"; l="$(bline "$p1")"
check "claude consent without clone/settings: no --yes" bash -c "! grep -q -- '--yes' <<<'$l'"
check "claude consent without settings consent: claude not wired" bash -c "! grep -q -- '--agent claude' <<<'$l'"
check "missing consent is explained" bash -c "\"$C\" --project-root '$p1' --plan | grep -q 'not wired'"
p2="$(mkp b3b --set agents.pi.wiring=consent)"; l="$(bline "$p2")"
check "pi consent without clone consent: no --yes" bash -c "! grep -q -- '--yes' <<<'$l'"
p3="$(mkp b3c --set agents.pi.wiring=consent --set llmctl.clone_consent=true)"; l="$(bline "$p3")"
check "pi + clone consent: --yes --agent pi" bash -c "grep -q -- '--agent pi --yes' <<<'$l'"
p4="$(mkp b3d --set agents.claude.wiring=consent --set llmctl.clone_consent=true --set agents.settings_json_consent=true)"; l="$(bline "$p4")"
check "claude + clone + settings consent: --yes --agent claude" bash -c "grep -q -- '--agent claude --yes' <<<'$l'"
p5="$(mkp b3e --set agents.claude.wiring=consent --set agents.kimi.wiring=consent --set llmctl.clone_consent=true)"; l="$(bline "$p5")"
check "claude dropped, kimi kept when settings consent absent" bash -c "grep -q -- '--agent kimi --yes' <<<'$l'"
p6="$(mkp b3f --set layer.mode=enforce)"; l="$(bline "$p6")"
check "R22 enforce flag printed" bash -c "grep -q -- '--enforce' <<<'$l'"
check "no consent recorded: no --yes/--allow-clone/--install-tools" bash -c "! grep -qE -- '--yes|--allow-clone|--install-tools' <<<'$l'"
p7="$(mkp b3g --set llmctl.install_consent=true)"; l="$(bline "$p7")"
check "install consent only: --install-tools without --allow-clone" bash -c "grep -q -- '--install-tools' <<<'$l' && ! grep -q -- '--allow-clone' <<<'$l'"
p8="$(mkp b3h --set hosted.allowed=false)"; l="$(bline "$p8")"
check "hosted off: JEV_HOSTED_PROBE=0" bash -c "grep -q 'JEV_HOSTED_PROBE=0' <<<'$l'"
echo "== B4: key discovery and var names are locked =="
expect_rc "discovery off refused" 4 "$C" --project-root "$P" --non-interactive --set keys.discovery_consent=false
expect_rc "empty var_names refused" 4 "$C" --project-root "$P" --non-interactive --set keys.var_names=
expect_rc "subset var_names refused" 4 "$C" --project-root "$P" --non-interactive --set keys.var_names=TYPESAFE_API_KEY
echo "== I1: endpoints must keep local =="
expect_rc "drop local refused" 4 "$C" --project-root "$P" --non-interactive --set endpoints.preference=lan,hosted
expect_rc "hosted only refused" 4 "$C" --project-root "$P" --non-interactive --set endpoints.preference=hosted
expect_rc "local only ok" 0 "$C" --project-root "$P" --non-interactive --set endpoints.preference=local
echo "== I2/R04/R05: excluded classes and default-deny enforce =="
for t in review merge finding_layer qa readiness evidence verifier code_review reviews qa_check merge_conflict pre_merge verify_step evidence_gate; do
  expect_rc "excluded $t enforce refused" 4 "$C" --project-root "$P" --non-interactive --set "question_types.$t.mode=enforce"
  expect_rc "excluded $t shadow refused" 4 "$C" --project-root "$P" --non-interactive --set "question_types.$t.mode=shadow"
done
expect_rc "excluded verifier off ok" 0 "$C" --project-root "$P" --non-interactive --set question_types.verifier.mode=off
expect_rc "unknown type enforce refused (default-deny)" 4 "$C" --project-root "$P" --non-interactive --set layer.mode=enforce --set question_types.foo.mode=enforce
check "refused by default-deny (layer oracle)" grep -q 'default-deny' "$SB/last.err"
expect_rc "unknown type shadow ok" 0 "$C" --project-root "$P" --non-interactive --set question_types.foo.mode=shadow
expect_rc "eligible gate enforce ok" 0 "$C" --project-root "$P" --non-interactive --set layer.mode=enforce --set question_types.gate.mode=enforce
echo "== I3: managed-block drift =="
Pd="$(mkp drift --set calibration.floor=0.95)"
expect_rc "check clean" 0 "$C" --project-root "$Pd" --check
sed -i 's/`calibration.floor`: 0.95/`calibration.floor`: 0.5/' "$Pd/CLAUDE.md"
expect_rc "edited block -> check 4" 4 "$C" --project-root "$Pd" --check
expect_rc "edited block -> gate FAIL" 1 bash "$DEC_REPO/scripts/gates/cm_decisions_override_valid.sh" --root "$Pd"
expect_rc "re-run repairs the block" 0 "$C" --project-root "$Pd" --non-interactive
expect_rc "check clean after repair" 0 "$C" --project-root "$Pd" --check
python3 -I -c "import re,sys;p=sys.argv[1];s=open(p).read();open(p,'w').write(re.sub(r'<!-- BEGIN constitution-decisions.*?<!-- END constitution-decisions -->\n','',s,flags=re.S))" "$Pd/AGENTS.md"
expect_rc "removed block -> check 4" 4 "$C" --project-root "$Pd" --check
echo "== I4: unknown or secret-shaped keys never echoed =="
K1="zzzz.$(printf 'q%.0s' $(seq 1 36))"
expect_rc "long unknown key refused" 4 "$C" --project-root "$P" --non-interactive --set "$K1=1"
check "long unknown key not echoed" bash -c "! grep -qF '$K1' '$SB/last.err' '$SB/last.out'"
K2="sk-$(printf 'Y%.0s' $(seq 1 30))"
expect_rc "secret key refused" 4 "$C" --project-root "$P" --non-interactive --set "$K2=1"
check "secret key not echoed" bash -c "! grep -qF '$K2' '$SB/last.err' '$SB/last.out'"
printf 'decisions:\n  %s: 1\n' "$K1" >"$SB/k1.yml"
expect_rc "answers unknown key refused" 4 "$C" --project-root "$P" --non-interactive --answers "$SB/k1.yml"
check "answers unknown key not echoed" bash -c "! grep -qF '$K1' '$SB/last.err'"
echo "== I5: ambient JEV_BOOTSTRAP_* consent needs --accept-env =="
Pe="$(new_project envp)"
expect_rc "env without --accept-env" 0 env JEV_BOOTSTRAP_NON_INTERACTIVE=1 JEV_BOOTSTRAP_MODE=enforce JEV_BOOTSTRAP_AGENTS=claude JEV_BOOTSTRAP_ALLOW_CLONE=1 "$C" --project-root "$Pe"
check "mode NOT taken from env without --accept-env (round 3, I-8)" bash -c "! grep -q 'layer.mode' '$Pe/.constitution/decisions.yml'"
check "agent consent NOT taken without --accept-env" bash -c "! grep -q 'agents.claude.wiring' '$Pe/.constitution/decisions.yml'"
check "clone consent NOT taken without --accept-env" bash -c "! grep -q 'clone_consent' '$Pe/.constitution/decisions.yml'"
check "ignored env names reported" grep -q 'JEV_BOOTSTRAP_AGENTS' "$SB/last.err"
expect_rc "env with --accept-env" 0 env JEV_BOOTSTRAP_NON_INTERACTIVE=1 JEV_BOOTSTRAP_AGENTS=claude JEV_BOOTSTRAP_ALLOW_CLONE=1 "$C" --project-root "$Pe" --accept-env
check "agent consent taken with --accept-env" grep -q 'agents.claude.wiring: consent' "$Pe/.constitution/decisions.yml"
echo "== I6: --doc targets =="
expect_rc "--doc .git/config refused" 3 "$C" --project-root "$P" --non-interactive --doc .git/config --set hosted.allowed=true
check ".git/config untouched by --doc" test "$(sha "$P/.git/config")" = "$g0"
expect_rc "--doc .constitution/x.md refused" 3 "$C" --project-root "$P" --non-interactive --doc .constitution/x.md --set hosted.allowed=true
printf 'plain\n' >"$P/notes.txt"
expect_rc "--doc non-markdown without markers refused" 3 "$C" --project-root "$P" --non-interactive --doc notes.txt --set hosted.allowed=true
check "notes.txt untouched" test "$(cat "$P/notes.txt")" = plain
printf 'plain\n<!-- BEGIN constitution-decisions -->\n<!-- END constitution-decisions -->\n' >"$P/notes.txt"
expect_rc "--doc non-markdown with markers ok" 0 "$C" --project-root "$P" --non-interactive --doc notes.txt --set hosted.allowed=true
expect_rc "--doc new markdown ok" 0 "$C" --project-root "$P" --non-interactive --doc LOCAL_CONSTITUTION.md --set hosted.allowed=false
check "new markdown has block" grep -q 'BEGIN constitution-decisions' "$P/LOCAL_CONSTITUTION.md"
echo "== I7: lock file symlink =="
Pl="$(mkp lockp --set hosted.allowed=false)"; printf 'victim\n' >"$SB/victim"
rm -f "$Pl/.constitution/.decisions.lock"; ln -s "$SB/victim" "$Pl/.constitution/.decisions.lock"
expect_rc "symlinked lock refused" 3 "$C" --project-root "$Pl" --non-interactive --set hosted.allowed=true
check "lock symlink target untouched" test "$(cat "$SB/victim")" = victim
echo "== I8/R17/R21: user scope lock, backup, symlink =="
Pu="$(new_project userp)"
expect_rc "user write 1" 0 "$C" --project-root "$Pu" --scope user --non-interactive --set hosted.allowed=false
expect_rc "user write 2" 0 "$C" --project-root "$Pu" --scope user --non-interactive --set hosted.allowed=true
check "R17 user file backed up (beside the user file, round 3)" bash -c "grep -q 'hosted.allowed: false' \"$(dirname "$CONSTITUTION_DECISIONS_USER_FILE")\"/.decisions-backup/*.yml"
CONSTITUTION_DECISIONS_TEST=1 CONSTITUTION_DECISIONS_TEST_WRITE_DELAY=3 "$C" --project-root "$Pu" --scope user --non-interactive --set calibration.floor=0.93 >/dev/null 2>&1 &
up=$!
for _ in $(seq 1 50); do ls "$(dirname "$CONSTITUTION_DECISIONS_USER_FILE")"/.decisions.yml.tmp.* >/dev/null 2>&1 && break; sleep 0.1; done
expect_rc "I8 concurrent user writer refused" 5 "$C" --project-root "$Pu" --scope user --non-interactive --set calibration.floor=0.94
wait "$up"
mv "$CONSTITUTION_DECISIONS_USER_FILE" "$SB/realuser.yml"; ln -s "$SB/realuser.yml" "$CONSTITUTION_DECISIONS_USER_FILE"; u0="$(sha "$SB/realuser.yml")"
expect_rc "R21 user file symlink refused" 3 "$C" --project-root "$Pu" --scope user --non-interactive --set hosted.allowed=false
check "R21 symlink target untouched" test "$(sha "$SB/realuser.yml")" = "$u0"
rm -f "$CONSTITUTION_DECISIONS_USER_FILE"
echo "== R10: control characters refused =="
for cc in $'\e[31m' $'a\rb' $'a\tb' $'a\x7fb'; do
  expect_rc "control char refused" 4 "$C" --project-root "$P" --non-interactive --set "llmctl.download_profile=$cc"
  # oracle: the control-character layer must be the one that refused (PROFILE_RE would also refuse)
  check "control char refused by the control-char check" grep -q 'control characters' "$SB/last.err"
done
# paths have no regex layer: has_control is the only check, so a narrowed check lets these through
for cc in $'a\tb.md' $'a\eb.md' $'a\x7fb.md'; do
  expect_rc "control char in --doc path refused" 3 "$C" --project-root "$P" --non-interactive --doc "$cc" --set calibration.floor=0.93
  check "no file created for control-char --doc path" test ! -e "$P/$cc"
done
echo "== minor: non-UTF-8 doc, CRLF, strict schema_version =="
Pm="$(new_project minor)"; printf '# T\n\xff\xfe bad\n' >"$Pm/GEMINI.md"
expect_rc "non-UTF-8 doc refused cleanly" 4 "$C" --project-root "$Pm" --non-interactive --set hosted.allowed=false
check "no traceback" bash -c "! grep -q Traceback '$SB/last.err'"
rm -f "$Pm/GEMINI.md"; printf '# W\r\nline one\r\n' >"$Pm/QWEN.md"
expect_rc "CRLF doc" 0 "$C" --project-root "$Pm" --non-interactive --set hosted.allowed=false
check "CRLF kept: no bare LF line" python3 -I -c "import sys;b=open(sys.argv[1],'rb').read();sys.exit(0 if b.count(b'\n')==b.count(b'\r\n') else 1)" "$Pm/QWEN.md"
check "CRLF doc user text kept" grep -q $'^line one\r$' "$Pm/QWEN.md"
# clean project with no docs: --check must refuse on the schema, not on block drift (confounded oracle)
Ps="$(new_project schema)"; rm -f "${Ps:?}/CLAUDE.md" "${Ps:?}/AGENTS.md"; mkdir -p "$Ps/.constitution"
printf 'schema_version: 1\ninherits: submodules/constitution\ndecisions: {}\n' >"$Ps/.constitution/decisions.yml"
sha256sum "$Ps/.constitution/decisions.yml" | cut -d' ' -f1 >"$Ps/.constitution/decisions.sha256"
expect_rc "schema_version 1 accepted (positive control)" 0 "$C" --project-root "$Ps" --check
for sv in '"1"' 'true' '1.0' '2'; do
  printf 'schema_version: %s\ninherits: submodules/constitution\ndecisions: {}\n' "$sv" >"$Ps/.constitution/decisions.yml"
  sha256sum "$Ps/.constitution/decisions.yml" | cut -d' ' -f1 >"$Ps/.constitution/decisions.sha256"
  expect_rc "schema_version $sv refused" 4 "$C" --project-root "$Ps" --check
  check "schema_version $sv refused for the schema" grep -q 'schema_version must be the integer 1' "$SB/last.err"
done
printf 'inherits: submodules/constitution\ndecisions: {}\n' >"$Ps/.constitution/decisions.yml"
sha256sum "$Ps/.constitution/decisions.yml" | cut -d' ' -f1 >"$Ps/.constitution/decisions.sha256"
expect_rc "missing schema_version refused" 4 "$C" --project-root "$Ps" --check
check "missing schema_version refused for the schema" grep -q 'schema_version must be the integer 1' "$SB/last.err"
finish test_round2
