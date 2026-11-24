"""Test doubles shared by the unit tests and prove_failure (tool-logic only, anchor 11.4.289)."""
import os, re, sqlite3, tempfile

class FakeGitHub:
    """Stateful transport emulating the GitHub REST subset the adapter uses."""
    def __init__(self, private=False, fail_after=None):
        self.issues, self.n, self.calls, self.private, self.fail_after, self.writes = [], 0, [], private, fail_after, 0
    def __call__(self, m, url, h, body):
        self.calls.append((m, url))
        path = url.split("api.github.com")[1]
        if m == "GET" and re.fullmatch(r"/repos/[^/]+/[^/]+", path):
            return 200, {}, {"private": self.private, "has_issues": True}
        if m == "GET" and "/issues" in path:
            return 200, {}, [self._j(i) for i in self.issues] if "page=1" in path else []
        self.writes += 1
        if self.fail_after is not None and self.writes > self.fail_after:
            return 502, {}, None
        if m == "POST":
            self.n += 1
            i = {"number": self.n, "title": body["title"], "body": body["body"], "state": "open", "labels": body["labels"]}
            self.issues.append(i); return 201, {}, self._j(i)
        if m == "PATCH":
            i = next(x for x in self.issues if x["number"] == int(path.rsplit("/", 1)[1]))
            for k in ("title", "body", "labels"):
                if k in body: i[k] = body[k]
            if "state" in body: i["state"] = body["state"]
            return 200, {}, self._j(i)
        return 404, {}, None
    @staticmethod
    def _j(i): return {"number": i["number"], "html_url": "https://github.com/o/r/issues/%d" % i["number"], "title": i["title"], "body": i["body"], "state": i["state"], "labels": [{"name": l} for l in i["labels"]]}

def mkdb(rows, subs=()):
    d = tempfile.mkdtemp(); p = os.path.join(d, "w.db"); c = sqlite3.connect(p)
    c.execute("CREATE TABLE items (atm_id,type,status,title,severity,description,forensic_anchor,body_md,current_location)")
    c.execute("CREATE TABLE sub_projects (prefix,path,class,ratified,url,note,synced_at)")
    for r in rows: c.execute("INSERT INTO items VALUES (?,?,?,?,?,?,?,?,?)", r)
    for s in subs: c.execute("INSERT INTO sub_projects VALUES (?,?,?,?,?,?,?)", s)
    c.commit(); c.close(); return p

def cfgfile(text="enabled: true\nmode: dry-run\n"):
    p = os.path.join(tempfile.mkdtemp(), "c.yaml"); open(p, "w").write(text); return p

