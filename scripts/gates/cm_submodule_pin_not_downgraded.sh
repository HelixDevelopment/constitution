#!/usr/bin/env bash
# cm_submodule_pin_not_downgraded.sh — CM-SUBMODULE-PIN-NOT-DOWNGRADED gate (CON-046, structural round CON-146, re-minted CON-194, then CON-280; §11.4.288(D), §11.4.233(G), §11.4.201).
#
# ── Purpose ───────────────────────────────────────────────────────────────
# A snapshot-style commit (`git add -A` / `commit -a`) records the HEAD of each submodule WORKTREE, not the pin the
# superproject last recorded. When a pin was advanced in the index without moving the checkout, such a commit silently
# moves the gitlink BACK to an ancestor (forensic FACT 2026-11-05: commit 724d818 moved containers 5ea870a -> 22b4970,
# an ancestor; repaired by 84084a2). This gate refuses a STAGED gitlink change whose new commit is a strict ancestor of
# the pin in the base commit (HEAD by default).
#
# ── Status of CON-046 (§11.4.115(G) / §11.4.292(D)) ───────────────────────
# DEFENSIVE HARDENING ONLY. The mechanism was reproduced as a HOST FIXTURE (a snapshot commit over a stale checkout);
# the tool that produced the real "Auto-commit <ms>" commits is UNIDENTIFIED (UNCONFIRMED), so this change does NOT close
# CON-046: the item stays OPEN and UNREPRODUCED for the real tool.
#
# ── What it guards (and what it does not — §11.4.6) ───────────────────────
# It compares the git INDEX with the base commit and guards commit paths that RUN git's pre-commit hook (or call this
# script). Threat model: an ACCIDENT guard (a stale checkout picked up by a snapshot commit), not a guard against a
# producer who wants to bypass it: that producer controls the environment and can skip hooks anyway.
# NOT guarded (measured on git 2.53): `git commit --no-verify`; plumbing (commit-tree, update-ref); and commits made
# without pre-commit: `git merge` (auto-commit and --ff-only), a CLEAN `cherry-pick` or `revert`, and `rebase` (clean
# AND after a conflict: `rebase --continue` runs no pre-commit). (After a conflict, `cherry-pick --continue` does run
# pre-commit.) Therefore a downgrade made on a vehicle branch can still land
# on `main` by ff-only merge (the §11.4.288(B)(3) landing path has no hook in scratch clones); run this script with
# `--base <parent>` on such a commit to judge it. Per-commit index diffs also miss a downgrade split across commits or
# combined with a path move. A `--range A..B` mode for a pre-push / landing seam is a FOLLOW-UP (not built; tracked as
# CON-147 (re-minted CON-195, then CON-281), which also lists the residuals below). The hook
# (scripts/hooks/pre-commit-submodule-pin-not-downgraded) is shipped, NOT installed anywhere (operator consent).
# --amend: git tells a pre-commit hook nothing about --amend, so the hook always uses base HEAD, that is the commit being
# amended, not its parent. Consequences: amending a waived rollback shows no gitlink change (PASS); an amend can strip or
# change the waiver row of an already waived commit unchecked; and after a WARN (diverged) move, an amend to an ancestor
# of the PARENT's pin is judged against the WARN commit, so it can land a downgrade against the real parent unwaived.
# Run the gate directly with `--base HEAD^` to judge an amend against the parent. So for an amend the rule's "the
# parent is base_sha" does not hold: the row is bound to the commit being amended (HEAD), the amended commit's parent is
# HEAD^, the WAIVED line names HEAD as "parent", and a later `--base HEAD^` re-check of that commit refuses it.
# Partial commit (`git commit -- <paths>`): git builds a temporary index from HEAD plus <paths>, so a waiver file not
# named in <paths> is not seen.
#
# ── Verdicts ──────────────────────────────────────────────────────────────
#   FAIL  staged gitlink new commit is a strict ancestor of the base pin and no valid waiver covers the transition.
#   BLIND the base, the index or a submodule cannot be read, one of the two commits is missing, or ancestry cannot be
#         decided (a shallow or incomplete submodule where neither direction is proven): never a pass (§11.4.201). The
#         message names the cause and the fix. Forward is checked first, so a bump proven forward in a shallow clone passes.
#         Submodule git calls run with `-c core.commitGraph=false`: with a commit-graph, git 2.53's reachability walk
#         reports a commit it cannot read as "not an ancestor" (rc 1, error on stderr) instead of dying (rc 128), so an
#         incomplete object store would look like a DIVERGED move (WARN, exit 0) on a true downgrade (CON-046 review
#         round 7, R7-1, measured); without the graph the same store gives rc 128 both ways, hence BLIND.
#   WARN  (exit 0, visible) diverged move: new pin neither ancestor nor descendant of the old pin in a complete history;
#         old pin's commits may be dropped from the superproject history — review by hand (reachability from upstream
#         main is the owed CM-SUBMODULE-POINTER-ON-MAIN, OWED-GATE-151).
#   PASS  no staged gitlink change, forward bump, diverged (WARN), new/deleted gitlink, or a valid waiver.
#
# ── Waiver (intentional rollbacks) — what IS and IS NOT enforced ─────────
# File `.submodule_pin_waivers`, read from the git INDEX. TAB-separated, exactly 7 fields:
#   path  old_sha  new_sha  authoriser  expiry  tracked_item  base_sha
# A row whose first field starts with `#` is a comment and never waives anything (a path that really starts with `#`
# cannot be waived); a row with any other field count never waives anything either.
# ONE RULE for the lifetime of a row: a row waives ONE transition (path, old pin, new pin; full SHAs) in ONE commit that
# has ONE parent, and that parent is base_sha (the full SHA of HEAD at the time the rollback is committed:
# `git rev-parse HEAD`). It is spent by ANY other commit (not only the first) that is reachable from a ref (`git
# rev-list --exclude=refs/stash --all`: branches, tags, remote-tracking refs, notes refs and every worktree's HEAD;
# refs/stash is excluded so that the stash's own W/I/U commits, which are no line of work, are not counted; this also
# hides every commit reachable ONLY through the stash, see Residual), has base_sha as a parent (first or
# second, so a merge with base_sha as second parent counts), and whose waiver file carries the same (path, old, new,
# base) row. This is conservative: once a later copy S exists, re-judging the first commit R with `--base HEAD^`
# refuses R too. The commit being judged is not counted: in hook mode it does not exist yet (HEAD is the base), and in
# `--base` mode HEAD is excluded only when the index IS HEAD's tree, decided by the plumbing command `git diff-index
# --cached --quiet --ignore-submodules=none HEAD` (plumbing applies no textconv driver and no external diff, and the
# flag overrides a `submodule.<name>.ignore` setting in .gitmodules, so an index that differs from HEAD only in a
# gitlink or only in bytes a textconv maps to the same text is a different index); any other index is judged as a
# new commit, so HEAD counts as a spender. When the spent check cannot tell (a candidate's tree or waiver
# blob is unreadable, a broken ref, or the superproject is shallow or its shallow state is unknown) the row is NOT
# honoured. So a row in an earlier commit, a row brought in by a merge, squash, cherry-pick or rebase, and a leftover row
# from before the last commit never count: each of those commits has a different parent, a second parent (MERGE_HEAD),
# or a parent whose waiver was already spent. A base_sha that is abbreviated, a name, or not the parent is refused.
# A spent transition cannot be waived again on the same parent while the first commit is on a ref: make the new
# rollback on top of a different parent, or remove that ref first.
# Residual (documented, not detectable by a local pre-commit check; the landing-seam `--range A..B` follow-up is the
# structural answer): a row bound to the CURRENT HEAD and never committed (an abandoned rollback) still waives the next
# commit on that HEAD; the row is visible in that commit's diff. A spender that no local ref reaches is not counted, so
# the same reviewed transition can land a SECOND time on the same parent (each WAIVED, pin back at the old value):
#   - `git reset --soft HEAD~2 && git commit -a` over [reviewed rollback, index-only forward] with the submodule
#     checkout still at the old pin: the common local-squash idiom; the forward is dropped and the old pin lands
#     (the incident shape, reported WAIVED, not FAIL). Mitigation: commit without `-a`, or run `git submodule update`
#     first. A plain `reset --soft` + redo of the rollback itself is the same mechanism and is intended;
#   - a squash from FETCH_HEAD only (the vehicle lives in another clone and never had a local ref);
#   - a vehicle whose branch was deleted before the squash commit (reflog only);
#   - a worktree that was removed while its HEAD was the spender;
#   - a spender that is reachable only from a note (refs/notes holds the note commit, not the annotated commit);
#   - `git merge --no-commit --no-ff X`, then `git merge --quit` (MERGE_HEAD gone, single-parent commit) with the
#     vehicle deleted: the MERGE_HEAD clause is bypassed by that documented git command, and only the spent check is
#     left (it refuses while X still has a ref);
#   - a spender reachable ONLY as an ancestor of refs/stash (the rollback committed, a stash made on top of it, then
#     `reset --hard HEAD~1`): `--exclude=refs/stash` drops the whole ref, ancestors included, so the redo on the
#     same parent is WAIVED (the round-4 gate refused it); `git stash branch` can bring the first commit back;
#   - a spender reachable only from a PER-WORKTREE ref of ANOTHER worktree (refs/worktree/*, refs/bisect/*; and
#     refs/rewritten/* during `rebase -r`, UNCONFIRMED): `rev-list --all` run here sees every worktree's HEAD but not
#     another worktree's per-worktree refs, so the redo is WAIVED.
# The other checks on a row:
#   - expiry is a real YYYY-MM-DD date, today <= expiry <= today + max_waiver_days (inclusive); "today" is the UTC date
#     (TZ=UTC), so the caller's TZ cannot move the decision by a day (round 11, CON-046 review r10 F2);
#   - tracked_item matches <item_prefix>-NNN (3+ ASCII digits; NOT checked to exist in the tracker);
#   - authoriser: no leading/trailing whitespace, no `<`/`>`, no character of Unicode general category C (Cc control,
#     Cf format such as U+200B, Cs surrogate, Co private use, Cn unassigned), and it is NOT the producer: under the
#     Unicode compatibility caseless form k(s) = NFKD(casefold(NFD(s))) followed by the UTS #39 confusable skeleton
#     (each character mapped to its prototype, then NFD, then k again, repeated until nothing changes; locale
#     independent, python3) it equals none of committer name, committer email, author name, author email (git var
#     GIT_COMMITTER_IDENT / GIT_AUTHOR_IDENT). The skeleton map is the vendored table
#     cm_submodule_pin_not_downgraded_confusables.tsv next to this gate (CM_PIN_CONFUSABLES overrides the path; the
#     content is sha256-pinned here, so an override cannot change it), generated from the host ICU 78.2 (Unicode
#     confusables data) by docs/qa/con046_review/r13_runs/tools/gen_confusables.py and checked against ICU's whole-
#     string skeleton (round 13, operator decision on review r12 R12-2: the strict option). Refused as a self-waive,
#     so: a compatibility spelling of the producer's name (fullwidth `ｍilos`), a confusable one (dotless `alı`,
#     Cyrillic or Greek `о`, mixed script, `mi1os`, `rnilos` for `milos`), a canonical caseless match (U+1FBC U+0342 vs
#     U+1FB7) and every character whose full casefold differs from its lowercase in a way that changes the equality
#     (163 code points, Unicode 16.0, enumerated by the paired test over the whole code space; fixtures COMPAT13,
#     FOLD13ALL, FOLD13CLS). An authoriser whose skeleton is empty (only invisible fillers such as U+3164 or
#     variation selectors: 267 non-C code points) identifies nobody and is refused as malformed. An unresolvable identity, python3 missing or failing, the table missing or not the pinned
#     one (rc 5), or a skeleton that does not settle in 8 rounds, means not waived. FALSE-REFUSAL RISK (accepted by the
#     operator): a genuinely different person whose name is a confusable of the producer's (rn/m, 1/l/I, 0/O, Cherokee
#     or Cyrillic letters that look Latin, `%` vs `o/o`) cannot authorise that producer's waiver; a different name
#     that is not a confusable (release-mgr, milo for milos, a transliteration such as `Milos Vasic` for `Милош Васић`)
#     still can (COMPAT13 negative controls);
#   - a row with a CR (CRLF line ending) is refused and says so;
#   - a waiver file (index copy or --waivers file) that holds a NUL byte waives nothing (bash would drop the byte
#     silently and git shows such a file as binary, so the reviewed text is not the read text); a same-parent commit's
#     waiver file with a NUL byte makes the row unprovable as unspent; a base config with a NUL byte disables waivers
#     (round 11, review r10 F3).
# Consumer DATA: `.submodule_pin_gate.conf`, read from the BASE commit (so it cannot be loosened in the commit that uses
# it), lines `key=value`, `#` comments. Keys: max_waiver_days (integer 1..365, default 30), item_prefix (^[A-Z][A-Z0-9]+$,
# default CON). An unknown key, a duplicate key, a bad value or an unreadable file disables ALL waivers (fail safe) and
# never blocks a non-waiver verdict, so a commit that repairs the config is not itself blocked.
# NOT ENFORCED: no authoriser ROSTER exists in this repository, so the authoriser is NOT verified to be a rostered
# non-producer human — a producer can still name a second identity. This is therefore a speed bump with an audit trail,
# NOT an §11.4.271-conformant waiver; CM-WAIVER-ROSTERED-EXPIRY-TRACKED remains owed. `--waivers FILE` replaces the index
# copy with a plain file (tests / explicit use only; the hook never uses it); the same rule applies to its rows.
#
# ── Usage ─────────────────────────────────────────────────────────────────
#   cm_submodule_pin_not_downgraded.sh [--root <repo>] [--base <rev>] [--waivers <file>] [-h]
#   --root is normalised to the repository top level (so diff.relative and a subdirectory --root cannot hide a path);
#   --base defaults to HEAD (empty tree when HEAD is unborn). A submodule checkout path that is a symlink is BLIND.
# Locale (round 13, review r12 N1): the gate exports LC_ALL=C before any check. Bash `=~` bracket ranges and `[[ < ]]`
# compare by the caller's locale: under en_US.UTF-8 `[0-9]` also matched Arabic-Indic and fullwidth digits and `[A-Z]`
# matched `É`, so a malformed item id or item prefix was honoured there and refused under C (measured, 6 locales x 3
# runs). With LC_ALL=C every range, class and compare is ASCII / byte order, and every child (python3, date, git, awk)
# runs in C; the authoriser check decodes UTF-8 itself, so it is unaffected. The paired test runs the locale cases
# under C, C.UTF-8 and a UTF-8 locale whose `[0-9]` is wider (LOC13 / HLOC13) and requires one verdict for all three.
# Exit: 0 PASS · 1 FAIL · 2 BLIND (a usage error also exits 2). Read-only (git plumbing; every git call that reads
# objects runs with GIT_NO_LAZY_FETCH=1, GIT_NO_REPLACE_OBJECTS=1 and GIT_GRAFT_FILE=/dev/null, so no network, no
# replace refs and no legacy grafts; `rev-parse --show-toplevel` and `rev-parse --local-env-vars` read no objects and
# run without them). Deps: bash 4.3+, git, awk, tr, wc, GNU date (`date -d`), python3 (waiver authoriser check only); the hook also
# needs GNU readlink (`readlink -f`). Its paired test pins GNU date (9.7) and gets the same verdicts under uutils date
# 0.8.0 (round 9, CON-146); without GNU readlink the hook prints SKIP (not guarded).
# Submodule git calls run with every variable from `git rev-parse --local-env-vars` removed except GIT_CONFIG_PARAMETERS
# and GIT_CONFIG_COUNT (what git itself does for submodules); the superproject reads keep them (needed for `commit -a`'s
# temporary index and for a linked worktree).
# Classification: universal (§11.4.17). Paired mutation test: cm_submodule_pin_not_downgraded_mutation_test.sh; its
# guard inventory (one row per guard member and site, checked by that test): cm_submodule_pin_not_downgraded_inventory.tsv.
set -uo pipefail
shopt -s lastpipe
export LC_ALL=C
GATE="CM-SUBMODULE-PIN-NOT-DOWNGRADED"
self="${BASH_SOURCE[0]:-$0}"
root="$(cd "$(dirname "$self")/../.." && pwd -P)"; waivers=""; base=""
conft="${CM_PIN_CONFUSABLES:-$(dirname "$self")/cm_submodule_pin_not_downgraded_confusables.tsv}" # sha256-pinned in IDPY
need() { [ "$1" -ge 2 ] && [ -n "$2" ] || { echo "$GATE: $3 needs a value" >&2; exit 2; }; } # <argc> <value> <flag>
while [ $# -gt 0 ]; do
  case "$1" in
    --root) need $# "${2:-}" --root; root="$(cd "$2" && pwd -P)" || exit 2; shift 2 ;;
    --base) need $# "${2:-}" --base; base="$2"; shift 2 ;;
    --waivers) need $# "${2:-}" --waivers; waivers="$2"; shift 2 ;;
    -h|--help) awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$self"; exit 0 ;;
    *) echo "$GATE: unknown argument $1" >&2; exit 2 ;;
  esac
done
blind0() { echo "$GATE: BLIND — $1"; exit 2; }
top="$(git -C "$root" rev-parse --show-toplevel 2>/dev/null)" || blind0 "$root is not inside a git work tree"
root="$(cd "$top" && pwd -P)" || blind0 "cannot enter $top"
mapfile -t lev < <(git rev-parse --local-env-vars 2>/dev/null)
[ "${#lev[@]}" -gt 0 ] || blind0 "git rev-parse --local-env-vars returned nothing"
unsets=(); for v in "${lev[@]}"; do case "$v" in GIT_CONFIG_PARAMETERS|GIT_CONFIG_COUNT) ;; *) unsets+=(-u "$v") ;; esac; done
sg() { env "${unsets[@]}" GIT_NO_LAZY_FETCH=1 GIT_NO_REPLACE_OBJECTS=1 GIT_GRAFT_FILE=/dev/null git -c core.commitGraph=false "$@"; } # submodule
pg() { GIT_NO_LAZY_FETCH=1 GIT_NO_REPLACE_OBJECTS=1 GIT_GRAFT_FILE=/dev/null git -C "$root" "$@"; }        # superproject
headc="$(pg rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null)"
if [ -z "$base" ]; then
  # unborn HEAD: the empty tree, spelled as git's built-in constant per object format (no hash-object: read-only)
  basec="$headc"; [ -n "$basec" ] || case "$(pg rev-parse --show-object-format 2>/dev/null)" in
    sha1) basec=4b825dc642cb6eb9a060e54bf8d69288fbee4904 ;;
    sha256) basec=6ef19b41225c5369f1c104d45d8d85efa9b057b53b14b4b9b939dd74decc5321 ;; *) blind0 "HEAD is unborn and the object format is unknown" ;; esac
else
  basec="$(pg rev-parse -q --verify "$base^{commit}" 2>/dev/null)" || blind0 "--base $base does not resolve to a commit"
fi
mergeh="$(pg rev-parse -q --verify 'MERGE_HEAD^{commit}' 2>/dev/null)"
blob() { # <treeish> <path> -> content on stdout; rc 0 present, 1 absent, 2 unreadable (a missing TREE is unreadable),
  # 3 the blob holds a NUL byte (bash command substitution would drop it silently; nothing is printed)
  local id nul
  pg cat-file -e "$1^{tree}" 2>/dev/null || return 2
  id="$(pg rev-parse -q --verify "$1:$2" 2>/dev/null)" || return 1
  nul="$(pg cat-file blob "$id" 2>/dev/null | tr -cd '\000' | wc -c)"
  [ "${nul// /}" = 0 ] || return 3
  pg cat-file blob "$id" 2>/dev/null || return 2
}
today="$(TZ=UTC date +%Y-%m-%d)"
# consumer DATA from the base commit; a config error disables waivers only
maxd=30; prefix=CON; conferr=""
ctext="$(blob "$basec" .submodule_pin_gate.conf)"; crc=$?
if [ "$crc" = 3 ]; then conferr="config .submodule_pin_gate.conf in base contains a NUL byte"
elif [ "$crc" = 2 ]; then conferr="config .submodule_pin_gate.conf unreadable in base"
elif [ "$crc" = 0 ]; then
  seen=" "
  while IFS= read -r line; do
    case "$line" in ''|'#'*) continue ;; esac
    k="${line%%=*}"; v="${line#*=}"
    [ "$k" != "$line" ] || { conferr="config line '$line' is not key=value"; break; }
    case "$seen" in *" $k "*) conferr="config key $k duplicated"; break ;; esac; seen+="$k "
    case "$k" in
      max_waiver_days) [[ "$v" =~ ^[1-9][0-9]{0,2}$ ]] && [ "$v" -le 365 ] || { conferr="config max_waiver_days='$v' not an integer 1..365"; break; }; maxd="$v" ;;
      item_prefix) [[ "$v" =~ ^[A-Z][A-Z0-9]+$ ]] || { conferr="config item_prefix='$v' does not match ^[A-Z][A-Z0-9]+\$"; break; }; prefix="$v" ;;
      *) conferr="config key '$k' unknown"; break ;;
    esac
  done <<<"$ctext"
fi
lim="$(TZ=UTC date -d "$today +$maxd days" +%Y-%m-%d)"
if [ -n "$waivers" ]; then wsrc="file $waivers"; wtext="$(cat "$waivers" 2>/dev/null)"; wnul="$(tr -cd '\000' <"$waivers" 2>/dev/null | wc -c)"
else wsrc="index :.submodule_pin_waivers"; wtext="$(pg show :.submodule_pin_waivers 2>/dev/null)"; wnul="$(pg show :.submodule_pin_waivers 2>/dev/null | tr -cd '\000' | wc -c)"; fi
cident="$(pg var GIT_COMMITTER_IDENT 2>/dev/null)"; aident="$(pg var GIT_AUTHOR_IDENT 2>/dev/null)"
idname() { printf '%s' "${1%% <*}"; }
idmail() { local m="${1#*<}"; printf '%s' "${m%%>*}"; }
IDPY='import sys,unicodedata,hashlib
def main():
    p=[x.decode("utf-8") for x in sys.stdin.buffer.read().split(b"\0")]
    if len(p)!=5: return 4
    a=p[0]
    if not a or a!=a.strip() or "<" in a or ">" in a or any(unicodedata.category(c).startswith("C") for c in a): return 3
    try:
        b=open(sys.argv[1],"rb").read()
    except OSError:
        return 5
    if hashlib.sha256(b).hexdigest()!="e5afc46b542187fb7c2955fb172c14e56798fae316f826ac3c2ddb0e3c9ee74f": return 5
    T={}
    for l in b.decode("utf-8").split("\n")[:-1]:
        x,y=l.split("\t"); T[chr(int(x,16))]="".join(chr(int(z,16)) for z in y.split())
    k=lambda s: unicodedata.normalize("NFKD", unicodedata.normalize("NFD", s).casefold())
    # the UTS #39 skeleton NFD(map(NFD(x))) wrapped in k: k starts with NFD and its NFKD output is already NFD, so the
    # two NFD calls of the spec are redundant here and are not written (measured: equal on all 1112064 scalar values)
    g=lambda s: k("".join(T.get(c,c) for c in k(s)))
    def f(s):
        for _ in range(8):
            t=g(s)
            if t==s: return t
            s=t
        raise ValueError("skeleton did not settle")
    if not f(a): return 3
    return 10 if any(i.strip() and f(i.strip())==f(a) for i in p[1:]) else 0
try:
    rc=main()
except BaseException:
    rc=4
sys.exit(rc)'
kids=""; kidsrc=""; SPENT=""
spent() { # <path> <old> <new> -> 0 spent (SPENT=commit), 1 unspent, 2 cannot tell (SPENT=reason)
  # spent = any commit reachable from a ref (refs/stash excluded), other than the commit being judged, that has the
  # base as a parent and whose waiver file carries the same (path, old, new, base) row
  local all k t rc hx
  if [ -z "$kidsrc" ]; then
    # HEAD is excluded only when the judged index IS HEAD's tree (--base HEAD^ re-check of HEAD); otherwise HEAD is
    # an ordinary candidate (in hook mode HEAD is the base, never its own child)
    hx=""
    pg diff-index --cached --quiet --ignore-submodules=none "${headc:-$basec}" -- 2>/dev/null && hx="$headc"
    if [ "$(pg rev-parse --is-shallow-repository 2>/dev/null)" != false ]; then kidsrc=shallow
    elif all="$(pg rev-list --exclude=refs/stash --all --parents 2>/dev/null)"; then kidsrc=ok
      kids="$(printf '%s\n' "$all" | awk 'BEGIN{b=ARGV[1]; h=ARGV[2]; ARGV[1]=ARGV[2]=""}
        $1""!=h"" {for(i=2;i<=NF;i++) if($i""==b""){print $1; break}}' "$basec" "$hx")"
    else kidsrc=err; fi
  fi
  [ "$kidsrc" = shallow ] && { SPENT="the superproject is shallow or its shallow state is unknown (a commit on the same parent may be hidden; run fetch --unshallow in the superproject)"; return 2; }
  [ "$kidsrc" = ok ] || { SPENT="git rev-list --all failed (a broken ref?)"; return 2; }
  for k in $kids; do
    t="$(blob "$k" .submodule_pin_waivers)"; rc=$?
    [ "$rc" = 3 ] && { SPENT="the waiver file of commit ${k:0:12} (same parent) contains a NUL byte"; return 2; }
    [ "$rc" = 2 ] && { SPENT="the waiver file of commit ${k:0:12} (same parent) is unreadable"; return 2; }
    [ "$rc" = 0 ] || continue
    printf '%s\n' "$t" | awk -F'\t' 'BEGIN{p=ARGV[1]; o=ARGV[2]; n=ARGV[3]; b=ARGV[4]; ARGV[1]=ARGV[2]=ARGV[3]=ARGV[4]=""; f=1}
      NF==7 && $1""==p"" && $2""==o"" && $3""==n"" && $7""==b"" {f=0} END{exit f}' "$1" "$2" "$3" "$basec" && { SPENT="$k"; return 0; }
  done
  return 1
}
WHY=""
waived() { # <path> <old_sha> <new_sha> -> 0 when a valid row waives this transition in this commit; sets WHY otherwise
  WHY="no waiver row for ($1, ${2:0:7} -> ${3:0:7}) in $wsrc"
  [ -z "$conferr" ] || { WHY="$conferr (waivers disabled)"; return 1; }
  [ -n "$wtext" ] || { WHY="no waiver data ($wsrc)"; return 1; }
  [ "${wnul// /}" = 0 ] || { WHY="waiver data ($wsrc) contains a NUL byte or could not be checked for one (git shows such a file as binary); remove it"; return 1; }
  local cand row rest a e i bs irc
  cand="$(printf '%s\n' "$wtext" | awk -F'\t' 'BEGIN{p=ARGV[1]; o=ARGV[2]; n=ARGV[3]; ARGV[1]=ARGV[2]=ARGV[3]=""}
    NF==7 && $1!~/^#/ && $1""==p"" && $2""==o"" && $3""==n"" {print $0 "\036" $4 "\037" $5 "\037" $6 "\037" $7}' "$1" "$2" "$3")"
  [ -n "$cand" ] || return 1
  while IFS=$'\036' read -r row rest; do
    IFS=$'\037' read -r a e i bs <<<"$rest"
    [[ "$row" != *$'\r'* ]] || { WHY="waiver row has a CR (CRLF line ending); save it with LF"; continue; }
    [ "$bs" = "$basec" ] || { WHY="waiver row is bound to base '$bs', but this commit's parent is $basec (a row waives one transition in one commit on top of the commit it names; for a new rollback bind a new row to the full SHA of the current HEAD)"; continue; }
    [[ "$e" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && [ "$(date -d "$e" +%Y-%m-%d 2>/dev/null)" = "$e" ] || { WHY="expiry '$e' is not a real YYYY-MM-DD date"; continue; }
    [[ "$e" < "$today" ]] && { WHY="waiver expired $e"; continue; }
    [[ "$e" > "$lim" ]] && { WHY="expiry $e is beyond today + max_waiver_days=$maxd ($lim)"; continue; }
    [[ "$i" =~ ^${prefix}-[0-9]{3,}$ ]] || { WHY="tracked item '$i' does not match ${prefix}-NNN"; continue; }
    [ -z "$mergeh" ] || { WHY="a merge is in progress (MERGE_HEAD ${mergeh:0:12}): a waiver is valid only in a single-parent commit; commit the rollback on its own"; continue; }
    [ -n "$cident" ] && [ -n "$aident" ] || { WHY="committer or author identity unresolvable; cannot check authoriser"; continue; }
    command -v python3 >/dev/null 2>&1 || { WHY="python3 missing; cannot check authoriser"; continue; }
    printf '%s\0%s\0%s\0%s\0%s' "$a" "$(idname "$cident")" "$(idmail "$cident")" "$(idname "$aident")" "$(idmail "$aident")" | python3 -I -c "$IDPY" "$conft"; irc=$?
    case "$irc" in
      0) spent "$1" "$2" "$3"; case $? in
           1) return 0 ;;
           0) WHY="waiver row already spent by commit ${SPENT:0:12} on the same parent ${basec:0:12} (a row waives one commit only)" ;;
           *) WHY="$SPENT; cannot prove the row is unspent" ;;
         esac ;;
      10) WHY="authoriser '$a' is the committer or author (producer cannot self-waive)" ;;
      3) WHY="authoriser '$a' is empty or has surrounding whitespace, <>, control characters, or no visible skeleton" ;;
      5) WHY="confusables table $conft is missing or is not the pinned one; cannot check authoriser" ;;
      *) WHY="authoriser check failed (python3 rc $irc)" ;;
    esac
  done <<<"$cand"
  return 1
}
fail=0; blind=0; checked=0
blindmsg() { echo "$GATE: BLIND $1 — $2. Fix: $3"; blind=1; }
pg diff --cached --raw -z --no-abbrev --no-renames --ignore-submodules=none "$basec" |
while IFS= read -r -d '' meta && IFS= read -r -d '' path; do
  [ -n "$path" ] || continue
  set -- $meta; om="${1#:}"; nm="$2"; osha="$3"; nsha="$4"
  [ "$om" = 160000 ] && [ "$nm" = 160000 ] || continue
  [ "$osha" != "$nsha" ] || continue
  checked=$((checked+1)); sub="$root/$path"; subp="$(cd "$sub" 2>/dev/null && pwd -P)"
  if [ -z "$subp" ] || ! sg -C "$sub" rev-parse --git-dir >/dev/null 2>&1; then
    blindmsg "$path" "submodule checkout missing or not a repository" "run submodule update --init -- $path in the superproject"; continue; fi
  if [ "$subp" != "$root/$path" ]; then
    blindmsg "$path" "checkout path is a symlink (resolves to $subp)" "replace it with a real checkout: run submodule update --init -- $path in the superproject"; continue; fi
  if [ "$(sg -C "$sub" rev-parse --show-toplevel 2>/dev/null)" != "$subp" ]; then
    blindmsg "$path" "path is not its own repository (resolves into the parent worktree)" "run submodule update --init -- $path in the superproject"; continue; fi
  shallow="$(sg -C "$sub" rev-parse --is-shallow-repository 2>/dev/null)"
  if [ "$shallow" = false ]; then fetchfix="run fetch in $path (then retry)"; else fetchfix="run fetch --unshallow in $path (then retry)"; fi
  if ! sg -C "$sub" cat-file -e "${osha}^{commit}" 2>/dev/null; then
    blindmsg "$path" "old pin ${osha:0:7} not in the submodule object store" "$fetchfix"; continue; fi
  if ! sg -C "$sub" cat-file -e "${nsha}^{commit}" 2>/dev/null; then
    blindmsg "$path" "new pin ${nsha:0:7} not in the submodule object store" "$fetchfix"; continue; fi
  sg -C "$sub" merge-base --is-ancestor "$osha" "$nsha" 2>/dev/null; fwd=$?
  if [ "$fwd" = 0 ]; then echo "$GATE: ok $path ${osha:0:7} -> ${nsha:0:7} (forward)"; continue; fi
  sg -C "$sub" merge-base --is-ancestor "$nsha" "$osha" 2>/dev/null; back=$?
  if [ "$back" = 0 ]; then
    if waived "$path" "$osha" "$nsha"; then echo "$GATE: WAIVED $path ${osha:0:7} -> ${nsha:0:7} (waiver row bound to parent ${basec:0:12} in $wsrc)"
    else echo "$GATE: FAIL $path — staged pin ${nsha:0:7} is an ANCESTOR of the base pin ${osha:0:7} (downgrade; waiver: $WHY). Advance the submodule checkout to the pin (run submodule update) or stage a valid waiver"; fail=1; fi
  elif [ "$fwd" = 1 ] && [ "$back" = 1 ] && [ "$shallow" = false ]; then
    echo "$GATE: WARN $path ${osha:0:7} -> ${nsha:0:7} DIVERGED (neither is an ancestor of the other; old pin's commits may be dropped — review by hand)"
  else
    blindmsg "$path" "ancestry of ${nsha:0:7} vs ${osha:0:7} cannot be decided (merge-base rc forward=$fwd back=$back, shallow=$shallow)" "$fetchfix"
  fi
done
dstat=("${PIPESTATUS[@]}")
[ "${dstat[0]}" = 0 ] || { echo "$GATE: BLIND — git diff --cached against ${basec:0:7} failed (rc ${dstat[0]}; index unreadable?)"; exit 2; }
[ "$fail" = 1 ] && exit 1
[ "$blind" = 1 ] && exit 2
echo "$GATE: PASS ($checked staged gitlink change(s) inspected)"; exit 0
