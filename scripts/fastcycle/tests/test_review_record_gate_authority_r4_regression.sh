#!/bin/bash
# test_review_record_gate_authority_r4_regression.sh
#
# T048 restart, independent review ROUND 4, area V3
# (docs/qa/t048_restart_round4_20261008/V3_review_record.md) -- STRUCTURAL
# round 4 of R_max 5 (constitution 11.4.276(E)). Three same-class
# recurrences, each closed by replacing a structure, not patching a member:
#
#   R4-F1  class "the tier is rated on principals the producer controls"
#          (R2-F3, R3-F1, R4-F1): capability is now a POSITIVE ALLOWLIST --
#          every inode of the store must be owned by an operator-declared
#          evidence-owner uid (--evidence-owner-uid) that is a passwd
#          account, neither producer nor runner, and in NO subordinate-id
#          range; nothing else (but root) may write or replace any of it.
#          The reviewer's attack -- chown the forged tree to one of the
#          user's own subordinate uids with `podman unshare chown` -- is
#          reproduced here and must now yield "instance".
#   R4-F2  class "the gate trusts supplied fields to pick the record that
#          counts" (R1-B1, R2-F1, R3-F2, R4-F2): backfill rows can only ADD
#          blockers; the live chain of a batch is decided from live units
#          only; the tier covers the WHOLE store.
#   R4-F3  isolating cases for the reviewer's mutations R4-A/D/F/H (R4-E/I
#          were already killed; R4-B/R4-C target structures this round
#          replaced -- see the mutation runner's header).
#   m1     an unlistable sub-directory (chmod 000) is exit 4, never skipped.
#
# Every CLI case drives the REAL `review_record.py record` / `backfill` /
# `gate`. The in-process cases call the real module's own _store_tier /
# _path_tier on REAL files with REAL owners (subordinate-uid ownership is
# created with `podman unshare`, and the host's real /etc/subuid is read);
# `ranges`/`getpw` are injected ONLY to isolate one sub-clause at a time
# (unit level, constitution 11.4.27(A)) -- the CLI never accepts them.
#
# Usage : bash test_review_record_gate_authority_r4_regression.sh
# Exit  : 0 all checks pass; 1 any check failed; 2 scratch dir unusable.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
# shellcheck disable=SC2034 # RR_TOOL is consumed by the sourced lib/review_record_genuine.sh
RR_TOOL="$FC/review/review_record.py"
# shellcheck source=lib/review_record_genuine.sh
# shellcheck disable=SC1091 # sourced helper is linted on its own; the precheck pack runs shellcheck without -x
. "$HERE/lib/review_record_genuine.sh"

FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }
expect() { # expect LABEL GOT WANT TEXT
  if [ "$2" = "$3" ]; then ok "$1: $4"; else bad "$1: got '$2' want '$3' ($4)"; fi
}

S=$(mktemp -d) || { echo "cannot create temp dir" >&2; exit 2; }
CAPROOT=""
cleanup() {
  if [ -n "$CAPROOT" ] && [ -d "$CAPROOT" ]; then podman unshare rm -rf "$CAPROOT" 2>/dev/null; fi
  chmod -R u+rwx "$S" 2>/dev/null; rm -rf "$S"
}
trap cleanup EXIT INT TERM
chmod 755 "$S"
RR_WORK="$S/work"; mkdir -p "$RR_WORK"
NONE='[]'
SD='[{"id":"F1","severity":"BLOCKING","finding_layer":"source-defect"}]'
ME=$(id -u)

fresh_case() {
  CASE="$S/$1"; mkdir -p "$CASE/records"
  RR_LEDGER="$CASE/ledger.jsonl"; : > "$RR_LEDGER"
  REC="$CASE/records"
}
gate() { # gate CHANGE [extra args] -> sets G_RC, G_OUT
  G_OUT=$(python3 "$RR_TOOL" gate --change "$1" --records "$REC" --dispatch-ledger "$RR_LEDGER" "${@:2}" 2>&1)
  G_RC=$?
}
covered()   { [ "$G_RC" -eq 0 ] && printf '%s\n' "$G_OUT" | grep -q "^COVERED $1 "; }
uncovered() { [ "$G_RC" -eq 1 ] && printf '%s\n' "$G_OUT" | grep -q "^UNCOVERED $1"; }
has()       { printf '%s\n' "$G_OUT" | grep -q -- "$1"; }
blind()     { [ "$G_RC" -eq 4 ] && has "$1"; }
edit() { # edit REC_JSON PY_STMT [rehash]
  python3 - "$1" "$2" "${3:-}" <<'PY'
import hashlib, json, sys
p, stmt, mode = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(p))
exec(stmt)
if mode == "rehash":
    body = {k: v for k, v in d.items() if k not in ("run_meta", "body_hash")}
    d["body_hash"] = hashlib.sha256(json.dumps(body, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()
json.dump(d, open(p, "w"))
PY
}
backfill() { # backfill OUT_JSON SPEC_JSON -> the REAL `backfill` CLI
  printf '%s\n' "$2" > "$CASE/bf_spec.json"
  python3 "$RR_TOOL" backfill --input "$CASE/bf_spec.json" --out "$1" >/dev/null 2>"$CASE/bf.err"
}
p3_case() { # honest P3: B1 r1 GO, B1 r2 genuine NO-GO, B9 r1 GO, all for cY
  fresh_case "$1"
  rr_genuine "$REC/b1r1.json" B1 cY 1 GO "$NONE" "D-$1-A"
  rr_genuine "$REC/b1r2.json" B1 cY 2 NO-GO "$SD" "D-$1-B"
  rr_genuine "$REC/b9r1.json" B9 cY 1 GO "$NONE" "D-$1-C"
}

echo "== V3 round-4 regression: positive-allowlist capability, backfill adds blockers only =="

# =============================================================================
# R4-F2: a producer-authored backfill row can never hide an open live NO-GO
# =============================================================================
p3_case bf1
backfill "$REC/zz_backfill.json" '{"review_id":"R-BF1","batch_id":"B1","round":3,"verdict":"GO","findings":[],"change_ids":["cY"],"source_evidence":"UNKNOWN"}'
gate cY
if uncovered cY && has "B1: reviewer verdict is not a zero-finding GO"; then
  ok "R4-BF1: a backfill GO at a higher round of B1 does NOT hide B1's open live round-2 NO-GO (was COVERED by B9, rc 0)"
else bad "R4-BF1: rc=$G_RC out=$G_OUT"; fi

fresh_case bf2
rr_genuine "$REC/r2.json" B2 cB 2 GO "$NONE" D-BF2
backfill "$REC/h1.json" '{"review_id":"R-BF2","batch_id":"B2","round":1,"verdict":"NO-GO","findings":[{"id":"H","severity":"BLOCKING"}],"change_ids":["cB"],"source_evidence":"UNKNOWN"}'
gate cB
if covered cB; then ok "R4-BF2 (false-refusal guard, 11.4.201(1)): a historical NO-GO superseded by a LATER live GO round of the same batch does not block"
else bad "R4-BF2: rc=$G_RC out=$G_OUT"; fi

fresh_case bf3
rr_genuine "$REC/r1.json" B3 cC 1 GO "$NONE" D-BF3
backfill "$REC/h2.json" '{"review_id":"R-BF3","batch_id":"B3","round":2,"verdict":"NO-GO","findings":[{"id":"H","severity":"BLOCKING"}],"change_ids":["cC"],"source_evidence":"UNKNOWN"}'
gate cC
if uncovered cC && has "B3: backfilled round 2 is not a zero-finding GO"; then
  ok "R4-BF3: a backfill NO-GO at a round no live round of its batch supersedes BLOCKS (backfill adds blockers)"
else bad "R4-BF3: rc=$G_RC out=$G_OUT"; fi

fresh_case bf4
rr_genuine "$REC/r1.json" B4 cD 1 GO "$NONE" D-BF4
backfill "$REC/h3.json" '{"review_id":"R-BF4","batch_id":"B4","round":3,"verdict":"GO","findings":[],"change_ids":["cD"],"source_evidence":"UNKNOWN"}'
gate cD
if covered cD && has "batch=B4 round=1 "; then ok "R4-BF4: a backfill GO at a higher round is neutral -- the live round 1 still covers (never the backfill row)"
else bad "R4-BF4: rc=$G_RC out=$G_OUT"; fi

fresh_case bf5
rr_genuine "$REC/r1.json" B5 cE 1 GO "$NONE" D-BF5
backfill "$REC/h5.json" '{"review_id":"R-BF5","batch_id":"B5","round":3,"verdict":"NO-GO","findings":[],"change_ids":["cOTHER"],"source_evidence":"UNKNOWN"}'
gate cE
if covered cE; then ok "R4-BF5: a backfill NO-GO that does not list the change does not block it"
else bad "R4-BF5: rc=$G_RC out=$G_OUT"; fi

# --- the same R4-F2 attack in a CAPABILITY-SHAPED tree is covered below (R4-CAP7)

# =============================================================================
# m1: a sub-directory that cannot be listed is exit 4, never silently skipped
# =============================================================================
if [ "$ME" -eq 0 ]; then
  echo "NOTE: running as root -- R4-OE SKIPPED (root lists any directory)"
else
  p3_case oe
  mkdir "$REC/hide"
  EV=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["verdict_evidence"])' "$REC/b1r2.json")
  PEV=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["precheck_evidence"])' "$REC/b1r2.json")
  mv "$REC/b1r2.json" "$REC/$EV" "$REC/hide/"; cp "$REC/$PEV" "$REC/hide/"
  gate cY; RC_VIS=$G_RC; OUT_VIS=$G_OUT
  chmod 000 "$REC/hide"; gate cY; chmod 755 "$REC/hide"
  if [ "$RC_VIS" -eq 1 ] && printf '%s\n' "$OUT_VIS" | grep -q "UNCOVERED cY" && blind "cannot be listed"; then
    ok "R4-OE: the NO-GO moved into hide/ blocks while readable (control); after chmod 000 hide the gate is BLIND (exit 4, 'cannot be listed'), never COVERED"
  else bad "R4-OE: control rc=$RC_VIS $OUT_VIS | hidden rc=$G_RC $G_OUT"; fi
  # the orphan walk refuses an unlistable directory on its own, too (in-process,
  # with the record walk already past -- the real function, a real chmod 000)
  OW=$(python3 - "$RR_TOOL" "$REC" <<'PY'
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("rr", sys.argv[1])
rr = importlib.util.module_from_spec(spec); spec.loader.exec_module(rr)
os.chmod(os.path.join(sys.argv[2], "hide"), 0)
try:
    out = rr._orphaned_evidence(sys.argv[2], [])
finally:
    os.chmod(os.path.join(sys.argv[2], "hide"), 0o755)
print(any("cannot be listed" in o for o in out))
PY
)
  expect R4-OE2 "$OW" True "_orphaned_evidence names an unlistable directory instead of skipping it"
fi

# =============================================================================
# R4-F3: isolating cases for the reviewer's surviving mutations
# =============================================================================
# R4-A: copies are merged, and EVERY copy must carry its own precheck.
fresh_case r4a
rr_genuine "$REC/r1.json" B5 c5 1 GO "$NONE" D-R4A
mkdir -p "$REC/a" "$REC/z"
EV=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["verdict_evidence"])' "$REC/r1.json")
mv "$REC/r1.json" "$REC/$EV" "$REC/"*.precheck-evidence "$REC/a/"
cp "$REC/a/r1.json" "$REC/a/$EV" "$REC/z/"
gate c5
if uncovered c5 && has "B5: precheck_evidence missing"; then
  ok "R4-A: byte-identical copies merge, and a copy (z/) with its verdict archive but no precheck archive refuses the merged unit"
else bad "R4-A: rc=$G_RC out=$G_OUT"; fi

# R4-D: a ledger row with a duplicate JSON key makes the whole ledger unreadable.
fresh_case r4d
RR_SKIP_LEDGER=1 rr_genuine "$REC/r1.json" B-R4D c-r4d 1 GO "$NONE" D-R4D
rr_ledger_row D-R4D opus xhigh
printf '%s\n' '{"key":"D-R4D","key":"D-OTHER","event":"complete","description":"(T1/main - claude5 - opus - xhigh) x"}' >> "$RR_LEDGER"
gate c-r4d
if uncovered c-r4d && has "dispatch ledger unreadable: duplicate JSON key"; then
  ok "R4-D: one ledger row with a duplicate JSON key makes the ledger unreadable -- no reviewer authenticates (was COVERED with the row ignored)"
else bad "R4-D: rc=$G_RC out=$G_OUT"; fi

# R4-F: the record's reviewer_dispatch_id must equal the evidence's dispatch.
fresh_case r4f
rr_genuine "$REC/r1.json" B-R4F c-r4f 1 GO "$NONE" D-R4F
edit "$REC/r1.json" 'd["reviewer_dispatch_id"]="D-SOMEONE-ELSE"' rehash
gate c-r4f
if blind "r1.json" && has "record fields disagree"; then
  ok "R4-F: an edited + re-hashed reviewer_dispatch_id is inadmissible (exit 4, fields disagree with the evidence)"
else bad "R4-F: rc=$G_RC out=$G_OUT"; fi

# R4-H: one dispatch backing two DIFFERENT batches' round 1 is reuse.
fresh_case r4h
rr_genuine "$REC/bx.json" BX c-x 1 GO "$NONE" D-SHARED
rr_genuine "$REC/bz.json" BZ c-z 1 GO "$NONE" D-SHARED
gate c-x; RC_X=$G_RC; OUT_X=$G_OUT
gate c-z
if [ "$RC_X" -eq 1 ] && printf '%s\n' "$OUT_X" | grep -q "reused for more than one verdict" \
   && uncovered c-z && has "reused for more than one verdict"; then
  ok "R4-H: one reviewer dispatch backing BX r1 AND BZ r1 is reuse -- both UNCOVERED (the reuse key carries the batch)"
else bad "R4-H: X rc=$RC_X $OUT_X | Z rc=$G_RC $G_OUT"; fi

# Evidence slice verdicts: a non-GO reviewer slice verdict refuses even when the
# producer-declared slice set (slice_lines) is edited down to one slice.
fresh_case sv
RR_SLICES='[{"slice_id":"S1","lines":[1]},{"slice_id":"S2","lines":[2]}]' \
RR_SLICE_VERDICTS='[{"slice_id":"S1","verdict":"GO"},{"slice_id":"S2","verdict":"GO"}]' \
  rr_genuine "$REC/r1.json" B-SV c-sv 1 GO "$NONE" D-SV
python3 - "$REC/r1.json" <<'PY'
import hashlib, json, os, sys
p = sys.argv[1]; d = json.load(open(p)); base = os.path.dirname(p)
old = os.path.join(base, d["verdict_evidence"]); v = json.load(open(old))
v["slice_verdicts"][1]["verdict"] = "NO-GO"
raw = json.dumps(v).encode(); os.remove(old)
sha = hashlib.sha256(raw).hexdigest()
open(os.path.join(base, sha + ".verdict-evidence"), "wb").write(raw)
d["verdict_evidence"] = sha + ".verdict-evidence"; d["verdict_evidence_sha256"] = sha
d["slice_lines"] = d["slice_lines"][:1]
body = {k: x for k, x in d.items() if k not in ("run_meta", "body_hash")}
d["body_hash"] = hashlib.sha256(json.dumps(body, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()
json.dump(d, open(p, "w"))
PY
gate c-sv
if uncovered c-sv && has "a reviewer slice verdict is not GO"; then
  ok "R4-SV: a reviewer NO-GO slice verdict refuses coverage even after slice_lines is edited down to one slice (forged + re-hashed)"
else bad "R4-SV: rc=$G_RC out=$G_OUT"; fi

# =============================================================================
# R4-F1: positive-allowlist capability
# =============================================================================
# --- CLI: no declared owner -> instance, whatever else is declared -----------
fresh_case nodecl
rr_genuine "$REC/r1.json" B-ND c-nd 1 GO "$NONE" D-ND
gate c-nd --seam release-tag --producer-uid 65534
if uncovered c-nd && has "achieved instance (no evidence-owner uid declared"; then
  ok "R4-CAP0: with no --evidence-owner-uid a high-blast seam refuses, naming the missing declaration"
else bad "R4-CAP0: rc=$G_RC out=$G_OUT"; fi
gate c-nd --seam release-tag --producer-uid 65534 --evidence-owner-uid "$ME"
if uncovered c-nd && has "is the producer or the runner"; then ok "R4-CAP0b: declaring the runner itself as evidence owner -> instance (named)"
else bad "R4-CAP0b: rc=$G_RC out=$G_OUT"; fi

# --- in-process sub-clause isolation of the declaration (real module) --------
DECL=$(python3 - "$RR_TOOL" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("rr", sys.argv[1])
rr = importlib.util.module_from_spec(spec); spec.loader.exec_module(rr)
def ok_pw(uid): return object()
def no_pw(uid): raise KeyError(uid)
e = rr._owner_declaration_error
out = [
    e(None, 65534, 1000, [], ok_pw),           # undeclared
    e(True, 65534, 1000, [], ok_pw),           # bool is not a uid
    e(-1, 65534, 1000, [], ok_pw),             # negative
    e(4242, 65534, 1000, [], no_pw),           # not in passwd
    e(1000, 65534, 1000, [], ok_pw),           # == runner
    e(65534, 65534, 1000, [], ok_pw),          # == producer
    e(100000, 65534, 1000, [(100000, 65536)], ok_pw),  # first id of a range
    e(165535, 65534, 1000, [(100000, 65536)], ok_pw),  # last id of a range
    e(165536, 65534, 1000, [(100000, 65536)], ok_pw),  # control: one past the range
    e(4242, 65534, 1000, [], ok_pw),           # control: acceptable
]
print("|".join("None" if r is None else r.split(" ")[0] + ":" + ("declared" if "declared" in r else "passwd" if "passwd" in r else "principal" if "producer or the runner" in r else "subordinate" if "subordinate" in r else "?") for r in out))
PY
)
expect R4-DECL "$DECL" "no:declared|no:declared|no:declared|evidence-owner:passwd|evidence-owner:principal|evidence-owner:principal|evidence-owner:subordinate|evidence-owner:subordinate|None|None" \
  "owner declaration: undeclared/bool/negative, non-passwd, == runner, == producer, first/last subordinate id refused; one past the range and a plain account accepted"

# producer / runner sub-clauses of _path_tier, with an acceptable owner and a
# REAL root-owned file (/etc/hostname): owner 0 is a real, non-subordinate
# account no ordinary user can act as -> the positive control is capability.
PT=$(python3 - "$RR_TOOL" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("rr", sys.argv[1])
rr = importlib.util.module_from_spec(spec); spec.loader.exec_module(rr)
def ok_pw(uid): return object()
def no_pw(uid): raise KeyError(uid)
t = rr._path_tier
f = ["/etc/hostname"]
out = [
    t(f, 65534, 0, runner_uid=1000, ranges=[], getpw=ok_pw)[0],    # positive control
    t(f, 65534, 0, runner_uid=0, ranges=[], getpw=ok_pw)[0],       # root runner
    t(f, None, 0, runner_uid=1000, ranges=[], getpw=ok_pw)[0],     # producer undeclared
    t(f, 0, 0, runner_uid=1000, ranges=[], getpw=ok_pw)[0],        # producer root
    t(f, 1000, 0, runner_uid=1000, ranges=[], getpw=ok_pw)[0],     # producer == runner
    t(f, 65534, 0, runner_uid=1000, ranges=[], getpw=lambda u: no_pw(u) if u == 65534 else 1)[0],  # producer unknown
    t(f, 65534, 0, runner_uid=1000, ranges=None, getpw=ok_pw)[0],  # REAL host subid files: 0 is in no range
    t([None], 65534, 0, runner_uid=1000, ranges=[], getpw=ok_pw)[0],  # a missing path
    t(["/nonexistent/x"], 65534, 0, runner_uid=1000, ranges=[], getpw=ok_pw)[0],  # unresolvable
    t(f, 65534, 4242, runner_uid=1000, ranges=[], getpw=ok_pw)[0], # owner differs from the real owner (0)
]
print(" ".join(out))
PY
)
expect R4-PT "$PT" "capability instance instance instance instance instance capability instance instance instance" \
  "_path_tier: root-owned evidence + owner 0 -> capability; root runner, undeclared/root producer, producer == runner, unknown producer, missing/unresolvable path, wrong owner -> instance"

# _subid_ranges sub-clauses on REAL temp files (the parser, unit level).
SR=$(python3 - "$RR_TOOL" "$S" <<'PY'
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("rr", sys.argv[1])
rr = importlib.util.module_from_spec(spec); spec.loader.exec_module(rr)
d = sys.argv[2]
def w(name, text):
    p = os.path.join(d, name); open(p, "w").write(text); return p
good = w("sub_good", "# c\n\nmilos:100000:65536\n1001:300000:10\n")
bad = w("sub_bad", "milos:100000\n")
ns_files = w("ns_files", "passwd: files\nsubid: files # local\n")
ns_ldap = w("ns_ldap", "subid: sss\n")
missing = os.path.join(d, "no_such_file")
unread = w("sub_unread", "x:1:1\n"); os.chmod(unread, 0)
out = [
    rr._subid_ranges((good,), ns_files)[0] == [(100000, 65536), (300000, 10)],
    rr._subid_ranges((good, missing), missing)[0] == [(100000, 65536), (300000, 10)],
    rr._subid_ranges((bad,), ns_files)[0] is None,
    rr._subid_ranges((good,), ns_ldap)[0] is None,
    (os.geteuid() == 0) or rr._subid_ranges((unread,), ns_files)[0] is None,
    (os.geteuid() == 0) or rr._subid_ranges((good,), unread)[0] is None,
]
os.chmod(unread, 0o600)
print(" ".join(str(x) for x in out))
PY
)
expect R4-SR "$SR" "True True True True True True" \
  "_subid_ranges: comments/blanks skipped, a missing file grants nothing, malformed line / non-file nsswitch subid source / unreadable subid or nsswitch file -> unknowable (None)"

# _owner_only_error sub-clauses with synthetic stat records on a real path
# (unit level, 11.4.27(A): ownership layouts a single uid cannot create).
OO=$(python3 - "$RR_TOOL" "$S" <<'PY'
import importlib.util, os, stat, sys
spec = importlib.util.spec_from_file_location("rr", sys.argv[1])
rr = importlib.util.module_from_spec(spec); spec.loader.exec_module(rr)
real = os.path.join(sys.argv[2], "oo_probe"); open(real, "w").write("x")
base = os.stat(real)
def st(uid, mode):
    f = list(base); f[0] = mode; f[4] = uid; return os.stat_result(f)
REG, DIR = stat.S_IFREG, stat.S_IFDIR
E = 4242
def ch(leaf, droot, leaf_path=real):
    return (leaf_path, leaf, {"/": droot}, [("/", leaf)])
e = rr._owner_only_error
words = []
for c in (
    ch(st(E, REG | 0o444), st(0, DIR | 0o755)),          # control: clean
    ch(st(1000, REG | 0o444), st(0, DIR | 0o755)),       # leaf owned by someone else
    ch(st(0, REG | 0o444), st(0, DIR | 0o755)),          # a FILE owned by root is not the owner's
    ch(st(0, DIR | 0o755), st(0, DIR | 0o755)),          # a DIRECTORY leaf owned by root is fine
    ch(st(E, REG | 0o464), st(0, DIR | 0o755)),          # group-writable leaf
    ch(st(E, REG | 0o446), st(0, DIR | 0o755)),          # other-writable leaf
    ch(st(E, REG | 0o444), st(1000, DIR | 0o755)),       # chain dir owned by someone else
    ch(st(E, REG | 0o444), st(0, DIR | 0o777)),          # foreign-writable non-sticky dir
    ch(st(E, REG | 0o444), st(0, DIR | 0o1777)),         # control: sticky protects an owner-owned entry
    ch(st(E, REG | 0o444), st(0, DIR | 0o1775)),         # control: sticky, group-writable
    (real, st(E, REG | 0o444), {"/": st(0, DIR | 0o1777)}, [("/", st(1000, REG | 0o444))]),  # sticky dir, entry owned by another uid
):
    r = e(c, E)
    words.append("ok" if r is None else ("owner" if "owned by uid" in r and "directory" not in r else
                  "write" if "writable" in r and "directory" not in r else
                  "dirowner" if "directory" in r and "owned by" in r else
                  "dirwrite" if "directory" in r and "writable" in r else "?:" + r))
print(" ".join(words))
PY
)
expect R4-OO "$OO" "ok owner owner ok write write dirowner dirwrite ok ok dirwrite" \
  "_owner_only_error: leaf owner, root-owned file vs dir, group/other write, chain-dir owner, non-sticky foreign-writable dir, sticky entry ownership"

# --- the reviewer's attack, end to end, on a REAL subordinate-uid tree -----------
podman_ok() { command -v podman >/dev/null 2>&1 && podman unshare true >/dev/null 2>&1; }
SUBRANGE=$(awk -F: -v u="$(id -un)" -v n="$ME" '$1==u || $1==n {print $2; exit}' /etc/subuid 2>/dev/null)
# A base directory whose whole chain is root-owned, so the ONLY thing that can
# refuse capability is the owner declaration (the reviewer used the same spot).
CAPBASE=$(python3 - "$S" <<'PY'
import os, sys
def root_chain(p):  # p and every ancestor owned by root
    while True:
        if os.stat(p).st_uid != 0:
            return False
        if p == "/":
            return True
        p = os.path.dirname(p)
p = os.path.realpath(sys.argv[1])
while p != "/" and not root_chain(p):
    p = os.path.dirname(p)
print(p if p != "/" else "")
PY
)
if [ "$ME" -eq 0 ]; then
  echo "NOTE: running as root -- R4-CAP SKIPPED (root is excluded from the tier on purpose)"
elif ! podman_ok; then
  echo "NOTE: podman unshare unavailable on this host -- R4-CAP1..7 SKIPPED (need a user-namespace subordinate-uid owner)"
elif [ -z "$SUBRANGE" ]; then
  echo "NOTE: $(id -un) has no /etc/subuid range -- R4-CAP1..7 SKIPPED"
elif [ -z "$CAPBASE" ] || [ ! -w "$CAPBASE" ]; then
  echo "NOTE: no writable directory with an all-root-owned chain above $S -- R4-CAP1..7 SKIPPED"
else
  SUBUID=$SUBRANGE   # `podman unshare chown 1:1` maps namespace uid 1 to the first subordinate uid
  CAPROOT=$(mktemp -d "$CAPBASE/rr_r4cap.XXXXXX")
  CASE="$CAPROOT"; REC="$CAPROOT/records"; mkdir -p "$REC"
  RR_LEDGER="$CAPROOT/ledger.jsonl"; : > "$RR_LEDGER"
  # P2 forgery: the producer authors the verdict under an invented reviewer,
  # appends its own ledger rows, and records it (all with the REAL CLI).
  rr_genuine "$REC/r1.json" B-CAP c-cap 1 GO "$NONE" rev-d1
  rr_genuine "$REC/b1r1.json" B1 cY 1 GO "$NONE" D-CAP-A
  rr_genuine "$REC/b1r2.json" B1 cY 2 NO-GO "$SD" D-CAP-B
  rr_genuine "$REC/b9r1.json" B9 cY 1 GO "$NONE" D-CAP-C
  chmod -R a+rX,go-w "$CAPROOT"
  if podman unshare chown -R 1:1 "$CAPROOT" 2>/dev/null \
     && [ "$(stat -c %u "$REC/r1.json")" = "$SUBUID" ] && [ "$(stat -c %u "$CAPROOT")" = "$SUBUID" ]; then
    ok "R4-CAP-needle: the forged tree is now owned by subordinate uid $SUBUID (podman unshare chown), chain above it root-owned ($CAPBASE)"
    gate c-cap --seam release-tag --producer-uid 65534 --evidence-owner-uid "$SUBUID"; RC1=$G_RC; OUT1=$G_OUT
    gate c-cap --seam qa-deploy --producer-uid 65534 --evidence-owner-uid "$SUBUID"; RC2=$G_RC; OUT2=$G_OUT
    gate c-cap --seam manual-qa-handoff --producer-uid 65534; RC3=$G_RC; OUT3=$G_OUT
    if [ "$RC1" -eq 1 ] && printf '%s\n' "$OUT1" | grep -q "achieved instance" \
       && [ "$RC2" -eq 1 ] && printf '%s\n' "$OUT2" | grep -q "achieved instance" \
       && [ "$RC3" -eq 1 ] && printf '%s\n' "$OUT3" | grep -q "achieved instance (no evidence-owner uid declared"; then
      ok "R4-CAP1: the reviewer's attack (subordinate-uid-owned forged tree, --producer-uid 65534) now gets 'instance' at release-tag / qa-deploy (owner declared) and manual-qa-handoff (undeclared) -- was COVERED with capability"
    else bad "R4-CAP1: A rc=$RC1 $OUT1 | B rc=$RC2 $OUT2 | C rc=$RC3 $OUT3"; fi
    gate c-cap --producer-uid 65534 --evidence-owner-uid "$SUBUID"
    if covered c-cap && has "independence=instance"; then ok "R4-CAP2: the same tree at the ORDINARY seam is still COVERED, honestly labelled instance"
    else bad "R4-CAP2: rc=$G_RC out=$G_OUT"; fi
    # in-process: the tree itself IS capability-shaped -- with the declaration
    # check satisfied by injection, the store tier is capability; with the
    # host's REAL subid ranges it is refused for exactly the subordinate reason.
    ST=$(python3 - "$RR_TOOL" "$REC" "$RR_LEDGER" "$SUBUID" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("rr", sys.argv[1])
rr = importlib.util.module_from_spec(spec); spec.loader.exec_module(rr)
rec, led, sub = sys.argv[2], sys.argv[3], int(sys.argv[4])
pw = lambda u: object()
a = rr._store_tier(rec, led, 65534, sub, ranges=[], getpw=pw)
b = rr._store_tier(rec, led, 65534, sub, ranges=None, getpw=pw)
print(a[0], "|", b[0], "|", "subordinate" in (b[1] or ""))
PY
)
    expect R4-CAP3 "$ST" "capability | instance | True" \
      "in-process: the subordinate-owned tree is capability-shaped (control) and the host's REAL /etc/subuid range is what refuses it"
    # R4-C (re-expressed): the store tier covers EVERY file, not only records:
    # an archive handed back to the producer uid makes the store "instance".
    ARCH=$(find "$REC" -maxdepth 1 -name '*.verdict-evidence' | sort | head -1)
    podman unshare chown 0:0 "$ARCH"
    ST2=$(python3 - "$RR_TOOL" "$REC" "$RR_LEDGER" "$SUBUID" "$ARCH" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("rr", sys.argv[1])
rr = importlib.util.module_from_spec(spec); spec.loader.exec_module(rr)
t, why = rr._store_tier(sys.argv[2], sys.argv[3], 65534, int(sys.argv[4]), ranges=[], getpw=lambda u: object())
print(t, sys.argv[5] in (why or ""))
PY
)
    podman unshare chown 1:1 "$ARCH"
    expect R4-CAP4 "$ST2" "instance True" "one archive owned by the producer uid (not a record) makes the whole store instance, naming that archive"
    # the ledger is part of the store
    podman unshare chown 0:0 "$RR_LEDGER"
    ST3=$(python3 - "$RR_TOOL" "$REC" "$RR_LEDGER" "$SUBUID" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("rr", sys.argv[1])
rr = importlib.util.module_from_spec(spec); spec.loader.exec_module(rr)
t, why = rr._store_tier(sys.argv[2], sys.argv[3], 65534, int(sys.argv[4]), ranges=[], getpw=lambda u: object())
print(t, sys.argv[3] in (why or ""))
PY
)
    podman unshare chown 1:1 "$RR_LEDGER"
    expect R4-CAP5 "$ST3" "instance True" "a ledger owned by the producer uid makes the store instance, naming the ledger"
    # a group-writable sub-directory inside the store (the producer's drop box)
    # shellcheck disable=SC2016 # $1 is expanded by the inner sh, not here
    podman unshare sh -c 'mkdir "$1" && chown 1:1 "$1" && chmod 775 "$1"' _ "$REC/drop"
    ST4=$(python3 - "$RR_TOOL" "$REC" "$RR_LEDGER" "$SUBUID" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("rr", sys.argv[1])
rr = importlib.util.module_from_spec(spec); spec.loader.exec_module(rr)
t, why = rr._store_tier(sys.argv[2], sys.argv[3], 65534, int(sys.argv[4]), ranges=[], getpw=lambda u: object())
print(t, "drop" in (why or "") and "writable" in (why or ""))
PY
)
    podman unshare rmdir "$REC/drop"
    expect R4-CAP6 "$ST4" "instance True" "a group-writable directory inside the store makes it instance (a writer could add a record)"
    # R4-F2 in the capability-shaped tree: the producer cannot even add its row
    if ( : > "$REC/zz_backfill.json" ) 2>/dev/null; then
      bad "R4-CAP7: the producer could create a file inside the owner-only store"
    else ok "R4-CAP7: in a capability-shaped store the producer cannot add a backfill row at all (permission denied) -- and any file it could add would be outside the owner allowlist"; fi
  else
    bad "R4-CAP-needle: podman unshare chown did not produce a subordinate-owned tree (uid $(stat -c %u "$REC/r1.json"), want $SUBUID)"
  fi
fi

echo ""
echo "== Summary: ok $PASS / NOT ok $FAIL =="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
