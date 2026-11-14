#!/usr/bin/env python3
"""Round-5 mutants for scripts/release/land_vehicle.sh.

Usage: python3 -I gen_r5mut.py <lander> <outdir>

Each mutant replaces exactly ONE occurrence of a source string. A string that
occurs 0 or more than 1 times is refused (the generator exits non-zero), so a
mutant can never silently miss its target. The mutant is written to
<outdir>/<name>/land_vehicle.sh and recorded in <outdir>/index.tsv with the
sha256 of the mutated file.

Groups:
  RM*  the 18 round-4 reviewer mutants, re-expressed against the round-5 code
  F*   the round-4 findings F1-F13 (each removes or weakens the round-5 fix)
  N*   the members the class inventory added (N1 merge strategy, N2 gitlink,
       N3 file modes)
  X*   other guards of the header (lock, environment scrub, hooks, pathspecs,
       bundle copy)
"""
import hashlib
import os
import sys

lander, outdir = sys.argv[1], sys.argv[2]
src = open(lander, encoding="utf-8").read()

M = [
    # ---------------------------------------------------- reviewer mutants
    ("RM01", "read-back compares with main re-read after the pushes",
     "  # pass 3: read-back\n",
     "  local_main=$(g rev-parse main)\n  # pass 3: read-back\n"),
    ("RM02", "g() no longer pins core.fsmonitor=false",
     "  -c core.hooksPath=/dev/null -c core.fsmonitor=false\n",
     "  -c core.hooksPath=/dev/null\n"),
    ("RM03", "tracker patterns compared as literal strings (no glob)",
     '[[ "$1" == $pat ]] && return 0',
     '[[ "$1" == "$pat" ]] && return 0'),
    ("RM04", "a remotes file without a final newline loses its last line",
     'while IFS= read -r line || [ -n "$line" ]; do\n    lineno=$((lineno + 1))',
     'while IFS= read -r line; do\n    lineno=$((lineno + 1))'),
    ("RM05", "re-expressed: the trailer value is normalised (CR removed) before validation",
     '    v=${v#"${v%%[![:space:]]*}"}\n    RI_VALS+=("$v")',
     '    v=${v#"${v%%[![:space:]]*}"}\n    v=${v//$\'\\r\'/}\n    RI_VALS+=("$v")'),
    ("RM06", "a TAB or newline in a mint path is no longer refused",
     '{ [[ "$st" == [AM] ]] && ! has_ctrl "$f" && tracker_path "$f"; }',
     '{ [[ "$st" == [AM] ]] && tracker_path "$f"; }'),
    ("RM08", "only an EMPTY line (not a whitespace-only line) opens the trailer block",
     'if [[ "${_l[i-1]}" =~ ^[[:space:]]*$ ]]; then MSG_BLOCK=$i; break; fi',
     'if [[ "${_l[i-1]}" =~ ^$ ]]; then MSG_BLOCK=$i; break; fi'),
    ("RM09", "the id-verify command runs in the caller's cwd",
     'out=$(cd "$CLONE" && export LAND_ITEM_ID="$1"',
     'out=$(export LAND_ITEM_ID="$1"'),
    ("RM10", "the id-verify command inherits the lock descriptor",
     'bash -c "$VERIFY_CMD" land_vehicle "$1" 9>&-)',
     'bash -c "$VERIFY_CMD" land_vehicle "$1")'),
    ("RM12", "prepare's final trailer check covers only commits after the landed vehicle head",
     'check_trailers "" "$after" --not "$main_before"',
     'check_trailers "" "$after" --not "$new_head"'),
    ("RM13", "the presence check accepts the id glued to a letter on its left",
     'id_in_blob() { grep -aEq -- "(^|[^A-Za-z0-9-])$1([^0-9]|\\$)" "$2"; }',
     'id_in_blob() { grep -aEq -- "$1([^0-9]|\\$)" "$2"; }'),
    ("RM15", "the newness check (text file) requires a left boundary",
     '    grep -aEq -- "$1-0*$2([^0-9]|\\$)" "$3"\n',
     '    grep -aEq -- "(^|[^A-Za-z0-9-])$1-0*$2([^0-9]|\\$)" "$3"\n'),
    ("RM16", "the publish trailer checks also run when preflight refused a remote",
     'if [ "$mode" = push ] && [ "$PREFLIGHT_BLOCKED" -eq 0 ]; then',
     'if [ "$mode" = push ]; then'),
    ("RM20", "an undocumented failing status is mapped to 0",
     "       exit 1 ;;\n  esac\n}",
     "       exit 0 ;;\n  esac\n}"),
    ("RM23", "re-expressed: the mode check accepts any mode starting with 1 (120000 symlink)",
     '[[ "$dmode" == 100644 || "$dmode" == 100755 ]] || die 1',
     '[[ "$dmode" == 1* ]] || die 1'),
    ("RM25", "LANDER_TRACKER_PATHS may hold '..'",
     '[[ "$_p" != /* ]] && [[ "$_p" != *..* ]] || die 2',
     '[[ "$_p" != /* ]] || die 2'),
    ("RM28", "the mint id keeps a trailing CR",
     "  id=${id%$'\\r'}\n",
     ""),
    ("RM31", "remote.<name>.* keys read from the clone's LOCAL config only",
     'got=$(g config --name-only --get-regexp "$ere" 2>/dev/null) || true',
     'got=$(g config --local --name-only --get-regexp "$ere" 2>/dev/null) || true'),
    # ---------------------------------------------------- F1 (check, then use)
    ("F1a", "the push sends the name main, not the checked sha",
     '"${R_NAMES[$i]}" "$local_main:refs/heads/main" 2>>"$ERRLOG"',
     '"${R_NAMES[$i]}" "main:refs/heads/main" 2>>"$ERRLOG"'),
    ("F1b", "no check that clone main is unchanged after the read-back",
     '[ "$now" = "$local_main" ] || die 1 "clone main moved during publish',
     'true || die 1 "clone main moved during publish'),
    ("F1c", "publish no longer checks the commits after the prepared base (WARN laundering)",
     '    check_trailers "; every commit after the prepared base',
     '    : check_trailers "; every commit after the prepared base'),
    ("F1d", "no assert_remote immediately before each push",
     '    assert_remote "$i"\n    if g push',
     '    if g push'),
    ("F1e", "the refusal message does not name the remotes already pushed",
     '; PUSHED_NAMES+=" ${R_NAMES[$i]}"',
     ''),
    ("F1f", "no assert_remote before ls-remote (preflight and read-back)",
     'remote_main() {\n  assert_remote "$1"\n',
     'remote_main() {\n'),
    ("F1g", "no assert_remote before each fetch at prepare",
     '    assert_remote "$i"\n    g fetch -q --no-tags --refmap= "${R_NAMES[$i]}"',
     '    g fetch -q --no-tags --refmap= "${R_NAMES[$i]}"'),
    ("F1h", "the internal ancestor check of a WARN row is removed",
     'g merge-base --is-ancestor "$c" "$main_before" \\\n          || die 1 "internal:',
     'true \\\n          || die 1 "internal:'),
    ("F1i", "the mint record is no longer compared with the write-tree result",
     'cmp -s "$rec" "$cmp" || die 1 "the mint commit differs from the recorded mint changes (the index changed after the checks)',
     'true || die 1 "the mint commit differs from the recorded mint changes (the index changed after the checks)'),
    # ---------------------------------------------------- F2 (newness)
    ("F2a", "no newness search in the tracker files at main",
     'if id_seen_in_file "$key" "$num" "$blob"; then',
     'if false; then'),
    ("F2b", "no newness search in the Roadmap-Item lines of the history",
     'if grep -aiEq -- "^[[:space:]]*roadmap-item',
     'if false && grep -aiEq -- "^[[:space:]]*roadmap-item'),
    ("F2c", "the history search covers main only, not the vehicle",
     'g rev-list "$head0" "$HEAD_SHA" | g cat-file --batch',
     'g rev-list "$head0" | g cat-file --batch'),
    ("F2z1", "newness in a text file no longer ignores leading zeros",
     '    grep -aEq -- "$1-0*$2([^0-9]|\\$)" "$3"\n',
     '    grep -aEq -- "$1-$2([^0-9]|\\$)" "$3"\n'),
    ("F2z2", "newness in the history no longer ignores leading zeros",
     ':.*$key-0*$num([^0-9]|\\$)" "$objs"',
     ':.*$key-$num([^0-9]|\\$)" "$objs"'),
    ("F2n", "a file holding a NUL byte is matched with a right boundary (not by substring)",
     '    grep -aEq -- "$1-0*$2" "$3"\n',
     '    grep -aEq -- "$1-0*$2([^0-9]|\\$)" "$3"\n'),
    # ---------------------------------------------------- F3 (head type, placeholders)
    ("F3a", "a non-commit --head is no longer refused",
     '[ "$htype" = commit ] || die 1',
     'true || die 1'),
    ("F3b", "the trailer checks accept a placeholder value",
     '[[ "$v" =~ $ID_RE ]] && ! [[ "$v" =~ $PLACEHOLDER_RE ]]\n}',
     '[[ "$v" =~ $ID_RE ]]\n}'),
    ("F3c", "--item-id may be a placeholder",
     '! [[ "$ITEM_ID" =~ $PLACEHOLDER_RE ]] || die 2',
     'true || die 2'),
    ("F3d", "a mint printing a placeholder is not refused at once",
     '! [[ "$id" =~ $PLACEHOLDER_RE ]] || die 1 "mint printed',
     'true || die 1 "mint printed'),
    # ---------------------------------------------------- F4 (showSignature)
    ("F4", "log.showSignature is no longer pinned",
     ' -c log.showSignature=false', ''),
    # ---------------------------------------------------- F5-F13
    ("F5", "push.pushOption is no longer cleared",
     '-c push.pushOption= -c push.gpgSign=false',
     '-c push.gpgSign=false'),
    ("F6", "git init uses the default template",
     'init -q -b main --template= --object-format',
     'init -q -b main --object-format'),
    ("F7", "an option value starting with '-' is accepted",
     '[ -z "$2" ] || [[ "$2" == -* ]]; then',
     '[ -z "$2" ]; then'),
    ("F9", "a tracker pattern needs no literal first directory",
     '[[ "$_p" == */* ]] && [[ "${_p%%/*}" =~ ^[A-Za-z0-9._-]+$ ]] && [ "${_p%%/*}" != . ] \\\n',
     'true \\\n'),
    ("F10", "the id pattern is the round-4 one (three or more digits)",
     'ID_RE="^${1}-(00[1-9]|0[1-9][0-9]|[1-9][0-9]{2,})\\$"',
     'ID_RE="^${1}-[0-9]{3,}\\$"'),
    ("F11", "a remotes-file line with a control character (a CR) is no longer refused",
     '    if [[ "$line" == *[',
     '    if false && [[ "$line" == *['),
    ("F13", "real_trailer no longer refuses a control character (ID_RE is anchored)",
     '! has_ctrl "$v" && [[ "$v" =~ $ID_RE ]]',
     '[[ "$v" =~ $ID_RE ]]'),
    # ---------------------------------------------------- N1 (merge strategy)
    ("N1a", "pull.twohead is no longer pinned (-s ort stays)",
     ' -c pull.twohead=ort', ''),
    ("N1b", "the merge no longer passes -s ort (pull.twohead=ort stays)",
     '--no-log --cleanup=strip -s ort \\',
     '--no-log --cleanup=strip \\'),
    ("N1c", "branch.main.mergeOptions is no longer cleared",
     ' -c branch.main.mergeOptions=', ''),
    ("N1d", "the merge tree is no longer compared with the oracle",
     '[ "${iso%%$\'\\n\'*}" = "$(g rev-parse --verify "$after^{tree}")" ] \\',
     'true \\'),
    ("N1e", "the oracle merge runs with the caller's global and system config",
     'iso=$(GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null g merge-tree',
     'iso=$(g merge-tree'),
    # ---------------------------------------------------- N2 (gitlinks)
    ("N2", "the mint record no longer passes --ignore-submodules=none",
     'g diff-index --cached --raw -z --no-abbrev --no-renames --ignore-submodules=none "$head0" > "$rec"',
     'g diff-index --cached --raw -z --no-abbrev --no-renames "$head0" > "$rec"'),
    # ---------------------------------------------------- N3 (file modes)
    ("N3a", "the file mode creation mask is 022, not 077",
     '\numask 077\n', '\numask 022\n'),
    ("N3b", "git init no longer pins core.sharedRepository=false",
     '-c core.fsmonitor=false -c core.sharedRepository=false \\\n    init -q',
     '-c core.fsmonitor=false \\\n    init -q'),
    ("N3c", "g() no longer pins core.sharedRepository=false",
     '-c core.commentChar=# -c core.sharedRepository=false\n',
     '-c core.commentChar=#\n'),
    # ---------------------------------------------------- E (commit identity)
    ("E2", "a commit that already carries one real trailer is re-committed (signature dropped)",
     '  if [ "$NEWMSG" = "$msg" ] && [ "$changed" = 0 ]; then MAP[$c]=$c; return 0; fi\n',
     ''),
    # ---------------------------------------------------- other guards
    ("X1", "the workdir lock is not taken",
     'flock -n 9 || die 2', 'true || die 2'),
    ("X2", "the GIT_* environment is not scrubbed",
     '\nlander_scrub_env\n', '\n'),
    ("X3", "g() no longer pins core.hooksPath=/dev/null",
     '  -c core.hooksPath=/dev/null -c core.fsmonitor=false\n',
     '  -c core.fsmonitor=false\n'),
    ("X4", "g() no longer passes --literal-pathspecs",
     'git --no-pager --no-replace-objects --literal-pathspecs -C "$CLONE"',
     'git --no-pager --no-replace-objects -C "$CLONE"'),
    ("X5", "the bundle copy in the clone is not hashed again",
     '[ "$actual" = "$want" ] || die 1 "bundle sha256 mismatch on the copy',
     'true || die 1 "bundle sha256 mismatch on the copy'),
    ("X6", "the trailer parser reads the caller's config",
     '  env GIT_DIR=/nonexistent GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \\\n',
     '  env GIT_DIR=/nonexistent \\\n'),
]

os.makedirs(outdir, exist_ok=True)
names = [m[0] for m in M]
if len(set(names)) != len(names):
    sys.exit("duplicate mutant name")
bad = 0
with open(os.path.join(outdir, "index.tsv"), "w", encoding="utf-8") as idx:
    idx.write("name\tsha256\tdescription\n")
    for name, desc, old, new in M:
        n = src.count(old)
        if n != 1:
            print(f"{name}: source string occurs {n} times, want exactly 1", file=sys.stderr)
            bad += 1
            continue
        body = src.replace(old, new, 1)
        if body == src:
            print(f"{name}: the mutant equals the original", file=sys.stderr)
            bad += 1
            continue
        d = os.path.join(outdir, name)
        os.makedirs(d, exist_ok=True)
        p = os.path.join(d, "land_vehicle.sh")
        with open(p, "w", encoding="utf-8") as fh:
            fh.write(body)
        os.chmod(p, 0o755)
        idx.write(f"{name}\t{hashlib.sha256(body.encode('utf-8')).hexdigest()}\t{desc}\n")
if bad:
    sys.exit(f"{bad} mutant(s) not generated")
print(f"{len(M)} mutants written under {outdir}")
