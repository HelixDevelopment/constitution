#!/usr/bin/env bash
# =============================================================================
# test_collect_baseline_red.sh -- first regression guard for
# cycle/collect_baseline.py (T045). T048 restart round 1 review R6 (F14) found
# the module had NO test at all; F9, F12, F21 and F22 were open in it.
#
# Drives the REAL collect_baseline.py end to end (the real select_sample.py and
# the real baseline_replay.sh underneath) against a hermetic fixture: a tiny git
# repo whose commit subjects name the sample items, and a tiny sqlite tracker DB
# with the two tables select_sample.py reads. Nothing touches this project's own
# tracker DB or multi-GB tree.
#
# Cases (tag -> finding):
#   C-F12  an ambient FC_OUT (fc_common determinism-check env) must not hijack the
#          per-item freeze/replay child processes.
#   C-F9   per-type medians pool PASS runs only (a crashed/FAILed run is not a
#          gate-speed measurement).
#   C-F21  --replay-item-ids naming an id that is not in the sample is refused;
#          the "owed follow-up" note appears only for a genuinely reduced run.
#   C-F22  the reopen rate's numerator is matched to its denominator (reopened
#          AFTER an in-window closure), so it can never exceed 1.
#   C-HE   a harness failure (a gate that cannot start) makes the run exit 4
#          (the baseline is still written, with the reason per item).
#   C-FRESH a --fresh-execution-json path that does not exist is refused.
#   C-V43  (round 2, V4-3) "DEC-36 protocol met" is written only when every
#          duration-eligible item really has >= 10 measured (PASS) cold and warm
#          runs: a run in which every gate run crashed, a sample of zero items, or
#          a run with zero measured runs exits 4 and never claims the protocol.
#   C-V411 (round 2, V4-11) the token baseline never claims a corpus search this
#          tool did not perform.
#   C-V413 (round 2, V4-13) an item id that could escape --out-dir as a path
#          ('/', '..', NUL, whitespace) is refused before anything is written.
#
# Env: FC_CB_UNDER_TEST (collect_baseline.py path), FC_BR_UNDER_TEST
# (baseline_replay.sh path) -- the paired-mutation runner points these at mutants.
#      CB_ONLY -- space-separated case tags to run (default all).
# Exit: 0 all selected cases held; 1 any NOT ok.
# =============================================================================
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FC="$(cd "$HERE/.." && pwd)"
CB="${FC_CB_UNDER_TEST:-$FC/cycle/collect_baseline.py}"
BR="${FC_BR_UNDER_TEST:-$FC/cycle/baseline_replay.sh}"
SS="$FC/cycle/select_sample.py"

PASS=0
FAIL=0
ok()  { PASS=$((PASS+1)); echo "ok $*"; }
bad() { FAIL=$((FAIL+1)); echo "NOT ok $*"; }
want() {
  [ -z "${CB_ONLY:-}" ] && return 0
  case " $CB_ONLY " in *" $1 "*) return 0 ;; esac
  return 1
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# jget <json-file> <python-expr over d>: the JSON is read from the file; the
# expression is always a literal written in THIS test file (never data), so the
# eval() below evaluates only test-authored code.
jget() {
  python3 - "$1" "$2" <<'PY' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print("<unreadable>")
    sys.exit(0)
v = eval(sys.argv[2], {"d": d})
print(json.dumps(v) if not isinstance(v, str) else v)
PY
}

g() { git -c user.email=t@t.t -c user.name=t "$@"; }

# --- fixture repo: one commit per item; ATM-954's tree carries crash.flag ---
REPO="$WORK/repo"
mkdir -p "$REPO"
g init -q "$REPO"
echo base >"$REPO/f.txt"; g -C "$REPO" add f.txt; g -C "$REPO" commit -q -m "base"
c() { echo "$1" >>"$REPO/f.txt"; g -C "$REPO" add -A; g -C "$REPO" commit -q -m "$1 fix"; }
c ATM-953
: >"$REPO/crash.flag"; c ATM-954
rm "$REPO/crash.flag"; c ATM-955
c ATM-200; c ATM-201; c ATM-202

# --- fixture tracker DB (as_of 2026-08-01, 30-day window -> from 2026-07-02) ---
DB="$WORK/items.db"
python3 - "$DB" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
c.execute("CREATE TABLE items (atm_id TEXT PRIMARY KEY, type TEXT)")
c.execute("CREATE TABLE item_history (id INTEGER PRIMARY KEY AUTOINCREMENT, atm_id TEXT, "
          "event_type TEXT, by TEXT, on_date TEXT, reason TEXT, evidence_path TEXT, created_at TEXT)")
rows = [
    # ATM-953 is select_sample.py's default control needle (Fixed on 2026-07-28)
    ("ATM-953", "Opened", "2026-07-10"), ("ATM-953", "Fixed", "2026-07-28"),
    ("ATM-954", "Opened", "2026-07-05"), ("ATM-954", "Fixed", "2026-07-20"),
    # closed in the window, then genuinely reopened in the window
    ("ATM-955", "Opened", "2026-07-03"), ("ATM-955", "Fixed", "2026-07-22"),
    ("ATM-955", "Reopened", "2026-07-25"),
    # closed BEFORE the window, reopened inside it: not in the denominator
    ("ATM-200", "Opened", "2026-05-01"), ("ATM-200", "Fixed", "2026-05-10"),
    ("ATM-200", "Reopened", "2026-07-15"),
    ("ATM-201", "Opened", "2026-05-01"), ("ATM-201", "Fixed", "2026-05-11"),
    ("ATM-201", "Reopened", "2026-07-16"),
    ("ATM-202", "Opened", "2026-05-01"), ("ATM-202", "Fixed", "2026-05-12"),
    ("ATM-202", "Reopened", "2026-07-17"),
]
for atm in sorted({r[0] for r in rows}):
    c.execute("INSERT INTO items VALUES (?, 'Bug')", (atm,))
for atm, ev, day in rows:
    c.execute("INSERT INTO item_history (atm_id, event_type, by, on_date, reason, evidence_path, created_at) "
              "VALUES (?, ?, 'test', ?, NULL, ?, ?)",
              (atm, ev, day, "qa/%s/%s.md" % (atm, ev), day + "T00:00:00Z"))
c.commit()
PY

# A gate that crashes fast when crash.flag is present, else PASSes after 0.4 s.
GATE="$WORK/gate.sh"
printf '#!/bin/sh\n[ -f crash.flag ] && exit 2\nsleep 0.4\nexit 0\n' >"$GATE"; chmod +x "$GATE"

# run_cb <out-dir> [extra args...] -> rc in CB_RC
run_cb() {
  local od="$1"; shift
  python3 "$CB" --as-of 2026-08-01 --window-days 30 --min-per-type 5 --repo-root "$REPO" \
    --db-path "$DB" --out-dir "$od" --select-sample-bin "$SS" --baseline-replay-bin "$BR" \
    --worktree-root "$WORK/wt" --min-free-kb 0 --min-free-kb-objects 0 --plausible-floor-ms 0 --timeout-s 60 "$@" \
    >"$od.stdout" 2>"$od.stderr"
  CB_RC=$?
}

[ -f "$CB" ] || { echo "NOT ok collect_baseline.py not found at $CB"; exit 1; }

# -----------------------------------------------------------------------------
if want C-F12; then
  OD="$WORK/fcout"
  FC_OUT="$WORK/hijack.json" run_cb "$OD" --gate-cmd true --cold-runs 1 --warm-runs 0 --replay-item-ids ATM-953
  B="$OD/baseline.json"
  FZ="$(jget "$B" 'sorted(k for k, v in d["freeze"].items() if v["commit"] in (None, "UNMEASURED"))')"
  RP="$(jget "$B" '[r["replayed"] for r in d["gate_window_replay"]["per_item"] if r["item_id"]=="ATM-953"][0]')"
  if [ "$CB_RC" = 0 ] && [ "$FZ" = "[]" ] && [ "$RP" = true ] && [ ! -e "$WORK/hijack.json" ]; then
    ok "[C-F12] under an ambient FC_OUT every item froze to a real commit, ATM-953 replayed, and no child wrote to FC_OUT"
  else
    bad "[C-F12] under FC_OUT: rc=$CB_RC unmeasured-freezes=$FZ ATM-953-replayed=$RP hijack-file-written=$([ -e "$WORK/hijack.json" ] && echo yes || echo no) -- FC_OUT leaked into the child tools ($(tail -c 300 "$OD.stderr"))"
  fi
fi

if want C-F9 || want C-F22; then
  OD="$WORK/main"
  run_cb "$OD" --gate-cmd "$GATE" --cold-runs 1 --warm-runs 1
  B="$OD/baseline.json"
  if want C-F9; then
    N="$(jget "$B" 'd["gate_window_replay"]["per_type_medians"]["Bug"]["cold"]["n_runs"]')"
    M="$(jget "$B" 'd["gate_window_replay"]["per_type_medians"]["Bug"]["cold"]["median_ms"]')"
    X="$(jget "$B" 'd["gate_window_replay"]["per_type_medians"]["Bug"]["cold"].get("n_excluded_non_pass")')"
    if [ "$N" = 5 ] && [ "$X" = 1 ] && [ "$M" -ge 350 ] 2>/dev/null; then
      ok "[C-F9] the Bug cold median pools the 5 PASS runs only (${M}ms); the 1 crashed run is counted as excluded"
    else
      bad "[C-F9] Bug cold pool: n_runs=$N excluded=$X median=$M (want 5 / 1 / >=350) -- a crashed FAIL run was pooled into the gate-speed baseline (rc=$CB_RC)"
    fi
  fi
  if want C-F22; then
    RATE="$(jget "$B" 'd["reopen_baseline"]["by_type"]["Bug"]["reopen_rate"]')"
    WANT="$(python3 -c 'print(round(1/3, 6))')"
    OVER="$(jget "$B" 'd["reopen_baseline"]["overall"]["reopen_rate"]')"
    if [ "$RATE" = "$WANT" ] && [ "$OVER" = "$WANT" ]; then
      ok "[C-F22] the reopen rate counts only items reopened after an in-window closure (Bug rate $RATE = 1/3)"
    else
      bad "[C-F22] Bug reopen rate=$RATE overall=$OVER (want $WANT) -- items closed before the window were counted in the numerator"
    fi
  fi
fi

# -----------------------------------------------------------------------------
if want C-F21; then
  OD="$WORK/unknown"
  run_cb "$OD" --gate-cmd "$GATE" --cold-runs 1 --warm-runs 1 --replay-item-ids "ATM-953,ATM-99999"
  if [ "$CB_RC" = 2 ] && grep -q "ATM-99999" "$OD.stderr"; then
    ok "[C-F21] --replay-item-ids naming an id outside the sample is refused (exit 2, id named)"
  else
    bad "[C-F21] unknown --replay-item-ids id: rc=$CB_RC -- it was silently dropped ($(tail -c 200 "$OD.stderr"))"
  fi
  OD="$WORK/reduced"
  run_cb "$OD" --gate-cmd true --cold-runs 1 --warm-runs 1 --replay-item-ids ATM-953
  NOTE="$(jget "$OD/baseline.json" 'd["gate_window_replay"]["full_protocol_note"]')"
  case "$NOTE" in *"OWED FOLLOW-UP"*"1 of 6"*|*"1 of 6"*"OWED FOLLOW-UP"*) good1=1 ;; *) good1=0 ;; esac
  OD="$WORK/full"
  run_cb "$OD" --gate-cmd true --cold-runs 10 --warm-runs 10
  NOTE2="$(jget "$OD/baseline.json" 'd["gate_window_replay"]["full_protocol_note"]')"
  # positive control for the V4-3 rule: a run in which every eligible item has
  # 10/10 measured PASS runs is the one case that may say "protocol met"
  case "$NOTE2" in *"OWED FOLLOW-UP"*) good2=0 ;; *"protocol met"*) good2=1 ;; *) good2=0 ;; esac
  if [ "$good1" = 1 ] && [ "$good2" = 1 ] && [ "$CB_RC" = 0 ]; then
    ok "[C-F21] the owed-follow-up note appears for a reduced run (1 of 6 items) and not for a full 10/10 run over every eligible item"
  else
    bad "[C-F21] protocol note: reduced='$NOTE' full='$NOTE2' (rc=$CB_RC)"
  fi
fi

# -----------------------------------------------------------------------------
if want C-HE; then
  OD="$WORK/harness"
  run_cb "$OD" --gate-cmd nosuchcmd_cb_xyz --cold-runs 1 --warm-runs 0 --replay-item-ids ATM-953
  R="$(jget "$OD/baseline.json" '[r["reason"] for r in d["gate_window_replay"]["per_item"] if r["item_id"]=="ATM-953"][0]')"
  if [ "$CB_RC" = 4 ] && [ -f "$OD/baseline.json" ] && case "$R" in *"harness"*) true ;; *) false ;; esac; then
    ok "[C-HE] a gate that cannot start makes the run exit 4; the baseline is still written with the reason ($R)"
  else
    bad "[C-HE] harness failure: rc=$CB_RC reason='$R' -- a run that could not measure exited as if it had"
  fi
  OD="$WORK/notrepo"
  mkdir -p "$WORK/notrepo_root"
  python3 "$CB" --as-of 2026-08-01 --window-days 30 --repo-root "$WORK/notrepo_root" --db-path "$DB" \
    --out-dir "$OD" --select-sample-bin "$SS" --baseline-replay-bin "$BR" --skip-gate-replay \
    >"$OD.stdout" 2>"$OD.stderr"; rc=$?
  R2="$(jget "$OD/baseline.json" 'sorted({v.get("reason", "") for v in d["freeze"].values()})')"
  if [ "$rc" = 4 ] && case "$R2" in *"harness"*) true ;; *) false ;; esac; then
    ok "[C-HE] a freeze that fails (repo root is not a git repo) is a harness error (exit 4), never 'no commit found'"
  else
    bad "[C-HE] freeze against a non-repo: rc=$rc reasons=$R2"
  fi
fi

# -----------------------------------------------------------------------------
if want C-FRESH; then
  OD="$WORK/fresh"
  run_cb "$OD" --skip-gate-replay --fresh-execution-json "$WORK/no_such_fresh.json"
  if [ "$CB_RC" = 2 ] && grep -q "no_such_fresh.json" "$OD.stderr"; then
    ok "[C-FRESH] a --fresh-execution-json path that does not exist is refused (exit 2), not recorded as NOT_YET_RECORDED"
  else
    bad "[C-FRESH] missing --fresh-execution-json file: rc=$CB_RC -- a typo'd path hid behind an honest-looking status"
  fi
fi

# -----------------------------------------------------------------------------
if want C-V43; then
  OD="$WORK/allcrash"
  run_cb "$OD" --gate-cmd false --cold-runs 10 --warm-runs 10
  B="$OD/baseline.json"
  NOTE="$(jget "$B" 'd["gate_window_replay"]["full_protocol_note"]')"
  NR="$(jget "$B" 'd["gate_window_replay"]["overall_medians"]["cold"]["n_runs"] + d["gate_window_replay"]["overall_medians"]["warm"]["n_runs"]')"
  case "$NOTE" in *"protocol met"*) met=1 ;; *) met=0 ;; esac
  if [ "$CB_RC" = 4 ] && [ "$met" = 0 ] && [ "$NR" = 0 ] && [ -f "$B" ]; then
    ok "[C-V43] every gate run crashed (10/10 x 6 items, 0 measured): exit 4, the note does not claim the protocol ('${NOTE:0:90}...')"
  else
    bad "[C-V43] all-crash run: rc=$CB_RC measured-runs=$NR note='$NOTE' -- 'protocol met' with nothing measured"
  fi
  # one item short of 10 PASS runs (ATM-954 crashes) with 10/10 requested: not met
  OD="$WORK/onecrash"
  run_cb "$OD" --gate-cmd "$GATE" --cold-runs 10 --warm-runs 10
  NOTE="$(jget "$OD/baseline.json" 'd["gate_window_replay"]["full_protocol_note"]')"
  case "$NOTE" in *"protocol met"*) met=1 ;; *) met=0 ;; esac
  if [ "$CB_RC" = 0 ] && [ "$met" = 0 ] && case "$NOTE" in *ATM-954*) true ;; *) false ;; esac; then
    ok "[C-V43] one item whose every run crashed (ATM-954): the protocol is NOT claimed met and the item is named"
  else
    bad "[C-V43] one all-crash item: rc=$CB_RC note='$NOTE' -- an item with zero measured runs was counted as replayed to protocol"
  fi
  # zero items in the sample: exit 4, never "met"
  OD="$WORK/zeroitems"
  run_cb "$OD" --gate-cmd true --cold-runs 10 --warm-runs 10 --as-of 2026-08-01 --window-days 1
  NOTE="$(jget "$OD/baseline.json" 'd["gate_window_replay"]["full_protocol_note"]')"
  NI="$(jget "$OD/baseline.json" 'd["sample"]["total_items"]')"
  case "$NOTE" in *"protocol met"*) met=1 ;; *) met=0 ;; esac
  if [ "$CB_RC" = 4 ] && [ "$NI" = 0 ] && [ "$met" = 0 ]; then
    ok "[C-V43] a sample of zero items exits 4 and does not claim the protocol"
  else
    bad "[C-V43] zero-item sample: rc=$CB_RC items=$NI note='$NOTE'"
  fi
  # zero items under --skip-gate-replay too: a dry run over nothing is still
  # UNMEASURED (exit 4), never an honest-looking dry run
  OD="$WORK/zeroitems_dry"
  run_cb "$OD" --skip-gate-replay --as-of 2026-08-01 --window-days 1
  if [ "$CB_RC" = 4 ]; then
    ok "[C-V43] a zero-item sample exits 4 even under --skip-gate-replay"
  else
    bad "[C-V43] zero-item sample under --skip-gate-replay: rc=$CB_RC -- a baseline of nothing exited as a successful dry run"
  fi
  # --skip-gate-replay: an honest dry run (exit 0), but never "protocol met"
  OD="$WORK/dryrun"
  run_cb "$OD" --gate-cmd true --cold-runs 10 --warm-runs 10 --skip-gate-replay
  NOTE="$(jget "$OD/baseline.json" 'd["gate_window_replay"]["full_protocol_note"]')"
  case "$NOTE" in *"protocol met"*) met=1 ;; *) met=0 ;; esac
  if [ "$CB_RC" = 0 ] && [ "$met" = 0 ]; then
    ok "[C-V43] --skip-gate-replay is a dry run (exit 0) whose note does not claim the protocol"
  else
    bad "[C-V43] --skip-gate-replay: rc=$CB_RC note='$NOTE'"
  fi
fi

# -----------------------------------------------------------------------------
if want C-V411; then
  OD="$WORK/tokens"
  run_cb "$OD" --skip-gate-replay
  RS="$(jget "$OD/baseline.json" 'sorted({i["reason"] for i in d["token_baseline"]["per_item"]})')"
  case "$RS" in *"corpus search"*|*"found by direct"*) claim=1 ;; *) claim=0 ;; esac
  if [ "$CB_RC" = 0 ] && [ "$claim" = 0 ] && case "$RS" in *"performs no"*) true ;; *) false ;; esac; then
    ok "[C-V411] the token baseline states that this tool searched nothing, and claims no corpus search"
  else
    bad "[C-V411] token reasons=$RS (rc=$CB_RC) -- a corpus search this tool never ran is claimed for every item"
  fi
fi

# -----------------------------------------------------------------------------
if want C-V413; then
  DB2="$WORK/items_bad.db"
  cp "$DB" "$DB2"
  python3 - "$DB2" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
bad = "ATM-9/../../../escaped"
c.execute("INSERT INTO items VALUES (?, 'Bug')", (bad,))
for ev, day in (("Opened", "2026-07-04"), ("Fixed", "2026-07-21")):
    c.execute("INSERT INTO item_history (atm_id, event_type, by, on_date, reason, evidence_path, created_at) "
              "VALUES (?, ?, 'test', ?, NULL, 'qa/x.md', ?)", (bad, ev, day, day + "T00:00:00Z"))
c.commit()
PY
  OD="$WORK/v413/out"
  mkdir -p "$WORK/v413"
  python3 "$CB" --as-of 2026-08-01 --window-days 30 --min-per-type 50 --repo-root "$REPO" \
    --db-path "$DB2" --out-dir "$OD" --select-sample-bin "$SS" --baseline-replay-bin "$BR" --skip-gate-replay \
    >"$WORK/v413.stdout" 2>"$WORK/v413.stderr"; rc=$?
  INS="$(jget "$OD/sample.json" '[i["item_id"] for i in d.get("items", []) if "/" in i["item_id"]]')"
  ESC="$(find "$WORK" -name 'escaped.json' 2>/dev/null | head -1)"
  if [ "$rc" = 4 ] && [ "$INS" != "[]" ] && [ -z "$ESC" ] && grep -q "ATM-9/../../../escaped" "$WORK/v413.stderr"; then
    ok "[C-V413] a sampled item id holding '/' and '..' is refused (exit 4, id named) and nothing is written for it"
  else
    bad "[C-V413] unsafe id: rc=$rc sampled=$INS escaped-file='$ESC' -- a DB item id was used as a path ($(tail -c 200 "$WORK/v413.stderr"))"
  fi
fi

echo "----"
echo "SUMMARY pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
