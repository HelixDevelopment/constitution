# README badge provenance

Every badge in the top-of-file row of `README.md` is computed, never
typed (§11.4.259(C)). The computer is `scripts/badges/compute_badges.sh`;
run it with `--print` for the row, `--facts` for the inputs, `--check` to
assert the README row equals the computed row, and `--selftest` for the
golden-good / golden-bad / negative-control self-validation
(§11.4.107(10)).

Colour vocabulary is the closed set of §11.4.259(A): green, amber, red
(gray is reserved for a class that does not apply). A source that cannot
be read makes the computer exit 2 (BLIND) and print no row — a missing
source is never rendered as a green badge.

Each section heading below is the badge's alt text, and its `Source:`
line names where the value and colour come from. The gate
`CM-BADGE-MACHINE-DERIVED-SOURCE` cross-checks this file against the row.

## Version
Source: scripts/badges/compute_badges.sh (first `## ` heading of CHANGELOG.md; amber while it is `Unreleased`, green once it is a `helixconstitution-vNN` release heading)

## Anchors
Source: scripts/badges/compute_badges.sh (count of `- id:` rows in constitution_index.yaml; red unless the index's recorded source SHA-256 equals the SHA-256 of Constitution.md)

## Groups
Source: scripts/badges/compute_badges.sh (count of `- name:` rows in constitution_index.yaml; red when zero)

## Gates
Source: scripts/badges/compute_badges.sh (`cm_*.sh` files in scripts/gates excluding `*_mutation_test.sh` and `*_selftest.sh`; paired means a `*_mutation_test.sh` or `*_selftest.sh` sibling exists; green when every gate is paired, amber up to 10 percent unpaired, red beyond)

## Mutation
Source: scripts/badges/compute_badges.sh (count of `*_mutation_test.sh` files in scripts/gates; red when fewer than the number of paired gates)

## Progressive
Source: scripts/badges/compute_badges.sh (`anchor_count` in progressive/catalog.json; red unless the catalog's recorded source SHA-256 equals the SHA-256 of Constitution.md)

## Submodules
Source: scripts/badges/compute_badges.sh (`path =` entries in .gitmodules against mode 160000 entries in `git ls-files -s`; red when they differ)

## Twins
Source: scripts/badges/compute_badges.sh (for Constitution, CLAUDE, AGENTS, QWEN, GEMINI, README and CHANGELOG: stale when the `.md` was last committed after its `.html` / `.pdf` / `.docx` sibling; amber while the Constitution.md header declares the twins stale or pending, red otherwise)

## Readiness
Source: scripts/badges/compute_badges.sh (composite per §11.4.259(D): green only when every other badge is green, amber when any is amber and none red, red when any is red)
