#!/usr/bin/env bash
# test_setup_prompt_round4_mutants.sh — paired mutation proof (§1.1) for
# test_setup_prompt_round4.sh. Each mutant injects ONE defect into a COPY of
# docs/prompts/setup/latest.md or a follow-up, runs the round 4 suite against the
# copies (R4_* overrides) and requires the suite to FAIL (KILLED). Before the
# mutants the suite must PASS on unmutated copies made the same way (control), and
# every mutant must actually change its file (a no-op mutation is reported, never
# KILLED). Reviewer mutants of round 4: V1 V4 V6 V7; the others are this round's own.
# Nothing outside mktemp -d sandboxes is written; no network.
# Usage: bash tests/prompts/test_setup_prompt_round4_mutants.sh   Exit 0: every mutant KILLED.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
SUITE="$REPO/tests/prompts/test_setup_prompt_round4.sh"
SRC="$REPO/docs/prompts/setup"

mutate() { # <id> <in> <out> -> rc 0 when the file changed
  python3 -I - "$1" "$2" "$3" <<'PY'
import sys
mid, src, dst = sys.argv[1:4]
s = open(src).read()
def in_block(text, b, e, old, new):
    i = text.index(b); j = text.index(e, i); seg = text[i:j]
    assert old in seg, (mid, old)
    return text[:i] + seg.replace(old, new, 1) + text[j:]
B = lambda n: ('# %s-BEGIN' % n, '# %s-END' % n)
M = {
 'V1':  ('STEP6B', " || ! grep -qF 'post_update_hook.sh: OK' <<<\"$out\"", ''),
 'V4':  ('STEP10', 'git push --recurse-submodules=no', 'git push --force-with-lease --recurse-submodules=no'),
 'V6':  ('STEP1', "|| echo '.constitution-install-backup/' >> \"$excl\"", '|| true'),
 'V7':  ('STEP3', 'rrun git submodule update --init -- submodules/constitution', 'rrun git submodule update --init --recursive -- submodules/constitution'),
 'OC-STEP4-RAW': ('STEP4', "'$(printf '%s' \"${u:-none}\" | redact)'", "'${u:-none}'"),
 'OC-STEP3-RAW': ('STEP3', "'$(printf '%s' \"${u:-none}\" | redact)'", "'${u:-none}'"),
 'STEP2-INIT-RAW': ('STEP2', 'rrun git submodule update --init -- "$c"', 'git submodule update --init -- "$c"'),
 'STEP5-INIT-RAW': ('STEP5', 'rrun git submodule update --init -- "$c"', 'git submodule update --init -- "$c"'),
 'STEP3-MIRROR-RAW': ('STEP3', 'echo "unreachable: $(printf \'%s\' "$u" | redact)"', 'echo "unreachable: $u"'),
 'STEP0-RAW': ('STEP0', " | sed -E 's#://[^[:space:]]*@#://***@#g; s#(^|[^[:alnum:]._~%+-])[[:alnum:]._~%+-]+:[^[:space:]@/][^[:space:]@]*@#\\1***@#g; s#([?&;][A-Za-z_]*([Tt][Oo][Kk][Ee][Nn]|[Kk][Ee][Yy]|[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]|[Ss][Ee][Cc][Rr][Ee][Tt])[A-Za-z_]*=)[^&;[:space:]]*#\\1***#g'", ''),
 'REDACT-WEAK': ('STEP2', "redact() { sed -E 's#://[^[:space:]]*@#://***@#g; s#(^|[^[:alnum:]._~%+-])[[:alnum:]._~%+-]+:[^[:space:]@/][^[:space:]@]*@#\\1***@#g; s#([?&;][A-Za-z_]*([Tt][Oo][Kk][Ee][Nn]|[Kk][Ee][Yy]|[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]|[Ss][Ee][Cc][Rr][Ee][Tt])[A-Za-z_]*=)[^&;[:space:]]*#\\1***#g'; }", "redact() { sed -E 's#://[^:/]*@#://***@#g'; }"),
 'STEP1-PEM': ('STEP1', " ! -name '*.pem'", ''),
 'STEP1-CRED': ('STEP1', " ! -name 'credentials*'", ''),
 'STEP10-RECURSE': ('STEP10', 'git push --recurse-submodules=no', 'git push'),
 'STEP5-NO-FILTER': ('STEP5', " | grep -E '^helixconstitution-v(0|[1-9][0-9]*)(\\.(0|[1-9][0-9]*))*$'", ''),
 'STEP3-LEXICAL': ('STEP3', '| sort -u | sort -V | tail -n 1', '| sort -u | sort | tail -n 1'),
 'STEP3-NO-VASIC': ('STEP3', ' https://github.com/vasic-digital/HelixConstitution.git}', '}'),
}
if mid in M:
    blk, old, new = M[mid]; b, e = B(blk); s = in_block(s, b, e, old, new)
elif mid == 'STEP5-LOCAL-TAGS':
    b, e = B('STEP5')
    s = in_block(s, b, e, "tag=\"$(printf '%s\\n' \"$rt\" | sed", "tag=\"$(git -C \"$c\" tag -l 'helixconstitution-v*' --sort=-v:refname | head -n1)\"; : \"$(printf '%s\\n' \"$rt\" | sed")
elif mid == 'STEP8-CONSENT':
    s = s.replace('env -u JEV_BOOTSTRAP_CONSENT ', 'env ', 1); assert 'env -u JEV_BOOTSTRAP_CONSENT' not in s
elif mid == 'FU02-CONSENT':
    s = s.replace('env -u JEV_BOOTSTRAP_CONSENT -u JEV_BOOTSTRAP_ALLOW_CLONE ', 'env -u JEV_BOOTSTRAP_ALLOW_CLONE ', 1)
elif mid == 'FU01-V3-LOCAL':
    s = s.replace("ls-remote --tags --refs origin 'helixconstitution-v*' 2> >(sed -E 's#://[^[:space:]]*@#://***@#g; s#(^|[^[:alnum:]._~%+-])[[:alnum:]._~%+-]+:[^[:space:]@/][^[:space:]@]*@#\\1***@#g; s#([?&;][A-Za-z_]*([Tt][Oo][Kk][Ee][Nn]|[Kk][Ee][Yy]|[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]|[Ss][Ee][Cc][Rr][Ee][Tt])[A-Za-z_]*=)[^&;[:space:]]*#\\1***#g' >&2) | sed 's#.*refs/tags/##' | grep -E '^helixconstitution-v(0|[1-9][0-9]*)(\\.(0|[1-9][0-9]*))*$' | sort -u | sort -V | tail -n 1",
                  "tag -l 'helixconstitution-v*' --sort=-v:refname | head -n1", 1)
elif mid == 'REMOTE-V-RAW':
    o = "git remote -v | sed -E 's#://[^[:space:]]*@#://***@#g; s#(^|[^[:alnum:]._~%+-])[[:alnum:]._~%+-]+:[^[:space:]@/][^[:space:]@]*@#\\1***@#g; s#([?&;][A-Za-z_]*([Tt][Oo][Kk][Ee][Nn]|[Kk][Ee][Yy]|[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]|[Ss][Ee][Cc][Rr][Ee][Tt])[A-Za-z_]*=)[^&;[:space:]]*#\\1***#g')"; assert o in s; s = s.replace(o, 'git remote -v)', 1)
elif mid == 'HDR-NO-VASIC':
    s = s.replace('  github-vasic   https://github.com/vasic-digital/HelixConstitution.git\n', '', 1)
elif mid == 'INLINE-FORCE':   # an inline (non-block) forbidden command in a follow-up
    s = s.replace('  V10 git status --porcelain\n', '  V10 git status --porcelain\n      git push --force origin HEAD:main\n', 1)
else: sys.exit(9)
open(dst, 'w').write(s)
sys.exit(0 if open(src).read() != s else 1)
PY
}
declare -A WHICH=(
  [V1]=L [V4]=L [V6]=L [V7]=L [OC-STEP4-RAW]=L [OC-STEP3-RAW]=L [STEP2-INIT-RAW]=L [STEP5-INIT-RAW]=L
  [STEP3-MIRROR-RAW]=L [STEP0-RAW]=L [REDACT-WEAK]=L [STEP1-PEM]=L [STEP1-CRED]=L [STEP10-RECURSE]=L
  [STEP5-NO-FILTER]=L [STEP3-LEXICAL]=L [STEP3-NO-VASIC]=L [STEP5-LOCAL-TAGS]=L [STEP8-CONSENT]=L
  [FU02-CONSENT]=F2 [FU01-V3-LOCAL]=F1 [HDR-NO-VASIC]=L [INLINE-FORCE]=F1 [REMOTE-V-RAW]=L
)
ORDER=(V1 V4 V6 V7 OC-STEP4-RAW OC-STEP3-RAW STEP2-INIT-RAW STEP5-INIT-RAW STEP3-MIRROR-RAW STEP0-RAW REDACT-WEAK
       STEP1-PEM STEP1-CRED STEP10-RECURSE STEP5-NO-FILTER STEP3-LEXICAL STEP3-NO-VASIC STEP5-LOCAL-TAGS
       STEP8-CONSENT FU02-CONSENT FU01-V3-LOCAL HDR-NO-VASIC INLINE-FORCE REMOTE-V-RAW)

prep() { # <sandbox> -> copies of every input under <sandbox>
  cp "$SRC/latest.md" "$1/latest.md"
  cp "$SRC/followups/01_verify_incorporation.md" "$1/fu01.md"
  cp "$SRC/followups/02_wire_decision_layer_optional.md" "$1/fu02.md"
  cp "$SRC/followups/03_final_report.md" "$1/fu03.md"
}
run_suite() { # <sandbox> -> suite rc; output in <sandbox>/suite.out
  R4_LATEST="$1/latest.md" R4_FU01="$1/fu01.md" R4_FU02="$1/fu02.md" R4_FU03="$1/fu03.md" \
    bash "$SUITE" >"$1/suite.out" 2>&1
}

C="$(mk_sandbox)"; prep "$C"; run_suite "$C"; rc=$?
[ "$rc" -eq 0 ] && ok "control: round 4 suite PASSES on unmutated copies ($(tail -n1 "$C/suite.out"))" \
  || { no "control: suite fails on unmutated copies: $(grep -E '^FAIL' "$C/suite.out" | head -n 5)"; summary round4_mutants; exit 1; }

for m in "${ORDER[@]}"; do
  M="$(mk_sandbox)"; prep "$M"
  case "${WHICH[$m]}" in L) f="$M/latest.md" ;; F1) f="$M/fu01.md" ;; F2) f="$M/fu02.md" ;; esac
  if ! mutate "$m" "$f" "$f.mut"; then no "mutant $m did not change its file (no-op mutation)"; continue; fi
  mv -f -- "$f.mut" "$f"
  run_suite "$M"; rc=$?
  if [ "$rc" -ne 0 ]; then
    ok "mutant $m KILLED by: $(grep -E '^FAIL' "$M/suite.out" | head -n 2 | cut -c1-140 | tr '\n' '|')"
  else
    no "mutant $m SURVIVED ($(tail -n1 "$M/suite.out"))"
  fi
done
summary round4_mutants
