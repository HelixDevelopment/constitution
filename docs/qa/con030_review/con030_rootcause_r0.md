# CON-030 root cause (read-only investigation, 11.4.102 / 11.4.292)

NOTE: the runner is Python. scripts/run_full_suite.sh is a thin wrapper; the code is
scripts/full_suite/run_full_suite.py (identical sub_paths on main, vehicle/con023 and the wip branches).

## Live reproduction (reproduced-host-fixture; host-only code)
Throwaway root (mktemp under .cache/claude-tmp, HOME=mktemp) with submodules "plain" and "sub dir".
`git submodule status --recursive` prints `<sha> plain (heads/main)` and ` <sha> sub dir (heads/main)`.
RED on the unfixed engine (functions imported, python3 -I):
  sub_paths: ['plain', 'sub']
  topology: ('standalone', 2, ['submodule sub: recorded commit 08df538fed38 is not in its object store'])
  quick_ident: ... sub=? ...   ident_diff(same, same) -> 'sub ? -> ?'
=> a topology gap => REFUSED-TOPOLOGY rc 9 (fail closed): the review r6 probe E symptom.
Instrument check: same functions return the right value for "plain" (no space).

## Exact lines (scripts/full_suite/run_full_suite.py on main)
- sub_paths(), ~L2192: `f = line[1:].split()` then `out_.append(f[1])` truncates at the first space.
- topology(), ~L2126: `flag, rest = line[0], line[1:].split()`; `sha, path = rest[0], rest[1]` same truncation; it then runs cat-file in the non-existent dir "sub" and emits the bogus "recorded commit not in object store" gap.
- quick_ident()/ident_diff(), ~L2200-2216 (latent third instance, visible only after the first two are fixed): identity is `" ".join("%s=%s")`, then `a.split()` and `x.split("=",1)`; "sub dir=<sha>" splits into keys "sub" and "dir".

## Root cause
`git submodule status` is `<flag><sha> <path>[ (<describe>)]`: human-oriented, path unquoted. Whitespace tokenising is the wrong parser, and the same space-separated record encoding is reused for the identity string.

## Proposed fix (test first): con030.patch
1. parse_sub_status(line): regex `^(.)([0-9a-f]{40,64}) (.+?)(?: \(([^()]*)\))?$`; used in topology() (unparseable line becomes an explicit gap, fail closed) and sub_paths().
2. quick_ident joins with TAB; ident_diff splits on TAB.
GREEN on a patched copy: sub_paths ['plain','sub dir'], topology gaps [], ident_diff(same,same) ''.
The patch = unified diff of the engine (applies to scripts/full_suite/run_full_suite.py) + appended text snippets for tests/test_run_full_suite.sh (RED/GREEN case) and tests/test_run_full_suite_mutations.sh (M30a restores the whitespace split in sub_paths; M30b restores the space join). Snippets were NOT executed inside the full suite.
Limits: a path literally ending in " (xyz)" without describe is ambiguous and stripped; TAB/newline in paths unsupported; the existing `"?" in qid` check would also fire for a path containing "?" (pre-existing, separate).

## Same word-splitting class elsewhere (control-needled, 11.4.273)
Control: grep count of the `submodule", "status", "--recursive"` call in the engine = 3 (known present); negative needle = 0.
- tree_ident(): hashes whole lines only; safe.
- submodule_paths(): `split(None,1)` on --get-regexp keeps the rest of line; ls-files -s splits on TAB; safe.
- extensions/install_speckit_superpowers_bridge.sh:306 and probe_bridge_layers.sh:134 query a fixed path, no parsing loop; safe.
- No unquoted `for x in $(... submodule ...)` loops found under scripts/.
Not audited in depth: scripts/fastcycle/verify/repo_verify.py and the gates (grepped only by the string "submodule status").
