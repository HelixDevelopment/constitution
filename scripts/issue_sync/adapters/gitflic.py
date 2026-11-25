"""GitFlic issues adapter (anchor 11.4.300(C),(G)). Endpoints are from the GitFlic REST docs (docs.gitflic.ru/latest/api/issue/):
GET /project/{o}/{p}/issue (HAL page: page/size params, `_embedded.issueModelList`), POST .../issue, PUT .../issue/{localId}/edit.
There is NO separate close verb: closing is the same PUT /edit with `status.id` CLOSED (cancelled) or COMPLETED, reopening is OPEN.
Auth is `Authorization: token <t>` (a Bearer header answers 403). Create and edit need `assignedUsers: []` in the body (422 without it).
Labels are addressed by id on this host, so label writes are NOT used (can_label stays False). Every write verb stays UNCONFIRMED until a
recorded live create + read-back lists the host in config/forge/issue_sync_proven.tsv; `proven=True` is passed only by a caller holding it."""
from .base import Adapter, AdapterError

_OPEN = ("OPEN", "IN_PROGRESS")


class GitFlic(Adapter):
    provider = "gitflic"
    api_base = "https://api.gitflic.ru"
    default_headers = {"Accept": "application/json", "Content-Type": "application/json"}
    transport_auth = staticmethod(lambda t: {"Authorization": "token " + t})
    capabilities = dict(Adapter.capabilities, can_list=True)       # list proven by a read-only probe; writes only through `proven`
    write_capabilities = {"can_create": True, "can_update": True, "can_close": True, "can_reopen": True, "not_planned": True}

    @staticmethod
    def norm(j, owner, repo):
        sid = (j.get("status") or {}).get("id")
        return {"number": int(j["localId"]), "url": "https://gitflic.ru/project/%s/%s/issue/%s" % (owner, repo, j["localId"]),
                "title": j["title"], "body": j.get("description") or "", "state": "open" if sid in _OPEN else "closed",
                "labels": sorted((l.get("title") or "") for l in j.get("labels") or [])}

    def repo_info(self, owner, repo):
        st, _, js = self.t("GET", "%s/project/%s/%s" % (self.api_base, owner, repo), self.default_headers, None)
        if st == 404:
            return {"exists": False, "private": None, "issues_enabled": None}
        if st != 200 or not isinstance(js, dict) or not isinstance(js.get("private"), bool):
            raise AdapterError("unexpected_status_%s" % st, st)
        return {"exists": True, "private": js["private"], "issues_enabled": None}   # no issues-enabled flag is exposed: unknown, not False

    def list_issues(self, owner, repo):
        out, page = [], 0
        while True:
            js, _ = self._call("GET", "/project/%s/%s/issue?page=%d&size=100" % (owner, repo, page))
            if not isinstance(js, dict):
                raise AdapterError("malformed_body")
            out += [self.norm(i, owner, repo) for i in (js.get("_embedded") or {}).get("issueModelList", [])]
            pg = js.get("page") or {}
            if page + 1 >= int(pg.get("totalPages") or 0):
                return out
            page += 1

    def _need(self, cap):
        if not self.capabilities[cap]:
            raise AdapterError("capability_unverified:" + cap)

    def create_issue(self, owner, repo, title, body, labels):
        self._need("can_create")
        js, _ = self._call("POST", "/project/%s/%s/issue" % (owner, repo),
                           {"title": title, "description": body, "assignedUsers": [], "status": {"id": "OPEN"}})
        return self.norm(js, owner, repo)

    def _edit(self, owner, repo, number, title, body, status):
        js, _ = self._call("PUT", "/project/%s/%s/issue/%d/edit" % (owner, repo, number),
                           {"title": title, "description": body, "assignedUsers": [], "status": {"id": status}})
        return self.norm(js, owner, repo)

    def _current(self, owner, repo, number):
        js, _ = self._call("GET", "/project/%s/%s/issue/%d" % (owner, repo, number))
        if not isinstance(js, dict) or "localId" not in js:
            raise AdapterError("malformed_body")
        return js

    def update_issue(self, owner, repo, number, title, body, labels):
        self._need("can_update")
        cur = self._current(owner, repo, number)          # an edit must carry a status: keep the issue's own
        return self._edit(owner, repo, number, title, body, (cur.get("status") or {}).get("id") or "OPEN")

    def set_state(self, owner, repo, number, state, not_planned=False):
        self._need("can_close" if state == "closed" else "can_reopen")
        cur = self._current(owner, repo, number)          # the PUT replaces title and description: re-send the current ones
        status = "OPEN" if state == "open" else ("CLOSED" if not_planned else "COMPLETED")
        return self._edit(owner, repo, number, cur["title"], cur.get("description") or "", status)
