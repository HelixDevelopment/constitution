"""Config loader and validator for .workable-items-sync.yaml (anchor 11.4.300(A)). Fail-closed: any problem is an error string;
a missing file means the mechanism is OFF (default-OFF), never an error."""
import re
import yaml

DEFAULTS = {
    "enabled": False, "scope": {"recursive": False}, "mode": "dry-run", "trackers": [], "visibility_policy": "owning-repo",
    "interval_hours": 24, "inbound": {"enabled": False, "assignees": []}, "docs_chain": {"context": "issues-sync"}, "token_vars": {},
}
_NAME = re.compile(r"^[A-Z][A-Z0-9_]{0,63}$")
_KEYS = set(DEFAULTS) | {"apply_decision"}


def _merge(base, over):
    out = {}
    for k, v in base.items():
        out[k] = dict(v) if isinstance(v, dict) else (list(v) if isinstance(v, list) else v)
    for k, v in over.items():
        if isinstance(out.get(k), dict) and isinstance(v, dict) and k != "token_vars":
            out[k] = {**out[k], **v}
        else:
            out[k] = v
    return out


def validate(raw):
    errs = []
    if not isinstance(raw, dict):
        return ["top level must be a mapping"]
    for k in raw:
        if k not in _KEYS:
            errs.append("unknown key: %s" % k)
    cfg = _merge(DEFAULTS, {k: v for k, v in raw.items() if k in _KEYS})
    if not isinstance(cfg["enabled"], bool):
        errs.append("enabled must be a boolean")
    if not isinstance(cfg["scope"], dict) or set(cfg["scope"]) - {"recursive"} or not isinstance(cfg["scope"].get("recursive"), bool):
        errs.append("scope must be {recursive: bool}")
    if cfg["mode"] not in ("dry-run", "apply"):
        errs.append("mode must be dry-run or apply")
    if cfg["mode"] == "apply" and cfg["enabled"] is True:
        ad = cfg.get("apply_decision")
        if not isinstance(ad, str) or not ad.strip():
            errs.append("mode apply requires apply_decision (path of the tracked recorded operator decision)")
    if not (isinstance(cfg["trackers"], list) and all(isinstance(t, str) and t for t in cfg["trackers"])):
        errs.append("trackers must be a list of non-empty strings")
    if cfg["visibility_policy"] != "owning-repo":
        errs.append("visibility_policy must be owning-repo")
    ih = cfg["interval_hours"]
    if isinstance(ih, bool) or not isinstance(ih, int) or not 1 <= ih <= 24:
        errs.append("interval_hours must be an integer 1..24")
    inb = cfg["inbound"]
    if not isinstance(inb, dict) or set(inb) - {"enabled", "assignees"} or not isinstance(inb.get("enabled"), bool) \
            or not isinstance(inb.get("assignees"), list) or not all(isinstance(a, str) for a in inb.get("assignees", [])):
        errs.append("inbound must be {enabled: bool, assignees: [str]}")
    dc = cfg["docs_chain"]
    if not isinstance(dc, dict) or set(dc) - {"context"} or not isinstance(dc.get("context"), str) or not dc.get("context"):
        errs.append("docs_chain must be {context: str}")
    tv = cfg["token_vars"]
    if not isinstance(tv, dict):
        errs.append("token_vars must be a mapping host -> [NAMES]")
    else:
        for host, names in tv.items():
            if not isinstance(names, list) or not names:
                errs.append("token_vars[%s] must be a non-empty list of variable NAMES" % host)
                continue
            for n in names:
                if not isinstance(n, str) or not _NAME.match(n) or n.startswith(("GHP_", "GLPAT")):
                    errs.append("token_vars[%s] holds a value that is not a variable NAME (names only, never values)" % host)
    return cfg, errs


def load(path):
    """Return (config, errors). A missing file is the default-OFF config with no errors."""
    try:
        with open(path) as f:
            raw = yaml.safe_load(f)
    except FileNotFoundError:
        return _merge(DEFAULTS, {}), []
    except (OSError, yaml.YAMLError) as e:
        return _merge(DEFAULTS, {}), ["cannot read config: %s" % type(e).__name__]
    if raw is None:
        raw = {}
    res = validate(raw)
    if isinstance(res, list):
        return _merge(DEFAULTS, {}), res
    return res
