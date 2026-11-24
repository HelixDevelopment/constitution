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


def make(host, transport_factory, hosts=None):
    """-> adapter or None (unknown host: nothing is guessed). transport_factory(token_vars, host) -> transport."""
    hosts = hosts or load_hosts()
    h = hosts.get(host)
    if not h:
        return None
    return CLASSES[h["provider"]](transport_factory(h["token_vars"], host), h["api_base"])
