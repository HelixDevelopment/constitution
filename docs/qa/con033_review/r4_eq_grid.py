"""Crafted-input differential for the review_record EQUIVALENT claims
(CON-033 round 4). Companion of r4_eq_trace.py; driven by
r4_equivalence_differential.sh.

usage: python3 -I r4_eq_grid.py ORIG.py EQDIR IDS.tsv SCRATCH  > grid.json

Two kinds of input:
  * function grids: the guarded function called directly over a crafted
    grid (adapted from the round-3 reviewer's probe eqdiff.py, extended to
    every claim and to the inputs each claim's own reasoning names);
  * CLI cases: crafted `record` / `backfill` / `gate` invocations, each run
    in a fresh copy of the same store for the original and for the mutant,
    compared on exit status, stdout and stderr (the store path normalised).
A claim is refuted at a level when one input differs. Output: JSON
{id: {fn_inputs, fn_differ, fn_first, cli_inputs, cli_differ, cli_rc_differ,
cli_first}}.
"""
import contextlib
import copy
import hashlib
import importlib.util
import io
import itertools
import json
import os
import shutil
import stat
import sys

orig_path, eqdir, idsf, scratch = sys.argv[1:5]
os.makedirs(scratch, exist_ok=True)


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


ORIG = load(orig_path, "rr_orig")
IDS = dict(line.split("\t") for line in open(idsf).read().splitlines())
MUT = {i: load(os.path.join(eqdir, i.replace("#", "_") + ".py"), "rr_m_" + i.replace("#", "_").replace("-", "_"))
       for i in IDS}
RES = {i: {"fn_inputs": 0, "fn_differ": 0, "fn_first": [], "cli_inputs": 0, "cli_differ": 0,
           "cli_rc_differ": 0, "cli_first": []} for i in IDS}


def canon(v):
    if isinstance(v, dict):
        return {"d": sorted(([canon(k), canon(x)] for k, x in v.items()), key=lambda p: json.dumps(p, sort_keys=True))}
    if isinstance(v, (list, tuple)):
        return [canon(x) for x in v]
    if isinstance(v, (set, frozenset)):
        return {"set": sorted((canon(x) for x in v), key=lambda p: json.dumps(p, sort_keys=True))}
    if isinstance(v, bytes):
        return {"bytes": hashlib.sha256(v).hexdigest()}
    if v is None or isinstance(v, (bool, int, float, str)):
        return [type(v).__name__, v]
    return {"obj": type(v).__name__}


def call(fn, args):
    try:
        return ["ret", canon(fn(*copy.deepcopy(args)))]
    except Exception as e:  # noqa: BLE001 - the exception TYPE is the observable
        return ["exc", type(e).__name__]


def fn_diff(ids, fname, inputs, setup=None):
    for args in inputs:
        if setup:
            setup()
        o = call(getattr(ORIG, fname), args)
        for i in ids:
            if setup:
                setup()
            m = call(getattr(MUT[i], fname), args)
            r = RES[i]
            r["fn_inputs"] += 1
            if m != o:
                r["fn_differ"] += 1
                if len(r["fn_first"]) < 3:
                    r["fn_first"].append({"args": repr(args)[:300], "orig": json.dumps(o)[:300],
                                          "mut": json.dumps(m)[:300]})


# ---------------------------------------------------------------- function grids
FV = [None, "", " ", "a.py", "b.py", 5, 0, True, ["a.py"], {"f": 1}]
LV = [None, 87, "87", " 87", 0, -1, True, False, "x", 1.5, "", [87]]
findings = [{"file": f, "line": l, "rule": r} for f, l, r in itertools.product(FV, LV, [None, "R1"])]
findings += [{}, {"rule": "R1"}, {"file": "a.py"}, {"line": 87}]
markers = [[]] + [[{"file": mf, "line": ml}] for mf, ml in itertools.product(FV, LV)]
markers += [[{}], [{"file": "a.py"}], [{"line": 87}], [{"file": "x", "line": 1}, {"file": "a.py", "line": "87"}]]
fn_diff([i for i in IDS if IDS[i] == "classify_finding"], "classify_finding",
        [(f, m) for f in findings for m in markers])
fn_diff([i for i in IDS if IDS[i] == "_normalize_line"], "_normalize_line",
        [(v,) for v in [None, True, False, 0, 1, -3, 87, "87", " 87 ", "-2", "", "x", 1.5, [], {}, b"1", "0x1"]])
vals = ["source-defect", "test-instrumentation", "process-doc", "x", "", 1, 0, True, False, [], {},
        ["source-defect"], 0.0, None, ("source-defect",), b"process-doc"]
fl = [({}, "L"), ({"x": 1}, "L")] + [({"finding_layer": v}, "L") for v in vals]
fl += [(x, "L") for x in [None, 5, "s", [], ["finding_layer"], ("finding_layer",), {"finding_layer"}]]
fn_diff([i for i in IDS if IDS[i] == "_validated_finding_layer"], "_validated_finding_layer", fl)


def getpw(uid):
    if not isinstance(uid, int) or uid > 10 ** 7:
        raise KeyError(uid)
    return None


uids = [None, True, False, -1, 0, 1, 1000, 65534, "1000", 1.0, 10 ** 8]
fn_diff([i for i in IDS if IDS[i] == "_owner_declaration_error"], "_owner_declaration_error",
        [(o, p, r, rg, getpw) for o in uids for p in [65534, 1000, None] for r in [1000, 2000]
         for rg in [[], [(100000, 65536)]]])
sids = {"s1", "s2"}
docs = [{}, {"slice_verdicts": None}, {"slice_verdicts": []}, {"slice_verdicts": "x"},
        {"slice_verdicts": [{"slice_id": "s1", "verdict": "GO"}]},
        {"slice_verdicts": [{"slice_id": "s1", "verdict": "NO-GO"}]},
        {"slice_verdicts": [{"slice_id": "s1", "verdict": "GO"}, {"slice_id": "s2", "verdict": "NO-GO"}]},
        {"slice_verdicts": [{"slice_id": None, "verdict": "GO"}]}, {"other": 1}]
fsets = [[], [{"id": "F1"}], [{"id": "F1", "slice_id": None}], [{"id": "F1", "slice_id": "s1"}],
         [{"id": "F1", "slice_id": "s1", "finding_layer": "source-defect"}], [{"id": "F1", "slice_id": "s2"}],
         [{"id": "F1", "slice_id": "zz"}], [{"id": "F1", "slice_id": ""}], [{"id": "F1", "slice_id": 0}]]
fn_diff([i for i in IDS if IDS[i] == "_validated_slice_verdicts"], "_validated_slice_verdicts",
        [(d, sids, v, fs) for d in docs for v in ["GO", "NO-GO"] for fs in fsets])
fn_diff([i for i in IDS if IDS[i] == "_validated_reviewer"], "_validated_reviewer",
        [(d,) for d in [{}, {"reviewer": None}, {"reviewer": "x"}, {"other": 1}, {"reviewer": {}},
                        {"reviewer": {"dispatch_id": "d", "model": "opus", "effort": "xhigh"}}]])
lists_in = [({"change_ids": c}, ch) for c in [None, [], ["a"], ["a", "a"], "a", "abc", ("a",), {"a": 1}, {"a"}, 5]
            for ch in ["a", "b", "ab"]]
fn_diff([i for i in IDS if IDS[i] == "_lists"], "_lists", lists_in)
units = [{"source": s, "reviewer": r, "batch_id": "B", "round": 1}
         for s in ["live", "backfill", None, "LIVE"] for r in [None, {"dispatch_id": "D1"}, {"dispatch_id": "D2"}]]
fn_diff([i for i in IDS if IDS[i] == "_dispatch_reuse"], "_dispatch_reuse",
        [([(u, "p")] , ) for u in units] + [([(u, "p"), (v, "q")],) for u in units for v in units])

# _evidence_bytes_verified: names, shapes, self-citation, FIFO (with and without a writer)
root = os.path.join(scratch, "evroot")
shutil.rmtree(root, ignore_errors=True)
os.makedirs(os.path.join(root, "sub"))
rec = os.path.join(root, "sub", "rec.json")
open(rec, "w").write("{}")
data = b'{"verdict": "GO"}'
open(os.path.join(root, "sub", "ev.json"), "wb").write(data)
good = hashlib.sha256(data).hexdigest()
empty = hashlib.sha256(b"").hexdigest()
recsha = hashlib.sha256(b"{}").hexdigest()
fifo = os.path.join(root, "sub", "fifo")
os.mkfifo(fifo)
os.link(rec, os.path.join(root, "sub", "rec_hard.json"))
names = ["ev.json", os.path.join(root, "sub", "ev.json"), "", "  ", "\t\n", "UNKNOWN", " ev.json ", "a\x00b",
         "ev.json\x00", "../../x", "sub", ".", "rec.json", "rec_hard.json", "fifo", "missing", 5, None]
shas = [good, good.upper(), "zz", "", None, 5, good + "\n", "g" * 64, " " + good, empty, recsha, "a\x00" * 32]
ev = [(n, s, own, root, os.path.dirname(rec)) for n in names for s in shas for own in (rec, None)]
fn_diff([i for i in IDS if IDS[i] == "_evidence_bytes_verified"], "_evidence_bytes_verified", ev)


HOLD = []


def with_writer():
    """A writer holding the FIFO open with the pinned bytes buffered. A
    helper reader end is kept open too (a write with no reader is EPIPE, and
    the buffer dies with the last end); each call starts a fresh pipe."""
    while HOLD:
        os.close(HOLD.pop())
    HOLD.append(os.open(fifo, os.O_RDONLY | os.O_NONBLOCK))
    HOLD.append(os.open(fifo, os.O_WRONLY | os.O_NONBLOCK))
    os.write(HOLD[-1], data)


fn_diff([i for i in IDS if IDS[i] == "_evidence_bytes_verified"], "_evidence_bytes_verified",
        [("fifo", good, rec, root, os.path.dirname(rec))], setup=with_writer)
while HOLD:
    os.close(HOLD.pop())

# _path_tier: the round-3 reviewer's tree (dot links, modes)
me = os.geteuid()
tree = os.path.join(scratch, "tree")
shutil.rmtree(tree, ignore_errors=True)
os.makedirs(tree, mode=0o700)
paths = []
for mode in (0o700, 0o755, 0o775, 0o777, 0o1777):
    d = os.path.join(tree, "d%o" % mode)
    os.makedirs(os.path.join(d, "s"))
    for nm, md in (("f", 0o600), ("g", 0o664)):
        open(os.path.join(d, nm), "w").write("x")
        os.chmod(os.path.join(d, nm), md)
    for ln, tgt in [("l_dot", "."), ("l_dotf", "./f"), ("l_up", "../d%o/./f" % mode), ("l_dd", "./s/../f")]:
        os.symlink(tgt, os.path.join(d, ln))
    os.chmod(d, mode)
    paths += [d, os.path.join(d, "f"), os.path.join(d, "g")] + [os.path.join(d, x) for x in
                                                                   ("l_dot", "l_dotf", "l_up", "l_dd")]
runner = me + 100000
pt = [([p], prod, me, runner, [], getpw) for p in paths for prod in (65534, None, "x", True, 0)]
fn_diff([i for i in IDS if IDS[i] == "_path_tier"], "_path_tier", pt)

# _admit_live is covered by the CLI cases below (it needs a whole admitted store).


# ---------------------------------------------------------------- CLI cases
def run_cli(mod, argv):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        try:
            rc = mod.main(list(argv))
        except SystemExit as se:
            rc = se.code
        except BaseException as e:  # noqa: BLE001
            rc = "raised:" + type(e).__name__
    return rc, out.getvalue(), err.getvalue()


CASE_N = [0]


def cli_case(ids, build, argv_of):
    """build(dir) creates the store; argv_of(dir) gives the argv. Each version
    gets its own fresh copy, built by the ORIGINAL tool."""
    CASE_N[0] += 1
    base = os.path.join(scratch, "cli%d" % CASE_N[0])
    shutil.rmtree(base, ignore_errors=True)
    tmpl = os.path.join(base, "tmpl")
    os.makedirs(tmpl)
    build(tmpl)
    outs = {}
    for v in ["orig"] + list(ids):
        d = os.path.join(base, "v_" + v.replace("#", "_"))
        shutil.copytree(tmpl, d, symlinks=True)
        rc, so, se = run_cli(ORIG if v == "orig" else MUT[v], argv_of(d))
        outs[v] = (rc, so.replace(d, "<D>"), se.replace(d, "<D>"))
    for i in ids:
        r = RES[i]
        r["cli_inputs"] += 1
        if outs[i] != outs["orig"]:
            r["cli_differ"] += 1
            r["cli_rc_differ"] += outs[i][0] != outs["orig"][0]
            if len(r["cli_first"]) < 3:
                r["cli_first"].append({"argv": " ".join(argv_of("<D>"))[:300], "orig": repr(outs["orig"])[:400],
                                       "mut": repr(outs[i])[:400]})
    shutil.rmtree(base, ignore_errors=True)


def write(p, doc, raw=None):
    with open(p, "w" if raw is None else "wb") as fh:
        if raw is None:
            json.dump(doc, fh)
        else:
            fh.write(raw)


def live_files(d, b_changes, v_changes, findings_=None, reviewer=True, slices=None):
    write(os.path.join(d, "batch.json"), {"batch_id": "B1", "changes": b_changes, "slices": slices or []})
    write(os.path.join(d, "precheck.json"), {"batch_id": "B1", "all_pass": True, "checks": [], "schema": "precheck/v1"})
    v = {"round": 1, "verdict": "GO", "findings": findings_ if findings_ is not None else [],
         "batch_id": "B1", "change_ids": v_changes, "review_base": "1" * 40, "review_head": "2" * 40}
    if reviewer:
        v["reviewer"] = {"dispatch_id": "D-REV-1", "model": "opus", "effort": "xhigh"}
    write(os.path.join(d, "verdict.json"), v)
    os.makedirs(os.path.join(d, "rec"), exist_ok=True)


def record_argv(d):
    return ["record", "--batch", d + "/batch.json", "--round", "1", "--verdict-file", d + "/verdict.json",
            "--precheck", d + "/precheck.json", "--tier", "opus", "--effort", "xhigh",
            "--producer-id", "PRODUCER-1", "--out", d + "/rec/r1.json"]


rec_ids = [i for i in IDS if IDS[i] == "cmd_record"] + [i for i in IDS if IDS[i] == "_validated_finding_layer"]
CH = ["c1", "c2", "c3"]
bvals = [["c1"], ["c1", "c1"], ["c1", "c2"], ["c1", "c1", "c2"], ["c2", "c1"], ["c1", 5], [], "c1", None,
         ["c1", "c2", "c2"]]
vvals = [["c1"], ["c1", "c2"], ["c1", "c1"], ["c2", "c1"], []]
for bv, vv in itertools.product(bvals, vvals):
    cli_case(rec_ids, lambda d, bv=bv, vv=vv: live_files(d, bv, vv), record_argv)
for fd in [[5], ["x"], [None], [["F1"]], [{"id": "F1", "finding_layer": "source-defect", "file": "a", "line": 1}],
           [{"id": "F1"}], [{"id": "F1", "finding_layer": ["source-defect"]}], [{"id": "F1", "finding_layer": None}]]:
    for rv in (True, False):
        cli_case(rec_ids, lambda d, fd=fd, rv=rv: live_files(d, ["c1"], ["c1"], fd, rv), record_argv)


def gate_argv(change):
    return lambda d: ["gate", "--change", change, "--records", d + "/rec"]


def store_with(d, edit_rec=None, edit_ev=None, extra=None):
    """A genuine store: one live record written by the ORIGINAL tool, then
    optionally edited (record fields or its verdict evidence) with every
    pin recomputed so the edit reaches the guard under test."""
    live_files(d, ["c1", "c2"], ["c1", "c2"])
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        rc = ORIG.main(record_argv(d))
    assert rc == 0, "template record not written (rc %r)" % rc
    rp = os.path.join(d, "rec", "r1.json")
    doc = json.load(open(rp))
    if edit_ev:
        evp = os.path.join(d, "rec", doc["verdict_evidence"])
        ev = json.load(open(evp))
        edit_ev(ev)
        raw = json.dumps(ev).encode()
        os.remove(evp)
        sha = hashlib.sha256(raw).hexdigest()
        name = doc["verdict_evidence"].replace(doc["verdict_evidence_sha256"], sha)
        write(os.path.join(d, "rec", name), None, raw)
        doc["verdict_evidence"], doc["verdict_evidence_sha256"] = name, sha
    if edit_rec:
        edit_rec(doc)
    body = {k: v for k, v in doc.items() if k not in ("body_hash", "run_meta")}
    doc["body_hash"] = ORIG._body_hash_of(body)
    write(rp, doc)
    if extra:
        extra(d)


gate_ids = [i for i in IDS if IDS[i] in ("_admit_live", "_dispatch_reuse", "_lists", "_evidence_bytes_verified")]


def set_(k, v):
    return lambda doc: doc.__setitem__(k, v)


edits = [None, set_("change_ids", ["c1", "c1", "c2"]), set_("change_ids", ["c1", "c2", "c2"]),
         set_("change_ids", ["c1", "c1"]), set_("change_ids", ["c2", "c1"]), set_("change_ids", ["c1"]),
         set_("change_ids", "c1"), set_("verdict_evidence", "a\x00b"), set_("verdict_evidence", " "),
         set_("verdict_evidence_sha256", "A" * 64), set_("verdict_evidence_sha256", "zz"),
         set_("source", "backfill"), set_("reviewer_dispatch_id", None)]


def multi(**kv):
    return lambda doc: doc.update(kv)


# two fields at once: an unusable name AND a malformed hash (each guard alone is not enough)
for nm in ("a\x00b", " ", "\t", "UNKNOWN", "rec/../x\x00"):
    for sh in ("A" * 64, "zz", "", "g" * 64, 5, None):
        edits.append(multi(verdict_evidence=nm, verdict_evidence_sha256=sh))
ev_edits = [None, lambda ev: ev.__setitem__("change_ids", ["c1", "c1", "c2"]),
            lambda ev: ev.__setitem__("change_ids", ["c1", "c1"]), lambda ev: ev.pop("reviewer"),
            lambda ev: ev.__setitem__("findings", [5, {"id": "F1"}])]


def backfill_row(d, verdict="GO", changes=None):
    spec = {"review_id": "R-BF", "batch_id": "B1", "round": 1, "verdict": verdict, "source_evidence": "UNKNOWN"}
    if changes is not None:
        spec["change_ids"] = changes
    write(os.path.join(d, "bf.json"), spec)
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        ORIG.main(["backfill", "--input", d + "/bf.json", "--out", d + "/rec/bf1.json"])


for er, ee in itertools.product(edits, ev_edits):
    for ch in ("c1", "c2", "c3"):
        cli_case(gate_ids, lambda d, er=er, ee=ee: store_with(d, er, ee), gate_argv(ch))
for verdict in ("GO", "NO-GO"):
    for chs in (None, ["c1"], ["c1", "c1"], "UNKNOWN", ["c3"]):
        for ch in ("c1", "c3"):
            cli_case(gate_ids, lambda d, v=verdict, c=chs: store_with(
                d, extra=lambda dd: backfill_row(dd, v, c)), gate_argv(ch))


# a FIFO planted as the verdict evidence, with a writer holding the pinned bytes
def fifo_case(ids):
    CASE_N[0] += 1
    base = os.path.join(scratch, "fifo%d" % CASE_N[0])
    shutil.rmtree(base, ignore_errors=True)
    outs = {}
    for v in ["orig"] + list(ids):
        d = os.path.join(base, "v_" + v.replace("#", "_"))
        os.makedirs(d)
        store_with(d)
        doc = json.load(open(os.path.join(d, "rec", "r1.json")))
        evp = os.path.join(d, "rec", doc["verdict_evidence"])
        payload = open(evp, "rb").read()
        os.remove(evp)
        os.mkfifo(evp)
        rfd = os.open(evp, os.O_RDONLY | os.O_NONBLOCK)
        wfd_ = os.open(evp, os.O_WRONLY | os.O_NONBLOCK)
        os.write(wfd_, payload)
        rc, so, se = run_cli(ORIG if v == "orig" else MUT[v], gate_argv("c1")(d))
        os.close(wfd_)
        os.close(rfd)
        outs[v] = (rc, so.replace(d, "<D>"), se.replace(d, "<D>"))
    for i in ids:
        r = RES[i]
        r["cli_inputs"] += 1
        if outs[i] != outs["orig"]:
            r["cli_differ"] += 1
            r["cli_rc_differ"] += outs[i][0] != outs["orig"][0]
            if len(r["cli_first"]) < 3:
                r["cli_first"].append({"argv": "gate (FIFO evidence with a writer)", "orig": repr(outs["orig"])[:400],
                                       "mut": repr(outs[i])[:400]})
    shutil.rmtree(base, ignore_errors=True)


fifo_case(gate_ids)

for i in RES:
    RES[i]["function"] = IDS[i]
json.dump(RES, sys.stdout, indent=1, sort_keys=True)
