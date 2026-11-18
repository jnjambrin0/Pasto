#!/bin/bash
# Runs the unit tests of the local packages (pure logic only; see docs/DEVELOPMENT.md).
# Extra arguments go to `swift test`, e.g. scripts/test.sh --filter StackModelTests
set -euo pipefail
cd "$(dirname "$0")/.."

status=0
for package in Packages/PastoKit; do
  log="$(mktemp)"
  if swift test --package-path "$package" "$@" >"$log" 2>&1; then
    grep -E "Test run with" "$log" | sed -E "s/^[^T]*/  /" || true
    echo "TESTS OK ($package)"
  else
    grep -E "error: |✘|failed|Fatal" "$log" | sed -E 's/\x1b\[[0-9;]*m//g' | cut -c1-300 | head -40 || true
    echo "TESTS FAILED ($package) — full log: $log"
    status=1
  fi
done
exit $status
