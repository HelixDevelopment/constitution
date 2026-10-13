"""Registry of composable, individually fail-closed CodeGraph runner patches.

Adding a patch = add one module exposing PATCH_ID / SUMMARY / plan(view) (see
common.py) and append its module name to REGISTRY. Order matters: patches are
planned and applied in REGISTRY order on a shared FileView, so a later patch
sees earlier edits. The runner key is "<version>-" + "-".join(applied ids)
(ids of patches reporting NOT_NEEDED are omitted).

OPT_IN patches are registered (selectable with `--patches id`) but are NEVER part of
the default set: the default runner is the bulk WRITER runner, and a read-only patch
must not be able to end up in it by omission. EXCLUSIVE patches define a runner of a
different KIND (mcpro1 = read-only MCP server) and may not be composed with any other
patch: the runner key "<ver>-mcpro1" therefore identifies the read-only runner exactly.
"""
import importlib

REGISTRY = ["fkidx1", "lockfix1", "datafrag1", "resolve1", "resolve2", "mcpro1"]
OPT_IN = frozenset(["mcpro1"])
EXCLUSIVE = frozenset(["mcpro1"])


def load(ids=None):
    from .common import Refuse
    if ids is None:
        wanted = [i for i in REGISTRY if i not in OPT_IN]
    else:
        unknown = sorted(set(ids) - set(REGISTRY))
        if unknown:
            raise Refuse(f"unknown patch id(s): {', '.join(unknown)} (known: {', '.join(REGISTRY)})")
        wanted = [i for i in REGISTRY if i in set(ids)]
        for ex in sorted(EXCLUSIVE & set(wanted)):
            if len(wanted) > 1:
                raise Refuse(f"patch '{ex}' is exclusive (it defines a different runner kind) and cannot be combined with: "
                             f"{', '.join(i for i in wanted if i != ex)}")
    return [importlib.import_module(f"{__name__}.{i}") for i in wanted]
