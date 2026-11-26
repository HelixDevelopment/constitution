# pi-constitution — Technical Specification

**Version:** 1.0.0 · **Schema:** `pi.extension.v1` · **Status:** active

This document is the authoritative technical specification for the `pi-constitution`
Pi extension. It defines types, schemas, event contracts, tool definitions, and
behavioral rules precisely enough that a second implementation could be built
from it alone.

---

## 1. Extension identity

| Field | Value |
|---|---|
| Name | `pi-constitution` |
| Version | `1.0.0` |
| Schema | `pi.extension.v1` |
| Entry point | `pi-constitution.ts` |
| Factory type | `ExtensionFactory = (pi: ExtensionAPI) => void \| Promise<void>` |
| Lifecycle hooks | `session_start`, `tool_call` |
| Custom tools | `pi-constitution-doctor` |

---

## 2. ExtensionAPI surface used

Only the documented Pi `ExtensionAPI` (release 1.6.1) is used. No private or
removed APIs.

| API member | Kind | Use |
|---|---|---|
| `pi.on("session_start", handler)` | event | Audit Constitution binding at session start |
| `pi.on("tool_call", handler)` | event | Peer-gate Constitution-relevant bash commands |
| `pi.registerTool(def)` | registration | Register `pi-constitution-doctor` |
| `pi.exec(cmd, args, opts)` | execution | Run `test -d`, `git rev-parse`, `cat` |
| `pi.sendMessage(msg)` | messaging | Emit audit + triage custom messages to transcript |
| `ctx.cwd` | property | Current working directory (string, not a function) |
| `ctx.ui.confirm(title, message, opts)` | UI | Peer-gate confirmation dialog |
| `ctx.ui.setStatus(key, text)` | UI | Shame-compatible status line |

### Not used (deliberately)

- `pi.cwd()` — does not exist; `ctx.cwd` is the string property
- `pi.status`, `pi.triageError`, `pi.ask`, `pi.reply`, `pi.on("custom_tool")` —
  not part of the ExtensionAPI; replaced by `ctx.ui.*` + `pi.sendMessage` +
  `pi.registerTool`
- Custom tool names containing `:` — providers reject them; use dashes only

---

## 3. Types

### 3.1 Triase codes

```ts
type ConstitutionTriageCode =
  | "constitution_submodule_missing"
  | "constitution_governance_file_missing"
  | "constitution_mandate_section_missing"
  | "constitution_pointer_stale"
```

### 3.2 Collaboration packets

```ts
interface ConstitutionCollabQuestion {
  schema: "pi-constitution.collab_question.v1"
  question_id: string                          // e.g. "constitution-1795649681982"
  triage: {
    code: ConstitutionTriageCode
    layer: "extension"
    cause: string                              // human-readable cause
  }
  question: string                             // rendered to user
  required_response_schema: "pi-constitution.collab_answer.v1"
  allowed_answers: ["SUFFICIENT", "NEEDS_FIX"]
}

interface ConstitutionCollabAnswer {
  schema: "pi-constitution.collab_answer.v1"
  question_id: string                          // must match question.question_id
  answer: "SUFFICIENT" | "NEEDS_FIX"
  reason: string                               // user's justification
}
```

**Validation rules:**
- `answer.question_id` must equal `question.question_id`
- `answer.answer` must be one of `question.allowed_answers`
- `answer.schema` must equal `question.required_response_schema`
- A valid answer with a wrong `question_id` or widened `allowed_answers` is invalid data, not dissent

### 3.3 Audit result

```ts
interface GovernanceFileInfo {
  present: boolean
  path: string
}

interface MandateSectionInfo {
  present: boolean
  foundIn: string[]   // file names where the section was found
}

interface AuditResult {
  submodulePresent: boolean
  submoduleHead: string | null        // full SHA
  governanceFiles: Record<string, GovernanceFileInfo>
  mandateSections: Record<string, MandateSectionInfo>
  verified: string[]                   // human-readable passing checks
  errors: {
    code: ConstitutionTriageCode
    message: string
  }[]
}
```

### 3.4 Custom tool: `pi-constitution-doctor`

```ts
const DoctorParams = Type.Object({
  detail: Type.Optional(Type.Boolean())
})
type DoctorParams = Static<typeof DoctorParams>

// Tool definition (TypeBox schema + execute)
registerTool({
  name: "pi-constitution-doctor"
  label: "Constitution Doctor"
  description: "Full Constitution governance audit"
  parameters: DoctorParams
  execute: (toolCallId, params, signal, onUpdate, ctx) => AgentToolResult
})
```

**Result shape:**
```ts
{
  isError: boolean,                          // true when errors.length > 0
  content: [{ type: "text", text: string }], // formatted audit report
  structuredContent: {
    plugin: string
    version: string
    submodulePresent: boolean
    submoduleHead: string | null
    errorCount: number
    verifiedCount: number
    errors: AuditResult["errors"]
    governanceFiles: AuditResult["governanceFiles"]
    mandateSections: AuditResult["mandateSections"]
    verified: AuditResult["verified"]
  }
}
```

---

## 4. Event contracts

### 4.1 `session_start`

**Input:** `SessionStartEvent = { type: "session_start", reason: "startup" \| "reload" \| "new" \| "resume" \| "fork" }`

**Context:** `ExtensionContext` with `cwd: string`, `ui: ExtensionUIContext`

**Side effects:**
1. `ctx.ui.setStatus("constitution", <status-text>)` — shame-compatible status
2. `pi.sendMessage({ customType: "pi-constitution.audit", content, display: true, details })`
3. `pi.sendMessage({ customType: "pi-constitution.triage", content, display: true, details })` per error

**Status text:**
- Healthy: `"Constitution bound (<short-sha>)"`
- Unhealthy: `"Constitution: <N> issue(s)"`

### 4.2 `tool_call` (bash)

**Input:** `BashToolCallEvent` narrowed via `isToolCallEventType("bash", event)`

**Interception condition:** `command` string contains any of:
- `submodules/constitution`
- `Constitution.md`
- `CLAUDE.md`
- `AGENTS.md`
- `pi-constitution`

**Guard logic:**
1. `test -d <cwd>/submodules/constitution`
2. If absent → `ctx.ui.confirm("Constitution submodule missing", ...)` with `blockedKind: "permission"`
3. If user declines → return `{ block: true, reason: "..." }`
4. If user accepts or submodule present → return `undefined` (allow)

---

## 5. Behavior specification

### 5.1 session_start flow

```
START
  │
  ▼
cPath = ctx.cwd + "/submodules/constitution"
  │
  ▼
test -d cPath ──NO──► record constitution_submodule_missing ──► RETURN (partial audit)
  │ YES
  ▼
git -C cPath rev-parse HEAD ──► record submoduleHead
  │
  ▼
for each file in [Constitution.md, CLAUDE.md, AGENTS.md]:
  cat file ──FAIL──► record constitution_governance_file_missing
  └─SUCCESS──► scan for mandate sections [§11.4.26, §11.4.28, §11.4.31, §11.4.32]
                 ──MISSING──► record constitution_mandate_section_missing
  │
  ▼
ctx.ui.setStatus("constitution", <healthy\|unhealthy>)
pi.sendMessage(audit)
pi.sendMessage(triage) per error
END
```

### 5.2 tool_call guard flow

```
START
  │
  ▼
isToolCallEventType("bash", event)? ──NO──► RETURN (undefined)
  │ YES
  ▼
command matches constitution patterns? ──NO──► RETURN (undefined)
  │ YES
  ▼
test -d submodules/constitution ──YES──► RETURN (undefined)
  │ NO
  ▼
ctx.ui.confirm(...) ──accept──► RETURN (undefined)
          │
          ▼ decline
    RETURN { block: true, reason }
END
```

---

## 6. Error handling & triage codes

| Code | When raised | Message template | Next command |
|---|---|---|---|
| `constitution_submodule_missing` | `test -d submodules/constitution` fails | "Constitution submodule not found at {path}. Run: git submodule update --init submodules/constitution" | `pi-constitution-doctor` |
| `constitution_governance_file_missing` | `cat <file>` fails in submodule | "Governance file missing: {path}" | `pi-constitution-doctor` |
| `constitution_mandate_section_missing` | Section not found in any governance file | "Mandate section {section} not found in any governance file" | `pi-constitution-doctor` |
| `constitution_pointer_stale` | (reserved) submodule HEAD != parent pointer | "Constitution submodule pointer is stale; bump to upstream tip" | `git submodule update --remote submodules/constitution` |

All errors are reported as `pi-constitution.triage` custom messages with `details.code`, `details.layer: "extension"`, `details.cause`, and `details.nextCommand`.

---

## 7. Security & trust boundary

- **No code execution at install** — the extension is a single TypeScript file; Pi loads it as an extension, not as executable project code
- **No secrets in manifests** — `plugin.json` contains only name, version, description, paths
- **No network access** — all operations are local filesystem + git commands
- **Fail-open on tool errors** — if `pi.exec` throws, the extension catches and continues (never blocks unrelated Pi operation)
- **Peer gating cannot be silently bypassed** — `ctx.ui.confirm` is blocking; the tool result is `block: true` unless the user explicitly confirms

---

## 8. Performance characteristics

| Operation | Cost | Frequency |
|---|---|---|
| `test -d submodules/constitution` | ~1ms | Every session start |
| `git rev-parse HEAD` | ~5ms | Every session start |
| `cat` ×3 governance files | ~10ms | Every session start |
| Section scan (4 sections × 3 files) | ~1ms | Every session start |
| Total session_start overhead | ~20ms | Every session start |

---

## 9. Compliance with best-practices-pi-extension

| Rule | Status | How satisfied |
|---|---|---|
| Typed boundary first | ✅ | TypeBox schemas for doctor params; typed collab question/answer interfaces |
| Shame-compatible status | ✅ | `ctx.ui.setStatus` from validated `AuditResult`; `verified[]` list; local proof in transcript |
| Peer-gated bidirectional | ✅ | `collab_question.v1` / `collab_answer.v1` with `question_id` + `allowed_answers` validation |
| Owner bridge for terminal discovery | N/A | No terminal discovery needed |
| Route failures through triage-error | ✅ | Deterministic catalog codes; `next_command` in every triage message |
| Retained eval before done | ✅ | `pi-constitution-doctor` is a real, runnable verification path; adversarial case = missing submodule |
