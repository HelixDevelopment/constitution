#!/usr/bin/env bash
# tests/decisions/repo_guard.sh — "the decisions tests wrote nothing into the real repository" guard.
#
# Sourced by run_all.sh; `bash repo_guard.sh --selftest` runs the control needles alone.
#
# DEFAULT (scoped) mode attributes only what a decisions-test run can have caused, so it can PASS in a shared
# tree where other streams, plugins and git legitimately change files at the same time (a guard that cannot
# pass there would be a §11.4.201 false-positive refusal). A snapshot holds four record classes:
#   (a) TOP     every entry at the repository root           -> a NEW root entry fails (the .decisions-backup
#                                                               leak shape)
#   (b) OWN     every path, with its content hash, under scripts/decisions/, tests/decisions/ and
#               docs/design/decisions_wizard_plan.md        -> any new, changed or removed path fails (allow-
#                                                               list DEC_GUARD_OWN_ALLOW, empty: no test edits
#                                                               those files on purpose)
#   (c) ART     every path outside .git/ and .remember/ whose name is a wizard artefact (decisions.yml,
#               decisions.sha256, decisions.intent, .decisions*, *.decisions-lock, .*.md.tmp.*) -> a NEW one
#               fails
#   (d) DOC     the managed-block region (BEGIN..END constitution-decisions, or "none") of CLAUDE.md,
#               AGENTS.md, GEMINI.md and QWEN.md at the root -> any change fails; DOCFULL (whole-file hash) is
#               compared only when git reports the file clean in BOTH snapshots, so another owner's edit outside
#               the block is not attributed to this run
# Anything else (.git/, .remember/, other streams' files) is ignored by design.
#
# STRICT mode (DEC_REPO_GUARD_STRICT=1) additionally compares the whole tree: `git status --porcelain --ignored
# -uall` plus every path (.git included, nothing excluded) newer than the run start. It is meant for a quiet
# tree and is EXPECTED to fail in a busy shared tree; its output says what changed.
#
# Honest boundary: the scoped mode cannot see a write by this run into an existing file outside its four
# classes (for example an existing file in another stream's directory). The strict mode can, but cannot tell
# who made it.

DEC_GUARD_OWN_DIRS=(scripts/decisions tests/decisions docs/design/decisions_wizard_plan.md)
DEC_GUARD_OWN_ALLOW="${DEC_GUARD_OWN_ALLOW:-}"   # space-separated repo-relative paths tests may edit (none)
DEC_GUARD_DOCS=(CLAUDE.md AGENTS.md GEMINI.md QWEN.md)

# region hash: the lines from an exact BEGIN marker line to the next exact END marker line, or "none"
_guard_region() {
  awk '/^<!-- BEGIN constitution-decisions( \(.*\))? -->\r?$/ {on=1} on {print} /^<!-- END constitution-decisions -->\r?$/ {on=0}' "$1" 2>/dev/null \
    | { r="$(sha256sum | cut -c1-64)"; [ "$r" = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ] && echo none || echo "$r"; }
}

# guard_snapshot ROOT -> sorted records on stdout
guard_snapshot() {
  local root="$1" e p rel
  (
    cd "$root" 2>/dev/null || exit 1
    for e in .[!.]* ..?* *; do [ -e "$e" ] || [ -L "$e" ] || continue; printf 'TOP %s\n' "$e"; done
    for p in "${DEC_GUARD_OWN_DIRS[@]}"; do
      [ -e "$p" ] || continue
      find "$p" \( -type f -o -type l \) -print 2>/dev/null | while IFS= read -r rel; do
        case " $DEC_GUARD_OWN_ALLOW " in *" $rel "*) continue ;; esac
        printf 'OWN %s %s\n' "$rel" "$(sha256sum <"$rel" 2>/dev/null | cut -c1-64)"
      done
      find "$p" -type d -print 2>/dev/null | sed 's/^/OWNDIR /'
    done
    find . \( -path ./.git -o -path ./.remember \) -prune -o \
      \( -name decisions.yml -o -name decisions.sha256 -o -name decisions.intent -o -name '.decisions*' \
         -o -name '*.decisions-lock' -o -name '.*.md.tmp.*' \) -print 2>/dev/null | sed 's|^\./||; s/^/ART /'
    for p in "${DEC_GUARD_DOCS[@]}"; do
      [ -e "$p" ] || { printf 'DOC %s absent\n' "$p"; continue; }
      printf 'DOC %s %s\n' "$p" "$(_guard_region "$p")"
      if git -C "$root" rev-parse --git-dir >/dev/null 2>&1 \
         && [ -z "$(git --no-optional-locks -C "$root" status --porcelain -- "$p" 2>/dev/null)" ]; then
        printf 'DOCFULL %s %s\n' "$p" "$(sha256sum <"$p" | cut -c1-64)"
      fi
    done
  ) | LC_ALL=C sort -u
}

# guard_compare BEFORE AFTER -> prints offending records, returns 1 when this run can have caused a change
guard_compare() {
  local before="$1" after="$2" bad=0 line name
  local fb fa; fb="$(mktemp)"; fa="$(mktemp)"
  # DOCFULL only when the file is git-clean in both snapshots (else another owner may be editing it)
  for name in $(grep '^DOCFULL ' "$before" | cut -d' ' -f2); do
    if grep -q "^DOCFULL $name " "$after"; then printf '%s\n' "$name"; fi
  done >"$fb.both"
  _guard_keep() { awk -v both="$fb.both" 'BEGIN{while((getline n < both)>0) k[n]=1} $1!="DOCFULL" || ($2 in k)' "$1"; }
  _guard_keep "$before" >"$fb"; _guard_keep "$after" >"$fa"
  # (a) and (c): only NEW records fail; (b) and (d): any difference fails
  while IFS= read -r line; do
    case "$line" in TOP\ *|ART\ *|OWN\ *|OWNDIR\ *|DOC\ *|DOCFULL\ *) echo "  new/changed: $line"; bad=1 ;; esac
  done < <(LC_ALL=C comm -13 "$fb" "$fa")
  while IFS= read -r line; do
    case "$line" in OWN\ *|OWNDIR\ *|DOC\ *|DOCFULL\ *) echo "  removed/changed: $line"; bad=1 ;; esac
  done < <(LC_ALL=C comm -23 "$fb" "$fa")
  rm -f "$fb" "$fa" "$fb.both"
  return $bad
}

# strict whole-tree census (opt-in)
guard_strict_status() { git --no-optional-locks -C "$1" status --porcelain=v1 --ignored -uall 2>&1; }
guard_strict_newer() { find "$1" -newer "$2" -print 2>/dev/null | LC_ALL=C sort; }

# --- control needles: the same functions must FAIL on every planted shape and PASS on unrelated changes
_guard_template() { # $1 = dir
  local r="$1"; mkdir -p "$r/scripts/decisions" "$r/tests/decisions" "$r/docs/design" "$r/other" "$r/.remember"
  git -C "$r" init -q 2>/dev/null
  printf '# P\n\nuser text\n' >"$r/CLAUDE.md"; printf '# A\n' >"$r/AGENTS.md"
  echo engine >"$r/scripts/decisions/decisions_engine.py"; echo t >"$r/tests/decisions/test_core.sh"
  echo plan >"$r/docs/design/decisions_wizard_plan.md"; echo x >"$r/other/x"; echo y >"$r/.remember/y"
  git -C "$r" add -A && git -C "$r" -c user.name=t -c user.email=t@t.invalid commit -qm t >/dev/null 2>&1
}
guard_selftest() {
  local w rc=0 name want got
  w="$(mktemp -d "${TMPDIR:-/tmp}/dec_guardst.XXXXXX")" || return 2
  _guard_template "$w/tpl"
  _case() { # name want(fail|pass) shell-snippet-run-in-the-copy
    name="$1"; want="$2"; local r="$w/$name"; cp -a "$w/tpl" "$r"
    guard_snapshot "$r" >"$w/$name.b"
    (cd "$r" && eval "$3")
    guard_snapshot "$r" >"$w/$name.a"
    if guard_compare "$w/$name.b" "$w/$name.a" >/dev/null; then got=pass; else got=fail; fi
    if [ "$got" = "$want" ]; then echo "  needle ok   $name ($got)"; else echo "  needle BAD  $name (want $want got $got)"; rc=1; fi
  }
  _case pos_new_top_entry      fail 'mkdir .decisions-backup-leak'
  _case pos_new_top_file       fail 'echo z >stray.txt'
  _case pos_own_changed        fail 'echo mutated >>scripts/decisions/decisions_engine.py'
  _case pos_own_new_pycache    fail 'mkdir scripts/decisions/__pycache__ && echo b >scripts/decisions/__pycache__/e.pyc'
  _case pos_own_removed        fail 'rm tests/decisions/test_core.sh'
  _case pos_plan_changed      fail 'echo edit >>docs/design/decisions_wizard_plan.md'
  _case pos_artefact_deep      fail 'mkdir -p other/deep && echo i >other/deep/decisions.intent'
  _case pos_backup_deep        fail 'mkdir -p other/u/.decisions-backup'
  _case pos_doc_block_added    fail 'printf "<!-- BEGIN constitution-decisions -->\nx\n<!-- END constitution-decisions -->\n" >>CLAUDE.md'
  _case pos_doc_full_changed   fail 'echo tail >>AGENTS.md; git add AGENTS.md; git -c user.name=t -c user.email=t@t.invalid commit -qm x'
  _case neg_other_stream       pass 'echo changed >>other/x; echo n >other/new.txt; echo r >.remember/z; echo g >.git/foo'
  _case neg_doc_edit_by_owner  pass 'echo "user line" >>CLAUDE.md'
  _case neg_no_change          pass ':'
  # BLIND check: an unreadable root must not look like "no change"
  if guard_snapshot "$w/does-not-exist" | grep -q .; then echo "  needle BAD  blind_root (records from a missing root)"; rc=1
  else echo "  needle ok   blind_root (no records from a missing root)"; fi
  safe_rm_rf "${w:?}"
  return $rc
}

if [ "${BASH_SOURCE[0]}" = "$0" ] && [ "${1:-}" = "--selftest" ]; then
  here="$(cd "$(dirname "$0")" && pwd)"; . "$here/../../scripts/lib/safe_rm.sh"
  guard_selftest; rc=$?; echo "repo_guard selftest: $([ $rc -eq 0 ] && echo PASS || echo FAIL)"; exit $rc
fi
