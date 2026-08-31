#!/usr/bin/env bash
# Local accelerated soak — bounded fuzz/invariant battery that needs NO docker/anvil/fork.
# Evidence this repo can absorb sustained random load; the real 48h anchored mainnet soak
# (scripts/soak.sh) remains a launch gate requiring infra (docker + ARCHIVE_RPC_URL).
set -euo pipefail

export PATH="${HOME}/.foundry/bin:${PATH}"
cd "$(dirname "${BASH_SOURCE[0]}")/../packages/contracts"

echo "[soak-local] extended fuzz runs over all contracts (60k fuzz-runs)..."
forge test --fuzz-runs 60000 -vvv

echo "[soak-local] invariant suites (512 runs x 128 depth per the foundry profile)..."
forge test --match-contract Invariant

echo "[soak-local] repeated full replay x3 for flake detection..."
for i in 1 2 3; do
  forge test --match-contract PennyToken --fuzz-runs 40000 >/dev/null 2>&1 || { echo "flake on pass ${i}"; exit 1; }
done
echo "[soak-local] ok — bounded accelerated battery green"