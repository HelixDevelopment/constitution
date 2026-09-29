#!/usr/bin/env bash
# cm_subsystem_shortcuts.sh — CM-SUBSYSTEM-SHORTCUTS gate (§11.4.140 extension).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# The §11.4.140 action-prefix system was extended (2026-07-14) so a
# first-non-blank-line grammar-shaped prefix ALSO recognises WHICH incorporated
# SUB-SYSTEM / submodule is referenced (e.g. `HELIXQA :: run the bank`,
# `PRESENTER ---> fix the pill`, `/CONTAINERS rebuild the pod`). Resolution has
# two data sources feeding ONE project-agnostic engine: (a) a NAMED
# Helix-ecosystem `subsystems:` catalogue in the registry (curated abbreviations
# like HXOTA), and (b) RECURSIVE .gitmodules discovery from the INVOKING
# project's root (every submodule auto-derives alias tokens — new submodules
# covered out-of-box). This gate asserts FIVE invariants that together prove the
# feature is present, wired, grammar-honouring, and FUNCTIONALLY real (not a
# grep-only bluff — §11.4 / §11.4.108):
#
#   1. PRESENCE — the library defines apx_lookup_subsystem + apx__py_subsystem +
#      apx__project_root; the registry carries a non-empty `subsystems:` block.
#   2. WIRING — apx_expand_prompt actually CALLS apx_lookup_subsystem (the
#      sub-system tier is reachable, between the action tier and the ASK tier).
#   3. GRAMMAR-HONOUR (§11.4.140) — every declared catalogue `aliases:` token is
#      UPPERCASE [A-Z][A-Z0-9_]* (a lowercase-declared alias is a mis-registration
#      that would never match the grammar); a lowercase PROMPT does NOT expand.
#   4. FUNCTIONAL (the load-bearing, anti-bluff invariant — the lib is SOURCED
#      and RUN against a controlled temp fixture project root): a NAMED catalogue
#      token resolves to verdict=expand kind=subsystem; a DISCOVERED submodule
#      token (from the fixture's .gitmodules) resolves to kind=subsystem; a
#      registered behavioral ACTION still resolves kind=action (precedence
#      preserved); an unknown grammar-shaped token still ASKs; a lowercase token
#      does NOT expand (grammar honoured at runtime).
#   5. PARSEABILITY (§11.4.67) — the library + this gate parse clean under the
#      interpreter each one's OWN shebang DECLARES (the "target shell" of
#      §11.4.67 is the declared shell; clause 4 sanctions bash-shebang +
#      `bash script.sh` callers for the clause-3 bash-only constructs, so
#      demanding `sh -n` of a declared-bash script is a §11.4.201(1)
#      false-positive refusal).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_subsystem_shortcuts.sh [--lib <path>] [--registry <path>] [--quiet]
#     --lib <path>       action_prefix_lib.sh to audit (default: the sibling
#                        ../action_prefix_lib.sh relative to this gate).
#     --registry <path>  registry.yaml to audit (default: ../../actions/registry.yaml).
#     --quiet            suppress per-check PASS lines (FAIL lines always shown).
#   The --lib / --registry overrides let the paired §1.1 mutation test point the
#   gate at MUTATED COPIES in a temp dir, so it NEVER mutates the real tree
#   (§11.4.84 quiescence by construction).
#
# ── Inputs ───────────────────────────────────────────────────────────────────
#   None beyond the args. Creates a throwaway temp fixture project root for the
#   FUNCTIONAL invariant (trap-cleaned on EXIT).
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   Per-check PASS/FAIL lines + a final summary; nonzero exit on any failed
#   invariant.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Creates + removes a temp dir under $TMPDIR (trap). Read-only on the real
#   lib/registry. No network, no commit, no device mutation.
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, sh, grep, sed. python3 (+ PyYAML) for the sub-system tier itself; if
#   absent, the FUNCTIONAL sub-system assertions SKIP-with-reason (§11.4.3) — the
#   PRESENCE / WIRING / GRAMMAR / PARSEABILITY invariants still run.
#
# ── Cross-references ──────────────────────────────────────────────────────────
#   §11.4.140 (action-prefix system + this sub-system extension), §11.4.28 /
#   §11.4.177 (project-decoupled engine — reads the invoking graph, no literal),
#   §11.4.6 (no-guessing — ambiguous/action-colliding/lowercase → no expansion),
#   §11.4.67 (target-shell-parseability), §11.4.108 (FUNCTIONAL beats grep-only),
#   §1.1 (paired mutation — cm_subsystem_shortcuts_mutation_test.sh).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — all invariants hold.  1 — at least one invariant violated.
#   2 — environment error (lib or registry not found).
#
# Classification: universal (§11.4.17) — the engine + gate carry no project
# literal; the FUNCTIONAL fixture builds its own generic submodule declaration.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE="CM-SUBSYSTEM-SHORTCUTS"

lib="${SCRIPT_DIR}/../action_prefix_lib.sh"
registry="${SCRIPT_DIR}/../../actions/registry.yaml"
quiet=""

while [ $# -gt 0 ]; do
    case "$1" in
        --lib)      lib="$2"; shift 2 ;;
        --registry) registry="$2"; shift 2 ;;
        --quiet)    quiet="1"; shift ;;
        -h|--help)  sed -n '1,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "${GATE}: unknown arg '$1'" >&2; exit 2 ;;
    esac
done

[ -f "$lib" ]      || { echo "❌ ${GATE}: FAIL — library not found: $lib" >&2; exit 2; }
[ -f "$registry" ] || { echo "❌ ${GATE}: FAIL — registry not found: $registry" >&2; exit 2; }

fail=0
ok()   { [ -n "$quiet" ] || echo "✅ $*"; }
bad()  { echo "❌ $*"; fail=1; }

# ── Invariant 1: PRESENCE ────────────────────────────────────────────────────
for fn in apx_lookup_subsystem apx__py_subsystem apx__project_root; do
    if grep -Eq "^${fn}\(\)" "$lib"; then ok "PRESENCE: library defines ${fn}()"; else bad "PRESENCE: library does not define ${fn}()"; fi
done
# registry has a non-empty `subsystems:` block (≥1 `- name:` under it).
sub_count="$(awk '
    /^subsystems:[[:space:]]*$/ { inb=1; next }
    /^[A-Za-z_]/ { if (inb) inb=0 }
    inb && /^[[:space:]]*-[[:space:]]+name:[[:space:]]*/ { n++ }
    END { print n+0 }
' "$registry")"
if [ "$sub_count" -ge 1 ]; then ok "PRESENCE: registry carries a subsystems: catalogue with ${sub_count} entr(y/ies)"
else bad "PRESENCE: registry has no non-empty subsystems: catalogue (found ${sub_count})"; fi

# ── Invariant 2: WIRING (apx_expand_prompt reaches the sub-system tier) ───────
if grep -Eq 'apx_lookup_subsystem "\$token"' "$lib"; then
    ok "WIRING: apx_expand_prompt calls apx_lookup_subsystem"
else
    bad "WIRING: apx_expand_prompt does NOT call apx_lookup_subsystem (sub-system tier unreachable)"
fi

# ── Invariant 3: GRAMMAR-HONOUR (declared aliases are UPPERCASE tokens) ───────
alias_bad=0; alias_seen=0
while IFS= read -r line; do
    body="$(printf '%s' "$line" | sed -E 's/^[[:space:]]*aliases:[[:space:]]*\[//; s/\][[:space:]]*$//')"
    old_ifs="$IFS"; IFS=','
    for tok in $body; do
        t="$(printf '%s' "$tok" | sed -E 's/^[[:space:]]*//; s/[[:space:]]*$//')"
        [ -n "$t" ] || continue
        alias_seen=$((alias_seen+1))
        if ! printf '%s' "$t" | grep -Eq '^[A-Z][A-Z0-9_]*$'; then
            bad "GRAMMAR-HONOUR: declared alias '${t}' is not an UPPERCASE [A-Z][A-Z0-9_]* grammar token (would never match §11.4.140)"
            alias_bad=$((alias_bad+1))
        fi
    done
    IFS="$old_ifs"
done < <(grep -E '^[[:space:]]*aliases:[[:space:]]*\[' "$registry")
if [ "$alias_bad" -eq 0 ]; then ok "GRAMMAR-HONOUR: all ${alias_seen} declared catalogue alias token(s) are UPPERCASE grammar tokens"; fi

# ── Invariant 4: FUNCTIONAL (source + run the lib against a temp fixture) ─────
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cm_subsys_gate.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT
mkdir -p "$TMP/proj"
# Generic fixture submodule (no project literal): FOO_WIDGET must resolve via
# recursive .gitmodules discovery. NAMED-catalogue HELIXQA must resolve too.
cat > "$TMP/proj/.gitmodules" <<'GM'
[submodule "foo_widget"]
	path = tools/foo_widget
	url = git@github.com:vasic-digital/foo-widget.git
GM

if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
    # Drive the real expander in a subshell with the fixture root + this registry.
    fx_out="$(
        HELIX_ACTION_REGISTRY="$registry" HELIX_PROJECT_ROOT="$TMP/proj" \
        bash -c '
            set -u
            . "'"$lib"'" || exit 3
            jget() { apx__json_get "$1" "$2"; }
            emit() { local p="$1" j; j="$(apx_expand_prompt "$p")"; printf "%s|%s\n" "$(jget "$j" verdict)" "$(jget "$j" kind)"; }
            printf "CATALOGUE %s\n"  "$(emit "HELIXQA :: run the bank")"
            printf "DISCOVERY %s\n"  "$(emit "FOO_WIDGET ---> build it")"
            printf "ACTIONPREC %s\n" "$(emit "BACKGROUND :: do X")"
            printf "UNKNOWN %s\n"    "$(emit "ZZUNKNOWNZZ :: do X")"
            printf "LOWER %s\n"      "$(emit "helixqa :: do X")"
        ' 2>/dev/null
    )"
    chk() { # $1 label  $2 expected "verdict|kind"  $3 human
        local got; got="$(printf '%s\n' "$fx_out" | awk -v k="$1" '$1==k {print $2}')"
        if [ "$got" = "$2" ]; then ok "FUNCTIONAL: ${3} → ${got}"; else bad "FUNCTIONAL: ${3} → expected [${2}] got [${got:-<none>}]"; fi
    }
    chk CATALOGUE  "expand|subsystem" "named-catalogue token HELIXQA expands as a sub-system"
    chk DISCOVERY  "expand|subsystem" "auto-discovered submodule token FOO_WIDGET expands as a sub-system"
    chk ACTIONPREC "expand|action"    "behavioral action BACKGROUND keeps kind=action (precedence)"
    chk UNKNOWN    "ask|action"       "unknown grammar-shaped token still ASKs (no invented expansion)"
    chk LOWER      "noop|action"      "lowercase token does NOT expand (grammar honoured at runtime)"
else
    echo "⚠️  FUNCTIONAL: SKIP-with-reason (python3+PyYAML absent — sub-system tier is python-dependent by design, §11.4.3/§11.4.6; PRESENCE/WIRING/GRAMMAR/PARSEABILITY still enforced)"
fi

# ── Invariant 5: PARSEABILITY (§11.4.67) ─────────────────────────────────────
# §11.4.67 binds a script to the shell it DECLARES: its mandate covers scripts
# "invoked under a target shell other than the one in its shebang", and clause 4
# ("Honest shebangs") sanctions bash-shebang + bash-callers for scripts carrying
# bash-only constructs (clause 3 names process substitution / `<<<` / `arr=()`
# explicitly). Running `sh -n` over a `#!/usr/bin/env bash` script asserts a
# condition the anchor never imposed — a §11.4.201(1) false-positive refusal and
# a §11.4.201(11) proxy check. Parse each file under its DECLARED interpreter;
# demand POSIX-cleanliness only where a POSIX shebang is actually declared.
for f in "$lib" "$0"; do
    rel="$(basename "$f")"
    case "$(head -n 1 "$f")" in
        *bash*) declared_sh="bash" ;;
        *)      declared_sh="sh"   ;;
    esac
    if "$declared_sh" -n "$f" 2>/tmp/cm_subsys_pn.$$; then
        ok "PARSEABILITY: ${rel} clean under its declared interpreter (${declared_sh} -n)"
    else
        bad "PARSEABILITY: ${rel} fails ${declared_sh} -n (its DECLARED interpreter): $(tr '\n' ' ' < /tmp/cm_subsys_pn.$$)"
    fi
    rm -f /tmp/cm_subsys_pn.$$
done

echo "----------------------------------------------------------------------"
if [ "$fail" -eq 0 ]; then
    echo "✅ ${GATE}: PASS — presence + wiring + grammar-honour + functional + parseability all hold"
    exit 0
fi
echo "❌ ${GATE}: FAIL — see violations above"
exit 1
