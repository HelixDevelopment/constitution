#!/bin/bash
# test_review_record_store_tier_all_entries_regression.sh
#
# CON-033 round 2, review I4: the store tier (_store_tier in
# review/review_record.py) must cover EVERY entry of the evidence store --
# sub-directories and non-record files, not only *.json records (guard
# G-T-STORE-ALL-ENTRIES, reviewer mutant R4-C "store tier from records only").
#
# WHY A SEPARATE SUITE. The R4-CAP cases of
# test_review_record_gate_authority_r4_regression.sh kill R4-C, but they need
# `podman unshare` AND a writable directory whose whole chain is root-owned;
# with TMPDIR under a home directory (as on the reviewer's and the fixer's
# host) there is none, R4-CAP1..7 are SKIPPED, and R4-C survived every suite.
# This suite needs neither: it calls the real module in-process with an
# injected runner uid, so the evidence owner can be the uid that created the
# files, and it makes an entry foreign-writable with chmod (no chown). It is
# not one of the suites the sub-clause kill ledger hashes, so adding it does
# not make that ledger stale.
#
#   N   needle: a store whose every entry is owner-only is "capability"
#       (otherwise every "instance" below would prove nothing);
#   E1  a group-writable NON-record file (an archive) makes it "instance",
#       naming that file;
#   E2  a group-writable SUB-DIRECTORY holding a record makes it "instance";
#   E2b a group-writable EMPTY sub-directory (a drop box) makes it
#       "instance" -- only the walk over directories can see this one;
#   E3  an other-writable file with no extension makes it "instance";
#   E4  control: a group-writable *.json record makes it "instance" too.
#
# Exit 0 = all passed; 1 = a check failed; 2 = setup error. When the needle
# cannot be made capability-shaped on this host the suite FAILS: it never
# skips silently (a skip is what let R4-C survive).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
TOOL="$HERE/../review/review_record.py"
[ -f "$TOOL" ] || { echo "setup: missing $TOOL" >&2; exit 2; }
PASS=0; FAIL=0
ok()  { echo "PASS: $*"; PASS=$((PASS + 1)); }
bad() { echo "FAIL: $*"; FAIL=$((FAIL + 1)); }

# A base whose chain is owner-or-root and not foreign-writable without the
# sticky bit: try TMPDIR first, then /tmp (sticky, root-owned).
S=""
for base in "${TMPDIR:-}" /tmp; do
  [ -n "$base" ] && [ -d "$base" ] && [ -w "$base" ] || continue
  S=$(mktemp -d "$base/rr_store_tier.XXXXXX") && break
done
[ -n "$S" ] || { echo "setup: no writable temp base" >&2; exit 2; }
trap 'chmod -R u+rwx "${S:?}" 2>/dev/null; rm -rf -- "${S:?}"' EXIT
chmod 0755 "$S"
REC="$S/records"; mkdir -m 0755 "$REC"
LED="$S/ledger.jsonl"; : > "$LED"; chmod 0644 "$LED"
printf '{}\n' > "$REC/r1.json"; chmod 0644 "$REC/r1.json"
printf 'x\n' > "$REC/r1.verdict-evidence"; chmod 0644 "$REC/r1.verdict-evidence"
mkdir -m 0755 "$REC/sub"
printf '{}\n' > "$REC/sub/r2.json"; chmod 0644 "$REC/sub/r2.json"
printf 'n\n' > "$REC/notes"; chmod 0644 "$REC/notes"
mkdir -m 0755 "$REC/drop"   # an EMPTY sub-directory: no record below it

tier() { # tier -> "<tier>\t<reason>" from the REAL module, in-process
  python3 - "$TOOL" "$REC" "$LED" <<'PY'
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("rr", sys.argv[1])
rr = importlib.util.module_from_spec(spec); spec.loader.exec_module(rr)
me = os.geteuid()
# runner: a non-root uid that is neither the owner nor the producer; the
# producer: 65534 (any non-root uid other than both). getpw / ranges are
# injected (every uid is a passwd account; no subordinate range), so the ONLY
# thing that can refuse capability is the file-system check under test.
runner = me + 100000 if me + 100000 != 65534 else me + 100001
t, why = rr._store_tier(sys.argv[2], sys.argv[3], 65534, me, runner_uid=runner, ranges=[], getpw=lambda u: object())
print("%s\t%s" % (t, why or ""))
PY
}

if [ "$(id -u)" -eq 0 ]; then
  echo "setup: running as root -- root is excluded from the tier on purpose; this suite needs a non-root uid" >&2
  exit 2
fi

out=$(tier); t=${out%%$'\t'*}; why=${out#*$'\t'}
if [ "$t" = capability ]; then
  ok "N: an owner-only store (records, an archive, a sub-directory, a plain file) is capability"
else
  bad "N: the owner-only store is '$t' ($why) -- the chain above $S is not owner-only on this host, so the cases below prove nothing"
fi

case_mode() { # case_mode ID PATH MODE WANT_NAME DESCRIPTION
  local id="$1" p="$2" mode="$3" name="$4" desc="$5" old
  old=$(stat -c %a "$p")
  chmod "$mode" "$p"
  out=$(tier); t=${out%%$'\t'*}; why=${out#*$'\t'}
  chmod "$old" "$p"
  if [ "$t" = instance ] && case "$why" in *"$name"*) true ;; *) false ;; esac; then
    ok "$id: $desc (instance, naming $name)"
  else
    bad "$id: $desc -- got '$t' ($why), want instance naming $name"
  fi
}
case_mode E1 "$REC/r1.verdict-evidence" 0664 r1.verdict-evidence "a group-writable archive (not a record) makes the store instance"
case_mode E2 "$REC/sub" 0775 "$REC/sub" "a group-writable sub-directory makes the store instance"
case_mode E2b "$REC/drop" 0775 "$REC/drop" "a group-writable EMPTY sub-directory (no record below it) makes the store instance"
case_mode E3 "$REC/notes" 0646 notes "an other-writable file without an extension makes the store instance"
case_mode E4 "$REC/r1.json" 0664 r1.json "control: a group-writable record makes the store instance"

out=$(tier); t=${out%%$'\t'*}
[ "$t" = capability ] && ok "N2: after the cases the store is capability again (modes restored)" \
  || bad "N2: the store is '$t' after the cases (a mode was not restored)"

echo "== Summary: ok $PASS / NOT ok $FAIL =="
[ "$FAIL" -eq 0 ]
