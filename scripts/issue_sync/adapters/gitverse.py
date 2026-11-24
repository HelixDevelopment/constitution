"""GitVerse issues adapter. Docs list GET/POST /repos/{o}/{r}/issues and PATCH .../issues/{n}; no `state` field is documented, so closing is UNKNOWN
and every write capability stays False until a live create + read-back proves it. Requires header Accept: application/vnd.gitverse.object+json;version=1."""
from .gitea import Gitea


class GitVerse(Gitea):
    provider = "gitverse"
    api_base = "https://api.gitverse.ru"
    default_headers = {"Accept": "application/vnd.gitverse.object+json;version=1", "Content-Type": "application/json"}

    def __init__(self, transport, api_base=None, proven=False):
        super().__init__(transport, api_base, proven=False)
        self.capabilities = dict(self.capabilities, can_close=False, can_reopen=False)
        if proven:
            self.capabilities.update(can_create=True, can_update=True)
