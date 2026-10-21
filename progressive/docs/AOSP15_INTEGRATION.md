# AOSP 15 consumer integration

The constitution is a **developer/agent tooling** layer. It never enters an OS
partition.

| Requirement | How it is met |
|---|---|
| Build outputs unchanged | No source file outside `constitution/progressive/` is touched; the generator writes only inside it. |
| No new build dependency | Python 3 standard library only; `tiktoken` is used by the validator, not by the build. |
| No Soong/Make changes | No `.mk`, `.bp`, `Android.bp`, or build script is added or modified. |
| Offline | The MCP server and all validators run without network. |
| Namespacing | Every surface is prefixed `helix-constitution` / `hp.*`; no existing namespace is claimed. |
| Runtime impact | None: nothing is shipped into `system`, `vendor`, or `boot`. |

**Honest boundary:** the before/after hash comparison of real AOSP images is NOT
performed here (it needs a full build on the operator's workstation). The claim
above is structural: the change set is confined to `constitution/progressive/`,
which no build target reads.
