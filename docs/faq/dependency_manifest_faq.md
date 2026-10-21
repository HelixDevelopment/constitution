# Dependency Manifest FAQ — `helix-deps.yaml`

| Field | Value |
|---|---|
| Revision | 2 |
| Created | 2026-10-21 |
| Last modified | 2026-10-21T17:56:25Z |
| Status | active |
| Status summary | Questions raised while landing the §11.4.31 extension (2026-10-21) and while running the verifier on real trees, with the answers the engine and the constitution give. |
| Authority | Constitution §11.4.31. The canonical text wins where this FAQ and the constitution disagree. |
| Scope | Universal (§11.4.17). |
| Issues | none |
| Issues summary | — |
| Fixed | initial creation |
| Fixed summary | — |
| Continuation | — |

Related: [user guide](../guides/dependency_manifest_user_guide.md) · [manual](../manuals/dependency_manifest_manual.md)

## General

**1. Which repositories need a `helix-deps.yaml`?**
The project root always, plus every own-org repository the root or the constitution hub declares in
`.gitmodules`, plus every checked-out own-org repository under `<root>/submodules/*` or
`<root>/constitution/submodules/*`. Own-org means the remote's organisation is in the own-org list
(default `vasic-digital`, `HelixDevelopment`).

**2. Does a third-party submodule need one?**
No. It is reported `SKIP(third_party)` and never makes the check fail. It is also never reported as PASS,
because nothing was verified about it.

**3. Why must the project root have one even if the project belongs to another organisation?**
The root is where the dependency graph is rebuilt. Its manifest is the list a newcomer reads first.

**4. My repository has no own-org dependencies. Do I still need the file?**
Yes, with `deps: []`. An empty list is a statement; a missing file is silence, and silence cannot be told
apart from "nobody checked".

**5. Is the file name configurable?**
The engine reads `helix-deps.yaml`. §11.4.31 allows one other serialisation per repository if its
ecosystem strongly prefers it, but the verifier and the gate only understand the YAML file, so use it.

## Writing the file

**6. What is the smallest valid file?**
`schema_version: 1`, `deps: []`, a `transitive_handling` mapping with `recursive: true` and
`conflict_resolution: operator-required`, and `language_specific_subtree: false`. The manual §3.4 shows it.

**7. Why is my ref `0123456` not turned into a number?**
Every value is read as a string on purpose. A normal YAML loader would read `0123456` as an octal number
and lose the commit.

**8. Can I write `ref: TODO` and fill it in later?**
No. `UNKNOWN`, `TODO`, `TBD` and `FIXME` placeholders in `ref` or `why` are rejected (§11.4.6). Pin a real
tag or commit.

**9. Can I use an HTTPS URL?**
No. `ssh_url` must be `git@host:org/repo.git`. The constitution's Hard Stop #2 is SSH-only.

**10. Why does my dependency on another organisation fail?**
Every entry whose URL organisation is not own-org must say `third_party: true` and name a `licence`. That
keeps foreign code visible in the manifest instead of looking like your own.

**11. What do `flat`, `grouped` and `hub` mean?**
Where the dependency lives at the consuming root: `<root>/<name>/`, `<root>/submodules/<name>/`, or
`<root>/constitution/submodules/<name>/` (a constitution hub engine).

**12. What is `recursive_init: false` for?**
It marks an entry that must be initialised one level only, never with `git submodule update --recursive`,
because its recorded pin still nests own-org repositories. Tooling does not walk into it.

**13. Can I add my own keys, like `owner:`?**
No. The key sets are closed; an unknown key fails, which is how typos such as `layuot:` are caught.
Descriptive keys the engines already use (`name`, `ssh_url`, `mirrors`, `language`, `project_agnostic`,
`carve_out`, `third_party_manifest`) are allowed at top level.

## Generating the file

**14. How do I create a first version quickly?**
`bash constitution/scripts/deps_manifest/verify_helix_deps_manifests.sh --scaffold <dir> --write`.
It reads `.gitmodules`, `go.mod` and `package.json`.

**15. Will scaffold overwrite my existing file?**
Never. With `--write` it refuses and exits 1 if the file exists. Without `--write` it only prints.

**16. Why does the scaffold output fail validation?**
On purpose: every `why` is `UNKNOWN: …` and some refs may be `UNKNOWN-pin-me`. Only a person who knows why
the dependency exists can write that line.

**17. My Go module path is `digital.vasic.assets`. Why is it only a comment?**
A vanity module path does not say which repository serves it. The scaffold lists it as a `# NOTE` so you
add the entry with the right SSH URL by hand.

## Running the checks

**18. How do I check everything?**
`bash constitution/scripts/deps_manifest/verify_helix_deps_manifests.sh --root .` and read the `VERDICT`
line. Exit 0 PASS, 1 FAIL, 2 BLIND, 64 usage.

**19. What does BLIND mean, and why is it not a PASS?**
Something could not be checked: an own-org submodule is declared but not checked out, the root is
unreadable, or the tool failed its own control needles. Reporting PASS there would claim a check that never
happened.

**20. When does the check run automatically?**
On every constitution pull, through `scripts/post_update_hook.sh` step 5b, as the gate
`CM-HELIX-DEPS-MANIFEST-PRESENT` pointed at your project root. A FAIL makes the hook exit non-zero.

**21. What is a KNOWN line?**
A leaf repository nests an own-org repository, but its parent's entry already carries
`recursive_init: false`. The debt is real and owned by `CM-HUB-ENGINE-NO-OWNORG-NESTING`; this check
prints it so it is not hidden, without counting the same defect twice.

**22. The check says `undeclared own-org submodule`. I did add the submodule — what is missing?**
The matching `deps` entry in the manifest of the repository that carries the submodule (root or hub).
Submodule and entry belong in the same commit.

**23. The file exists but the check says it is not tracked.**
`git add helix-deps.yaml`. A file only in your working tree is absent from every fresh clone (§11.4.215).

**24. A submodule under `constitution/submodules/` fails. Can I fix it from my project?**
Not by editing it in place. Add or fix the manifest in that repository's own upstream, then bump the
constitution's pointer. Copies kept by a parent drift.

**25. Our project has its own `scripts/verify_helix_deps_manifests.sh`. Which one counts?**
The constitution's engine is the source of truth. A project script may only be a thin wrapper that calls
`constitution/scripts/deps_manifest/verify_helix_deps_manifests.sh`.

**26. Our organisation is not `vasic-digital` or `HelixDevelopment`.**
Pass `--own-orgs my-org,other-org` or set `HELIX_OWN_ORGS`.

**27. Does a PASS mean my refs match the pinned submodule commits?**
No. It means the manifests exist, are tracked, are well-formed, and cover the own-org submodules. Ref
drift against the recorded gitlinks is the job of `CM-DEPENDENCY-POINTER-PREFLIGHT-FAIL-CLOSED`
(§11.4.233(G)).

**28. A submodule with an https URL (for example `https://go.googlesource.com/go`) made the check report BLIND. Is that still so?**
No. The engine parses `https://`, `ssh://` and scp-style (`git@host:org/repo.git`) URLs. The organisation is the
first path segment (a single-segment path uses the host), so a URL whose organisation is not in the own-org list is
`SKIP(third_party)`, while an https URL of an own-org repository is still own-org and still needs its manifest. The
SSH-only rule applies to the `ssh_url` fields of the manifest, not to `.gitmodules`. A URL with another scheme, no
path, a `..` segment or whitespace stays BLIND: fix it in `.gitmodules`.
