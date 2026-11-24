"""Sync engine (anchor 11.4.300(B),(C),(D),(E)): plan / apply / verify. DB -> tracker, one way. Pure given adapters; dry-run default.
Identity: title prefix '[ID] ' plus hidden footer '<!-- workable-item: ID | sha256: HASH -->'; the issue number is never the identity."""
import re

from . import payload as pl
from . import visibility as vis

CLOSED_STATUS_PREFIXES = ("Fixed", "Implemented", "Completed", "Obsolete")
FOOTER = re.compile(r"<!--\s*workable-item:\s*([A-Za-z0-9._-]+)\s*\|\s*sha256:\s*([0-9a-f]{64})\s*-->")
SYNC_LABEL = "wi-sync"


def is_closed(status):
    return status.startswith(CLOSED_STATUS_PREFIXES)


def slug(s):
    return re.sub(r"[^a-z0-9]+", "-", s.split(" (")[0].lower()).strip("-")


def labels_for(p):
    return sorted([SYNC_LABEL, "status:" + slug(p["status"]), "type:" + p["type"].lower()])


def render(p, h, doc_path=None):
    """-> (title, body). Body holds only mirrored fields, a repo-relative pointer and the hidden footer."""
    body = p["description"].strip()
    if p["severity"]:
        body += "\n\nSeverity: " + p["severity"]
    body += "\n\nStatus: %s | Type: %s" % (p["status"], p["type"])
    if doc_path:
        body += "\nDetails (repo readers only): `%s`" % doc_path
    body += "\n\n<!-- workable-item: %s | sha256: %s -->" % (p["atm_id"], h)
    return "[%s] %s" % (p["atm_id"], p["title"]), body


def key_of(issue):
    m = FOOTER.search(issue.get("body") or "")
    if m:
        return m.group(1), m.group(2)
    m = re.match(r"\[([A-Za-z0-9._-]+)\]", issue.get("title") or "")
    return (m.group(1), None) if m else (None, None)


def index_issues(issues):
    """-> ({key: [issues sorted by number]}, adopted-less). Duplicates are every key with more than one issue."""
    idx = {}
    for i in issues:
        k, _ = key_of(i)
        if k:
            idx.setdefault(k, []).append(i)
    for v in idx.values():       # footer-keyed (engine-owned) issues first: an unkeyed title match never shadows ours
        v.sort(key=lambda x: (0 if FOOTER.search(x.get("body") or "") else 1, x["number"]))
    return idx


class Leg:
    """One (item-owner-repo, tracker) target: adapter, owner/repo on that host, resolved visibility and capability state."""
    def __init__(self, host, owner, repo, adapter, visibility, exists=True, issues_enabled=True):
        self.host, self.owner, self.repo, self.adapter, self.visibility = host, owner, repo, adapter, visibility
        self.exists, self.issues_enabled = exists, issues_enabled

    @property
    def id(self):
        return "%s/%s/%s" % (self.host, self.owner, self.repo)

    def unconfirmed_reason(self, need):
        if not self.exists:
            return "repo-absent"
        if self.issues_enabled is False:
            return "issues-disabled"
        for c in need:
            if not self.adapter.capabilities.get(c):
                return "capability-unverified:" + c
        return None


def plan_leg(items, leg, owner_vis, owner_repo, issues, fingerprint_set=None, known_ids=None):
    """Return a list of actions for one leg. Action: {op, item, number?, reason?}. ops: create update close reopen noop
    blocked unconfirmed duplicate orphan anomaly. `issues` is the leg's full issue listing (state=all). `known_ids` = every item id this
    repository owns (default: the ids in `items`); a filtered run (--only-open/--limit) passes the unfiltered set so out-of-scope items'
    issues are not reported as orphans."""
    if issues is None:     # the leg's issues cannot be listed: nothing may be planned from an assumed-empty listing
        r = leg.unconfirmed_reason(["can_list"]) or "capability-unverified:can_list"
        return [{"op": "unconfirmed", "item": it["atm_id"], "reason": r} for it in items]
    acts = []
    target = vis.canonical_repo("ssh://git@%s/%s/%s.git" % (leg.host, leg.owner, leg.repo))   # same canonical form as the owner (case, nested groups)
    ok, why = vis.allowed_target(owner_repo, target, owner_vis, leg.visibility)
    idx = index_issues(issues)
    known = set(known_ids or ())
    for it in items:
        aid = it["atm_id"]
        known.add(aid)
        if not ok:
            acts.append({"op": "blocked", "item": aid, "reason": why})
            continue
        res = pl.prepare(it, fingerprint_set)
        if res["verdict"] == "BLOCKED":
            acts.append({"op": "blocked", "item": res["item"], "reason": "redaction:" + ",".join(sorted({h["kind"] for h in res["hits"]}))})
            continue
        h, want_closed = res["hash"], is_closed(res["payload"]["status"])
        found = idx.get(aid, [])
        if len(found) > 1:
            acts.append({"op": "duplicate", "item": aid, "numbers": [f["number"] for f in found]})
        if not found:
            need = ["can_create"] + (["can_close"] if want_closed else [])
            r = leg.unconfirmed_reason(need)
            acts.append({"op": "unconfirmed", "item": aid, "reason": r} if r else {"op": "create", "item": aid, "closed": want_closed})
            continue
        cur = found[0]
        if not FOOTER.search(cur.get("body") or ""):
            # a human-made issue whose title merely starts with '[ID]': never adopted or overwritten (adoption is item C7), reported instead
            acts.append({"op": "anomaly", "item": aid, "number": cur["number"], "reason": "unkeyed-title-match"})
            continue
        _, cur_hash = key_of(cur)
        want_title, want_body = render(res["payload"], h)
        if cur_hash != h or cur["title"] != want_title or (cur.get("body") or "").strip() != want_body.strip() \
                or (leg.adapter.capabilities.get("can_label") and sorted(cur["labels"]) != labels_for(res["payload"])):
            r = leg.unconfirmed_reason(["can_update"])
            if r:
                acts.append({"op": "unconfirmed", "item": aid, "reason": r})
                continue
            acts.append({"op": "update", "item": aid, "number": cur["number"]})
        if want_closed and cur["state"] != "closed":
            r = leg.unconfirmed_reason(["can_close"])
            acts.append({"op": "unconfirmed", "item": aid, "reason": r} if r else {"op": "close", "item": aid, "number": cur["number"]})
        elif not want_closed and cur["state"] != "open":
            r = leg.unconfirmed_reason(["can_reopen"])
            acts.append({"op": "unconfirmed", "item": aid, "reason": r} if r else {"op": "reopen", "item": aid, "number": cur["number"]})
        if not any(a["item"] == aid and a["op"] != "duplicate" for a in acts):
            acts.append({"op": "noop", "item": aid})
    for k, lst in idx.items():
        if k not in known and any(FOOTER.search(i.get("body") or "") for i in lst):
            acts.append({"op": "orphan", "item": k, "numbers": [i["number"] for i in lst]})
    return acts


def apply_leg(items, leg, actions, doc_path_for=lambda it: None, on_done=None, apply=False, fingerprint_set=None):
    """Execute create/update/close/reopen actions. Dry-run (apply=False) performs NO write and returns the same list marked dry. Resumable:
    each action is idempotent through the footer key; on_done(action, issue) checkpoints the map after every successful write."""
    by_id = {i["atm_id"]: i for i in items}
    out = []
    for a in actions:
        if a["op"] not in ("create", "update", "close", "reopen"):
            out.append(dict(a, done=False))
            continue
        if not apply:
            out.append(dict(a, done=False, dry=True))
            continue
        it = by_id[a["item"]]
        res = pl.prepare(it, fingerprint_set)
        if res["verdict"] != "OK":                      # re-gate immediately before the write
            out.append(dict(a, done=False, error="redaction-regate"))
            continue
        title, body = render(res["payload"], res["hash"], doc_path_for(it))
        lab = labels_for(res["payload"])
        ad = leg.adapter
        if a["op"] == "create":
            ad.ensure_labels(leg.owner, leg.repo, lab)
            issue = ad.create_issue(leg.owner, leg.repo, title, body, lab)
            if a.get("closed"):
                issue = ad.set_state(leg.owner, leg.repo, issue["number"], "closed", not_planned=res["payload"]["status"].startswith("Obsolete") and ad.capabilities.get("not_planned", False))
        elif a["op"] == "update":
            issue = ad.update_issue(leg.owner, leg.repo, a["number"], title, body, lab)
        elif a["op"] == "close":
            issue = ad.set_state(leg.owner, leg.repo, a["number"], "closed", not_planned=res["payload"]["status"].startswith("Obsolete") and ad.capabilities.get("not_planned", False))
        else:
            issue = ad.set_state(leg.owner, leg.repo, a["number"], "open")
        if on_done:
            on_done(a, issue, res["hash"])
        out.append(dict(a, done=True, number=issue["number"]))
    return out


def verify_leg(items, leg, owner_vis, owner_repo, issues, fingerprint_set=None, known_ids=None):
    """-> (rc, findings). 1 drift, 2 cannot determine, 0 in sync; precedence 1 over 2 over 0. Reads only."""
    acts = plan_leg(items, leg, owner_vis, owner_repo, issues, fingerprint_set, known_ids)
    drift = [a for a in acts if a["op"] in ("create", "update", "close", "reopen", "duplicate", "orphan", "anomaly")]
    und = [a for a in acts if a["op"] in ("blocked", "unconfirmed")]
    if drift:
        return 1, drift + und
    if und:
        return 2, und
    return 0, []
