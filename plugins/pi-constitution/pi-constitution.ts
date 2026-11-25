// pi-constitution — Pi extension binding the Helix Constitution governance layer.
//
// Wires the Constitution submodule (Constitution.md / CLAUDE.md / AGENTS.md) into
// Pi so every agent session starts with governance context and any
// Constitution-relevant operation is validated against the §11.4 mandate set.
//
// Uses only the documented Pi ExtensionAPI:
// - ctx.cwd (string property, not pi.cwd())
// - ctx.ui.setStatus / ctx.ui.confirm for status + peer gating
// - pi.registerTool for the pi-constitution:doctor custom tool
// - pi.exec for shell commands
// - pi.sendMessage for session messages
// - pi.on("session_start") / pi.on("tool_call") lifecycle hooks
//
// Failures are reported via validated data (ctx.ui.setStatus + sendMessage),
// not model prose (best-practices-pi-extension rule 2).

import type { ExtensionAPI, TSchema, Static } from "@earendil-works/pi-coding-agent"
import { Type } from "@sinclair/typebox"
import { isToolCallEventType } from "@earendil-works/pi-coding-agent"

const PLUGIN_NAME = "pi-constitution"
const PLUGIN_VERSION = "1.0.0"

// Constitution submodule location relative to the consuming project root.
const CONSTITUTION_SUBMODULE = "submodules/constitution"

// Governance files that must exist inside the Constitution submodule.
const GOVERNANCE_FILES = ["Constitution.md", "CLAUDE.md", "AGENTS.md"] as const

// Mandate sections the plugin enforces presence/awareness of.
const MANDATE_SECTIONS = ["§11.4.26", "§11.4.28", "§11.4.31", "§11.4.32"] as const

// --- Typed schemas (boundary validation) -------------------------------------

// triage-error catalog codes we emit (deterministic codes per rule 5).
type ConstitutionTriageCode =
  | "constitution_submodule_missing"
  | "constitution_governance_file_missing"
  | "constitution_mandate_section_missing"
  | "constitution_pointer_stale"

// pi-constitution:doctor tool parameters.
const DoctorParams = Type.Object({
  detail: Type.Optional(Type.Boolean()),
})
type DoctorParams = Static<typeof DoctorParams>

// --- Helpers -----------------------------------------------------------------

function constitutionPath(ctx: { cwd: string }): string {
  return `${ctx.cwd}/${CONSTITUTION_SUBMODULE}`
}

async function readFileSafe(pi: ExtensionAPI, path: string): Promise<string | null> {
  try {
    const result = await pi.exec("cat", [path], { timeout: 5_000 })
    if (result.code === 0) return result.stdout
    return null
  } catch {
    return null
  }
}

async function runCommand(
  pi: ExtensionAPI,
  cmd: string,
  args: string[],
  timeout = 10_000
): Promise<{ code: number; stdout: string; stderr: string }> {
  const result = await pi.exec(cmd, args, { timeout })
  return { code: result.code, stdout: result.stdout, stderr: result.stderr }
}

// --- Audit: validate the Constitution submodule and governance files ---------

interface GovernanceFileInfo {
  present: boolean
  path: string
}

interface MandateSectionInfo {
  present: boolean
  foundIn: string[]
}

interface AuditResult {
  submodulePresent: boolean
  submoduleHead: string | null
  governanceFiles: Record<string, GovernanceFileInfo>
  mandateSections: Record<string, MandateSectionInfo>
  verified: string[]
  errors: { code: ConstitutionTriageCode; message: string }[]
}

async function auditConstitution(
  pi: ExtensionAPI,
  ctx: { cwd: string }
): Promise<AuditResult> {
  const errors: { code: ConstitutionTriageCode; message: string }[] = []
  const verified: string[] = []
  const cPath = constitutionPath(ctx)

  // 1. Submodule presence.
  const subResult = await runCommand(pi, "test", ["-d", cPath])
  const submodulePresent = subResult.code === 0
  if (submodulePresent) verified.push(`Constitution submodule present at ${cPath}`)
  else {
    errors.push({
      code: "constitution_submodule_missing",
      message: `Constitution submodule not found at ${cPath}. Run: git submodule update --init ${CONSTITUTION_SUBMODULE}`,
    })
    return {
      submodulePresent: false,
      submoduleHead: null,
      governanceFiles: {},
      mandateSections: Object.fromEntries(MANDATE_SECTIONS.map((s) => [s, { present: false, foundIn: [] }])),
      verified,
      errors,
    }
  }

  // 2. Submodule HEAD.
  const headResult = await runCommand(pi, "git", ["-C", cPath, "rev-parse", "HEAD"])
  const submoduleHead = headResult.code === 0 ? headResult.stdout.trim() : null
  if (submoduleHead) verified.push(`Constitution submodule HEAD: ${submoduleHead.slice(0, 12)}`)

  // 3. Governance files presence + mandate section awareness.
  const governanceFiles: Record<string, GovernanceFileInfo> = {}
  const mandateSections: Record<string, MandateSectionInfo> = Object.fromEntries(
    MANDATE_SECTIONS.map((s) => [s, { present: false, foundIn: [] }])
  )

  for (const file of GOVERNANCE_FILES) {
    const filePath = `${cPath}/${file}`
    const content = await readFileSafe(pi, filePath)
    const present = content !== null
    governanceFiles[file] = { present, path: filePath }
    if (present) {
      verified.push(`Governance file present: ${file}`)
      for (const section of MANDATE_SECTIONS) {
        const info = mandateSections[section]
        if (content.includes(section)) {
          info.present = true
          info.foundIn.push(file)
        }
      }
    } else {
      errors.push({
        code: "constitution_governance_file_missing",
        message: `Governance file missing: ${filePath}`,
      })
    }
  }

  // 4. Mandate section coverage report.
  for (const section of MANDATE_SECTIONS) {
    const info = mandateSections[section]
    if (info.present) verified.push(`Mandate section referenced: ${section} (in ${info.foundIn.join(", ")})`)
    else {
      errors.push({
        code: "constitution_mandate_section_missing",
        message: `Mandate section ${section} not found in any governance file`,
      })
    }
  }

  return {
    submodulePresent: true,
    submoduleHead,
    governanceFiles,
    mandateSections,
    verified,
    errors,
  }
}

function formatAudit(result: AuditResult): string {
  const lines: string[] = []
  lines.push(`## pi-constitution audit`)
  lines.push(`- Submodule: ${result.submodulePresent ? "present" : "MISSING"}`)
  if (result.submoduleHead) lines.push(`- Submodule HEAD: ${result.submoduleHead.slice(0, 12)}`)
  for (const [file, info] of Object.entries(result.governanceFiles)) {
    lines.push(`- Governance ${file}: ${info.present ? "present" : "MISSING"}`)
  }
  for (const [section, info] of Object.entries(result.mandateSections)) {
    lines.push(`- Mandate ${section}: ${info.present ? `present (${info.foundIn.join(", ")})` : "MISSING"}`)
  }
  if (result.errors.length > 0) {
    lines.push("")
    lines.push(`### Errors (${result.errors.length})`)
    for (const err of result.errors) {
      lines.push(`- [${err.code}] ${err.message}`)
    }
  } else {
    lines.push("")
    lines.push("Constitution governance is healthy.")
  }
  return lines.join("\n")
}

// --- Extension entrypoint ----------------------------------------------------

export default async function (pi: ExtensionAPI): Promise<void> {
  // --- session_start: validate Constitution submodule presence ----------------
  pi.on("session_start", async (_event, ctx) => {
    const result = await auditConstitution(pi, ctx)

    // Shame-compatible status from validated data (rule 2).
    ctx.ui.setStatus(
      "constitution",
      result.errors.length === 0
        ? `Constitution bound (${result.submoduleHead?.slice(0, 12) ?? "?"})`
        : `Constitution: ${result.errors.length} issue(s)`
    )

    // Report result as a session message so it's visible in the transcript.
    pi.sendMessage({
      customType: "pi-constitution.audit",
      content: formatAudit(result),
      display: true,
      details: {
        plugin: PLUGIN_NAME,
        version: PLUGIN_VERSION,
        errorCount: result.errors.length,
        verifiedCount: result.verified.length,
      },
    })

    // Surface each failure as a deterministic triage code.
    for (const err of result.errors) {
      pi.sendMessage({
        customType: "pi-constitution.triage",
        content: `Constitution triage: ${err.code} — ${err.message}`,
        display: true,
        details: {
          code: err.code,
          layer: "extension",
          cause: err.message,
          nextCommand: `pi-constitution-doctor`,
        },
      })
    }
  })

  // --- tool_call: guard Constitution-relevant operations ---------------------
  pi.on("tool_call", async (event, ctx) => {
    if (!isToolCallEventType("bash", event)) return

    const cmd = event.input.command
    if (typeof cmd !== "string" || cmd.trim() === "") return

    // Only intercept commands that reference the Constitution submodule or
    // governance files.
    if (
      !cmd.includes(CONSTITUTION_SUBMODULE) &&
      !cmd.includes("Constitution.md") &&
      !cmd.includes("CLAUDE.md") &&
      !cmd.includes("AGENTS.md") &&
      !cmd.includes("pi-constitution")
    ) {
      return
    }

    // Validate the submodule is present before allowing the operation.
    const cPath = constitutionPath(ctx)
    const subResult = await runCommand(pi, "test", ["-d", cPath])
    if (subResult.code !== 0) {
      // Peer-gate: ask the user whether to proceed or abort.
      const proceed = await ctx.ui.confirm(
        "Constitution submodule missing",
        `Constitution submodule not present at ${cPath}.\n\nCommand: ${cmd}\n\nProceed anyway (risking governance drift)?`,
        { blockedKind: "permission" }
      )
      if (!proceed) {
        return { block: true, reason: `Constitution submodule missing at ${cPath}; bind it first (git submodule update --init ${CONSTITUTION_SUBMODULE})` }
      }
    }
  })

  // --- Custom tool: pi-constitution:doctor ----------------------------------
  pi.registerTool({
    name: "pi-constitution-doctor",
    label: "Constitution Doctor",
    description: "Run a full Constitution governance audit: submodule presence, governance files, mandate sections.",
    parameters: DoctorParams,
    execute: async (_toolCallId, params, _signal, _onUpdate, ctx) => {
      const result = await auditConstitution(pi, ctx)
      return {
        isError: result.errors.length > 0,
        content: [{ type: "text", text: formatAudit(result) }],
        structuredContent: {
          plugin: PLUGIN_NAME,
          version: PLUGIN_VERSION,
          submodulePresent: result.submodulePresent,
          submoduleHead: result.submoduleHead,
          errorCount: result.errors.length,
          verifiedCount: result.verified.length,
          errors: result.errors,
          governanceFiles: result.governanceFiles,
          mandateSections: result.mandateSections,
          verified: result.verified,
        },
      }
    },
  })
}
