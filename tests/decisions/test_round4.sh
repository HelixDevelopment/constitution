#!/usr/bin/env bash
# test_round4.sh — regression tests for the round-3 independent review (B-A fences, I-A env census, I-B OS errors,
# MINOR items). Class: integration against REAL git projects and the REAL wizard; the two python blocks marked
# UNIT-CLASS import the real engine (no double) and the statvfs block patches os.statvfs (a labelled unit-class
# double, §11.4.289: gate-logic only, never cited as live evidence).
set -u
. "$(dirname "$0")/lib.sh"
new_sandbox; trap 'chmod -R u+w "$SB" 2>/dev/null; cleanup_sandbox' EXIT
C="$DEC_CLI"
ENGINE_DIR="$(dirname "$C")"
JEV_DIR="$DEC_REPO/scripts/jev"
begins() { grep -c '^<!-- BEGIN constitution-decisions' "$1"; }
no_abs() { if grep -qF -- "$SB" "$SB/last.err" "$SB/last.out"; then bad "$1"; else ok "$1"; fi; }
no_tb() { if grep -q 'Traceback' "$SB/last.err" "$SB/last.out"; then bad "$1"; else ok "$1"; fi; }

echo "== B-A: CommonMark fences; the doc never accumulates managed blocks; an unhealthy doc is never worsened =="
# name|CLAUDE.md content (printf format)|expected outcome: ok (one live block, --check clean) or refuse (untouched)
cases=(
  'unclosed|# P\n```\ncode\n|refuse'
  'unclosed_tilde|# P\n~~~~ sh\ncode\n|refuse'
  'short_close|# P\n````\nx\n```\n|refuse'
  'mixed_close|# P\n```\nx\n~~~\n|refuse'
  'block_then_unclosed|# P\n<!-- BEGIN constitution-decisions -->\nold\n<!-- END constitution-decisions -->\n```\nx\n|ok'
  'bt_info_backtick|# P\n``` a`b\ntext\n|ok'
  'tilde_info_backtick|# P\n~~~ a`b\nx\n~~~\n|ok'
  'fenced_example|# P\n~~~\n<!-- BEGIN constitution-decisions -->\nexample\n<!-- END constitution-decisions -->\n~~~\n|ok'
  'longer_close|# P\n````\n```\nx\n````\n|ok'
  'indent3_fence|# P\n   ```\nx\n   ```\n|ok'
  'indent4_code|# P\n    ```\nx\n|ok'
  'tab_code|# P\n\t```\nx\n|ok'
  'nested_longer|# P\n`````\n````\n```\n````\n`````\n|ok'
  'u2028_not_a_line_end|# P\nx ```\n|ok'
  'block_after_closed|# P\n```\nx\n```\n<!-- BEGIN constitution-decisions -->\nold\n<!-- END constitution-decisions -->\n|ok'
)
for c in "${cases[@]}"; do
  IFS='|' read -r name body want <<<"$c"
  P="$(new_project "f_$name")"; printf "$body" >"$P/CLAUDE.md"; before="$(sha "$P/CLAUDE.md")"; n0="$(begins "$P/CLAUDE.md")"
  first=""; grew=0; stale=0
  for v in 0.95 0.96 0.97 0.98; do
    "$C" --project-root "$P" --non-interactive --set calibration.floor=$v >"$SB/last.out" 2>"$SB/last.err"; rc=$?
    [ -z "$first" ] && { first="$(begins "$P/CLAUDE.md")"; frc=$rc; }
    [ "$(begins "$P/CLAUDE.md")" -le "$first" ] || grew=1
    if [ "$rc" = 0 ] && grep -q 'calibration.floor' "$P/CLAUDE.md"; then
      [ "$(grep -c 'calibration.floor' "$P/CLAUDE.md")" = 1 ] && grep -q "calibration.floor\`: $v" "$P/CLAUDE.md" || stale=1
    fi
  done
  check "[$name] BEGIN count never grows across 4 runs" test "$grew" = 0
  if [ "$want" = refuse ]; then
    check "[$name] refused (rc 4)" test "$frc" = 4
    check "[$name] doc untouched" test "$(sha "$P/CLAUDE.md")" = "$before"
    check "[$name] refusal names the unclosed fence" grep -q 'unclosed code fence' "$SB/last.err"
    check "[$name] decisions.yml not written while a doc is refused" test ! -e "$P/.constitution/decisions.yml"
  else
    check "[$name] written (rc 0)" test "$frc" = 0
    check "[$name] exactly one live block added at most" test "$first" -le "$((n0 + 1))"
    check "[$name] no stale value beside the current one" test "$stale" = 0
    expect_rc "[$name] --check clean" 0 "$C" --project-root "$P" --check
  fi
done

echo "== B-A: property test, deterministic random fence layouts (UNIT-CLASS, real engine) =="
python3 -I - "$ENGINE_DIR" >"$SB/prop.out" 2>&1 <<'PY'
import random, sys
sys.dont_write_bytecode = True; sys.path.insert(0, sys.argv[1]); import decisions_engine as d
pool = ["```", "````", "~~~", "~~~~", "``` a`b", "```py", "~~~ a`b", "    ```", "\t~~~", "   ```", "text", "",
        "<!-- BEGIN constitution-decisions -->", "<!-- END constitution-decisions -->", "<!-- END constitution-decisions --> x",
        "``", "  ~~~  ", "```   "]
rng = random.Random(20261030)
bad = runs = refused = 0
for case in range(400):
    doc = "\n".join(rng.choice(pool) for _ in range(rng.randint(0, 9))) + rng.choice(["", "\n"])
    t, first = doc, None
    for i in range(4):
        blk = d.render_block("constitution", {"calibration.floor": 0.91 + i / 100})
        try:
            t2 = d.apply_block(t, blk, "doc")
        except d.Refused:
            refused += 1
            t2 = t
        n = sum(1 for l in d.md_lines(t2) if l.rstrip("\r\n").startswith("<!-- BEGIN constitution-decisions"))
        if first is None:
            first = n
        elif n > first:
            bad += 1
            print("GREW case %d run %d: %r" % (case, i, doc))
            break
        if t2 != t and blk not in t2:
            bad += 1
            print("WRITE WITHOUT CURRENT BLOCK case %d: %r" % (case, doc))
            break
        t = t2
        runs += 1
print("property: cases=400 runs=%d refused=%d violations=%d" % (runs, refused, bad))
sys.exit(1 if bad else 0)
PY
prc=$?
check "property: BEGIN count never grows, every write carries the current block (400 layouts x 4 runs)" test "$prc" = 0
check "property instrument saw refusals AND writes (not blind)" bash -c "grep -q 'refused=[1-9]' '$SB/prop.out' && grep -q 'runs=[1-9]' '$SB/prop.out'"
tail -1 "$SB/prop.out" | sed 's/^/      /'

echo "== I-A: the printed bootstrap command neutralises every variable the bootstrap scripts read =="
# independent instrument: every JEV_/LLMCTL_/CLAUDE_/TYPESAFE_/OPENROUTER_/HELIX_ token in the five scripts
scripts=(bootstrap.sh lib_decide.sh lib_keys.sh jev-calibrate.sh jev-probe.sh)
for f in "${scripts[@]}"; do check "census source readable: $f" test -r "$JEV_DIR/$f"; done
(cd "$JEV_DIR" && grep -ohE '\b(JEV|LLMCTL|CLAUDE|TYPESAFE|OPENROUTER|HELIX)_[A-Z0-9_]+' "${scripts[@]}") | LC_ALL=C sort -u >"$SB/broad.txt"
check "census control needle: JEV_BOOTSTRAP_NESTED found" grep -qx JEV_BOOTSTRAP_NESTED "$SB/broad.txt"
check "census control needle: JEV_CALIBRATE_FLOOR found" grep -qx JEV_CALIBRATE_FLOOR "$SB/broad.txt"
check "census negative control: fabricated name absent" bash -c "! grep -qx JEV_NEEDLE_NOT_THERE_7Q '$SB/broad.txt'"
# names that occur but are NOT read from the environment by these scripts (each with its reason):
#   JEV_BOOTSTRAP_   prose prefix in comments          JEV_MODE   a key inside the jev MCP/env FILES
#   JEV_PROBE_CMD    set by bootstrap for the gates    LLMCTL_VALIDATE_STRICT   set =1 by lib_decide for llmctl
notread='^(JEV_BOOTSTRAP_|JEV_MODE|JEV_PROBE_CMD|LLMCTL_VALIDATE_STRICT)$'
python3 -I - "$ENGINE_DIR" "$SB/broad.txt" "$notread" >"$SB/census.out" 2>&1 <<'PY'
import re, sys
sys.dont_write_bytecode = True; sys.path.insert(0, sys.argv[1]); import decisions_engine as d
names = [n for n in open(sys.argv[2]).read().split() if not re.match(sys.argv[3], n)]
miss = [n for n in names if n not in d.BOOTSTRAP_ENV and n not in d.BOOTSTRAP_PASS_ENV]
print("census: %d names, unclassified: %s" % (len(names), ",".join(miss) or "none"))
sys.exit(1 if miss else 0)
PY
check "every variable read by the bootstrap scripts is classified (unset or deliberately passed)" test $? = 0
sed 's/^/      /' "$SB/census.out"
P="$(new_project env)"
JEV_CALIBRATE_FLOOR=0.5 JEV_BOOTSTRAP_NESTED=1 JEV_BOOTSTRAP_HOME=/tmp/elsewhere JEV_SKIP_VALIDATION=1 \
  "$C" --project-root "$P" --non-interactive --set layer.mode=shadow >"$SB/last.out" 2>"$SB/last.err"
cmd="$(grep '^bootstrap (' "$SB/last.out")"
for n in JEV_CALIBRATE_FLOOR JEV_CALIBRATE_MIN_SAMPLE JEV_BOOTSTRAP_NESTED JEV_BOOTSTRAP_HOME JEV_SKIP_VALIDATION \
         JEV_TEST LLMCTL_REF_OVERRIDE JEV_CONSTITUTION_ROOT; do
  check "printed command unsets $n" grep -q -- "-u $n " <<<"$cmd"
done
check "calibration floor always explicit (default 0.9)" grep -q 'JEV_CALIBRATE_FLOOR=0.9 ' <<<"$cmd"
check "calibration min sample always explicit (default 30)" grep -q 'JEV_CALIBRATE_MIN_SAMPLE=30 ' <<<"$cmd"
check "state locations are passed, not unset" bash -c "! grep -q -- '-u JEV_STATE_DIR ' <<<\"\$1\"" _ "$cmd"
# the printed prefix really neutralises an ambient weakening value
pre="${cmd#bootstrap (printed, NOT run): }"; pre="${pre%% bash *}"
read -ra parts <<<"$pre"
check "printed prefix starts with env" test "${parts[0]}" = env
got="$(JEV_CALIBRATE_FLOOR=0.5 JEV_BOOTSTRAP_NESTED=1 "${parts[@]}" sh -c 'printf "%s|%s" "${JEV_CALIBRATE_FLOOR-unset}" "${JEV_BOOTSTRAP_NESTED-unset}"')"
check "ambient JEV_CALIBRATE_FLOOR=0.5 does not reach bootstrap (got $got)" test "$got" = "0.9|unset"
# run-time re-scan: a NEW variable in a copy of the bootstrap scripts is unset before the static list knows it
F="$SB/fakeconst"; mkdir -p "$F/scripts"; cp -R "$ENGINE_DIR" "$F/scripts/decisions"; cp -R "$JEV_DIR" "$F/scripts/jev"
printf '\n: "${JEV_BRAND_NEW_SWITCH:-}"\n' >>"$F/scripts/jev/bootstrap.sh"
P2="$(new_project rescan)"
expect_rc "wizard from a constitution with a new bootstrap variable" 0 bash "$F/scripts/decisions/constitution_decisions.sh" --project-root "$P2" --non-interactive --set layer.mode=shadow
check "new bootstrap variable is unset by the run-time re-scan" grep -q -- '-u JEV_BRAND_NEW_SWITCH ' "$SB/last.out"

echo "== I-B: OS errors are pre-flighted; never a traceback, an absolute path, or a half-applied change =="
P="$(new_project roroot)"
"$C" --project-root "$P" --non-interactive --set calibration.floor=0.95 >/dev/null 2>&1
mkdir -p "$P/docs"; printf '# D\n' >"$P/docs/x.md"; yb="$(sha "$P/.constitution/decisions.yml")"; chmod 555 "$P/docs"
expect_rc "read-only doc directory refused before any write" 3 "$C" --project-root "$P" --non-interactive --doc docs/x.md --set calibration.floor=0.96
check "message names the unwritable directory" grep -q 'docs is not writable; nothing written' "$SB/last.err"
no_tb "no traceback (read-only directory)"; no_abs "no absolute path (read-only directory)"
check "decisions.yml unchanged after a pre-flight refusal" test "$(sha "$P/.constitution/decisions.yml")" = "$yb"
check "no intent journal left after a pre-flight refusal" test ! -e "$P/.constitution/decisions.intent"
chmod 755 "$P/docs"
P="$(new_project ro444)"; chmod 444 "$P/CLAUDE.md"; cb="$(sha "$P/CLAUDE.md")"
expect_rc "0444 doc refused (not silently replaced)" 3 "$C" --project-root "$P" --non-interactive --set calibration.floor=0.95
check "0444 refusal names the read-only file" grep -q 'CLAUDE.md is read-only; refused' "$SB/last.err"
check "0444 doc untouched and still 0444" bash -c "[ \"\$(sha256sum <'$P/CLAUDE.md' | cut -d' ' -f1)\" = '$cb' ] && [ \"\$(stat -c %a '$P/CLAUDE.md')\" = 444 ]"
check "nothing written for a refused run" test ! -e "$P/.constitution/decisions.yml"
chmod 644 "$P/CLAUDE.md"
P="$(new_project hardlink)"; ln "$P/CLAUDE.md" "$P/twin.md"
expect_rc "hard-linked doc refused" 3 "$C" --project-root "$P" --non-interactive --set calibration.floor=0.95
check "hard-link refusal message" grep -q 'hard links' "$SB/last.err"
check "hard link kept (same inode)" test "$(stat -c %i "$P/CLAUDE.md")" = "$(stat -c %i "$P/twin.md")"
# a failure the pre-flight cannot see (permissions change mid-run): clean message, journal, self-heal
P="$(new_project midrun)"
"$C" --project-root "$P" --non-interactive --set calibration.floor=0.95 >/dev/null 2>&1
CONSTITUTION_DECISIONS_TEST=1 CONSTITUTION_DECISIONS_TEST_WRITE_DELAY=2 "$C" --project-root "$P" --non-interactive \
  --set calibration.floor=0.96 >"$SB/last.out" 2>"$SB/last.err" & wpid=$!
sleep 3; chmod 555 "$P"; wait "$wpid"; mrc=$?; chmod 755 "$P"
check "mid-run permission loss: clean blocked exit (rc $mrc)" test "$mrc" = 3
no_tb "no traceback (mid-run failure)"; no_abs "no absolute path (mid-run failure)"
check "mid-run failure names the intent journal" grep -q 'decisions.intent records the unfinished change' "$SB/last.err"
check "intent journal present after the failure" test -e "$P/.constitution/decisions.intent"
expect_rc "next run completes the change" 0 "$C" --project-root "$P" --non-interactive --set calibration.floor=0.96
expect_rc "check clean after self-heal" 0 "$C" --project-root "$P" --check
check "intent journal gone after self-heal" test ! -e "$P/.constitution/decisions.intent"
# lost update: an editor changes CLAUDE.md while the run waits before replacing it
P="$(new_project lost)"
"$C" --project-root "$P" --non-interactive --set calibration.floor=0.95 >/dev/null 2>&1
CONSTITUTION_DECISIONS_TEST=1 CONSTITUTION_DECISIONS_TEST_WRITE_DELAY=2 "$C" --project-root "$P" --non-interactive \
  --set calibration.floor=0.96 >"$SB/last.out" 2>"$SB/last.err" & wpid=$!
sleep 5; printf 'EDITOR LINE\n' >>"$P/CLAUDE.md"; wait "$wpid"; lrc=$?
check "concurrent editor change detected (rc $lrc)" test "$lrc" = 4
check "lost-update message" grep -q 'CLAUDE.md changed while this run was working' "$SB/last.err"
check "the editor's change survives" grep -q '^EDITOR LINE$' "$P/CLAUDE.md"
expect_rc "re-run after the concurrent edit applies cleanly" 0 "$C" --project-root "$P" --non-interactive --set calibration.floor=0.96
check "editor change still there after the re-run" grep -q '^EDITOR LINE$' "$P/CLAUDE.md"
# size limits and non-regular inputs
python3 -I -c "import sys; open(sys.argv[1],'w').write('decisions:\n  calibration.floor: 0.95\n' + '#' * (4*1024*1024))" "$SB/huge.yml"
expect_rc "oversized answers file refused" 4 "$C" --project-root "$P" --non-interactive --answers "$SB/huge.yml"
check "size refusal message" grep -q 'larger than' "$SB/last.err"
mkfifo "$SB/fifo.yml"
expect_rc "FIFO answers file refused without blocking" 3 timeout 20 "$C" --project-root "$P" --non-interactive --answers "$SB/fifo.yml"
# statvfs-dependent branches (UNIT-CLASS: os.statvfs patched; a live EROFS/ENOSPC needs a mount the host refuses)
python3 -I - "$ENGINE_DIR" "$SB" >"$SB/vfs.out" 2>&1 <<'PY'
import os, sys
sys.dont_write_bytecode = True; sys.path.insert(0, sys.argv[1]); import decisions_engine as d
real = os.statvfs
class V:
    def __init__(self, ro, free): self.f_flag = os.ST_RDONLY if ro else 0; self.f_bavail = free; self.f_frsize = 1
res = []
for ro, free, want in ((True, 10**9, "read-only file system"), (False, 10, "not enough free space"), (False, 10**9, None)):
    d.os.statvfs = lambda p, ro=ro, free=free: V(ro, free)
    try:
        d.preflight([(os.path.join(sys.argv[2], "new.md"), "x")], os.path.basename); got = None
    except d.Precondition as e:
        got = str(e)
    res.append((want is None and got is None) or (want is not None and got is not None and want in got))
d.os.statvfs = real
print("vfs:", res); sys.exit(0 if all(res) else 1)
PY
check "pre-flight refuses a read-only FS and a full FS, passes a healthy one (unit-class)" test $? = 0
P="$(new_project rofresh)"; chmod 555 "$P"
expect_rc "unwritable project root (no .constitution yet) is a clean block" 3 "$C" --project-root "$P" --non-interactive --set calibration.floor=0.95
no_tb "no traceback (unwritable project root)"; no_abs "no absolute path (unwritable project root)"
check "top-level OS error names the file and the OS reason" grep -q 'blocked: .constitution: Permission denied' "$SB/last.err"
chmod 755 "$P"
echo "  SKIP live EROFS/ENOSPC: user-namespace mounts are refused on this host (unshare: uid_map not permitted); topology_unsupported"

echo "== MINOR: output sanitising, redaction precision, file modes =="
P="$(new_project minor)"
expect_rc "unknown option with a token value is a usage error" 2 "$C" --project-root "$P" --bogus "sk-$(printf 'Q%.0s' $(seq 1 30))"
check "unrecognized-argument values not echoed" bash -c "! grep -q 'QQQQ\|bogus' '$SB/last.err'"
expect_rc "invalid --scope choice is a usage error" 2 "$C" --project-root "$P" --scope "$(printf 'x‮y')"
check "invalid choice value not echoed" bash -c "! grep -q \$'‮' '$SB/last.err' && ! grep -q 'xy\|x.*y' '$SB/last.err'"
expect_rc "--doc with a bidi override refused" 3 "$C" --project-root "$P" --non-interactive --doc "$(printf 'a‮b.md')" --set calibration.floor=0.95
check "no raw bidi character in any output" bash -c "! grep -q \$'‮' '$SB/last.err' '$SB/last.out'"
expect_rc "excluded type refused" 4 "$C" --project-root "$P" --non-interactive --set question_types.review_x.mode=shadow
check "anchor text is not eaten by the redaction" grep -q 'review/merge/finding/QA/readiness/evidence/verifier' "$SB/last.err"
P="$(new_project umask077)"
( umask 077; "$C" --project-root "$P" --non-interactive --set calibration.floor=0.95 >/dev/null 2>&1 )
check "new decisions.yml honours umask 077 (mode 600)" test "$(stat -c %a "$P/.constitution/decisions.yml")" = 600
P="$(new_project umask022)"
( umask 022; "$C" --project-root "$P" --non-interactive --set calibration.floor=0.95 >/dev/null 2>&1 )
check "new decisions.yml under umask 022 (mode 644)" test "$(stat -c %a "$P/.constitution/decisions.yml")" = 644
python3 -I - "$ENGINE_DIR" >"$SB/san.out" 2>&1 <<'PY'
import sys
sys.dont_write_bytecode = True; sys.path.insert(0, sys.argv[1]); import decisions_engine as d   # UNIT-CLASS: the real redact / has_control
out = d.redact("a‮b ⁦c\x85d\x1be ok")
ok = all(ch not in out for ch in "‮⁦\x85\x1b") and "\\u202e" in out and out.endswith(" ok")
sec = d.redact("k sk-" + "A" * 40 + " ghp_" + "b" * 20 + " ab0123456789abcdef0123456789abcdef end")
ok = ok and sec == "k [redacted] [redacted] [redacted] end"
ok = ok and all(d.has_control(x) for x in ("‮", "⁩", "\x9b", " ", "﻿")) and not d.has_control("plain-text_1.md")
print("sanitise:", repr(out), repr(sec), ok); sys.exit(0 if ok else 1)
PY
check "redact replaces secret-shaped runs and escapes bidi, C1 and C0 controls; has_control covers them (unit-class)" test $? = 0
python3 -I - "$ENGINE_DIR" >"$SB/post.out" 2>&1 <<'PY'
import sys
sys.dont_write_bytecode = True; sys.path.insert(0, sys.argv[1]); import decisions_engine as d   # UNIT-CLASS: apply_block's post-write check
bad_block = "<!-- BEGIN constitution-decisions -->\n```\n<!-- END constitution-decisions -->\n"
res = []
for doc in ("# P\n", "# P\n<!-- BEGIN constitution-decisions -->\nold\n<!-- END constitution-decisions -->\n"):
    try:
        d.apply_block(doc, bad_block, "doc"); res.append(False)
    except d.Refused as e:
        res.append("would not be recognised" in str(e))
good = d.apply_block("# P\n", d.render_block("constitution", {}), "doc").count("<!-- BEGIN") == 1
print("post-verify:", res, good); sys.exit(0 if all(res) and good else 1)
PY
check "post-write verification refuses a block the next scan would not see (append and replace; unit-class)" test $? = 0

echo "== LEAK: user-scope files never land in the project tree"
P="$(new_project userleak)"
# (a) a user file INSIDE the project: refused for writes and dry-run alike, nothing created in the project
mkdir -p "$P/userconf"; printf 'schema_version: 1\ninherits: submodules/constitution\ndecisions:\n  hosted.allowed: false\n' >"$P/userconf/decisions.yml"
ub="$(sha "$P/userconf/decisions.yml")"
expect_rc "user file inside the project refused (write)" 3 env CONSTITUTION_DECISIONS_USER_FILE="$P/userconf/decisions.yml" \
  "$C" --project-root "$P" --scope user --non-interactive --set hosted.allowed=true
check "refusal names the reason" grep -q 'resolves inside the project being operated on' "$SB/last.err"
expect_rc "user file inside the project refused (dry-run)" 3 env CONSTITUTION_DECISIONS_USER_FILE="$P/userconf/decisions.yml" \
  "$C" --project-root "$P" --scope user --non-interactive --set hosted.allowed=true --dry-run
check "in-project user file unchanged" test "$(sha "$P/userconf/decisions.yml")" = "$ub"
check "no .decisions-backup/ or lock created in the project" test -z "$(cd "$P" && find . -name '.decisions-backup' -o -name '.decisions.lock*')"
# (b) the same through a symlinked directory that resolves into the project
ln -s "$P/userconf" "$SB/linkconf"
expect_rc "user dir symlinked into the project refused" 3 env CONSTITUTION_DECISIONS_USER_FILE="$SB/linkconf/decisions.yml" \
  "$C" --project-root "$P" --scope user --non-interactive --set hosted.allowed=true
check "symlink refusal is the in-project guard (resolved path)" grep -q 'resolves inside the project being operated on' "$SB/last.err"
# (c) XDG_CONFIG_HOME pointing into the project (no explicit user file) is refused the same way
expect_rc "XDG_CONFIG_HOME inside the project refused" 3 env -u CONSTITUTION_DECISIONS_USER_FILE XDG_CONFIG_HOME="$P/xdg" \
  "$C" --project-root "$P" --scope user --non-interactive --set hosted.allowed=true
check "no xdg tree created in the project" test ! -e "$P/xdg"
# (d) a relative user file (would resolve against the cwd) is refused, from a cwd inside the project
expect_rc "relative CONSTITUTION_DECISIONS_USER_FILE refused" 3 sh -c 'cd "$1" && CONSTITUTION_DECISIONS_USER_FILE=rel/decisions.yml "$2" --project-root "$1" --scope user --non-interactive --set hosted.allowed=true' _ "$P" "$C"
check "relative refusal names the reason" grep -q 'must be an absolute path' "$SB/last.err"
check "no rel/ tree created in the project" test ! -e "$P/rel"
# (e) control: a user file outside the project still works, and its backup lands beside it, not in the project
"$C" --project-root "$P" --scope user --non-interactive --set hosted.allowed=false >/dev/null 2>&1
expect_rc "user file outside the project still written (with backup)" 0 "$C" --project-root "$P" --scope user --non-interactive --set hosted.allowed=true
check "backup beside the user file" test -n "$(ls "$SB/userconf/.decisions-backup/" 2>/dev/null)"
check "still nothing user-scope in the project" test -z "$(cd "$P" && find . -name '.decisions-backup')"
finish test_round4
