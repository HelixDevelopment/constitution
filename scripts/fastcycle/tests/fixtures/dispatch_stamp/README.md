# fixtures/dispatch_stamp/ — T036 self-validation fixtures

Fixture convention for `constitution/scripts/fastcycle/tokens/dispatch_stamp.sh`
(§11.4.107(10) self-validation: golden-good / golden-bad / negative-control).

Each case directory holds:

| File               | Content                                                                                                   |
|---------------------|-------------------------------------------------------------------------------------------------------------------|
| `input`             | The raw stdin JSON payload (the Claude Code PreToolUse hook invocation shape), byte-for-byte as it would arrive on stdin. Matches the `input`/`expected` naming already used by the sibling `fixtures/build_deploy_qa/` set. |
| `expected`          | The expected **GUARD mode** (default invocation, no CLI flag) exit code — `0` or `2` — on its own line.           |
| `expected_extract`  | The expected **EXTRACTION mode** (`--extract-item-id`) stdout — the bare `ATM-nnnn` token, the literal `?`, or **empty** (0 bytes, no trailing newline) when `item=` is genuinely absent. This file is deliberately a *separate* file from `expected` because this tool has two independent behaviours (a blocking guard decision and a non-blocking extraction) driven by the SAME input — one `expected` file could not hold both without an ad-hoc multi-field format. |

## Cases

- **`golden-good/`** — a well-formed `Agent` dispatch carrying `item=ATM-1041`
  alongside a real §11.4.182 label → GUARD mode `exit 0`; EXTRACTION mode
  prints `ATM-1041`.
- **`golden-bad/`** — the identical shape (`Task` dispatch, real §11.4.182
  label) but with the `item=` token missing entirely → GUARD mode `exit 2`
  (stderr names the fix); EXTRACTION mode prints nothing (empty).
- **`negative-control/`** — a `Bash` tool_name (never gated) with no `item=`
  anywhere → GUARD mode `exit 0`, proving the guard does not over-fire on
  tools it was never meant to gate. (This case exercises GUARD mode only;
  EXTRACTION mode is tool_name-agnostic by design — see dispatch_stamp.sh's
  own header — so its `expected_extract` is empty here simply because the
  fixture's description field itself never contains `item=`, not because of
  any tool_name check in extraction mode.)

## Running a case by hand

```bash
TOOL="$REPO_ROOT/constitution/scripts/fastcycle/tokens/dispatch_stamp.sh"
CASE="$REPO_ROOT/constitution/scripts/fastcycle/tests/fixtures/dispatch_stamp/golden-good"

# GUARD mode
cat "$CASE/input" | bash "$TOOL"; echo "exit=$?"        # compare against $CASE/expected

# EXTRACTION mode
cat "$CASE/input" | bash "$TOOL" --extract-item-id       # compare against $CASE/expected_extract
```
