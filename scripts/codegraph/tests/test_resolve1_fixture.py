#!/usr/bin/env python3
"""Deterministic fixture generator for the resolve1 study.

usage: gen_fixture.py <outdir> <n_filler> <n_probe> [--mixed]
  filler : n_filler tiny C files (lowercase calls only -> never reach vue's
           PascalCase path); these only grow the files table (the N in O(N)).
  probe  : n_probe C++ files, each with 2 PascalCase `calls` refs
           (HelperJ -> defined, Widget -> the Vue component) = the per-ref
           O(#files) path in stock vue.resolveComponent.
  web/Widget.vue : makes the vue framework detect() true (as on AOSP).
  --novue: omit web/Widget.vue (vue must NOT be detected).
  --mixed: adds a small AOSP-like mix (java/kotlin/python/js/ts/sh/go/c/h)
           with imports, includes, PascalCase + lowercase calls.
Content is a pure function of the arguments (no randomness, no timestamps).
"""
import os
import sys


def w(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)


def main():
    out, n_fill, n_probe = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    mixed = "--mixed" in sys.argv[4:]
    for k in range(n_fill):
        w(f"{out}/fill/d{k // 1000:04d}/f{k}.c",
          f"static int g_{k}(int x) {{ return x + {k % 7}; }}\n"
          f"int f_{k}(int x) {{ return g_{k}(x); }}\n")
    for j in range(n_probe):
        w(f"{out}/probe/q{j // 500:03d}/p{j}.cpp",
          f"void Helper{j}() {{}}\n"
          f"void Probe{j}() {{ Helper{j}(); Widget(); }}\n")
    if "--novue" not in sys.argv[4:]:
      w(f"{out}/web/Widget.vue",
        "<template><div>{{ msg }}</div></template>\n"
        "<script>\nexport default { name: 'Widget', data() { return { msg: 'hi' }; } };\n</script>\n")
    if mixed:
        w(f"{out}/libcore/src/main/java/java/util/Box.java",
          "package java.util;\nimport java.util.List;\n"
          "public class Box { public int size() { return 0; }\n"
          "  public static Box make() { Box b = new Box(); b.size(); return b; } }\n")
        w(f"{out}/libcore/src/main/java/java/util/User.java",
          "package java.util;\nimport java.util.Box;\n"
          "public class User extends Object { void run() { Box b = Box.make(); b.size(); Helper0(); } }\n")
        w(f"{out}/frameworks/base/core/Kit.kt",
          "package android.kit\nimport java.util.Box\n"
          "class Kit { fun go(): Int { val b = Box(); return b.size() } }\n"
          "fun Build(): Kit = Kit()\nfun use() { Build().go(); Widget() }\n")
        w(f"{out}/external/pytool/tool/core.py",
          "import os\nfrom tool.util import Parser, helper\n\n"
          "class Runner:\n    def run(self):\n        p = Parser()\n        return helper(p)\n")
        w(f"{out}/external/pytool/tool/util.py",
          "class Parser:\n    pass\n\ndef helper(x):\n    return Parser()\n")
        w(f"{out}/external/pytool/tool/__init__.py", "")
        w(f"{out}/tools/web/src/app.js",
          "import { Widget } from './widget.js';\nconst util = require('./util.js');\n"
          "export function App() { return Widget() + util.run(); }\n")
        w(f"{out}/tools/web/src/widget.js", "export function Widget() { return 1; }\n")
        w(f"{out}/tools/web/src/util.js", "module.exports = { run() { return 2; } };\n")
        w(f"{out}/tools/web/src/main.ts",
          "import { App } from './app';\nexport const Main = (): number => App();\n")
        w(f"{out}/build/envsetup.sh",
          "#!/bin/sh\nsource ./lib.sh\nsetup() { helper_fn; Widget; }\nsetup\n")
        w(f"{out}/build/lib.sh", "helper_fn() { echo hi; }\n")
        w(f"{out}/tools/go/main.go",
          "package main\nimport \"fmt\"\nfunc Run() int { return 1 }\n"
          "func main() { fmt.Println(Run()); Helper() }\nfunc Helper() {}\n")
        w(f"{out}/system/core/include/util.h",
          "#pragma once\nint UtilAdd(int a, int b);\n#define LOGE(x) (void)(x)\n")
        w(f"{out}/system/core/util.c",
          "#include \"include/util.h\"\nint UtilAdd(int a, int b) { LOGE(a); return a + b; }\n")
        w(f"{out}/system/core/main.cpp",
          "#include <vector>\n#include \"include/util.h\"\nclass Svc { public: int Run(); };\n"
          "int Svc::Run() { std::vector<int> v; v.push_back(UtilAdd(1, 2)); return Size(v); }\n"
          "int Size(const std::vector<int>& v) { return (int)v.size(); }\n")


if __name__ == "__main__":
    main()
