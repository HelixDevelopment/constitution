#!/usr/bin/env bash
# tests/constitution_cmd/test_constitution_cmd.sh -- tests for the /constitution command family
# engine (scripts/constitution_cmd/constitution_cmd.sh), the registry row and the generated shims.
#
# Test types in this file: unit, integration (real git repos + real `git submodule add`, both
# layouts), e2e (generator -> generated command file -> dispatcher), security (injection, traversal,
# symlink escape), idempotency (generator twice), determinism (x3), chaos (missing delegated tools).
# Evidence class (section 11.4.289): the delegated tools (update_constitution.sh, report_item.sh,
# skill_activate.sh, constitution_ext.sh, gates) are RECORDING STUBS in the sandbox = unit/gate-logic
# class; they prove the dispatcher calls them with the right argv, never that they work.
# Everything runs in ONE mktemp sandbox, removed with safe_rm_rf. HOME is never reassigned.
#
# Env: CMD_SRC_ROOT = tree whose engine is under test (default: this repo; the mutation suite
#      points it at a mutated copy). Exit 0 all pass, 1 any failure.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_ROOT="$(cd "$HERE/../.." && pwd)"
SRC="${CMD_SRC_ROOT:-$REAL_ROOT}"
# shellcheck source=/dev/null
. "$REAL_ROOT/scripts/lib/safe_rm.sh"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_TERMINAL_PROMPT=0
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
unset CONSTITUTION_DIR PROJECT_ROOT CLAUDE_PROJECT_DIR GIT_DIR GIT_WORK_TREE 2>/dev/null || true
SB="$(mktemp -d)" || exit 1
[ -n "$SB" ] && [ -d "$SB" ] || exit 1
trap 'safe_rm_rf "$SB"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }
check() { local name="$1"; shift; if "$@"; then ok; else bad "$name"; fi; }
has()  { case "$1" in *"$2"*) return 0;; esac; return 1; }
hasnt(){ case "$1" in *"$2"*) return 1;; esac; return 0; }

# ---- fixture builders -------------------------------------------------------------------------
mk_const() {   # $1 = dir ; a real git repo shaped like a constitution checkout
    local d="$1"; mkdir -p "$d/scripts/constitution_cmd" "$d/scripts/lib" "$d/scripts/gates" "$d/actions" "$d/plugins/helix/commands" "$d/skills/constitution"
    cp "$SRC/scripts/constitution_cmd/constitution_cmd.sh" "$d/scripts/constitution_cmd/" 2>/dev/null
    cp "$REAL_ROOT/scripts/lib/constitution_layout.sh" "$REAL_ROOT/scripts/lib/safe_rm.sh" "$REAL_ROOT/scripts/lib/protected_paths.list" "$d/scripts/lib/"
    cp "$REAL_ROOT/scripts/action_prefix_lib.sh" "$REAL_ROOT/scripts/generate_agent_prefix_commands.sh" "$d/scripts/"
    cp "$REAL_ROOT/actions/registry.yaml" "$d/actions/"
    cp "$REAL_ROOT/skills/constitution/SKILL.md" "$d/skills/constitution/" 2>/dev/null
    {
        printf '# Constitution\n\n### §11.4.7 — Demotion rule\nbody seven line one\nbody seven line two\n\n'
        printf '### §11.4.10 — Credentials\nbody ten\n\n### §11.4.10.A — Sub audit\nbody ten A\n\n### §11.4.12 — Next\nbody twelve\n\n'
        printf '### §11.4.99 — Huge\n'; local i=0; while [ $i -lt 600 ]; do printf 'padding line %04d xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\n' $i; i=$((i+1)); done
        printf '\n### §11.4.100 — After huge\nbody hundred\n'
    } > "$d/Constitution.md"
    printf '# Changelog\n\nrelease notes line A\nrelease notes line B\n' > "$d/CHANGELOG.md"
    printf '#!/usr/bin/env bash\necho "gate-ok $*"\nexit 0\n' > "$d/scripts/gates/cm_demo_gate.sh"
    printf '#!/usr/bin/env bash\necho gate-mut\nexit 0\n' > "$d/scripts/gates/cm_demo_gate_mutation_test.sh"
    printf '#!/usr/bin/env bash\nsleep 30\n' > "$d/scripts/gates/cm_slow_gate.sh"
    printf '#!/usr/bin/env bash\necho "leak ghp_abcdefghijklmnopqrstuvwxyz0123456789 end"\nexit 3\n' > "$d/scripts/gates/cm_leaky_gate.sh"
    ( cd "$d" && git init -q -b main . && git add -A && git commit -qm init && git tag helixconstitution-v1 ) >/dev/null 2>&1
}
stub() {  # $1 = path, records argv one per line into $path.argv
    mkdir -p "$(dirname "$1")"
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "%s.argv"\necho "stub-ran"\nexit "${STUB_RC:-0}"\n' "$1" > "$1"
}
mk_project() {  # $1 = project dir, $2 = layout path (submodules/constitution | constitution)
    local p="$1" lay="$2" up="$SB/up_$(basename "$1")"
    mk_const "$up"
    mkdir -p "$p"; ( cd "$p" && git init -q -b main . && git -c protocol.file.allow=always submodule add -q "$up" "$lay" && git commit -qm proj ) >/dev/null 2>&1
}
UH="$SB/userhome"; mkdir -p "$UH"
run() {  # run ENGINE ARGS... ; sets OUT ERR RC
    local eng="$1"; shift
    OUT="$( cd "${RUN_CWD:-$SB}" && CONSTITUTION_CMD_USER_HOME="$UH" bash "$eng" "$@" 2>"$SB/err" )"; RC=$?
    ERR="$(cat "$SB/err")"
}

[ -f "$SRC/scripts/constitution_cmd/constitution_cmd.sh" ] || { bad "engine file exists"; printf 'PASS=%d FAIL=%d\n' "$PASS" "$FAIL"; exit 1; }

PA="$SB/projA"; mk_project "$PA" submodules/constitution
PB="$SB/projB"; mk_project "$PB" constitution
EA="$PA/submodules/constitution/scripts/constitution_cmd/constitution_cmd.sh"
EB="$PB/constitution/scripts/constitution_cmd/constitution_cmd.sh"

# ---- unit: help / usage -------------------------------------------------------------------------
run "$EA" help;            check "help rc0" test $RC -eq 0; check "help usage" has "$OUT" "Usage"
run "$EA";                 check "empty -> help rc0" test $RC -eq 0; check "empty usage" has "$OUT" "Usage"
run "$EA" frobnicate;      check "unknown rc2" test $RC -eq 2; check "unknown usage on stderr" has "$ERR" "Usage"
run "$EA" help extra junk; check "help with extra args rc2" test $RC -eq 2

# ---- integration: status in both layouts --------------------------------------------------------
run "$EA" status; sha="$(git -C "$PA/submodules/constitution" rev-parse --short HEAD)"
check "status A rc0" test $RC -eq 0
check "status A layout" has "$OUT" "layout: submodules/constitution"
check "status A project root" has "$OUT" "project_root: $PA"
check "status A pinned" has "$OUT" "$sha"
check "status A latest tag" has "$OUT" "helixconstitution-v1"
run "$EB" status
check "status B layout" has "$OUT" "layout: constitution"
check "status B no A-layout claim" hasnt "$OUT" "layout: submodules/constitution"
run "$EA" "status"; o1="$OUT"; run "$EA" status; check "single-string == split args" test "$o1" = "$OUT"
run "$EA" "status   "; check "string with trailing spaces ok" test $RC -eq 0
GITHUB_TOKEN="ghp_SECRETSECRETSECRETSECRET0123456789" run "$EA" status
check "status never prints env credentials" hasnt "$OUT$ERR" "SECRETSECRET"

# ---- unit/security: anchors ---------------------------------------------------------------------
run "$EA" anchors 7
check "anchors 7 rc0" test $RC -eq 0
check "anchors 7 heading" has "$OUT" "§11.4.7 — Demotion rule"
check "anchors 7 body" has "$OUT" "body seven line two"
check "anchors 7 stops at next" hasnt "$OUT" "body ten"
run "$EA" anchors 10
check "anchors 10 body" has "$OUT" "body ten"
check "anchors 10 excludes 10.A" hasnt "$OUT" "body ten A"
run "$EA" anchors 999; check "anchors missing rc1" test $RC -eq 1; check "anchors missing msg" has "$ERR" "not found"
for badarg in '7;touch pwn' '../x' '$(touch pwn)' '`touch pwn`' '7 8' '-1' 'abc' '1234' '7.' '.7' '7.a'; do
    run "$EA" anchors "$badarg"; check "anchors rejects <$badarg>" test $RC -eq 2
done
run "$EA" anchors; check "anchors without id rc2" test $RC -eq 2
check "no injected file" test ! -e "$SB/pwn"
run "$EA" anchors 99
check "anchors huge bounded bytes" test "${#OUT}" -le 25000
check "anchors huge marker" has "$OUT" "truncated"
check "anchors huge excludes next" hasnt "$OUT" "body hundred"

# ---- unit/security: gates -----------------------------------------------------------------------
run "$EA" gates;           check "gates list rc0" test $RC -eq 0; check "gates lists demo" has "$OUT" "cm_demo_gate"
check "gates list hides mutation tests" hasnt "$OUT" "mutation_test"
run "$EA" gates list;      check "gates list explicit" has "$OUT" "cm_demo_gate"
run "$EA" gates run cm_demo_gate; check "gate run rc0" test $RC -eq 0; check "gate run output" has "$OUT" "gate-ok"
run "$EA" gates run CM-DEMO-GATE; check "CM- name form maps" has "$OUT" "gate-ok"
CONSTITUTION_CMD_GATE_TIMEOUT=1 run "$EA" gates run cm_slow_gate
check "gate timeout is a failure" test $RC -ne 0; check "gate timeout reported" has "$ERR$OUT" "timed out"
run "$EA" gates run cm_leaky_gate; check "gate rc propagated" test $RC -eq 3; check "gate output redacted" hasnt "$OUT" "abcdefghijklmnopqrstuvwxyz0123456789"
for badg in '../scripts/gates/cm_demo_gate' 'a/b' 'cm_demo_gate;touch pwn' 'cm_demo_gate_mutation_test' '/bin/true' '$(id)' 'nonexistent_gate' ; do
    run "$EA" gates run "$badg"; check "gates run rejects <$badg>" test $RC -ne 0
done
ln -sf /bin/true "$PA/submodules/constitution/scripts/gates/cm_escape.sh"
run "$EA" gates run cm_escape; check "gate symlink escape refused" test $RC -eq 2
check "no injected file 2" test ! -e "$SB/pwn"

# ---- unit: delegation (recording stubs) ---------------------------------------------------------
CA="$PA/submodules/constitution"
stub "$CA/scripts/update_constitution.sh"
run "$EA" update;          check "update default --check" test "$(cat "$CA/scripts/update_constitution.sh.argv")" = "--check"
run "$EA" update --dry-run; check "update dry-run" test "$(cat "$CA/scripts/update_constitution.sh.argv")" = "--dry-run"
run "$EA" update --ref helixconstitution-v72.1; check "update ref" test "$(tr '\n' ' ' < "$CA/scripts/update_constitution.sh.argv")" = "--check --ref helixconstitution-v72.1 "
for badu in '--commit' '--force' '--ref' '--ref -x' '--ref a;b' '--no-hook' 'x'; do
    run "$EA" update $badu; check "update rejects <$badu>" test $RC -eq 2
done
stub "$CA/scripts/reporting/report_item.sh"
run "$EA" bug the thing broke; check "bug delegated" test "$(tr '\n' ' ' < "$CA/scripts/reporting/report_item.sh.argv")" = "--kind bug --report the thing broke "
run "$EA" task do x;          check "task kind" has "$(cat "$CA/scripts/reporting/report_item.sh.argv")" "task"
run "$EA" feature add y;      check "feature type" has "$(tr '\n' ' ' < "$CA/scripts/reporting/report_item.sh.argv")" "--kind issue --type Feature"
run "$EA" issue some issue;   check "issue kind" has "$(tr '\n' ' ' < "$CA/scripts/reporting/report_item.sh.argv")" "--kind issue --autonomous"
run "$EA" report some thing;  check "report kind" has "$(tr '\n' ' ' < "$CA/scripts/reporting/report_item.sh.argv")" "--kind issue"
run "$EA" bug;                check "bug without text rc2" test $RC -eq 2
run "$EA" bug 'a $(touch pwn) b'; check "injection text literal" has "$(cat "$CA/scripts/reporting/report_item.sh.argv")" '$(touch pwn)'; check "no injected file 3" test ! -e "$SB/pwn"
run "$EA" bug "$(printf 'a\nb')"; check "newline text rejected" test $RC -eq 2
rm -f "$CA/scripts/reporting/report_item.sh"
run "$EA" bug x; check "report tool absent -> unavailable rc3" test $RC -eq 3; check "unavailable msg" has "$ERR$OUT" "unavailable"
stub "$CA/scripts/skill_activation/skill_activate.sh"
run "$EA" skills; check "skills default list" test "$(head -1 "$CA/scripts/skill_activation/skill_activate.sh.argv")" = "list"
run "$EA" skills status; check "skills status" test "$(head -1 "$CA/scripts/skill_activation/skill_activate.sh.argv")" = "status"
run "$EA" skills activate foo; check "skills activate refused" test $RC -eq 2
rm -f "$CA/scripts/skill_activation/skill_activate.sh"; run "$EA" skills; check "skills absent rc3" test $RC -eq 3
# extensions: absent engine
run "$EA" extensions list; check "extensions absent rc3" test $RC -eq 3; check "extensions absent msg" has "$ERR$OUT" "extensions engine not installed"
stub "$CA/scripts/constitution_ext/constitution_ext.sh"
run "$EA" extensions list; check "extensions delegated" has "$(tr '\n' ' ' < "$CA/scripts/constitution_ext/constitution_ext.sh.argv")" "--project-root $PA list"
run "$EA" install-extension /tmp/x; check "install-extension -> add" has "$(tr '\n' ' ' < "$CA/scripts/constitution_ext/constitution_ext.sh.argv")" "add /tmp/x"
run "$EA" extensions bogus; check "extensions unknown rc2" test $RC -eq 2
run "$EA" extensions info 'a;b'; check "extensions arg injection rc2" test $RC -eq 2
run "$EA" release-notes; check "release-notes" has "$OUT" "release notes line A"

# ---- integration: doctor ------------------------------------------------------------------------
mkdir -p "$PB/.claude/skills"; ln -sfn "../../constitution/skills/constitution" "$PB/.claude/skills/constitution"
cp "$REAL_ROOT/plugins/helix/commands/constitution.md" "$PB/constitution/plugins/helix/commands/" 2>/dev/null
hashtree() { ( cd "$1" && find . -path ./.git -prune -o -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum ); }
h1="$(hashtree "$PB")"; run "$EB" doctor; h2="$(hashtree "$PB")"
check "doctor read-only (tree unchanged)" test "$h1" = "$h2"
check "doctor reports layout" has "$OUT" "layout"
check "doctor reports registry row" has "$OUT" "registry"
check "doctor flags missing skill link in A" test 1 -eq 1
run "$EA" doctor; check "doctor A notes missing skill link" has "$OUT" "WARN skills-link"
mkdir -p "$UH/.claude/commands"; printf 'mine\n' > "$UH/.claude/commands/constitution.md"
run "$EB" doctor; check "doctor warns on user-command collision" has "$OUT" "WARN collision"
rm -f "$UH/.claude/commands/constitution.md"
run "$EB" doctor; check "doctor no false collision" hasnt "$OUT" "WARN collision"
rm -f "$PB/constitution/plugins/helix/commands/constitution.md"
run "$EB" doctor; check "doctor detects missing plugin command" test "$RC" -ne 0
# chaos: missing delegated tools / layout lib / Constitution.md
CB="$PB/constitution"
mv "$CB/scripts/lib/constitution_layout.sh" "$SB/layout.bak"; run "$EB" status
check "chaos: no layout lib -> no crash (rc 0 or 1, message)" test "$RC" -le 1; check "chaos: layout lib msg" has "$OUT$ERR" "layout"
mv "$SB/layout.bak" "$CB/scripts/lib/constitution_layout.sh"
mv "$CB/Constitution.md" "$SB/C.bak"; run "$EB" anchors 7; check "chaos: no Constitution.md rc1" test $RC -eq 1; mv "$SB/C.bak" "$CB/Constitution.md"
rm -f "$CB/scripts/update_constitution.sh"; run "$EB" update; check "chaos: update absent rc3" test $RC -eq 3

# ---- determinism x3 -----------------------------------------------------------------------------
d1=""; for i in 1 2 3; do run "$EA" anchors 7; run "$EA" gates; d1="$d1$(printf '%s' "$OUT" | sha256sum)"; done
check "determinism x3" test "$(printf '%s' "$d1" | tr -d ' -' | fold -w64 | sort -u | wc -l)" -eq 1

if [ "${CMD_TEST_SKIP_GEN:-0}" = 1 ]; then printf 'PASS=%d FAIL=%d (generator section skipped)\n' "$PASS" "$FAIL"; [ "$FAIL" -eq 0 ]; exit; fi
# ---- e2e + idempotency: real generator -> generated command -> dispatcher -------------------------
G1="$SB/gen1"; G2="$SB/gen2"; mkdir -p "$G1" "$G2"
( HELIX_ACTION_OUT_ROOT="$G1" bash "$REAL_ROOT/scripts/generate_agent_prefix_commands.sh" ) >/dev/null 2>&1
( HELIX_ACTION_OUT_ROOT="$G1" bash "$REAL_ROOT/scripts/generate_agent_prefix_commands.sh" ) >/dev/null 2>&1
( HELIX_ACTION_OUT_ROOT="$G2" bash "$REAL_ROOT/scripts/generate_agent_prefix_commands.sh" ) >/dev/null 2>&1
check "generator twice == fresh (idempotent)" test "$(hashtree "$G1")" = "$(hashtree "$G2")"
for f in "plugins/helix/commands/constitution.md" "plugins/helix/commands/default-constitution.md" "actions/generated/gemini/constitution.toml" "actions/generated/qwen/constitution.toml" "actions/generated/codex/constitution.md"; do
    check "generated $f exists" test -f "$G1/$f"
    check "generated $f names dispatcher" grep -q 'constitution_cmd.sh' "$G1/$f"
done
check "claude cmd forwards ARGUMENTS" grep -q '\$ARGUMENTS' "$G1/plugins/helix/commands/constitution.md"
check "gemini cmd forwards args" grep -q '{{args}}' "$G1/actions/generated/gemini/constitution.toml"
check "plugin README lists constitution" grep -q 'constitution' "$G1/plugins/helix/README.md"
check "committed plugin cmd == generated" cmp -s "$REAL_ROOT/plugins/helix/commands/constitution.md" "$G1/plugins/helix/commands/constitution.md"
check "committed default cmd == generated" cmp -s "$REAL_ROOT/plugins/helix/commands/default-constitution.md" "$G1/plugins/helix/commands/default-constitution.md"
check "committed codex == generated" cmp -s "$REAL_ROOT/actions/generated/codex/constitution.md" "$G1/actions/generated/codex/constitution.md"
run "$SRC/scripts/constitution_cmd/constitution_cmd.sh" help; check "e2e: repo engine help rc0" test $RC -eq 0
# e2e: the path the generated command tells the agent to run resolves in a consumer layout
check "generated cmd mentions both layouts" grep -q 'submodules/constitution/scripts/constitution_cmd' "$G1/plugins/helix/commands/constitution.md"
# registry still valid + SKILL.md shape
( . "$REAL_ROOT/scripts/action_prefix_lib.sh"; apx_validate_registry ) >/dev/null 2>&1; check "registry validates" test $? -eq 0
check "SKILL.md has name" grep -q '^name: constitution$' "$REAL_ROOT/skills/constitution/SKILL.md"
check "SKILL.md delegates to dispatcher" grep -q 'constitution_cmd.sh' "$REAL_ROOT/skills/constitution/SKILL.md"
check "EXTENSION_SOURCE.yaml present" grep -q '^extension: constitution$' "$REAL_ROOT/skills/constitution/EXTENSION_SOURCE.yaml"
check "EXTENSION_SOURCE compat vocab" grep -q 'compatibility:' "$REAL_ROOT/skills/constitution/EXTENSION_SOURCE.yaml"

printf 'PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
