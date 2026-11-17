// scripts/label-sync/adapters/opencode/server.js
//
// Purpose : Directory entry point of the OpenCode label-sync plugin for opencode >= 2. The v2 loader accepts only a
//           DIRECTORY plugin entry (a single-file entry is skipped: "configured plugin path must be a directory") and
//           reads `server.js` / `index.js` from it; this file re-exports the one plugin definition of label-sync.mjs
//           (default export `{ id, server, setup }`), so 1.x (file entry) and >= 2 (directory entry) run the same code.
// Usage   : not run by hand. install_adapters.sh lists the DIRECTORY holding this file in opencode.json `plugin`
//           ("file:///abs/path/adapters/opencode") when `opencode --version` is >= 2 (LABEL_SYNC_OPENCODE_ENTRY=dir forces it).
// Inputs  : none (opencode imports the module).
// Outputs : none.
// Exit    : n/a (module).
// Side-effects: none beyond what label-sync.mjs does.
// Deps    : node/bun (the opencode runtime), label-sync.mjs beside this file.
// Cross-refs: §11.4.182, §11.4.18, docs/label-sync/ADAPTERS.md, label-sync.mjs.
// Classification: universal (§11.4.17).
export { default } from "./label-sync.mjs"
