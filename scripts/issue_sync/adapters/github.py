"""GitHub REST v3 issues adapter. Docs: create POST /repos/{o}/{r}/issues; PATCH state open|closed, state_reason completed|not_planned|reopened."""
from .base import Adapter, AdapterError


class GitHub(Adapter):
    provider = "github"
    api_base = "https://api.github.com"
    default_headers = {"Accept": "application/vnd.github+json", "Content-Type": "application/json", "X-GitHub-Api-Version": "2022-11-28"}
    capabilities = {"can_list": True, "can_create": True, "can_update": True, "can_close": True, "can_reopen": True, "can_label": True, "not_planned": True}

    @staticmethod
    def norm(j):
        return {"number": j["number"], "url": j["html_url"], "title": j["title"], "body": j.get("body") or "",
                "state": j["state"], "labels": sorted(l["name"] if isinstance(l, dict) else l for l in j.get("labels", []))}

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
            js, _ = self._call("GET", "/repos/%s/%s/issues?state=all&per_page=100&page=%d" % (owner, repo, page))
            out += [self.norm(i) for i in js if "pull_request" not in i]
            if len(js) < 100:
                return out
            page += 1

    def create_issue(self, owner, repo, title, body, labels):
        js, _ = self._call("POST", "/repos/%s/%s/issues" % (owner, repo), {"title": title, "body": body, "labels": labels})
        return self.norm(js)

    def update_issue(self, owner, repo, number, title, body, labels):
        js, _ = self._call("PATCH", "/repos/%s/%s/issues/%d" % (owner, repo, number), {"title": title, "body": body, "labels": labels})
        return self.norm(js)

    def set_state(self, owner, repo, number, state, not_planned=False):
        b = {"state": state}
        b["state_reason"] = "reopened" if state == "open" else ("not_planned" if not_planned else "completed")
        js, _ = self._call("PATCH", "/repos/%s/%s/issues/%d" % (owner, repo, number), b)
        return self.norm(js)
