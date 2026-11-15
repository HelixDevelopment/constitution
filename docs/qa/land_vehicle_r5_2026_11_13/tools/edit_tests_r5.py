#!/usr/bin/env python3
"""Round-5 edit of tests/release/test_land_vehicle.sh: exact, single-occurrence text
replacements (each asserted), plus the round-5 helpers and cases inserted after BASE_OF.
Usage: edit_tests_r5.py <test file> <helpers file> <r5 section file>"""
import sys

path, helpers_path, section_path = sys.argv[1:4]
s = open(path, encoding="utf-8").read()
helpers = open(helpers_path, encoding="utf-8").read()
section = open(section_path, encoding="utf-8").read()


def rep(old, new):
    global s
    n = s.count(old)
    assert n == 1, (n, old[:120])
    s = s.replace(old, new)


# ---- header
rep("""# lander starts (push, send-pack, http-push, and any alias), and a second shim that fails one
# git call on purpose (V13). The run proves the
""", """# lander starts (push, send-pack, http-push, and any alias), and shims that fail one git call
# on purpose (V13, X8b) or change the index inside git write-tree (V15). The run proves the
""")
rep("""# Usage: bash tests/release/test_land_vehicle.sh [path/to/land_vehicle.sh]
#        (LANDER_SCRIPT=<path> also selects another copy; LANDER_TEST_FAILFAST=1
#        stops at the first FAIL, used by the mutant runner)
""", """# Round 5: the R5-* cases (right after the shared helpers) cover the round-5 findings F1-F13
# and N1-N3 and the round-4 reviewer mutants; see docs/qa/land_vehicle_r5_2026_11_13/.
#
# Usage: bash tests/release/test_land_vehicle.sh [path/to/land_vehicle.sh]
#        (LANDER_SCRIPT=<path> also selects another copy; LANDER_TEST_FAILFAST=1
#        stops at the first FAIL, used by the mutant runner; LANDER_TEST_R5_ONLY=1 runs
#        the setup and the round-5 cases only, then prints RESULT and exits)
""")

# ---- push_log_clean: the source of every push is a full sha (F1)
rep("""# push_log_clean: every recorded push is exactly `-q --no-verify --no-follow-tags
# <declared remote> main:refs/heads/main` (no +refspec, -f, --force*, --mirror,
# --delete, tags, send-pack or alias ...).
push_log_clean() {
  local line r okr
  [ -s "$PUSHLOG" ] || return 1
  while IFS= read -r line; do
    okr=0
    for r in $REMOTES; do [ "$line" = "-q"$'\\x1f'"--no-verify"$'\\x1f'"--no-follow-tags"$'\\x1f'"$r"$'\\x1f'"main:refs/heads/main" ] && okr=1; done
""", """# push_log_clean: every recorded push is exactly `-q --no-verify --no-follow-tags
# --recurse-submodules=no <declared remote> <full sha>:refs/heads/main` (no +refspec, -f,
# --force*, --mirror, --delete, tags, a branch name as the source, send-pack or alias ...).
push_log_clean() {
  local line r okr re US=$'\\x1f'
  [ -s "$PUSHLOG" ] || return 1
  while IFS= read -r line; do
    okr=0
    for r in $REMOTES; do
      re="^-q${US}--no-verify${US}--no-follow-tags${US}--recurse-submodules=no${US}${r}${US}[0-9a-f]{40}([0-9a-f]{24})?:refs/heads/main\\$"
      [[ "$line" =~ $re ]] && okr=1
    done
""")

# ---- the round-5 helpers and cases, after BASE_OF
rep("""BASE_OF() { g "$1/seed" rev-parse main; }
""", """BASE_OF() { g "$1/seed" rev-parse main; }
""" + helpers + "\n" + section)

# ---- SH1b: every T1 push names the checked sha
rep("""  ok "SH1 T1 publish made 9 plain pushes (argv recorded by the shim)"; else bad "SH1 T1 publish made 9 plain pushes"; sed 's/^/    | /' "$PUSHLOG"; fi
""", """  ok "SH1 T1 publish made 9 plain pushes (argv recorded by the shim)"; else bad "SH1 T1 publish made 9 plain pushes"; sed 's/^/    | /' "$PUSHLOG"; fi
srcs=$(awk -F $'\\x1f' '{print $6}' "$PUSHLOG" | sort -u)
if [ "$srcs" = "$local_main:refs/heads/main" ]; then
  ok "SH1b T1 every push names the checked sha as its source, never the branch name"; else bad "SH1b push sources: $srcs"; fi
""")

# ---- S2-S5
rep("""vc "$F" s5g 'feat s5g\\n\\nRoadmap-Item: CON-0501\\n'
""", """vc "$F" s5g 'feat s5g\\n\\nRoadmap-Item: CON-1050\\n'
""")
rep("""m3=$(g "$C" cat-file commit "$H_s3" 2>/dev/null || true)
if [ "$(rimtrailers "$C" "$H_s3")" = CON-777 ] && ! grep -q $'\\r' <<<"$m3"; then
  ok "S3 CRLF trailer replaced, CR stripped"; else bad "S3 CRLF trailer replaced, CR stripped"; fi
""", """H_s3=$(g "$C" log --format=%H -1 main -- s3 2>/dev/null || true)
m3=$(rawmsg "$C" "${H_s3:-HEAD}"; printf x); m3=${m3%x}
if [ -n "$H_s3" ] && [ "$(rimtrailers "$C" "$H_s3")" = CON-777 ] && [ "$m3" = $'feat s3\\r\\n\\r\\nRoadmap-Item: CON-777\\n' ]; then
  ok "S3 CRLF trailer replaced; the subject and the blank line keep their CR, byte for byte"; else bad "S3 CRLF trailer (message: $(printf '%q' "$m3"))"; fi
""")
rep("""if [ "$(rimtrailers "$C" "$H_s5g")" = CON-0501 ]; then
  ok "S5g a real id containing 050 (CON-0501) is kept"; else bad "S5g real id CON-0501 kept"; fi
""", """if [ "$(rimtrailers "$C" "$H_s5g")" = CON-1050 ]; then
  ok "S5g a real id containing 050 (CON-1050) is kept"; else bad "S5g real id CON-1050 kept"; fi
""")
rep("""run "$F/pub.out" publish "$F"; succeeded "S2-S5 publish exits 0" "$F/pub.out"
""", """run "$F/pub.out" publish "$F"; succeeded "S2-S5 publish exits 0" "$F/pub.out"
# S5g-b a value with a leading zero beyond three digits (CON-0501) is not an id: refused
base_fixture s5gb; F=$T/s5gb
vc "$F" s5gb 'feat s5gb\\n\\nRoadmap-Item: CON-0501\\n'; mkbundle "$F"
run "$F/out" prepare_raw "$F" --item-id CON-788
refused "S5g-b a trailer CON-0501 (not canonical) is refused at prepare" 1 "lacks a single real Roadmap-Item trailer \\\\(found: 'CON-0501'" "$F/out"
""")

# ---- X8b: the trailer rewrite no longer calls git; the re-commit write is the failing step
rep("""# ============================================ X8b append failure (parse succeeds) aborts
""", """# ============================================ X8b a failing write of the re-commit aborts (round 5:
# the trailer is rewritten in bash, so the write of the new commit object is the git step to fail)
""")
rep("""it=0; tr=0
for a in "\\$@"; do [ "\\$a" = interpret-trailers ] && it=1; [ "\\$a" = --trailer ] && tr=1; done
[ \\$it = 1 ] && [ \\$tr = 1 ] && { echo "fake append failure" >&2; exit 7; }
""", """prev=
for a in "\\$@"; do
  if [ "\\$prev" = -t ] && [ "\\$a" = commit ]; then echo "fake hash-object failure" >&2; exit 7; fi
  prev=\\$a
done
""")
rep("""refused "X8b interpret-trailers append failure aborts prepare" 1 'interpret-trailers failed \\(append\\)' "$F/out"
""", """refused "X8b a failing write of the re-commit aborts prepare" 1 'git hash-object failed for the re-commit' "$F/out"
if grep -q 'fake hash-object failure' "$F/out"; then ok "X8b control: the fault was really injected"; else bad "X8b control: the fault was really injected"; fi
""")

# ---- L6: ids have three digits at least
rep("""run "$F/prep.out" prepare_raw "$F" --key-prefix ABC --item-id ABC-12
""", """run "$F/prep.out" prepare_raw "$F" --key-prefix ABC --item-id ABC-012
""")
rep("""if [ "$RC" -eq 0 ] && [ "$(rimtrailers "$C" "$n")" = ABC-12 ]; then
  ok "L6 --key-prefix ABC: placeholder replaced with ABC-12"; else""", """if [ "$RC" -eq 0 ] && [ "$(rimtrailers "$C" "$n")" = ABC-012 ]; then
  ok "L6 --key-prefix ABC: placeholder replaced with ABC-012"; else""")

# ---- U4/U5
rep("""run "$F/out" prepare_raw "$F" --mint-cmd 'echo CON-5'
refused "U4 mint that prints an id but changes nothing is refused" 1 'printed CON-5 but changed no file in the clone' "$F/out"
""", """run "$F/out" prepare_raw "$F" --mint-cmd 'echo CON-005'
refused "U4 mint that prints an id but changes nothing is refused" 1 'printed CON-005 but changed no file in the clone' "$F/out"
""")
rep("""printf 'CON-77\\\\n' >> "$F/outside_tracker.db"
echo CON-77
""", """printf 'CON-077\\\\n' >> "$F/outside_tracker.db"
echo CON-077
""")
rep("""refused "U5 mint that writes outside the clone is refused" 1 'printed CON-77 but changed no file in the clone' "$F/out"
""", """refused "U5 mint that writes outside the clone is refused" 1 'printed CON-077 but changed no file in the clone' "$F/out"
""")

# ---- U10: a commit published elsewhere AFTER prepare is now refused; U10b prepares again
rep("""# U10: a remote moved after prepare with an already-published untrailered commit; the
# lander merges it; publish must not refuse that already-published commit
""", """# U10: a remote moved AFTER prepare with an untrailered commit and the caller merged it into
# the clone: round 5 refuses it (only commits at or before the prepared base may lack a
# trailer); U10b: prepare again in a new workdir makes it part of the base
""")
rep("""run "$F/pub.out" publish "$F"
allok=1; lm=$(g "$C" rev-parse main)
for r in $REMOTES; do [ "$(rmain "$F" "$r")" = "$lm" ] || allok=0; done
if [ "$RC" -eq 0 ] && [ $allok = 1 ] && g "$C" merge-base --is-ancestor "$pubd" "$lm"; then
  ok "U10 already-published untrailered commit is not refused; 9 remotes at main"; else bad "U10 already-published commit (rc=$RC)"; sed 's/^/    | /' "$F/pub.out"; fi
wrows=$(tail -n +2 "$F/ev/publish_warnings.tsv" 2>/dev/null || true)
if [ "$(grep -c $'\\t'"$pubd"$'\\t' <<<"$wrows")" -eq 8 ] && ! grep -q '^gitverse'$'\\t' <<<"$wrows" \\
   && [ "$(grep -c 'WARN: ' "$F/pub.out")" -eq 8 ] && grep -q '^## warnings' "$F/ev/publish.md"; then
  ok "V4 U10 the 8 remotes that receive the untrailered commit get a WARN row (gitverse none)"; else bad "V4 U10 WARN rows"; printf '%s\\n' "$wrows" | sed 's/^/    | /'; fi
""", """run "$F/pub.out" publish "$F"
refused "U10 a commit published elsewhere AFTER prepare, without a trailer, is refused" 1 \\
  'lacks a single real Roadmap-Item trailer.*run prepare again in a new workdir' "$F/pub.out"
if [ "$(atcount "$F" "$(BASE_OF "$F")")" = 8 ] && [ "$(rmain "$F" gitverse)" = "$pubd" ]; then
  ok "U10 no remote moved (8 at base, gitverse at the commit published elsewhere)"; else bad "U10 remotes moved"; fi
mkdir -p "$F/work2"
run "$F/prep2.out" lv prepare --bundle "$F/vehicle.bundle" --sha256 "$(cat "$F/sha")" --head "$(cat "$F/head")" \\
  --workdir "$F/work2" --remotes-file "$F/remotes.txt" --evidence-dir "$F/ev2" --item-id CON-803
succeeded "U10b prepare again in a new workdir exits 0" "$F/prep2.out"
C2=$F/work2/constitution
run "$F/pub2.out" lv publish --workdir "$F/work2" --remotes-file "$F/remotes.txt" --evidence-dir "$F/ev2"
allok=1; lm=$(g "$C2" rev-parse main 2>/dev/null || echo none)
for r in $REMOTES; do [ "$(rmain "$F" "$r")" = "$lm" ] || allok=0; done
if [ "$RC" -eq 0 ] && [ $allok = 1 ] && g "$C2" merge-base --is-ancestor "$pubd" "$lm"; then
  ok "U10b the commit published before this prepare is not refused; 9 remotes at main"; else bad "U10b (rc=$RC)"; sed 's/^/    | /' "$F/pub2.out"; fi
wrows=$(tail -n +2 "$F/ev2/publish_warnings.tsv" 2>/dev/null || true)
if [ "$(grep -c $'\\t'"$pubd"$'\\t' <<<"$wrows")" -eq 8 ] && ! grep -q '^gitverse'$'\\t' <<<"$wrows" \\
   && [ "$(grep -c 'WARN: ' "$F/pub2.out")" -eq 8 ] && grep -q '^## warnings' "$F/ev2/publish.md"; then
  ok "V4 U10b the 8 remotes that receive the untrailered commit get a WARN row (gitverse none)"; else bad "V4 U10b WARN rows"; printf '%s\\n' "$wrows" | sed 's/^/    | /'; fi
""")

# ---- U12: a value starting with '-' is a missing value (F7)
rep("""  if [ -z "$cn" ]; then refused "U12 empty --clone-name refused" 2 'option --clone-name needs a value' "$F/out"
""", """  if [ -z "$cn" ] || [[ "$cn" == -* ]]; then refused "U12 --clone-name '$cn' refused as a missing value" 2 'option --clone-name needs a value' "$F/out"
""")

# ---- the helpers moved up: remove the old definitions
rep("""landed_all() { # landed_all <F>: all 9 remote mains equal the clone main
  local lm r; lm=$(g "$1/work/constitution" rev-parse main 2>/dev/null || echo none)
  for r in $REMOTES; do [ "$(rmain "$1" "$r")" = "$lm" ] || return 1; done
}
lvenv() { # lvenv <VAR=value>... -- <lander args>: run the lander with extra env through the shim
  local -a e=()
  while [ "$1" != -- ]; do e+=("$1"); shift; done; shift
  env "${e[@]}" PATH="$T/shim:$PATH" "$LANDER" "$@"
}
PREP_ARGS() { printf '%s\\n' --bundle "$1/vehicle.bundle" --sha256 "$(cat "$1/sha")" --head "$(cat "$1/head")" \\
  --workdir "$1/work" --remotes-file "$1/remotes.txt" --evidence-dir "$1/ev"; }
# V2a GIT_DIR""", """# (landed_all, lvenv, PREP_ARGS, seed_main_file and mkmint are defined with the round-5 helpers)
# V2a GIT_DIR""")
rep("""# ============================================ V3 R3-3 the minted id must be new
seed_main_file() { # seed_main_file <F> <path> <content as printf %b>: commit on main, push to all 9, vehicle restarts at main
  local F=$1 r
  g "$F/seed" checkout -q main
  mkdir -p "$F/seed/$(dirname "$2")"; printf '%b' "$3" > "$F/seed/$2"
  g "$F/seed" add "$2"; g "$F/seed" commit -q -m "tracker seed" -m "Roadmap-Item: CON-002"
  for r in $REMOTES; do g "$F/seed" push -q "$F/remotes/$r.git" main:refs/heads/main; done
  g "$F/seed" checkout -q -B vehicle main
}
mkmint() { # mkmint <file> <line to append to docs/tracker.fake> <printed id>
  printf '#!/usr/bin/env bash\\nmkdir -p docs; printf %q >> docs/tracker.fake\\necho %q\\n' "$2"$'\\n' "$3" > "$1"; chmod +x "$1"
}
""", """# ============================================ V3 R3-3 the minted id must be new
""")

# ---- V3c: ids have three digits at least
rep("""mkmint "$F/mint_sub.sh" 'CON-777 minted' CON-77
run "$F/out" prepare_raw "$F" --mint-cmd "$F/mint_sub.sh"
refused "V3c id CON-77 is not found inside CON-777 (token match)" 1 'printed CON-77 but no changed file in the clone contains it' "$F/out"
""", """mkmint "$F/mint_sub.sh" 'CON-0770 minted' CON-077
run "$F/out" prepare_raw "$F" --mint-cmd "$F/mint_sub.sh"
refused "V3c id CON-077 is not found inside CON-0770 (token match)" 1 'printed CON-077 but no changed file in the clone contains it' "$F/out"
""")

# ---- V8d: tracker patterns need a literal first directory (F9), so the deleted file is docs/old.txt
rep("""fixture v8d; F=$T/v8d
printf '#!/usr/bin/env bash\\nrm -f a.txt; mkdir -p docs; printf "CON-777 minted\\\\n" >> docs/tracker.fake; echo CON-777\\n' > "$F/mint_del2.sh"; chmod +x "$F/mint_del2.sh"
run "$F/out" env LANDER_TRACKER_PATHS="a.txt docs/tracker.fake" PATH="$T/shim:$PATH" "$LANDER" prepare""", """base_fixture v8d; F=$T/v8d
seed_main_file "$F" docs/old.txt 'old\\n'
vc "$F" v1.txt 'feat: one\\n\\nRoadmap-Item: CON-050\\n'; mkbundle "$F"
printf '#!/usr/bin/env bash\\nrm -f docs/old.txt; printf "CON-777 minted\\\\n" >> docs/tracker.fake; echo CON-777\\n' > "$F/mint_del2.sh"; chmod +x "$F/mint_del2.sh"
run "$F/out" env LANDER_TRACKER_PATHS="docs/old.txt docs/tracker.fake" PATH="$T/shim:$PATH" "$LANDER" prepare""")
rep("""refused "V8d deleting a file that IS a tracker path is still refused as a deletion" 1 'mint command changed a path it may not change \\(D a\\.txt\\)' "$F/out"
""", """refused "V8d deleting a file that IS a tracker path is still refused as a deletion" 1 'mint command changed a path it may not change \\(D docs/old\\.txt\\)' "$F/out"
""")

# ---- V15: the mint commit is plumbing now (write-tree + commit-tree): the shim hits write-tree
v15_start = "# V15 (Z20) fixture: a PATH shim stages an extra file just before the lander's mint `git commit`,"
v16_start = "# V16 (Z23) LIVE git clean filter"
v9_start = "# ============================================ V9 T-1 checks the earlier tests did not pin"
a = s.index(v15_start); b = s.index(v16_start); c = s.index(v9_start)
assert s.count(v15_start) == 1 and s.count(v16_start) == 1 and s.count(v9_start) == 1 and a < b < c
new_v15 = r'''# V15 (Z20, round 5) a PATH shim changes the index inside the lander's `git write-tree`, after
# every check of the recorded mint changes: the tree differs from the record, so the lander refuses
mkdir -p "$T/shim_wt"
cat > "$T/shim_wt/git" <<'EOF'
#!/usr/bin/env bash
args=("$@"); n=$#; i=0; dir=
while [ "$i" -lt "$n" ]; do
  case "${args[$i]}" in
    -c) i=$((i + 2)) ;;
    -C) dir=${args[$((i + 1))]}; i=$((i + 2)) ;;
    -*) i=$((i + 1)) ;;
    *) break ;;
  esac
done
if [ "$i" -lt "$n" ] && [ "${args[$i]}" = write-tree ] && [ -n "$dir" ]; then
  case "${LV_WT_MODE:-}" in
    swap) printf 'CON-777 minted\nswapped after the checks\n' > "$dir/docs/tracker.fake"; @REALGIT@ -C "$dir" add docs/tracker.fake ;;
    extra) printf 'injected\n' > "$dir/docs/injected.fake"; @REALGIT@ -C "$dir" add docs/injected.fake ;;
  esac
  echo "write-tree fault injected (${LV_WT_MODE:-none})" >&2
fi
exec @REALGIT@ "$@"
EOF
sed -i "s#@REALGIT@#$REALGIT#g" "$T/shim_wt/git"; chmod +x "$T/shim_wt/git"
for mode in swap extra; do
  fixture "v15$mode"; F=$T/v15$mode
  run "$F/out" env LV_WT_MODE="$mode" PATH="$T/shim_wt:$PATH" "$LANDER" prepare --bundle "$F/vehicle.bundle" --sha256 "$(cat "$F/sha")" \
    --head "$(cat "$F/head")" --workdir "$F/work" --remotes-file "$F/remotes.txt" --evidence-dir "$F/ev" --mint-cmd "$F/mint.sh"
  refused "V15 ($mode) a mint tree that differs from the recorded mint changes is refused" 1 \
    'the mint commit differs from the recorded mint changes \(the index changed after the checks\)' "$F/out"
  if grep -qF "write-tree fault injected ($mode)" "$F/out" && [ ! -e "$F/work/constitution/.git/land_vehicle.state" ]; then
    ok "V15 ($mode) the fault was really injected (control); nothing landed"; else bad "V15 ($mode) fault not injected or state written"; fi
done

'''
new_v16 = r'''# V16 (Z23, round 5) a clean filter named by the caller's core.attributesFile does not apply: the
# lander pins core.attributesFile=/dev/null, so the staged tracker holds the id and prepare succeeds
fixture v16; F=$T/v16
gccopy "$F"
printf 'docs/tracker.fake filter=hideid\n' > "$F/attrs"
gcset "$F" core.attributesFile "$F/attrs"
gcset "$F" filter.hideid.clean 'sed s/CON-777/CON-XXX/'
run "$F/out" prep_gc "$F" --mint-cmd "$F/mint.sh"
committed=$(g "$F/work/constitution" show main:docs/tracker.fake 2>/dev/null || true)
git init -q "$F/ctl"; mkdir -p "$F/ctl/docs"; printf 'CON-777 minted\n' > "$F/ctl/docs/tracker.fake"
GIT_CONFIG_GLOBAL="$F/gc" git -C "$F/ctl" add docs/tracker.fake 2>/dev/null || true
cstaged=$(git -C "$F/ctl" cat-file blob :docs/tracker.fake 2>/dev/null || true)
if [ "$RC" -eq 0 ] && grep -q 'CON-777' <<<"$committed" && grep -q 'CON-XXX' <<<"$cstaged"; then
  ok "V16 core.attributesFile from the caller config is ignored: the tracker is committed with CON-777 (control: git add under that config stages CON-XXX)"
else bad "V16 attributesFile (rc=$RC committed=[$committed] control=[$cstaged])"; sed 's/^/    | /' "$F/out"; fi
# V16c the same filter named by an IN-TREE .gitattributes cannot be pinned away; the presence
# check reads the staged blob, so it refuses
base_fixture v16c; F=$T/v16c
seed_main_file "$F" .gitattributes 'docs/tracker.fake filter=hideid\n'
vc "$F" v1.txt 'feat: one\n\nRoadmap-Item: CON-050\n'; mkbundle "$F"
gccopy "$F"; gcset "$F" filter.hideid.clean 'sed s/CON-777/CON-XXX/'
run "$F/out" prep_gc "$F" --mint-cmd "$F/mint.sh"
refused "V16c an id that an in-tree attribute's clean filter strips from the staged tracker is refused" 1 'printed CON-777 but no changed file in the clone contains it' "$F/out"
staged=$(git -C "$F/work/constitution" cat-file blob :docs/tracker.fake 2>/dev/null || true)
if grep -q 'CON-777' "$F/work/constitution/docs/tracker.fake" 2>/dev/null && grep -q 'CON-XXX' <<<"$staged"; then
  ok "V16c control: the worktree holds CON-777 and the staged blob holds CON-XXX"; else bad "V16c control (staged: $staged)"; fi

'''
s = s[:a] + new_v15 + new_v16 + s[c:]

# ---- SH0 / SH2: the push call site pushes the checked sha
rep("""if grep -qF 'g -c push.followTags=false -c push.recurseSubmodules=no push -q --no-verify --no-follow-tags "${R_NAMES[$i]}" "main:refs/heads/main"' "$LANDER"; then
  ok "SH0 the push call site is the plain main:refs/heads/main push"; else bad "SH0 the push call site text"; fi
""", """if grep -qF 'g push -q --no-verify --no-follow-tags --recurse-submodules=no "${R_NAMES[$i]}" "$local_main:refs/heads/main"' "$LANDER"; then
  ok "SH0 the push call site pushes the checked sha to refs/heads/main"; else bad "SH0 the push call site text"; fi
""")
rep("""if push_log_clean; then ok "SH2 all $(wc -l < "$PUSHLOG") recorded pushes are plain main:refs/heads/main pushes"; else bad "SH2 recorded pushes"; fi
""", """if push_log_clean; then ok "SH2 all $(wc -l < "$PUSHLOG") recorded pushes of the round-4 cases are plain <sha>:refs/heads/main pushes"; else bad "SH2 recorded pushes"; fi
""")

open(path, "w", encoding="utf-8").write(s)
print("edited", path)
