# Tutorial 07 - Install, enable, wire and verify an extension

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-10-29 |
| Last modified | 2026-10-29T20:00:00Z |
| Status | draft |
| Status summary | Engine (E1) implemented with its own tests; experimental, dormant, not independently GO'd (rounds 10 and 11 fixes landed, round 11 fixes pending independent re-review). `/constitution extensions ...` delegates to it (`constitution_cmd.sh`; `install-extension` maps to `add`); installer and post-update-hook wiring of extensions is UNCONFIRMED; shim formats other than Claude are UNCONFIRMED against live agents. Written 2026-10-29 from `constitution_ext.sh --help` and `scripts/constitution_ext/README.md`. |
| Authority | Tool documentation for `scripts/constitution_ext/`; design in `docs/design/constitution_extensions_plan.md`. §11.4.228, §11.4.272, §11.4.18, §11.4.257, §11.4.212 govern. |
| Scope | Step-by-step with the extension engine, using a throwaway local extension. |
| Issues | none |

Work in a scratch project. Paths use the standard layout.

1. Set the engine path and create a minimal extension (see the engine README for the manifest schema; run `validate` and fix what it reports).

```bash
E=submodules/constitution/scripts/constitution_ext/constitution_ext.sh
bash $E validate ./hello_ext          # prints the content sha256; note it
```

2. Dry-run, then install with the pin.

```bash
bash $E --dry-run add ./hello_ext --sha256 <printed hash>
bash $E add ./hello_ext --sha256 <printed hash>      # consent prompt on /dev/tty
```

3. Enable and wire for one agent, then verify.

```bash
bash $E enable hello_ext
bash $E wire hello_ext --agent claude
bash $E verify; echo "exit=$?"        # 0 means clean
bash $E doctor
```

4. Undo.

```bash
bash $E unwire hello_ext --agent all
bash $E disable hello_ext
bash $E remove hello_ext --yes
```

Fresh clone? `verify` exits 5 until you `enable <id> --yes` again; that is by design. See [guide](../guides/extensions_guide.md), [lifecycle](../diagrams/extension_lifecycle.md).
