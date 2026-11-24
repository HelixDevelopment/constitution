"""Config loader and validator for .workable-items-sync.yaml (anchor 11.4.300(A)). Fail-closed: any problem is an error string;
a missing file means the mechanism is OFF (default-OFF), never an error."""
import re
import yaml
from . import redact


class _StrictLoader(yaml.SafeLoader):
    """SafeLoader that (1) refuses a duplicate mapping key (plain safe_load lets the last one win silently) and (2) reads only true/false as
    booleans: YAML 1.1 yes/no/on/off/y/n stay STRINGS, so `enabled: yes` is a validation error, never a silent ON."""


_StrictLoader.yaml_implicit_resolvers = {k: [(t, r) for t, r in v if t != "tag:yaml.org,2002:bool"] for k, v in yaml.SafeLoader.yaml_implicit_resolvers.items()}
_StrictLoader.add_implicit_resolver("tag:yaml.org,2002:bool", re.compile(r"^(?:true|True|TRUE|false|False|FALSE)$"), list("tTfF"))


def _no_dup_mapping(loader, node, deep=False):
    loader.flatten_mapping(node)
    seen = set()
    for knode, _ in node.value:
        key = loader.construct_object(knode, deep=True)
        try:
            dup = key in seen
            seen.add(key)
        except TypeError:
            raise yaml.constructor.ConstructorError(None, None, "unhashable mapping key", knode.start_mark)
        if dup:
            raise yaml.constructor.ConstructorError(None, None, "duplicate key", knode.start_mark)
    return yaml.SafeLoader.construct_mapping(loader, node, deep)


_StrictLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _no_dup_mapping)

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
    if "apply_decision" in cfg or (cfg["mode"] == "apply" and cfg["enabled"] is True):
        ad = cfg.get("apply_decision")      # type-checked in EVERY mode, not only when apply is on
        if not isinstance(ad, str) or not ad.strip():
            errs.append("apply_decision must be a non-empty string (relative path of the tracked recorded operator decision)" if "apply_decision" in cfg
                        else "mode apply requires apply_decision (path of the tracked recorded operator decision)")
        elif ad.startswith(("/", "\\")) or re.match(r"^[A-Za-z]:", ad) or "\x00" in ad or ".." in re.split(r"[\\/]+", ad):
            errs.append("apply_decision must be a relative path inside the repository (no absolute path, no '..')")
    if not (isinstance(cfg["trackers"], list) and all(isinstance(t, str) and t for t in cfg["trackers"])):
        errs.append("trackers must be a list of non-empty strings")
    elif any(not re.match(r"^[A-Za-z0-9][A-Za-z0-9.-]*$", t) or redact.scan({"v": t}) for t in cfg["trackers"]):
        errs.append("trackers must be bare host names (no URL, no credentials)")
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
                if not isinstance(n, str) or not _NAME.match(n) or redact.scan({"v": n}) or re.match(r"^(AKIA|AIZA|SG_|XOX)", n):
                    errs.append("token_vars[%s] holds a value that is not a variable NAME (names only, never values)" % host)
    if errs:
        return _merge(DEFAULTS, {}), errs   # fail closed: an invalid declaration is never an enabled one
    return cfg, errs


def load(path):
    """Return (config, errors). A missing file is the default-OFF config with no errors."""
    try:
        with open(path) as f:
            raw = yaml.load(f, Loader=_StrictLoader)
    except FileNotFoundError:
        return _merge(DEFAULTS, {}), []
    except yaml.constructor.ConstructorError as e:
        return _merge(DEFAULTS, {}), ["cannot read config: %s" % (e.problem or "invalid YAML")]
    except (OSError, yaml.YAMLError) as e:
        return _merge(DEFAULTS, {}), ["cannot read config: %s" % type(e).__name__]
    if raw is None:
        raw = {}
    res = validate(raw)
    if isinstance(res, list):
        return _merge(DEFAULTS, {}), res
    return res
