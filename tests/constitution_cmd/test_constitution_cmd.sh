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
# residue guard (item B): top-level entries of the repo root and of the invoking cwd, before vs after
residue_snap() { { ls -A "$REAL_ROOT"; printf -- '--cwd--\n'; ls -A . ; } 2>/dev/null; }
RESIDUE_BEFORE="$(residue_snap)"
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }
check() { local name="$1"; shift; if "$@"; then ok; else bad "$name"; fi; }
has()  { case "$1" in *"$2"*) return 0;; esac; return 1; }
hasnt(){ case "$1" in *"$2"*) return 1;; esac; return 0; }

# ---- fixture builders -------------------------------------------------------------------------
mk_const() {   # $1 = dir ; a real git repo shaped like a constitution checkout
    local d="$1"; mkdir -p "$d/scripts/constitution_cmd" "$d/scripts/lib" "$d/scripts/gates" "$d/actions" "$d/plugins/helix/commands" "$d/skills/constitution"
    cp "$SRC/scripts/constitution_cmd/constitution_cmd.sh" "$SRC/scripts/constitution_cmd/args_file_read.py" "$d/scripts/constitution_cmd/" 2>/dev/null
    cp "$REAL_ROOT/scripts/lib/constitution_layout.sh" "$REAL_ROOT/scripts/lib/safe_rm.sh" "$REAL_ROOT/scripts/lib/protected_paths.list" "$d/scripts/lib/"
    cp "$REAL_ROOT/scripts/action_prefix_lib.sh" "$REAL_ROOT/scripts/generate_agent_prefix_commands.sh" "$d/scripts/"
    cp "$REAL_ROOT/actions/registry.yaml" "$d/actions/"
    cp "$REAL_ROOT/skills/constitution/SKILL.md" "$d/skills/constitution/" 2>/dev/null
    {
        printf '# Constitution\n\n### §11.4.7 — Demotion rule\nbody seven line one\nbody seven line two\n\n'
        printf '### §11.4.10 — Credentials\nbody ten\n\n### §11.4.10.A — Sub audit\nbody ten A\n\n### §11.4.12 — Next\nbody twelve\n\n'
        printf '### §11.4.99 — Huge\n'; local i=0; while [ $i -lt 600 ]; do printf 'padding line %04d xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\n' $i; i=$((i+1)); done
        printf '\n### §11.4.100 — After huge\nbody hundred\n'
    printf '\n**§11.4.150 — Bold anchor (test).** bold body text one\n\nafter bold paragraph text\n'
    } > "$d/Constitution.md"
    printf '# Changelog\n\nrelease notes line A\nrelease notes line B\n' > "$d/CHANGELOG.md"
    printf '#!/usr/bin/env bash\necho "gate-ok $*"\nexit 0\n' > "$d/scripts/gates/cm_demo_gate.sh"
    printf '#!/usr/bin/env bash\necho gate-mut\nexit 0\n' > "$d/scripts/gates/cm_demo_gate_mutation_test.sh"
    printf '#!/usr/bin/env bash\nsleep 30\n' > "$d/scripts/gates/cm_slow_gate.sh"
    printf '#!/usr/bin/env bash\nhead -c 200000 /dev/zero | tr "\\0" a\necho\nexit "${BIG_RC:-0}"\n' > "$d/scripts/gates/cm_big_gate.sh"
    printf '#!/usr/bin/env bash\necho "Authorization: Bearer abcdefghijklmnopqrstuvwx0123"\necho "token zzzzzzzzzzzzzzzz9999"\necho "api_key: \\"sk_live_ABCDEFGH12345678\\""\necho "password=hunter2hunter2"\necho "Password: pw-value-12345"\nexit 0\n' > "$d/scripts/gates/cm_secrets_gate.sh"
    printf '#!/usr/bin/env bash\necho "id AKIAABCDEFGHIJKLMNOP end"\necho "key AIzaSyA1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q"\necho "url postgres://dbuser:fakepassw0rdXYZ@db.example/x"\necho "-----BEGIN RSA PRIVATE KEY-----"\necho "FAKEPEMBODYLINEONE0123456789abcdef"\necho "FAKEPEMBODYLINETWO0123456789abcdef"\necho "-----END RSA PRIVATE KEY-----"\necho "after-pem-ok"\nexit 0\n' > "$d/scripts/gates/cm_secrets2_gate.sh"
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
for badg in '../scripts/gates/cm_demo_gate' 'a/b' 'cm_demo_gate;touch pwn' 'cm_demo_gate_mutation_test' '/bin/true' '$(id)' 'cm.demo'; do
    run "$EA" gates run "$badg"; check "gates run malformed <$badg> is usage error rc2" test $RC -eq 2
done
run "$EA" gates run nonexistent_gate; check "gates run unknown name rc1" test $RC -eq 1
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
long="$(head -c 4001 /dev/zero | tr '\0' 'a')"; run "$EA" bug "$long"; check "over-long report text rc2" test $RC -eq 2
run "$EA" bug "$(head -c 3000 /dev/zero | tr '\0' 'a')"; check "3000-char report text accepted" test $RC -eq 0
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

# ---- S1: user text never evaluated by the shell (command template from SKILL.md) ---------------
# The template: the agent writes the text to /tmp/constitution_args_<id>.txt with its file-write tool
# (modelled here by printf into the file), then runs the one --args-file command. No heredoc, so no
# delimiter a pasted payload can contain.
tmpl_line="$(grep -m1 -- '--args-file' "$REAL_ROOT/skills/constitution/SKILL.md")"
check "S1 template has --args-file command" test -n "$tmpl_line"
check "S1 template has no heredoc" bash -c '! grep -q "<<" "$1"' _ "$REAL_ROOT/skills/constitution/SKILL.md"
check "S1 template has no fixed public delimiter" bash -c '! grep -q "CONSTITUTION_ARGS_" "$1"' _ "$REAL_ROOT/skills/constitution/SKILL.md"
AFN=0
agent_run() {   # agent_run TEXT [ENGINE] : write TEXT to a fresh args file, run the template command; sets OUT RC
    local text="$1" eng="${2:-$EA}" id f cmd; AFN=$((AFN+1)); id="agentrun${AFN}p$$"; f="${TMPDIR:-/tmp}/constitution_args_${id}.txt"
    printf '%s\n' "$text" > "$f"
    cmd="${tmpl_line//<id>/$id}"; cmd="${cmd//submodules\/constitution\/scripts\/constitution_cmd\/constitution_cmd.sh/$eng}"; cmd="${cmd//\/tmp\/constitution_args_/${TMPDIR:-/tmp}\/constitution_args_}"
    OUT="$( cd "$PA" && CONSTITUTION_CMD_USER_HOME="$UH" bash -c "$cmd" 2>&1 )"; RC=$?
    AFFILE="$f"
}
rm -f "$PA/SENTINEL" "$PA/SENTINEL2" "$PA/SENTINEL3" "$PA/BREAKOUT"
agent_run 'anchors 7 $(touch SENTINEL) `touch SENTINEL2` ${HOME}'
check "S1 hostile \$(..) not executed" test ! -e "$PA/SENTINEL"
check "S1 hostile backticks not executed" test ! -e "$PA/SENTINEL2"
agent_run 'anchors 7'; check "S1 args-file path works rc0" test $RC -eq 0; check "S1 args-file path output" has "$OUT" 'Demotion rule'
check "S1 args file consumed (deleted)" test ! -e "$AFFILE"
agent_run ''; check "S1 empty args file -> help" has "$OUT" Usage
# Item A: a payload containing the OLD public delimiter (and any heredoc-looking lines) is inert.
agent_run "$(printf 'anchors 7\nCONSTITUTION_ARGS_7f3a9c\ntouch BREAKOUT')"
check "A payload with old delimiter: no breakout" test ! -e "$PA/BREAKOUT"
check "A multi-line payload rejected rc2 (control char)" test $RC -eq 2
# control needle (RED baseline): the OLD fixed-delimiter heredoc form DOES break out on that payload
old_cmd="bash $EA --stdin <<'CONSTITUTION_ARGS_7f3a9c'
anchors 7
CONSTITUTION_ARGS_7f3a9c
touch BREAKOUT
CONSTITUTION_ARGS_7f3a9c"
( cd "$PA" && CONSTITUTION_CMD_USER_HOME="$UH" bash -c "$old_cmd" ) >/dev/null 2>&1
check "A control needle: old heredoc form breaks out" test -e "$PA/BREAKOUT"
rm -f "$PA/BREAKOUT"
# --args-file validation (security). TD = the allowed temp dir ($TMPDIR when set, else /tmp).
TD="${TMPDIR:-/tmp}"; TD="${TD%/}"; HLP="$SRC/scripts/constitution_cmd/args_file_read.py"
mkaf() { printf '%s\n' "$2" > "$TD/constitution_args_$1.txt"; }
run "$EA" --args-file /etc/passwd; check "A path outside pattern rejected rc2" test $RC -eq 2
run "$EA" --args-file "$TD/constitution_args_nofile$$.txt"; check "A missing file rejected rc2" test $RC -eq 2
run "$EA" --args-file; check "A --args-file without path rejected" test $RC -eq 2
mkaf "extra000$$" "help"; run "$EA" --args-file "$TD/constitution_args_extra000$$.txt" status; check "A --args-file VALID path + extra arg rejected" test $RC -eq 2; check "A extra-arg case: valid file not consumed" test -e "$TD/constitution_args_extra000$$.txt"; rm -f "$TD/constitution_args_extra000$$.txt"
run "$EA" --stdin; check "A --stdin no longer exists (treated as a plain subcommand, rc2)" test $RC -eq 2
# A1/A2: traversal. The directories EXIST and a decoy (shaped like a legitimate victim) sits at the
# traversal target; if any check fails the decoy is deleted and the test fails.
V="$SB/victim"; mkdir -p "$V" "$TD/constitution_args_dirx$$"
printf 'help\n' > "$V/notes.txt"; printf 'help\n' > "$V/constitution_args_decoy01.txt"
VR="$(realpath "$V")"
run "$EA" --args-file "$TD/constitution_args_dirx$$/../../${VR#/}/notes.txt"; check "A1 dotdot via existing dir rejected rc2" test $RC -eq 2; check "A1 decoy survives (dotdot)" test -e "$V/notes.txt"
run "$EA" --args-file "$TD/constitution_args_dirx$$/../$(realpath --relative-to="$TD" "$V")/notes.txt"; check "A1 relative dotdot rejected rc2" test $RC -eq 2; check "A1 decoy survives (relative dotdot)" test -e "$V/notes.txt"
ln -sfn "$V" "$TD/constitution_args_symdir$$"
run "$EA" --args-file "$TD/constitution_args_symdir$$/notes.txt"; check "A1 symlinked middle dir rejected rc2" test $RC -eq 2; check "A1 decoy survives (symlinked dir)" test -e "$V/notes.txt"
run "$EA" --args-file "$TD/constitution_args_symdir$$/constitution_args_decoy01.txt"; check "A1 symlinked dir + valid leaf name rejected rc2" test $RC -eq 2; check "A1 decoy survives (symlinked dir, valid leaf)" test -e "$V/constitution_args_decoy01.txt"
rm -f "$TD/constitution_args_symdir$$"; rmdir "$TD/constitution_args_dirx$$"
run "$EA" --args-file "$V/constitution_args_decoy01.txt"; check "A1 valid leaf in a foreign dir rejected rc2" test $RC -eq 2; check "A1 decoy survives (foreign dir)" test -e "$V/constitution_args_decoy01.txt"
run "$EA" --args-file "$TD//constitution_args_decoy01.txt"; check "A1 doubled slash rejected rc2" test $RC -eq 2
run "$EA" --args-file "$TD/./constitution_args_decoy01.txt"; check "A1 dot segment rejected rc2" test $RC -eq 2
run "$EA" --args-file "$TD/sub/constitution_args_decoy01.txt"; check "A1 extra component rejected rc2" test $RC -eq 2
# the id contains a slash and the directory exists: the decoy must survive
mkdir -p "$TD/constitution_args_a"; printf 'help\n' > "$TD/constitution_args_a/x.txt"
run "$EA" --args-file "$TD/constitution_args_a/x.txt"; check "A2 id with slash rejected rc2 (dir exists)" test $RC -eq 2; check "A2 decoy survives (id with slash)" test -e "$TD/constitution_args_a/x.txt"
rm -f "$TD/constitution_args_a/x.txt"; rmdir "$TD/constitution_args_a"
# symlink leaf to an own file
printf 'help\n' > "$SB/tgt.txt"; ln -sf "$SB/tgt.txt" "$TD/constitution_args_lnk$$.txt"; run "$EA" --args-file "$TD/constitution_args_lnk$$.txt"
check "A symlink (to own file) rejected rc2" test $RC -eq 2; check "A symlink target survives" test -e "$SB/tgt.txt"; rm -f "$TD/constitution_args_lnk$$.txt"
printf 'help\n' > "$SB/constitution_args_okokokok.txt"; run "$EA" --args-file "$SB/constitution_args_okokokok.txt"
check "A own valid file outside tmpdir rejected rc2" test $RC -eq 2; check "A outside-tmpdir file not consumed" test -e "$SB/constitution_args_okokokok.txt"
# id grammar: lowercase [a-z0-9], length 8..64
for badid in "a;b$$" "UPPER$$xyz" "short" "abcdefg" "$(head -c 65 /dev/zero | tr '\0' a)" "has-dash0123" "has_under012"; do
    printf 'help\n' > "$TD/constitution_args_${badid}.txt" 2>/dev/null; run "$EA" --args-file "$TD/constitution_args_${badid}.txt"
    check "A bad id <${badid:0:12}> rejected rc2" test $RC -eq 2; check "A bad id <${badid:0:12}> file not consumed" test -e "$TD/constitution_args_${badid}.txt"; rm -f "$TD/constitution_args_${badid}.txt"
done
okid64="$(head -c 64 /dev/zero | tr '\0' b)"; mkaf "$okid64" "help"; run "$EA" --args-file "$TD/constitution_args_${okid64}.txt"; check "A 64-char id accepted rc0" test $RC -eq 0
mkaf "abcdefgh" "help"; run "$EA" --args-file "$TD/constitution_args_abcdefgh.txt"; check "A 8-char id accepted rc0" test $RC -eq 0
# non-regular files: a FIFO and a directory with a valid name must be rejected (and not hang)
mkfifo "$TD/constitution_args_fifo0000$$.txt"; run "$EA" --args-file "$TD/constitution_args_fifo0000$$.txt"
check "A FIFO rejected rc2 (no hang)" test $RC -eq 2; rm -f "$TD/constitution_args_fifo0000$$.txt"
mkdir "$TD/constitution_args_dir00000$$.txt"; run "$EA" --args-file "$TD/constitution_args_dir00000$$.txt"; check "A directory rejected rc2" test $RC -eq 2; rmdir "$TD/constitution_args_dir00000$$.txt"
# hard link (two names, one inode) rejected
mkaf "hardl0000$$" "help"; ln "$TD/constitution_args_hardl0000$$.txt" "$SB/hardlink.keep"; run "$EA" --args-file "$TD/constitution_args_hardl0000$$.txt"
check "A multi-link file rejected rc2" test $RC -eq 2; rm -f "$TD/constitution_args_hardl0000$$.txt" "$SB/hardlink.keep"
# size: the file cap (8001 bytes) is checked before reading; message distinguishes it from the 8000-char cap
mkaf "big00000$$" "help$(head -c 8100 /dev/zero | tr '\0' ' ')"; run "$EA" --args-file "$TD/constitution_args_big00000$$.txt"
check "A over-long args file rejected rc2" test $RC -eq 2; check "A over-long args file: size-cap message" has "$ERR$OUT" "too large"; rm -f "$TD/constitution_args_big00000$$.txt"
mkaf "edge0000$$" "help$(head -c 7990 /dev/zero | tr '\0' ' ')"; run "$EA" --args-file "$TD/constitution_args_edge0000$$.txt"; check "A ~8000-byte args file accepted rc0" test $RC -eq 0
printf '%s' "help$(head -c 7996 /dev/zero | tr '\0' ' ')x" > "$TD/constitution_args_len80010$$.txt"; run "$EA" --args-file "$TD/constitution_args_len80010$$.txt"
check "A 8001-char line (within file cap) rejected by the 8000-char cap rc2" test $RC -eq 2; check "A 8001-char: char-cap message" has "$ERR$OUT" "longer than 8000"; rm -f "$TD/constitution_args_len80010$$.txt"
printf 'status\001x\n' > "$TD/constitution_args_ctl00000$$.txt"; run "$EA" --args-file "$TD/constitution_args_ctl00000$$.txt"
check "A control char in args file rejected rc2" test $RC -eq 2; rm -f "$TD/constitution_args_ctl00000$$.txt"
printf 'help\000\n' > "$TD/constitution_args_nul00000$$.txt"; run "$EA" --args-file "$TD/constitution_args_nul00000$$.txt"
check "A NUL byte in args file rejected rc2" test $RC -eq 2; rm -f "$TD/constitution_args_nul00000$$.txt"
# filename anchored at the END: a valid-looking prefix followed by extra characters must be rejected
for sfx in ".bak" "x" ".txt"; do
    printf 'help\n' > "$TD/constitution_args_trail000$$.txt$sfx"; run "$EA" --args-file "$TD/constitution_args_trail000$$.txt$sfx"
    check "A trailing '$sfx' after .txt rejected rc2" test $RC -eq 2; check "A trailing '$sfx' file survives" test -e "$TD/constitution_args_trail000$$.txt$sfx"
    rm -f "$TD/constitution_args_trail000$$.txt$sfx"
done
# TMPDIR hygiene: the helper claims it accepts only a canonical absolute $TMPDIR (no ".."/"."/empty
# segment, not relative, realpath(TMPDIR)==TMPDIR). Driven directly with a controlled TMPDIR.
TR="$(realpath "$SB")/tdr"; mkdir -p "$TR/real" "$TR/other"; ln -s real "$TR/link"
hlp(){ ( cd "$SB" && env "$@" python3 -I "$HLP" "$HLP_PATH" ) >"$SB/hout" 2>"$SB/herr"; HRC=$?; }
printf 'help\n' > "$TR/real/constitution_args_tmpdir01.txt"
HLP_PATH="$TR/real/../real/constitution_args_tmpdir01.txt"; hlp TMPDIR="$TR/real/../real"
check "A TMPDIR with '..' rejected rc2" test $HRC -eq 2; check "A TMPDIR '..' file survives" test -e "$TR/real/constitution_args_tmpdir01.txt"
HLP_PATH="$TR/link/constitution_args_tmpdir01.txt"; hlp TMPDIR="$TR/link"
check "A symlinked TMPDIR rejected rc2" test $HRC -eq 2; check "A symlinked TMPDIR file survives" test -e "$TR/real/constitution_args_tmpdir01.txt"
HLP_PATH="relative/constitution_args_tmpdir01.txt"; hlp TMPDIR="relative"
check "A relative TMPDIR rejected rc2" test $HRC -eq 2
HLP_PATH="$TR/real//constitution_args_tmpdir01.txt"; hlp TMPDIR="$TR/real//"
check "A TMPDIR with empty segment rejected rc2" test $HRC -eq 2
HLP_PATH="$TR/real/constitution_args_tmpdir01.txt"; hlp TMPDIR="$TR/real"
check "A canonical TMPDIR accepted rc0" test $HRC -eq 0; check "A canonical TMPDIR file consumed" test ! -e "$TR/real/constitution_args_tmpdir01.txt"
# identity check (dev+inode): driven IN-PROCESS (import + after_open callback); the shipped entry point has
# no environment-controlled behaviour at all.
check "A production helper has no env-controlled seam" bash -c "! grep -q 'CONSTITUTION_CMD_TEST' '$HLP'"
printf 'help\n' > "$TR/real/constitution_args_swapa0001.txt"; printf 'evil\n' > "$TR/real/constitution_args_swapb0001.txt"
SWOUT="$(python3 -I - "$HLP" "$TR/real" 2>&1 <<'PYEOF'
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("afr", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
d = sys.argv[2]
def swap(dfd, name):
    os.rename("constitution_args_swapb0001.txt", name, src_dir_fd=dfd, dst_dir_fd=dfd)
try:
    m.read_and_consume(d + "/constitution_args_swapa0001.txt", [d], after_open=swap)
    print("ACCEPTED")
except SystemExit as e:
    print("REJECTED", e.code)
PYEOF
)"
check "A entry swapped after open rejected rc2" bash -c "[ \"\$1\" = 'REJECTED 2' ]" _ "$(printf '%s\n' "$SWOUT" | tail -1)"
check "A swap rejection says identity changed" bash -c "printf '%s' \"\$1\" | grep -q 'identity changed'" _ "$SWOUT"
check "A swapped-in file consumed not (swap target stays)" test -e "$TR/real/constitution_args_swapa0001.txt"
# owner check: unit-test the helper with a different effective uid (a foreign-owned file cannot be created unprivileged)
mkaf "owner000$$" "help"
OUT="$(python3 -I - "$HLP" "$TD/constitution_args_owner000$$.txt" "$TD" 2>&1 <<'PYEOF'
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("afr", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
try:
    m.read_and_consume(sys.argv[2], [sys.argv[3]], euid=os.geteuid() + 1)
    print("ACCEPTED")
except SystemExit as e:
    print("REJECTED", e.code)
PYEOF
)"
check "A foreign-owner file rejected (helper unit, euid+1)" has "$OUT" "REJECTED 2"; check "A foreign-owner file not consumed" test -e "$TD/constitution_args_owner000$$.txt"; rm -f "$TD/constitution_args_owner000$$.txt"
# control needle: the OLD-style pattern (case glob) DOES accept a traversal path, so the instrument can see it
oldglob() { case "$1" in "$2"/constitution_args_*.txt) return 0 ;; esac; return 1; }
check "A control needle: old glob accepts traversal path" oldglob "$TD/constitution_args_x/../../victim/notes.txt" "$TD"
# control needle: the OLD double-quoted form DOES execute the text, so the instrument can see it
( cd "$PA" && bash -c 'bash "$1" "anchors 7 $(touch SENTINEL3)"' _ "$EA" ) >/dev/null 2>&1
check "S1 control needle: old quoted form executes" test -e "$PA/SENTINEL3"
rm -f "$PA/SENTINEL3"
# class sweep: other path-like arguments: '..' segments are refused
run "$EA" update --ref ../../x; check "sweep: update --ref with .. rejected" test $RC -eq 2
run "$EA" update --ref a//b; check "sweep: update --ref with // rejected" test $RC -eq 2
run "$EA" extensions remove ../../x; check "sweep: extensions arg with .. rejected" test $RC -eq 2
run "$EA" install-extension ../x; check "sweep: install-extension .. rejected" test $RC -eq 2

# ---- S2: truncation marker + real tool rc -------------------------------------------------------
run "$EA" gates run cm_big_gate; check "S2 big output tool rc0 preserved" test $RC -eq 0
check "S2 big output bounded" test "${#OUT}" -le 40400; check "S2 truncation marker" has "$OUT" "[truncated: delegated output"
BIG_RC=7 run "$EA" gates run cm_big_gate; check "S2 big output tool rc7 preserved" test $RC -eq 7
# ---- gate timeout range ---------------------------------------------------------------------------
for badt in 0 601 abc 1000 -5; do CONSTITUTION_CMD_GATE_TIMEOUT="$badt" run "$EA" gates run cm_demo_gate; check "gate timeout <$badt> rejected rc2" test $RC -eq 2; done
CONSTITUTION_CMD_GATE_TIMEOUT=600 run "$EA" gates run cm_demo_gate; check "gate timeout 600 ok" test $RC -eq 0
# ---- S5: redactor shapes (synthetic fake values) --------------------------------------------------
run "$EA" gates run cm_secrets_gate; check "S5 secrets gate rc0" test $RC -eq 0
for v in abcdefghijklmnopqrstuvwx0123 zzzzzzzzzzzzzzzz9999 sk_live_ABCDEFGH12345678 hunter2hunter2 pw-value-12345; do check "S5 redacted <$v>" hasnt "$OUT" "$v"; done
check "S5 marker present" has "$OUT" "[REDACTED]"
run "$EA" gates run cm_secrets2_gate; check "S5b gate rc0" test $RC -eq 0
for v in AKIAABCDEFGHIJKLMNOP AIzaSyA1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q fakepassw0rdXYZ FAKEPEMBODYLINEONE0123456789abcdef FAKEPEMBODYLINETWO0123456789abcdef; do check "S5b redacted <$v>" hasnt "$OUT" "$v"; done
check "S5b non-secret text kept" has "$OUT" "after-pem-ok"
check "S5b url host kept" has "$OUT" "@db.example/x"
# ---- S3: bold-form anchors (fixture + the REAL Constitution.md) ---------------------------------
run "$EA" anchors 150; check "S3 fixture bold anchor rc0" test $RC -eq 0; check "S3 bold heading" has "$OUT" "Bold anchor (test)"
check "S3 bold stops at blank" hasnt "$OUT" "after bold paragraph"
RC_DIR="$SB/realc"; mkdir -p "$RC_DIR/scripts/constitution_cmd" "$RC_DIR/scripts/lib"
cp "$SRC/scripts/constitution_cmd/constitution_cmd.sh" "$RC_DIR/scripts/constitution_cmd/"; cp "$REAL_ROOT/scripts/lib/"{constitution_layout,safe_rm}.sh "$REAL_ROOT/scripts/lib/protected_paths.list" "$RC_DIR/scripts/lib/"; cp "$REAL_ROOT/Constitution.md" "$RC_DIR/"
run "$RC_DIR/scripts/constitution_cmd/constitution_cmd.sh" anchors 170
check "S3 real anchor 170 rc0" test $RC -eq 0; check "S3 real anchor 170 text" has "$OUT" "§11.4.170 — Device-independent"; check "S3 real 170 excludes 171" hasnt "$OUT" "§11.4.171 —"
run "$RC_DIR/scripts/constitution_cmd/constitution_cmd.sh" anchors 100
check "S3 real anchor 100 rc0" test $RC -eq 0; check "S3 real anchor 100 text" has "$OUT" "RETIRED"
# ---- S4: extension option allow-list --------------------------------------------------------------
for bad in --root --root=/x --project-root --project-root=/x --yes --bogus --waiver-id; do
    run "$EA" extensions list "$bad"; check "S4 rejects <$bad>" test $RC -eq 2
done
run "$EA" extensions list --root /tmp; check "S4 rejects --root /tmp" test $RC -eq 2; check "S4 rejection message" has "$ERR$OUT" "rejected extension option: --root"
run "$EA" extensions add src --yes; check "S4 add --yes rejected" test $RC -eq 2
run "$EA" extensions list --json; check "S4 allows --json" test $RC -eq 0
run "$EA" extensions add src --sha abc123; check "S4 add --sha allowed" test $RC -eq 0
run "$EA" extensions info '-x;y'; check "S4 weird single-dash rejected" test $RC -eq 2
run "$EA" extensions info '--json;y'; check "S4 --json;y rejected" test $RC -eq 2
# ---- S6: extra args rejected ------------------------------------------------------------------------
run "$EA" jev extra; check "S6 jev extra rc2" test $RC -eq 2
run "$EA" release-notes extra; check "S6 release-notes extra rc2" test $RC -eq 2
# ---- single-string arg is never glob-expanded -------------------------------------------------------
GD="$SB/globdir"; mkdir -p "$GD"; : > "$GD/7"
RUN_CWD="$GD" run "$EA" 'anchors *'; check "glob in lone string not expanded (rc2)" test $RC -eq 2

# ---- determinism x3 -----------------------------------------------------------------------------
d1=""; for i in 1 2 3; do run "$EA" anchors 7; run "$EA" gates; d1="$d1$(printf '%s' "$OUT" | sha256sum)"; done
check "determinism x3" test "$(printf '%s' "$d1" | tr -d ' -' | fold -w64 | sort -u | wc -l)" -eq 1

residue_check() {
    local after; after="$(residue_snap)"
    if [ "$after" = "$RESIDUE_BEFORE" ]; then ok; else bad "residue: new files in repo root or cwd: $(diff <(printf '%s\n' "$RESIDUE_BEFORE") <(printf '%s\n' "$after") | grep '^>' | tr '\n' ' ')"; fi
}
if [ "${CMD_TEST_SKIP_GEN:-0}" = 1 ]; then residue_check; printf 'PASS=%d FAIL=%d (generator section skipped)\n' "$PASS" "$FAIL"; [ "$FAIL" -eq 0 ]; exit; fi
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
for f in "plugins/helix/commands/constitution.md" "actions/generated/gemini/constitution.toml" "actions/generated/codex/constitution.md"; do
    check "generated $f uses --args-file" grep -q -- "--args-file /tmp/constitution_args_" "$G1/$f"
    check "generated $f has no heredoc delimiter" bash -c '! grep -q "CONSTITUTION_ARGS_" "$1"' _ "$G1/$f"
    check "generated $f has no double-quoted arguments form" bash -c '! grep -q "constitution_cmd.sh \"<arguments>\"" "$1"' _ "$G1/$f"
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

residue_check
printf 'PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
