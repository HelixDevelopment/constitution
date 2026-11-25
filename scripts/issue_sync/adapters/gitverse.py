"""GitVerse issues adapter. Docs list GET/POST /repos/{o}/{r}/issues and PATCH .../issues/{n}; no `state` field is documented, so closing is UNKNOWN
and every write capability stays False until a live create + read-back proves it. Requires header Accept: application/vnd.gitverse.object+json;version=1."""
from .base import AdapterError
from .gitea import Gitea


class GitVerse(Gitea):
    provider = "gitverse"
    api_base = "https://api.gitverse.ru"
    default_headers = {"Accept": "application/vnd.gitverse.object+json;version=1", "Content-Type": "application/json"}

    def __init__(self, transport, api_base=None, proven=False):
        super().__init__(transport, api_base, proven=False)   # the Gitea base is never told `proven`: GitVerse closing is undocumented
        self.capabilities = dict(self.capabilities, can_close=False, can_reopen=False)
        if proven:
            self.capabilities.update(can_create=True, can_update=True)

    def list_issues(self, owner, repo):
        """GitVerse rejects the Gitea query (`limit` is a VALIDATION_ERROR 400, `type=issues` answers 403); it takes `per_page` and `page`, and the list
        holds issues and pull requests together, so entries carrying `pull_request` are dropped."""
        out, page = [], 1
        while True:
            js, _ = self._call("GET", "/repos/%s/%s/issues?state=all&per_page=50&page=%d" % (owner, repo, page))
            if not isinstance(js, list):
                raise AdapterError("malformed_body")
            out += [self.norm(i) for i in js if "pull_request" not in i]
            if len(js) < 50:
                return out
            page += 1
