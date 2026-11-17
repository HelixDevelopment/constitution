#!/usr/bin/env python3
"""sanitise_p43.py IN.json OUT.json: the net_probe.py sample file reduced to what the C43 diagnosis needs and nothing
that could carry a real value: per sample ppid, pgid, argv (paths and the probe URL only), env_count, and
test_names = the NAMES of environment entries whose value holds one of the suite's fake ZZ markers; plus rc,
elapsed, leftover. The caller environment itself (which may hold real values of the host session) is dropped."""
import json, sys
Z = ("ZZM3W43", "ZZXYZ43", "ZZGH43", "ZZGL43", "ZZRPG43", "ZZXH43", "ZZCREDPW43")
d = json.load(open(sys.argv[1]))
out = {"rc": d.get("rc"), "elapsed": round(d.get("elapsed", 0), 2), "leftover": d.get("leftover"), "samples": []}
for s in d["samples"]:
    env = s.get("env")
    out["samples"].append({"ppid": s["ppid"], "pgid": s["pgid"], "argv": s["argv"],
                           "env_count": None if env is None else len(env),
                           "test_names": None if env is None else sorted(e.split("=", 1)[0] for e in env if any(z in e for z in Z))})
json.dump(out, open(sys.argv[2], "w"), indent=1, sort_keys=True)
