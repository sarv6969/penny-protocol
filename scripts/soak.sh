# Accelerated soak harness for fork/local runs.
# Requires: docker (postgres), ARCHIVE_RPC_URL for mainnet fork, and forge.
# Usage: ./scripts/soak.sh
set -euo pipefail

FORGE="${HOME}/.foundry/bin/forge"
RPC_URL="${ARCHIVE_RPC_URL:-http://127.0.0.1:8545}"

echo "[soak] generating anvil mainnet fork at ${RPC_URL}"
"${FORGE}" test --match-path "test/fork/**" -vv

echo "[soak] volumes/sessions/fees/purchase/claims covered by contracts tests"
make contracts-test

echo "[soak] ok (bounded; extend for real accelerated 48h soak before mainnet)"