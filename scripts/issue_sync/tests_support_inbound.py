"""Test double for the inbound/pipeline tests (tool logic only, anchor 11.4.289: it proves THIS tool's logic, never any host's behaviour).
FakeGH2 is the FakeGitHub transport plus the two read shapes inbound needs: issue comments and assignees."""
import re

from .tests_support import FakeGitHub


class FakeGH2(FakeGitHub):
    def __init__(self, *a, **k):
        super().__init__(*a, **k)
        self.comment_calls = 0

    def add_human(self, title, body="", labels=(), assignees=(), comments=(), state="open"):
        self.n += 1
        self.issues.append({"number": self.n, "title": title, "body": body, "state": state, "labels": list(labels),
                            "assignees": list(assignees), "comments": list(comments)})
        return self.n

    def __call__(self, m, url, h, body):
        path = url.split("api.github.com")[1]
        mm = re.fullmatch(r"/repos/[^/]+/[^/]+/issues/(\d+)/comments\?per_page=100&page=(\d+)", path)
        if m == "GET" and mm:
            self.calls.append((m, url))
            self.comment_calls += 1
            i = next(x for x in self.issues if x["number"] == int(mm.group(1)))
            cs = [{"id": 1000 * i["number"] + k, "body": c, "user": {"login": "someone"}} for k, c in enumerate(i.get("comments", []))]
            return 200, {}, cs if mm.group(2) == "1" else []
        return super().__call__(m, url, h, body)

    @staticmethod
    def _j(i):
        d = FakeGitHub._j(i)
        d["comments"] = len(i.get("comments", []))
        d["assignees"] = [{"login": a} for a in i.get("assignees", [])]
        return d
