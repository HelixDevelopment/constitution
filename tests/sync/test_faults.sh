#!/usr/bin/env bash
# tests/sync/test_faults.sh -- FAULT-INJECTION tests (review round 2, I-1, the whole F3 class): EVERY git call the
# engine makes in a full --apply run is made to give NO ANSWER, one call per run, and the run must be BLIND
# (exit 6), never CURRENT / APPLIED / UPDATES-AVAILABLE / ATTENTION, and must not move the repository whose call
# failed. Three kinds of "no answer":
#   sigkill  the git process is killed by a signal before it does anything (negative return code)
#   rc77     git exits with a status no call site declares (stands for 128, 129, 137, ... where undeclared)
#   garbage  git exits 0 with output of the wrong shape (only calls whose site declares a shape, want=)
# The call sites are enumerated from the engine's AST (the lister below); a site the control run never
# reaches FAILS the suite (so a new git call cannot hide from this test).
# Fixture: a root behind upstream whose new commit bumps libs/a (follow path), vendor/t third-party behind its main
# (advance-pin path, --advance-pins --advance-third-party), an ignored file in the root (ignored-file check path).
# Every run uses a fresh cp -a copy of the prepared tree, --jobs 1 (a deterministic call order).
# Real git against real bare repositories in a sandbox; no network; $HOME untouched. FAULT_MODES="sigkill rc77
# garbage" (default all) selects the kinds.
T_NAME=sync-faults
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/sync/fixture_lib.sh"
sx_sandbox
echo "== $T_NAME (sandbox $SB)"
ENGINE_PY="$(dirname "$SX_ENGINE")/sync_all_upstreams.py"
modes="${FAULT_MODES:-sigkill rc77 garbage}"

sx_std_tree
wr="$(sx_seed "$U_ROOT")"; printf 'local.cache\n' >"$wr/.gitignore"; git -C "$wr" add .gitignore
git -C "$wr" commit -q -m ignore; git -C "$wr" push -q origin main
git -C "$W" pull -q --ff-only origin main
echo "local" >"$W/local.cache"
sx_commit "$U_A" "liba moves"; sx_bump_pin "$U_ROOT" libs/a   # root behind; its new commit moves libs/a's pin
sx_commit "$U_T" "tlib moves"                                    # vendor/t behind its main (advance-pin)
BASE="$SB/base"; cp -a "$W" "$BASE"

mkdir -p "$SB/fault"
cat >"$SB/fault/git" <<EOF
#!/usr/bin/env bash
n=\$(( \$(cat "\$FAULT_CTR" 2>/dev/null || echo 0) + 1 )); echo "\$n" >"\$FAULT_CTR"
rest=(); seen=0
for a in "\$@"; do if [ "\$seen" = 1 ]; then rest+=("\$a"); elif [ "\$a" = --no-optional-locks ]; then seen=1; fi; done
printf '%s\x1f%s\x1f%s\n' "\$n" "\${2#\$FAULT_TREE}" "\${rest[*]}" >>"\$FAULT_LOG"
if [ "\$n" = "\${FAULT_AT:-0}" ]; then
  case "\${FAULT_MODE:-}" in
    sigkill) kill -9 \$\$ ;;
    rc77) echo "fatal: injected" >&2; exit 77 ;;
    garbage) echo "not-an-answer garbage"; exit 0 ;;
  esac
fi
exec "$SX_GIT" "\$@"
EOF
chmod +x "$SB/fault/git"

# state TREE REPO-PATH... -> HEAD of each repository, and for a submodule whether a new gitlink was STAGED for it in
# its parent (index != HEAD; a parent's own fast-forward changes index and HEAD together, which is not a staging)
state() { local t="$1" p par rel; shift; for p in "$@"; do
  if [ "$p" = . ]; then printf '%s;' "$(sx_head "$t")"; continue; fi
  case "$p" in libs/a/inner) par="$t/libs/a"; rel=inner ;; *) par="$t"; rel="$p" ;; esac
  "$SX_GIT" -C "$par" diff --cached --quiet -- "$rel" && printf '%s unstaged;' "$(sx_head "$t/$p")" \
    || printf '%s STAGED;' "$(sx_head "$t/$p")"; done; }
ALL=". libs/a libs/a/inner vendor/t"
under() { local r="$1" p out=""; for p in $ALL; do   # REPO and every repository below it
  if [ "$r" = . ] || [ "$p" = "$r" ] || [ "${p#"$r"/}" != "$p" ]; then out="$out $p"; fi; done; echo "$out"; }
fault_run() { # fault_run LABEL MODE AT -> F_RC, F_TREE, F_OUT, F_JSON
  local label="$1" t="$SB/t_$1"
  [ -e "$t" ] && safe_rm_rf "${t:?}"
  cp -a "$BASE" "$t"; : >"$SB/ctr"; : >"$SB/log_$1"
  F_OUT="$(FAULT_TREE="$t" FAULT_CTR="$SB/ctr" FAULT_LOG="$SB/log_$1" FAULT_MODE="$2" FAULT_AT="$3" PATH="$SB/fault:$PATH" \
    bash "$SX_ENGINE" --apply --advance-pins --advance-third-party --jobs 1 --timeout 20 --deadline 300 --root "$t" \
    --out "$SB/out/$1" --run-id "$1" 2>"$SB/out/$1.err")"; F_RC=$?
  F_TREE="$t"; F_JSON="$SB/out/$1/sync_report.json"
}
# fq EXPR: test-only, EXPR is a literal written in this file (never external input), like sx_q
fq() { python3 -I -c 'import json,sys; r=json.load(open(sys.argv[1])); P={x["path"]:x for x in r["repos"]}; print(eval(sys.argv[2]))' "$F_JSON" "$1" 2>/dev/null; }

# ── control: no fault; the run must reach every call site of the engine and integrate everything
fault_run control none 0
eq "control: APPLIED exit 0" "0" "$F_RC"
CTRL_LOG="$SB/log_control"; N="$(wc -l <"$CTRL_LOG")"
[ "$N" -ge 40 ] && ok "control: $N git calls logged" || nok "control: only $N git calls"
eq "control: root fast-forwarded" "$(sx_remote_head "$SB/remotes/HelixDevelopment/root.git")" "$(sx_head "$F_TREE")"
eq "control: libs/a followed its new pin" "$("$SX_GIT" -C "$F_TREE" ls-tree HEAD libs/a | awk '{print $3}')" "$(sx_head "$F_TREE/libs/a")"
eq "control: vendor/t advanced" "$(sx_remote_head "$SB/remotes/thirdparty/tlib.git")" "$(sx_head "$F_TREE/vendor/t")"
# the call-site lister: one line per Runner.run / g_out call of the engine, from its AST: LINE<TAB>WANT<TAB>OK<TAB>
# PREFIX (PREFIX = the constant leading words of the git argument list, "?" when there is none; WANT 1 when the
# site declares an output shape; OK the declared answer statuses). The forwarding call inside g_out() is no site.
python3 -I - "$ENGINE_PY" >"$SB/sites.tsv" <<'PY' || nok "sites: the engine's AST cannot be read"
import ast
import sys


def const_list(node, consts):
    if isinstance(node, ast.Name) and node.id in consts:
        return consts[node.id]
    if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == "fetch_args":
        return ["fetch"]
    if isinstance(node, (ast.List, ast.Tuple)):
        words = []
        for e in node.elts:
            if isinstance(e, ast.Constant) and isinstance(e.value, str):
                words.append(e.value)
            else:
                break
        return words
    return None


def main(path):
    try:
        tree = ast.parse(open(path, encoding="utf-8").read())
    except (OSError, SyntaxError) as e:
        print("sites: cannot parse %s: %s" % (path, e), file=sys.stderr)
        return 2
    consts = {}
    for n in tree.body:
        if isinstance(n, ast.Assign) and len(n.targets) == 1 and isinstance(n.targets[0], ast.Name):
            v = const_list(n.value, {})
            if v:
                consts[n.targets[0].id] = v
    parents = {}
    for p in ast.walk(tree):
        for c in ast.iter_child_nodes(p):
            parents[c] = p

    def enclosing(node):
        while node in parents:
            node = parents[node]
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                return node.name
        return None

    for n in ast.walk(tree):
        if not isinstance(n, ast.Call):
            continue
        f = n.func
        name = f.attr if isinstance(f, ast.Attribute) else f.id if isinstance(f, ast.Name) else None
        if name not in ("run", "g_out"):
            continue
        if name == "run" and not (isinstance(f, ast.Attribute)):
            continue
        idx = 1 if name == "run" else 2
        if len(n.args) <= idx:
            continue
        arg = n.args[idx]
        if enclosing(n) == "g_out" and isinstance(arg, ast.Name) and arg.id == "args":
            continue
        words = const_list(arg, consts)
        kw = {k.arg: k.value for k in n.keywords}
        ok = kw.get("ok")
        okv = ",".join(str(e.value) for e in ok.elts) if isinstance(ok, ast.Tuple) else "?"
        print("%d\t%d\t%s\t%s" % (n.lineno, 1 if "want" in kw else 0, okv, " ".join(words) if words else "?"))
    return 0


sys.exit(main(sys.argv[1]) if len(sys.argv) == 2 else 2)
PY
NS="$(wc -l <"$SB/sites.tsv")"
[ "$NS" -ge 20 ] && ok "sites: $NS git call sites enumerated from the AST" || nok "sites: only $NS sites"
python3 -I - "$SB/sites.tsv" "$CTRL_LOG" >"$SB/coverage.txt" <<'PY'
import sys
sites = [l.rstrip("\n").split("\t") for l in open(sys.argv[1]) if l.strip()]
calls = [l.rstrip("\n").split("\x1f") for l in open(sys.argv[2]) if l.strip()]
for line, want, ok, prefix in sites:
    if prefix == "?":
        print("UNRECOGNISABLE site line %s" % line); continue
    w = prefix.split()
    if not any(c[2].split()[:len(w)] == w for c in calls):
        print("UNREACHED site line %s: %s" % (line, prefix))
PY
eq "sites: every call site is reached by the control run (and recognisable)" "" "$(cat "$SB/coverage.txt")"
# which calls carry a declared shape (garbage mode) and each repository's first write (merge/checkout/add)
python3 -I - "$SB/sites.tsv" "$CTRL_LOG" >"$SB/plan.tsv" <<'PY'
import sys
sites = [l.rstrip("\n").split("\t") for l in open(sys.argv[1]) if l.strip()]
calls = [l.rstrip("\n").split("\x1f") for l in open(sys.argv[2]) if l.strip()]
first_write = {}
for n, repo, args in calls:
    if args.split()[:1] in (["merge"], ["checkout"], ["add"]):
        first_write.setdefault(repo, int(n))
glob_write = min(first_write.values()) if first_write else 10 ** 9
for n, repo, args in calls:
    a = args.split()
    best = max((s for s in sites if a[:len(s[3].split())] == s[3].split()), key=lambda s: len(s[3].split()), default=None)
    want = best[1] if best else "0"
    print("%s\t%s\t%s\t%d\t%d\t%s" % (n, repo or ".", want, first_write.get(repo, 10 ** 9), glob_write, args))
PY

# ── one fault per call, per mode. Property: exit 6 (BLIND), the repository whose call gave no answer is "blind",
#    and when the fault came before that repository's own first write, neither it nor any repository below it moved
#    (other repositories may still be integrated: a no-answer blocks only what it is about)
fails=0; runs=0
while IFS=$'\t' read -r n repo want fw gw args; do
  for m in $modes; do
    [ "$m" = garbage ] && [ "$want" != 1 ] && continue
    runs=$((runs+1)); lab="f${n}_$m"
    fault_run "$lab" "$m" "$n"
    rpath="${repo#/}"; [ -z "$rpath" ] && rpath="."
    bad=""
    [ "$F_RC" = 6 ] || bad="$bad exit=$F_RC"
    case "$F_OUT" in *"RESULT: BLIND exit=6"*) ;; *) bad="$bad no-BLIND-line" ;; esac
    if [ -f "$F_JSON" ]; then
      res="$(fq "P.get(\"$rpath\",{}).get(\"result\")")"
      [ "$res" = blind ] || bad="$bad result($rpath)=$res"
    elif [ "$n" -gt 2 ]; then bad="$bad no-report"   # only the two pre-lock calls end before a report exists
    fi
    if [ "$n" -le "$fw" ]; then   # the fault came before (or at) this repository's first write
      # shellcheck disable=SC2046
      [ "$(state "$F_TREE" $(under "$rpath"))" = "$(state "$BASE" $(under "$rpath"))" ] || bad="$bad faulted-repo-or-below-moved"
    fi
    if [ -n "$bad" ]; then fails=$((fails+1)); nok "fault $m at call $n ($rpath: $args):$bad"; fi
    [ -e "$F_TREE" ] && safe_rm_rf "${F_TREE:?}"
  done
done <"$SB/plan.tsv"
[ "$runs" -ge 60 ] && ok "faults: $runs fault runs over $N calls ($modes)" || nok "faults: only $runs fault runs"
eq "faults: every no-answer made the run BLIND and moved nothing it should not" 0 "$fails"

# ── control needle for the instrument: the shim really injects (a fault on call 1 is seen by the engine)
fault_run needle rc77 1
eq "needle: an injected first-call failure is BLIND" 6 "$F_RC"
has "needle: the engine names the call" "no answer" "$(cat "$SB/out/needle.err")"
finish
