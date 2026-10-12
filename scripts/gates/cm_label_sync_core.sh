#!/usr/bin/env bash
# cm_label_sync_core.sh — CM-LABEL-SYNC-CORE gate for the §11.4.182
# label + real-time sync CORE (scripts/label-sync/).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Asserts, against a constitution root, that the label-sync CORE is present,
# documented and genuinely working:
#   (1) STRUCTURAL (always; fixture-mutation-tested):
#       (a) scripts/label-sync/go.mod declares a module
#       (b) cmd/labelctl/main.go and cmd/label-busd/main.go exist
#       (c) internal/{state,bus,label,model} each carry a *.go file
#       (d) scripts/label-sync/labelctl.sh exists, executable, has a §11.4.18
#           header (Purpose:/Usage:/Exit)
#       (e) docs/label-sync/CONTRACT.md + README.md exist and CONTRACT names the
#           load-bearing tokens: events.jsonl snapshot.json active.json seq
#           follow_active alias_switch 11.4.182
#       (f) scripts/label-sync/prove_mutations.sh exists
#   (2) RUNTIME (skipped ONLY with an explicit --structural-only; when `go` is
#       absent the gate exits 2 "cannot determine" — never a PASS):
#       (g) `go test -race ./...` inside scripts/label-sync exits 0
#       (h) end-to-end smoke in a TEMP state dir: register a follower, switch
#           the alias, and the entity's label MUST show the NEW alias; a child
#           of a PINNED session (claude3) MUST keep claude3 across the switch
#           (derived binding, CONTRACT §4); an ESC/OSC-laden branch MUST print
#           with no control byte; verify MUST exit 0.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_label_sync_core.sh [--root <constitution-root>] [--structural-only] [--quiet]
# ── Inputs ───────────────────────────────────────────────────────────────────
#   CONSTITUTION_ROOT env override for --root (arg wins).
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Per-check PASS/FAIL/SKIP lines and a summary.
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Runtime checks build into a temp bin dir and use a temp LABEL_SYNC_DIR
#   (removed on exit). Never touches ~/.claude* or a real state dir.
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, grep; go for the runtime checks.
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.182, §11.4.116, §11.4.233, §11.4.18, §1.1 (paired mutation), §11.4.201.
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 all checks PASS (runtime SKIPs only with --structural-only) | 1 a check
#   FAILed | 2 cannot determine (go absent, environment error) — never a pass.
# Classification: universal (§11.4.17).
set -uo pipefail

GATE="CM-LABEL-SYNC-CORE"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
root="${CONSTITUTION_ROOT:-${SCRIPT_DIR}/../..}"
quiet=""; structural=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) root="$2"; shift 2 ;;
    --quiet) quiet=1; shift ;;
    --structural-only) structural=1; shift ;;
    -h|--help) sed -n '1,45p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "${GATE}: unknown arg '$1'" >&2; exit 2 ;;
  esac
done
[ -d "$root" ] || { echo "${GATE}: root not found: $root" >&2; exit 2; }
for tool in grep find; do # a missing instrument is "cannot determine", never a FAIL/PASS
  command -v "$tool" >/dev/null 2>&1 || { echo "⚠️  ${GATE}: CANNOT DETERMINE — required tool '$tool' absent (rc 2)"; exit 2; }
done
root="$(cd "$root" && pwd)"
ls_dir="$root/scripts/label-sync"
doc="$root/docs/label-sync"

fail=0
say()  { [ -n "$quiet" ] || echo "$@"; }
warn() { echo "$@"; }
need() { # desc, test-command...
  local d="$1"; shift
  if "$@"; then say "✅ PASS     $d"; else warn "❌ FAIL     $d"; fail=1; fi
}
has_go() { [ -n "$(find "$1" -maxdepth 1 -name '*.go' -print -quit 2>/dev/null)" ]; }

need "go.mod declares a module" grep -q '^module ' "$ls_dir/go.mod" 2>/dev/null
need "cmd/labelctl/main.go present" test -f "$ls_dir/cmd/labelctl/main.go"
need "cmd/label-busd/main.go present" test -f "$ls_dir/cmd/label-busd/main.go"
for p in state bus label model; do need "internal/$p has Go sources" has_go "$ls_dir/internal/$p"; done
need "labelctl.sh executable" test -x "$ls_dir/labelctl.sh"
need "labelctl.sh §11.4.18 header (Purpose/Usage/Exit)" bash -c "grep -q '^# Purpose' '$ls_dir/labelctl.sh' && grep -q '^# Usage' '$ls_dir/labelctl.sh' && grep -q '^# Exit' '$ls_dir/labelctl.sh'"
need "prove_mutations.sh present" test -f "$ls_dir/prove_mutations.sh"
need "docs/label-sync/README.md present" test -f "$doc/README.md"
need "docs/label-sync/CONTRACT.md present" test -f "$doc/CONTRACT.md"
for tok in events.jsonl snapshot.json active.json seq follow_active alias_switch 11.4.182; do
  need "CONTRACT.md names '$tok'" grep -qF -- "$tok" "$doc/CONTRACT.md"
done

if [ -n "$structural" ]; then
  warn "⚠️  SKIP     runtime checks (--structural-only requested — honest skip, §11.4.3)"
elif ! command -v go >/dev/null 2>&1; then
  echo "----------------------------------------------------------------------"
  [ "$fail" -ne 0 ] && { echo "❌ ${GATE}: FAIL (structural) — runtime also undeterminable: go absent"; exit 1; }
  echo "⚠️  ${GATE}: CANNOT DETERMINE — go toolchain absent, runtime checks could not run (rc 2, never a pass)"
  exit 2
else
  TMPD="$(mktemp -d "${TMPDIR:-/tmp}/cm_label_sync.XXXXXX")"
  trap 'rm -rf "$TMPD"' EXIT
  if ( cd "$ls_dir" && GOPROXY=off GOFLAGS=-buildvcs=false nice -n 10 go test -race -p 2 -count=1 ./... ) >"$TMPD/gotest.log" 2>&1; then
    say "✅ PASS     go test -race ./... (race-clean)"
  else
    warn "❌ FAIL     go test -race ./... — tail:"; tail -15 "$TMPD/gotest.log"; fail=1
  fi
  export LABEL_SYNC_DIR="$TMPD/state" LABEL_SYNC_BIN="$TMPD/bin"
  L="$ls_dir/labelctl.sh"
  if bash "$L" --build >/dev/null 2>"$TMPD/build.log" \
     && bash "$L" switch-alias --alias claude1 --model opus --effort high >/dev/null \
     && bash "$L" register --id gate-follower --kind agent --track 1 --branch gate --pid $$ >/dev/null \
     && bash "$L" switch-alias --alias claude2 --model sonnet --effort xhigh >/dev/null \
     && lbl="$(bash "$L" label gate-follower)" \
     && [ "$lbl" = "(T1/gate - claude2 - sonnet - xhigh)" ] \
     && bash "$L" register --id gate-sess --kind session --session GS --track 1 --branch gate --alias claude3 --model opus --effort high --follow-active false >/dev/null \
     && bash "$L" register --id gate-child --kind agent --parent gate-sess >/dev/null \
     && bash "$L" switch-alias --alias claude4 --model m --effort e >/dev/null \
     && clbl="$(bash "$L" label gate-child)" \
     && [ "$clbl" = "(T1/gate - claude3 - opus - high)" ] \
     && inj="$(bash "$L" register --id gate-inj --kind shell --branch "$(printf 'x\033]0;PWN\007y')" --alias a --follow-active false)" \
     && ! printf '%s' "$inj" | LC_ALL=C grep -q "$(printf '\033')" \
     && bash "$L" verify >/dev/null; then
    say "✅ PASS     e2e: switch relabelled follower -> $lbl ; pinned-session child kept -> $clbl ; injection stripped ; verify OK"
  else
    warn "❌ FAIL     e2e smoke (register/switch/label/binding/sanitise/verify) — follower: '${lbl:-<none>}' child: '${clbl:-<none>}'"; cat "$TMPD/build.log" 2>/dev/null | tail -5; fail=1
  fi
fi

echo "----------------------------------------------------------------------"
if [ "$fail" -ne 0 ]; then echo "❌ ${GATE}: FAIL"; exit 1; fi
echo "✅ ${GATE}: PASS — label-sync CORE present, documented and working"
exit 0
