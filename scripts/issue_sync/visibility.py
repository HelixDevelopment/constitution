"""Visibility resolution and the owning-repo routing rule (anchor 11.4.300(D)). Undetermined visibility BLOCKS; never defaults to public."""
import re

_SCP = re.compile(r"^(?:[\w.-]+@)?([\w.-]+):(?!//)/?(.+)$")
_URL = re.compile(r"^(?:https?|ssh|git)://(?:[^@/]+@)?([^/:]+)(?::\d+)?/(.+)$")


def canonical_repo(url):
    """(host, owner, repo) lower-cased, .git stripped; None when the URL is not a repo URL."""
    m = _URL.match(url or "") or _SCP.match(url or "")
    if not m:
        return None
    host, path = m.group(1).lower(), m.group(2).strip("/")
    if path.endswith(".git"):
        path = path[:-4]
    parts = path.split("/")
    if len(parts) < 2 or not all(parts[-2:]):
        return None
    return (host, parts[-2].lower(), parts[-1].lower())


def resolve(probe, repo=None):
    """probe(repo) -> {'private': bool} read from the live provider answer, or None. Anything else is undetermined."""
    try:
        ans = probe(repo)
    except Exception:  # a failing probe is a could-not-determine, never a guess
        return "undetermined"
    if not isinstance(ans, dict) or not isinstance(ans.get("private"), bool):
        return "undetermined"
    return "private" if ans["private"] else "public"


def allowed_target(owner_repo, target_repo, owner_vis, target_vis):
    """May an item owned by owner_repo be written to target_repo? Returns (ok, reason).
    Only the owning repository's own trackers (any host mirror of it: same owner/repo name) are allowed; both
    visibilities must be determined; a private item never reaches a public tracker."""
    if owner_vis == "undetermined" or target_vis == "undetermined" or owner_vis not in ("public", "private") or target_vis not in ("public", "private"):
        return False, "visibility-undetermined"
    if owner_repo is None or target_repo is None or tuple(owner_repo[1:]) != tuple(target_repo[1:]):
        return False, "not-owning-repo"
    if owner_vis == "private" and target_vis == "public":
        return False, "private-to-public"
    return True, "ok"


def owning_repo(atm_id, sub_projects, db_repo=None):
    """Prefix -> owning repo through the sub_projects map; ids with no mapped prefix belong to the repo whose DB holds them
    (routing is by DB location when the prefix is the repo's own, e.g. CON in the constitution DB). None = unroutable (blocked)."""
    prefix = atm_id.split("-", 1)[0].upper()
    if prefix in sub_projects:
        return sub_projects[prefix]
    return db_repo


def is_third_party(atm_id, third_party_prefixes):
    return atm_id.split("-", 1)[0].upper() in third_party_prefixes
