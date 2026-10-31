#!/usr/bin/env bash
# test_detection.sh — DETECTION tests on THIS host: the installer's agent detection (--detect-agents --json)
# is compared with an independent oracle: real `command -v` and real `<agent> --version` run here; for the
# Claude Toolkit natives, `claude-list-accounts` run here. No LLM call is made (only --version / list commands).
# Also LAYOUT detection: standard (submodules/constitution), legacy (./constitution), both, none.
# Usage: bash tests/install/test_detection.sh   Exit 0 all pass · 1 a case failed · 2 env error.
T_NAME=detection
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
new_sandbox

echo "# agents (real host detection vs independent oracle)"
json="$(bash "$INSTALLER" --detect-agents --json 2>/dev/null)"; rc=$?
eq "--detect-agents exit 0" 0 "$rc"
check "--detect-agents output is JSON" python3 -I -c 'import json,sys; json.loads(sys.stdin.read())' <<<"$json"
field() { python3 -I -c 'import json,sys; a={x["id"]:x for x in json.loads(sys.argv[1])}; v=a.get(sys.argv[2],{}).get(sys.argv[3],""); print(str(v).lower() if isinstance(v,bool) else v)' "$json" "$1" "$2"; }
for a in claude kimi opencode pi aider codex gemini qwen cursor-agent amp goose; do
  if command -v "$a" >/dev/null 2>&1; then want=true; else want=false; fi
  eq "$a installed flag matches command -v" "$want" "$(field "$a" installed)"
  if [ "$want" = true ]; then
    eq "$a path matches command -v" "$(command -v "$a")" "$(field "$a" path)"
    real="$(timeout 10 "$a" --version 2>&1 | head -1)"; got="$(field "$a" version)"
    check "$a version [$got] is a substring of the real --version output" eval '[ -n "$got" ] && [[ "$real" == *"$got"* ]]'
  fi
  case "$a" in claude|kimi|opencode|pi) t=drivable ;; *) t=detect-only ;; esac
  eq "$a tier" "$t" "$(field "$a" tier)"
done
if command -v claude-list-accounts >/dev/null 2>&1; then
  oracle="$(timeout 20 claude-list-accounts 2>/dev/null | awk '{print $1}' | grep -E '^claude[0-9]+$' | sort -u | tr '\n' ' ')"
  got="$(python3 -I -c 'import json,sys; print(" ".join(sorted(x["id"] for x in json.loads(sys.argv[1]) if x.get("kind")=="native-alias"))+" ")' "$json")"
  eq "native aliases match claude-list-accounts" "$oracle" "$got"
else
  echo "  SKIP native aliases: claude-list-accounts not installed (reason: topology_unsupported)"
fi
check "detection made no file in the sandbox cwd" eval '[ -z "$(cd "$SB" && bash "$INSTALLER" --detect-agents --json >/dev/null 2>&1; ls -A "$SB" | grep -v gitconfig)" ]'

echo "# layout detection"
mkdir -p "$SB/up"; make_upstream "$SB/up" || exit 2; UP="$SB/up/upstream.git"
lay() { bash "$INSTALLER" --detect-layout --project-root "$1" 2>/dev/null; }
N="$SB/none"; new_project "$N"; eq "no constitution -> none" none "$(lay "$N")"
S="$SB/std"; new_project "$S"; git -C "$S" -c protocol.file.allow=always submodule add -q "$UP" submodules/constitution >/dev/null 2>&1
eq "submodules/constitution -> standard" standard "$(lay "$S")"
L="$SB/leg"; new_project "$L"; git -C "$L" -c protocol.file.allow=always submodule add -q "$UP" constitution >/dev/null 2>&1
eq "./constitution -> legacy" legacy "$(lay "$L")"
B="$SB/both"; new_project "$B"; git -C "$B" -c protocol.file.allow=always submodule add -q "$UP" constitution >/dev/null 2>&1
git -C "$B" -c protocol.file.allow=always submodule add -q "$UP" submodules/constitution >/dev/null 2>&1
eq "both -> both" both "$(lay "$B")"
D="$SB/dirnotsub"; new_project "$D"; mkdir -p "$D/submodules/constitution"; echo x >"$D/submodules/constitution/f"
eq "plain directory (not a registered submodule) -> partial" partial "$(lay "$D")"
finish
