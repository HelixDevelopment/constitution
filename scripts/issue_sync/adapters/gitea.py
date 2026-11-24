"""Gitea / Forgejo (m3w, Codeberg) issues adapter. Create and edit are documented; the `state` field on edit and `has_issues` are standard Gitea
but NOT proven here, so every write capability stays False (leg UNCONFIRMED) until a live create + read-back proves it (anchor 11.4.300(G));
`proven=True` is passed only by a caller holding that live evidence."""
from .base import Adapter, AdapterError


class Gitea(Adapter):
    provider = "gitea"
    api_base = "https://codeberg.org/api/v1"
    auth_header = staticmethod(lambda t: {"Authorization": "token " + t})

    def __init__(self, transport, api_base=None, proven=False):
        super().__init__(transport, api_base)
        self.capabilities = dict(Adapter.capabilities, can_list=True)
        if proven:
            self.capabilities.update(can_create=True, can_update=True, can_close=True, can_reopen=True, can_label=True)

    @staticmethod
    def norm(j):
        return {"number": j["number"], "url": j["html_url"], "title": j["title"], "body": j.get("body") or "", "state": j["state"],
                "labels": sorted(l["name"] for l in j.get("labels", []))}

    def repo_info(self, owner, repo):
        st, _, js = self.t("GET", "%s/repos/%s/%s" % (self.api_base, owner, repo), self.default_headers, None)
        if st == 404:
            return {"exists": False, "private": None, "issues_enabled": None}
        if st != 200 or not isinstance(js, dict):
            raise AdapterError("unexpected_status_%s" % st, st)
        return {"exists": True, "private": js.get("private"), "issues_enabled": js.get("has_issues")}

    def list_issues(self, owner, repo):
        out, page = [], 1
        while True:
            js, _ = self._call("GET", "/repos/%s/%s/issues?state=all&type=issues&limit=50&page=%d" % (owner, repo, page))
            out += [self.norm(i) for i in js]
            if len(js) < 50:
                return out
            page += 1

    def _need(self, cap):
        if not self.capabilities[cap]:
            raise AdapterError("capability_unverified:" + cap)

    def create_issue(self, owner, repo, title, body, labels):
        self._need("can_create")
        js, _ = self._call("POST", "/repos/%s/%s/issues" % (owner, repo), {"title": title, "body": body})
        return self.norm(js)

    def update_issue(self, owner, repo, number, title, body, labels):
        self._need("can_update")
        js, _ = self._call("PATCH", "/repos/%s/%s/issues/%d" % (owner, repo, number), {"title": title, "body": body})
        return self.norm(js)

    def set_state(self, owner, repo, number, state, not_planned=False):
        self._need("can_close")
        js, _ = self._call("PATCH", "/repos/%s/%s/issues/%d" % (owner, repo, number), {"state": state})
        return self.norm(js)
