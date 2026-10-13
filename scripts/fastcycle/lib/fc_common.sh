#!/bin/bash
# fc_common.sh - shell helpers for spec-004 fastcycle tools (source me).
# Purpose: fc_body_hash PATH prints the canonical body_hash of a result doc (recomputed, excludes run_meta).
# Inputs: PATH to a fastcycle JSON doc. Outputs: hash on stdout; nonzero on unreadable doc.
# Dependencies: python3, fc_common.py alongside. Cross-ref: contracts/common-conventions.md C-002.
FC_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE:-$0}")" && pwd)"
fc_body_hash() {
  python3 "$FC_LIB_DIR/fc_common.py" body-hash --doc "$1"
}
