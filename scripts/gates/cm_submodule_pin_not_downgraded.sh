#!/usr/bin/env bash
# cm_submodule_pin_not_downgraded.sh — CM-SUBMODULE-PIN-NOT-DOWNGRADED gate (CON-046; §11.4.288(D), §11.4.233(G), §11.4.201).
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
# script). NOT guarded (measured): `git commit --no-verify`; plumbing (commit-tree, update-ref); and commit paths that
# do not run pre-commit at all: `git merge` (auto-commit and --ff-only), `cherry-pick`, `revert`, `rebase`. Therefore
# a downgrade made on a vehicle branch can still land on `main` by ff-only merge (the §11.4.288(B)(3) landing path has no
# hook in scratch clones). Per-commit index diffs also miss a downgrade split across commits or combined with a path
# move. A `--range A..B` mode for a pre-push / landing seam is a FOLLOW-UP (not built). The hook (scripts/hooks/
# pre-commit-submodule-pin-not-downgraded) is shipped, NOT installed anywhere (operator consent).
# --amend: git tells a pre-commit hook nothing about --amend, so the hook always uses base HEAD. For an amend that means
# the transition is judged against the commit being amended, not its parent: amending the waived rollback commit
# itself shows no gitlink change (PASS); a waiver row already in HEAD never counts (see below), so an amend cannot
# re-use an old row. Run the gate directly with `--base HEAD^` to judge an amend against the parent.
# Partial commit (`git commit -- <paths>`): git builds a temporary index from HEAD plus <paths>, so a waiver file not
# named in <paths> is not seen.
#
# ── Verdicts ──────────────────────────────────────────────────────────────
#   FAIL  staged gitlink new commit is a strict ancestor of the base pin and no valid waiver covers the transition.
#   BLIND the base, the index or a submodule cannot be read, one of the two commits is missing, or ancestry cannot be
#         decided (a shallow or incomplete submodule where neither direction is proven): never a pass (§11.4.201). The
#         message names the cause and the fix. Forward is checked first, so a bump proven forward in a shallow clone passes.
#   WARN  (exit 0, visible) diverged move: new pin neither ancestor nor descendant of the old pin in a complete history;
#         old pin's commits may be dropped from the superproject history — review by hand (reachability from upstream
#         main is the owed CM-SUBMODULE-POINTER-ON-MAIN, OWED-GATE-151).
#   PASS  no staged gitlink change, forward bump, diverged (WARN), new/deleted gitlink, or a valid waiver.
#
# ── Waiver (intentional rollbacks) — what IS and IS NOT enforced ─────────
# File `.submodule_pin_waivers`, read from the git INDEX. TAB-separated, exactly 6 fields:
#   path  old_sha  new_sha  authoriser  expiry  tracked_item
# A row is valid for ONE transition, in ONE commit:
#   - it binds the full transition (path, old pin, new pin), full 40/64-hex SHAs;
#   - it must be NEW in this commit: a row whose exact line is already in the base commit's waiver file never counts, so
#     a row committed with an earlier rollback cannot permit a later downgrade of the same pin;
#   - expiry is a real YYYY-MM-DD date, today <= expiry <= today + max_waiver_days (inclusive);
#   - tracked_item matches <item_prefix>-NNN (3+ digits; NOT checked to exist in the tracker);
#   - authoriser: no leading/trailing whitespace, no `<`/`>`, no control characters, and after Unicode NFC + casefold
#     (locale independent, python3) it equals none of committer name, committer email, author name, author email
#     (git var GIT_COMMITTER_IDENT / GIT_AUTHOR_IDENT); an unresolvable identity, or python3 missing, means not waived;
#   - a row with a CR (CRLF line ending) is refused and says so.
# Consumer DATA: `.submodule_pin_gate.conf`, read from the BASE commit (so it cannot be loosened in the commit that uses
# it), lines `key=value`, `#` comments. Keys: max_waiver_days (integer 1..365, default 30), item_prefix (^[A-Z][A-Z0-9]+$,
# default CON). An unknown key, a duplicate key or a bad value disables ALL waivers (fail safe) and never blocks a
# non-waiver verdict, so a commit that repairs the config is not itself blocked.
# NOT ENFORCED: no authoriser ROSTER exists in this repository, so the authoriser is NOT verified to be a rostered
# non-producer human — a producer can still name a second identity. This is therefore a speed bump with an audit trail,
# NOT an §11.4.271-conformant waiver; CM-WAIVER-ROSTERED-EXPIRY-TRACKED remains owed. `--waivers FILE` replaces the index
# copy with a plain file and then the novelty rule compares against an EMPTY base (tests / explicit use only; the hook
# never uses it).
#
# ── Usage ─────────────────────────────────────────────────────────────────
#   cm_submodule_pin_not_downgraded.sh [--root <repo>] [--base <rev>] [--waivers <file>] [-h]
#   --root is normalised to the repository top level (so diff.relative and a subdirectory --root cannot hide a path);
#   --base defaults to HEAD (empty tree when HEAD is unborn). A submodule checkout path that is a symlink is BLIND.
# Exit: 0 PASS · 1 FAIL · 2 BLIND (a usage error also exits 2). Read-only (git plumbing; submodule git calls run with
# GIT_NO_LAZY_FETCH=1 and GIT_NO_REPLACE_OBJECTS=1, so no network and no replace refs). Deps: bash, git, awk, date,
# python3 (waiver authoriser check only).
# Submodule git calls run with every variable from `git rev-parse --local-env-vars` removed except GIT_CONFIG_PARAMETERS
# and GIT_CONFIG_COUNT (what git itself does for submodules); the superproject reads keep them (needed for `commit -a`'s
# temporary index and for a linked worktree).
# Classification: universal (§11.4.17). Paired mutation test: cm_submodule_pin_not_downgraded_mutation_test.sh.
set -uo pipefail
shopt -s lastpipe
GATE="CM-SUBMODULE-PIN-NOT-DOWNGRADED"
self="${BASH_SOURCE[0]:-$0}"
root="$(cd "$(dirname "$self")/../.." && pwd -P)"; waivers=""; base=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) root="$(cd "${2:?--root needs a value}" && pwd -P)" || exit 2; shift 2 ;;
    --base) base="${2:?--base needs a value}"; shift 2 ;;
    --waivers) waivers="${2:?--waivers needs a value}"; shift 2 ;;
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
sg() { env "${unsets[@]}" GIT_NO_LAZY_FETCH=1 GIT_NO_REPLACE_OBJECTS=1 git "$@"; }
if [ -z "$base" ]; then
  basec="$(git -C "$root" rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null)" || basec="$(git -C "$root" hash-object -t tree /dev/null)"
else
  basec="$(git -C "$root" rev-parse -q --verify "$base^{commit}" 2>/dev/null)" || blind0 "--base $base does not resolve to a commit"
fi
blob() { # <treeish> <path> -> content on stdout; rc 0 present, 1 absent, 2 unreadable
  local id; id="$(git -C "$root" rev-parse -q --verify "$1:$2" 2>/dev/null)" || return 1
  git -C "$root" cat-file blob "$id" 2>/dev/null || return 2
}
today="$(date +%Y-%m-%d)"
# consumer DATA from the base commit; a config error disables waivers only
maxd=30; prefix=CON; conferr=""
ctext="$(blob "$basec" .submodule_pin_gate.conf)"; crc=$?
if [ "$crc" = 2 ]; then conferr="config .submodule_pin_gate.conf unreadable in base"
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
lim="$(date -d "$today +$maxd days" +%Y-%m-%d)"
if [ -n "$waivers" ]; then wsrc="file $waivers"; wtext="$(cat "$waivers" 2>/dev/null)"; btext=""
else wsrc="index :.submodule_pin_waivers"; wtext="$(git -C "$root" show :.submodule_pin_waivers 2>/dev/null)"
  btext="$(blob "$basec" .submodule_pin_waivers)"; [ $? = 2 ] && conferr="waiver file unreadable in base"; fi
cident="$(git -C "$root" var GIT_COMMITTER_IDENT 2>/dev/null)"; aident="$(git -C "$root" var GIT_AUTHOR_IDENT 2>/dev/null)"
idname() { printf '%s' "${1%% <*}"; }
idmail() { local m="${1#*<}"; printf '%s' "${m%%>*}"; }
IDPY='import sys,unicodedata
try:
    p=[x.decode("utf-8") for x in sys.stdin.buffer.read().split(b"\0")]
except Exception:
    sys.exit(4)
if len(p)!=5: sys.exit(4)
a=p[0]
if not a or a!=a.strip() or "<" in a or ">" in a or any(unicodedata.category(c).startswith("C") for c in a): sys.exit(3)
f=lambda s: unicodedata.normalize("NFC", unicodedata.normalize("NFC", s).casefold())
sys.exit(1 if any(i.strip() and f(i.strip())==f(a) for i in p[1:]) else 0)'
WHY=""
waived() { # <path> <old_sha> <new_sha> -> 0 when a complete, valid, new waiver row exists; sets WHY otherwise
  WHY="no waiver row for ($1, ${2:0:7} -> ${3:0:7}) in $wsrc"
  [ -z "$conferr" ] || { WHY="$conferr (waivers disabled)"; return 1; }
  [ -n "$wtext" ] || { WHY="no waiver data ($wsrc)"; return 1; }
  local cand row a e i irc
  cand="$(printf '%s\n' "$wtext" | awk -F'\t' 'BEGIN{p=ARGV[1]; o=ARGV[2]; n=ARGV[3]; ARGV[1]=ARGV[2]=ARGV[3]=""}
    NF==6 && $1!~/^#/ && $1==p && $2==o && $3==n {print $0 "\036" $4 "\037" $5 "\037" $6}' "$1" "$2" "$3")"
  [ -n "$cand" ] || return 1
  while IFS=$'\036' read -r row rest; do
    IFS=$'\037' read -r a e i <<<"$rest"
    [[ "$row" != *$'\r'* ]] || { WHY="waiver row has a CR (CRLF line ending); save it with LF"; continue; }
    [[ "$e" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && [ "$(date -d "$e" +%Y-%m-%d 2>/dev/null)" = "$e" ] || { WHY="expiry '$e' is not a real YYYY-MM-DD date"; continue; }
    [[ "$e" < "$today" ]] && { WHY="waiver expired $e"; continue; }
    [[ "$e" > "$lim" ]] && { WHY="expiry $e is beyond today + max_waiver_days=$maxd ($lim)"; continue; }
    [[ "$i" =~ ^${prefix}-[0-9]{3,}$ ]] || { WHY="tracked item '$i' does not match ${prefix}-NNN"; continue; }
    case $'\n'"$btext"$'\n' in *$'\n'"$row"$'\n'*) WHY="waiver row already in the base commit (a row counts only in the commit that adds it)"; continue ;; esac
    [ -n "$cident" ] && [ -n "$aident" ] || { WHY="committer or author identity unresolvable; cannot check authoriser"; continue; }
    command -v python3 >/dev/null 2>&1 || { WHY="python3 missing; cannot check authoriser"; continue; }
    printf '%s\0%s\0%s\0%s\0%s' "$a" "$(idname "$cident")" "$(idmail "$cident")" "$(idname "$aident")" "$(idmail "$aident")" | python3 -I -c "$IDPY"; irc=$?
    case "$irc" in
      0) return 0 ;;
      1) WHY="authoriser '$a' is the committer or author (producer cannot self-waive)" ;;
      3) WHY="authoriser '$a' is empty or has surrounding whitespace, <>, or control characters" ;;
      *) WHY="authoriser check failed (rc $irc, not valid UTF-8?)" ;;
    esac
  done <<<"$cand"
  return 1
}
fail=0; blind=0; checked=0
blindmsg() { echo "$GATE: BLIND $1 — $2. Fix: $3"; blind=1; }
git -C "$root" diff --cached --raw -z --no-abbrev --no-renames --ignore-submodules=none "$basec" |
while IFS= read -r -d '' meta && IFS= read -r -d '' path; do
  [ -n "$path" ] || continue
  set -- $meta; om="${1#:}"; nm="$2"; osha="$3"; nsha="$4"
  [ "$om" = 160000 ] && [ "$nm" = 160000 ] || continue
  [ "$osha" != "$nsha" ] || continue
  checked=$((checked+1)); sub="$root/$path"; subp="$(cd "$sub" 2>/dev/null && pwd -P)"
  if [ -z "$subp" ] || ! sg -C "$sub" rev-parse --git-dir >/dev/null 2>&1; then
    blindmsg "$path" "submodule checkout missing or not a repository" "git submodule update --init -- $path"; continue; fi
  if [ "$subp" != "$root/$path" ]; then
    blindmsg "$path" "checkout path is a symlink (resolves to $subp)" "replace it with a real checkout: git submodule update --init -- $path"; continue; fi
  if [ "$(sg -C "$sub" rev-parse --show-toplevel 2>/dev/null)" != "$subp" ]; then
    blindmsg "$path" "path is not its own repository (resolves into the parent worktree)" "git submodule update --init -- $path"; continue; fi
  shallow="$(sg -C "$sub" rev-parse --is-shallow-repository 2>/dev/null)"
  if [ "$shallow" = false ]; then fetchfix="git -C $path fetch (then retry)"; else fetchfix="git -C $path fetch --unshallow (then retry)"; fi
  if ! sg -C "$sub" cat-file -e "${osha}^{commit}" 2>/dev/null; then
    blindmsg "$path" "old pin ${osha:0:7} not in the submodule object store" "$fetchfix"; continue; fi
  if ! sg -C "$sub" cat-file -e "${nsha}^{commit}" 2>/dev/null; then
    blindmsg "$path" "new pin ${nsha:0:7} not in the submodule object store" "$fetchfix"; continue; fi
  sg -C "$sub" merge-base --is-ancestor "$osha" "$nsha" 2>/dev/null; fwd=$?
  if [ "$fwd" = 0 ]; then echo "$GATE: ok $path ${osha:0:7} -> ${nsha:0:7} (forward)"; continue; fi
  sg -C "$sub" merge-base --is-ancestor "$nsha" "$osha" 2>/dev/null; back=$?
  if [ "$back" = 0 ]; then
    if waived "$path" "$osha" "$nsha"; then echo "$GATE: WAIVED $path ${osha:0:7} -> ${nsha:0:7} (new waiver row in $wsrc)"
    else echo "$GATE: FAIL $path — staged pin ${nsha:0:7} is an ANCESTOR of the base pin ${osha:0:7} (downgrade; waiver: $WHY). Advance the submodule checkout to the pin (git submodule update) or stage a valid waiver"; fail=1; fi
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
