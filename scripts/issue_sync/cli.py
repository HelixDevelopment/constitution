#!/usr/bin/env python3
"""issue_sync CLI (anchor 11.4.300). Subcommands: plan (dry-run, default), apply (--apply required to write), verify (0/1/2), status.
All three-valued: 0 in sync / done, 1 drift / failure, 2 cannot determine (never a pass). A missing or disabled config exits 0 with 'disabled' (default OFF).
Targets: --target HOST/OWNER/REPO (repeatable). Tokens are read by variable NAME (credentials.py), never printed.
Visibility of the owning repo is resolved live from the target's repo_info; undetermined blocks."""
import argparse
import sqlite3
import datetime
import json
import sys

from . import config as cfgmod, credentials, registry, store, engine, visibility as vis
from .adapters.base import AdapterError, HttpTransport


def _legs(targets, hosts, transport_factory):
    legs = []
    for t in targets:
        host, owner, repo = t.split("/", 2)
        ad = registry.make(host, transport_factory, hosts)
        if ad is None:
            legs.append((t, None, "unknown-host"))
            continue
        try:
            info = ad.repo_info(owner, repo)
        except AdapterError as e:
            legs.append((t, None, e.code))
            continue
        v = "undetermined" if info["private"] is None else ("private" if info["private"] else "public")
        legs.append((t, engine.Leg(host, owner, repo, ad, v, info["exists"], info["issues_enabled"]), None))
    return legs


def _transport_factory(token_vars, host):
    st, _, tok = credentials.resolve(token_vars)
    return HttpTransport(tok if st == "found" else None)


def run(argv, transport_factory=_transport_factory, out=sys.stdout):
    ap = argparse.ArgumentParser(prog="issue_sync")
    ap.add_argument("cmd", choices=["plan", "apply", "verify", "status"])
    ap.add_argument("--config", default=".workable-items-sync.yaml")
    ap.add_argument("--db", default="docs/workable_items.db")
    ap.add_argument("--target", action="append", default=[])
    ap.add_argument("--owner-repo", help="HOST/OWNER/REPO owning the items of this DB (items route to its trackers only)")
    ap.add_argument("--db-repo", help="HOST/OWNER/REPO whose DB this is (owner of prefixes with no repo of their own); default --owner-repo")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--only-open", action="store_true", help="tier 1: skip items in a closed status")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args(argv)
    cfg, errs = cfgmod.load(a.config)
    if errs:
        print("CONFIG-INVALID: " + "; ".join(errs), file=out)
        return 2
    if not cfg["enabled"]:
        print("disabled (default OFF): nothing to do", file=out)
        return 0
    if a.cmd == "apply" and not (a.apply and cfg["mode"] == "apply"):
        print("apply refused: needs --apply AND mode: apply with a recorded apply_decision in the config (dry-run default)", file=out)
        return 2
    if not a.target or not a.owner_repo:
        print("cannot determine: --target and --owner-repo are required", file=out)
        return 2
    if any(t.count("/") < 2 for t in a.target) or a.owner_repo.count("/") < 2 or (a.db_repo and a.db_repo.count("/") < 2):
        print("cannot determine: --target/--owner-repo/--db-repo must be HOST/OWNER/REPO", file=out)
        return 2
    owner_repo = vis.canonical_repo("ssh://git@%s/%s.git" % tuple(a.owner_repo.split("/", 1)))
    db_repo = vis.canonical_repo("ssh://git@%s/%s.git" % tuple((a.db_repo or a.owner_repo).split("/", 1)))
    hosts = registry.load_hosts()
    try:
        con = store.open_db(a.db, write=(a.cmd == "apply"))
        items = store.load_items(con)
        prefixes, third, parents, has_table = store.load_sub_projects(con)
    except (sqlite3.Error, OSError) as e:
        print("cannot determine: workable-items DB unreadable (%s)" % type(e).__name__, file=out)
        return 2
    items = [i for i in items if not vis.is_third_party(i["atm_id"], third)]
    # route each item to its OWNING repository; only items owned by --owner-repo are ever written to its trackers
    own = {p: vis.canonical_repo(u) for p, u in prefixes.items()}
    routed, foreign, unroutable = [], 0, 0
    for i in items:
        pfx = i["atm_id"].split("-", 1)[0].upper()
        if pfx in own:
            o = own[pfx]
        elif pfx in parents or not has_table:
            o = db_repo                       # the parent / the DB's own repository (or a DB with no sub_projects table)
        else:
            unroutable += 1
            continue
        if o is not None and o[1:] == owner_repo[1:]:
            routed.append(i)
        else:
            foreign += 1
    items = routed
    if a.only_open:
        items = [i for i in items if not engine.is_closed(i["status"])]
    if a.limit:
        items = items[:a.limit]
    rc, report = 0, []
    tf = _transport_factory if transport_factory is None else transport_factory
    _, owner_leg, _ = _legs([a.owner_repo], hosts, tf)[0]           # the OWNING repo's own visibility, resolved live
    owner_vis = owner_leg.visibility if owner_leg else "undetermined"
    legs = _legs(a.target, hosts, tf)
    for tid, leg, err in legs:
        if leg is None:
            report.append({"leg": tid, "verdict": "UNDETERMINED", "reason": err})
            rc = max(rc, 2) if rc != 1 else 1
            continue
        try:
            issues = leg.adapter.list_issues(leg.owner, leg.repo) if leg.exists and leg.adapter.capabilities["can_list"] and leg.issues_enabled is not False else None
        except AdapterError as e:
            report.append({"leg": leg.id, "verdict": "UNDETERMINED", "reason": e.code})
            rc = 1 if rc == 1 else 2
            continue
        if a.cmd == "verify":
            r, f = engine.verify_leg(items, leg, owner_vis, owner_repo, issues)
            report.append({"leg": leg.id, "rc": r, "findings": f})
            rc = 1 if (r == 1 or rc == 1) else max(rc, r)
            continue
        acts = engine.plan_leg(items, leg, owner_vis, owner_repo, issues)
        if a.cmd == "apply":
            try:
                store.ensure_map(con)
            except sqlite3.Error as e:
                print("cannot determine: DB not writable (%s)" % type(e).__name__, file=out)
                return 2
            now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
            def done(act, issue, h, leg=leg):
                store.record(con, act["item"], leg.id, leg.host, "%s/%s" % (leg.owner, leg.repo), issue, h, now)
            try:
                acts = engine.apply_leg(items, leg, acts, on_done=done, apply=True)
            except AdapterError as e:
                report.append({"leg": leg.id, "verdict": "STOPPED", "reason": e.code})
                rc = 1
                continue
        counts = {}
        for x in acts:
            counts[x["op"]] = counts.get(x["op"], 0) + 1
        reasons = sorted({x["reason"] for x in acts if x["op"] in ("blocked", "unconfirmed")})   # ids never printed with reasons; counts only
        report.append({"leg": leg.id, "counts": counts, **({"reasons": reasons} if reasons else {})})
        if any(x["op"] in ("blocked", "unconfirmed") for x in acts):
            rc = max(rc, 2) if rc != 1 else 1
    if foreign or unroutable:
        report.append({"routing": {"not-owned-by-this-repo (never sent)": foreign, "unroutable-prefix (blocked)": unroutable}})
        if unroutable:
            rc = 1 if rc == 1 else 2
    print(json.dumps(report, indent=1) if a.json else "\n".join(json.dumps(r) for r in report), file=out)
    return rc


if __name__ == "__main__":
    sys.exit(run(sys.argv[1:]))
