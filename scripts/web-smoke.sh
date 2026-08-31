#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WEB="$ROOT/apps/web"
OUT="$WEB/out"

echo "==> build web (static export)"
pnpm --filter web build

echo "==> assert landing (index) and status pages exported with expected copy"
if [[ ! -f "$OUT/index.html" ]]; then
  echo "FAIL: $OUT/index.html not found"
  exit 1
fi

if ! grep -q "Penny Protocol" "$OUT/index.html"; then
  echo "FAIL: out/index.html does not contain 'Penny Protocol'"
  exit 1
fi

if ! grep -q "not redeemable" "$OUT/index.html"; then
  echo "FAIL: landing is missing the non-redeemable disclosure"
  exit 1
fi

if [[ ! -f "$OUT/status.html" ]] || ! grep -q "Penny Stocks" "$OUT/status.html"; then
  echo "FAIL: status page missing or lost its content"
  exit 1
fi

echo "==> export-check (pkg test)"
pnpm --filter web test

echo "web-smoke OK"
