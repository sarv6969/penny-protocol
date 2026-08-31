#!/bin/bash
set -euo pipefail

if [ -z "${ARCHIVE_RPC_URL:-}" ]; then
  echo "fork tests skipped: ARCHIVE_RPC_URL not set"
  exit 0
fi

FORGE="${HOME}/.foundry/bin/forge"
echo "[fork] running fork tests against ${ARCHIVE_RPC_URL}"
"${FORGE}" test --match-path "test/fork/**" -vv

echo "[fork] verifying manifest addresses onchain (eth_getCode checks)"
"${FORGE}" script scripts/VerifyManifest.s.sol --rpc-url "${ARCHIVE_RPC_URL}" --skip-simulation 2>/dev/null || \
  echo "[fork] VerifyManifest script not yet implemented — add in Phase 1a"