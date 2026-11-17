#!/usr/bin/env python3
"""mark_census.py - path-wise census of the class "a mark held across several bounded calls" (round 9, review R8-1).

GATE-LOGIC instrument (§11.4.289(C)(2)): it reads the trace that scripts/jev/jev-place.sh writes under JEV_TEST=1 when
JEV_TRACE_FILE is set (one line per event, appended by the producer process itself):

    call <pid> <args of the bounded call>          e.g. "call 4711 llmctl stop decide-b"
    save <pid> <json: {profile: {"stopping": <pid|null>, "starting": <pid|null>}}>   after every registry write

Invariant checked for every `llmctl stop <p>` and `llmctl start <p>` call of a process X:
  (1) X's last registry write before the call shows set <p> marked (stopping for a stop, starting for a start) by X;
  (2) that mark first appeared in X's writes AFTER X's previous bounded call (if any): a mark written before an earlier
      bounded call of X and still in place is a mark held across several bounded calls, the class R8-1 belongs to.
A mark of X that disappears from X's writes and comes back counts as a new mark.

Exit codes: 0 every checked call satisfies the invariant (the counts are printed, the zero is a finding only with the
control needle: --needle requires at least one checked stop and one checked start); 1 a violation (each one printed);
2 usage / unreadable trace / a trace with nothing to check (BLIND, never a clean zero).
"""
import json
import sys


def main(argv):
    needle = False
    paths = []
    for a in argv[1:]:
        if a == "--needle":
            needle = True
        else:
            paths.append(a)
    if not paths:
        print("usage: mark_census.py [--needle] <trace>...", file=sys.stderr)
        return 2
    events = []
    for p in paths:
        try:
            with open(p, encoding="utf-8", errors="replace") as fh:
                for ln in fh:
                    events.append((p, ln.rstrip("\n")))
        except OSError as e:
            print(f"mark_census: cannot read {p}: {e}", file=sys.stderr)
            return 2
    # per (trace file, pid): ordered list of events
    seq = {}
    for (p, ln) in events:
        parts = ln.split(" ", 2)
        if len(parts) < 3 or parts[0] not in ("call", "save"):
            continue
        seq.setdefault((p, parts[1]), []).append((parts[0], parts[2]))
    checked = {"stop": 0, "start": 0}
    viol = []
    for (p, pid), evs in seq.items():
        last_call_idx = -1
        first_seen = {}   # (profile, kind) -> index of the write where X's current mark first appeared
        cur_marks = set()
        for i, (kind, rest) in enumerate(evs):
            if kind == "save":
                try:
                    m = json.loads(rest)
                except ValueError:
                    viol.append(f"{p} pid {pid}: unparseable save line: {rest[:120]}")
                    continue
                now = set()
                for prof, mk in m.items():
                    for mkind in ("stopping", "starting"):
                        if str(mk.get(mkind)) == pid:
                            now.add((prof, mkind))
                for key in now - cur_marks:
                    first_seen[key] = i
                for key in cur_marks - now:
                    first_seen.pop(key, None)
                cur_marks = now
                continue
            toks = rest.split()
            if len(toks) >= 3 and toks[-2] in ("stop", "start"):
                verb, prof = toks[-2], toks[-1]
                mkind = "stopping" if verb == "stop" else "starting"
                checked[verb] += 1
                key = (prof, mkind)
                if key not in cur_marks:
                    viol.append(f"{p} pid {pid}: '{rest}' runs while {prof} carries no {mkind} mark of this process")
                elif first_seen.get(key, -1) < last_call_idx:
                    viol.append(f"{p} pid {pid}: '{rest}' runs under a {mkind} mark written before an earlier bounded call of this process (held across bounded calls)")
            last_call_idx = i
    print(f"mark_census: processes={len(seq)} checked_stops={checked['stop']} checked_starts={checked['start']} violations={len(viol)}")
    for v in viol:
        print("VIOLATION " + v)
    if not seq:
        print("mark_census: BLIND (no trace events)", file=sys.stderr)
        return 2
    if needle and (checked["stop"] == 0 or checked["start"] == 0):
        print("mark_census: BLIND (the needle needs at least one checked stop and one checked start)", file=sys.stderr)
        return 2
    return 1 if viol else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
