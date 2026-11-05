#!/bin/bash
# Purpose : sourced helper for SpecKit-004 fastcycle tests that exercise CONSUMER-project data
#           (tracker DB, specs/, config/, device/ trees) which does not exist in the canon repository.
#           fc_require_consumer <path-under-consumer-root>...  exits 77 (honest SKIP, section 11.4.3 /
#           11.4.69 topology_unsupported) when any path is absent, naming each; never a PASS.
# Consumer root = the directory four levels above the calling test (parent of the canon checkout).
fc_require_consumer() {
  local root missing="" p
  root=$(cd "$(dirname "${BASH_SOURCE[1]}")/../../../.." && pwd) || { echo "SKIP consumer_root_unresolvable"; exit 77; }
  for p in "$@"; do [ -e "$root/$p" ] || missing="$missing $p"; done
  if [ -n "$missing" ]; then
    echo "SKIP topology_unsupported: consumer-project files absent under $root:$missing (test targets a consumer layout, not canon alone)"
    exit 77
  fi
}
