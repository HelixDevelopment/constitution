#!/usr/bin/env python3
"""test_resolve2_fixture.py <dir> <n_java_methods> — Swift->ObjC bridge fixture for runner patch resolve2.

Purpose  A tiny project in which Swift call sites can ONLY resolve through the
         swift-objc-bridge framework resolver (no Swift definitions of the callee),
         the ObjC side has AMBIGUOUS candidates (two .m files define the same bridged
         selector, so `candidates[0]` — i.e. the iteration ORDER of ObjC methods —
         decides the target), and a large pool of NON-objc `method` nodes exists
         (Java), so "materialize every method node" is observable.
Output   files under <dir>; idempotent (the dir is recreated).
"""
import os, shutil, sys
d, n_java = sys.argv[1], int(sys.argv[2])
shutil.rmtree(d, ignore_errors=True)
os.makedirs(os.path.join(d, "objc"), exist_ok=True)
os.makedirs(os.path.join(d, "swift"), exist_ok=True)
os.makedirs(os.path.join(d, "java"), exist_ok=True)
os.makedirs(os.path.join(d, "aa"), exist_ok=True)
SELS = ["playWithSong", "fetchWithKey", "loadFromPath", "sendToHost", "renderInView"]
# NON-objc methods with the SAME bridged selector names, in a path that indexes FIRST:
# only the `language === 'objc'` filter keeps them out of the bridge candidate lists.
with open(os.path.join(d, "aa", "Early.java"), "w") as fh:
    fh.write("package aa;\npublic class Early {\n")
    for s in SELS:
        fh.write(f"    public void {s}(int x) {{ }}\n")
    fh.write("}\n")
for tag in ("A", "B", "C"):
    with open(os.path.join(d, "objc", f"Obj{tag}.h"), "w") as fh:
        fh.write(f"@interface Obj{tag} : NSObject\n")
        for s in SELS:
            fh.write(f"- (void){s}:(int)x;\n")
        fh.write("@end\n")
    with open(os.path.join(d, "objc", f"Obj{tag}.m"), "w") as fh:
        fh.write(f'#import "Obj{tag}.h"\n@implementation Obj{tag}\n')
        for s in SELS:
            fh.write(f"- (void){s}:(int)x {{\n    [self helper{tag}];\n}}\n")
        fh.write(f"- (void)helper{tag} {{\n}}\n@end\n")
with open(os.path.join(d, "swift", "Caller.swift"), "w") as fh:
    fh.write("import Foundation\n\nclass Caller {\n    func run(p: AnyObject) {\n")
    for s, base, lab in (("playWithSong", "play", "song"), ("fetchWithKey", "fetch", "key"),
                         ("loadFromPath", "load", "path"), ("sendToHost", "send", "host"),
                         ("renderInView", "render", "view")):
        fh.write(f"        p.{base}({lab}: 1)\n        {base}({lab}: 2)\n")
    fh.write("    }\n}\n")
per = 50
for i in range((n_java + per - 1) // per):
    with open(os.path.join(d, "java", f"J{i}.java"), "w") as fh:
        fh.write(f"package p;\npublic class J{i} {{\n")
        for m in range(per):
            fh.write(f"    public int m{i}_{m}() {{ return {m}; }}\n")
        fh.write("}\n")
print(f"fixture {d}: objc files=6 swift=1 java_methods~{n_java}")
