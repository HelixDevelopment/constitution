#!/usr/bin/env python3
"""Run the gate's IDPY (extracted from the gate file) on authoriser/committer pairs; print rc per pair."""
import sys,subprocess,re
gate,table=sys.argv[1:3]
src=open(gate,encoding='utf-8').read(); m=re.search(r"^IDPY='(.*?)'$",src,re.S|re.M); idpy=m.group(1)
pairs=[("ｍilos","milos"),("alı","ali"),("milоs","milos"),("milοs","milos"),("аli","ali"),("mi1os","milos"),("rnilos","milos"),("ᾼ͂","ᾷ"),("ΆΊ","ᾴ́"),("release-mgr","milos"),("milo","milos"),("Milos Vasic","Милош Васић"),("ops","t1")]
for a,c in pairs:
    r=subprocess.run(["python3","-I","-c",idpy,table],input="\0".join([a,c,"","",""]).encode())
    print(r.returncode,ascii(a),ascii(c))
