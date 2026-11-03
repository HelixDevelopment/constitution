#!/usr/bin/env bash
# test_core.sh — unit, integration, security, idempotency and determinism tests for the decisions wizard.
# Class: integration against REAL git projects and the REAL wizard; no test doubles.
set -u
. "$(dirname "$0")/lib.sh"
new_sandbox; trap cleanup_sandbox EXIT
P="$(new_project p1)"; C="$DEC_CLI"
echo "== unit: catalogue validation =="
expect_rc "unknown key refused"           4 "$C" --project-root "$P" --non-interactive --set bogus.key=1
expect_rc "floor below 0.90 refused"      4 "$C" --project-root "$P" --non-interactive --set calibration.floor=0.5
expect_rc "floor raised accepted"         0 "$C" --project-root "$P" --non-interactive --set calibration.floor=0.95
expect_rc "min_sample below 30 refused"   4 "$C" --project-root "$P" --non-interactive --set calibration.min_sample=10
expect_rc "cadence 30 days refused"       4 "$C" --project-root "$P" --non-interactive --set calibration.cadence_days=30
expect_rc "hosted.enforce=true refused"   4 "$C" --project-root "$P" --non-interactive --set hosted.enforce=true
expect_rc "hosted.enforce=false no-op ok" 0 "$C" --project-root "$P" --non-interactive --set hosted.enforce=false
expect_rc "validate_strict=false refused" 4 "$C" --project-root "$P" --non-interactive --set llmctl.validate_strict=false
expect_rc "token arm off refused"         4 "$C" --project-root "$P" --non-interactive --set proof.token_reduction_arm=off
expect_rc "ratio above 1.0 refused"       4 "$C" --project-root "$P" --non-interactive --set proof.max_after_before_ratio=1.5
expect_rc "endpoint reorder refused"      4 "$C" --project-root "$P" --non-interactive --set endpoints.preference=hosted,local
expect_rc "endpoint subset ok"            0 "$C" --project-root "$P" --non-interactive --set endpoints.preference=local,hosted
expect_rc "excluded class enforce refused" 4 "$C" --project-root "$P" --non-interactive --set question_types.review.mode=enforce
expect_rc "excluded class off ok"         0 "$C" --project-root "$P" --non-interactive --set question_types.review.mode=off
expect_rc "bad type name refused"         4 "$C" --project-root "$P" --non-interactive --set 'question_types.Bad-Name.mode=shadow'
expect_rc "unknown agent refused"         4 "$C" --project-root "$P" --non-interactive --set agents.evilbot.wiring=consent
expect_rc "agent consent ok"              0 "$C" --project-root "$P" --non-interactive --set agents.claude.wiring=consent
expect_rc "bad enum refused"              4 "$C" --project-root "$P" --non-interactive --set layer.mode=maybe
expect_rc "contradiction off+enforce"     4 "$C" --project-root "$P" --non-interactive --set layer.mode=off --set question_types.gate.mode=enforce
expect_rc "contradiction never_enforce"   4 "$C" --project-root "$P" --non-interactive --set exclusions.never_enforce=gate --set question_types.gate.mode=enforce
expect_rc "key var name outside set"      4 "$C" --project-root "$P" --non-interactive --set keys.var_names=AWS_SECRET_ACCESS_KEY
expect_rc "duplicate --set refused"       2 "$C" --project-root "$P" --non-interactive --set layer.mode=off --set layer.mode=shadow
expect_rc "bad profile name refused"      4 "$C" --project-root "$P" --non-interactive --set 'llmctl.download_profile=../x'
expect_rc "budget negative refused"       4 "$C" --project-root "$P" --non-interactive --set budget.max_usd_per_day=-1
expect_rc "budget ok"                     0 "$C" --project-root "$P" --non-interactive --set budget.max_usd_per_day=2.5

echo "== integration: files, blocks, show, reset, import/export =="
D="$P/.constitution/decisions.yml"
check "decisions.yml written" test -f "$D"
check "sha sidecar written" test -f "$P/.constitution/decisions.sha256"
check "inherits submodules/constitution" grep -q '^inherits: submodules/constitution$' "$D"
check "floor override stored" grep -q 'calibration.floor: 0.95' "$D"
check "refused values never stored" bash -c "! grep -q 'calibration.floor: 0.5' '$D'"
check "CLAUDE.md user text kept" grep -q '^User text above.$' "$P/CLAUDE.md"
check "CLAUDE.md block present" grep -q 'BEGIN constitution-decisions' "$P/CLAUDE.md"
check "AGENTS.md block present" grep -q 'BEGIN constitution-decisions' "$P/AGENTS.md"
check "GEMINI.md not created" test ! -e "$P/GEMINI.md"
check "block names inheritance" grep -q 'inherits from submodules/constitution' "$P/CLAUDE.md"
check "exactly one BEGIN marker" test "$(grep -c 'BEGIN constitution-decisions' "$P/CLAUDE.md")" = 1
check "backup dir created" bash -c "ls -d '$P'/.constitution-install-backup/*-decisions >/dev/null 2>&1"
"$C" --project-root "$P" --show --json >"$SB/show.json"; check "show --json rc0" test $? = 0
check "show reports source project" python3 -c "import json,sys;d=json.load(open('$SB/show.json'));sys.exit(0 if d['effective']['calibration.floor']['source']=='project' and d['effective']['calibration.floor']['value']==0.95 else 1)"
check "show reports constitution default" python3 -c "import json,sys;d=json.load(open('$SB/show.json'));sys.exit(0 if d['effective']['calibration.min_sample']['source']=='constitution' else 1)"
expect_rc "check clean" 0 "$C" --project-root "$P" --check
"$C" --project-root "$P" --export - >"$SB/export.yml"; check "export rc0" test $? = 0
check "export has floor" grep -q 'calibration.floor: 0.95' "$SB/export.yml"
expect_rc "export path outside project refused" 3 "$C" --project-root "$P" --export "$SB/outside.yml"
check "outside export not written" test ! -e "$SB/outside.yml"
expect_rc "unset key" 0 "$C" --project-root "$P" --non-interactive --unset budget.max_usd_per_day
check "unset removed" bash -c "! grep -q budget.max_usd_per_day '$D'"
expect_rc "reset" 0 "$C" --project-root "$P" --non-interactive --reset
check "reset empties overrides" grep -q '^decisions: {}$' "$D"
check "block says all inherited" grep -q 'All decisions are inherited' "$P/CLAUDE.md"
expect_rc "import" 0 "$C" --project-root "$P" --non-interactive --import "$SB/export.yml"
check "import restored floor" grep -q 'calibration.floor: 0.95' "$D"
printf 'decisions:\n  layer.mode: off\n  hosted.allowed: false\n  endpoints.preference: [local, lan]\n' >"$SB/answers.yml"
expect_rc "answers file" 0 "$C" --project-root "$P" --non-interactive --answers "$SB/answers.yml"
check "answers applied" grep -q 'layer.mode: "off"' "$D"
expect_rc "set wins over answers" 0 "$C" --project-root "$P" --non-interactive --answers "$SB/answers.yml" --set layer.mode=shadow
check "set precedence" grep -q 'layer.mode: shadow' "$D"

echo "== integration: env JEV_BOOTSTRAP_* mapping =="
P2="$(new_project p2)"
expect_rc "env mapping" 0 env JEV_BOOTSTRAP_NON_INTERACTIVE=1 JEV_BOOTSTRAP_MODE=enforce JEV_BOOTSTRAP_AGENTS=claude,pi JEV_BOOTSTRAP_ALLOW_CLONE=1 "$C" --project-root "$P2" --accept-env
check "env mode" grep -q 'layer.mode: enforce' "$P2/.constitution/decisions.yml"
check "env agents" grep -q 'agents.pi.wiring: consent' "$P2/.constitution/decisions.yml"
check "env clone" grep -q 'llmctl.clone_consent: true' "$P2/.constitution/decisions.yml"
expect_rc "env bad mode refused" 4 env JEV_BOOTSTRAP_NON_INTERACTIVE=1 JEV_BOOTSTRAP_MODE=yolo "$C" --project-root "$P2" --accept-env

echo "== integration: legacy ./constitution layout and no TTY =="
P3="$SB/p3"; mkdir -p "$P3/constitution"; git -C "$P3" init -q
expect_rc "legacy layout" 0 "$C" --project-root "$P3" --non-interactive --set hosted.allowed=false
check "inherits constitution" grep -q '^inherits: constitution$' "$P3/.constitution/decisions.yml"
expect_rc "no TTY no flag -> 2" 2 setsid "$C" --project-root "$P3" </dev/null
expect_rc "missing project root" 3 "$C" --project-root "$SB/nope" --show

echo "== user scope and conflicts =="
expect_rc "user scope write" 0 "$C" --project-root "$P3" --scope user --non-interactive --set hosted.allowed=true
check "user file inside sandbox" test -f "$CONSTITUTION_DECISIONS_USER_FILE"
"$C" --project-root "$P3" --show --json >"$SB/s3.json"
check "conflict reported" python3 -c "import json,sys;d=json.load(open('$SB/s3.json'));sys.exit(0 if any(c['key']=='hosted.allowed' for c in d['conflicts']) and d['effective']['hosted.allowed']['value'] is False else 1)"

echo "== security =="
P4="$(new_project p4)"
SECRET="sk-$(printf 'A%.0s' $(seq 1 40))"
expect_rc "secret-looking value refused" 4 "$C" --project-root "$P4" --non-interactive --set "llmctl.download_profile=$SECRET"
check "secret absent from tree" bash -c "! grep -rqF '$SECRET' '$P4'"
check "secret not echoed" bash -c "! grep -qF '$SECRET' '$SB/last.err' '$SB/last.out'"
expect_rc "injection in key refused" 4 "$C" --project-root "$P4" --non-interactive --set 'layer.mode;touch /tmp/x=on'
expect_rc "newline in value refused" 4 "$C" --project-root "$P4" --non-interactive --set "llmctl.download_profile=a
b"
expect_rc "markdown injection refused" 4 "$C" --project-root "$P4" --non-interactive --set 'llmctl.profiles=<!-- END constitution-decisions -->'
mkdir -p "$SB/elsewhere"; printf 'victim\n' >"$SB/elsewhere/target.md"; ln -s "$SB/elsewhere/target.md" "$P4/GEMINI.md"
expect_rc "symlinked doc refused" 3 "$C" --project-root "$P4" --non-interactive --set hosted.allowed=false
check "symlink target untouched" test "$(cat "$SB/elsewhere/target.md")" = victim
rm -f "$P4/GEMINI.md"
expect_rc "--doc traversal refused" 3 "$C" --project-root "$P4" --non-interactive --doc ../elsewhere/target.md --set hosted.allowed=false
mkdir -p "$P4/.claude"; printf '{"x":1}\n' >"$P4/.claude/settings.json"; S0="$(sha "$P4/.claude/settings.json")"
expect_rc "settings consent recorded" 0 "$C" --project-root "$P4" --non-interactive --set agents.settings_json_consent=true
check "settings.json untouched" test "$(sha "$P4/.claude/settings.json")" = "$S0"
printf '# X\n<!-- BEGIN constitution-decisions -->\none\n<!-- BEGIN constitution-decisions -->\n' >"$P4/QWEN.md"; Q0="$(sha "$P4/QWEN.md")"
expect_rc "broken markers refused" 4 "$C" --project-root "$P4" --non-interactive --set hosted.allowed=true
check "broken-marker doc untouched" test "$(sha "$P4/QWEN.md")" = "$Q0"
rm -f "$P4/QWEN.md"
printf '# X\n<!-- BEGIN constitution-decisions -->\na\n<!-- END constitution-decisions -->\n<!-- BEGIN constitution-decisions -->\nb\n<!-- END constitution-decisions -->\n' >"$P4/QWEN.md"; Q1="$(sha "$P4/QWEN.md")"
expect_rc "duplicate complete blocks refused" 4 "$C" --project-root "$P4" --non-interactive --set hosted.allowed=true
check "duplicate-block doc untouched" test "$(sha "$P4/QWEN.md")" = "$Q1"
printf '# X\n<!-- END constitution-decisions -->\n<!-- BEGIN constitution-decisions -->\n' >"$P4/QWEN.md"
expect_rc "END before BEGIN refused" 4 "$C" --project-root "$P4" --non-interactive --set hosted.allowed=true
rm -f "$P4/QWEN.md"
printf 'schema_version: 1\ninherits: submodules/constitution\ndecisions:\n  calibration.floor: 0.5\n' >"$P4/.constitution/decisions.yml"
expect_rc "tampered weakening file -> check 4" 4 "$C" --project-root "$P4" --check
expect_rc "tampered file blocks writes" 4 "$C" --project-root "$P4" --non-interactive --set hosted.allowed=false
printf 'schema_version: 1\ninherits: submodules/constitution\ndecisions:\n  calibration.floor: 0.97\n' >"$P4/.constitution/decisions.yml"
expect_rc "valid manual edit still flagged" 4 "$C" --project-root "$P4" --check
expect_rc "accept-external-edits adopts" 0 "$C" --project-root "$P4" --non-interactive --accept-external-edits --set hosted.allowed=false
expect_rc "check clean after adopt" 0 "$C" --project-root "$P4" --check

echo "== idempotency, dry-run, determinism =="
P5="$(new_project p5)"
"$C" --project-root "$P5" --non-interactive --set calibration.floor=0.92 --set agents.kimi.wiring=declined >/dev/null 2>&1
h1="$(sha "$P5/.constitution/decisions.yml")$(sha "$P5/CLAUDE.md")"; nb1="$(ls "$P5/.constitution-install-backup" | wc -l)"
"$C" --project-root "$P5" --non-interactive --set calibration.floor=0.92 --set agents.kimi.wiring=declined >"$SB/idem.out" 2>&1
h2="$(sha "$P5/.constitution/decisions.yml")$(sha "$P5/CLAUDE.md")"; nb2="$(ls "$P5/.constitution-install-backup" | wc -l)"
check "second run byte-identical" test "$h1" = "$h2"
check "second run no new backup" test "$nb1" = "$nb2"
check "second run says no-change" grep -q 'no-change' "$SB/idem.out"
expect_rc "dry-run" 0 "$C" --project-root "$P5" --non-interactive --dry-run --set calibration.floor=0.99
check "dry-run wrote nothing" test "$(sha "$P5/.constitution/decisions.yml")$(sha "$P5/CLAUDE.md")" = "$h1"
check "dry-run shows bootstrap command" grep -q 'bootstrap.sh' "$SB/last.out"
for i in 1 2 3; do Pd="$(new_project det$i)"; "$C" --project-root "$Pd" --non-interactive --set calibration.floor=0.93 --set endpoints.preference=local,hosted --set agents.opencode.wiring=consent >/dev/null 2>&1; done
check "determinism x3 decisions.yml" test "$(sha "$SB/det1/.constitution/decisions.yml")" = "$(sha "$SB/det2/.constitution/decisions.yml")" -a "$(sha "$SB/det2/.constitution/decisions.yml")" = "$(sha "$SB/det3/.constitution/decisions.yml")"
check "determinism x3 CLAUDE.md" test "$(sha "$SB/det1/CLAUDE.md")" = "$(sha "$SB/det3/CLAUDE.md")"

echo "== plan (read-only integration with the real jev-status.sh) =="
expect_rc "plan" 0 "$C" --project-root "$P5" --plan
check "plan names jev-status" grep -q 'jev-status' "$SB/last.out"
check "plan never ran bootstrap (no state dir created)" test ! -e "$JEV_HOME/.local/state/jev/bootstrap.stamp"
finish test_core
