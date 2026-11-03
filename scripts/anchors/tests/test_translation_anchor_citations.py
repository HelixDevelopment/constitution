"""Stale translation-sense citations of 11.4.140 / 11.4.141 (2026-08-18 re-mint).

The HelixTranslate pipeline and the independent per-language review were
re-minted from 11.4.140/11.4.141 to 11.4.255/11.4.256 (commit 5ed8c80).
11.4.140 is now the action-prefix system and 11.4.141 token efficiency, so a
sentence that cites 140/141 in the translation sense is stale. Sentences that
document the re-mint itself (re-mint / collision / redirect wording) are
exempt; citations in the action-prefix / token-efficiency sense are never
flagged (golden-FALSE with carrier, section 11.4.201(1)).
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from _paths import CANON  # noqa: E402

CITE = re.compile(r"11\.4\.14[01](?!\d)")
SENSE = re.compile(r"translat|helixtranslate|per-language|localiz", re.I)
EXEMPT = re.compile(r"re-?mint|collision|redirect|resolved 2026-08-18|formerly", re.I)


def stale_sentences(text):
    out = []
    for para in text.splitlines():
        for sent in re.split(r"(?<=[.;])\s+", para):
            if CITE.search(sent) and SENSE.search(sent) and not EXEMPT.search(sent):
                out.append(sent.strip()[:160])
    return out


FILES = ["Constitution.md", "CLAUDE.md", "AGENTS.md", "QWEN.md", "GEMINI.md",
         os.path.join("docs", "translations.md")]
fails = 0


def check(name, cond):
    global fails
    print(("PASS " if cond else "FAIL ") + name)
    if not cond:
        fails += 1


# Fixtures (instrument self-validation)
check("golden-bad: translation sense flagged",
      len(stale_sentences("Composes §11.4.140 (canonical translation pipeline) / §11.4.6.")) == 1)
check("golden-bad: per-language review flagged",
      len(stale_sentences("Every translation reviewed per §11.4.141 per-language.")) == 1)
check("golden-FALSE carrier: action-prefix sense not flagged",
      stale_sentences("§11.4.140 universal action-prefix system (ACTION_NAME ::).") == [])
check("golden-FALSE carrier: token-efficiency sense not flagged",
      stale_sentences("§11.4.141 token-efficiency mandate; reads are targeted.") == [])
check("golden-FALSE carrier: re-mint note exempt",
      stale_sentences("Translation was re-minted from 11.4.140 to 11.4.255.") == [])

for rel in FILES:
    with open(os.path.join(CANON, rel), encoding="utf-8") as f:
        bad = stale_sentences(f.read())
    check("no stale translation-sense 140/141 citation in " + rel, not bad)
    for b in bad:
        print("   STALE: " + b)

sys.exit(1 if fails else 0)
