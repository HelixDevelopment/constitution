#!/usr/bin/env bash
# tests/release/test_derive_release_facts_injection.sh — hermetic test of the fact-output integrity of
# scripts/release/derive_release_facts.sh (review of f4c6e8ab, N4: a tracker value carrying a newline forged
# KEY=VALUE fact lines). Real git and real sqlite3; payloads are built in Python (parameter binding, so no shell
# or SQL quoting touches them).
#   Part 1, CENSUS (§11.4.273): every text source that can reach the facts output is seeded with its own needle
#   and the script is run; the set of needles found in the output IS the class of printed data fields. Positive
#   controls: the seeded fields are expected by name; negative controls: the item body and the commit message are
#   seeded too and must NOT appear. The expected set is pinned, so a new printed field fails here first.
#   Part 2, INJECTION: for every field the census found, and for every character class of the guard (LF, CR, ESC,
#   NEL, LINE SEPARATOR, RIGHT-TO-LEFT OVERRIDE, ZERO WIDTH SPACE, a Unicode TAG character), the field is given
#   the needle plus that character plus a forged fact text; the run must exit 3 with nothing on stdout, and the
#   forged line must appear on neither stream. A field that cannot hold the character at all (a git ref name or a
#   CHANGELOG heading cannot hold a newline) is checked to be refused by its source, and counted as such.
#   Part 3, separator and shape cases: a body, a status and a key value that would split or forge records without
#   any control character in the output; duplicate keys; first- and last-match readers agree on every key.
#   Part 4, false-positive controls (§11.4.201(1)): non-ASCII letters and a CHANGELOG heading cut inside a UTF-8
#   character are accepted.
# DRF_SCRIPT overrides the script under test. Evidence class: gate-logic (PROVISIONAL).
set -u
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
S="${DRF_SCRIPT:-$ROOT/scripts/release/derive_release_facts.sh}"
pass=0; fail=0
ok(){ pass=$((pass+1)); echo "PASS $*"; }; bad(){ fail=$((fail+1)); echo "FAIL $*"; }
W="$(mktemp -d "${TMPDIR:-/tmp}/drf_inj.XXXXXX")"; : "${W:?}"
cleanup(){ [ -n "${W:-}" ] && [ -d "$W" ] && . "$ROOT/scripts/lib/safe_rm.sh" 2>/dev/null && safe_rm_rf "$W" 2>/dev/null; }
trap cleanup EXIT; trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
mkdir -p "$W/tmp"; export TMPDIR="$W/tmp"
G=(git -c user.email=t@t -c user.name=t -c init.defaultBranch=main)
FORGE='retest_item_evidence=yes'

# build DIR FIELD KIND: a repository with one open item A (every text field seeded with a needle), one item B at
# location Issues (FIELD location appends the payload to it), a CHANGELOG heading needle, a tag prev-v1 dated 2026-01-02, a base commit after it, and a
# remote-tracking ref refs/remotes/o/<needle> on a side commit. FIELD (id status severity repro inv closure
# location heading ref body or none) gets KIND appended: none | LF CR ESC NEL LS RLO ZWSP TAG (+ the forged text)
# or a named special case. Prints the ref name status: "ref-ok" or "ref-refused".
build(){
  local d="$1" f="$2" k="$3" rn rc
  "${G[@]}" init -q "$d" || return 1; mkdir -p "$d/docs"
  python3 -I - "$d" "$f" "$k" "$FORGE" <<'PY' || return 1
import sqlite3, sys
d, field, kind, forge = sys.argv[1:5]
ch = {"none": "", "LF": "\n", "CR": "\r", "ESC": "\x1b[31m", "NEL": "\u0085", "LS": " ", "RLO": "‮",
      "ZWSP": "​", "TAG": "\U000e0041"}
v = {"id": "NDLid-1", "status": "NDLstatus", "severity": "NDLsev", "repro": "NDLrepro", "inv": "NDLinv",
     "closure": "NDLclos", "location": "Issues", "heading": "NDLhead", "ref": "NDLref", "body": "x NDLbody"}
if kind in ch:
    if field != "none":
        v[field] = v[field] + ch[kind] + (forge if kind != "none" else "")
elif kind == "OK":
    v[field] = v[field] + "-é→§—"     # non-ASCII letters and symbols: never refused
con = sqlite3.connect(d + "/docs/workable_items.db")
con.execute("CREATE TABLE items (atm_id TEXT, status TEXT, severity TEXT, current_location TEXT, body_md TEXT,"
            " reproduction_state TEXT DEFAULT 'UNSET', investigation_state TEXT DEFAULT 'UNSET', closure_date TEXT)")
con.execute("INSERT INTO items VALUES (?,?,?,?,?,?,?,?)",
            (v["id"], v["status"], v["severity"], "Issues", v["body"], v["repro"], v["inv"], v["closure"]))
con.execute("INSERT INTO items VALUES (?,?,?,?,?,?,?,?)",
            ("NDLid-2", "Queued", "Low", v["location"], "y", "UNSET", "UNSET", None))
con.commit()
open(d + "/CHANGELOG.md", "w", encoding="utf-8", newline="").write("# log\n\n## " + v["heading"] + "\n")
open(d + "/.refname", "wb").write(v["ref"].encode("utf-8"))
PY
  ( cd "$d" && "${G[@]}" add CHANGELOG.md docs && GIT_COMMITTER_DATE=2026-01-02T00:00:00 "${G[@]}" commit -qm 'a NDLmsg' \
    && "${G[@]}" tag -a prev-v1 -m prev && printf 'b\n' >b && "${G[@]}" add b && "${G[@]}" commit -qm 'b NDLmsg' \
    && "${G[@]}" checkout -q -b side && printf 'c\n' >c && "${G[@]}" add c && "${G[@]}" commit -qm c && "${G[@]}" checkout -q main ) || return 1
  rn="$(cat "$d/.refname")"; rm -f -- "$d/.refname"
  ( cd "$d" && "${G[@]}" update-ref "refs/remotes/o/$rn" side 2>/dev/null ); rc=$?
  [ "$rc" = 0 ] && echo ref-ok || echo ref-refused
}
# run DIR ITEM: OUT (stdout), ERRF (stderr file), RC
run(){ OUT="$( cd "$1" && timeout 120 bash "$S" --base main --prev-tag prev-v1 --today 2026-06-01 --remotes o --retest-item "$2" 2>"$W/err" )"; RC=$?; ERRF="$W/err"; }
# keys_unique: every key printed once, so a first-match and a last-match reader read the same value
keys_unique(){ [ -z "$(printf '%s\n' "$OUT" | sed -n 's/=.*//p' | sort | uniq -d)" ]; }

# ---- Part 1: census of the printed data fields ----
CD="$W/census"; build "$CD" none none >/dev/null || { bad "census fixture could not be built"; echo "RESULT: pass=$pass fail=$fail"; exit 1; }
run "$CD" NDLid-1; o1="$OUT"; r1=$RC
run "$CD" NDLid-2; o2="$OUT"; r2=$RC
[ "$r1" = 0 ] && [ "$r2" = 0 ] && ok "census runs exit 0" || bad "census runs exit 0 (rc $r1 $r2: $(head -c 400 "$ERRF"))"
OUT="$o1"; keys_unique && ok "census run 1: every key printed once (first match = last match)" || bad "census run 1: a key is printed twice"
OUT="$o2"; keys_unique && ok "census run 2: every key printed once" || bad "census run 2: a key is printed twice"
found=""
for n in NDLid-1:id NDLstatus:status NDLsev:severity NDLrepro:repro NDLinv:inv NDLclos:closure NDLhead:heading NDLref:ref NDLbody:body NDLmsg:commit-message; do
  printf '%s\n%s\n' "$o1" "$o2" | grep -qF -- "${n%%:*}" && found="$found ${n#*:}"
done
found="${found# }"
EXPECTED="id status severity repro inv closure heading ref"
[ "$found" = "$EXPECTED" ] && ok "census: the printed data fields are exactly: $EXPECTED" || bad "census: printed data fields are '$found', want '$EXPECTED'"
case " $found " in *" body "*) bad "census negative control: the item body reached the facts" ;; *) ok "census negative control: the item body is not printed" ;; esac
case " $found " in *" commit-message "*) bad "census negative control: a commit message reached the facts" ;; *) ok "census negative control: a commit message is not printed" ;; esac
case " $found " in *" status "*) ok "census positive control: a seeded status is found" ;; *) bad "census positive control: the seeded status is not found (instrument blind)" ;; esac

# ---- Part 2: every census field x every character class ----
# the location is not free text: the tracker schema and the script hold it to the closed set Issues, Fixed, so it is
# seeded as Issues (not a needle) and is not in the census; it is still attacked here (Issues + payload is refused)
nrun=0 nsrc=0
for f in $found location; do
  for k in LF CR ESC NEL LS RLO ZWSP TAG; do
    d="$W/i_${f}_$k"; st="$(build "$d" "$f" "$k")" || { bad "$f/$k fixture could not be built"; continue; }
    if [ "$f" = ref ] && [ "$st" = ref-refused ]; then
      case "$k" in LF|CR|ESC) ok "$f/$k: git refuses the ref name at its source (cannot reach the facts)"; nsrc=$((nsrc+1)); continue ;;
        *) bad "$f/$k: git refused a ref name it should accept (the case is not exercised)"; continue ;; esac
    fi
    if [ "$f" = heading ] && [ "$k" = LF ]; then ok "$f/$k: a heading is one line (the newline ends it at its source)"; nsrc=$((nsrc+1)); continue; fi
    item=NDLid-1; [ "$f" = id ] && item=NDLid-2
    run "$d" "$item"; nrun=$((nrun+1))
    msg="$f/$k:"
    [ "$RC" = 3 ] && ok "$msg exit 3" || bad "$msg exit 3 (got $RC)"
    [ -z "$OUT" ] && ok "$msg nothing on stdout" || bad "$msg stdout not empty: $(printf '%s' "$OUT" | head -c 200 | od -c | head -2 | tr -s ' ')"
    grep -q "^$FORGE" "$ERRF" && bad "$msg the forged line reached stderr" || ok "$msg the forged line is on neither stream"
    if [ "$k" = ESC ]; then LC_ALL=C grep -q $'\x1b' "$ERRF" && bad "$msg a raw ESC reached stderr" || ok "$msg no raw ESC on stderr"; fi
    grep -qE 'invisible format character|separator byte|item id|location outside the closed set' "$ERRF" && ok "$msg the refusal names its reason" || bad "$msg the refusal names its reason: $(head -c 300 "$ERRF")"
    # the retest refusal message names the item's status and location on stderr: it must not carry the payload either
    if [ "$f" = status ] || [ "$f" = location ]; then
      item2=NDLid-1; [ "$f" = location ] && item2=NDLid-2
      OUT="$( cd "$d" && timeout 120 bash "$S" --base main --prev-tag prev-v1 --today 2026-06-01 --retest-item "$item2" --require-retest-evidence 2>"$W/err2" )"; RC=$?
      { [ "$RC" = 3 ] && [ -z "$OUT" ] && ! grep -q "^$FORGE" "$W/err2" && ! LC_ALL=C grep -q $'[\x1b\r]' "$W/err2" && grep -q '(not shown)' "$W/err2"; } \
        && ok "$msg --require-retest-evidence: the stderr message shows '(not shown)', no payload" || bad "$msg --require-retest-evidence stderr: $(head -c 300 "$W/err2" | od -c | head -4 | tr -s ' ')"
    fi
  done
done
[ "$nrun" -ge 60 ] && ok "injection runs: $nrun (plus $nsrc refused at their source; control: at least 60 runs)" || bad "injection runs: only $nrun"

# ---- Part 3: separator, key-shape and duplicate-key cases (no control character reaches the output) ----
# special builds: one item set per case, written directly
spec(){
  local d="$1" case="$2"
  "${G[@]}" init -q "$d" || return 1; mkdir -p "$d/docs"
  python3 -I - "$d" "$case" <<'PY' || return 1
import sqlite3, sys
d, case = sys.argv[1:3]
con = sqlite3.connect(d + "/docs/workable_items.db")
con.execute("CREATE TABLE items (atm_id TEXT, status TEXT, severity TEXT, current_location TEXT, body_md TEXT,"
            " reproduction_state TEXT DEFAULT 'UNSET', investigation_state TEXT DEFAULT 'UNSET', closure_date TEXT)")
M = "**Verification:** provisional -- due: 2000-01-01"
rows = [("S-1", "Queued", "Low", "Issues", "x", "UNSET", "UNSET", None)]
if case == "body-rs":      # a record separator in a body forges a provisional item FAKE-1
    rows.append(("S-2", "Queued", "Low", "Issues", "x\x1eFAKE-1\x1f" + M, "UNSET", "UNSET", None))
elif case == "status-rs":  # a record separator in a status forges a count: open_status[Zed]=999
    rows.append(("S-2", "Zed\x1e999", "Low", "Issues", "x", "UNSET", "UNSET", None))
elif case == "status-us":  # a unit separator in a status
    rows.append(("S-2", "Zed\x1f999", "Low", "Issues", "x", "UNSET", "UNSET", None))
elif case == "key-eq":     # a status that closes the key and starts a value: open_status[a]=9]=1
    rows.append(("S-2", "a]=9", "Low", "Issues", "x", "UNSET", "UNSET", None))
elif case == "rlist":      # a status that forges a whole lookup record: T-200 Fixed, closed after the tag
    rows.append(("S-2", "Q\x1eT-200\x1fFixed\x1fFixed\x1f2099-01-01", "Low", "Issues", "x", "UNSET", "UNSET", None))
    rows.append(("T-200", "Queued", "Low", "Issues", "x", "UNSET", "UNSET", None))
elif case == "id-space":   # an id with a space forges a second id into a list
    rows.append(("A-1 CON-999", "Reopened", "Low", "Issues", "x", "UNSET", "UNSET", None))
elif case == "id-lf":
    rows.append(("A-1\nretest_item_evidence=yes", "Reopened", "Low", "Issues", "x", "UNSET", "UNSET", None))
elif case == "ok-nonascii":  # false-positive control: non-ASCII text in printed fields is accepted
    rows.append(("S-2", "Bereit zum Testen → é", "Hoch—ü", "Issues", "x", "UNSET", "UNSET", None))
for r in rows:
    con.execute("INSERT INTO items VALUES (?,?,?,?,?,?,?,?)", r)
con.commit()
head = "NDLhead"
if case == "ok-cut":   # a heading of 121+ bytes whose 120th byte is inside an em dash: cut, then the partial
    head = "a" * 118 + "—" + "tail"       # character is dropped (bytes 119-121 are the dash)
elif case == "lone-c1":   # a lone C1 byte (not UTF-8) at the end of a short heading: refused, never trimmed
    head = None
data = ("# log\n\n## " + head + "\n").encode("utf-8") if head is not None else b"# log\n\n## short\x85\n"
open(d + "/CHANGELOG.md", "wb").write(data)
PY
  ( cd "$d" && "${G[@]}" add CHANGELOG.md docs && GIT_COMMITTER_DATE=2026-01-02T00:00:00 "${G[@]}" commit -qm a \
    && "${G[@]}" tag -a prev-v1 -m prev && printf 'b\n' >b && "${G[@]}" add b && "${G[@]}" commit -qm b )
}
srun(){ OUT="$( cd "$1" && timeout 120 bash "$S" --base main --prev-tag prev-v1 --today 2026-06-01 "${@:2}" 2>"$W/err" )"; RC=$?; ERRF="$W/err"; }
for c in body-rs:'provisional_ids=.*FAKE-1' status-rs:'open_status\[Zed\]=999' status-us:'open_status\[Zed' key-eq:'open_status\[a\]' rlist:'retest_item_evidence=yes' id-space:'_ids.*CON-999' id-lf:'_ids.*retest_item_evidence'; do
  name="${c%%:*}"; pat="${c#*:}"; d="$W/s_$name"; spec "$d" "$name" || { bad "$name fixture could not be built"; continue; }
  if [ "$name" = rlist ]; then srun "$d" --retest-item T-200; else srun "$d"; fi
  [ "$RC" = 3 ] && ok "$name: exit 3" || bad "$name: exit 3 (got $RC)"
  [ -z "$OUT" ] && ok "$name: nothing on stdout" || bad "$name: stdout not empty"
  { printf '%s\n' "$OUT"; cat "$ERRF"; } | grep -q -- "$pat" && bad "$name: a forged value is printed" || ok "$name: no forged value on either stream"
done
d="$W/s_dup"; spec "$d" none || bad "dup fixture could not be built"
srun "$d" --remotes "o o"
[ "$RC" = 3 ] && [ -z "$OUT" ] && grep -q 'printed twice' "$ERRF" && ok "a duplicate fact key (--remotes 'o o') is refused (rc 3), so no reader can pick a different copy" || bad "a duplicate fact key is refused (rc $RC: $(head -c 300 "$ERRF"))"
srun "$d" --remotes o
[ "$RC" = 0 ] && keys_unique && ok "duplicate-key control: --remotes o prints every key once (rc 0)" || bad "duplicate-key control: --remotes o (rc $RC)"

# ---- Part 4: false-positive controls (§11.4.201(1)) ----
d="$W/s_ok"; spec "$d" ok-nonascii || bad "ok-nonascii fixture could not be built"
srun "$d"
[ "$RC" = 0 ] && ok "non-ASCII status and severity: accepted (rc 0)" || bad "non-ASCII status and severity: accepted (rc $RC: $(head -c 300 "$ERRF"))"
printf '%s\n' "$OUT" | grep -qxF 'open_status[Bereit zum Testen → é]=1' && ok "non-ASCII status printed as stored" || bad "non-ASCII status printed as stored"
printf '%s\n' "$OUT" | grep -qxF -e 'open_severity[hoch—ü]=1' -e 'open_severity[hoch—Ü]=1' -e 'open_severity[Hoch—ü]=1' && ok "non-ASCII severity printed" || bad "non-ASCII severity printed: $(printf '%s\n' "$OUT" | grep '^open_severity\[')"
d="$W/s_cut"; spec "$d" ok-cut || bad "ok-cut fixture could not be built"
srun "$d"
[ "$RC" = 0 ] && ok "a heading cut inside a UTF-8 character: accepted (rc 0)" || bad "a heading cut inside a UTF-8 character: accepted (rc $RC: $(head -c 300 "$ERRF"))"
printf '%s\n' "$OUT" | grep -qxF "changelog_first_heading=$(printf 'a%.0s' $(seq 118))" && ok "the partial character is dropped, the 118 whole bytes are kept" || bad "the cut heading: $(printf '%s\n' "$OUT" | grep '^changelog_first_heading' | od -c | tail -3 | head -2 | tr -s ' ')"
d="$W/s_c1"; spec "$d" lone-c1 || bad "lone-c1 fixture could not be built"
srun "$d"
[ "$RC" = 3 ] && [ -z "$OUT" ] && ok "a lone C1 byte in a short heading is refused (rc 3), never trimmed away" || bad "a lone C1 byte in a short heading is refused (rc $RC)"
echo "RESULT: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
