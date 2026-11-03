#!/usr/bin/env bash
# shellcheck disable=SC2034  # T_NAME, OUT and RC are shared with lib.sh
# test_cli.sh — CLI surface of scripts/constitution_ext/constitution_ext.sh: help, usage errors,
# exit codes, validate/list/info on fixture inputs, root and project resolution, --json, --dry-run.
# Real engine, real files in a mktemp sandbox; nothing touches $HOME or this repository.
T_NAME=cli
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
new_sandbox
R="$SB/croot"; P="$SB/proj"; make_root "$R"; make_project "$P"

eng --help; eq "--help exits 0" 0 "$RC"; has "--help lists add" "add <source>" "$OUT"; has "--help lists exit codes" "Exit codes" "$OUT"
eng; eq "no command is usage error (2)" 2 "$RC"
eng frobnicate; eq "unknown command is usage error (2)" 2 "$RC"
eng --root "$R" --project-root "$P" list --bogus; eq "unknown flag is usage error (2)" 2 "$RC"
eng --root "$R" --project-root "$P" info; eq "info without id is usage error (2)" 2 "$RC"
eng --root "$SB/nowhere" --project-root "$P" list; eq "missing root is precondition (3)" 3 "$RC"

eng validate "$FIX/hello-fixture"; eq "validate good fixture" 0 "$RC"; has "validate says OK" "OK" "$OUT"
eng validate "$FIX/hooks-fixture"; eq "validate hooks fixture" 0 "$RC"
mkdir -p "$SB/bad"; printf 'schema_version: "1.0"\nextension:\n  id: Bad_ID\n' >"$SB/bad/extension.yml"
eng validate "$SB/bad"; eq "validate bad manifest exits 1" 1 "$RC"; has "names the bad id" "extension.id" "$OUT"
eng validate "$SB/none"; eq "validate missing dir exits 1" 1 "$RC"

engj --root "$R" --project-root "$P" --json list; eq "list --json ok" 0 "$RC"; eq "empty list" "[]" "$(jget "$OUT" extensions)"
copy_fixture hello-fixture "$R/extensions/hello-fixture"
engj --root "$R" --project-root "$P" --json list; eq "bundled ext listed" "hello-fixture" "$(jget "$OUT" extensions.0.id)"
eq "bundled origin" "bundled" "$(jget "$OUT" extensions.0.origin)"; eq "bundled not enabled" "false" "$(jget "$OUT" extensions.0.enabled)"
engj --root "$R" --project-root "$P" --json info hello-fixture; eq "info ok" 0 "$RC"; eq "info version" "1.0.0" "$(jget "$OUT" version)"
eng --root "$R" --project-root "$P" info no-such; eq "info unknown id exits 1" 1 "$RC"
eng --root "$R" --project-root "$P" info '../etc'; eq "info hostile id is usage (2)" 2 "$RC"

# root auto-resolution: engine copied into a root at both layouts, run with no --root
for layout in constitution submodules/constitution; do
  P2="$SB/auto_${layout//\//_}"; make_project "$P2"; C="$P2/$layout"; mkdir -p "$C"
  cp -R "$R/." "$C/"; mkdir -p "$C/scripts/constitution_ext" "$C/scripts/lib"
  cp "$REPO"/scripts/constitution_ext/*.sh "$REPO"/scripts/constitution_ext/*.py "$C/scripts/constitution_ext/" 2>/dev/null
  cp "$REPO/scripts/lib/safe_rm.sh" "$REPO/scripts/lib/protected_paths.list" "$C/scripts/lib/" 2>/dev/null
  OUT="$(cd "$P2" && bash "$C/scripts/constitution_ext/constitution_ext.sh" --json list 2>/dev/null)"; RC=$?
  eq "auto root at $layout" 0 "$RC"; eq "auto root sees bundled at $layout" "hello-fixture" "$(jget "$OUT" extensions.0.id 2>/dev/null)"
  OUT="$(cd "$P2" && bash "$C/scripts/constitution_ext/constitution_ext.sh" --json doctor 2>/dev/null)"
  eq "doctor reports layout $layout" "$layout" "$(jget "$OUT" layout 2>/dev/null)"
done

# --dry-run writes nothing
before="$(tree_fp "$P")$(tree_fp "$R")"
eng --root "$R" --project-root "$P" --dry-run enable hello-fixture --yes; eq "dry-run enable ok" 0 "$RC"; has "dry-run says so" "dry-run" "$OUT"
eq "dry-run wrote nothing" "$before" "$(tree_fp "$P")$(tree_fp "$R")"
finish
