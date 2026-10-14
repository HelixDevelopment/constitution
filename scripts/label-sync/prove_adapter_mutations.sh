#!/usr/bin/env bash
# scripts/label-sync/prove_adapter_mutations.sh
#
# Purpose : Paired-mutation proof (§1.1 / §11.4.115) for the CLI-agent adapters and
#           install_adapters.sh. Copies scripts/label-sync (+ the canonical labeler)
#           to a SCRATCH tree, applies ONE deliberate defect at a time, and requires
#           the hermetic suite (adapters/tests/test_adapters.sh) to FAIL for each.
#           An UNMUTATED control must pass, and a mutant whose pattern is not found
#           or that leaves the file unchanged is reported INOPERATIVE (a void proof).
# Usage   : prove_adapter_mutations.sh [--keep] [--only NAME[,NAME...]]   (NAME = mutant id, e.g. N8)
# Inputs  : none. Needs jq, python3 (>=3.11 + PyYAML), node (opencode section runs
#           only inside the full suite), and a built labelctl (labelctl.sh --build).
# Outputs : `KILLED`/`SURVIVED`/`INOPERATIVE`/`UNDETERMINED` per mutant and a summary
#           (UNDETERMINED = failed with no `FAIL` assertion line; exit 2, never a pass).
# Exit    : 0 all killed + control green | 1 survivor / inoperative / red control |
#           2 environment error.
# Mutants :
#   installer: A1 dry-run writes | A2 clobbers existing JSON config | A3 non-idempotent
#              (duplicates on re-apply) | A4 invalid JSON "repaired" instead of refused |
#              A5 no backup | A6 codex notify appended after tables | A7 ignores --home
#              (writes under the real $HOME) | A8 aider own notifications-command clobbered
#   lib/hooks: B1 adapters follow the active alias by default | B2 derived Claude effort
#              leaks into a non-Claude entity | B3 kimi hook exits 2 (would BLOCK kimi) |
#              B4 crush hook emits an allow decision | B5 wrapper swallows the exit code |
#              B6 wrapper never marks the entity done | B7 hostile id not sanitized
# Side-effects: temp dir only (removed unless --keep). Heavy-ish (runs the suite per
#           mutant): niced, run alone (§12.7).
# Cross-refs: §1.1, §11.4.115, §11.4.18, docs/label-sync/ADAPTERS.md.
# Classification: universal (§11.4.17).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
LSROOT="$HERE"; CONST="$(cd "$HERE/../.." && pwd)"
for b in jq python3; do command -v "$b" >/dev/null || { echo "prove_adapter_mutations: $b missing" >&2; exit 2; }; done
keep=0 only=""
while [ $# -gt 0 ]; do case "$1" in --keep) keep=1; shift ;; --only) only=",${2:-},"; shift 2 ;; *) shift ;; esac; done
S="$(mktemp -d "${TMPDIR:-/tmp}/ls_adapt_mut.XXXXXX")"; [ "$keep" = 1 ] || trap 'rm -rf "$S"' EXIT
mkdir -p "$S/scripts"
cp -a "$LSROOT" "$S/scripts/label-sync"; cp -a "$CONST/scripts/multitrack" "$S/scripts/multitrack"
rm -rf "$S/scripts/label-sync/.git"
A="$S/scripts/label-sync/adapters"
export LABEL_SYNC_BIN; LABEL_SYNC_BIN="$("$LSROOT/labelctl.sh" --build 2>/dev/null | tail -1)"
run() { (cd "$S" && nice -n 10 bash "$A/tests/test_adapters.sh" ${1:+--only "$1"} >"$S/out.txt" 2>&1); }
snap() { mkdir -p "$S/orig"; cp -a "$A/." "$S/orig/"; }
restore() { rm -rf "$A" && cp -a "$S/orig" "$A"; }
snap
rc=0 killed=0 total=0 undet=0
mutant() { # name  section  file  old  new
  local name="$1" sect="$2" f="$3" old="$4" new="$5"
  [ -z "$only" ] || case "$only" in *",${name%% *},"*) ;; *) return 0 ;; esac
  total=$((total+1)); restore
  if ! F="$A/$f" OLD="$old" NEW="$new" python3 - <<'PY'
import os,sys
p=os.environ["F"]; s=open(p).read(); o=os.environ["OLD"]; n=os.environ["NEW"]
if s.count(o)<1: sys.exit(3)
open(p,"w").write(s.replace(o,n,1))
PY
  then echo "INOPERATIVE $name (pattern not found: void proof)"; rc=1; return; fi
  if cmp -s "$S/orig/$f" "$A/$f"; then echo "INOPERATIVE $name (unchanged)"; rc=1; return; fi
  if run "$sect"; then echo "SURVIVED   $name"; rc=1
  elif ! grep -q '^FAIL ' "$S/out.txt"; then
    # failed without a failing assertion (syntax error, crash): not a kill (§11.4.201)
    echo "UNDETERMINED $name (no FAIL assertion line: $(tail -1 "$S/out.txt" | cut -c1-70))"; undet=1
  else echo "KILLED     $name ($(grep -m1 '^FAIL ' "$S/out.txt" | cut -c1-70))"; killed=$((killed+1)); fi
}
if run ""; then echo "CONTROL    unmutated suite passes ($(tail -1 "$S/out.txt"))"; else echo "CONTROL FAILED"; tail -15 "$S/out.txt"; exit 1; fi

mutant "A1 dry-run writes"                  install _edit_config.py 'write = a.mode in ("apply", "remove")' 'write = True'
mutant "A2 clobbers existing JSON config"   install _edit_config.py '    if text is None or text.strip() == "":
        return {}' '    if True:
        return {}'
mutant "A3 non-idempotent (duplicates)"     install _edit_config.py 'kept = [h for h in pre if not (isinstance(h, dict) and "adapters/crush/crush-hook.sh" in str(h.get("command", "")))]' 'kept = list(pre)'
mutant "A4 invalid JSON repaired"           install _edit_config.py '        raise Refused("invalid", f"existing file is not valid JSON ({e.msg} at line {e.lineno}); refusing to touch it")' '        return {}'
mutant "A5 no backup"                       install _edit_config.py '                write_backup(path, text)' '                pass'
mutant "A6 codex notify after the tables"   install _edit_config.py 'new = block_codex(adir, 0, post) + "\n" * post + remainder' 'new = remainder + "\n" * post + block_codex(adir, 0, post)'
mutant "A7 --home ignored (real HOME used)" install install_adapters.sh '  CFG="$H/.config"            # --home pins' '  H="$HOME"; CFG="$H/.config"            # --home pins'
mutant "A8 aider own command clobbered"     install _edit_config.py '        if "notifications-command" in base or "notifications_command" in base:' '        if False:'
mutant "B1 follow active by default"        lib     lib/adapter_lib.sh 'follow=false; [ "${LABEL_SYNC_FOLLOW_ACTIVE:-}" = 1 ] && follow=true' 'follow=true'
mutant "B2 derived effort leaks"            lib     lib/adapter_lib.sh '  args+=(--model "$mdl" --effort "$eff")' '  [ -n "$mdl" ] && args+=(--model "$mdl")'
mutant "B3 kimi hook exits 2"               kimi    kimi/kimi-hook.sh 'esac
exit 0' 'esac
exit 2'
mutant "B4 crush hook emits allow"          crush   crush/crush-hook.sh "printf '{\"version\":1}\\n'" "printf '{\"version\":1,\"decision\":\"allow\"}\\n'"
mutant "B5 wrapper swallows exit code"      run     generic/label-agent-run.sh 'exit "$rc"' 'exit 0'
mutant "B6 wrapper never marks done"        run     generic/label-agent-run.sh 'cleanup() { [ "$registered" = 1 ] && al_ctl unregister --id "$id" >/dev/null; return 0; }' 'cleanup() { return 0; }'
mutant "B7 hostile id not sanitized"        lib     lib/adapter_lib.sh '  local s="${1//[^A-Za-z0-9._-]/_}" max="${2:-64}" h' '  local s="${1}" max="${2:-64}" h'
mutant "N8 wrapper drops stdin"             run     generic/label-agent-run.sh '( trap - INT QUIT; exec "$@" ) <&0 &' '( trap - INT QUIT; exec "$@" ) </dev/null &'
mutant "N9a backup takes the config mode"   install _edit_config.py '0o600)  # MUT:bakmode' 'os.stat(path).st_mode & 0o7777)  # MUT:bakmode'
mutant "N9b backup not 0600 from birth"     install _edit_config.py '            fd = os.open(bak, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)  # MUT:bakmode' '            fd = os.open(bak, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o666)  # MUT:bakmode'
mutant "C1 agent keeps SIGINT ignored"      run     generic/label-agent-run.sh '( trap - INT QUIT; exec "$@" ) <&0 &' '"$@" <&0 &'
mutant "C2 tty INT forwarded twice"         run     generic/label-agent-run.sh 'then return 0; fi  # MUT:fwdtty' 'then :; fi  # MUT:fwdtty'
mutant "C3 signal before child ignored"     run     generic/label-agent-run.sh '    stop="$1"                                   # before the child exists' '    :'
mutant "C4 separator not taken back"        install _edit_config.py '    if pre and text[a - pre:a] == "\n" * pre:   # MUT:sepstrip' '    if False:   # MUT:sepstrip'
mutant "C5 backups pile up"                 install _edit_config.py '                return b  # MUT:bakdedupe' '                pass  # MUT:bakdedupe'
mutant "C6 dollar adapters dir accepted"    install _edit_config.py '    if UNSAFE & set(adir):  # MUT:unsafe' '    if False:  # MUT:unsafe'
mutant "C7 trailing --home hangs"           install install_adapters.sh 'needv() { [ "$1" -ge 2 ] ||' 'needv() { true ||'
mutant "C8 hook path unquoted"              install _edit_config.py '    return " ".join(shlex.quote(a) for a in argv)' '    return " ".join(argv)'
mutant "C9 JSON original not restored"      install _edit_config.py '                    new = orig  # the user'"'"'s exact original bytes' '                    pass'
mutant "C10 created config kept"            install _edit_config.py '                delete = True  # created by the installer: rollback = absent again' '                delete = False'
restore
echo "---"; echo "prove_adapter_mutations: $killed/$total mutants killed"
[ "$undet" = 0 ] || { echo "prove_adapter_mutations: UNDETERMINED mutant(s) — not a pass"; exit 2; }
[ "$rc" = 0 ] && [ "$killed" = "$total" ]
