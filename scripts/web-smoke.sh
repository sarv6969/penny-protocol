#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WEB="$ROOT/apps/web"
OUT="$WEB/out"

echo "==> build web (static export)"
pnpm --filter web build

echo "==> assert out/index.html exists and contains 'Penny Stocks'"
if [[ ! -f "$OUT/index.html" ]]; then
  echo "FAIL: $OUT/index.html not found"
  exit 1
fi

if ! grep -q "Penny Stocks" "$OUT/index.html"; then
  echo "FAIL: out/index.html does not contain 'Penny Stocks'"
  exit 1
fi

echo "==> export-check (pkg test)"
pnpm --filter web test

echo "web-smoke OK"
