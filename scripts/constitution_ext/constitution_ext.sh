#!/usr/bin/env bash
# constitution_ext.sh — the constitution EXTENSION ENGINE (install, verify and wire extensions).
#
# ── Purpose (§11.4.18) ────────────────────────────────────────────────────
# Manages extensions of the Helix Constitution: bundled ones shipped in <root>/extensions/<id>/ and
# user-installed ones in <root>/extensions/_installed/<id>/ (kept out of git through the
# constitution checkout's info/exclude, so a submodule stays clean). State for a consumer project
# lives in <project>/.constitution/: extensions.lock.yml (tracked: id, version, source, git sha,
# content sha256, enabled, consent, waiver), extensions.wiring.yml (shims this engine created),
# extensions.catalog.json (imported catalog), extensions.audit.log, and the LOCAL git-ignored
# extensions.state/ (HMAC-signed copy of each lock entry; verify cross-checks it). Manifest = <ext>/extension.yml,
# a strict YAML subset (see ext_yaml.py) with the schema of docs/design/constitution_extensions_plan.md §3.2.
#
# ── Usage ─────────────────────────────────────────────────────────────────
#   constitution_ext.sh [--root DIR] [--project-root DIR] [--json] [--dry-run] <command> [args]
#     validate <dir>                      check a manifest + tree; prints the content sha256
#     list                                bundled + installed extensions and their lock state
#     info <id>                           manifest summary, capabilities, lock entry, wiring
#     add <source> [--sha SHA] [--sha256 H] [--dev] [--waiver-id ID] [--yes]
#                                         install from a local dir (pin: --sha256) or a git URL/repo
#                                         (pin: --sha 40-hex AND --sha256, as printed by validate);
#                                         unpinned needs --waiver-id (recorded; refused if token-shaped)
#     remove <id> [--yes]                 unwire and delete an installed extension (never a bundled one)
#     enable <id> [--yes]                 record consent; mark enabled (hooks/MCP enabled in the lock)
#     disable <id>                        unwire its commands; mark disabled
#     verify [<id>]                       recompute CHECKSUMS, compare to the lock, catalog revocations,
#                                         consented capabilities and wired shims
#     lock                                write/refresh the lock (bundled hashes only; never launders
#                                         a changed installed tree; an enabled bundled extension whose
#                                         consent list changed is not refreshed: exit 3, run enable <id>)
#     doctor                              environment, layout, exclude, lock, journal, wiring, per-extension verify
#     catalog <file> [--replace]          validate and import a JSON catalog; revocations of the previous
#                                         catalog are kept unless --replace (which warns); an unreadable
#                                         previous catalog refuses the import unless --replace
#                                         {schema_version, catalog{id,install_allowed,trust_tier},
#                                          revoked[{id,version,reason}], extensions{id:{releases{ver:{url,sha256,git_sha}}}}}
#     wire [<id>] --agent A [--target DIR]    A = claude|opencode|gemini|qwen|pi|all; materialise
#                                         commands/<name>/SKILL.md as: claude .claude/skills/<name>
#                                         (symlink), opencode .opencode/commands/<name>.md, gemini/qwen
#                                         .gemini|.qwen/commands/<name>.toml, pi .pi/prompts/<name>.md
#     unwire [<id>] --agent A [--target DIR]  remove only shims this engine recorded and that are unchanged
#   wire --target must resolve inside the project; an invalid wiring-file entry makes every command
#   that would act on shims refuse (exit 5) without touching anything. Wiring entries and Claude link
#   texts are project-relative, so a committed wiring file works in a clone. An entry is acted on only
#   when it is in this checkout's signed wiring record (extensions.state/wiring.json) or its file carries
#   the engine's managed-by marker; otherwise wire/unwire/remove/disable refuse (exit 5). wire refuses a
#   revoked extension (exit 3) and one whose capabilities changed since consent (exit 5).
#   Agent-side constructs in any file under commands/<name>/ or a skill file (!{...}, !`...`,
#   allowed-tools/hooks front matter, @{...}, @path) must be declared under capabilities.agent_shell /
#   capabilities.reads_files, or add/enable/wire refuse; such files must be UTF-8 and their front matter
#   exact (no BOM/CR, exact --- lines, plain keys). MCP launch commands (manifest and *.json MCP file)
#   must be a bare program or a path inside the extension with plain-token arguments; a shell or
#   inline interpreter code needs capabilities.shell. The consent list (always printed on stderr, also
#   with --json) shows the trust tier, the waiver id, the MCP argv, env var names and the sha256 of every
#   bound file (hooks, MCP files, executables, shell/file-injecting command directories); any change
#   to it needs a new enable. --project-root must not be the constitution root.
#   --root defaults to: $CONSTITUTION_DIR (when it holds a Constitution.md), then the place this engine
#   itself lives (<root>/scripts/constitution_ext next to a Constitution.md). The cwd is never searched
#   (R23); otherwise the command refuses and asks for --root DIR.
#   --project-root defaults to the git superproject of the root, else the cwd's git toplevel.
#
# ── Exit codes ────────────────────────────────────────────────────────────
#   0 ok · 1 failure · 2 usage · 3 precondition / refused by policy · 5 verification failed
#
# ── Safety ────────────────────────────────────────────────────────────────
#   * No code from an extension is executed, ever (copy only; git runs with a scrubbed environment,
#     no system/global config, hooksPath=/dev/null, symlinks off, filters/attributes neutralised).
#   * Source URLs: https/ssh/file/git@ only; no '::' helpers, no credentials in the URL.
#   * .git anywhere in a tree, bare repositories, hard links and >2000 directories are refused.
#   * One exclusive lock per command; journals are validated before any recovery acts on them.
#   * Paths contained; symlinks, special files and setuid bits refused; size/count/depth limits.
#   * Pins enforced; consent recorded; hooks and MCP disabled until `enable`.
#   * No secrets: manifests with secret-shaped values are refused and values are never printed.
#   * Install is staged + journaled + atomic (rename) with rollback on the next run after a crash.
#   * Recursive deletes only through scripts/lib/safe_rm.sh safe_rm_rf (refused if missing).
#   * Interactive consent reads /dev/tty only; CONSTITUTION_EXT_NO_TTY=1 forbids the prompt.
#   * Test hooks (CONSTITUTION_EXT_TEST_MODE/_KILL_AT, CONSTITUTION_EXT_CONSTITUTION_VERSION) are inert
#     unless CONSTITUTION_EXT_TEST_NONCE matches <parent of project>/.constitution-ext-test-nonce
#     (0600); outside such a sandbox the version override is refused with exit 3.
#
# Requires: bash, python3 >= 3.8 (stdlib only), git (for git sources and exclude handling).
set -uo pipefail

_ce_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" || { echo "constitution_ext: cannot resolve own directory" >&2; exit 1; }
_ce_py="$(command -v python3 2>/dev/null || true)"
if [ -z "$_ce_py" ]; then
  echo "constitution_ext: python3 is required (stdlib only)" >&2
  exit 3
fi
if ! "$_ce_py" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' 2>/dev/null; then
  echo "constitution_ext: python3 >= 3.8 is required" >&2
  exit 3
fi
CONSTITUTION_EXT_USAGE="$(sed -n '/^# ── Usage/,/^# Requires:/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//')"
export CONSTITUTION_EXT_USAGE
exec "$_ce_py" -I "$_ce_dir/ext_engine.py" "$@"
