#!/usr/bin/env bash
# tests/sync/test_faults.sh -- FAULT-INJECTION tests (review round 2, I-1, the whole F3 class): EVERY git call the
# engine makes in a full --apply run is made to give NO ANSWER, one call per run, and the run must be BLIND
# (exit 6), never CURRENT / APPLIED / UPDATES-AVAILABLE / ATTENTION, and must not move the repository whose call
# failed. Three kinds of "no answer", and the REAL exit 128 (review round 3, F8):
#   sigkill  the git process is killed by a signal before it does anything (negative return code)
#   rc77     git exits with a status no call site declares (stands for 129, 137, ... where undeclared)
#   garbage  git exits 0 with output of the wrong shape (only calls whose site declares a shape, want=)
#   rc128    git exits 128 ("fatal:"), the status git really uses for most fatal errors. What it must become
#            depends on the call site; the expectation comes from the gate's hand-written call-site oracle
#            (scripts/gates/cm_sync_upstreams_ff_only.sh --print-sites), matched to each call by its longest
#            constant prefix (equally long matches must agree): "blind" (128 not declared) and "start-dir" (the
#            start-directory probe; the fixture always has a .git there) -> BLIND exit 6 as above; "failed" (merge,
#            checkout, add in the guarded writer) -> FAILED exit 1, the written repository's record "failed" (for
#            add: the submodule named by the path argument); "unreachable" (a fetch) -> ATTENTION exit 4, the
#            fetched repository "attention" with an "unreachable:" reason -- except a repository the control run
#            made follow its parent's new pin: the parent still moves, the pin cannot be followed without the
#            failed fetch, so FAILED exit 1 with the action follow-blocked:new-pin-unfetchable (the set of such
#            repositories is read from the control report). A suite whose own AST lister and the
#            oracle disagree about the (prefix, ok=, want=) multiset FAILS before any run.
# The call sites are enumerated from the engine's AST (the lister below); a site the control run never
# reaches FAILS the suite (so a new git call cannot hide from this test).
# Record check (round 4, class C): the report's "moved" field is held against the disk. In the control run the
# set of repositories the report says moved must EQUAL the set whose HEAD changed on disk; in every fault run a
# repository the report says moved must have a HEAD that changed on disk (a no-answer at the final head read may
# hide a real move, so only that direction holds there). A head that was not read before the run is never "moved".
# Fixture: a root behind upstream whose new commit bumps libs/a (follow path), vendor/t third-party behind its main
# (advance-pin path, --advance-pins --advance-third-party), an ignored file in the root (ignored-file check path).
# Every run uses a fresh cp -a copy of the prepared tree, --jobs 1 (a deterministic call order).
# Real git against real bare repositories in a sandbox; no network; $HOME untouched. FAULT_MODES="sigkill rc77
# garbage" (default all) selects the kinds.
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
T_NAME=sync-faults
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/sync/fixture_lib.sh"
sx_sandbox
echo "== $T_NAME (sandbox $SB)"
ENGINE_PY="$(dirname "$SX_ENGINE")/sync_all_upstreams.py"
modes="${FAULT_MODES:-sigkill rc77 rc128 garbage}"

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
    rc128) echo "fatal: injected exit 128" >&2; exit 128 ;;
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
# report_moved -> " p1 p2 " the repositories whose record says moved (from F_JSON; "?" when it cannot be read)
report_moved() { local s; s="$(fq '" ".join(sorted(p for p, x in P.items() if x.get("moved") is True))')" || s="?"
  [ -f "$F_JSON" ] || s="?"; echo " ${s}${s:+ }"; }
# disk_moved TREE -> " p1 p2 " the repositories of ALL whose HEAD in TREE differs from BASE (an unreadable HEAD
# on either side counts as differing: it is never evidence that nothing moved)
disk_moved() { local t="$1" p a b out=""; for p in $ALL; do
  a="$(sx_head "$BASE/$p" 2>/dev/null)" || a="?"; b="$(sx_head "$t/$p" 2>/dev/null)" || b="!"
  [ "$a" = "$b" ] || out="$out $p"; done; echo "$out "; }

# ── control: no fault; the run must reach every call site of the engine and integrate everything
fault_run control none 0
eq "control: APPLIED exit 0" "0" "$F_RC"
CTRL_LOG="$SB/log_control"; N="$(wc -l <"$CTRL_LOG")"
[ "$N" -ge 40 ] && ok "control: $N git calls logged" || nok "control: only $N git calls"
eq "control: root fast-forwarded" "$(sx_remote_head "$SB/remotes/HelixDevelopment/root.git")" "$(sx_head "$F_TREE")"
eq "control: libs/a followed its new pin" "$("$SX_GIT" -C "$F_TREE" ls-tree HEAD libs/a | awk '{print $3}')" "$(sx_head "$F_TREE/libs/a")"
eq "control: vendor/t advanced" "$(sx_remote_head "$SB/remotes/thirdparty/tlib.git")" "$(sx_head "$F_TREE/vendor/t")"
# the repositories the control run made follow a new pin of their parent (read from the control report, never assumed)
CTRL_FOLLOWED=" $(fq '" ".join(sorted(p for p, x in P.items() if x.get("followed")))') "
eq "control: the report says libs/a followed its new pin" " libs/a " "$CTRL_FOLLOWED"
# record check, control (both directions); the needle: the control run really moved repositories on disk
eq "control: root, libs/a and vendor/t moved on disk" " . libs/a vendor/t " "$(disk_moved "$F_TREE")"
eq "control: the report's moved set equals the repositories whose HEAD changed on disk" \
  "$(disk_moved "$F_TREE")" "$(report_moved)"
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
# the gate's call-site oracle: what an exit 128 must become at each site (independent of this suite's lister)
ENGINE_ROOT="$(cd "$(dirname "$ENGINE_PY")/../.." && pwd)"
bash "$SX_REPO/scripts/gates/cm_sync_upstreams_ff_only.sh" --root "$ENGINE_ROOT" --print-sites >"$SB/oracle.tsv"
eq "oracle: the gate prints its call-site table" 0 "$?"
python3 -I - "$SB/sites.tsv" "$SB/oracle.tsv" >"$SB/oracle_diff.txt" <<'PY'
import sys
mine = sorted((l.split("\t")[3].rstrip("\n"), l.split("\t")[2], l.split("\t")[1]) for l in open(sys.argv[1]) if l.strip())
theirs = sorted((l.split("\t")[1], l.split("\t")[2], "0" if l.split("\t")[3] == "-" else "1")
                for l in open(sys.argv[2]) if l.strip())
for x in sorted(set(mine) | set(theirs)):
    if mine.count(x) != theirs.count(x):
        print("prefix=%r ok=%s want=%s: engine %d, oracle %d" % (x + (mine.count(x), theirs.count(x))))
PY
eq "oracle: the engine's call sites equal the oracle's (prefix, ok=, want=) multiset" "" "$(cat "$SB/oracle_diff.txt")"
# which calls carry a declared shape (garbage mode), what an exit 128 becomes (rc128 mode) and each repository's
# first write (merge/checkout/add)
python3 -I - "$SB/sites.tsv" "$CTRL_LOG" "$SB/oracle.tsv" >"$SB/plan.tsv" <<'PY'
import sys
sites = [l.rstrip("\n").split("\t") for l in open(sys.argv[1]) if l.strip()]
calls = [l.rstrip("\n").split("\x1f") for l in open(sys.argv[2]) if l.strip()]
oracle = [l.rstrip("\n").split("\t") for l in open(sys.argv[3]) if l.strip()]
first_write = {}
for n, repo, args in calls:
    if args.split()[:1] in (["merge"], ["checkout"], ["add"]):
        first_write.setdefault(repo, int(n))
glob_write = min(first_write.values()) if first_write else 10 ** 9


def on128(a):
    """The oracle class of one call: longest matching constant prefix; equally long matches must agree
    (start-dir counts as blind: the fixture's start directory always holds a .git)."""
    hits = [o for o in oracle if o[1] != "?" and a[:len(o[1].split())] == o[1].split()]
    if not hits:
        return "UNMATCHED"
    top = max(len(o[1].split()) for o in hits)
    cls = {("blind" if o[4] == "start-dir" else o[4]) for o in hits if len(o[1].split()) == top}
    return cls.pop() if len(cls) == 1 else "AMBIGUOUS:" + "/".join(sorted(cls))


for n, repo, args in calls:
    a = args.split()
    best = max((s for s in sites if a[:len(s[3].split())] == s[3].split()), key=lambda s: len(s[3].split()), default=None)
    want = best[1] if best else "0"
    print("%s\t%s\t%s\t%d\t%d\t%s\t%s" % (n, repo or ".", want, first_write.get(repo, 10 ** 9), glob_write,
                                       on128(a), args))
PY
bad_cls="$(python3 -I -c 'import sys
for l in open(sys.argv[1]):
    f = l.rstrip("\n").split("\t")
    if f[5] == "UNMATCHED" or f[5].startswith("AMBIGUOUS"):
        print(f[0] + ": " + f[5])' "$SB/plan.tsv")"
eq "oracle: every logged call has exactly one exit-128 class" "" "$bad_cls"

# ── one fault per call, per mode. Property: exit 6 (BLIND), the repository whose call gave no answer is "blind",
#    and when the fault came before that repository's own first write, neither it nor any repository below it moved
#    (other repositories may still be integrated: a no-answer blocks only what it is about)
fails=0; runs=0
r128=0; r128_failed=0; r128_unreach=0; r128_unreach_follow=0
while IFS=$'\t' read -r n repo want fw gw cls args; do
  for m in $modes; do
    [ "$m" = garbage ] && [ "$want" != 1 ] && continue
    runs=$((runs+1)); lab="f${n}_$m"
    fault_run "$lab" "$m" "$n"
    rpath="${repo#/}"; [ -z "$rpath" ] && rpath="."
    bad=""
    expect=blind; [ "$m" = rc128 ] && expect="$cls"
    [ "$m" = rc128 ] && r128=$((r128+1))
    case "$expect" in
      failed)  # the guarded writer's merge / checkout / add exited 128: a real, answered failure
        r128_failed=$((r128_failed+1))
        target="$rpath"
        if [ "${args%% *}" = add ]; then target="${args##* }"; [ "$rpath" != . ] && target="$rpath/$target"; fi
        [ "$F_RC" = 1 ] || bad="$bad exit=$F_RC"
        case "$F_OUT" in *"RESULT: FAILED exit=1"*) ;; *) bad="$bad no-FAILED-line" ;; esac
        res="$(fq "P.get(\"$target\",{}).get(\"result\")")"
        [ "$res" = failed ] || bad="$bad result($target)=$res"
        case "$(cat "$SB/out/$lab.err")" in *"internal error"*) bad="$bad internal-error" ;; esac
        ;;
      unreachable)  # a fetch exited 128: the remote is unreachable, the repository needs attention
        r128_unreach=$((r128_unreach+1))
        rs="$(fq "len([x for x in P.get(\"$rpath\",{}).get(\"reasons\",[]) if x.startswith(\"unreachable:\")])")"
        [ "${rs:-0}" -ge 1 ] 2>/dev/null || bad="$bad no-unreachable-reason"
        res="$(fq "P.get(\"$rpath\",{}).get(\"result\")")"
        followed=0; for x in $CTRL_FOLLOWED; do [ "$x" = "$rpath" ] && followed=1; done
        if [ "$followed" = 1 ]; then
          # its parent still fast-forwards (the parent's own fetch answered) and records a pin this repository never
          # fetched: following it is impossible, an answered FAILURE named follow-blocked (exit 1 outranks exit 4)
          r128_unreach_follow=$((r128_unreach_follow+1))
          [ "$F_RC" = 1 ] || bad="$bad exit=$F_RC"
          case "$F_OUT" in *"RESULT: FAILED exit=1"*) ;; *) bad="$bad no-FAILED-line" ;; esac
          [ "$res" = failed ] || bad="$bad result($rpath)=$res"
          fb="$(fq "len([a for a in P.get(\"$rpath\",{}).get(\"actions\",[]) if a.get(\"why\") == \"follow-blocked:new-pin-unfetchable\"])")"
          [ "${fb:-0}" = 1 ] || bad="$bad no-follow-blocked-action"
        else
          [ "$F_RC" = 4 ] || bad="$bad exit=$F_RC"
          case "$F_OUT" in *"RESULT: ATTENTION exit=4"*) ;; *) bad="$bad no-ATTENTION-line" ;; esac
          [ "$res" = attention ] || bad="$bad result($rpath)=$res"
        fi
        ;;
      blind)
        [ "$F_RC" = 6 ] || bad="$bad exit=$F_RC"
        case "$F_OUT" in *"RESULT: BLIND exit=6"*) ;; *) bad="$bad no-BLIND-line" ;; esac
        if [ -f "$F_JSON" ]; then
          res="$(fq "P.get(\"$rpath\",{}).get(\"result\")")"
          [ "$res" = blind ] || bad="$bad result($rpath)=$res"
        elif [ "$n" -gt 2 ]; then bad="$bad no-report"   # only the two pre-lock calls end before a report exists
        fi
        ;;
      *) bad="$bad no-oracle-class($expect)" ;;
    esac
    if [ "$expect" = blind ] && [ "$n" -le "$fw" ]; then   # the fault came before (or at) this repository's first write
      # shellcheck disable=SC2046
      [ "$(state "$F_TREE" $(under "$rpath"))" = "$(state "$BASE" $(under "$rpath"))" ] || bad="$bad faulted-repo-or-below-moved"
    fi
    if [ -f "$F_JSON" ]; then   # record check: "moved" in the report only where the HEAD really changed on disk
      rm_set="$(report_moved)"; dm_set="$(disk_moved "$F_TREE")"
      if [ "$rm_set" = " ? " ]; then bad="$bad report-unreadable"
      else for p in $rm_set; do case "$dm_set" in *" $p "*) ;; *) bad="$bad moved-in-report-not-on-disk($p)" ;; esac; done
      fi
    fi
    if [ -n "$bad" ]; then fails=$((fails+1)); nok "fault $m at call $n ($rpath: $args):$bad"; fi
    [ -e "$F_TREE" ] && safe_rm_rf "${F_TREE:?}"
  done
done <"$SB/plan.tsv"
[ "$runs" -ge 60 ] && ok "faults: $runs fault runs over $N calls ($modes)" || nok "faults: only $runs fault runs"
case " $modes " in *" rc128 "*)
  [ "$r128" -ge 40 ] && ok "rc128: $r128 runs with a real exit 128" || nok "rc128: only $r128 runs"
  # the fixture reaches every non-blind class: a fetch, and the writer's merge / checkout / add
  [ "$r128_failed" -ge 3 ] && ok "rc128: $r128_failed runs where 128 is a writer failure" || nok "rc128: only $r128_failed writer-failure runs"
  [ "$r128_unreach" -ge 1 ] && ok "rc128: $r128_unreach runs where 128 is an unreachable remote" || nok "rc128: no unreachable run"
  # both unreachable outcomes are reached: a plain ATTENTION and a child that cannot follow its parent's new pin
  [ "$r128_unreach_follow" -ge 1 ] && [ "$r128_unreach_follow" -lt "$r128_unreach" ] \
    && ok "rc128: $r128_unreach_follow of $r128_unreach unreachable runs block a pin follow (FAILED), the rest are ATTENTION" \
    || nok "rc128: unreachable outcomes not both reached ($r128_unreach_follow of $r128_unreach block a follow)" ;;
esac
eq "faults: every no-answer made the run BLIND and moved nothing it should not" 0 "$fails"

# ── control needle for the instrument: the shim really injects (a fault on call 1 is seen by the engine)
fault_run needle rc77 1
eq "needle: an injected first-call failure is BLIND" 6 "$F_RC"
has "needle: the engine names the call" "no answer" "$(cat "$SB/out/needle.err")"
finish
