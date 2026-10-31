#!/usr/bin/env bash
# test_round5.sh — regression tests for the round-4 independent review (I-1 cross-layer contradiction, I-2 foreign
# write targets, I-3 project precondition, I-4 key material in backups, I-5 path redaction, I-6 honest wording,
# MINOR items). Class: integration against REAL git projects and the REAL wizard CLI (no re-implementation of the
# logic under test); the blocks marked UNIT-CLASS import the real engine. Every sandbox is a mktemp -d; deletes go
# through safe_rm_rf; HOME is never reassigned.
set -u
. "$(dirname "$0")/lib.sh"
new_sandbox; trap 'chmod -R u+w "$SB" 2>/dev/null; cleanup_sandbox' EXIT
C="$DEC_CLI"
ENGINE_DIR="$(dirname "$C")"
tree() { local d; for d in "$@"; do if [ -e "$d" ]; then (cd "$d" && find . -printf '%p %y %s %m\n' | LC_ALL=C sort \
  && find . -type f -exec sha256sum {} + | LC_ALL=C sort); else echo "absent $d"; fi; done | sha256sum | cut -d' ' -f1; }
newuser() { export CONSTITUTION_DECISIONS_USER_FILE="$SB/u$1/decisions.yml"; }

echo "== I-1: a cross-layer contradiction never bricks read or recovery paths =="
mk_contradiction() { # $1 = case id; leaves project B (preference lists hosted) under a user layer hosted.allowed=false
  newuser "$1"; PA="$(new_project "a$1")"; PB="$(new_project "b$1")"
  "$C" --project-root "$PB" --non-interactive --set endpoints.preference=local,lan,hosted >/dev/null 2>&1
  "$C" --project-root "$PA" --scope user --non-interactive --set hosted.allowed=false >"$SB/last.out" 2>"$SB/last.err"
}
mk_contradiction 1; check "setup: user-scope write from project A succeeded" test -f "$SB/u1/decisions.yml"
expect_rc "--show in B still works" 0 "$C" --project-root "$PB" --show
check "--show reports the contradiction" grep -qi 'contradiction' "$SB/last.out" "$SB/last.err"
expect_rc "--show --json in B still works" 0 "$C" --project-root "$PB" --show --json
check "--show --json stays valid JSON" python3 -I -c 'import json,sys; json.load(open(sys.argv[1]))' "$SB/last.out"
expect_rc "--check reports (not refuses): rc 4, as for drift" 4 "$C" --project-root "$PB" --check
check "--check says WARNING contradiction and how to recover" bash -c "grep -qi 'WARNING' '$SB/last.err' && grep -qi 'contradiction' '$SB/last.err'"
expect_rc "--plan in B still works" 0 "$C" --project-root "$PB" --plan
expect_rc "--reset in B recovers" 0 "$C" --project-root "$PB" --non-interactive --reset
mk_contradiction 2
expect_rc "--unset endpoints.preference in B recovers" 0 "$C" --project-root "$PB" --non-interactive --unset endpoints.preference
expect_rc "after the unset, --check is clean" 0 "$C" --project-root "$PB" --check
mk_contradiction 3
printf 'schema_version: 1\ninherits: submodules/constitution\ndecisions: {}\n' >"$SB/clean.yml"
expect_rc "--export - in B still works" 0 "$C" --project-root "$PB" --export -
expect_rc "--import of a clean file recovers B" 0 "$C" --project-root "$PB" --non-interactive --import "$SB/clean.yml"
mk_contradiction 4
expect_rc "--scope user --reset from B recovers the user layer" 0 "$C" --project-root "$PB" --scope user --non-interactive --reset
expect_rc "after the user reset, B --check is clean" 0 "$C" --project-root "$PB" --check
mk_contradiction 5
expect_rc "an unrelated write in a contradicted project is allowed (the contradiction is not NEW)" 0 \
  "$C" --project-root "$PB" --non-interactive --set calibration.floor=0.95
mk_contradiction 6
expect_rc "a write that would CREATE a new contradiction is still refused" 4 \
  "$C" --project-root "$PA" --non-interactive --set endpoints.preference=local,hosted
check "…with the contradiction message" grep -q 'contradiction' "$SB/last.err"
# the layer.mode / enforce analogue (inherited layer.mode weakened under a project enforce type)
newuser 7; PA="$(new_project a7)"; PB="$(new_project b7)"
"$C" --project-root "$PA" --scope user --non-interactive --set layer.mode=enforce >/dev/null 2>&1
"$C" --project-root "$PB" --non-interactive --set question_types.gate.mode=enforce >/dev/null 2>&1
"$C" --project-root "$PA" --scope user --non-interactive --set layer.mode=shadow >"$SB/last.out" 2>"$SB/last.err"
expect_rc "layer.mode analogue: B --show still works" 0 "$C" --project-root "$PB" --show
expect_rc "layer.mode analogue: B --check reports rc 4" 4 "$C" --project-root "$PB" --check
expect_rc "layer.mode analogue: B --reset recovers" 0 "$C" --project-root "$PB" --non-interactive --reset
expect_rc "layer.mode analogue: B clean afterwards" 0 "$C" --project-root "$PB" --check

echo "== MINOR: never_enforce contradiction, not pre-empted by the layer-mode check =="
newuser 8; PM="$(new_project m8)"
expect_rc "layer.mode=enforce + gate=enforce + gate in never_enforce refused" 4 "$C" --project-root "$PM" --non-interactive \
  --set layer.mode=enforce --set question_types.gate.mode=enforce --set exclusions.never_enforce=gate
check "…by the never_enforce rule (message oracle)" grep -q 'never_enforce' "$SB/last.err"
check "…and not by the layer-mode rule" bash -c "! grep -q 'but layer.mode is' '$SB/last.err'"

echo "== I-2: no write target resolves into the inherited constitution, a gitlink or another repository =="
newuser 9; P="$(new_project i2)"
mkdir -p "$P/submodules/constitution"
printf '# Constitution carrier\n' >"$P/submodules/constitution/CLAUDE.md"
rm -f "$P/AGENTS.md"; ln -s submodules/constitution/CLAUDE.md "$P/AGENTS.md"
mkdir -p "$P/docs"; ln -s ../submodules/constitution/CLAUDE.md "$P/docs/inherited.md"
ln -s submodules/constitution "$P/linkdir"
mkdir -p "$P/vendor/lib/.git"; printf '# lib\n' >"$P/vendor/lib/README.md"
mkdir -p "$P/ext/thing"; printf '# thing\n' >"$P/ext/thing/README.md"
printf '[submodule "ext/thing"]\n\tpath = ext/thing\n\turl = git@example.invalid:o/thing.git\n' >"$P/.gitmodules"
mkdir -p "$P/nested/sub" ; printf '.git' >/dev/null
carrier_sha="$(sha "$P/submodules/constitution/CLAUDE.md")"
t0="$(tree "$P/submodules" "$P/vendor" "$P/ext")"
expect_rc "default AGENTS.md symlinked into the constitution: wizard runs, target skipped" 0 "$C" --project-root "$P" --non-interactive --set calibration.floor=0.95
check "…the constitution carrier is byte-identical" test "$(sha "$P/submodules/constitution/CLAUDE.md")" = "$carrier_sha"
check "…the skip is announced" grep -qi 'skip' "$SB/last.err" "$SB/last.out"
check "…CLAUDE.md of the project got the block" grep -q 'BEGIN constitution-decisions' "$P/CLAUDE.md"
expect_rc "--check ignores the skipped symlinked default doc" 0 "$C" --project-root "$P" --check
expect_rc "--doc into the constitution refused (exit 3)" 3 "$C" --project-root "$P" --non-interactive --set calibration.floor=0.96 --doc submodules/constitution/CLAUDE.md
check "…message names the rule" grep -qi 'inherited\|submodule\|another repository' "$SB/last.err"
expect_rc "--doc via an in-project symlink into the constitution refused" 3 "$C" --project-root "$P" --non-interactive --set calibration.floor=0.96 --doc docs/inherited.md
expect_rc "--export into the constitution refused" 3 "$C" --project-root "$P" --export submodules/constitution/out.yml
expect_rc "--export through a symlinked directory into the constitution refused" 3 "$C" --project-root "$P" --export linkdir/out.yml
expect_rc "--doc inside a directory with its own .git refused" 3 "$C" --project-root "$P" --non-interactive --set calibration.floor=0.96 --doc vendor/lib/README.md
expect_rc "--doc under a .gitmodules path refused" 3 "$C" --project-root "$P" --non-interactive --set calibration.floor=0.96 --doc ext/thing/README.md
expect_rc "--export under a .gitmodules path refused" 3 "$C" --project-root "$P" --export ext/thing/o.yml
check "nothing was written into submodules/vendor/ext" test "$(tree "$P/submodules" "$P/vendor" "$P/ext")" = "$t0"
P2="$SB/legacy"; mkdir -p "$P2/constitution"; git -C "$P2" init -q 2>/dev/null; printf '# P\n' >"$P2/CLAUDE.md"; printf '# c\n' >"$P2/constitution/CLAUDE.md"
expect_rc "legacy ./constitution carrier is also protected" 3 "$C" --project-root "$P2" --non-interactive --set calibration.floor=0.95 --doc constitution/CLAUDE.md
check "…legacy carrier untouched" test "$(cat "$P2/constitution/CLAUDE.md")" = "# c"

echo "== I-3: a project precondition; a bare directory or HOME gets nothing without --inherits =="
newuser 10
B="$SB/bare"; mkdir -p "$B"; printf '# Home-like\n' >"$B/CLAUDE.md"
expect_rc "bare dir (no repo, no constitution) refused" 3 "$C" --project-root "$B" --non-interactive --set calibration.floor=0.95
check "…nothing created" bash -c "[ ! -e '$B/.constitution' ] && [ ! -e '$B/.constitution-install-backup' ] && [ \"\$(cat '$B/CLAUDE.md')\" = '# Home-like' ]"
check "…message says what is missing" grep -qi 'constitution' "$SB/last.err"
expect_rc "bare dir: --show still works (read-only)" 0 "$C" --project-root "$B" --show
expect_rc "bare dir: --dry-run also refused" 3 "$C" --project-root "$B" --non-interactive --set calibration.floor=0.95 --dry-run
mkdir -p "$B/submodules/constitution"
expect_rc "bare dir: explicit --inherits accepted (the path must exist, round 6)" 0 "$C" --project-root "$B" --non-interactive --inherits submodules/constitution --set calibration.floor=0.95
expect_rc "--inherits with a bad value refused" 2 "$C" --project-root "$B" --non-interactive --inherits '../x' --set calibration.floor=0.96
G="$SB/gitonly"; mkdir -p "$G"; git -C "$G" init -q 2>/dev/null; printf '# G\n' >"$G/CLAUDE.md"
expect_rc "git repo without an inherited constitution refused" 3 "$C" --project-root "$G" --non-interactive --set calibration.floor=0.95
FH="$SB/fakehome"; mkdir -p "$FH/submodules/constitution"; git -C "$FH" init -q 2>/dev/null; printf '# H\n' >"$FH/CLAUDE.md"
expect_rc "the HOME directory itself refused" 3 env HOME="${FH:?}" "$C" --project-root "$FH" --non-interactive --set calibration.floor=0.95
expect_rc "…explicit --inherits lets the operator override" 0 env HOME="${FH:?}" "$C" --project-root "$FH" --non-interactive --inherits submodules/constitution --set calibration.floor=0.95
expect_rc "a project that has the constitution still works" 0 "$C" --project-root "$(new_project ok10)" --non-interactive --set calibration.floor=0.95

echo "== MINOR: --project-root inside .git refused =="
PG="$(new_project g11)"
expect_rc "--project-root .git refused" 3 "$C" --project-root "$PG/.git" --show
expect_rc "--project-root .git/hooks refused" 3 "$C" --project-root "$PG/.git/hooks" --non-interactive --set calibration.floor=0.95

echo "== I-4: recovery never copies key material into backups; backups are private =="
newuser 12; P="$(new_project i4)"
"$C" --project-root "$P" --non-interactive --set calibration.floor=0.95 >/dev/null 2>&1
SECRET="sk-$(printf 'Q%.0s' $(seq 1 30))"
printf 'schema_version: 1\ninherits: submodules/constitution\ndecisions:\n  llmctl.download_profile: %s\n' "$SECRET" >"$P/.constitution/decisions.yml"
expect_rc "--reset --accept-external-edits recovers a secret-shaped stored entry" 0 "$C" --project-root "$P" --non-interactive --reset --accept-external-edits
check "secret is in no backup file" bash -c "! grep -rqF -- '$SECRET' '$P/.constitution-install-backup'"
check "secret is in no file of the project" bash -c "! grep -rqF -- '$SECRET' '$P' --exclude-dir=.git"
check "secret not echoed" bash -c "! grep -qF -- '$SECRET' '$SB/last.out' '$SB/last.err'"
bd="$(ls -d "$P"/.constitution-install-backup/*decisions* | sort | tail -1)"
check "backup dirs are 0700" bash -c "[ \"\$(stat -c %a '$P/.constitution-install-backup')\" = 700 ] && [ \"\$(stat -c %a '$bd')\" = 700 ] && [ \"\$(stat -c %a '$bd/.constitution')\" = 700 ]"
check "backup files are 0600" bash -c "[ \"\$(find '$P/.constitution-install-backup' -type f -printf '%m\n' | sort -u)\" = 600 ]"
check "the redacted backup says so" grep -q 'redacted' "$bd/.constitution/decisions.yml"
check "gitignore guidance printed once backups exist" grep -q 'gitignore' "$SB/last.err" "$SB/last.out"
# user scope
newuser 13; P="$(new_project i4u)"; mkdir -p "$SB/u13"
printf 'schema_version: 1\ninherits: submodules/constitution\ndecisions:\n  llmctl.download_profile: %s\n' "$SECRET" >"$SB/u13/decisions.yml"
expect_rc "user-scope --reset recovers a secret-shaped entry" 0 "$C" --project-root "$P" --scope user --non-interactive --reset
check "secret in no user backup" bash -c "! grep -rqF -- '$SECRET' '$SB/u13'"
check "user backup dir 0700, file 0600" bash -c "[ \"\$(stat -c %a '$SB/u13/.decisions-backup')\" = 700 ] && [ \"\$(find '$SB/u13/.decisions-backup' -type f -printf '%m\n' | sort -u)\" = 600 ]"
# export replace
newuser 14; P="$(new_project i4e)"
printf 'schema_version: 1\ninherits: submodules/constitution\ndecisions:\n  llmctl.download_profile: %s\n' "$SECRET" >"$P/old.yml"
expect_rc "--export --force-export replaces a secret-bearing file" 0 "$C" --project-root "$P" --export old.yml --force-export
check "…its backup does not hold the secret" bash -c "! grep -rqF -- '$SECRET' '$P/.constitution-install-backup'"

echo "== I-5: validated filesystem paths are never redacted =="
newuser 15
LONG="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1bbbbbbbbbbbbbbbbbbbbbbbb"
mkdir -p "$SB/$LONG"; P="$SB/$LONG/proj"; mkdir -p "$P/submodules/constitution"; git -C "$P" init -q 2>/dev/null; printf '# P\n' >"$P/CLAUDE.md"
export CONSTITUTION_DECISIONS_USER_FILE="$SB/$LONG/userconf/decisions.yml"
real="$(cd "$P" && pwd -P)"
expect_rc "--show --json with a long path segment" 0 "$C" --project-root "$P" --show --json
check "project_root is the exact real path" python3 -I -c 'import json,sys; j=json.load(open(sys.argv[1])); assert j["project_root"]==sys.argv[2], j["project_root"]' "$SB/last.out" "$real"
check "project_file / user_file are exact" python3 -I -c 'import json,sys; j=json.load(open(sys.argv[1])); assert j["project_file"]==sys.argv[2]+"/.constitution/decisions.yml"; assert j["user_file"]==sys.argv[3]' "$SB/last.out" "$real" "$CONSTITUTION_DECISIONS_USER_FILE"
expect_rc "--show (text) with a long path segment" 0 "$C" --project-root "$P" --show
check "text output holds the real path" grep -qF -- "$real" "$SB/last.out"
expect_rc "user write under a long path" 0 "$C" --project-root "$P" --scope user --non-interactive --set calibration.floor=0.95
"$C" --project-root "$P" --scope user --non-interactive --set calibration.floor=0.96 >"$SB/last.out" 2>"$SB/last.err"
check "user backup line holds the real path" grep -qF -- "$LONG" "$SB/last.out"
check "the secret redaction still works (values)" bash -c "'$C' --project-root '$P' --non-interactive --set llmctl.download_profile='$SECRET' 2>&1 | grep -qv '$SECRET'"

echo "== I-6: honest wording about layer.mode=off and no false 'only tighten' claim =="
newuser 16; P="$(new_project i6)"
"$C" --project-root "$P" --non-interactive --set layer.mode=off >"$SB/last.out" 2>"$SB/last.err"
check "off: block names the §11.4.279(E) conflict" grep -q '11.4.279(E)' "$P/CLAUDE.md"
check "off: decisions.yml header names it" grep -q '11.4.279(E)' "$P/.constitution/decisions.yml"
check "off: no 'only tighten' claim in the block" bash -c "! grep -qi 'only tighten' '$P/CLAUDE.md'"
check "off: no 'only tighten' claim in decisions.yml" bash -c "! grep -qi 'only tighten' '$P/.constitution/decisions.yml'"
check "off: bootstrap line says what off does" grep -q 'off' "$SB/last.out"
expect_rc "off: --check still clean (wording is part of the block)" 0 "$C" --project-root "$P" --check
P="$(new_project i6b)"
"$C" --project-root "$P" --non-interactive --set calibration.floor=0.95 >/dev/null 2>&1
check "non-off: no 'only tighten' either" bash -c "! grep -qi 'only tighten' '$P/CLAUDE.md' '$P/.constitution/decisions.yml'"
check "plan has no unqualified 'only tighten' claim" bash -c "! grep -n 'only tighten' '$DEC_REPO/docs/design/decisions_wizard_plan.md' | grep -vi 'locked'"

echo "== MINOR: PROFILE_RE charset is pinned (UNIT-CLASS, real engine) =="
python3 -I - "$ENGINE_DIR" >"$SB/prof.out" 2>&1 <<'PY'
import sys
sys.dont_write_bytecode = True; sys.path.insert(0, sys.argv[1]); import decisions_engine as d
good = ["a", "A1", "llama-3.2_1B.q4", "x" * 64, "9abc", "a.b-c_d"]
bad = ["", "-a", ".a", "_a", "a b", "a/b", "../x", "a\n", "a:b", "a,b", "a$b", "a;b", "x" * 65, "é", "a​", "a\x00"]
errs = [g for g in good if not d.PROFILE_RE.fullmatch(g)] + [b for b in bad if d.PROFILE_RE.fullmatch(b)]
print("PROFILE_RE errors:", errs)
sys.exit(1 if errs else 0)
PY
check "PROFILE_RE accepts exactly the documented charset" test "$?" = 0
P="$(new_project prof)"
for v in 'a b' 'a/b' '../x' 'a;b' 'a$b'; do
  expect_rc "profile '$v' refused by the CLI" 4 "$C" --project-root "$P" --non-interactive --set "llmctl.download_profile=$v"
done

echo "== MINOR: the number grammar is tight =="
P="$(new_project num)"
for v in '0.9_5' '0x1' 'nan' 'inf' '9e' '0.95e0.1' '1,0' '٠.٩٥'; do
  expect_rc "calibration.floor=$v refused" 4 "$C" --project-root "$P" --non-interactive --set "calibration.floor=$v"
done
for v in '3_0' '0x1e' '30.5' '3e1' ' ' '٣٠'; do
  expect_rc "calibration.min_sample=$v refused" 4 "$C" --project-root "$P" --non-interactive --set "calibration.min_sample=$v"
done
expect_rc "calibration.floor=0.95 ok" 0 "$C" --project-root "$P" --non-interactive --set calibration.floor=0.95
expect_rc "calibration.floor=9.5e-1 ok" 0 "$C" --project-root "$P" --non-interactive --set 'calibration.floor=9.5e-1'
expect_rc "calibration.min_sample=45 ok" 0 "$C" --project-root "$P" --non-interactive --set calibration.min_sample=45

echo "== MINOR: backup pruning is guarded (UNIT-CLASS, real engine) =="
python3 -I - "$ENGINE_DIR" "$SB" >"$SB/prune.out" 2>&1 <<'PY'
import os, sys, tempfile
sys.dont_write_bytecode = True; sys.path.insert(0, sys.argv[1]); import decisions_engine as d
sb = sys.argv[2]; os.environ["CONSTITUTION_DECISIONS_BACKUP_KEEP"] = "1"
root = tempfile.mkdtemp(prefix="prune.", dir=sb)
def mk(base, names):
    os.makedirs(base, exist_ok=True)
    for n in names:
        os.makedirs(os.path.join(base, n), exist_ok=True)
        open(os.path.join(base, n, "f"), "w").write("x")
names = ["20260101T000000Z-decisions", "20260102T000000Z-decisions", "20260103T000000Z-decisions"]
other = os.path.join(root, "not-a-wizard-dir"); mk(other, names)
d.prune(other, d.BACKUP_DIR_RE, True)
assert len(os.listdir(other)) == 3, "prune touched a directory that is not a wizard backup location"
good = os.path.join(root, ".constitution-install-backup"); mk(good, names)
d.prune(good, d.BACKUP_DIR_RE, True)
assert sorted(os.listdir(good)) == [names[2]], os.listdir(good)
# a backup entry that is a symlink to elsewhere is never followed or removed through
victim = os.path.join(root, "victim"); mk(victim, ["keep"])
good2 = os.path.join(root, "x", ".constitution-install-backup"); mk(good2, names[1:])
os.symlink(victim, os.path.join(good2, names[0]))
d.prune(good2, d.BACKUP_DIR_RE, True)
assert os.path.isdir(os.path.join(victim, "keep")), "prune followed a symlink"
print("prune ok")
PY
check "prune only works inside a wizard backup location and never follows links" grep -q 'prune ok' "$SB/prune.out"

echo "== MINOR: discriminating FORBIDDEN_TOP case (the directory exists, so the rule is what answers) =="
P="$(new_project ft)"; mkdir -p "$P/.constitution-install-backup"
expect_rc "--export into an EXISTING backup dir refused" 3 "$C" --project-root "$P" --export .constitution-install-backup/x.yml
check "…by the forbidden-directory rule" grep -q 'may not target' "$SB/last.err"
mkdir -p "$P/.constitution"
expect_rc "--export into an EXISTING .constitution refused" 3 "$C" --project-root "$P" --export .constitution/x.yml
check "…by the forbidden-directory rule" grep -q 'may not target' "$SB/last.err"

echo "== MINOR: docs state the registry exit list and the unclosed-comment risk =="
check "registry proposal lists exit 1" grep -q '1 internal' "$DEC_REPO/scripts/decisions/registry_rows_proposal.yaml"
check "plan states enforce needs the exact type name" grep -q 'exact' "$DEC_REPO/docs/design/decisions_wizard_plan.md"
check "plan records the unclosed <!-- risk as UNCONFIRMED" grep -q 'UNCONFIRMED.*<!--\|<!--.*UNCONFIRMED' "$DEC_REPO/docs/design/decisions_wizard_plan.md"

finish "test_round5"
