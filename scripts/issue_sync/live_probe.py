#!/usr/bin/env python3
"""Read-only live probe of repo existence, visibility and Issues-enabled per host (evidence for anchor 11.4.300(G); never writes).
Usage: python3 -m issue_sync.live_probe HOST/OWNER/REPO [...]   Output: one line per target; tokens read by NAME, never printed.
Exit: 0 every target probed, 2 a target could not be determined."""
import sys
from . import credentials, registry
from .adapters.base import AdapterError, HttpTransport


def probe(spec):
    host, owner, repo = spec.split("/", 2)
    hosts = registry.load_hosts()
    if host not in hosts:
        return "%s UNKNOWN host_not_in_hosts_tsv" % spec
    st, name, tok = credentials.resolve(hosts[host]["token_vars"])
    tr = HttpTransport(tok if st == "found" else None, min_interval=0.5, auth_header=registry.transport_auth(host))
    ad = registry.CLASSES[hosts[host]["provider"]](tr, hosts[host]["api_base"], proven=host in registry.load_proven())
    try:
        info = ad.repo_info(owner, repo)
    except AdapterError as e:
        return "%s UNDETERMINED %s (auth=%s)" % (spec, e.code, st)
    return "%s exists=%s private=%s issues_enabled=%s auth=%s caps=%s writes=%s" % (spec, info["exists"], info["private"], info["issues_enabled"], st if st != "found" else "token:" + name, ",".join(k for k, v in ad.capabilities.items() if v) or "none-verified", "PROVEN" if ad.capabilities.get("can_create") else "UNCONFIRMED")


def main(argv):
    rc = 0
    for s in argv:
        line = probe(s)
        print(line)
        if "UNDETERMINED" in line or "UNKNOWN" in line:
            rc = 2
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
