#!/usr/bin/env bash
# scripts/label-sync/mcp/prove_mcp_mutations.sh
#
# Purpose : Paired-mutation proof (§1.1 / §11.4.115) for the label-sync MCP server.
#           Copies the Go module to a SCRATCH dir, applies one deliberate defect at
#           a time to mcp/label-mcp/server.go, and requires the server's own tests
#           to FAIL for each mutant. A mutant that the tests do not kill means a
#           test is hollow. Also runs an UNMUTATED control that must pass, and
#           verifies every mutant actually changed the source (an inoperative
#           mutant would be a false proof).
# Usage   : prove_mcp_mutations.sh [--keep] [--selftest]   (--keep keeps the scratch dir;
#           --selftest runs one non-compiling mutant: must report UNDETERMINED, exit 2)
# Inputs  : none. Needs `go` (stdlib only; GOPROXY=off).
# Outputs : `KILLED`/`SURVIVED`/`INOPERATIVE` per mutant and a summary.
# Exit    : 0 every mutant killed and the control green | 1 a mutant survived /
#           was inoperative / control red | 2 environment error (no go).
# Mutants : M1 alias filter ignored | M2 switch does not call the bus |
#           M3 malformed JSON silently accepted | M4 unknown method answered OK |
#           M5 notification answered | M6 session_id lookup ignored |
#           M7 EOF drops in-flight responses | M8 pid range unchecked |
#           M9 ping result omitted | M10 invalid kind filter accepted |
#           M11 pipelined dependent requests not kept in arrival order |
#           M12 explicit alias does not pin (review-2 core finding 4) |
#           M13 follow_active default flipped (adapters review N1) |
#           M14 request line not size-capped (adapters review J).
#           A mutant counts as KILLED only when it compiles (go vet) AND the
#           suite reports at least one `--- FAIL:`; a mutant that does not
#           compile, does not apply, or fails without a `--- FAIL:` line is
#           UNDETERMINED and the proof exits 2 (never a pass). --selftest proves it.
# Side-effects: temp dir only (removed unless --keep). Run niced, alone (§12.7).
# Cross-refs: §1.1, §11.4.115, §11.4.18, docs/label-sync/MCP.md.
# Classification: universal (§11.4.17).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
MOD="$(cd "$HERE/.." && pwd)"
command -v go >/dev/null || { echo "prove_mcp_mutations: go missing" >&2; exit 2; }
keep=0 selftest=0
for a in "$@"; do case "$a" in --keep) keep=1 ;; --selftest) selftest=1 ;; esac; done
S="$(mktemp -d "${TMPDIR:-/tmp}/ls_mcp_mut.XXXXXX")"; [ "$keep" = 1 ] || trap 'rm -rf "$S"' EXIT
cp -a "$MOD" "$S/mod" && rm -rf "$S/mod/.git"
SRC="$S/mod/mcp/label-mcp/server.go"
ORIG="$S/server.go.orig"; cp "$SRC" "$ORIG"
export GOPROXY=off GOFLAGS=-buildvcs=false
runtests() { (cd "$S/mod" && nice -n 10 go test -short -count=1 ./mcp/label-mcp >"$S/out.txt" 2>&1); }
rc=0 killed=0 total=0 undet=0
mutant() { # name  python-expr(old,new)
  local name="$1" old="$2" new="$3"
  total=$((total+1)); cp "$ORIG" "$SRC"
  if ! OLD="$old" NEW="$new" SRC="$SRC" python3 - <<'PY'
import os,sys
p=os.environ["SRC"]; s=open(p).read(); o=os.environ["OLD"]; n=os.environ["NEW"]
if s.count(o)<1: sys.exit(3)
open(p,"w").write(s.replace(o,n,1))
PY
  then echo "UNDETERMINED $name (pattern not found: the proof is void)"; undet=1; return; fi
  if cmp -s "$ORIG" "$SRC"; then echo "UNDETERMINED $name (source unchanged)"; undet=1; return; fi
  if (cd "$S/mod" && go vet ./mcp/label-mcp >/dev/null 2>&1) ; then :; else echo "UNDETERMINED $name (mutant does not compile — never a kill)"; undet=1; return; fi   # MUT:mcpundet
  if runtests; then echo "SURVIVED   $name"; rc=1
  elif grep -qE '^[[:space:]]*--- FAIL:' "$S/out.txt"; then echo "KILLED     $name ($(grep -m1 -E -- '--- FAIL:' "$S/out.txt" | sed 's/^[[:space:]]*//' | cut -c1-70))"; killed=$((killed+1))
  else echo "UNDETERMINED $name (suite failed without any '--- FAIL:' — proves nothing)"; undet=1; fi
}
cp "$ORIG" "$SRC"
if runtests; then echo "CONTROL    unmutated server passes"; else echo "CONTROL FAILED — unmutated tests are red"; tail -20 "$S/out.txt"; exit 1; fi
finish() {
  cp "$ORIG" "$SRC"
  echo "---"; echo "prove_mcp_mutations: $killed/$total mutants killed"
  [ "$undet" = 0 ] || { echo "prove_mcp_mutations: UNDETERMINED mutant(s) — not a pass"; exit 2; }
  [ "$rc" = 0 ] && [ "$killed" = "$total" ]; exit $?
}
if [ "$selftest" = 1 ]; then   # a non-compiling mutant must be UNDETERMINED and the proof exit 2
  mutant "S1 does not compile" 'if f < 0 || f > state.MaxPID { // MUT:mcppidrange' 'if f < 0 || f > state.MaxPID { undefinedSymbol() // MUT:mcppidrange'
  finish
fi

mutant "M1 alias filter ignored" 'if alias != "" && e.Alias != alias {' 'if alias == "" && e.Alias != alias {'
mutant "M2 switch does not call the bus" 'ev, err := st.Apply(model.Event{Type: model.EvAliasSwitch, Active: &model.Active{Alias: alias, Model: mo, Effort: ef}})
	if err != nil {
		return nil, err
	}
	return map[string]any{"alias": ev.Active.Alias, "model": mo, "effort": ef, "seq": ev.Seq}, nil' '_ = st
	return map[string]any{"alias": alias, "model": mo, "effort": ef, "seq": 0}, nil'
mutant "M3 malformed JSON silently accepted" 'return errResp(nil, errParse, "parse error: "+err.Error())
	}
	if _, isObj' 'return nil
	}
	if _, isObj'
mutant "M4 unknown method answered OK" 'return nil, &rpcError{errMethodNotFound, "method not found: " + method}' 'return map[string]any{}, nil'
mutant "M5 notification answered" 'if isNotification {
		return nil
	}
	if rerr != nil {' 'if rerr != nil {'
mutant "M6 session_id lookup ignored" 'if e.SessionID != sid {' 'if false {'
mutant "M7 EOF does not wait for in-flight responses" '	close(slots)
	<-wdone' '	close(slots)'
mutant "M8 pid range unchecked" 'if f < 0 || f > state.MaxPID { // MUT:mcppidrange' 'if false { // MUT:mcppidrange'
mutant "M9 ping result omitted" 'case "ping":
		return map[string]any{}, nil' 'case "ping":
		return nil, nil'
mutant "M10 invalid kind filter accepted" 'if kind != "" && !model.ValidKind(kind) {' 'if kind != "" && false {'
mutant "M11 pipelined requests not ordered" 's.sched(isMutating(raw))' 's.sched(false)'
mutant "M12 explicit alias does not pin" 'e.FollowActive = false // MUT:explicitpin' 'e.FollowActive = true // MUT:explicitpin'
mutant "M13 follow_active default flipped" 'e := model.Entity{ID: id, Kind: kind, FollowActive: true}' 'e := model.Entity{ID: id, Kind: kind, FollowActive: false}'
mutant "M14 request line not size-capped" 'if len(line)+len(frag) > max+1 { // +1: the newline itself // MUT:linecap' 'if false { // MUT:linecap'
finish
