# Deployment runbook

Local/testnet deterministic; mainnet is a **dry-run only** until every STATUS.md gate is green.

## Order of deployment

1. **Wallet/Safe prep.** Collect on paper the `HUMAN_INPUT_REQUIRED` set (deployer, Safe signers/threshold, treasury, initial ETH/WETH, pool tick/range, max slippage, min sweep USD, keeper gas caps, compliance attestor, launch timestamp). No defaults silently substituted for mainnet.
2. **Chain validation.** Verify chain ID + RPC provenance; resolve official manifests (Robinhood contracts, Uniswap v4, Chainlink feeds) and onchain-verify: `eth_getCode`, code hash, symbol, decimals, ERC-8056 methods (`uiMultiplier`, `oraclePaused`, active/status), feed correctness. Fail closed.
3. **Hook mining (v4).** Mine CREATE2 address so `getHookPermissions()` match the intended PoolKey flags; bind the exact PENNY/WETH PoolKey; prove flag equality in output.
4. **Core deploy.** Token → Allocator(+vesting, Safe) → Timelock/Safe → FeeCollector+OracleGuard → BasketBuyer(+adapters, whitelist) → RewardVault+Distributor+EligibilityRegistry.
5. **Pool init + LP.** `initialize` pool, add initial position, permanently lock (deferred until approval; irreversible step requires typed confirmation in a dry-run simulation).
6. **Governance handover.** Transfer roles, renounce deployer where appropriate. Print diff of every role, owner, fee, basket, oracle proxy, adapter, limit, token flow for signer verification.
7. **Wiring.** Indexer start block, keeper config, monitoring; simulate every tx; store artifacts + bytecode hashes; verify source on Blockscout (dry-run plan).

## Verification gates built into scripts

- `chainId` and RPC consensus assert.
- Manifest addresses must be `verified-onchain` (verification gate refuses `blocked`).
- Simulated txs with explicit typed confirmation for irreversible steps.
- `MAINNET_LEGAL_APPROVAL=false` hard stop enforced.

## Testnet/local

- Mock Stock Tokens + mock feeds labelled unmistakably (`MockTE`, etc.); never presented as canonical.
- See [STATUS.md](../STATUS.md) for the 48-hour soak scenario list (volume, fees, five-asset purchases, corporate-action pause, oracle outage, sequencer outage, reorg, keeper restart, root correction, self/relayed claims, reconciliation).