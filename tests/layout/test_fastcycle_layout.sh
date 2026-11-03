#!/usr/bin/env bash
# tests/layout/test_fastcycle_layout.sh — the consumer-fleet tools
# (scripts/fastcycle/consumers/{_layout.py,_enumerate_impl.py,audit.py,migrate.sh})
# recognise a consumer in BOTH layouts.
#
# Unit: the Python layout list is read from scripts/lib/constitution_layout.sh;
#   INHERIT_RE matches the standard and the legacy pointer; the local classifier
#   and audit's gitlink reader see a real submodules/constitution gitlink.
# Integration/e2e: migrate.sh --apply migrates a real fixture consumer (local
#   bare upstream, real git, built by the existing fixture builder) whose
#   constitution is at submodules/constitution, and still migrates the legacy one.
#   The review-ref file is a FIXTURE (gate-logic class), exactly as in
#   scripts/fastcycle/tests/test_consumer_migrate_red.sh — never a real review.
# No network: no gh/glab call is made by this file.
# Usage: bash tests/layout/test_fastcycle_layout.sh
LT_SUITE="fastcycle_layout"
. "$(cd "$(dirname "$0")" && pwd)/lib_layout_harness.sh"

C="$LAYOUT_SRC_ROOT/scripts/fastcycle/consumers"
export PYTHONDONTWRITEBYTECODE=1

# --- unit: layout list + INHERIT_RE + local classifier ----------------------
REPO="$LT_SB/local_std"
lt_git init -q "$REPO"
printf '# x\n\n@submodules/constitution/CLAUDE.md\n' > "$REPO/CLAUDE.md"
lt_git -C "$REPO" add CLAUDE.md
lt_git -C "$REPO" update-index --add --cacheinfo "160000,$(printf '%040d' 1 | tr 0 a),submodules/constitution"
lt_git -C "$REPO" commit -q -m x
TXT="$LT_SB/local_txt"; mkdir -p "$TXT"; lt_git init -q "$TXT"
printf '# y\n\n## INHERITED FROM submodules/constitution/CLAUDE.md\n' > "$TXT/CLAUDE.md"

out="$(python3 - "$C" "$REPO" "$TXT" <<'PY' 2>&1
import sys
sys.path.insert(0, sys.argv[1])
import _layout
print("RELS", " ".join(_layout.LAYOUT_RELS))
import _enumerate_impl as e
print("RE_STD", bool(e.INHERIT_RE.search("## INHERITED FROM submodules/constitution/CLAUDE.md")))
print("RE_STDIMP", bool(e.INHERIT_RE.search("@submodules/constitution/CLAUDE.md")))
print("RE_LEG", bool(e.INHERIT_RE.search("## INHERITED FROM constitution/CLAUDE.md")))
print("RE_NEG", bool(e.INHERIT_RE.search("## INHERITED FROM elsewhere/CLAUDE.md")))
print("CLS_STD", e._classify_local(sys.argv[2]))
print("CLS_TXT", e._classify_local(sys.argv[3]))
print("GL_STD", _layout.local_gitlink(sys.argv[2])[0])
PY
)"
lt_check "python: layout list read from the shell lib (standard first)" grep -qx 'RELS submodules/constitution constitution' <<<"$out"
lt_check "INHERIT_RE: standard heading matches"  grep -qx 'RE_STD True' <<<"$out"
lt_check "INHERIT_RE: standard @import matches" grep -qx 'RE_STDIMP True' <<<"$out"
lt_check "INHERIT_RE: legacy heading still matches" grep -qx 'RE_LEG True' <<<"$out"
lt_check "INHERIT_RE: negative control (other path) does not match" grep -qx 'RE_NEG False' <<<"$out"
lt_check "enumerate: submodules/constitution gitlink -> submodule" grep -qx 'CLS_STD submodule' <<<"$out"
lt_check "enumerate: standard text pointer -> text-only-inheritance" grep -qx 'CLS_TXT text-only-inheritance' <<<"$out"
lt_check "audit/_layout: local gitlink found at submodules/constitution" grep -qx 'GL_STD submodules/constitution' <<<"$out"
grep -q '^RELS' <<<"$out" || printf '%s\n' "$out" | tail -5
lt_check "audit.py imports cleanly" python3 -c "import sys; sys.path.insert(0, '$C'); import audit"
# parity: audit.py's lone-copy fallback (used when it runs without _layout.py
# beside it) must give the same layout list and the same gitlink answer.
LONE="$LT_SB/lone"; mkdir -p "$LONE"; cp "$C/audit.py" "$LONE/audit.py"
par="$(python3 - "$LONE" "$C" "$REPO" <<'PY' 2>&1
import sys
sys.path.insert(0, sys.argv[1])
import audit
assert "_layout" not in sys.modules, "lone copy unexpectedly imported _layout"
sys.path.insert(0, sys.argv[2])
import _layout
print("PAR_RELS", tuple(audit.LAYOUT_RELS) == tuple(_layout.LAYOUT_RELS))
print("PAR_GL", audit.local_gitlink(sys.argv[3]) == _layout.local_gitlink(sys.argv[3]))
PY
)"
lt_check "audit.py lone-copy fallback: same layout list as _layout.py" grep -qx 'PAR_RELS True' <<<"$par"
lt_check "audit.py lone-copy fallback: same gitlink answer as _layout.py" grep -qx 'PAR_GL True' <<<"$par"
grep -q '^PAR_RELS' <<<"$par" || printf '%s\n' "$par" | tail -4
lib_rels="$(sed -n 's/^CONSTITUTION_LAYOUT_RELS="\(.*\)"$/\1/p' "$LAYOUT_SRC_ROOT/scripts/lib/constitution_layout.sh")"
mig_rels="$(sed -n 's/^ *CONSTITUTION_LAYOUT_RELS="\(.*\)"$/\1/p' "$C/migrate.sh")"
lt_check "migrate.sh lone-copy fallback list equals the lib list ('$mig_rels' vs '$lib_rels')" \
    eval 'test -n "$lib_rels" && test "$mig_rels" = "$lib_rels"'

# --- I4: GitLab tree probe is PAGINATED (no false "absent" on page 2+) ----
# Test double (gate-logic class, §11.4.289): glab_json is replaced by an
# in-process fake serving a paginated tree; no network, no real glab.
gl="$(python3 - "$C" <<'PYGL' 2>&1
import sys, urllib.parse
sys.path.insert(0, sys.argv[1])
import _enumerate_impl as e
GITLINK = {"name": "constitution", "type": "commit", "mode": "160000"}
def make(scenario):
    def fake(args, timeout=None):
        path, _, q = args[1].partition("?")
        qs = dict(urllib.parse.parse_qsl(q))
        page = int(qs.get("page", "1")); per = int(qs.get("per_page", "20"))
        if path.startswith("groups/"):
            return ([{"id": 7, "path_with_namespace": "g/p"}] if page == 1 else []), "ok"
        if scenario == "error":
            return None, "error"
        tp = qs.get("path", "")
        filler = [{"name": "f%03d" % i, "type": "blob", "mode": "100644"} for i in range(150)]
        entries = None
        if tp == "":
            entries = filler + ([GITLINK] if scenario == "legacy_page2" else [])
        elif tp == "submodules" and scenario == "std_page2":
            entries = filler + [GITLINK]
        elif tp == "submodules" and scenario == "other_gitlink":
            entries = filler + [{"name": "not-constitution", "type": "commit", "mode": "160000"}]
        if entries is None:
            return None, "http_404"
        return entries[(page - 1) * per: page * per], "ok"
    return fake
for sc in ("std_page2", "legacy_page2", "other_gitlink", "absent", "error"):
    e.glab_json = make(sc)
    hits, reach, deg = e.source2_gitlab(["g"])
    print("GL", sc, "hit=%s" % bool(hits.get("g/p")), "degraded=%d" % len(deg))
PYGL
)"
lt_check "gitlab: standard gitlink on tree page 2 -> found"   grep -qx 'GL std_page2 hit=True degraded=0' <<<"$gl"
lt_check "gitlab: legacy gitlink on root page 2 -> found"     grep -qx 'GL legacy_page2 hit=True degraded=0' <<<"$gl"
lt_check "gitlab: another gitlink under submodules/ is NOT a hit" grep -qx 'GL other_gitlink hit=False degraded=0' <<<"$gl"
lt_check "gitlab: genuinely absent -> no hit, no degraded"   grep -qx 'GL absent hit=False degraded=0' <<<"$gl"
lt_check "gitlab: probe error -> degraded, never a silent absent" grep -q '^GL error hit=False degraded=[1-9]' <<<"$gl"
grep -q '^GL std_page2' <<<"$gl" || printf '%s\n' "$gl" | tail -5

# --- e2e: migrate.sh on real fixture consumers, both layouts ---------------
FIX="$LT_SB/fx"
if ! sh "$LAYOUT_SRC_ROOT/scripts/fastcycle/tests/fixtures/consumer_migrate/build_fixtures.sh" "$FIX" >"$LT_SB/build.log" 2>&1; then
    lt_bad "fixture builder"; cat "$LT_SB/build.log"; lt_summary; exit 1
fi
OLD_SHA="$(python3 -c "import json;print(json.load(open('$FIX/manifest.json'))['old_sha'])")"
NEW_SHA="$(python3 -c "import json;print(json.load(open('$FIX/manifest.json'))['new_sha'])")"
MINI="$(python3 -c "import json;print(json.load(open('$FIX/manifest.json'))['mini_constitution'])")"
GOOD="$FIX/ca_good_migrate/checkout"

# A second good consumer in the STANDARD layout (same history, moved gitlink).
STD_BARE="$LT_SB/std_remote.git"; lt_git clone -q --bare "$FIX/ca_good_migrate/remote.git" "$STD_BARE"
STD="$LT_SB/std_checkout"; lt_git clone -q "$STD_BARE" "$STD"
lt_git -C "$STD" update-index --force-remove constitution
printf '[submodule "constitution"]\n\tpath = submodules/constitution\n\turl = %s\n' "$MINI" > "$STD/.gitmodules"
sed -i 's|INHERITED FROM constitution/CLAUDE.md|INHERITED FROM submodules/constitution/CLAUDE.md|' "$STD/CLAUDE.md"
lt_git -C "$STD" update-index --add --cacheinfo "160000,$OLD_SHA,submodules/constitution"
lt_git -C "$STD" add .gitmodules CLAUDE.md
lt_git -C "$STD" commit -q -m "move constitution to submodules/constitution"
lt_git -C "$STD" push -q origin HEAD:main
# a FRESH clone, exactly as a consumer would have it (uninitialised submodule dir)
STD="$LT_SB/std_fresh"; lt_git clone -q "$STD_BARE" "$STD"

review_ref() { # project target base -> file
    local out="$LT_SB/review_$(printf '%s' "$1" | tr / _).json"
    python3 - "$out" "$1" "$2" "$3" <<'PY'
import json, sys
out, project, target, base = sys.argv[1:5]
json.dump({"schema": "review-verdict-fixture/v1", "verdict": "GO", "project_id": project,
           "target_commit": target, "consumer_base_commit": base, "findings": [],
           "model_tier": "opus", "effort": "xhigh",
           "note": "layout-test fixture only -- not a real review record"}, open(out, "w"))
PY
    printf '%s\n' "$out"
}
CFG="$LT_SB/fastcycle.yaml"; printf 'schema: dummy\n' > "$CFG"

for pair in "submodules/constitution:$STD" "constitution:$GOOD"; do
    rel="${pair%%:*}"; wd="${pair#*:}"
    proj="fixture/layout_$(printf '%s' "$rel" | tr / _)"
    rr="$(review_ref "$proj" "$NEW_SHA" "$(git -C "$wd" rev-parse HEAD)")"
    out="$( cd "$LT_SB" && env -u GIT_CONFIG_GLOBAL sh "$C/migrate.sh" --config "$CFG" --project "$proj" \
            --workdir "$wd" --out "$LT_SB/mig_$(printf '%s' "$rel" | tr / _).json" --apply --review-ref "$rr" 2>&1 )"; rc=$?
    lt_check "[$rel] migrate.sh --apply -> MIGRATED (rc=$rc)" \
        eval 'test "$rc" -eq 0 && grep -q "MIGRATED" <<<"$out" && ! grep -q "NOT-MIGRATED" <<<"$out"'
    [ "$rc" -eq 0 ] || printf '%s\n' "$out" | tail -4
    got="$(git -C "$wd" ls-tree HEAD -- "$rel" | awk '{print $3}')"
    lt_check "[$rel] consumer gitlink at $rel bumped to the target" test "$got" = "$NEW_SHA"
    lt_check "[$rel] no stray gitlink created at the other layout path" \
        test -z "$(git -C "$wd" ls-tree HEAD -- "$( [ "$rel" = constitution ] && echo submodules/constitution || echo constitution )")"
done

lt_summary
