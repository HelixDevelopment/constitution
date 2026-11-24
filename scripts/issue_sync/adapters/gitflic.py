"""GitFlic issues adapter: NO verified issue endpoint (docs host refused the fetch; only releases and tags are known). Every verb raises
capability_unverified so the leg is UNCONFIRMED (anchor 11.4.300(G)); it exists so the engine reports the leg instead of omitting it."""
from .base import Adapter, AdapterError


class GitFlic(Adapter):
    provider = "gitflic"
    api_base = "https://api.gitflic.ru"
    capabilities = dict(Adapter.capabilities)

    def repo_info(self, owner, repo):
        raise AdapterError("capability_unverified:repo_info")

    def list_issues(self, owner, repo):
        raise AdapterError("capability_unverified:can_list")

    def create_issue(self, *a, **k):
        raise AdapterError("capability_unverified:can_create")

    update_issue = set_state = create_issue
