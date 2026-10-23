#!/usr/bin/env bash
# Fixture probe stub: endpoint unreachable (mutation sandboxes — llmctl/endpoints absent).
echo "jev-probe-fail: endpoint '$1' unreachable in this sandbox" >&2
exit 1
