"""Adapter contract (anchor 11.4.300(C),(G)). Normalised issue: {number, url, title, body, state: open|closed, labels: [str]}.
Capability flags are per host; a verb whose behaviour is unverified is False and the leg is reported UNCONFIRMED, never in sync."""
import json
import time
import urllib.error
import urllib.request

KEY_PREFIX = "["  # titles are '[ID] text'


class AdapterError(Exception):
    def __init__(self, code, status=None):
        super().__init__(code)
        self.code, self.status = code, status


class HttpTransport:
    """Real transport. The token is placed in a header here only; never logged. Honors Retry-After on 429/403-secondary."""
    def __init__(self, token, min_interval=1.0, max_retries=4, sleep=time.sleep, timeout=30):
        self._token, self.min_interval, self.max_retries, self._sleep, self.timeout = token, min_interval, max_retries, sleep, timeout
        self._last = 0.0

    def __call__(self, method, url, headers, body):
        data = None if body is None else json.dumps(body).encode()
        for attempt in range(self.max_retries + 1):
            wait = self.min_interval - (time.monotonic() - self._last)
            if wait > 0:
                self._sleep(wait)
            h = dict(headers)
            if self._token:
                h.update(self.auth_header(self._token))
            req = urllib.request.Request(url, data=data, method=method, headers=h)
            self._last = time.monotonic()
            try:
                with urllib.request.urlopen(req, timeout=self.timeout) as r:
                    raw = r.read()
                    return r.status, dict(r.headers), (json.loads(raw) if raw else None)
            except urllib.error.HTTPError as e:
                raw = e.read()
                if e.code in (429, 403) and attempt < self.max_retries and (e.code == 429 or e.headers.get("Retry-After")):
                    self._sleep(min(float(e.headers.get("Retry-After") or 2 ** attempt), 120))
                    continue
                try:
                    return e.code, dict(e.headers), (json.loads(raw) if raw else None)
                except ValueError:
                    return e.code, dict(e.headers), None
            except (urllib.error.URLError, OSError) as e:
                if attempt < self.max_retries:
                    self._sleep(2 ** attempt)
                    continue
                raise AdapterError("network_" + type(e).__name__)
        raise AdapterError("rate_limited", 429)

    auth_header = staticmethod(lambda t: {"Authorization": "Bearer " + t})


class Adapter:
    provider = "base"
    api_base = ""
    default_headers = {"Accept": "application/json", "Content-Type": "application/json"}
    # unverified until proven by a live create + read-back; True only where documented AND proven
    capabilities = {"can_list": False, "can_create": False, "can_update": False, "can_close": False, "can_reopen": False,
                    "can_label": False, "not_planned": False}

    def __init__(self, transport, api_base=None):
        self.t, self.api_base = transport, (api_base or self.api_base).rstrip("/")

    def _call(self, method, path, body=None, ok=(200, 201, 204)):
        st, hdr, js = self.t(method, self.api_base + path, self.default_headers, body)
        if st not in ok:
            raise AdapterError("unexpected_status_%s" % st, st)
        return js, hdr

    # --- to override ---
    def repo_info(self, owner, repo):
        """-> {'exists': bool, 'private': bool|None, 'issues_enabled': bool|None}. Read-only."""
        raise NotImplementedError

    def list_issues(self, owner, repo):
        raise NotImplementedError

    def create_issue(self, owner, repo, title, body, labels):
        raise NotImplementedError

    def update_issue(self, owner, repo, number, title, body, labels):
        raise NotImplementedError

    def set_state(self, owner, repo, number, state, not_planned=False):
        raise NotImplementedError

    def ensure_labels(self, owner, repo, labels):
        return None
