"""Host map -> adapter (reads config/forge/hosts.tsv, the DATA that decides which origin receives which token variable)."""
import os
from .adapters.github import GitHub
from .adapters.gitlab import GitLab
from .adapters.gitea import Gitea
from .adapters.gitverse import GitVerse
from .adapters.gitflic import GitFlic

CLASSES = {"github": GitHub, "gitlab": GitLab, "gitea": Gitea, "gitverse": GitVerse, "gitflic": GitFlic}
HOSTS_TSV = os.path.join(os.path.dirname(__file__), "..", "..", "config", "forge", "hosts.tsv")


def load_hosts(path=HOSTS_TSV):
    hosts = {}
    with open(path) as f:
        for line in f:
            if line.startswith("#") or not line.strip():
                continue
            c = line.rstrip("\n").split("\t")
            if len(c) >= 4 and c[1] in CLASSES and c[2].startswith("https://"):
                hosts[c[0]] = {"provider": c[1], "api_base": c[2], "token_vars": [n for n in c[3].split(",") if n]}
    return hosts


PROVEN_TSV = os.path.join(os.path.dirname(__file__), "..", "..", "config", "forge", "issue_sync_proven.tsv")


EVIDENCE_MARKER = "LIVE-CREATE-READBACK-RECORDED"


def _has_readback(path):
    """The evidence file must say, in a line of its own, that a live create AND a read-back were recorded for the host (a read-only probe does not)."""
    try:
        with open(path, errors="replace") as f:
            return any(line.strip().startswith(EVIDENCE_MARKER) for line in f)
    except OSError:
        return False


def load_proven(path=PROVEN_TSV, root=None):
    """Hosts whose WRITE verbs are proven: rows `host<TAB>evidence-path` where the evidence file (a recorded live create + read-back) EXISTS
    under the constitution root. A missing file, a row without evidence, or an evidence path that does not exist proves nothing."""
    root = root or os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    proven = set()
    try:
        with open(path) as f:
            for line in f:
                if line.startswith("#") or not line.strip():
                    continue
                c = line.rstrip("\n").split("\t")
                ev = os.path.realpath(os.path.join(root, c[1])) if len(c) >= 2 and c[1] else None
                if ev and ev.startswith(os.path.realpath(root) + os.sep) and os.path.isfile(ev) and c[0] in load_hosts() and _has_readback(ev):
                    proven.add(c[0])
    except OSError:
        pass
    return proven


def make(host, transport_factory, hosts=None, proven=()):
    """-> adapter or None (unknown host: nothing is guessed). transport_factory(token_vars, host) -> transport.
    Write verbs are enabled only for hosts in `proven`."""
    hosts = hosts or load_hosts()
    h = hosts.get(host)
    if not h:
        return None
    return CLASSES[h["provider"]](transport_factory(h["token_vars"], host), h["api_base"], proven=host in proven)
