"""GitHub REST v3 issues adapter. Docs: create POST /repos/{o}/{r}/issues; PATCH state open|closed, state_reason completed|not_planned|reopened."""
from .base import Adapter, AdapterError


class GitHub(Adapter):
    provider = "github"
    api_base = "https://api.github.com"
    default_headers = {"Accept": "application/vnd.github+json", "Content-Type": "application/json", "X-GitHub-Api-Version": "2022-11-28"}
    # Reads are proven by the recorded read-only live probe; every write verb is UNCONFIRMED until a recorded live create + read-back
    # lists this host in config/forge/issue_sync_proven.tsv (then `proven=True` enables write_capabilities).
    capabilities = {"can_list": True, "can_create": False, "can_update": False, "can_close": False, "can_reopen": False, "can_label": False, "not_planned": False}
    write_capabilities = {"can_create": True, "can_update": True, "can_close": True, "can_reopen": True, "can_label": True, "not_planned": True}

    @staticmethod
    def norm(j):
        return {"number": j["number"], "url": j["html_url"], "title": j["title"], "body": j.get("body") or "",
                "state": j["state"], "labels": sorted(l["name"] if isinstance(l, dict) else l for l in j.get("labels", [])),
                "comments": j.get("comments", 0), "assignees": sorted(a.get("login", "") for a in (j.get("assignees") or []) if isinstance(a, dict))}

    def repo_info(self, owner, repo):
        st, _, js = self.t("GET", "%s/repos/%s/%s" % (self.api_base, owner, repo), self.default_headers, None)
        if st == 404:
            return {"exists": False, "private": None, "issues_enabled": None}
        if st != 200 or not isinstance(js, dict):
            raise AdapterError("unexpected_status_%s" % st, st)
        priv = None if js.get("visibility") == "internal" else js.get("private")   # internal = readable by every org member: not 'private'
        return {"exists": True, "private": priv, "issues_enabled": js.get("has_issues")}

    def list_issues(self, owner, repo):
        out, page = [], 1
        while True:
            js, _ = self._call("GET", "/repos/%s/%s/issues?state=all&per_page=100&page=%d" % (owner, repo, page))
            out += [self.norm(i) for i in js if "pull_request" not in i]
            if len(js) < 100:
                return out
            page += 1

    def list_comments(self, owner, repo, number):
        """READ-ONLY (inbound intake, C7): -> [{id, author, body}] of one issue's comments. Never writes."""
        out, page = [], 1
        while True:
            js, _ = self._call("GET", "/repos/%s/%s/issues/%d/comments?per_page=100&page=%d" % (owner, repo, number, page))
            out += [{"id": c["id"], "author": (c.get("user") or {}).get("login", ""), "body": c.get("body") or ""} for c in js]
            if len(js) < 100:
                return out
            page += 1

    def create_issue(self, owner, repo, title, body, labels):
        js, _ = self._call("POST", "/repos/%s/%s/issues" % (owner, repo), {"title": title, "body": body, "labels": labels})
        return self.norm(js)

    def update_issue(self, owner, repo, number, title, body, labels):
        # NOTE: `labels` REPLACES the issue's whole label set (mirror semantics: the DB is truth, a hand-added label is removed on the next sync).
        js, _ = self._call("PATCH", "/repos/%s/%s/issues/%d" % (owner, repo, number), {"title": title, "body": body, "labels": labels})
        return self.norm(js)

    def set_state(self, owner, repo, number, state, not_planned=False):
        b = {"state": state}
        b["state_reason"] = "reopened" if state == "open" else ("not_planned" if not_planned else "completed")
        js, _ = self._call("PATCH", "/repos/%s/%s/issues/%d" % (owner, repo, number), b)
        return self.norm(js)
