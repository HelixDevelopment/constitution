#!/usr/bin/env bash
# test_setup_prompt_round3_mutants.sh — paired mutation proof (§1.1) for
# test_setup_prompt_round3.sh. Each mutant injects ONE defect into a COPY of
# docs/prompts/setup/latest.md, followups/01_verify_incorporation.md,
# scripts/prompts/rotate_setup_prompt.sh or the setup-prompt gate, runs the round 3
# suite against the copy (R3_* overrides) and requires the suite to FAIL (KILLED).
# Before the mutants, the suite must PASS on unmutated copies made the same way
# (control: proves the copy mechanism itself does not cause the failures), and every
# mutant must actually change its file (a no-op mutation is reported, never KILLED).
# Reviewer mutants of round 3: R4-1 R4-2 R4-5 R4-6 STEP2-NO-TOPLEVEL; the others are
# this round's own. Nothing outside mktemp -d sandboxes is written; no network.
# Usage: bash tests/prompts/test_setup_prompt_round3_mutants.sh   Exit 0: every mutant KILLED.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
SUITE="$REPO/tests/prompts/test_setup_prompt_round3.sh"
SRC_L="$REPO/docs/prompts/setup/latest.md"
SRC_F="$REPO/docs/prompts/setup/followups/01_verify_incorporation.md"
SRC_R="$ROTATE"

mutate() { # <id> <in> <out> -> rc 0 when the file changed
  python3 -I - "$1" "$2" "$3" <<'PY'
import sys, re
mid, src, dst = sys.argv[1:4]
s = open(src).read()
def blk(text, b, e):
    i = text.index(b); j = text.index(e, i); return i, j
def in_block(text, b, e, old, new, count=1):
    i, j = blk(text, b, e); seg = text[i:j]
    assert old in seg, (mid, old)
    return text[:i] + seg.replace(old, new, count) + text[j:]
def del_line(text, needle, b=None, e=None):
    i, j = (0, len(text)) if b is None else blk(text, b, e)
    seg = text[i:j]; lines = seg.split('\n')
    hit = [k for k, l in enumerate(lines) if needle in l]
    assert hit, (mid, needle)
    del lines[hit[0]]
    return text[:i] + '\n'.join(lines) + text[j:]
OLD_TOP = '  [ "$(git -C "$c" rev-parse --show-toplevel 2>/dev/null)" = "$(pwd -P)/$c" ] || { echo "STOP: $c is not its own checkout"; exit 3; }'
if mid == 'R4-1':   s = del_line(s, 'has local changes', '# STEP5-BEGIN', '# STEP5-END')
elif mid == 'R4-2': s = del_line(s, 'git status --porcelain -- .gitmodules constitution', '# STEP4-BEGIN', '# STEP4-END')
elif mid == 'R4-5': s = s.replace('[ "$(rsp_lock_age_sec "$lk")" -lt 10 ]', '[ "$(rsp_lock_age_sec "$lk")" -lt 0 ]')
elif mid == 'R4-6': s = in_block(s, '# STEP10-BEGIN', '# STEP10-END', 'git merge-base --is-ancestor "refs/remotes/$r/main" HEAD ||', 'true ||')
elif mid == 'STEP2-NO-TOPLEVEL': s = del_line(s, 'why="$(own_checkout "$c")"', '# STEP2-BEGIN', '# STEP2-END')
elif mid == 'STEP2-TOPLEVEL-ONLY':
    i, j = blk(s, '# STEP2-BEGIN', '# STEP2-END'); seg = s[i:j]
    seg = '\n'.join(OLD_TOP if 'why="$(own_checkout "$c")"' in l else l for l in seg.split('\n'))
    s = s[:i] + seg + s[j:]
elif mid == 'STEP5-TOPLEVEL-ONLY':
    i, j = blk(s, '# STEP5-BEGIN', '# STEP5-END'); seg = s[i:j]
    seg = '\n'.join(OLD_TOP if 'why="$(own_checkout "$c")"' in l else l for l in seg.split('\n'))
    s = s[:i] + seg + s[j:]
elif mid == 'STEP4-TOPLEVEL-ONLY':
    i, j = blk(s, '# STEP4-BEGIN', '# STEP4-END'); seg = s[i:j]
    old4 = '  [ "$(git -C constitution rev-parse --show-toplevel 2>/dev/null)" = "$(pwd -P)/constitution" ] || { echo "STOP: legacy not own checkout"; exit 3; }'
    seg = '\n'.join(old4 if 'why="$(own_checkout constitution)"' in l else l for l in seg.split('\n'))
    s = s[:i] + seg + s[j:]
elif mid == 'NO-URL-FALLBACK': s = s.replace('&& return 0\n    echo "$p is another repository', '&& false\n    echo "$p is another repository')
elif mid == 'NO-WORKTREE-CHECK': s = re.sub(r'\n    \[ "\$scd" != "\$pcd" \] \|\| \{[^\n]*', '', s)
elif mid == 'NO-STATUS-ERROR': s = re.sub(r'(st="\$\(git submodule status -- [^)]*\)") \|\| \{[^\n]*?exit 3; \}', r'\1', s)
elif mid == 'STEP10-ONE-PHASE':
    s = in_block(s, '# STEP10-BEGIN', '# STEP10-END', '    fi\n  done\n  for r in $remotes; do   # phase 2', '    fi\n  # phase 2 merged into phase 1')
elif mid == 'S7-SUBSTRING': s = in_block(s, '# S7-BEGIN', '# S7-END', 'grep -vcE "$lx")"', 'grep -vic legacy)"')
elif mid == 'V6-SUBSTRING': s = in_block(s, '# V6-BEGIN', '# V6-END', 'grep -vcE "$lx")"', 'grep -vic legacy)"')
elif mid == 'S7-TRIVIAL-NEEDLE': s = in_block(s, '# S7-BEGIN', '# S7-END', "$(grep -cE '[^[:space:]]' \"$f\")", '$(grep -cF -- "$(head -n1 "$f")" "$f")')
elif mid == 'V6-TRIVIAL-NEEDLE': s = in_block(s, '# V6-BEGIN', '# V6-END', "$(grep -cE '[^[:space:]]' \"$f\")", '$(grep -cF -- "$(head -n1 "$f")" "$f")')
elif mid == 'STEP4G-LINES': s = in_block(s, '# STEP4G-BEGIN', '# STEP4G-END', '-cE "$rx"', '-nE "$rx"')
elif mid == 'STEP4G-NO-SECRET-EXCL':
    s = in_block(s, '# STEP4G-BEGIN', '# STEP4G-END', " ':(exclude,glob)**/.env*' ':(exclude,glob)**/settings.local.json' ':(exclude,glob)**/*.pem' ':(exclude,glob)**/*.key' ':(exclude,glob)**/credentials*'", '')
elif mid == 'GATE-LIB-UNCHECKED': s = s.replace('then lib_untrusted=1; fi', 'then :; fi')
else: sys.exit(9)
open(dst, 'w').write(s)
sys.exit(0 if open(src).read() != s else 1)
PY
}

# id -> which file it mutates
declare -A WHICH=(
  [R4-1]=L [R4-2]=L [R4-5]=R [R4-6]=L [STEP2-NO-TOPLEVEL]=L
  [STEP2-TOPLEVEL-ONLY]=L [STEP5-TOPLEVEL-ONLY]=L [STEP4-TOPLEVEL-ONLY]=L
  [NO-URL-FALLBACK]=L [NO-WORKTREE-CHECK]=L [NO-STATUS-ERROR]=L [STEP10-ONE-PHASE]=L
  [S7-SUBSTRING]=L [V6-SUBSTRING]=F [S7-TRIVIAL-NEEDLE]=L [V6-TRIVIAL-NEEDLE]=F
  [STEP4G-LINES]=L [STEP4G-NO-SECRET-EXCL]=L [GATE-LIB-UNCHECKED]=G
)
ORDER=(R4-1 R4-2 R4-5 R4-6 STEP2-NO-TOPLEVEL STEP2-TOPLEVEL-ONLY STEP5-TOPLEVEL-ONLY STEP4-TOPLEVEL-ONLY
       NO-URL-FALLBACK NO-WORKTREE-CHECK NO-STATUS-ERROR STEP10-ONE-PHASE S7-SUBSTRING V6-SUBSTRING
       S7-TRIVIAL-NEEDLE V6-TRIVIAL-NEEDLE STEP4G-LINES STEP4G-NO-SECRET-EXCL GATE-LIB-UNCHECKED)

prep() { # <sandbox> -> copies of every input under <sandbox>
  local s="$1"
  cp "$SRC_L" "$s/latest.md"; cp "$SRC_F" "$s/fu01.md"
  mkdir -p "$s/r/scripts/prompts" "$s/r/scripts/lib"   # the rotate script finds its library at ../lib
  cp "$SRC_R" "$s/r/scripts/prompts/"; cp "$REPO/scripts/lib/setup_prompt_extract.sh" "$s/r/scripts/lib/"
  mkdir -p "$s/g/scripts/gates" "$s/g/scripts/lib"
  cp "$GATE" "$s/g/scripts/gates/"; cp "$REPO/scripts/lib/setup_prompt_extract.sh" "$s/g/scripts/lib/"
}
run_suite() { # <sandbox> -> suite rc; output in <sandbox>/suite.out
  R3_LATEST="$1/latest.md" R3_FU01="$1/fu01.md" R3_ROTATE="$1/r/scripts/prompts/rotate_setup_prompt.sh" R3_GATE_DIR="$1/g" \
    bash "$SUITE" >"$1/suite.out" 2>&1
}

C="$(mk_sandbox)"; prep "$C"; run_suite "$C"; rc=$?
[ "$rc" -eq 0 ] && ok "control: round 3 suite PASSES on unmutated copies ($(tail -n1 "$C/suite.out"))" \
  || { no "control: suite fails on unmutated copies: $(grep -E '^FAIL' "$C/suite.out" | head -n 5)"; summary round3_mutants; exit 1; }

for m in "${ORDER[@]}"; do
  M="$(mk_sandbox)"; prep "$M"
  case "${WHICH[$m]}" in
    L) f="$M/latest.md" ;; F) f="$M/fu01.md" ;; R) f="$M/r/scripts/prompts/rotate_setup_prompt.sh" ;; G) f="$M/g/scripts/gates/cm_setup_prompt_latest_present.sh" ;;
  esac
  if ! mutate "$m" "$f" "$f.mut"; then no "mutant $m did not change its file (no-op mutation)"; continue; fi
  mv -f -- "$f.mut" "$f"
  run_suite "$M"; rc=$?
  if [ "$rc" -ne 0 ]; then
    ok "mutant $m KILLED by: $(grep -E '^FAIL' "$M/suite.out" | head -n 2 | cut -c1-140 | tr '\n' '|')"
  else
    no "mutant $m SURVIVED ($(tail -n1 "$M/suite.out"))"
  fi
done
summary round3_mutants
