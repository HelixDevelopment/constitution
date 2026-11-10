"""Tracing differential for the review_record EQUIVALENT sub-clause claims
(CON-033 round 4, review R3-F1/R3-F2 follow-up: "refute by differential").

The differential harness (r4_equivalence_differential.sh) builds a snapshot
of review/ + tests/ and replaces the tool's `if __name__ == "__main__":`
block with a call to install() below. Every suite then runs the ORIGINAL
tool, unchanged in behaviour, while this module compares it with every
mutant on the inputs the suites really produce:

  * function level: each call of a guarded function (one that holds an
    EQUIVALENT claim or its positive control) is replayed on each mutant's
    copy of that function with a deep copy of the same arguments, and the
    two results (return value, or exception type) are compared;
  * CLI level: each invocation of main(argv) is replayed, before the
    original runs, in a forked child on each mutant's main(argv); the
    child's exit status, stdout, stderr and the body it would have written
    (its _write_record is replaced by a capture) are compared with the
    original's.

Nothing the original prints, writes or returns is changed; the harness
checks that by running the suites on an untraced control snapshot and
comparing statuses. Results go to $RR_EQ_LOG/<pid>.json, one file per
process, as counts per (id, level) plus the first three differing inputs.

Environment: RR_EQ_DIR (mutant .py files, <ID with # -> _>.py), RR_EQ_IDS
(file: id<TAB>function per line), RR_EQ_LOG (output directory).
"""
import copy
import importlib.util
import io
import json
import os
import sys

_STATE = {"fn": {}, "cli": {}}


def _canon(v, depth=0):
    """A deterministic JSON-able image of a value (sets sorted, bytes hashed
    by content, objects by type name) so two results compare by content."""
    if depth > 40:
        return "<deep>"
    if isinstance(v, dict):
        return {"d": sorted(([_canon(k, depth + 1), _canon(x, depth + 1)] for k, x in v.items()),
                            key=lambda p: json.dumps(p, sort_keys=True))}
    if isinstance(v, (list, tuple)):
        return {type(v).__name__: [_canon(x, depth + 1) for x in v]}
    if isinstance(v, (set, frozenset)):
        return {"set": sorted((_canon(x, depth + 1) for x in v), key=lambda p: json.dumps(p, sort_keys=True))}
    if isinstance(v, bytes):
        import hashlib
        return {"bytes": hashlib.sha256(v).hexdigest(), "len": len(v)}
    if v is None or isinstance(v, (bool, int, float, str)):
        return [type(v).__name__, v]
    return {"obj": type(v).__name__}


def _outcome(fn, args, kwargs):
    try:
        return ["ret", _canon(fn(*args, **kwargs))]
    except Exception as exc:  # noqa: BLE001 - the exception TYPE is the observable
        return ["exc", type(exc).__name__]


def _short(x, n=300):
    s = json.dumps(x, sort_keys=True, default=repr)
    return s if len(s) <= n else s[:n] + "..."


def _note(kind, id_, differ, sample):
    slot = _STATE[kind].setdefault(id_, {"calls": 0, "differ": 0, "first": []})
    slot["calls"] += 1
    if differ:
        slot["differ"] += 1
        if len(slot["first"]) < 3:
            slot["first"].append(sample)


def _load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def _flush():
    out = os.environ.get("RR_EQ_LOG")
    if not out:
        return
    with open(os.path.join(out, "%d.json" % os.getpid()), "w", encoding="utf-8") as fh:
        json.dump(_STATE, fh, sort_keys=True)


def install(g):
    """Wrap the guarded functions of the ORIGINAL module namespace `g` and
    return the traced main."""
    eqdir, idfile = os.environ["RR_EQ_DIR"], os.environ["RR_EQ_IDS"]
    by_fn, mutants = {}, {}
    for line in open(idfile, encoding="utf-8"):
        id_, fn = line.rstrip("\n").split("\t")
        by_fn.setdefault(fn, []).append(id_)
        mutants[id_] = _load(os.path.join(eqdir, id_.replace("#", "_") + ".py"),
                             "rr_mut_" + id_.replace("#", "_").replace("-", "_"))
    import atexit
    atexit.register(_flush)

    def wrap(fname, orig_fn):
        ids = by_fn[fname]

        def traced(*args, **kwargs):
            outs = {}
            for id_ in ids:
                outs[id_] = _outcome(getattr(mutants[id_], fname), copy.deepcopy(args), copy.deepcopy(kwargs))
            res, exc = None, None
            try:
                res = orig_fn(*args, **kwargs)
                o = ["ret", _canon(res)]
            except Exception as e:  # noqa: BLE001
                exc, o = e, ["exc", type(e).__name__]
            for id_ in ids:
                d = outs[id_] != o
                _note("fn", id_, d, {"args": _short(_canon(list(args))), "orig": _short(o), "mut": _short(outs[id_])}
                      if d else None)
            if exc is not None:
                raise exc
            return res
        return traced

    for fname in by_fn:
        if fname not in ("cmd_record",) and fname in g:
            g[fname] = wrap(fname, g[fname])

    real_main = g["main"]
    real_write = g["_write_record"]
    all_ids = [i for ids in by_fn.values() for i in ids]

    def run_child(mod, argv):
        r, w = os.pipe()
        pid = os.fork()
        if pid == 0:
            os.close(r)
            out, err, bodies = io.StringIO(), io.StringIO(), []
            sys.stdout, sys.stderr = out, err

            def cap(body, out_path):
                bodies.append([_canon(body), out_path])
                return 0
            mod._write_record = cap
            try:
                rc = mod.main(list(argv))
            except SystemExit as se:
                rc = se.code
            except BaseException as e:  # noqa: BLE001
                rc = "raised:" + type(e).__name__
            payload = json.dumps([rc, out.getvalue(), err.getvalue(), bodies], default=repr).encode()
            with os.fdopen(w, "wb") as fh:
                fh.write(payload)
            os._exit(0)
        os.close(w)
        with os.fdopen(r, "rb") as fh:
            data = fh.read()
        os.waitpid(pid, 0)
        return json.loads(data.decode())

    class Tee(io.TextIOBase):
        def __init__(self, real):
            self.real, self.buf = real, io.StringIO()

        def write(self, s):
            self.buf.write(s)
            return self.real.write(s)

        def flush(self):
            self.real.flush()

    def traced_main(argv):
        child = {id_: run_child(mutants[id_], argv) for id_ in all_ids}
        bodies = []

        def cap_write(body, out_path):
            bodies.append([_canon(copy.deepcopy(body)), out_path])
            return real_write(body, out_path)
        g["_write_record"] = cap_write
        so, se = sys.stdout, sys.stderr
        sys.stdout, sys.stderr = Tee(so), Tee(se)
        try:
            rc = real_main(argv)
        finally:
            to, te = sys.stdout, sys.stderr
            sys.stdout, sys.stderr = so, se
        orig = json.loads(json.dumps([rc, to.buf.getvalue(), te.buf.getvalue(), bodies], default=repr))
        for id_ in all_ids:
            m = child[id_]
            d = m != orig
            _note("cli", id_, d, {"argv": _short(argv), "orig_rc": orig[0], "mut_rc": m[0],
                                  "orig_err": orig[2][-300:], "mut_err": m[2][-300:],
                                  "same_rc": orig[0] == m[0]} if d else None)
            slot = _STATE["cli"][id_]
            slot["rc_differ"] = slot.get("rc_differ", 0) + (1 if orig[0] != m[0] else 0)
        return rc

    return traced_main
