"""GitLab REST v4 issues adapter. Project addressed by URL-encoded path; issue identity is iid; close/reopen via state_event."""
import urllib.parse
from .base import Adapter, AdapterError


class GitLab(Adapter):
    provider = "gitlab"
    api_base = "https://gitlab.com/api/v4"
    # Reads proven by the read-only probe; writes UNCONFIRMED until proven (see GitHub adapter and issue_sync_proven.tsv).
    capabilities = {"can_list": True, "can_create": False, "can_update": False, "can_close": False, "can_reopen": False, "can_label": False, "not_planned": False}
    write_capabilities = {"can_create": True, "can_update": True, "can_close": True, "can_reopen": True, "can_label": True}
    auth_header = staticmethod(lambda t: {"PRIVATE-TOKEN": t})

    @staticmethod
    def _p(owner, repo):
        return urllib.parse.quote("%s/%s" % (owner, repo), safe="")

    @staticmethod
    def norm(j):
        return {"number": j["iid"], "url": j["web_url"], "title": j["title"], "body": j.get("description") or "",
                "state": "open" if j["state"] == "opened" else "closed", "labels": sorted(j.get("labels", []))}

    def repo_info(self, owner, repo):
        st, _, js = self.t("GET", "%s/projects/%s" % (self.api_base, self._p(owner, repo)), self.default_headers, None)
        if st == 404:
            return {"exists": False, "private": None, "issues_enabled": None}
        if st != 200 or not isinstance(js, dict):
            raise AdapterError("unexpected_status_%s" % st, st)
        vis = js.get("visibility")   # 'internal' (any signed-in user) and unknown values are undetermined, never private
        return {"exists": True, "private": {"private": True, "public": False}.get(vis), "issues_enabled": js.get("issues_access_level") not in (None, "disabled") if "issues_access_level" in js else None}

    def list_issues(self, owner, repo):
        out, page = [], 1
        while True:
            js, _ = self._call("GET", "/projects/%s/issues?state=all&per_page=100&page=%d" % (self._p(owner, repo), page))
            out += [self.norm(i) for i in js]
            if len(js) < 100:
                return out
            page += 1

    def create_issue(self, owner, repo, title, body, labels):
        js, _ = self._call("POST", "/projects/%s/issues" % self._p(owner, repo), {"title": title, "description": body, "labels": ",".join(labels)})
        return self.norm(js)

    def update_issue(self, owner, repo, number, title, body, labels):
        # NOTE: `labels` REPLACES the issue's whole label set (mirror semantics: the DB is truth).
        js, _ = self._call("PUT", "/projects/%s/issues/%d" % (self._p(owner, repo), number), {"title": title, "description": body, "labels": ",".join(labels)})
        return self.norm(js)

    def set_state(self, owner, repo, number, state, not_planned=False):
        js, _ = self._call("PUT", "/projects/%s/issues/%d" % (self._p(owner, repo), number), {"state_event": "reopen" if state == "open" else "close"})
        return self.norm(js)
