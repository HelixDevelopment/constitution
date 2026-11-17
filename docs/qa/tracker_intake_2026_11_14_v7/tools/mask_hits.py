"""Print a masked shape of each leak-scan HIT line: alphanumerics masked, structure kept.
Never prints a value. Usage: python3 -I mask_hits.py <repo> <leak_scan run file>"""
import re
import sys

repo, run = sys.argv[1], sys.argv[2]
for ln in open(run, encoding="utf-8"):
    m = re.match(r"HIT (\S+) line=(\d+) kind=(\S+)", ln)
    if not m:
        continue
    path, lineno, kind = m.group(1), int(m.group(2)), m.group(3)
    try:
        text = open(f"{repo}/{path}", encoding="utf-8", errors="replace").read().splitlines()[lineno - 1]
    except Exception as e:  # report, never guess
        print(f"{path}:{lineno} {kind} UNREADABLE {type(e).__name__}")
        continue
    tags = []
    if re.search(r"\(\?|\\[sbdw]|\[\^", text):
        tags.append("regex-source")
    if re.search(r"<[A-Za-z_.-]{1,20}>", text):
        tags.append("angle-placeholder")
    if re.search(r"(?i)fake|needle|example|dummy|placeholder|xxxx|hunter2|s3cr3t|changeme", text):
        tags.append("fixture-word")
    shape = re.sub(r"[A-Za-z]", "a", re.sub(r"[0-9]", "9", text))
    shape = re.sub(r"a{4,}", lambda x: f"a{{{len(x.group())}}}", shape)
    print(f"{path}:{lineno} {kind} tags={','.join(tags) or 'NONE'} shape={shape[:160]}")
