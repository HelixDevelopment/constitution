#!/usr/bin/env bash
# test_guard_destructive_paths.sh — tests for guard-destructive-paths.py (§11.4.287)
# Conventions (as test_guard_forbidden_commands.sh): golden-TRUE (must BLOCK),
# golden-FALSE-CARRIER (mentions a trigger but must ALLOW), escape-hatch cases,
# and an exact replay of the 2026-10-23 incident script. Trigger tokens are
# assembled from fragments so this file's own command line cannot trip a hook.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="${GUARD:-$HERE/guard-destructive-paths.py}"
PASS=0; FAIL=0

RM="r""m"; RF="-r""f"; RR="-r"; HM="/ho""me"; HV='$HO''ME'

mkjson() { # tool, field, text
  python3 -I -c 'import json,sys; t,f,x=sys.argv[1:4]; print(json.dumps({"tool_name":t,"tool_input":{f:x}}))' "$1" "$2" "$3"
}
run() { # expected_rc label tool field text
  local exp="$1" label="$2" tool="$3" field="$4" text="$5" rc
  mkjson "$tool" "$field" "$text" | python3 -I "$GUARD" >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq "$exp" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [$label] expected rc=$exp got rc=$rc"; fi
}
B() { run "$1" "$2" Bash command "$3"; }
W() { run "$1" "$2" Write content "$3"; }

# ---- golden-TRUE: class P (never overridable) ----
B 2 "rm root"            "$RM $RF /"
B 2 "rm root star"       "$RM $RF /*"
B 2 "rm /home"           "$RM $RF $HM"
B 2 "rm /home/"          "$RM $RF $HM/"
B 2 "rm /home/*"         "$RM $RF $HM/*"
B 2 "rm user home"       "$RM $RF $HM/someuser"
B 2 "rm HOME"            "$RM $RF \"$HV\""
B 2 "rm HOME braces"     "$RM $RF \${HOME}"
B 2 "rm tilde"           "$RM $RF ~"
B 2 "rm HOME star"       "$RM $RF $HV/*"
B 2 "rm HOME/Projects"   "$RM $RF $HV/Projects"
B 2 "rm HOME/scripts"    "$RM $RF ~/scripts"
B 2 "rm HOME/.claude-x"  "$RM $RF ~/.claude-claude4"
B 2 "rm /usr"            "$RM $RF /usr"
B 2 "rm /etc"            "$RM $RF /etc/"
B 2 "sudo rm"            "sudo $RM $RF $HM"
B 2 "long opt"           "$RM --recursive --force $HM"
B 2 "after &&"           "echo hi && $RM $RF $HM"
B 2 "after ;"            "cd /tmp; $RM $RF /"
B 2 "bash -c"            "bash -c '$RM $RF $HM'"
B 2 "sh -c dquote"       "sh -c \"$RM $RF $HV\""
B 2 "subst"              "echo \$($RM $RF $HM)"
B 2 "find delete home"   "find $HM -delete"
B 2 "find exec rm"       "find / -exec $RM {} +"
B 2 "rsync delete"       "rsync -a --delete /empty/ $HM/"
B 2 "chmod -R 000 home"  "chmod -R 000 $HM"
B 2 "chown -R root /"    "chown -R root /"
B 2 "heredoc to file"    "cat > x.sh <<'EOF'
$RM $RF $HM
EOF"
B 2 "heredoc to bash"    "bash <<EOF
$RM $RF $HM
EOF"
W 2 "write script P"     "#!/usr/bin/env bash
$RM $RF $HM"

# ---- the incident, replayed (class H; no marker => BLOCK) ----
INCIDENT='W="$2"
export HOME="$W/home"
rm -rf "$HOME"'
B 2 "incident replay (bash)"   "$INCIDENT"
W 2 "incident replay (Write)"  "#!/usr/bin/env bash
$INCIDENT"
B 2 "incident via heredoc"     "cat > /tmp/s.sh <<'EOF'
$INCIDENT
EOF"

# ---- class V: unguarded positional ----
B 2 "positional rm"   'D="$1"
rm -rf "$D/cache"'
B 2 "positional chain" 'A="$1"
B="$A/x"
rm -rf "$B"'

# ---- golden-FALSE / carriers: must ALLOW (rc 0) ----
B 0 "rm tmp child"        "$RM $RF /tmp/scratch-abc"
B 0 "rm relative build"   "$RM $RF ./build"
B 0 "rm single file"      "$RM -f /tmp/x.log"
B 0 "rm HOME file nonrec" "$RM -f $HV/.cache/x.log"
B 0 "rm HOME/.cache/foo"  "$RM $RF $HV/.cache/foo"
B 0 "rm Projects/x/node_modules" "$RM $RF $HV/Projects/x/node_modules"
B 0 "echo carrier"        "echo 'never run $RM $RF $HM'"
B 0 "grep carrier"        "grep -rn '$RM $RF $HM' docs/"
B 0 "comment carrier"     "ls # $RM $RF $HM"
B 0 "git commit msg"      "git commit -m 'forbid $RM $RF $HM'"
B 0 "heredoc to cat only" "cat <<'EOF'
$RM $RF $HM
EOF"
B 0 "guarded var"         'D="${1:?need dir}"
rm -rf "$D/cache"'
B 0 "guarded -n"          'D="$1"
[ -n "$D" ] || exit 1
rm -rf "$D/cache"'
B 0 "home from fixed"     'export HOME="/tmp/fakehome"
rm -rf /tmp/fakehome/x'
B 0 "mktemp var"          'T="$(mktemp -d)"
rm -rf "$T"'
B 0 "rsync no delete"     "rsync -a src/ dst/"
B 0 "find no delete"      "find $HM -name x"
B 0 "chmod nonrec"        "chmod 600 $HV/.ssh/id"
W 0 "write non-script"    "$RM $RF $HM"          # not a .sh and no shebang -> data
B 0 "unparsable json ok"  ""

# ---- escape hatch: H and V downgrade, P does not ----
B 0 "H allowed with marker"  "# guardrails:allow disposable sandbox HOME
$INCIDENT"
B 0 "V allowed with marker"  '# guardrails:allow arg validated upstream
D="$1"
rm -rf "$D/cache"'
B 2 "P NOT overridable"      "# guardrails:allow I really mean it
$RM $RF $HM"
B 2 "P not overridable root" "# guardrails:allow x
$RM $RF /"

# ---- unparsable payload is allowed with a warning ----
echo 'not json' | python3 -I "$GUARD" >/dev/null 2>&1
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [garbage stdin]"; fi

# ---- paired mutation: neutering the protected-target check must flip golden-TRUE ----
if [ "${SKIP_MUTATION:-0}" != 1 ]; then
  MUT="$(mktemp -d)"; trap 'rm -rf "${MUT:?}"' EXIT
  # mutcheck LABEL MUTATED_GUARD COMMAND: the sed must have changed the guard, the
  # UNMUTATED guard must block (rc 2) the same command in this run, and the mutated
  # guard must allow it (rc 0). Anything else is a failed mutation check.
  mutcheck() {
    local label="$1" mg="$2" cmd="$3" rc_ok rc_mut
    if cmp -s "$GUARD" "$mg"; then FAIL=$((FAIL+1)); echo "FAIL [$label: sed changed nothing - marker missing]"; return; fi
    mkjson Bash command "$cmd" | python3 -I "$GUARD" >/dev/null 2>&1; rc_ok=$?
    mkjson Bash command "$cmd" | python3 -I "$mg" >/dev/null 2>&1; rc_mut=$?
    if [ "$rc_ok" -eq 2 ] && [ "$rc_mut" -eq 0 ]; then PASS=$((PASS+1))
    else FAIL=$((FAIL+1)); echo "FAIL [$label: unmutated rc=$rc_ok (want 2), mutated rc=$rc_mut (want 0)]"; fi
  }
  sed 's/^def protected_reason(t):/def protected_reason(t):\n    return None/' "$GUARD" > "$MUT/g.py"
  mutcheck "protected_reason neutered" "$MUT/g.py" "$RM $RF $HM"
  sed -e 's/home_taint = TV in hv or UV in hv  # MUT-H/home_taint = False/' -e 's/if TV in s:  # MUT-V/if False:/' "$GUARD" > "$MUT/g2.py"
  mutcheck "taint layer (H+V) neutered" "$MUT/g2.py" "$INCIDENT"
  # round-7 mutations (reviewer mutants RD/RE adopted verbatim, plus the class-V unknown-target rule)
  sed 's/elif re.search(r"\[rR\]", a):/elif re.search(r"[r]", a):/' "$GUARD" > "$MUT/g3.py"
  mutcheck "rm -R (capital) ignored" "$MUT/g3.py" "$RM -R $HM"
  sed 's/elif not file_input and pipe and pipe\[0\] in ("find", "lit"):/elif not file_input and pipe and pipe[0] in ("find",):/' "$GUARD" > "$MUT/g4.py"
  # the mutant only turns class P into class V here (rc stays 2), so pin the harmless side: a
  # literal-pipe xargs over a scratch path must be allowed by the guard and blocked by the mutant
  if cmp -s "$GUARD" "$MUT/g4.py"; then FAIL=$((FAIL+1)); echo "FAIL [xargs mutation: sed changed nothing]"; else
    xc="printf '%s\\n' /tmp/r7-build | xargs $RM $RF"
    mkjson Bash command "$xc" | python3 -I "$GUARD" >/dev/null 2>&1; r1=$?
    mkjson Bash command "$xc" | python3 -I "$MUT/g4.py" >/dev/null 2>&1; r2=$?
    if [ "$r1" -eq 0 ] && [ "$r2" -eq 2 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [literal-pipe xargs ignored: unmutated rc=$r1 (want 0), mutated rc=$r2 (want 2)]"; fi
  fi
  sed 's/^R7_UNKNOWN_RECURSIVE = .*/R7_UNKNOWN_RECURSIVE = False/' "$GUARD" > "$MUT/g5.py"
  mutcheck "unknown recursive target rule off" "$MUT/g5.py" "$RM $RF \"\$NEVER_SET_TARGET\""
fi

# ---- review-round bypass suite (python, no shell payloads) ----
python3 -I "$(dirname "$0")/test_guard_bypasses.py" || FAIL=$((FAIL+1))

echo "guard-destructive-paths tests: pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
