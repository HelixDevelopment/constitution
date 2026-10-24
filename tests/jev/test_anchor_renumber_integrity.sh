#!/usr/bin/env bash
# test_anchor_renumber_integrity.sh — Jev anchors were renumbered 277..284 -> 279..286
# because upstream already owns §11.4.277 (llmctl model validation gate) and
# §11.4.278 (HelixQA UI QA). Asserts, from the corpus itself (no hard-coded
# anchor TOTAL — that moves with every amendment):
#   1. every of §11.4.272..§11.4.286 appears exactly once, ascending, contiguous;
#   2. §11.4.277/278 keep their upstream meaning and carry NO Jev meaning;
#   3. §11.4.279..286 carry the Jev meanings in the fixed order;
#   4. no Jev artifact still attaches Jev meaning to 277/278 (stale pre-renumber text);
#   5. no duplicate `### §11.4.N` heading anywhere in the corpus;
#   6. the four carriers + anchors companion mention the new top anchor (lockstep).
# Every assertion can FAIL: a negative control proves the checker rejects a
# synthetic corpus with a duplicated / out-of-order / mis-attributed heading.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=lib_assert.sh
source "$HERE/lib_assert.sh"
CORPUS="${JEV_TEST_CORPUS:-$REPO/Constitution.md}"

# check_corpus <file> -> prints problems, one per line (empty = clean)
check_corpus() {
  local f="$1"
  awk '
    /^### §11\.4\.[0-9]+([ —]|$)/ {
      match($0, /11\.4\.[0-9]+/); id=substr($0, RSTART+5, RLENGTH-5)+0
      cnt[id]++; ln[id]=NR; head[id]=$0
    }
    END {
      prev=0
      for (n=272; n<=286; n++) {
        if (cnt[n]!=1) printf("anchor 11.4.%d appears %d times (want 1)\n", n, cnt[n]+0)
        else { if (ln[n] < prev) printf("anchor 11.4.%d out of order\n", n); prev=ln[n] }
      }
      for (n in cnt) if (cnt[n]>1) printf("duplicate heading 11.4.%d x%d\n", n, cnt[n])
      want[277]="llmctl"; want[278]="HelixQA"
      want[279]="[Dd]etection"; want[280]="[Pp]er-agent"; want[281]="[Bb]ootstrap"
      want[282]="[Mm]aximal"; want[283]="[Tt]oken-reduction"; want[284]="[Pp]re-ladder"
      want[285]="[Aa]uto-tuning"; want[286]="[Dd]ependency submodules"
      for (n=277; n<=286; n++)
        if (cnt[n]==1 && head[n] !~ want[n]) printf("anchor 11.4.%d heading lacks expected meaning /%s/\n", n, want[n])
      for (n=277; n<=278; n++)
        if (cnt[n]==1 && head[n] ~ /[Jj]ev|[Dd]ecision-(layer|model)|[Bb]ootstrap wizard/) printf("anchor 11.4.%d wrongly carries Jev meaning\n", n)
    }' "$f"
}

if [ ! -f "$CORPUS" ]; then fail "Constitution.md missing at $CORPUS"; finish; exit $?; fi
probs="$(check_corpus "$CORPUS")"
if [ -z "$probs" ]; then ok "anchors 272..286 unique+ascending, 277/278 upstream meaning, 279..286 Jev meanings"
else fail "renumber integrity violated:"; printf '%s\n' "$probs" | sed 's/^/    /'; fi

dups="$(grep -oE '^### §11\.4\.[0-9]+(\.[A-Za-z0-9]+)*' "$CORPUS" | sort | uniq -d | tr '\n' ' ')"
assert_eq "" "$dups" "no duplicate '### §11.4.N' heading in the whole corpus"

# --- negative controls: the checker must be able to say NO -------------------
mk() { # mk <name> : synthetic corpus built from the real one
  cp "$CORPUS" "$T/$1.md"
}
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mk dup;  grep -m1 '^### §11\.4\.280 ' "$CORPUS" >> "$T/dup.md"
[ -n "$(check_corpus "$T/dup.md")" ] && ok "NEG: duplicated 11.4.280 heading is detected" || fail "NEG: duplicate heading NOT detected"
mk stale; sed -i 's/^\(### §11\.4\.277 — \)/\1Jev decision-layer bootstrap wizard: /' "$T/stale.md"
check_corpus "$T/stale.md" | grep -q 'wrongly carries Jev' && ok "NEG: Jev meaning re-attached to 277 is detected" || fail "NEG: stale Jev meaning on 277 NOT detected"
mk gone;  sed -i '/^### §11\.4\.286 /d' "$T/gone.md"
check_corpus "$T/gone.md" | grep -q '11.4.286 appears 0' && ok "NEG: missing 286 is detected" || fail "NEG: missing 286 NOT detected"

# --- stale references inside Jev artifacts -----------------------------------
# A line that cites 11.4.277/278 in a Jev artifact must be about llmctl
# validation / HelixQA / the renumber itself; otherwise it is pre-renumber text.
stale=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  while IFS= read -r line; do
    case "$line" in
      *llmctl*alidat*|*HelixQA*|*renumber*|*RENUMBER*|*"277..284"*|*"277→279"*|*"277->279"*) ;;
      *) printf '    stale 277/278 reference: %s: %s\n' "${f#"$REPO"/}" "$(printf '%s' "$line" | cut -c1-140)"; stale=$((stale+1)) ;;
    esac
  done < <(grep -nE '11\.4\.27[78]' "$f" 2>/dev/null)
done < <(find "$REPO/scripts/jev" "$REPO/skills/jev-decision-layer" "$REPO/docs/jev" "$REPO/mcp/templates" \
              "$REPO/docs/jev-gate-ledger.tsv" "$REPO"/scripts/gates/cm_jev_*.sh "$REPO/scripts/gates/fixtures/jev" \
              "$REPO/tests/jev" -type f ! -name 'test_anchor_renumber_integrity.sh' 2>/dev/null)
assert_eq "0" "$stale" "no Jev artifact still cites §11.4.277/278 with Jev meaning"

# --- every carrying artifact: exactly one definition per anchor, right meaning --
# Definition markers: Constitution.md "### §11.4.N ", carriers "**§11.4.N — ",
# constitution_index.yaml "- id: 11.4.N" (title on the next lines).
MEAN_277='llmctl'; MEAN_278='HelixQA'
MEAN_279='[Dd]etection'; MEAN_280='[Pp]er-agent'; MEAN_281='[Bb]ootstrap'; MEAN_282='[Mm]aximal'
MEAN_283='[Tt]oken-reduction'; MEAN_284='[Pp]re-ladder'; MEAN_285='[Aa]uto-tuning'; MEAN_286='[Dd]ependency submodules'
JEVRE='[Jj]ev|[Dd]ecision-(layer|model)|[Bb]ootstrap wizard'
def_lines() { # def_lines <file> <n> -> definition text (header + 2 following lines for yaml)
  case "$1" in
    *Constitution.md) grep -E "^### §11\.4\.$2( |$)" "$1" ;;
    *constitution_index.yaml) awk -v id="11.4.$2" '$0=="- id: " id {f=1; print; next} f&&/^- id:/ {f=0} f&&/^  title:/ {print; f=0}' "$1" ;;
    *) grep -E "^\*\*§11\.4\.$2 " "$1" | cut -c1-260 ;;
  esac
}
check_artifact() { # check_artifact <file> -> problems on stdout
  local f="$1" n cnt txt
  for n in 277 278 279 280 281 282 283 284 285 286; do
    txt="$(def_lines "$f" "$n")"
    case "$f" in *constitution_index.yaml) cnt="$(printf '%s\n' "$txt" | grep -c '^- id:')" ;; *) cnt="$(printf '%s\n' "$txt" | grep -c .)" ;; esac
    [ "$cnt" = "1" ] || { printf '%s: anchor 11.4.%s defined %s times (want exactly 1)\n' "${f##*/}" "$n" "$cnt"; continue; }
    eval "want=\$MEAN_$n"
    printf '%s' "$txt" | grep -qE "$want" || printf '%s: anchor 11.4.%s lacks expected meaning /%s/\n' "${f##*/}" "$n" "$want"
    case "$n" in 277|278) printf '%s' "$txt" | grep -qE "$JEVRE" && printf '%s: anchor 11.4.%s wrongly carries Jev meaning\n' "${f##*/}" "$n" ;; esac
  done
}
for f in Constitution.md CLAUDE.md AGENTS.md QWEN.md GEMINI.md constitution_index.yaml; do
  if [ ! -f "$REPO/$f" ]; then fail "$f missing"; continue; fi
  pr="$(check_artifact "$REPO/$f")"
  if [ -z "$pr" ]; then ok "$f: 11.4.279..286 each defined exactly once with the Jev meaning; 277/278 keep upstream meaning"
  else fail "$f renumber problems:"; printf '%s\n' "$pr" | sed 's/^/    /'; fi
done
# negative controls on this checker
cp "$REPO/CLAUDE.md" "$T/c.md"; l="$(grep -m1 -E '^\*\*§11\.4\.283 ' "$T/c.md")"; printf '%s\n' "$l" >> "$T/c.md"
check_artifact "$T/c.md" | grep -q 'defined 2 times' && ok "NEG: duplicated carrier definition is detected" || fail "NEG: duplicate carrier definition NOT detected"
cp "$REPO/CLAUDE.md" "$T/d.md"; sed -i 's/^\(\*\*§11\.4\.278 — \)/\1Jev decision-layer bootstrap wizard: /' "$T/d.md"
check_artifact "$T/d.md" | grep -q 'wrongly carries Jev' && ok "NEG: Jev meaning on 278 in a carrier is detected" || fail "NEG: stale Jev meaning on 278 NOT detected"
mkdir -p "$T/idx"; cp "$REPO/constitution_index.yaml" "$T/idx/constitution_index.yaml"; sed -i '/^- id: 11\.4\.285$/d' "$T/idx/constitution_index.yaml"
check_artifact "$T/idx/constitution_index.yaml" | grep -q '11.4.285 defined 0' && ok "NEG: missing index entry is detected" || fail "NEG: missing index entry NOT detected"

# --- CLAUDE_ANCHORS_FULL.md holds only relocated carrier blocks: it must not
# contain any Jev anchor under a STALE number (277/278 with Jev meaning).
AF="$REPO/CLAUDE_ANCHORS_FULL.md"
if [ -f "$AF" ]; then
  stale_af="$(grep -nE '11\.4\.27[78]' "$AF" | grep -E "$JEVRE" || true)"
  assert_eq "" "$stale_af" "CLAUDE_ANCHORS_FULL.md attaches no Jev meaning to 11.4.277/278"
else fail "CLAUDE_ANCHORS_FULL.md missing"; fi
finish
