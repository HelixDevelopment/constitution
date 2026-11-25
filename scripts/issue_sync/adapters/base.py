"""Adapter contract (anchor 11.4.300(C),(G)). Normalised issue: {number, url, title, body, state: open|closed, labels: [str]}.
Capability flags are per host; a verb whose behaviour is unverified is False and the leg is reported UNCONFIRMED, never in sync."""
import json
import time
import email.utils
import socket
import urllib.error
import urllib.request

KEY_PREFIX = "["  # titles are '[ID] text'


class AdapterError(Exception):
    def __init__(self, code, status=None):
        super().__init__(code)
        self.code, self.status = code, status


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """The token must go only to the hosts.tsv origin: a redirect is refused, never followed (it would carry the auth header along)."""
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def retry_after_seconds(value, attempt):
    """Retry-After as delta-seconds or HTTP-date; anything else falls back to exponential backoff; clamped to 0..120."""
    try:
        sec = float(value)
    except (TypeError, ValueError):
        try:
            sec = (email.utils.parsedate_to_datetime(value).timestamp() - time.time())
        except (TypeError, ValueError):
            sec = 2 ** attempt
    return max(0.0, min(sec, 120.0))


def _pre_send(err):
    """True only when the failure provably happened before any request bytes left (so even a POST may be retried)."""
    r = getattr(err, "reason", err)
    return isinstance(r, (ConnectionRefusedError, socket.gaierror))


class HttpTransport:
    """Real transport. The token is placed in a header here only; never logged. Honors Retry-After on 429/403-secondary."""
    def __init__(self, token, min_interval=1.0, max_retries=4, sleep=time.sleep, timeout=30, auth_header=None):
        if auth_header is not None:      # a host whose API wants a different scheme (GitFlic: `token`); default stays Bearer
            self.auth_header = auth_header
        self._token, self.min_interval, self.max_retries, self._sleep, self.timeout = token, min_interval, max_retries, sleep, timeout
        self._last = 0.0
        self._opener = urllib.request.build_opener(_NoRedirect)

    def __call__(self, method, url, headers, body):
        if not url.startswith("https://"):
            raise AdapterError("non_https_refused")
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
                with self._opener.open(req, timeout=self.timeout) as r:
                    raw = r.read()
                    try:
                        return r.status, dict(r.headers), (json.loads(raw) if raw else None)
                    except ValueError:     # a 2xx whose body is not JSON: a write may have happened, so never treat it as success or retry it
                        raise AdapterError("malformed_body", r.status)
            except urllib.error.HTTPError as e:
                raw = e.read()
                if 300 <= e.code < 400:
                    raise AdapterError("redirect_refused", e.code)
                if e.code in (429, 403) and attempt < self.max_retries and (e.code == 429 or e.headers.get("Retry-After")):
                    self._sleep(retry_after_seconds(e.headers.get("Retry-After"), attempt))
                    continue
                try:
                    return e.code, dict(e.headers), (json.loads(raw) if raw else None)
                except ValueError:
                    return e.code, dict(e.headers), None
            except (urllib.error.URLError, OSError) as e:
                if method == "POST" and not _pre_send(e):
                    raise AdapterError("network_ambiguous_write")   # the issue may already exist: never blind-retry a create
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
    # unverified until proven by a live create + read-back; True only where documented AND proven. Read verbs may be proven by a read-only probe.
    capabilities = {"can_list": False, "can_create": False, "can_update": False, "can_close": False, "can_reopen": False,
                    "can_label": False, "not_planned": False}

    write_capabilities = {}   # declared, UNPROVEN write verbs: enabled only per host through `proven` (recorded live create + read-back)

    def __init__(self, transport, api_base=None, proven=False):
        self.t, self.api_base = transport, (api_base or self.api_base).rstrip("/")
        self.capabilities = dict(type(self).capabilities)
        if proven:
            self.capabilities.update(self.write_capabilities)

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
