#!/bin/sh
# shellcheck disable=SC2015,SC2016 # A && ok || bad is the house test idiom (ok never fails); printf fixtures are literal shell text by design
# =============================================================================
# test_precheck_shellcheck_red.sh
# TDD (constitution 11.4.224) RED-first suite for the shellcheck check of
# review/precheck_pack.sh (lib/precheck_pack_run.py) under the WHOLE-FILE
# STRICT + SEVERITY FLOOR contract (T048 structural simplification, 11.4.250 +
# 11.4.276(E); operator decisions 2026-10-09 "Simplify: whole-file strict" and
# "Strict, with severity floor"):
#
#   "touch a file, own its shellcheck findings" -- every shell script the batch
#   touches (extension, shebang incl. versioned shells and busybox/toybox, or a
#   shell BASE blob) is linted whole with `shellcheck --norc -e SC1090,SC1091`
#   on stdin from an empty cwd with a scrubbed environment, INSIDE a hard
#   cgroup memory cap (systemd-run --user --scope MemoryMax) and only after a
#   size cap. error/warning findings and the closed info set SC2086 SC2030
#   SC2031 SC2162 SC2059 FAIL; every other finding is advisory (listed, never
#   failing). Directives (line-start or trailing after code) are policed:
#   disable=all / ranges / extended-analysis!=true / unknown keys FAIL; every
#   `disable=` carries its justification on the SAME line (>= 16 letters,
#   >= 3 distinct vowel-bearing non-placeholder words). Symlinked SCRIPT
#   candidates FAIL, other symlinks are listed. NUL bytes FAIL. /system/bin/sh
#   is linted as ksh (Android mksh, probed). ONE legacy exception: the
#   canonical checked-in TSV, chosen by the gate in a bound run, compared with
#   the BASE commit's TSV (new rows / raised pins only in a TSV-only batch),
#   rows evidence-checked, ratcheted per rule over BLOCKING findings, parse
#   errors fail closed, SC10xx unpinnable.
#
# Sections: N control needles (11.4.273); G golden good/bad; K severity floor;
# P special-character paths; E tool environment; X candidate selection +
# dialect; Y symlinks; Z CRLF / NUL; D directives; H host-safety caps + tool
# failures; B binding + gitlinks; L legacy exceptions; MUT mutants (own, >= 8)
# run against a scratch copy of the gate.
#
# Usage: sh test_precheck_shellcheck_red.sh     Exit: 0 all held; 1 any FAIL.
# =============================================================================
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
REVIEW="$FC/review"
FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "NOT ok: $1"; }

echo "== precheck_pack shellcheck WHOLE-FILE STRICT + SEVERITY FLOOR (RED-first) =="
if ! command -v shellcheck >/dev/null 2>&1; then
    echo "SKIP: shellcheck not on PATH -- cannot exercise this check (11.4.3 honest skip)"
    exit 0
fi

TMP=$(mktemp -d)
HOLDER_PID=""
cleanup() {
    if [ -n "$HOLDER_PID" ]; then kill "$HOLDER_PID" 2>/dev/null; fi
    rm -rf "$TMP"
}
trap cleanup EXIT INT TERM
GIT="git -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false"

# The gate under test (MUT re-points this at a mutated scratch copy).
GATE_DIR="$REVIEW"

# --- scenario helpers -------------------------------------------------------
# new_case <name>          fresh repo $R with an empty-ish base (README.md)
# wb <rel> <printf-fmt>    write a BASE file (before `base`)
# base                     commit the base
# wh <rel> <printf-fmt>    write a HEAD file
# head                     commit the head
# gate [args...]           bind (builder lib) + run the gate bound; sets RC, OUT
new_case() {
    CASE=$1; R="$TMP/$CASE"; mkdir -p "$R"
    printf 'readme\n' >"$R/README.md"
}
wb() { mkdir -p "$(dirname "$R/$1")"; printf '%b' "$2" >"$R/$1"; }
wh() { mkdir -p "$(dirname "$R/$1")"; printf '%b' "$2" >"$R/$1"; }
base() { ( cd "$R" && git init -q . && $GIT add -A && $GIT commit -q -m base ) >/dev/null 2>&1; BASE=$(git -C "$R" rev-parse HEAD); }
head() { ( cd "$R" && $GIT add -A && $GIT commit -q -m head ) >/dev/null 2>&1; HEADC=$(git -C "$R" rev-parse HEAD); }
mkraw() { # <out> -> an unbound batch of every path changed BASE..HEADC
    python3 - "$R" "$BASE" "$HEADC" "$1" <<'PY'
import json, subprocess, sys
r, b, h, out = sys.argv[1:5]
p = subprocess.run(["git", "-C", r, "-c", "core.quotePath=false", "diff", "-z", "--name-only", "--no-renames", b, h],
                   capture_output=True).stdout.split(b"\0")
paths = sorted(x.decode("utf-8", "surrogateescape") for x in p if x)
json.dump({"batch_id": "RB-SC-" + r.rsplit("/", 1)[-1], "changes": [], "related_by": "logic_group:sc",
           "total_changed_lines": 1,
           "slices": [{"slice_id": "S1", "lines": 1, "context_pack": {
               "intent": "fixture", "changed_paths": paths,
               "blast_radius": "%d changed path(s) in this slice: %s" % (len(paths), ", ".join(paths))}}]},
          open(out, "w"), ensure_ascii=False)
PY
}
gate_prepare() { # worktree at HEADC + bound batch, no gate run yet
    git -C "$R" worktree add --detach --quiet "$R.co" "$HEADC" >/dev/null 2>&1
    mkraw "$R.raw.json"
    python3 "$GATE_DIR/lib/precheck_pack_build_run.py" bind --repo "$R" --base "$BASE" --head "$HEADC" \
        --batch "$R.raw.json" --out "$R.batch.json" --rewrite-changes >"$R.bind.out" 2>&1
}
gate_run() {
    OUT="$R.out.json"
    sh "$GATE_DIR/precheck_pack.sh" --batch "$R.batch.json" --clean-checkout "$R.co" --out "$OUT" \
        --baseline-repo "$R" --baseline-ref "$BASE" --head-sha "$HEADC" "$@" >"$R.stdout" 2>"$R.stderr"
    RC=$?
}
gate() { gate_prepare; gate_run "$@"; }
sc() { # <python expr over c (shellcheck check), d (pack), e (evidence)>
    python3 - "$OUT" "$1" <<'PY' 2>&1
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
c = [x for x in d["checks"] if x["check"] == "shellcheck"][0]
e = c["evidence"]
# eval is safe here: argv[2] is a literal expression written in THIS test file, never external input.
print(eval(sys.argv[2], {"c": c, "d": d, "e": e}))
PY
}
rules() { sc 'sorted({f["rule"] for f in e.get("findings", [])})'; }
viol() { sc '" ".join(sorted({v.split()[0] for x in e.get("directive_violations", []) for v in x["violations"]}))'; }
has_err() { case "$(sc 'e.get("errors")')" in *"$1"*) return 0 ;; *) return 1 ;; esac; }

# =============================================================================
# N. control needles (11.4.273): the instrument sees a positive and a negative.
# =============================================================================
POS=$(printf '#!/bin/sh\necho $1\n' | shellcheck --norc -s sh -f json1 - | python3 -c 'import json,sys;print(sorted(c["code"] for c in json.load(sys.stdin)["comments"]))')
NEG=$(printf '#!/bin/sh\necho "$1"\n' | shellcheck --norc -s sh -f json1 - | python3 -c 'import json,sys;print(len(json.load(sys.stdin)["comments"]))')
[ "$POS" = "[2086]" ] && [ "$NEG" = "0" ] && ok "N1 control needles: raw shellcheck reports SC2086 on 'echo \$1' and nothing on the quoted twin" \
    || bad "N1 control needles failed: pos=$POS neg=$NEG"
CAPN=$(systemd-run --user --scope --quiet --collect -p MemoryMax=64M -p MemorySwapMax=0 -- sh -c 'cat "/sys/fs/cgroup$(sed -n "s/^0:://p" /proc/self/cgroup)/memory.max"' 2>&1)
[ "$CAPN" = "67108864" ] && ok "N2 control needle: a systemd-run --user scope really enforces MemoryMax on this host (memory.max=$CAPN)" \
    || bad "N2 control needle: the hard memory cap mechanism is not usable here: $CAPN"

# =============================================================================
# G. golden good / golden bad
# =============================================================================
new_case g1; base; wh pkg/clean.sh '#!/bin/sh\necho "clean"\n'; head; gate
G1=$(sc 'c["verdict"], e["mode"], e["counts"]["files_linted"], e["binding"]["state"], d["provenance"]["head_sha_source"]')
[ "$RC" -eq 0 ] && [ "$G1" = "('PASS', 'whole-file', 1, 'bound', 'batch-binding-verified')" ] \
    && ok "G1 golden-good: a clean new script => PASS, whole-file mode, 1 file linted, bound" \
    || bad "G1 golden-good: rc=$RC $G1 $(head -c 300 "$R.stderr")"

new_case g2
wb pkg/legacy.sh '#!/bin/sh\nx=$1\necho $x\n# pad\n# pad\n# pad\n# pad\n# pad\n# pad\n# pad\n# pad\n'; base
wh pkg/legacy.sh '#!/bin/sh\nx=$1\necho $x\n# pad\n# pad\n# pad\n# pad\n# pad\n# pad\n# pad\n# edited far away from the finding\n'; head; gate
[ "$RC" -eq 1 ] && [ "$(rules)" = "['SC2086']" ] && [ "$(sc 'e["findings"][0]["line"]')" = "3" ] \
    && ok "G2 golden-bad: a PRE-EXISTING blocking finding 8 lines from the edit in a touched file FAILs (touch a file, own its findings)" \
    || bad "G2 golden-bad: rc=$RC rules=$(rules)"

new_case g3; wb pkg/other.sh '#!/bin/sh\necho $1\n'; base; wh pkg/clean.sh '#!/bin/sh\necho "c"\n'; head; gate
[ "$RC" -eq 0 ] && [ "$(sc 'e["counts"]["files_linted"]')" = "1" ] \
    && ok "G3 scope: an UNTOUCHED script with a finding is not part of the batch => not linted, PASS" \
    || bad "G3 scope: rc=$RC $(sc 'e.get("findings")')"

# =============================================================================
# K. severity floor: error + warning + the closed info set block; the rest is advisory
# =============================================================================
new_case k1; base
wh pkg/error.sh '#!/bin/sh\nif true; then\n  echo x\n'
wh pkg/warning.sh '#!/bin/sh\nunused=1\n'
wh pkg/info.sh '#!/bin/sh\necho $1\n'
head; gate
K1=$(sc 'sorted({(f["file"], f["level"]) for f in e.get("findings", [])})')
for lv in "'pkg/error.sh', 'error'" "'pkg/warning.sh', 'warning'" "'pkg/info.sh', 'info'"; do
    case "$K1" in *"($lv)"*) ok "K1 blocking class ($lv) FAILs the check" ;; *) bad "K1 blocking class ($lv) missing: $K1" ;; esac
done
[ "$RC" -eq 1 ] || bad "K1 rc=$RC (want 1)"

new_case k2; base
wh pkg/style.sh '#!/bin/sh\nx=`date`\necho "$x"\n'
wh pkg/advisory_info.sh "#!/bin/sh\necho '\$HOME is literal here'\n"
head; gate
K2=$(sc 'sorted({(f["file"], f["level"], f["rule"]) for f in e.get("advisory_findings", [])}), e["counts"]["findings"]')
[ "$RC" -eq 0 ] && [ "$K2" = "([('pkg/advisory_info.sh', 'info', 'SC2016'), ('pkg/style.sh', 'style', 'SC2006')], 0)" ] \
    && ok "K2 advisory: a style finding (SC2006) and a non-floor info finding (SC2016) are LISTED but do not fail (PASS)" \
    || bad "K2 advisory: rc=$RC $K2"

new_case k3; base
wh pkg/sub.sh '#!/bin/sh\nx=1\n(x=2)\necho "$x"\n'
wh pkg/read.sh '#!/bin/sh\nread line\necho "$line"\n'
wh pkg/fmt.sh '#!/bin/sh\nfmt=$1\nprintf "$fmt"\n'
head; gate
[ "$RC" -eq 1 ] && [ "$(rules)" = "['SC2030', 'SC2031', 'SC2059', 'SC2162']" ] \
    && ok "K3 the rest of the always-blocking info set (SC2030 SC2031 SC2059 SC2162) FAILs" \
    || bad "K3 blocking info set: rc=$RC rules=$(rules)"

new_case k4; base; wh pkg/src.sh '#!/bin/sh\n. ./lib.sh\nx=lib2.sh\n. "$x"\n'; head; gate
K4=$(sc 'sorted({f["rule"] for f in e.get("findings", []) + e.get("advisory_findings", [])}), "SC1090,SC1091" in e["tool"]["argv"]')
[ "$RC" -eq 0 ] && [ "$K4" = "([], True)" ] \
    && ok "K4 the stdin-lint 'cannot follow source' rules SC1090/SC1091 are excluded explicitly (recorded in argv)" \
    || bad "K4 excluded rules: rc=$RC $K4"

# =============================================================================
# P. special-character paths (NUL-safe enumeration, core.quotePath=false)
# =============================================================================
new_case p1; base
for nm in "$(printf 'caf\303\251.sh')" 'with space.sh' '-lead.sh' "quo'te.sh" "$(printf 'ta\tb.sh')" "$(printf 'new\nline.sh')"; do
    printf '#!/bin/sh\nrm -rf $1\n' >"$R/pkg_$nm"
done
head; gate
P1=$(sc 'sorted(f["file"] for f in e.get("findings", []) if f["rule"] == "SC2086")')
P1N=$(python3 -c 'import sys;print(len(eval(sys.argv[1])))' "$P1" 2>/dev/null)
[ "$RC" -eq 1 ] && [ "$P1N" = "6" ] && [ "$(sc 'd["provenance"]["head_sha_source"]')" = "batch-binding-verified" ] \
    && ok "P1 special paths: e-acute / space / leading '-' / quote / tab / newline names are all bound and linted (6 SC2086 on the real names)" \
    || bad "P1 special paths: rc=$RC n=$P1N files=$P1 $(head -c 300 "$R.stderr")"

# =============================================================================
# E. tool environment: SHELLCHECK_OPTS / HOME / XDG rc / planted .shellcheckrc
# =============================================================================
new_case e1; base; wh pkg/a.sh '#!/bin/sh\necho $1\n'; head
mkdir -p "$TMP/home/.config"; printf 'disable=all\n' >"$TMP/home/.shellcheckrc"; printf 'disable=all\n' >"$TMP/home/.config/shellcheckrc"
OLDHOME=$HOME
export SHELLCHECK_OPTS="--exclude=SC2086 --severity=error" HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/home/.config"
gate
export HOME="$OLDHOME"; unset SHELLCHECK_OPTS XDG_CONFIG_HOME
[ "$RC" -eq 1 ] && [ "$(rules)" = "['SC2086']" ] \
    && ok "E1 env scrub: SHELLCHECK_OPTS=--exclude, a HOME and an XDG shellcheckrc with disable=all cannot hide SC2086" \
    || bad "E1 env scrub: rc=$RC rules=$(rules)"
E1T=$(sc '(e["tool"]["argv"][0], "MemoryMax=8192M" in e["tool"]["argv"], "MemorySwapMax=0" in e["tool"]["argv"], "--norc" in e["tool"]["argv"], e["tool"]["argv"][-1], bool(e["tool"]["version"]), e["tool"]["timeout_s"], e["tool"]["memory_cap_mib"], e["tool"]["max_lines"], d["provenance"]["shellcheck_version"] == e["tool"]["version"])')
[ "$E1T" = "('systemd-run', True, True, True, '-', True, 60, 8192, 10000, True)" ] \
    && ok "E1b evidence: systemd-run scope cap argv (MemoryMax=8192M, MemorySwapMax=0), --norc, stdin, version (also in provenance), 60 s budget and caps are recorded" \
    || bad "E1b evidence: $E1T"

new_case e2; base; wh pkg/a.sh '#!/bin/sh\necho $1\n'; wh pkg/.shellcheckrc 'disable=all\n'; wh .shellcheckrc 'disable=all\n'; head; gate
[ "$RC" -eq 1 ] && [ "$(rules)" = "['SC2086']" ] && [ "$(sc 'sorted(e.get("shellcheckrc_ignored_by_norc", []))')" = "['.shellcheckrc', 'pkg/.shellcheckrc']" ] \
    && ok "E2 planted .shellcheckrc (disable=all, next to the script and at the root) changes nothing (--norc) and is listed" \
    || bad "E2 planted rc: rc=$RC rules=$(rules) rc=$(sc 'e.get("shellcheckrc_ignored_by_norc")')"

# =============================================================================
# X. candidate selection + dialect
# =============================================================================
new_case x1; base; wh bin/tool '#!/usr/bin/env bash\necho $1\n'; wh bin/tool2 '#!/usr/bin/env -S bash -e\necho $1\n'; head; gate
[ "$RC" -eq 1 ] && [ "$(sc 'sorted({f["file"] for f in e.get("findings", [])})')" = "['bin/tool', 'bin/tool2']" ] \
    && ok "X1 extension-less scripts (#!/usr/bin/env bash, env -S) are candidates and FAIL" || bad "X1 rc=$RC $(rules)"

new_case x2; wb bin/runme '#!/bin/sh\necho "$1"\n'; base; wh bin/runme 'echo $1\n'; head; gate
[ "$RC" -eq 1 ] && [ "$(rules)" = "['SC2086']" ] \
    && ok "X2 shebang removal: a file whose BASE blob was a shell script stays a candidate after losing its shebang" \
    || bad "X2 shebang removal: rc=$RC rules=$(rules)"

new_case x3; base; wh docs/notes.md 'echo $1 is not code\n'; wh data.txt '#!not a shell\n'; head; gate
[ "$RC" -eq 0 ] && [ "$(sc 'e["counts"]["files_linted"]')" = "0" ] \
    && ok "X3 non-shell files (markdown, text) are not linted => PASS" || bad "X3 rc=$RC $(sc 'e["counts"]')"

X4BODY='# one\n# two\n# three\n# four\n# five\n# six\n# seven\n# eight\n'
new_case x4; wb pkg/old.sh "#!/bin/sh\n${X4BODY}echo \"\$1\"\n"; base; git -C "$R" mv pkg/old.sh pkg/renamed >/dev/null 2>&1
printf '%b' "${X4BODY}echo \$1\n" >"$R/pkg/renamed"; head; gate
[ "$RC" -eq 1 ] && [ "$(rules)" = "['SC2086']" ] \
    && ok "X4 rename + shebang removal: the BASE blob is followed through the rename, the file stays a candidate" \
    || bad "X4 rename: rc=$RC rules=$(rules) $(sc 'e.get("renames")')"

new_case x5; base; wh pkg/plain.bash 'echo $1\n'; head; gate
[ "$RC" -eq 1 ] && [ "$(sc 'sorted({f["file"] for f in e.get("findings", [])})')" = "['pkg/plain.bash']" ] \
    && ok "X5 a .bash file WITHOUT a shebang is a candidate (extension) and FAILs" || bad "X5 rc=$RC $(rules)"

new_case x6; base; wh bin/bb '#!/bin/busybox sh\necho $1\n'; wh bin/b5 '#!/usr/bin/bash5\necho $1\n'; wh bin/tb '#!/usr/bin/env toybox sh\necho $1\n'; head; gate
[ "$RC" -eq 1 ] && [ "$(sc 'sorted({f["file"] for f in e.get("findings", [])})')" = "['bin/b5', 'bin/bb', 'bin/tb']" ] \
    && ok "X6 '#!/bin/busybox sh', '#!/usr/bin/bash5' and 'env toybox sh' shebangs are candidates and FAIL" || bad "X6 rc=$RC $(sc 'e["counts"], e.get("findings")')"

new_case x7; base
wh pkg/android.sh '#!/system/bin/sh\nf() { local x=1; echo -n "$x"; }\nf\n'
head; gate
X7A=$RC
new_case x7b; base; wh pkg/posix.sh '#!/bin/sh\nf() { local x=1; echo "$x"; }\nf\n'; head; gate
[ "$X7A" -eq 0 ] && [ "$RC" -eq 1 ] && [ "$(rules)" = "['SC3043']" ] \
    && ok "X7 dialect: '#!/system/bin/sh' (Android mksh, probed) is linted as ksh -- local/echo -n PASS -- while '#!/bin/sh' local FAILs (SC3043)" \
    || bad "X7 dialect: android rc=$X7A posix rc=$RC rules=$(rules)"

# =============================================================================
# Y. symlinks
# =============================================================================
new_case y1; wb pkg/clean.sh '#!/bin/sh\necho "c"\n'; base; ln -s clean.sh "$R/pkg/link.sh"; head; gate
[ "$RC" -eq 1 ] && [ "$(sc 'e.get("symlinks_refused")')" = "['pkg/link.sh']" ] \
    && ok "Y1 a symlinked SCRIPT candidate (pkg/link.sh -> clean.sh) FAILs" || bad "Y1 rc=$RC $(sc 'e.get("symlinks_refused"), e.get("symlinks_ignored")')"

new_case y2; base; ln -s README.md "$R/doc.md"; wh pkg/clean.sh '#!/bin/sh\necho "c"\n'; head; gate
[ "$RC" -eq 0 ] && [ "$(sc 'e.get("symlinks_ignored")')" = "['doc.md']" ] \
    && ok "Y2 a symlinked DOCS file in the batch does not block; it is listed in evidence" || bad "Y2 rc=$RC $(sc 'e.get("symlinks_ignored"), e.get("errors")')"

new_case y3; wb bin/runme '#!/bin/sh\necho "$1"\n'; base; rm "$R/bin/runme"; printf '#!/bin/sh\necho hi\n' >"$R/target.txt"; ln -s ../target.txt "$R/bin/runme"; head; gate
[ "$RC" -eq 1 ] && [ "$(sc 'e.get("symlinks_refused")')" = "['bin/runme']" ] \
    && ok "Y3 a former shell script replaced by a symlink is still a script candidate => FAIL" || bad "Y3 rc=$RC $(sc 'e.get("symlinks_refused"), e.get("symlinks_ignored")')"

# =============================================================================
# Z. CRLF and NUL
# =============================================================================
new_case z1; base; wh pkg/crlf.sh '#!/bin/sh\r\necho "x"\r\n'; head; gate
[ "$RC" -eq 1 ] && case "$(rules)" in *SC1017*) true ;; *) false ;; esac \
    && ok "Z1 a CRLF script FAILs (SC1017)" || bad "Z1 CRLF: rc=$RC rules=$(rules)"
new_case z2; base; printf '#!/bin/sh\n# \000\necho "x"\n' >"$R/pkg_nul.sh"; head; gate
[ "$RC" -eq 1 ] && has_err "NUL byte" \
    && ok "Z2 a script containing a NUL byte FAILs (refused, never a partial lint)" || bad "Z2 NUL: rc=$RC $(sc 'e.get("errors")')"

# =============================================================================
# D. directives (honoured by shellcheck, policed by the gate). A fixture whose
# directive is indented or trailing writes its '#' as \0043 (printf %b) so this
# file's own source carries no directive-shaped line the gate would police.
# =============================================================================
dcase() { # <name> <script body after shebang> -> RC, viol
    new_case "$1"; base; wh pkg/d.sh "#!/bin/sh\n$2"; head; gate
}
dcase d1 '# shellcheck disable=all # suppress everything for this legacy helper\necho $1\n'
[ "$RC" -eq 1 ] && [ "$(viol)" = "D1" ] && ok "D1 disable=all FAILs even with a justification" || bad "D1: rc=$RC viol=$(viol)"
dcase d1b '# shellcheck disable=SC2086,ALL # suppress everything for this legacy helper\necho $1\n'
[ "$RC" -eq 1 ] && [ "$(viol)" = "D1" ] && ok "D1b disable=...,ALL (list position, case) FAILs" || bad "D1b: rc=$RC viol=$(viol)"
dcase d1i '    \0043 shellcheck disable=all # suppress everything for this legacy helper\necho $1\n'
[ "$RC" -eq 1 ] && [ "$(viol)" = "D1" ] && ok "D1i an INDENTED disable=all (shellcheck honours it) is policed and FAILs" || bad "D1i: rc=$RC viol=$(viol)"
dcase d1tab '\t#\tshellcheck\tdisable=all # suppress everything for this legacy helper\necho $1\n'
[ "$RC" -eq 1 ] && [ "$(viol)" = "D1" ] && ok "D1tab a TAB-indented, tab-separated disable=all is policed and FAILs" || bad "D1tab: rc=$RC viol=$(viol)"
dcase d1t 'if true; then \0043 shellcheck disable=all # suppress everything inside this block\n  echo $1\nfi\n'
[ "$RC" -eq 1 ] && [ "$(viol)" = "D1" ] && ok "D1t a TRAILING directive after code (then + the disable=all directive, honoured by shellcheck) is policed and FAILs" || bad "D1t: rc=$RC viol=$(viol)"
dcase d2 '# shellcheck disable=SC2000-SC2999 # range covering everything else here\necho "$1"\n'
[ "$RC" -eq 1 ] && [ "$(viol)" = "D2" ] && ok "D2 a range form (SC2000-SC2999) FAILs" || bad "D2: rc=$RC viol=$(viol)"
dcase d2b '# shellcheck disable=2000-2999 # range covering everything else here\necho "$1"\n'
[ "$RC" -eq 1 ] && [ "$(viol)" = "D2" ] && ok "D2b a bare-number range form FAILs" || bad "D2b: rc=$RC viol=$(viol)"
dcase d3 '# shellcheck extended-analysis=false\necho "$1"\n'
[ "$RC" -eq 1 ] && [ "$(viol)" = "D3" ] && ok "D3 extended-analysis=false (hides data-flow findings) FAILs" || bad "D3: rc=$RC viol=$(viol)"
dcase d3b '# shellcheck extended-analysis=true\necho "$1"\n'
[ "$RC" -eq 0 ] && ok "D3b extended-analysis=true is allowed (negative control)" || bad "D3b: rc=$RC viol=$(viol)"
dcase d4 '# shellcheck frobnicate=1\necho "$1"\n'
[ "$RC" -eq 1 ] && [ "$(viol)" = "D4" ] && ok "D4 an unknown directive key FAILs" || bad "D4: rc=$RC viol=$(viol)"
dcase d5 '# shellcheck disable=SC2086\necho $1\n'
[ "$RC" -eq 1 ] && [ "$(viol)" = "D5" ] && [ "$(rules)" = "[]" ] \
    && ok "D5 disable= with NO justification FAILs (the finding itself is hidden -- the directive is what fails)" || bad "D5: rc=$RC viol=$(viol) rules=$(rules)"
dcase d5a '# word splitting of the flag list is intended here\n# shellcheck disable=SC2086\necho $1\n'
[ "$RC" -eq 1 ] && [ "$(viol)" = "D5" ] && ok "D5a a justification on the line ABOVE is NOT accepted" || bad "D5a: rc=$RC viol=$(viol)"
for ph in x TODO noise ok '   ' 'ok ok ok ok ok ok' 'see above' 'intentionally intentionally intentionally' 'qwerty asdfgh' 'zxcvbnm qwrtpsd fghjklz xcvbnmq'; do
    dcase "d5p$(printf '%s' "$ph" | tr -c 'a-zA-Z' '_')" "# shellcheck disable=SC2086 # $ph\necho \$1\n"
    [ "$RC" -eq 1 ] && [ "$(viol)" = "D5" ] && ok "D5p weak justification '$ph' FAILs" || bad "D5p '$ph': rc=$RC viol=$(viol)"
done
dcase d5res '# shellcheck disable=SC2086 # qwerty asdfgh uiopkl\necho $1\n'
[ "$RC" -eq 0 ] && ok "D5res RESIDUAL (stated, not closed): vowel-bearing keyboard mash ('qwerty asdfgh uiopkl') passes D5 -- adequacy is review territory" || bad "D5res: rc=$RC viol=$(viol)"
dcase d6 '# shellcheck disable=SC2086 # word splitting of the flag list is intended here\necho $1\n'
D6=$(sc '[(x["line"], x["justification"], x["violations"]) for x in e.get("directives", [])]')
[ "$RC" -eq 0 ] && [ "$D6" = "[(2, 'word splitting of the flag list is intended here', [])]" ] \
    && ok "D6 a same-line real justification is accepted, honoured, and the directive is listed in evidence" || bad "D6: rc=$RC $D6"
dcase d7 'cat <<EOF\n# shellcheck disable=SC2086\nEOF\n'
[ "$RC" -eq 1 ] && [ "$(viol)" = "D5" ] \
    && ok "D7 residual (stricter by design): a here-doc line SHAPED like an unjustified directive is policed too" || bad "D7: rc=$RC viol=$(viol)"

# =============================================================================
# H. host-safety caps (B1) and tool failures
# =============================================================================
new_case h1; base; wh pkg/long.sh "#!/bin/sh\n$(i=0; while [ $i -lt 30 ]; do printf 'echo "line %s"\\n' $i; i=$((i+1)); done)"; head; gate --shellcheck-max-lines 10
[ "$RC" -eq 1 ] && has_err "exceeds the size cap" && [ "$(sc 'e["counts"]["files_linted"]')" = "0" ] \
    && ok "H1 a candidate over the SIZE cap is BLIND (fails closed) and shellcheck is never started" || bad "H1 size cap: rc=$RC $(sc 'e.get("errors"), e["counts"]')"
gate_run --shellcheck-max-lines 99999
H1B=$RC; gate_run --shellcheck-memory-cap-mib 999999
[ "$H1B" -eq 2 ] && [ "$RC" -eq 2 ] && ok "H1b a cap can be LOWERED per run, never raised (a higher --shellcheck-max-lines / --shellcheck-memory-cap-mib exits 2)" \
    || bad "H1b raising a cap: rc=$H1B/$RC"

new_case h2; base
python3 -c 'import sys;open(sys.argv[1],"w").write("#!/bin/sh\n"+"".join("x%d=\"$1\"; echo \"$x%d\"\n"%(i,i) for i in range(3000)))' "$R/pkg_mem.sh"
head; gate --shellcheck-memory-cap-mib 16
[ "$RC" -eq 1 ] && has_err "16 MiB memory cap" && has_err "BLIND" \
    && ok "H2 a lint killed by the hard memory cap (16 MiB) is BLIND and FAILs closed -- never PASS" || bad "H2 memory cap: rc=$RC $(sc 'e.get("errors")')"

FAKE="$TMP/fakebin"; mkdir -p "$FAKE"
printf '#!/bin/sh\n# a "systemd-run" that runs the command WITHOUT any cap\nwhile [ "$#" -gt 0 ] && [ "$1" != "--" ]; do shift; done\nshift\nexec "$@"\n' >"$FAKE/systemd-run"; chmod +x "$FAKE/systemd-run"
new_case h3; base; wh pkg/a.sh '#!/bin/sh\necho "fine"\n'; head
OLDPATH=$PATH; PATH="$FAKE:$PATH"; gate; PATH=$OLDPATH
[ "$RC" -eq 1 ] && has_err "no hard memory cap" && [ "$(sc 'e["counts"]["files_linted"]')" = "0" ] \
    && ok "H3 a cap wrapper that does NOT enforce MemoryMax (pass-through systemd-run) is detected by the probe => BLIND, nothing linted" \
    || bad "H3 unenforced cap: rc=$RC $(sc 'e.get("errors")')"

SCF="$TMP/fakesc"; mkdir -p "$SCF"
printf '#!/bin/sh\ncase "$*" in *--version*) echo "version: 9.9.9"; exit 0 ;; esac\ncat >/dev/null\necho "{\\"comments\\":[]}"\nexit 3\n' >"$SCF/shellcheck"; chmod +x "$SCF/shellcheck"
new_case h5; base; wh pkg/a.sh '#!/bin/sh\necho $1\n'; head
PATH="$SCF:$OLDPATH"; gate; PATH=$OLDPATH
[ "$RC" -eq 1 ] && has_err "exited 3" \
    && ok "H5 a shellcheck that prints clean json but exits 3 is a TOOL FAILURE (BLIND), never 'clean'" || bad "H5 tool failure: rc=$RC $(sc 'e.get("errors")')"
SCF2="$TMP/fakesc2"; mkdir -p "$SCF2"
printf '#!/bin/sh\ncase "$*" in *--version*) echo "version: 9.9.9"; exit 0 ;; esac\ncat >/dev/null\nexit 0\n' >"$SCF2/shellcheck"; chmod +x "$SCF2/shellcheck"
new_case h5b; base; wh pkg/a.sh '#!/bin/sh\necho $1\n'; head
PATH="$SCF2:$OLDPATH"; gate; PATH=$OLDPATH
[ "$RC" -eq 1 ] && has_err "no json1 output" \
    && ok "H5b a shellcheck that exits 0 with NO output is BLIND (silence is not 'clean')" || bad "H5b silent tool: rc=$RC $(sc 'e.get("errors")')"

LOCKP=$(python3 -c 'import os;b=os.environ.get("XDG_RUNTIME_DIR");b=b if b and os.path.isdir(b) else "/tmp";print(os.path.join(b,"helix-precheck-shellcheck-large-%d.lock"%os.getuid()))')
python3 -c 'import fcntl,sys,time;f=open(sys.argv[1],"a");fcntl.flock(f.fileno(),fcntl.LOCK_EX);open(sys.argv[2],"w").close();time.sleep(60)' "$LOCKP" "$TMP/holder.ready" &
HOLDER_PID=$!
i=0; while [ ! -f "$TMP/holder.ready" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done
new_case h6; mkdir -p "$R/config"; printf 'vendor/big.sh\tvendored\tATM-1234\tSC2086=1\t2026-10-09\n' >"$R/config/shellcheck_legacy_exceptions.tsv"
wb vendor/big.sh '#!/bin/sh\necho $1\n'; base; wh vendor/big.sh '#!/bin/sh\necho $1\n# edited\n'; head; gate --shellcheck-exception-timeout 0.5
H6A=$RC; H6E=$(sc 'e.get("errors")')
kill "$HOLDER_PID" 2>/dev/null; wait "$HOLDER_PID" 2>/dev/null; HOLDER_PID=""
gate_run --shellcheck-exception-timeout 0.5
case "$H6E" in *"lock"*"still held"*) H6OK=1 ;; *) H6OK=0 ;; esac
[ "$H6A" -eq 1 ] && [ "$H6OK" -eq 1 ] && [ "$RC" -eq 0 ] && [ "$(sc 'e["tool"]["lock"]')" = "$LOCKP" ] \
    && ok "H6 legacy-exception lints are serialised by the host-wide flock ($LOCKP): BLIND while another holder has it, PASS once released" \
    || bad "H6 lock: held rc=$H6A ($H6E) released rc=$RC $(sc 'e.get("errors"), e["tool"].get("lock")')"

# =============================================================================
# B. binding + gitlinks
# =============================================================================
new_case b1; base; wh pkg/a.sh '#!/bin/sh\necho "a"\n'; head; gate_prepare
printf 'tampered\n' >>"$R.co/pkg/a.sh"; gate_run
[ "$RC" -eq 1 ] && [ "$(sc 'e["binding"]["state"], d["provenance"]["head_sha_source"]')" = "('binding-failed', 'binding-failed')" ] \
    && ok "B1 a checkout whose bytes differ from the bound head => binding-failed, FAIL" || bad "B1 rc=$RC $(sc 'e["binding"]')"

new_case b2; mkdir -p "$R/pkg"; printf '#!/bin/sh\necho $1\n' >"$R/pkg/a.sh"
mkbatch_unbound() { python3 -c 'import json,sys;json.dump({"batch_id":"RB-B2","changes":[],"related_by":"x","total_changed_lines":1,"slices":[{"slice_id":"S1","lines":1,"context_pack":{"intent":"f","changed_paths":sys.argv[2:],"blast_radius":"%d changed path(s) in this slice: %s"%(len(sys.argv[2:]),", ".join(sys.argv[2:]))}}]},open(sys.argv[1],"w"))' "$@"; }
mkbatch_unbound "$R.batch.json" pkg/a.sh; OUT="$R.out.json"
sh "$REVIEW/precheck_pack.sh" --batch "$R.batch.json" --clean-checkout "$R" --out "$OUT" >/dev/null 2>&1; RC=$?
[ "$RC" -eq 1 ] && [ "$(rules)" = "['SC2086']" ] && [ "$(sc 'e["binding"]["state"]')" = "unbound" ] \
    && ok "B2 an unbound (legacy) run is still whole-file strict and records binding=unbound (never dispatch-ready)" || bad "B2 rc=$RC $(rules)"

new_case b3; base; wh pkg/a.sh '#!/bin/sh\necho "a"\n'; head
SIDE=$(git -C "$R" commit-tree "$(git -C "$R" rev-parse "$BASE^{tree}")" -m side </dev/null 2>/dev/null)
gate_prepare
python3 - "$R.batch.json" "$SIDE" <<'PY'
import json, sys
b = json.load(open(sys.argv[1])); b["binding"]["base_sha"] = sys.argv[2]; json.dump(b, open(sys.argv[1], "w"))
PY
BASE_KEEP=$BASE; BASE=$SIDE; gate_run; BASE=$BASE_KEEP
[ "$RC" -eq 1 ] && has_err "is not an ancestor of head" \
    && ok "B3 the GATE itself refuses a binding whose base is not an ancestor of head (independent of the dispatch verifier)" || bad "B3 ancestry: rc=$RC $(sc 'e.get("errors")')"

new_case b4; base; wh pkg/a.sh '#!/bin/sh\necho "a"\n'; head; gate_prepare
python3 - "$R.batch.json" <<'PY'
import json, sys
b = json.load(open(sys.argv[1])); b["changes"] = ["sha256:" + "0" * 64]; json.dump(b, open(sys.argv[1], "w"))
PY
gate_run
[ "$RC" -eq 1 ] && has_err "binding change_ids differ from batch.changes" \
    && ok "B4 the GATE itself refuses a batch whose changes differ from the binding's change_ids" || bad "B4 change_ids: rc=$RC $(sc 'e.get("errors")')"

new_case b5; SUBR="$TMP/b5sub"; mkdir -p "$SUBR"
( cd "$SUBR" && git init -q . && $GIT commit -q --allow-empty -m s1 && $GIT commit -q --allow-empty -m s2 ) >/dev/null 2>&1
S1=$(git -C "$SUBR" rev-parse HEAD~1); S2=$(git -C "$SUBR" rev-parse HEAD)
( cd "$R" && git init -q . && git update-index --add --cacheinfo "160000,$S1,sub" && $GIT add README.md && $GIT commit -q -m base ) >/dev/null 2>&1
BASE=$(git -C "$R" rev-parse HEAD)
( cd "$R" && git update-index --cacheinfo "160000,$S2,sub" && mkdir -p pkg && printf '#!/bin/sh\necho "x"\n' >pkg/a.sh && $GIT add pkg/a.sh && $GIT commit -q -m head ) >/dev/null 2>&1
HEADC=$(git -C "$R" rev-parse HEAD); gate
[ "$RC" -eq 0 ] && [ "$(sc "e.get('gitlinks') == [{'path': 'sub', 'commit': '$S2'}] and e['binding']['state'] == 'bound'")" = "True" ] \
    && ok "B5 a batch that bumps a gitlink (mode 160000) is bound; the pointer is listed as a non-shell gitlink (I4)" || bad "B5 gitlink: rc=$RC $(sc 'e.get("gitlinks"), e.get("errors")')"

new_case b6; mkdir -p "$R/pkg"; printf '#!/bin/sh\necho "fine"\n' >"$R/pkg/a.sh"
mkbatch_unbound "$R.batch.json" pkg pkg/a.sh; OUT="$R.out.json"
sh "$REVIEW/precheck_pack.sh" --batch "$R.batch.json" --clean-checkout "$R" --out "$OUT" >/dev/null 2>&1; RC=$?
[ "$RC" -eq 1 ] && has_err "directories but not bound gitlinks" \
    && ok "B6 a declared DIRECTORY that is not a bound gitlink is refused (never silently skipped)" || bad "B6 dir: rc=$RC $(sc 'e.get("errors")')"

# =============================================================================
# L. legacy exceptions (canonical checked-in TSV, base-compared, per-rule ratchet)
# =============================================================================
TAB=$(printf '\t')
TSV=config/shellcheck_legacy_exceptions.tsv
row() { printf '%s\t%s\t%s\t%s\t%s\n' "$@"; }
lcase2() { # <name> <script rel> <base body> <head body> <base tsv rows> <head tsv rows> [gate args]
    n=$1; rel=$2; bb=$3; hb=$4; brows=$5; hrows=$6; shift 6
    new_case "$n"; mkdir -p "$R/config"; printf '%s' "$brows" >"$R/$TSV"
    wb "$rel" "#!/bin/sh\n$bb"; base
    printf '%s' "$hrows" >"$R/$TSV"
    wh "$rel" "#!/bin/sh\n$hb"; head; gate "$@"
}
lcase() { # <name> <head body> <tsv rows (base == head)> [gate args] -- script vendor/big.sh
    n=$1; hb=$2; rows=$3; shift 3
    lcase2 "$n" vendor/big.sh '# base\n' "$hb" "$rows" "$rows" "$@"
}
TWO='echo $1\necho $2\n'
lcase l1 "$TWO" "$(row vendor/big.sh vendored ATM-1234 SC2086=1 2026-10-09)"
[ "$RC" -eq 1 ] && [ "$(sc 'e["legacy_exceptions"][0]["verdict"], e["legacy_exceptions"][0]["over_pin"]')" = "('FAIL', {'SC2086': {'now': 2, 'pinned': 1}})" ] \
    && ok "L1 ratchet: a rule count ABOVE its pin FAILs" || bad "L1 rc=$RC $(sc 'e.get("legacy_exceptions"), e.get("errors")')"
lcase l2 "# Generated by the fixture tool -- do not edit\n$TWO" "$(row vendor/big.sh generated ATM-1234 SC2086=3 2026-10-09)"
[ "$RC" -eq 0 ] && [ "$(sc 'e["legacy_exceptions"][0]["lowered"]')" = "{'SC2086': {'now': 2, 'pinned': 3}}" ] \
    && ok "L2 ratchet: a count BELOW its pin PASSes and is reported as lowerable (generated row WITH its marker)" || bad "L2 rc=$RC $(sc 'e.get("legacy_exceptions"), e.get("errors")')"
lcase l3 "$TWO" "$(row vendor/big.sh vendored ATM-1234 SC2086=2 2026-10-09)"
[ "$RC" -eq 0 ] && ok "L3 ratchet: counts EQUAL to the pin PASS" || bad "L3 rc=$RC $(sc 'e.get("legacy_exceptions"), e.get("errors")')"
lcase l4 "${TWO}unused=1\n" "$(row vendor/big.sh vendored ATM-1234 SC2086=2 2026-10-09)"
[ "$RC" -eq 1 ] && [ "$(sc 'sorted(e["legacy_exceptions"][0]["over_pin"])')" = "['SC2034']" ] \
    && ok "L4 ratchet: a NEW blocking rule absent from the pin FAILs" || bad "L4 rc=$RC $(sc 'e.get("legacy_exceptions")')"
lcase l4b "${TWO}x=\`date\`\necho \"\$x\"\n" "$(row vendor/big.sh vendored ATM-1234 SC2086=2 2026-10-09)"
[ "$RC" -eq 0 ] && [ "$(sc 'sorted({f["rule"] for f in e.get("advisory_findings", [])}), e["legacy_exceptions"][0]["counts"]')" = "(['SC2006'], {'SC2086': 2})" ] \
    && ok "L4b an ADVISORY rule (SC2006 style) in a listed file is listed but neither counted nor failing" || bad "L4b rc=$RC $(sc 'e.get("legacy_exceptions"), e.get("advisory_findings")')"
lcase l5 "$TWO" "$(row vendor/big.sh vendored ATM-1234 SC2086=2 2026-10-09)" --shellcheck-exception-timeout 0.0001
[ "$RC" -eq 1 ] && [ "$(sc 'e["legacy_exceptions"][0]["verdict"], e["tool"]["exception_timeout_s"]')" = "('BLIND', 0.0001)" ] \
    && ok "L5 a listed file over even the larger timeout FAILs closed (BLIND), timeout recorded" || bad "L5 rc=$RC $(sc 'e.get("legacy_exceptions")')"
lcase2 l6 pkg/big.sh '# base\n' "$TWO" "$(row vendor/other.sh vendored ATM-1234 SC2086=9 2026-10-09)" "$(row vendor/other.sh vendored ATM-1234 SC2086=9 2026-10-09)"
[ "$RC" -eq 1 ] && [ "$(rules)" = "['SC2086']" ] && [ "$(sc 'e.get("legacy_exceptions")')" = "None" ] \
    && ok "L6 an UNLISTED file is plain whole-file strict even when an exception file exists" || bad "L6 rc=$RC $(rules) $(sc 'e.get("errors")')"
new_case l6b; base; wh pkg/a.sh '#!/bin/sh\necho "x"\n'; head; gate --shellcheck-timeout 0.0001
[ "$RC" -eq 1 ] && case "$(sc 'e.get("errors")')" in *"exceeded its 0.0001s budget"*"legacy-exception"*) true ;; *) false ;; esac \
    && ok "L6b an unlisted file over the normal budget FAILs (pointing at the exception mechanism)" || bad "L6b rc=$RC $(sc 'e.get("errors")')"
lcase l7 "$TWO" "vendor/big.sh${TAB}vendored${TAB}ATM-1234${TAB}SC2086=2
"
[ "$RC" -eq 1 ] && has_err "want 5 tab-separated fields" && ok "L7 a malformed row (4 fields) is rejected => FAIL" || bad "L7 rc=$RC $(sc 'e.get("errors")')"
lcase l8 "$TWO" "vendor/big.sh${TAB}vendored${TAB}${TAB}SC2086=2${TAB}2026-10-09
"
[ "$RC" -eq 1 ] && has_err "tracked_item" && ok "L8 a row WITHOUT a tracked item is rejected => FAIL" || bad "L8 rc=$RC $(sc 'e.get("errors")')"
lcase l9 "$TWO" "$(row vendor/big.sh because-i-said-so ATM-1234 SC2086=2 2026-10-09)"
[ "$RC" -eq 1 ] && has_err "reason_class" && ok "L9 a reason_class outside the closed set is rejected => FAIL" || bad "L9 rc=$RC $(sc 'e.get("errors")')"
lcase l10 "# shellcheck disable=SC2086\n$TWO" "$(row vendor/big.sh vendored ATM-1234 - 2026-10-09)"
[ "$RC" -eq 1 ] && [ "$(sc 'sorted(e["legacy_exceptions"][0]["over_pin"])')" = "['DIR-UNJUSTIFIED']" ] \
    && ok "L10 an unjustified directive in a listed file is ratcheted as DIR-UNJUSTIFIED (new => FAIL)" || bad "L10 rc=$RC $(sc 'e.get("legacy_exceptions")')"
lcase l11 "$TWO" "$(row vendor/big.sh vendored ATM-77 SC2086=2 2026-10-09)"
L11=$(sc '(e["exceptions_file"]["path"], e["exceptions_file"]["rows"], len(e["exceptions_file"]["head_blob_sha256"]), e["exceptions_file"]["head_blob_sha256"] == e["exceptions_file"]["base_blob_sha256"], e["legacy_exceptions"][0]["tracked_item"], d["provenance"]["exceptions"] == e["exceptions_file"])')
[ "$RC" -eq 0 ] && [ "$L11" = "('config/shellcheck_legacy_exceptions.tsv', 1, 64, True, 'ATM-77', True)" ] \
    && ok "L11 the exceptions file is recorded REPO-RELATIVE with head + base blob sha256 in evidence AND provenance" || bad "L11 rc=$RC $L11"
lcase l12 "$TWO" "$(row vendor/big.sh vendored ATM-1234 SC2086=x 2026-10-09)"
[ "$RC" -eq 1 ] && has_err "bad pinned_counts" && ok "L12 a malformed pinned_counts entry is rejected => FAIL" || bad "L12 rc=$RC $(sc 'e.get("errors")')"
THREE='echo $1\necho $2\necho $3\n'
lcase2 l13 vendor/big.sh '# base\n' "$THREE" "$(row vendor/big.sh vendored ATM-1234 SC2086=2 2026-10-09)" "$(row vendor/big.sh vendored ATM-1234 SC2086=3 2026-10-09)"
[ "$RC" -eq 1 ] && has_err "INCREASED versus the base TSV" \
    && ok "L13 (A2) raising a pin in the HEAD TSV while also changing the script FAILs (the BASE TSV is the reference)" || bad "L13 rc=$RC $(sc 'e.get("errors")')"
new_case l13b; mkdir -p "$R/config"; row vendor/big.sh vendored ATM-1234 SC2086=2 2026-10-09 >"$R/$TSV"; wb vendor/big.sh "#!/bin/sh\n$THREE"; base
row vendor/big.sh vendored ATM-1234 SC2086=3 2026-10-09 >"$R/$TSV"; head; gate
[ "$RC" -eq 0 ] && [ "$(sc 'e["exceptions_increase"] == [{"path": "vendor/big.sh", "kind": "raised-pin", "raised": {"SC2086": {"base": 2, "head": 3}}}] and e["exceptions_file"]["tsv_only_batch"]')" = "True" ] \
    && ok "L13b the same raise in an explicit TSV-only batch is accepted and LISTED (exceptions_increase) for the reviewer/operator" || bad "L13b rc=$RC $(sc 'e.get("exceptions_increase"), e.get("errors")')"
lcase2 l14 vendor/big.sh '# base\n' "$TWO" '' "$(row vendor/big.sh vendored ATM-1234 SC2086=2 2026-10-09)"
[ "$RC" -eq 1 ] && has_err "new-row" \
    && ok "L14 a NEW row in the head TSV in a batch that also changes the script FAILs" || bad "L14 rc=$RC $(sc 'e.get("errors")')"
lcase l15 "$TWO" "$(row vendor/big.sh vendored ATM-1234 SC2086=2 2026-10-09)" --shellcheck-exceptions ../lax.tsv
[ "$RC" -eq 2 ] && grep -q "canonical" "$R.stderr" \
    && ok "L15 a bound run refuses any exceptions path but the canonical one ('../lax.tsv' => exit 2)" || bad "L15 rc=$RC $(head -c 200 "$R.stderr")"
new_case l16; mkdir -p "$R/config"; row vendor/big.sh vendored ATM-1234 SC2086=0 2026-10-09 >"$R/$TSV"; wb vendor/big.sh '#!/bin/sh\n# base\n'; base
wh vendor/big.sh "#!/bin/sh\n$TWO"; head; gate_prepare
row vendor/big.sh vendored ATM-1234 SC2086=9 2026-10-09 >"$R.co/$TSV"; gate_run
[ "$RC" -eq 1 ] && has_err "is not the bound head's blob" \
    && ok "L16 a checkout TSV that differs from the bound head's blob (a lax planted copy) is refused" || bad "L16 rc=$RC $(sc 'e.get("errors")')"
lcase l17a "$TWO" "$(row vendor/big.sh too-large-to-lint-in-budget ATM-1234 SC2086=2 2026-10-09)"
L17A=$RC; L17AE=$(sc 'e.get("errors")')
lcase l17b "$TWO" "$(row vendor/big.sh generated ATM-1234 SC2086=2 2026-10-09)"
L17B=$RC; L17BE=$(sc 'e.get("errors")')
lcase2 l17c pkg/x.sh '# base\n' "$TWO" "$(row pkg/x.sh vendored ATM-1234 SC2086=2 2026-10-09)" "$(row pkg/x.sh vendored ATM-1234 SC2086=2 2026-10-09)"
case "$L17AE" in *"needs >= 5000 lines"*) L17AOK=1 ;; *) L17AOK=0 ;; esac
case "$L17BE" in *"generated-file marker"*) L17BOK=1 ;; *) L17BOK=0 ;; esac
[ "$L17A" -eq 1 ] && [ "$L17AOK" -eq 1 ] && [ "$L17B" -eq 1 ] && [ "$L17BOK" -eq 1 ] && [ "$RC" -eq 1 ] && has_err "vendored path component" \
    && ok "L17 reason_class needs evidence: too-large on a 3-line file, generated without a marker, vendored outside a vendored directory all FAIL" \
    || bad "L17 evidence: $L17A/$L17AE // $L17B/$L17BE // $RC/$(sc 'e.get("errors")')"
lcase l18 "$TWO" "$(row vendor/big.sh vendored ATM-1234 SC2086=2,SC1072=1 2026-10-09)"
[ "$RC" -eq 1 ] && has_err "SC10xx" && ok "L18 an SC10xx (parse-class) code cannot be pinned => FAIL" || bad "L18 rc=$RC $(sc 'e.get("errors")')"
lcase l19 "f() if :; then :; fi\necho \$1\nrm -rf \$HOME/\$3\n" "$(row vendor/big.sh vendored ATM-1234 SC2086=2 2026-10-09)"
[ "$RC" -eq 1 ] && has_err "PARSE error" && [ "$(sc 'sorted(f["rule"] for f in e["legacy_exceptions"][0].get("parse_errors", []))')" = "['SC1064', 'SC1072', 'SC1073']" ] \
    && ok "L19 (A4) a bash-valid but shellcheck-fatal construct in a listed file FAILs closed as a PARSE error (it would hide the analysis of 'rm -rf \$HOME/\$3')" \
    || bad "L19 parse: rc=$RC $(sc 'e.get("errors"), e.get("legacy_exceptions")')"
new_case l20; mkdir -p "$R/config"; row vendor/new.sh vendored ATM-1234 SC2086=2 2026-10-09 >"$R/$TSV"; base
wh vendor/new.sh "#!/bin/sh\n$TWO"; head; gate
[ "$RC" -eq 1 ] && has_err "must cover a file tracked at the batch base" \
    && ok "L20 (A5) a row (already in the base TSV) for a script that is NEW in the batch FAILs -- a new script cannot exempt itself" || bad "L20 rc=$RC $(sc 'e.get("errors")')"
lcase l21 "$TWO" "$(row ../vendor/big.sh vendored ATM-1234 SC2086=2 2026-10-09)"
[ "$RC" -eq 1 ] && has_err "normalised repo-relative path" && ok "L21 a traversing row path ('../vendor/big.sh') is rejected" || bad "L21 rc=$RC $(sc 'e.get("errors")')"
lcase l22 "$TWO" "$(row vendor/big.sh vendored ATM-1234 SC2086=1 2026-10-09)"
[ "$RC" -eq 1 ] && [ "$(sc 'e["legacy_exceptions"][0]["verdict"]')" = "FAIL" ] \
    && ok "L22 a bound run uses the canonical head-tracked TSV even without --shellcheck-exceptions (the producer cannot skip it)" || bad "L22 rc=$RC $(sc 'e.get("legacy_exceptions")')"

# =============================================================================
# MUT. own mutants: each removes ONE mechanism from a scratch copy of the gate;
# the case that only that mechanism catches must flip (default: the shellcheck
# check PASSes; or the given python expression over c/d/e holds).
# =============================================================================
MUTROOT="$TMP/mut"
mutant() { # <id> <old=>>new> <case function> [python expr that must hold after the mutation]
    id=$1; edit=$2; fn=$3; want=${4:-'c["verdict"] == "PASS"'}
    rm -rf "$MUTROOT"; mkdir -p "$MUTROOT/lib"
    cp "$REVIEW/precheck_pack.sh" "$MUTROOT/"; cp "$REVIEW/lib/"*.py "$MUTROOT/lib/"
    if ! python3 - "$MUTROOT/lib/precheck_pack_run.py" "$edit" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old, new = sys.argv[2].split("=>>", 1)
new = new.replace("<NL>", "\n")  # a mutation spanning lines writes <NL> for the newline
if s.count(old) != 1:
    sys.exit("needle found %d times" % s.count(old))
open(p, "w").write(s.replace(old, new))
PY
    then bad "$id mutation setup: needle not found exactly once"; return; fi
    GATE_DIR="$MUTROOT"; $fn; GATE_DIR="$REVIEW"
    MV=$(sc "$want")
    [ "$MV" = "True" ] && ok "$id mutation-flip: with the mechanism removed the golden-bad case flips ($want) -- the mechanism is load-bearing" \
        || bad "$id mutation-flip: '$want' is '$MV' with the mechanism removed (rc=$RC) -- tautological or mutation missed"
}
m_d5() { dcase md5 '# shellcheck disable=SC2086\necho $1\n'; }
m_d1() { dcase md1 '# shellcheck disable=all # suppress everything for this legacy helper\necho $1\n'; }
m_d2() { dcase md2 '# shellcheck disable=SC2000-SC2999 # range covering everything else here\necho "$1"\n'; }
m_d3() { dcase md3 '# shellcheck extended-analysis=false\necho "$1"\n'; }
m_x2() { new_case mx2; wb bin/runme '#!/bin/sh\necho "$1"\n'; base; wh bin/runme 'echo $1\n'; head; gate; }
m_y1() { new_case my1; wb pkg/clean.sh '#!/bin/sh\necho "c"\n'; base; ln -s clean.sh "$R/pkg/link.sh"; head; gate; }
m_e1() { new_case me1; base; wh pkg/a.sh '#!/bin/sh\necho $1\n'; head; export SHELLCHECK_OPTS="--exclude=SC2086"; gate; unset SHELLCHECK_OPTS; }
m_l1() { lcase ml1 "$TWO" "$(row vendor/big.sh vendored ATM-1234 SC2086=1 2026-10-09)"; }
m_l4() { lcase ml4 "${TWO}unused=1\n" "$(row vendor/big.sh vendored ATM-1234 SC2086=2 2026-10-09)"; }
m_l5() { lcase ml5 "$TWO" "$(row vendor/big.sh vendored ATM-1234 SC2086=2 2026-10-09)" --shellcheck-exception-timeout 0.0001; }
m_l8() { lcase ml8 "$TWO" "$(row vendor/big.sh vendored none SC2086=2 2026-10-09)"; }
m_z2() { new_case mz2; base; printf '#!/bin/sh\n# \000\necho "x"\n' >"$R/pkg_nul.sh"; head; gate; }
m_k3() { new_case mk3; base; wh pkg/read.sh '#!/bin/sh\nread line\necho "$line"\n'; head; gate; }
m_h1() { new_case mh1; base; wh pkg/long.sh '#!/bin/sh\necho "1"\necho "2"\necho "3"\necho "4"\n'; head; gate --shellcheck-max-lines 2; }
m_h3() { new_case mh3; base; wh pkg/a.sh '#!/bin/sh\necho "fine"\n'; head; PATH="$FAKE:$OLDPATH"; gate; PATH=$OLDPATH; }
m_h5() { new_case mh5; base; wh pkg/a.sh '#!/bin/sh\necho "fine"\n'; head; PATH="$SCF:$OLDPATH"; gate; PATH=$OLDPATH; }
m_h5b() { new_case mh5b; base; wh pkg/a.sh '#!/bin/sh\necho "fine"\n'; head; PATH="$SCF2:$OLDPATH"; gate; PATH=$OLDPATH; }
m_d1t() { dcase md1t 'if true; then \0043 shellcheck disable=all # suppress everything inside this block\n  echo $1\nfi\n'; }
m_d1i() { dcase md1i '    \0043 shellcheck disable=all # suppress everything for this legacy helper\necho $1\n'; }
m_d5r() { dcase md5r '# shellcheck disable=SC2086 # intentionally intentionally intentionally\necho $1\n'; }
m_x5() { new_case mx5; base; wh pkg/plain.bash 'echo $1\n'; head; gate; }
m_l13() { lcase2 ml13 vendor/big.sh '# base\n' "$THREE" "$(row vendor/big.sh vendored ATM-1234 SC2086=2 2026-10-09)" "$(row vendor/big.sh vendored ATM-1234 SC2086=3 2026-10-09)"; }
m_l17a() { lcase ml17a "$TWO" "$(row vendor/big.sh too-large-to-lint-in-budget ATM-1234 SC2086=2 2026-10-09)"; }
m_l19() { lcase ml19 "f() if :; then :; fi\necho \$1\n" "$(row vendor/big.sh vendored ATM-1234 SC2086=2 2026-10-09)"; }
m_l20() { new_case ml20; mkdir -p "$R/config"; row vendor/new.sh vendored ATM-1234 SC2086=2 2026-10-09 >"$R/$TSV"; base; wh vendor/new.sh "#!/bin/sh\n$TWO"; head; gate; }
m_l21() { lcase ml21 "$TWO" "$(row ../vendor/big.sh vendored ATM-1234 SC2086=2 2026-10-09)"; }
m_l16() { new_case ml16; mkdir -p "$R/config"; row vendor/big.sh vendored ATM-1234 SC2086=2 2026-10-09 >"$R/$TSV"; wb vendor/big.sh '#!/bin/sh\n# base\n'; base
          wh vendor/big.sh "#!/bin/sh\n$TWO"; head; gate_prepare; row vendor/big.sh vendored ATM-1234 SC2086=9 2026-10-09 >"$R.co/$TSV"; gate_run; }
m_b3() { new_case mb3; base; wh pkg/a.sh '#!/bin/sh\necho "a"\n'; head
         SIDE=$(git -C "$R" commit-tree "$(git -C "$R" rev-parse "$BASE^{tree}")" -m side </dev/null 2>/dev/null); gate_prepare
         python3 -c 'import json,sys;b=json.load(open(sys.argv[1]));b["binding"]["base_sha"]=sys.argv[2];json.dump(b,open(sys.argv[1],"w"))' "$R.batch.json" "$SIDE"
         BASE_KEEP=$BASE; BASE=$SIDE; gate_run; BASE=$BASE_KEEP; }
m_b4() { new_case mb4; base; wh pkg/a.sh '#!/bin/sh\necho "a"\n'; head; gate_prepare
         python3 -c 'import json,sys;b=json.load(open(sys.argv[1]));b["changes"]=["sha256:"+"0"*64];json.dump(b,open(sys.argv[1],"w"))' "$R.batch.json"; gate_run; }
m_b6() { new_case mb6; mkdir -p "$R/pkg"; printf '#!/bin/sh\necho "fine"\n' >"$R/pkg/a.sh"; mkbatch_unbound "$R.batch.json" pkg pkg/a.sh; OUT="$R.out.json"
         sh "$GATE_DIR/precheck_pack.sh" --batch "$R.batch.json" --clean-checkout "$R" --out "$OUT" >/dev/null 2>&1; RC=$?; }
mutant M1 '        if "disable" in keys and not _justification_ok(just):=>>        if False:' m_d5
mutant M2 '                    if key == "disable" and code.strip().lower() == "all":=>>                    if False:' m_d1
mutant M3 '                    if _RANGE_RE.match(code.strip()):=>>                    if False:' m_d2
mutant M4 '            if key == "extended-analysis" and val.strip().lower() != "true":=>>            if False:' m_d3
mutant M5 '        return (st == "tracked" and _bytes_are_shell(blob)), st=>>        return False, st' m_x2
mutant M6 '            if _symlink_is_script(path, root, b_shell):=>>            if False:' m_y1
mutant M7 '    return {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": empty, "XDG_CONFIG_HOME": empty,=>>    return {**{k: v for k, v in os.environ.items() if "\n" not in v and "=" not in k}, "HOME": empty, "XDG_CONFIG_HOME": empty,' m_e1
mutant M8 '                if v > row["pinned_counts"].get(k, 0)}=>>                if v > row["pinned_counts"].get(k, 0) + 1000}' m_l1
mutant M9 '                if v > row["pinned_counts"].get(k, 0)}=>>                if k in row["pinned_counts"] and v > row["pinned_counts"][k]}' m_l4
mutant M10 '            errors.append({"file": rel, "message": "legacy exception BLIND (fails closed): " + err})=>>            pass' m_l5
mutant M11 '        if not _ITEM_RE.match(item):=>>        if False:' m_l8
mutant M12 '        if b"\0" in cdata:=>>        if False:' m_z2
mutant M13 '    return c.get("level") in BLOCKING_LEVELS or ("SC%s" % c.get("code")) in BLOCKING_INFO_RULES=>>    return c.get("level") in BLOCKING_LEVELS' m_k3
mutant M14 '        if len(clines) > max_lines or len(cdata) > max_bytes:=>>        if False:' m_h1
mutant M15 '    cap_problem = _probe_cap(mem_cap)=>>    cap_problem = None' m_h3
mutant M16 '    if proc.returncode not in (0, 1):  # 0 clean, 1 findings; anything else is a tool failure=>>    if False:' m_h5
mutant M17 '    if not out.strip():  # json1 always prints {"comments":[...]}; silence is not "clean"=>>    if not out.strip():<NL>        out = "{\"comments\": []}"<NL>    if False:' m_h5b
mutant M18 '        m0 = _DIRECTIVE_RE.search(raw)=>>        m0 = _DIRECTIVE_RE.match(raw)' m_d1t
mutant M19 '_DIRECTIVE_RE = re.compile(r"(?:^|\s)#\s*shellcheck\s")=>>_DIRECTIVE_RE = re.compile(r"^#\s?shellcheck\s")' m_d1i
mutant M20 '    return sum(len(w) for w in words) >= 16 and len(real) >= 3=>>    return sum(len(w) for w in words) >= 16 and len(real) >= 1' m_d5r
mutant M21 '_SHELL_EXTS = (".sh", ".bash", ".ksh", ".dash")=>>_SHELL_EXTS = (".sh",)' m_x5
mutant M22 '        if increase and not exc["tsv_only"]:=>>        if False:' m_l13
mutant M23 '                why = _reason_evidence_error(row, rel, _split_lines(hblob))=>>                why = None' m_l17a
mutant M24 '        if parse_errors:=>>        if False:' m_l19 'not any("PARSE error" in x["message"] for x in e.get("errors", []))'
mutant M25 '            if bst != "tracked":=>>            if False:' m_l20
mutant M26 '".." in rpath.split("/")=>>False' m_l21 'not any("normalised repo-relative" in x["message"] for x in e.get("errors", []))'
mutant M27 '        if data != blob:=>>        if False:' m_l16
mutant M28 '        if anc.returncode != 0:=>>        if False:' m_b3
mutant M29 '    if sorted(ids) != sorted(c for c in (batch.get("changes") or []) if isinstance(c, str)):=>>    if False:' m_b4
mutant M30 '        if rel not in gitlink_paths:=>>        if False:' m_b6

echo
echo "== Summary: ok $PASS / NOT ok $FAIL =="
[ "$FAIL" -eq 0 ]
