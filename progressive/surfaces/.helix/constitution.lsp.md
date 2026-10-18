---
name: helix-constitution-lsp
language: markdown
root: constitution/
index:
  - glob: progressive/rules/*.md
    symbol: "^#{2,6}\\s+(§[0-9.]+)"
    kind: anchor
  - glob: progressive/catalog.json
    symbol: "$.anchors[*].id"
    kind: catalog-entry
capabilities:
  hover: "Return the anchor's one_line_description from catalog.json"
  goto-definition: "Open progressive/rules/<id>.md at line 1"
  references: "Every occurrence of the anchor id in Constitution.md and the twins"
  workspace-symbol: "Every anchor in catalog.json"
---

# Helix Constitution LSP frontmatter

One symbol per anchor, declared by the heading regex above, hover text from the
catalog. No LSP code is shipped; other tooling reads this declaration.
