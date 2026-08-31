#!/usr/bin/env bash
# Export deploy artifacts for the launch bundle: ABI + bytecode/deployedBytecode + creation
# salts for the Penny Stocks core contracts, one JSON per contract in artifacts/, plus a
# checksums manifest. Requires forge-build output (packages/contracts/out).
# Contracts shipped: PennyToken, BasketBuyer, PennyFeeHook, PennyFeeHookFactory, FeeCollector,
# RewardVault, RewardDistributor, EligibilityRegistry, RebalanceController, TeamVesting,
# StockTokenVerifier. (Deployment Salt/script lives in src/DeployPennyFeeHook.s.sol.)
set -euo pipefail

export PATH="${HOME}/.foundry/bin:${PATH}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${ROOT}/packages/contracts/out"
ART="${ROOT}/artifacts"

mkdir -p "${ART}"
cd "${ROOT}/packages/contracts"
forge build --sizes >/dev/null 2>&1 || forge build >/dev/null

CORE=(PennyToken BasketBuyer PennyFeeHook PennyFeeHookFactory FeeCollector RewardVault)
CORE+=(RewardDistributor EligibilityRegistry RebalanceController TeamVesting StockTokenVerifier)

for c in "${CORE[@]}"; do
  src="${OUT}/${c}.sol/${c}.json"
  [ -f "${src}" ] || { echo "missing ${src}"; exit 1; }
  node -e '
    const path=require("path");
    const o=require(path.resolve(process.argv[1]));
    const m = typeof o.metadata === "string" ? JSON.parse(o.metadata) : (o.metadata || {});
    const out={
      contract: process.argv[2],
      abi: o.abi,
      bytecode: o.bytecode && o.bytecode.object,
      deployedBytecode: o.deployedBytecode && o.deployedBytecode.object,
      compiler: m.compiler,
      generatedAt: new Date().toISOString(),
    };
    process.stdout.write(JSON.stringify(out,null,2)+"\n");
  ' "${src}" "${c}" > "${ART}/${c}.json"
done

(cd "${ART}" && shasum -a 256 ./*.json) > "${ART}/SHA256SUMS"
echo "[artifacts] exported ${#CORE[@]} contracts -> ${ART}"
echo "[artifacts] checksums -> ${ART}/SHA256SUMS"
cat "${ART}/SHA256SUMS"