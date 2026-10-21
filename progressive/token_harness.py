#!/usr/bin/env python3
"""token_harness.py — REAL provider token measurement for the progressive layer.

Pack 02 §3 / pack 03 §10 DoD 6-7: produce TOKENS_BEFORE.json / TOKENS_AFTER.json
from real model calls, per prompt, and prove the cache-collapse mutation.

Nothing here is simulated or estimated: every number is the `usage` object the
provider returned for a real `claude --print` turn. If a call fails, the run
aborts and writes NOTHING (the validator then stays UNCONFIRMED).

ARMS (identical harness, identical prompts, identical settings; only the
governance text appended to the system prompt differs):
  BEFORE  the monolithic delivery consumers load today: constitution/CLAUDE.md
  AFTER   the progressive delivery: progressive/core.md + progressive/catalog.json
          (lean core + discoverable catalog; rule bodies load on demand)

CORPUS: deterministic — derived from catalog.json (evenly strided §11.4.* anchors),
written to EVIDENCE/corpus/corpus.json with its sha256. Each prompt asks which
anchor governs a topic; the expected id is known, so answer correctness is
recorded per arm (a token saving that loses the answer would be a regression).

Usage:
  token_harness.py corpus            freeze the corpus
  token_harness.py run               run both arms -> TOKENS_BEFORE/AFTER.json
  token_harness.py cache-proof       volatile-token mutation -> CACHE_PROOF.json
Exit: 0 written; 3 a provider run failed (nothing written).
"""
import concurrent.futures as cf
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

PROG = Path(__file__).resolve().parent
ROOT = PROG.parent
EV = PROG / "EVIDENCE"
CORPUS = EV / "corpus" / "corpus.json"
N_PROMPTS = int(os.environ.get("TOKEN_HARNESS_N", "24"))
MODEL = os.environ.get("TOKEN_HARNESS_MODEL", "sonnet")
BUDGET = os.environ.get("TOKEN_HARNESS_BUDGET_USD", "3")
WORKERS = int(os.environ.get("TOKEN_HARNESS_WORKERS", "4"))


def sha256(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def build_corpus():
    cat = json.loads((PROG / "catalog.json").read_text(encoding="utf-8"))["anchors"]
    pool = sorted((e for e in cat if re.fullmatch(r"§11\.4\.\d+", e["id"])),
                  key=lambda e: int(e["id"].rsplit(".", 1)[1]))
    stride = max(1, len(pool) // N_PROMPTS)
    pick = pool[stride // 2::stride][:N_PROMPTS]
    prompts = []
    for e in pick:
        topic = re.sub(r"\s+", " ", e["title"]).strip()
        topic = re.sub(r"§\d+(\.\d+)*", "", topic).strip(" -—:")
        prompts.append({
            "expected": e["id"],
            "prompt": ("Which constitution anchor id governs this topic? Topic: "
                       f"{topic[:160]}. Answer with the anchor id only, in the form §11.4.N."),
        })
    return {"model": MODEL, "arms": {"before": "constitution/CLAUDE.md (monolith)",
                                       "after": "progressive/core.md + progressive/catalog.json"},
            "prompts": prompts}


def freeze_corpus():
    c = build_corpus()
    if len(c["prompts"]) < 20:
        sys.exit("token_harness: corpus has fewer than 20 prompts")
    CORPUS.parent.mkdir(parents=True, exist_ok=True)
    CORPUS.write_text(json.dumps(c, indent=1, sort_keys=True) + "\n", encoding="utf-8")
    print(f"corpus: {len(c['prompts'])} prompts sha256={sha256(CORPUS)}")


def claude_turn(prompt: str, sysfile: Path, workdir: Path):
    cmd = ["claude", "--print", "--output-format", "json", "--no-session-persistence",
           "--max-budget-usd", BUDGET, "--model", MODEL, "--setting-sources", "project",
           "--append-system-prompt-file", str(sysfile), prompt]
    r = subprocess.run(cmd, cwd=workdir, capture_output=True, text=True, timeout=600)
    try:
        d = json.loads(r.stdout)
    except Exception:
        raise RuntimeError(f"no JSON from claude (rc={r.returncode}): {r.stderr[:200]}")
    if d.get("is_error") or "usage" not in d:
        raise RuntimeError(f"turn failed: {str(d)[:200]}")
    return d


def total(u):
    return sum(int(u.get(k, 0)) for k in
               ("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens", "output_tokens"))


def run_arm(name: str, sysfile: Path, corpus: dict, workdir: Path):
    prompts = corpus["prompts"]
    results = {}

    def one(i):
        d = claude_turn(prompts[i]["prompt"], sysfile, workdir)
        exp = prompts[i]["expected"]
        ok = re.search(re.escape(exp) + r"(?!\d)", d.get("result", "")) is not None
        return i, d["usage"], d.get("total_cost_usd", 0.0), ok, d.get("result", "")[:80]

    # warm the cache with one turn first, then fan out (avoids N cache writes)
    first = one(0)
    results[first[0]] = first
    with cf.ThreadPoolExecutor(max_workers=WORKERS) as ex:
        for r in ex.map(one, range(1, len(prompts))):
            results[r[0]] = r
    per = {prompts[i]["prompt"]: total(results[i][1]) for i in range(len(prompts))}
    return {
        "arm": name, "model": MODEL, "total": sum(per.values()),
        "total_cost_usd": round(sum(results[i][2] for i in results), 4),
        "correct": sum(1 for i in results if results[i][3]),
        "prompts": per,
        "detail": [{"expected": prompts[i]["expected"], "usage": results[i][1],
                    "correct": results[i][3], "answer": results[i][4]} for i in range(len(prompts))],
    }


def cmd_run():
    if not CORPUS.is_file():
        freeze_corpus()
    corpus = json.loads(CORPUS.read_text(encoding="utf-8"))
    work = Path(tempfile.mkdtemp(prefix="th_"))
    try:
        (work / "w").mkdir()
        subprocess.run(["git", "init", "-q"], cwd=work / "w", check=True)
        before_txt = ROOT / "CLAUDE.md"
        after_txt = work / "after_governance.md"
        after_txt.write_text((PROG / "core.md").read_text(encoding="utf-8") + "\n\n"
                             + (PROG / "catalog.json").read_text(encoding="utf-8"), encoding="utf-8")
        out = {}
        for name, f in (("before", before_txt), ("after", after_txt)):
            print(f"arm {name}: {f.name} ({f.stat().st_size} bytes) x {len(corpus['prompts'])} prompts ...", flush=True)
            out[name] = run_arm(name, f, corpus, work / "w")
            print(f"  total={out[name]['total']} cost=${out[name]['total_cost_usd']} correct={out[name]['correct']}/{len(corpus['prompts'])}", flush=True)
    except Exception as e:  # nothing is written on any failure
        print(f"token_harness: provider run failed — UNCONFIRMED, nothing written: {e}", file=sys.stderr)
        sys.exit(3)
    finally:
        shutil.rmtree(work, ignore_errors=True)
    meta = {"corpus_sha256": sha256(CORPUS), "claude_version": subprocess.run(["claude", "--version"], capture_output=True, text=True).stdout.strip()}
    ratio = out["after"]["total"] / out["before"]["total"]
    for name, fn in (("before", "TOKENS_BEFORE.json"), ("after", "TOKENS_AFTER.json")):
        d = dict(out[name]); d.update(meta)
        (EV / fn).write_text(json.dumps(d, indent=1, sort_keys=True) + "\n", encoding="utf-8")
    print(f"aggregate AFTER/BEFORE = {ratio:.4f}; answers correct before={out['before']['correct']} after={out['after']['correct']}")


def cmd_cache_proof():
    """Volatile-token mutation (pack 03 §10 DoD 7): a unique token at the START of
    the governance text must collapse the cache reuse of the second identical run."""
    work = Path(tempfile.mkdtemp(prefix="th_cp_"))
    try:
        (work / "w").mkdir(); subprocess.run(["git", "init", "-q"], cwd=work / "w", check=True)
        base = (PROG / "core.md").read_text(encoding="utf-8") + "\n\n" + (PROG / "catalog.json").read_text(encoding="utf-8")
        P = "Reply with the single word: ok"

        def two(label, make):
            res = []
            for i in range(2):
                f = work / f"{label}{i}.md"; f.write_text(make(i), encoding="utf-8")
                d = claude_turn(P, f, work / "w"); u = d["usage"]
                t = u["input_tokens"] + u["cache_read_input_tokens"] + u["cache_creation_input_tokens"]
                res.append({"cache_read": u["cache_read_input_tokens"], "cache_creation": u["cache_creation_input_tokens"],
                            "prompt_total": t, "reuse_ratio": round(u["cache_read_input_tokens"] / t, 4)})
            return res
        stable = two("stable", lambda i: base)
        volatile = two("volatile", lambda i: f"run-token {os.urandom(8).hex()}-{i}\n" + base)
    except Exception as e:
        print(f"token_harness: cache proof failed — UNCONFIRMED, nothing written: {e}", file=sys.stderr); sys.exit(3)
    finally:
        shutil.rmtree(work, ignore_errors=True)
    collapsed = volatile[1]["reuse_ratio"] < 0.5 * stable[1]["reuse_ratio"]
    out = {"stable": stable, "volatile": volatile, "collapse_observed": collapsed,
           "note": "reuse_ratio of the SECOND run; volatile = unique token prepended to the governance text each run"}
    (EV / "CACHE_PROOF.json").write_text(json.dumps(out, indent=1, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(out, indent=1))
    sys.exit(0 if collapsed else 3)


if __name__ == "__main__":
    {"corpus": freeze_corpus, "run": cmd_run, "cache-proof": cmd_cache_proof}.get(
        sys.argv[1] if len(sys.argv) > 1 else "", lambda: sys.exit(__doc__))()
