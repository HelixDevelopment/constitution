// scripts/label-sync/adapters/opencode/label-sync.mjs
//
// Purpose : OpenCode plugin -> label bus (§11.4.182). OpenCode loads JS/TS plugin
//           modules (`@opencode-ai/plugin`, `export default { server }` or a named
//           `Plugin` function; this file uses the default-module form) and calls their `event` and `chat.*` hooks. This
//           plugin maps session lifecycle events to the label contract by running
//           the agent-neutral adapter CLI (lib/label-adapter-event.sh), so all
//           logic stays in one place:
//             session.created   -> register  (subagent when info.parentID is set)
//             session.updated   -> heartbeat running
//             session.idle      -> heartbeat idle
//             session.deleted   -> done
//             chat.message      -> heartbeat running + the REAL model id
//                                  (<providerID>/<modelID> from the hook input)
// Usage   : install_adapters.sh copies/links this file and adds its path to
//           `plugin` in opencode.json. Manual: "plugin": ["file:///abs/path/label-sync.mjs"].
// Inputs  : OpenCode hook input only (session id, directory, parentID, model ids).
//           Messages, prompts, tool args and file contents are NEVER read.
// Outputs : none. The plugin NEVER throws, never blocks an event for more than
//           the spawn itself (fire-and-forget, detached stdio) — a label is
//           cosmetic. env LABEL_SYNC_PLUGIN_SYNC=1 awaits each call (tests only).
// Exit    : n/a (module). Deps: node (OpenCode runtime), bash, labelctl.sh.
// Cross-refs: §11.4.182, §11.4.18, docs/label-sync/ADAPTERS.md.
// Classification: universal (§11.4.17).
import { spawn } from "node:child_process"
import { fileURLToPath } from "node:url"
import path from "node:path"
import fs from "node:fs"

const HERE = path.dirname(fileURLToPath(import.meta.url))
const EVENT_CLI = path.join(HERE, "..", "lib", "label-adapter-event.sh")
const SYNC = process.env.LABEL_SYNC_PLUGIN_SYNC === "1"

function dbg(msg) {
  // LABEL_SYNC_ADAPTER_DEBUG=1: append a line to $LABEL_SYNC_DIR/adapters/opencode-plugin.log
  if (process.env.LABEL_SYNC_ADAPTER_DEBUG !== "1") return
  try {
    const dir = path.join(process.env.LABEL_SYNC_DIR || path.join(process.env.HOME || "/tmp", ".local/state/constitution-label-sync"), "adapters")
    fs.mkdirSync(dir, { recursive: true })
    fs.appendFileSync(path.join(dir, "opencode-plugin.log"), `${Date.now()} ${msg}\n`)
  } catch {
    /* debug only */
  }
}

function entityOf(sessionID) {
  // must equal al_entity_id() in adapter_lib.sh for agent "opencode"
  const safe = String(sessionID || "unknown").replace(/[^A-Za-z0-9._-]/g, "_")
  return `opencode-${safe}`
}

function run(args) {
  return new Promise((resolve) => {
    try {
      const child = spawn("bash", [EVENT_CLI, "--agent", "opencode", "--pid", String(process.pid), ...args], {
        stdio: "ignore",
        detached: !SYNC,
      })
      child.on("error", () => resolve())
      if (SYNC) child.on("exit", () => resolve())
      else {
        child.unref()
        resolve()
      }
    } catch {
      resolve()
    }
  })
}

const LabelSyncPlugin = async (input) => {
  const cwd = (input && (input.directory || input.worktree)) || process.cwd()
  dbg(`plugin loaded cwd=${cwd}`)
  return {
    event: async (arg) => {
      try {
        const event = arg && (arg.event || arg)
        dbg(`event-hook keys=${Object.keys(arg || {}).join(",")}`)
        const t = event && event.type
        dbg(`event ${t}`)
        const p = (event && event.properties) || {}
        const info = p.info || {}
        if (t === "session.created") {
          const args = ["--event", "register", "--session", String(info.id || ""), "--cwd", String(info.directory || cwd)]
          if (info.parentID) args.push("--kind", "subagent", "--parent", entityOf(info.parentID))
          if (info.id) await run(args)
        } else if (t === "session.updated") {
          if (info.id) await run(["--event", "heartbeat", "--session", String(info.id), "--cwd", String(info.directory || cwd), "--state", "running"])
        } else if (t === "session.idle") {
          if (p.sessionID) await run(["--event", "heartbeat", "--session", String(p.sessionID), "--cwd", cwd, "--state", "idle"])
        } else if (t === "session.deleted") {
          if (info.id) await run(["--event", "done", "--session", String(info.id)])
        }
      } catch {
        /* a label must never break the agent */
      }
    },
    "chat.message": async (inp) => {
      try {
        if (!inp || !inp.sessionID) return
        const m = inp.model
        const model = m && m.modelID ? (m.providerID ? `${m.providerID}/${m.modelID}` : m.modelID) : ""
        await run(["--event", "heartbeat", "--session", String(inp.sessionID), "--cwd", cwd, "--state", "running", ...(model ? ["--model", model] : [])])
      } catch {
        /* never break the agent */
      }
    },
  }
}

export default { id: "label-sync", server: LabelSyncPlugin }
