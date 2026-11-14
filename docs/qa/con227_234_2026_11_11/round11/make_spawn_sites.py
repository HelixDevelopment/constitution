import sys, collections
sys.path.insert(0, "tests/release")
import channel_census as cc
S=["scripts/release/tag_and_release.sh","scripts/release/derive_release_facts.sh","scripts/release_publish_gitea.sh","scripts/release/redact_cut.sh"]
env={}
for l in open("tests/release/channels.tsv"):
    if l.startswith("#") or not l.strip(): continue
    f=l.rstrip("\n").split("\t"); env[(f[0],f[1],f[2])]=f[4]
c=collections.Counter()
for s in S:
    for a,i,cmd,k,nl,via in cc.scan(s):
        cls = "network, through rc_net" if via in ("rc_net","nt","net") else ("re-execution (exec -c)" if via=="exec" else "local child")
        c[(a,cls,cmd,via or "-",env.get((a,cmd,k),"?"))]+=1
print("| Script | Class | Command | Reached via | Environment (channels.tsv) | Sites |")
print("|---|---|---|---|---|---|")
for k in sorted(c, key=lambda k:(k[0],k[1]!="network, through rc_net",k[2])): print("| "+" | ".join("`%s`"%x if j in (2,3,4) else x for j,x in enumerate(k))+" | %d |"%c[k])
