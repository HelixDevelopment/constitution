#!/usr/bin/env bash
# test_e2e.sh — END-TO-END tests: the REAL installer served over a local HTTP server (python3 http.server
# bound to 127.0.0.1) and over file://, fetched with real curl and piped into bash exactly as a user would
# (`curl -fsSL URL | bash -s -- ...`), into throwaway projects, against a REAL local bare clone of this
# repository. Also: a REAL interactive run on a pseudo-terminal (util-linux `script`) answering the
# questions, the `sh` re-exec path, and the update path after the upstream advances.
# Usage: bash tests/install/test_e2e.sh   Exit 0 all pass · 1 a case failed · 2 env error.
T_NAME=e2e
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
new_sandbox
command -v curl >/dev/null && command -v script >/dev/null || { echo "curl/script missing" >&2; exit 2; }
mkdir -p "$SB/up" "$SB/www"; make_upstream "$SB/up" || exit 2
UP="$SB/up/upstream.git"
cp "$SB/up/upwork/scripts/install_constitution.sh" "$SB/www/install_constitution.sh"
(cd "$SB/www" && exec python3 -I -u -m http.server --bind 127.0.0.1 0 >"$SB/http.log" 2>&1) &
HTTP_PID=$!
port=""; for _ in $(seq 1 50); do port="$(sed -n 's/.*port \([0-9][0-9]*\).*/\1/p' "$SB/http.log" | head -1)"; [ -n "$port" ] && break; sleep 0.1; done
[ -n "$port" ] || { echo "http server did not start" >&2; exit 2; }
trap 'kill "$HTTP_PID" 2>/dev/null; cleanup_sandbox' EXIT
URL="http://127.0.0.1:$port/install_constitution.sh"
V0="$(tagsha "$SB/up" helixconstitution-v999.0)"

echo "# curl | bash over HTTP"
P="$SB/p1"; new_project "$P"
out="$(cd "$P" && curl -fsSL "$URL" | bash -s -- --non-interactive --agent none --run-setup off --upstream-url "$UP" --report-json "$SB/r.json" 2>&1)"; rc=$?
eq "curl|bash exit 0" 0 "$rc"; [ "$rc" = 0 ] || printf '%s\n' "$out" | tail -20
eq "curl|bash: gitlink = newest tag" "$V0" "$(gitlink "$P")"
check "curl|bash: CLAUDE.md inheritance" grep -qx '@submodules/constitution/CLAUDE.md' "$P/CLAUDE.md"
eq "curl|bash: report status" success "$(report_field "$SB/r.json" status)"
check "http server really served the script" grep -q 'GET /install_constitution.sh' "$SB/http.log"

echo "# update path via curl | bash after the upstream advances"
git -C "$P" commit -qm "add constitution"
advance_upstream "$SB/up" helixconstitution-v999.1 || exit 2; V1="$(tagsha "$SB/up" helixconstitution-v999.1)"
out="$(cd "$P" && curl -fsSL "$URL" | bash -s -- --non-interactive --agent none --run-setup off --upstream-url "$UP" 2>&1)"; rc=$?
eq "curl|bash update exit 0" 0 "$rc"
eq "update fast-forwarded" "$V1" "$(git -C "$P/submodules/constitution" rev-parse HEAD)"
eq "update staged gitlink" "$V1" "$(gitlink "$P")"
check "fast-forward relation" git -C "$P/submodules/constitution" merge-base --is-ancestor "$V0" "$V1"

echo "# curl file:// | bash"
P2="$SB/p2"; new_project "$P2"
out="$(cd "$P2" && curl -fsSL "file://$SB/www/install_constitution.sh" | bash -s -- --non-interactive --agent none --run-setup off --upstream-url "$UP" 2>&1)"; rc=$?
eq "file:// curl|bash exit 0" 0 "$rc"; eq "file:// gitlink" "$V1" "$(gitlink "$P2")"

echo "# sh invocation"
out="$(sh "$SB/www/install_constitution.sh" --print-snippets 2>&1)"; rc=$?
eq "sh FILE re-execs under bash: exit 0" 0 "$rc"
case "$out" in *"re-executing under bash"*"curl -fsSL"*) ok "sh FILE says so and works" ;; *) nok "sh FILE says so and works"; printf '%s\n' "$out" | head -5 ;; esac
P3="$SB/p3"; new_project "$P3"; s0="$(project_state "$P3")"
out="$(cd "$P3" && curl -fsSL "$URL" | sh -s -- --non-interactive --agent none --run-setup off --upstream-url "$UP" 2>&1)"; rc=$?
eq "curl|sh refused with exit 2" 2 "$rc"
case "$out" in *"| bash"*) ok "curl|sh tells the user to pipe into bash" ;; *) nok "curl|sh tells the user to pipe into bash" ;; esac
eq "curl|sh wrote nothing" "$s0" "$(project_state "$P3")"

echo "# interactive run on a real pseudo-terminal"
P4="$SB/p4"; new_project "$P4"; s0="$(project_state "$P4")"; f0="$(tree_fingerprint "$P4")"
# answers: agent=none, decision layer=off, edit agent docs=y, register hooks=n, run setup=n, commit=n, dry-run first=y, apply=n
printf 'none\noff\ny\nn\nn\nn\ny\nn\n' | (cd "$P4" && script -qec "curl -fsSL '$URL' | bash -s -- --upstream-url '$UP'" "$SB/tty1.log") >/dev/null 2>&1; rc=$?
eq "interactive dry-run-then-decline exit 0" 0 "$rc"; [ "$rc" = 0 ] || tail -20 "$SB/tty1.log"
check "interactive: questions were shown on the terminal" grep -q 'Which agent should run the setup prompt' "$SB/tty1.log"
check "interactive: plan shown" grep -q 'DRY RUN' "$SB/tty1.log"
eq "interactive decline: nothing written" "$s0" "$(project_state "$P4")"
# full fingerprint, .git and any backup dir included: no backup dir, no exclude edit, no config edit
eq "interactive decline: full tree incl. .git byte-identical" "$f0" "$(tree_fingerprint "$P4")"
check "interactive decline: no backup dir" test ! -e "$P4/.constitution-install-backup"
printf 'none\noff\ny\nn\nn\nn\nn\n' | (cd "$P4" && script -qec "curl -fsSL '$URL' | bash -s -- --upstream-url '$UP'" "$SB/tty2.log") >/dev/null 2>&1; rc=$?
eq "interactive apply exit 0" 0 "$rc"; [ "$rc" = 0 ] || tail -20 "$SB/tty2.log"
eq "interactive apply: gitlink" "$V1" "$(gitlink "$P4")"
check "interactive apply: CLAUDE.md written" grep -qx '@submodules/constitution/CLAUDE.md' "$P4/CLAUDE.md"

echo "# interactive limits are validated (0 and over-cap refused, re-asked; EOF -> exit 2)"
mkdir -p "$SB/fakebin"; printf '#!/bin/sh\n# FAKE claude (TEST DOUBLE): must never run in this test\ntouch "%s/claude-ran"\nexit 1\n' "$SB" >"$SB/fakebin/claude"; chmod +x "$SB/fakebin/claude"
P5="$SB/p5"; new_project "$P5"; f5="$(tree_fingerprint "$P5")"
printf '0\n86401\n' | (cd "$P5" && PATH="$SB/fakebin:$PATH" script -qec "curl -fsSL '$URL' | bash -s -- --upstream-url '$UP' --agent claude --model sonnet --effort low --max-budget-usd 1" "$SB/tty3.log") >/dev/null 2>&1; rc=$?
eq "interactive timeout 0 / 86401 then EOF -> exit 2" 2 "$rc"
eq "interactive timeout: invalid answer shown twice" 2 "$(grep -c 'invalid answer' "$SB/tty3.log")"
printf '0\n50.01\n' | (cd "$P5" && PATH="$SB/fakebin:$PATH" script -qec "curl -fsSL '$URL' | bash -s -- --upstream-url '$UP' --agent claude --model sonnet --effort low --timeout-sec 60" "$SB/tty4.log") >/dev/null 2>&1; rc=$?
eq "interactive budget 0 / 50.01 then EOF -> exit 2" 2 "$rc"
eq "interactive budget: invalid answer shown twice" 2 "$(grep -c 'invalid answer' "$SB/tty4.log")"
check "interactive limit refusals: the agent never ran" test ! -e "$SB/claude-ran"
eq "interactive limit refusals wrote nothing" "$f5" "$(tree_fingerprint "$P5")"
finish
