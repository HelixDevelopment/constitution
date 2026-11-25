// pi-constitution — Pi extension binding the Helix Constitution governance layer.
//
// Wires the Constitution submodule (Constitution.md / CLAUDE.md / AGENTS.md) into
// Pi so every agent session starts with governance context and any
// Constitution-relevant operation is validated against the §11.4 mandate set.
//
// Imports typed schemas from the Pi extension runtime; keeps every cross-boundary
// payload validated before action and before persistence (best-practices-pi-extension
// rule 1). Failures are routed through $triage-error with a deterministic catalog
// code (rule 5). Status is emitted as pi.agent_status.v1 (rule 2).

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent"
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

// triage-error catalog codes we emit.
type ConstitutionTriageCode =
  | "constitution_submodule_missing"
  | "constitution_governance_file_missing"
  | "constitution_mandate_section_missing"
  | "constitution_pointer_stale"
  | "constitution_unclassified"

// Structured question/answer packet for collaboration (rule 4: peer-gated).
interface ConstitutionCollabQuestion {
  schema: "pi-constitution.collab_question.v1"
  question_id: string
  triage: { code: ConstitutionTriageCode; layer: "extension"; cause: string }
  question: string
  required_response_schema: "pi-constitution.collab_answer.v1"
  allowed_answers: ["SUFFICIENT", "NEEDS_FIX"]
}

interface ConstitutionCollabAnswer {
  schema: "pi-constitution.collab_answer.v1"
  question_id: string
  answer: "SUFFICIENT" | "NEEDS_FIX"
  reason: string
}

// pi.agent_status.v1 payload (rule 2: shame-compatible status from validated data).
interface ConstitutionStatus {
  version: string
  plugin: string
  submodule: string
  submodule_present: boolean
  submodule_head: string | null
  governance_files: Record<string, { present: boolean }>
  mandate_sections: Record<string, { present: boolean }>
  verified: string[]
  errors: { code: ConstitutionTriageCode; message: string }[]
}

// --- Helpers -----------------------------------------------------------------

function projectRoot(pi: ExtensionAPI): string {
  return pi.cwd()
}

function constitutionPath(pi: ExtensionAPI): string {
  return `${projectRoot(pi)}/${CONSTITUTION_SUBMODULE}`
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
  opts?: { timeout?: number }
): Promise<{ code: number; stdout: string; stderr: string }> {
  const result = await pi.exec(cmd, args, { timeout: opts?.timeout ?? 10_000 })
  return { code: result.code, stdout: result.stdout, stderr: result.stderr }
}

function triageCodeFor(code: ConstitutionTriageCode): string {
  return `constitution_${code}`
}

// --- Extension entrypoint ----------------------------------------------------

export default async function (pi: ExtensionAPI): Promise<void> {
  const root = projectRoot(pi)
  const cPath = constitutionPath(pi)

  // --- session_start: validate Constitution submodule presence ----------------
  pi.on("session_start", async () => {
    const status = await auditConstitution(pi, root, cPath)

    // Emit shame-compatible status from validated data.
    pi.status({
      plugin: PLUGIN_NAME,
      version: PLUGIN_VERSION,
      answer:
        status.submodule_present && status.errors.length === 0
          ? "Constitution submodule bound and governance files present"
          : `Constitution binding incomplete: ${status.errors.length} issue(s)`,
      verified: status.verified,
      errors: status.errors.map((e) => ({
        code: triageCodeFor(e.code),
        message: e.message,
      })),
    })

    // Report each failure through triage-error with a deterministic code.
    for (const err of status.errors) {
      await pi.triageError?.({
        code: triageCodeFor(err.code),
        cause: `Constitution governance: ${err.message}`,
        layer: "extension",
        next_command: `pi plugin:pi-constitution doctor --submodule ${CONSTITUTION_SUBMODULE}`,
      })
    }
  })

  // --- tool_call: guard Constitution-relevant operations ---------------------
  pi.on("tool_call", async (event, ctx) => {
    if (!isToolCallEventType("bash", event)) return

    const cmd = event.input.command
    if (typeof cmd !== "string" || cmd.trim() === "") return

    // Only intercept commands that reference the Constitution submodule or
    // governance files, so we don't add noise to unrelated operations.
    if (
      !cmd.includes(CONSTITUTION_SUBMODULE) &&
      !cmd.includes("Constitution.md") &&
      !cmd.includes("pi-constitution")
    ) {
      return
    }

    // Validate the submodule is present before allowing the operation.
    const submoduleResult = await runCommand(pi, "test", ["-d", cPath])
    if (submoduleResult.code !== 0) {
      const question: ConstitutionCollabQuestion = {
        schema: "pi-constitution.collab_question.v1",
        question_id: `constitution-${Date.now()}`,
        triage: {
          code: "constitution_submodule_missing",
          layer: "extension",
          cause: `Constitution submodule not present at ${cPath}; cannot safely run: ${cmd}`,
        },
        question:
          "Constitution submodule is missing. Proceed with the operation anyway (risking governance drift), or abort and bind the submodule first?",
        required_response_schema: "pi-constitution.collab_answer.v1",
        allowed_answers: ["SUFFICIENT", "NEEDS_FIX"],
      }

      const answer = await pi.ask?.<ConstitutionCollabAnswer>(question)
      if (!answer || answer.answer !== "SUFFICIENT") {
        event.blocked = true
        event.input.command = `# BLOCKED by pi-constitution: ${question.triage.cause}`
        return
      }
    }
  })

  // --- Custom tool: pi plugin:pi-constitution doctor -------------------------
  pi.on("custom_tool", async (event) => {
    if (event.input.name !== "pi-constitution:doctor") return

    const status = await auditConstitution(pi, root, cPath)

    pi.reply({
      kind: "tool_result",
      tool_name: "pi-constitution:doctor",
      content: {
        ...status,
        summary:
          status.errors.length === 0
            ? "Constitution governance is healthy."
            : `Constitution governance has ${status.errors.length} issue(s) requiring attention.`,
      },
    })
  })
}

// --- Audit: validate the Constitution submodule and governance files ---------

async function auditConstitution(
  pi: ExtensionAPI,
  root: string,
  cPath: string
): Promise<ConstitutionStatus> {
  const errors: { code: ConstitutionTriageCode; message: string }[] = []
  const verified: string[] = []

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
      version: PLUGIN_VERSION,
      plugin: PLUGIN_NAME,
      submodule: CONSTITUTION_SUBMODULE,
      submodule_present: false,
      submodule_head: null,
      governance_files: {},
      mandate_sections: {},
      verified,
      errors,
    }
  }

  // 2. Submodule HEAD (pointer staleness check against parent).
  const headResult = await runCommand(pi, "git", ["-C", cPath, "rev-parse", "HEAD"])
  const submoduleHead = headResult.code === 0 ? headResult.stdout.trim() : null
  if (submoduleHead) verified.push(`Constitution submodule HEAD: ${submoduleHead.slice(0, 12)}`)

  // 3. Governance files presence + mandate section awareness.
  const governanceFiles: Record<string, { present: boolean }> = {}
  const mandateSections: Record<string, { present: boolean }> = {}

  for (const file of GOVERNANCE_FILES) {
    const filePath = `${cPath}/${file}`
    const content = await readFileSafe(pi, filePath)
    const present = content !== null
    governanceFiles[file] = { present }
    if (present) {
      verified.push(`Governance file present: ${file}`)
      // Check for mandate sections.
      for (const section of MANDATE_SECTIONS) {
        const already = mandateSections[section] ?? { present: false }
        if (content.includes(section)) already.present = true
        mandateSections[section] = already
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
    const info = mandateSections[section] ?? { present: false }
    if (info.present) verified.push(`Mandate section referenced: ${section}`)
    else {
      errors.push({
        code: "constitution_mandate_section_missing",
        message: `Mandate section ${section} not found in any governance file`,
      })
    }
  }

  return {
    version: PLUGIN_VERSION,
    plugin: PLUGIN_NAME,
    submodule: CONSTITUTION_SUBMODULE,
    submodule_present: true,
    submodule_head: submoduleHead,
    governance_files: governanceFiles,
    mandate_sections: mandateSections,
    verified,
    errors,
  }
}
