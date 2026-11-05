#!/usr/bin/env bash
# tests/gates/test_oracle_frozen_exclusions.sh -- CON-043 (operator decision 2026-11-05): checked-in per-file exclusion
# list for frozen RED-evidence files in CM-ORACLE-STRATEGY-NAMED-AND-INDEPENDENT (section 11.4.245).
#   Contract under test (config/oracle_frozen_evidence_exclusions.tsv, TAB columns: path class blob-sha reason):
#     * header line `# ceiling: N` is REQUIRED (the entry count may only decrease; more entries than N => FAIL);
#     * path is a literal repository-relative file (no glob, no absolute, no `..`, no trailing slash);
#     * class is a member of the closed set {frozen-red-evidence}; blob-sha is the git blob id of the frozen file as its
#       OWNING repository computes it (40-hex sha1 or 64-hex sha256; checkout filters applied, like git status);
#     * an entry whose file's current blob id differs (or cannot be hashed) is VOIDED: the file is scanned again AND the
#       gate FAILs naming the voided entry; a malformed list is BLIND (rc 2), never a pass; an absent list = no exclusions.
#   Part B proves, on the REAL tree, that no runner executes the 3 frozen files (the premise of the exclusion).
# Test classes: unit/integration (REAL gate CLI in git sandboxes, no doubles), security (glob/path abuse), chaos (malformed,
# duplicate, missing-ceiling lists), determinism x3, RED proof vs a PINNED pre-change gate (ef18fea, never HEAD), paired
# section 1.1 mutations (incl. the round-1 reviewer mutants RM1-RM10).
set -uo pipefail
export CONSTITUTION_JEV_HOOK=off
unset ORACLE_GUARD_STRICT ORACLE_GUARD_BASELINE ORACLE_GUARD_BASE ORACLE_GUARD_ROOT CONSUMER_ROOT
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="$(cd "$here/../.." && pwd)"
sb="$(mktemp -d)"; : "${sb:?}"
trap 'rm -rf -- "${sb:?}"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "PASS $1"; }
bad() { fail=$((fail+1)); echo "FAIL $1"; }
chk() { if [ "$1" = 0 ]; then ok "$2"; else bad "$2"; fi; }
OR=cm_oracle_strategy_named_and_independent
GIT=(git -c user.email=t@t -c user.name=t -c commit.gpgsign=false)
EXC=config/oracle_frozen_evidence_exclusions.tsv

mkgate() { # $1 dir ; $2 gate source ; optional $3 sed expr (mutant)
    mkdir -p "$1/scripts/gates" "$1/scripts/lib" "$1/scripts/deps_manifest"
    cp "$2" "$1/scripts/gates/$OR.sh"
    cp "$src"/scripts/lib/default_scan_root.sh "$src"/scripts/lib/gate_env_override.sh "$src"/scripts/lib/third_party_prune.sh "$1/scripts/lib/"
    cp "$src"/scripts/deps_manifest/helix_deps_tsv.sh "$src"/scripts/deps_manifest/helix_deps_tsv.py "$src"/scripts/deps_manifest/helix_deps_manifest.py "$src"/scripts/deps_manifest/override_guard.sh "$1/scripts/deps_manifest/"
    [ -z "${3:-}" ] || sed -i -E "$3" "$1/scripts/gates/$OR.sh"
}
mkgate "$sb/g_new" "$src/scripts/gates/$OR.sh"
# RED gate = the gate as it was BEFORE exclusion support, from a PINNED pre-change commit (fix round 2, F1). It must never
# be `git show HEAD:`: once this change is committed HEAD already has exclusion support, so a HEAD-built "RED" gate PASSes
# and the RED half of the RED->GREEN proof can never run on the shipped tree. ef18fea = the parent of the CON-043 commits.
RED_PIN=ef18feadcba9f1a3ef06e2422ffc2b668d3f411e
have_red=0
if git -C "$src" show "$RED_PIN:scripts/gates/$OR.sh" > "$sb/red_gate.sh" 2>/dev/null; then
    if grep -q -- '--exclusions)' "$sb/red_gate.sh" || grep -q 'excl_sha' "$sb/red_gate.sh"; then
        bad "RED pin $RED_PIN: the pinned gate already has exclusion support, so it proves nothing"
    else
        ok "RED pin $RED_PIN: pinned pre-change gate resolves and has no --exclusions / excl_sha (control: the current gate has both)"
        grep -q -- '--exclusions)' "$src/scripts/gates/$OR.sh" && grep -q 'excl_sha' "$src/scripts/gates/$OR.sh" || bad "control needle: current gate lacks --exclusions)/excl_sha, so the pin check is blind"
        mkgate "$sb/g_red" "$sb/red_gate.sh"; have_red=1
    fi
else
    bad "RED pin $RED_PIN is not reachable in $src (shallow clone?): the RED proof cannot run; fetch full history"
fi

RUNCWD=""   # cwd for the gate run (default: the sandbox, which is not a git repository)
run() { local gd="$1" r="$2"; shift 2; OUT=$(cd "${RUNCWD:-$sb}" && nice -n 15 bash "$gd/scripts/gates/$OR.sh" --root "$r" "$@" 2>&1); RC=$?; }
commit() { "${GIT[@]}" -C "$1" add -A >/dev/null 2>&1; "${GIT[@]}" -C "$1" commit -qm "$2" >/dev/null 2>&1; git -C "$1" update-ref refs/remotes/origin/main HEAD; }
FROZEN='def test_a():
    assert 1

def test_b():
    assert 2
'
mkrepo() { # $1 dir ; $2 ceiling ; $3 class (default frozen-red-evidence); entry for frozen/test_frozen.py with its real blob sha
    local d="$1" sha
    mkdir -p "$d/config" "$d/frozen"; git -C "$d" init -q 2>/dev/null
    printf '%s' "$FROZEN" > "$d/frozen/test_frozen.py"
    printf '# baseline\n' > "$d/config/oracle_ratchet_baseline.txt"
    sha=$(git hash-object --no-filters "$d/frozen/test_frozen.py")
    printf '# frozen evidence exclusions\n# ceiling: %s\nfrozen/test_frozen.py\t%s\t%s\tarchived RED evidence, cannot run\n' "$2" "${3:-frozen-red-evidence}" "$sha" > "$d/$EXC"
    printf 'one\n' > "$d/README.md"; commit "$d" c1; printf 'two\n' >> "$d/README.md"; commit "$d" c2
}

# RED proof: the pinned pre-change gate (no exclusion support) FAILs a file above the empty baseline
mkrepo "$sb/r1" 1
if [ "$have_red" = 1 ]; then
    run "$sb/g_red" "$sb/r1" --quiet
    [ "$RC" = 1 ]; chk $? "RED: pinned pre-change gate FAILs the frozen file (rc=$RC) -- no exclusion support existed"
fi
run "$sb/g_new" "$sb/r1" --quiet
[ "$RC" = 0 ] && grep -q $'^ORACLE-VERDICT\tPASS\tmode=ratchet' <<<"$OUT" && grep -q 'excluded=1' <<<"$OUT" && grep -q 'voided=0' <<<"$OUT"; chk $? "GREEN: listed frozen file is excluded (rc=$RC, excluded=1 voided=0 in verdict)"
echo "$OUT" | tail -2

# determinism x3
a=$(bash -c 'cd "$1" && for i in 1 2 3; do bash "$2/scripts/gates/'"$OR"'.sh" --root "$3" --quiet 2>&1 | grep -v "^ORACLE-VERDICT" | sha256sum; done | sort -u | wc -l' _ "$sb" "$sb/g_new" "$sb/r1")
[ "$a" = 1 ]; chk $? "determinism: 3 runs give one identical output hash"

# voiding: edit the frozen file -> entry voided -> FAIL (with and without baseline slack)
mkrepo "$sb/r2" 1; printf '\ndef test_c():\n    assert 3\n' >> "$sb/r2/frozen/test_frozen.py"; commit "$sb/r2" edit
run "$sb/g_new" "$sb/r2" --quiet
[ "$RC" = 1 ] && grep -q 'VOIDED' <<<"$OUT" && grep -q 'frozen/test_frozen.py' <<<"$OUT"; chk $? "edited frozen file -> entry VOIDED, rc=1 (rc=$RC)"
printf '# baseline\nfrozen/test_frozen.py\t9\n' > "$sb/r2/config/oracle_ratchet_baseline.txt"; commit "$sb/r2" slack
run "$sb/g_new" "$sb/r2" --quiet
[ "$RC" = 1 ] && grep -q 'VOIDED' <<<"$OUT"; chk $? "voided entry FAILs even when the baseline has slack to absorb the file"
# RM1: a voided file is SCANNED AGAIN (its 3 unannotated functions are counted), not silently skipped
grep -q 'ratchet total=3 ' <<<"$OUT"; chk $? "voided file is rescanned: its 3 unannotated functions are counted (ratchet total=3)"
# RM5: the machine-readable verdict carries the real voided count
grep -q $'^ORACLE-VERDICT\tFAIL\tmode=ratchet\t.*\tvoided=1\t' <<<"$OUT"; chk $? "FAIL verdict line carries voided=1 (machine-readable field, not a constant)"
# F8: --write-baseline and --adopt-new-files refuse while an exclusion is voided (no PASS line after a FAIL line)
bsum=$(sha256sum < "$sb/r2/config/oracle_ratchet_baseline.txt")
run "$sb/g_new" "$sb/r2" --quiet --write-baseline
[ "$RC" = 1 ] && grep -q $'^ORACLE-VERDICT\tFAIL\tmode=write-baseline\treason=exclusions_voided' <<<"$OUT" && ! grep -q $'^ORACLE-VERDICT\tPASS' <<<"$OUT" \
  && [ "$(sha256sum < "$sb/r2/config/oracle_ratchet_baseline.txt")" = "$bsum" ]; chk $? "--write-baseline with a voided exclusion: FAIL rc=1, reason=exclusions_voided, no PASS line, baseline untouched (rc=$RC)"
run "$sb/g_new" "$sb/r2" --quiet --adopt-new-files --reason "probe"
[ "$RC" = 1 ] && grep -q $'^ORACLE-VERDICT\tFAIL\tmode=adopt\treason=exclusions_voided' <<<"$OUT" && ! grep -q $'^ORACLE-VERDICT\tPASS' <<<"$OUT"; chk $? "--adopt-new-files with a voided exclusion: FAIL rc=1, reason=exclusions_voided (rc=$RC)"
mkrepo "$sb/r2b" 1; rm -f "$sb/r2b/frozen/test_frozen.py"; mkdir -p "$sb/r2b/frozen"; ln -s /nonexistent "$sb/r2b/frozen/test_frozen.py"; commit "$sb/r2b" sym
run "$sb/g_new" "$sb/r2b" --quiet
[ "$RC" = 1 ]; chk $? "unhashable (dangling symlink) frozen path -> fail closed (rc=$RC)"

# new unlisted unannotated file still fails
mkrepo "$sb/r3" 1; printf 'def test_z():\n    assert 0\n' > "$sb/r3/frozen/test_other.py"; commit "$sb/r3" other
run "$sb/g_new" "$sb/r3" --quiet
[ "$RC" = 1 ] && grep -q 'test_other.py' <<<"$OUT"; chk $? "new unlisted unannotated file still FAILs"

# malformed lists are BLIND (rc 2)
badlist() { # $1 name ; $2 sed expr applied to the entry line ; $3 desc
    mkrepo "$sb/$1" 1; sed -i -E "$2" "$sb/$1/$EXC"; commit "$sb/$1" bad
    run "$sb/g_new" "$sb/$1" --quiet
    [ "$RC" = 2 ] && grep -q $'^ORACLE-VERDICT\tBLIND' <<<"$OUT"; chk $? "$3 -> BLIND rc=2 (rc=$RC)"
}
badlist b_glob 's#^frozen/test_frozen.py#frozen/*.py#' "glob in path"
badlist b_glob2 's#^frozen/test_frozen.py#frozen/test_frozen.p[y]#' "bracket glob in path"
badlist b_abs 's#^frozen/test_frozen.py#/etc/passwd#' "absolute path"
badlist b_dots 's#^frozen/test_frozen.py#frozen/../frozen/test_frozen.py#' "dot-dot path"
badlist b_dir 's#^frozen/test_frozen.py#frozen/#' "directory path"
badlist b_class 's#frozen-red-evidence#whatever#' "class outside the closed set"
badlist b_sha 's#\t[0-9a-f]{40}\t#\tabc\t#' "malformed blob sha"
badlist b_cols 's#\tarchived RED evidence, cannot run##' "missing reason column"
badlist b_extra 's#(cannot run)$#\1\textra#' "fifth column (exactly 4 columns required)"
badlist b_dtab 's#^(frozen/test_frozen.py)\t#\1\t\t#' "doubled TAB (an empty field is not collapsed)"
badlist b_dotslash 's#^frozen/test_frozen.py#./frozen/test_frozen.py#' "leading ./ in path"
badlist b_dslash 's#^frozen/test_frozen.py#frozen//test_frozen.py#' "double slash in path"
badlist b_dotseg 's#^frozen/test_frozen.py#frozen/./test_frozen.py#' "./ segment in path"
badlist b_dottail 's#^frozen/test_frozen.py#frozen/.#' "trailing /. in path"
# unreadable list: BLIND naming the real reason (not "missing ceiling")
mkrepo "$sb/b_unr" 1; commit "$sb/b_unr" unr; chmod 000 "$sb/b_unr/$EXC"
if [ ! -r "$sb/b_unr/$EXC" ]; then
    run "$sb/g_new" "$sb/b_unr" --quiet
    [ "$RC" = 2 ] && grep -q $'^ORACLE-VERDICT\tBLIND' <<<"$OUT" && grep -q 'unreadable' <<<"$OUT" && ! grep -q 'missing required header' <<<"$OUT"; chk $? "unreadable list -> BLIND rc=2 naming 'unreadable' (rc=$RC)"
else
    echo "SKIP unreadable-list case: running with CAP_DAC_OVERRIDE (chmod 000 still readable)"
fi
chmod 644 "$sb/b_unr/$EXC"
mkrepo "$sb/b_dup" 2; sed -n '3p' "$sb/b_dup/$EXC" >> "$sb/b_dup/$EXC"; commit "$sb/b_dup" dup
run "$sb/g_new" "$sb/b_dup" --quiet
[ "$RC" = 2 ]; chk $? "duplicate path -> BLIND rc=2 (rc=$RC)"
mkrepo "$sb/b_nc" 1; sed -i '/^# ceiling/d' "$sb/b_nc/$EXC"; commit "$sb/b_nc" noceil
run "$sb/g_new" "$sb/b_nc" --quiet
[ "$RC" = 2 ] && grep -q 'ceiling' <<<"$OUT"; chk $? "missing ceiling header -> BLIND rc=2"
mkrepo "$sb/b_over" 0; commit "$sb/b_over" over
run "$sb/g_new" "$sb/b_over" --quiet
[ "$RC" = 1 ] && grep -q 'ceiling' <<<"$OUT"; chk $? "more entries than the ceiling -> FAIL rc=1 (count may only decrease)"

# --exclusions /dev/null (not a regular file) = no exclusions, never BLIND (the explicit "no list" idiom)
run "$sb/g_new" "$sb/r1" --quiet --exclusions /dev/null
[ "$RC" = 1 ] && grep -q $'\texcluded=0\tvoided=0\texclusion_entries=0\t' <<<"$OUT"; chk $? "--exclusions /dev/null: no exclusions, frozen file counted, FAIL rc=1 not BLIND (rc=$RC)"
# absent list = no exclusions, existing behaviour unchanged
mkrepo "$sb/r4" 1; rm -f "$sb/r4/$EXC"; commit "$sb/r4" noexc
run "$sb/g_new" "$sb/r4" --quiet
[ "$RC" = 1 ] && ! grep -q 'excluded=[1-9]' <<<"$OUT"; chk $? "absent exclusion list: frozen file counted as before (FAIL against empty baseline)"
# stale entry (file removed) is reported, not fatal
mkrepo "$sb/r5" 1; git -C "$sb/r5" rm -q -f frozen/test_frozen.py; commit "$sb/r5" rm
run "$sb/g_new" "$sb/r5" --quiet
[ "$RC" = 0 ] && grep -q 'stale exclusion' <<<"$OUT"; chk $? "stale exclusion entry reported, not fatal (rc=$RC)"
# strict mode ignores exclusions (absolute mode)
run "$sb/g_new" "$sb/r1" --quiet --strict
[ "$RC" = 1 ]; chk $? "--strict (absolute mode) does not honour exclusions"

# ── F2: "no candidate test files" stays SKIP rc 0 in every topology (it must not need the rule-3 base) ───────────
mknf() { # $1 dir ; $2 1 = give it a remote main
    mkdir -p "$1"; git -C "$1" init -q 2>/dev/null; printf 'one\n' > "$1/README.md"
    "${GIT[@]}" -C "$1" add -A >/dev/null 2>&1; "${GIT[@]}" -C "$1" commit -qm c1 >/dev/null 2>&1
    [ "${2:-0}" = 1 ] && git -C "$1" update-ref refs/remotes/origin/main HEAD
    return 0
}
mknf "$sb/nf1" 0
if [ "$have_red" = 1 ]; then run "$sb/g_red" "$sb/nf1" --quiet; [ "$RC" = 0 ] && grep -q $'^ORACLE-VERDICT\tSKIP' <<<"$OUT"; chk $? "characterisation: pinned pre-change gate SKIPs a tree with no candidate files and no remote main (rc=$RC)"; fi
run "$sb/g_new" "$sb/nf1" --quiet
[ "$RC" = 0 ] && grep -q $'^ORACLE-VERDICT\tSKIP\treason=topology_unsupported' <<<"$OUT"; chk $? "no candidate files, no remote main -> SKIP rc=0, not BLIND (rc=$RC)"
mknf "$sb/nf2" 1
run "$sb/g_new" "$sb/nf2" --quiet --base no-such-ref
[ "$RC" = 0 ] && grep -q $'^ORACLE-VERDICT\tSKIP\treason=topology_unsupported' <<<"$OUT"; chk $? "no candidate files, invalid --base -> SKIP rc=0, not FAIL (rc=$RC)"
run "$sb/g_new" "$sb/nf2" --quiet
[ "$RC" = 0 ] && grep -q $'^ORACLE-VERDICT\tSKIP' <<<"$OUT"; chk $? "no candidate files, remote main -> SKIP rc=0 (rc=$RC)"

# ── F3: the blob id is the one git itself compares (owning repository, its filters, its object format) ───────────
# The frozen file lives in its OWN repository (like the llmctl submodule); the list lives in the scan root. The id
# must equal `git ls-tree` of the owning repository whatever its checkout filters are, and must not depend on the
# caller's cwd.
mknested() { # $1 dir ; $2 mode: crlf | eolcrlf | ident | sha256 ; sets NESTED_BLOB (the owning repo's blob id)
    local d="$1" n="$1/frozen" fmt=()
    mkdir -p "$d/config"; git -C "$d" init -q 2>/dev/null
    printf 'frozen/\n' > "$d/.gitignore"; printf '# baseline\n' > "$d/config/oracle_ratchet_baseline.txt"
    [ "$2" = sha256 ] && fmt=(--object-format=sha256)
    mkdir -p "$n"; git init -q "${fmt[@]}" "$n" 2>/dev/null
    case "$2" in
        crlf) git -C "$n" config core.autocrlf true ;;
        eolcrlf) printf '*.py eol=crlf\n' > "$n/.gitattributes" ;;
        ident) printf '*.py ident\n' > "$n/.gitattributes" ;;
    esac
    { [ "$2" = ident ] && printf '# $Id$\n'; printf '%s' "$FROZEN"; } > "$n/test_frozen.py"
    "${GIT[@]}" -C "$n" add -A >/dev/null 2>&1; "${GIT[@]}" -C "$n" commit -qm frozen >/dev/null 2>&1
    rm -f "$n/test_frozen.py"; git -C "$n" checkout -q -- test_frozen.py   # a real checkout applies the smudge/eol filters
    NESTED_BLOB=$(git -C "$n" rev-parse HEAD:test_frozen.py)
    printf 'one\n' > "$d/README.md"; commit "$d" c1
}
writelist() { printf '# ceiling: 1\nfrozen/test_frozen.py\tfrozen-red-evidence\t%s\tarchived RED evidence, cannot run\n' "$2" > "$1/$EXC"; commit "$1" list; }
for mode in crlf eolcrlf ident; do
    mknested "$sb/f3_$mode" "$mode"; writelist "$sb/f3_$mode" "$NESTED_BLOB"
    raw=$(git hash-object --no-filters "$sb/f3_$mode/frozen/test_frozen.py")
    # control needles: the checkout really changed the bytes, and git itself calls the file unmodified
    [ "$raw" != "$NESTED_BLOB" ] && [ -z "$(git -C "$sb/f3_$mode/frozen" status --porcelain)" ]; chk $? "F3 $mode: control: worktree bytes differ from the blob (raw $raw) and git status is clean"
    run "$sb/g_new" "$sb/f3_$mode" --quiet
    [ "$RC" = 0 ] && grep -q $'\texcluded=1\tvoided=0\t' <<<"$OUT"; chk $? "F3 $mode: a git-clean checkout is NOT voided (excluded=1 voided=0, rc=$RC)"
done
grep -q $'\r' "$sb/f3_crlf/frozen/test_frozen.py"; chk $? "F3 crlf: control: the autocrlf checkout really holds CR bytes"
# sha256 owning repository: its 64-hex blob id is accepted; the sha1 id of the same bytes is not (fail closed)
mknested "$sb/f3_s256" sha256; writelist "$sb/f3_s256" "$NESTED_BLOB"
[ "${#NESTED_BLOB}" = 64 ]; chk $? "F3 sha256: control: the owning repository reports a 64-hex blob id (${#NESTED_BLOB})"
run "$sb/g_new" "$sb/f3_s256" --quiet
[ "$RC" = 0 ] && grep -q $'\texcluded=1\tvoided=0\t' <<<"$OUT"; chk $? "F3 sha256 owning repo: its 64-hex blob id is accepted (rc=$RC)"
writelist "$sb/f3_s256" "$(git hash-object --no-filters "$sb/f3_s256/frozen/test_frozen.py")"
run "$sb/g_new" "$sb/f3_s256" --quiet
[ "$RC" = 1 ] && grep -q 'VOIDED' <<<"$OUT"; chk $? "F3 sha256 owning repo: a sha1 id of the same bytes is VOIDED, rc=1 (rc=$RC)"
# the caller's cwd is irrelevant: run from inside a sha256-format repository
mkdir -p "$sb/cwd256"; git init -q --object-format=sha256 "$sb/cwd256" 2>/dev/null
RUNCWD="$sb/cwd256" run "$sb/g_new" "$sb/r1" --quiet
[ "$RC" = 0 ] && grep -q $'\texcluded=1\tvoided=0\t' <<<"$OUT"; chk $? "F3 cwd: running from inside a sha256 repository does not void a sha1 entry (rc=$RC)"

# ── paired mutations: each mutant gate must be caught by the cases above ────────────────────────────────────────
mut() { # $1 name ; $2 sed ; $3 repo ; $4 expected rc that the REAL gate gives ; $5 desc ; [$6 ERE the REAL output contains] ; [rest: extra gate args]
    local name="$1" expr="$2" repo="$3" rrc="$4" desc="$5" needle="${6:-}"; shift 5; [ $# -gt 0 ] && shift
    mkgate "$sb/m_$name" "$src/scripts/gates/$OR.sh" "$expr"
    if cmp -s "$sb/m_$name/scripts/gates/$OR.sh" "$sb/g_new/scripts/gates/$OR.sh"; then bad "mutant $name: sed did not change the gate (dead mutation)"; return; fi
    # the real gate must give rrc (and the needle) on this repo, else the mutant check is blind
    run "$sb/g_new" "$repo" --quiet "$@"
    if [ "$RC" != "$rrc" ] || { [ -n "$needle" ] && ! grep -qE "$needle" <<<"$OUT"; }; then bad "mutant $name: the REAL gate does not give rc=$rrc${needle:+ + /$needle/} on $repo (rc=$RC): check is blind"; return; fi
    run "$sb/m_$name" "$repo" --quiet "$@"
    [ "$RC" != "$rrc" ] || { [ -n "$needle" ] && ! grep -qE "$needle" <<<"$OUT"; }; chk $? "mutant $name killed: $desc (mutant rc=$RC, real gate rc=$rrc${needle:+, needle /$needle/})"
}
mut sha 's#^excl_sha_ok[(][)] [{]#excl_sha_ok() { return 0;#' "$sb/r2" 1 "blob sha comparison disabled -> edited frozen file no longer voided"
mut glob 's#^is_glob[(][)] [{]#is_glob() { return 1;#' "$sb/b_glob" 2 "glob validation removed"
mut ceil 's#^excl_over_ceiling[(][)] [{]#excl_over_ceiling() { return 1;#' "$sb/b_over" 1 "ceiling check removed"
mut cls 's#frozen-red-evidence\) return 0#*) return 0#' "$sb/b_class" 2 "closed class set widened"
# reviewer mutants of round 1 (RM1-RM10), adopted; seds adapted to the round-2 code where it moved
mut RM1 's#\[ -n "\$\{excl_sha\[\$rel\]\+x\}" \] && \[ -z "\$\{excl_voided\[\$rel\]\+x\}" \]; then continue#[ -n "${excl_sha[$rel]+x}" ]; then continue#' "$sb/r2" 1 "voided file not rescanned" 'ratchet total=3 '
mut RM2 's#^excl_blob_id[(][)] [{]#excl_blob_id() { git hash-object --no-filters -- "$1/$2"; return;#' "$sb/f3_crlf" 0 "round-1 hashing (raw bytes in the caller cwd) voids a git-clean autocrlf checkout"
mut RM2fmt 's#^excl_blob_id[(][)] [{]#excl_blob_id() { git hash-object --no-filters -- "$1/$2"; return;#' "$sb/f3_s256" 1 "round-1 hashing ignores the owning repository object format"
mut RM2path 's#hash-object --path="\$2"#hash-object --no-filters#' "$sb/f3_ident" 0 "filters of the owning repository ignored (ident)"
mut RM3 's#"\$excl_nf" -ne 4#"$excl_nf" -lt 4#' "$sb/b_extra" 2 "fifth column accepted"
mut RM3tab 's#^excl_empty_field[(][)] [{]#excl_empty_field() { return 1;#' "$sb/b_dtab" 2 "doubled TAB collapsed and accepted"
mut RM4 's#\|\./\*\|\*/\./\*\|\*//\*\|#|*/./*|#' "$sb/b_dotslash" 2 "./ and // path checks removed (./ case)"
mut RM4b 's#\|\./\*\|\*/\./\*\|\*//\*\|#|*/./*|#' "$sb/b_dslash" 2 "./ and // path checks removed (// case)"
mut RM4c 's#\|\*/\.\|\.\) excl_blind#) excl_blind#' "$sb/b_dottail" 2 "trailing /. path check removed"
mut RM5 's#voided=\$\{excl_voided_n\}#voided=0#' "$sb/r2" 1 "verdict voided= field forced to 0" $'\tvoided=1\t'
mut RM6 's#if \[ "\$\{\#files\[@\]\}" -eq 0 \] && \[ "\$excl_voided_n" -eq 0 \]; then#if [ "${\#files[@]}" -eq 0 ]; then#' "$sb/r2b" 1 "SKIP before the exclusion check"
mut RM7 's#\[ -n "\$excl_ceiling" \] \|\| excl_blind "missing required header#[ -n "$excl_ceiling" ] || excl_ceiling=999999; : "#' "$sb/b_nc" 2 "missing ceiling treated as unbounded"
mut RM8 's#^if \[ "\$strict" != 1 \]; then$#if true; then#' "$sb/r1" 1 "--strict honours the list" '' --strict
mut RM9 's#if \[ -L "\$root/\$ep" \] \|\| #if #' "$sb/r2b" 1 "symlink check removed"
mut RM10 's#excl_stale=\$\(\( excl_stale \+ 1 \)\); echo#excl_applied=$(( excl_applied + 1 )); : #' "$sb/r5" 0 "vanished file silently counted as excluded" 'stale exclusion'
mut F8 's#^excl_refuse_write[(][)] [{]#excl_refuse_write() { return 1;#' "$sb/r2" 1 "write-baseline refusal on a voided exclusion removed" 'reason=exclusions_voided' --write-baseline

# ── Part B: the premise, on the REAL tree: no runner executes the 3 frozen files ───────────────────────────────
L="$src/submodules/llmctl"; P=specs/009-jev-decision-models/evidence/p1-red-original/harness/py
if [ ! -f "$L/$P/n_tests.py" ]; then
    echo "SKIP part B: submodules/llmctl not checked out (topology_unsupported)"
else
    # real list covers exactly the 3 frozen files; every recorded id equals (a) the blob in llmctl at the gitlink the
    # parent records (independent oracle: git's own object store) and (b) the id the gate computes for the worktree file
    gl=$(git -C "$src" ls-tree HEAD submodules/llmctl | awk '{print $3}')
    n=0; allok=0
    while IFS=$'\t' read -r p c s r; do
        case "$p" in ''|'#'*) continue ;; esac
        n=$((n+1)); rp="${p#submodules/llmctl/}"
        [ -n "$gl" ] && [ "$(git -C "$L" rev-parse "$gl:$rp" 2>/dev/null)" = "$s" ] || allok=1
        [ "$(git -C "$(dirname "$src/$p")" hash-object --path="$(basename "$p")" -- "$(basename "$p")")" = "$s" ] || allok=1
    done < "$src/$EXC"
    [ "$n" = 3 ] && [ "$allok" = 0 ]; chk $? "real list: 3 entries, each recorded id = the blob at the recorded llmctl gitlink ${gl:0:12} = the worktree file's id in its owning repo (n=$n)"
    # (1) parent census cannot see them: the parent tracks only the gitlink
    [ -z "$(git -C "$src" ls-files -- submodules/llmctl/specs)" ] && [ -n "$(git -C "$src" ls-files -- scripts/run_full_suite.sh)" ]; chk $? "parent run_full_suite census: no file under submodules/llmctl/specs is tracked by the parent (control needle: scripts/run_full_suite.sh is)"
    # (2) llmctl runner enumerates only tests/test_*.sh ; the py tier discovers only tests/py
    RUNNERS=("$L/tests/run_tests.sh" "$L/tests/test_py_unit.sh" "$L/Makefile")
    allf=0; for f in "${RUNNERS[@]}"; do [ -f "$f" ] || allf=1; done
    [ "$allf" = 0 ]; chk $? "the inspected runner files exist (a missing file must not read as 'no reference')"
    grep -q 'TESTS_DIR}"/test_\*\.sh' "$L/tests/run_tests.sh" && grep -q 'discover -s tests/py ' "$L/tests/test_py_unit.sh"; chk $? "llmctl runners: run_tests.sh globs tests/test_*.sh, test_py_unit.sh discovers -s tests/py only"
    RQ='specs/|p1-red-original|\bn_tests\b|\btest_d16_d32\b|\btest_defects_d01_d15\b'
    grep -nE "$RQ" "${RUNNERS[@]}" >/dev/null 2>&1; rq=$?
    [ "$allf" = 0 ] && [ "$rq" = 1 ]; chk $? "no runner/Makefile references specs/, p1-red-original or the 3 modules (grep rc=$rq: 1 = no match; 2 = error, not a pass)"
    # class-matched control needle for (2): the same -E \b word query over the same files finds a name that is present
    grep -qE '\brun_tests\b' "${RUNNERS[@]}"; chk $? "control needle (2): the same grep -E \\b query over the same runner files finds 'run_tests'"
    # (3) no code outside the frozen dir imports or invokes them
    DIRS=("$L/tests" "$L/lib" "$L/bin" "$L/llmctld" "$L/scripts")
    alld=0; for d in "${DIRS[@]}"; do [ -d "$d" ] || alld=1; done
    [ "$alld" = 0 ]; chk $? "the inspected llmctl directories exist (tests lib bin llmctld scripts)"
    q3='\bn_tests\b|\btest_d16_d32\b|\btest_defects_d01_d15\b'
    hits=$(grep -rlE "$q3" "${DIRS[@]}" 2>/dev/null | grep -v '/evidence/' | wc -l)
    [ "$alld" = 0 ] && [ "$hits" = 0 ]; chk $? "no file under llmctl tests/ lib/ bin/ llmctld/ scripts/ names the 3 modules (hits=$hits)"
    # class-matched control needle for (3): same -r -l -E \b query, same directory set, same /evidence/ filter
    nh=$(grep -rlE '\brun_tests\b' "${DIRS[@]}" 2>/dev/null | grep -v '/evidence/' | wc -l)
    [ "$nh" -gt 0 ]; chk $? "control needle (3): the same grep -rlE \\b query over the same directories finds 'run_tests' (files=$nh)"
    # (4) the archive itself says it cannot run and is not part of make test; the seams it drives are gone
    R="$L/specs/009-jev-decision-models/evidence/p1-red-original/README.md"
    grep -q 'can no longer run' "$R" && grep -q 'NOT part of `make test`' "$R" && [ ! -e "$L/lib/decide_gateway.py" ]; chk $? "archive README declares non-runnable + not in make test; the Python gateway it drives (lib/decide_gateway.py) is gone"
fi
echo "RESULT: pass=$pass fail=$fail"
[ "$fail" = 0 ]
