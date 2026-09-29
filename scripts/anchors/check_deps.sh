#!/usr/bin/env bash
set -euo pipefail
if ! python3 -c 'import yaml' 2>/dev/null; then
  echo "FATAL: PyYAML not importable. Install with: pip3 install --user PyYAML" >&2
  echo "See: specs/003-reorganize-constitution-yaml/contracts/generator-cli.md G-005" >&2
  exit 4
fi
echo "PyYAML OK: $(python3 -c 'import yaml; print(yaml.__version__)')"
