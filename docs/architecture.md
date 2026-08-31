# Architecture

Penny Stocks v1 — Robinhood Chain mainnet (4663). One v4 pool, one hook, one cumulative reward rail.

## Goals

- `PENNY` is a boring fixed-supply ERC-20. All product value is delivered through the reward rail.
- No ~15-minute claimable-yield fake machine: rewards are discrete funded epochs, gas-aware, published as signed Merkle roots.
- No mechanism can push Stock Tokens to arbitrary holders; receipt requires a live, scoped, revocable eligibility attestation.
- Everything spendable is on a tight leash: immutable fee, whitelisted adapters, oracle sanity bands, deadlines, min-outputs, atomic multi-asset purchase cycles.

## Components

```
                    ┌────────────────────────────────────────────┐
   Trader ──PENNY/WETH exact-input──►  Uniswap v4 Pool + PennyFeeHook
                    │                      │  3% WETH on both directions
                    │                      ▼
                    │              FeeCollector (WETH custody, hook-only ingress)
                    │                      │
                    │                      ▼
                    │         BasketBuyer (adapter-whitelisted, OracleGuard-gated)
                    │                      │  atomic five-asset equal-USD purchase
                    │                      ▼
                    │               RewardVault (Stock Tokens, no admin sweep)
                    │                      │
                    │                      ▼
                    │   cumulative MerkleDistributor ──► eligible holders (self-claim)
                    │   eligibility registry (signed/scoped/revocable attestations)
                    │
                    └── gov: Safe multisig + TimelockController + role split
```

## Data & control flow

1. **Swap:** hook charges 300 bps of WETH input (buy, exact-in) or takes 3% of WETH out (sell, exact-in), settles deltas via the pool manager and forwards WETH to `FeeCollector`.
2. **Keeper sweep:** idempotent job, min-USD threshold, reeled by `PennyFeeHook`/collector accounting. Sweeps WETH to `BasketBuyer`.
3. **Basket cycle:** `BasketBuyer` iterates the active basket; for each constituent executes a whitelisted adapter swap of equal USD notional; `OracleGuard` gates price age/session/sequencer-liveness/oraclePaused and cross-checks quotes vs oracle within sanity bands; all-or-nothing for the five-asset basket.
4. **Epoch:** purchased tokens transferred to `RewardVault`; totals recorded per asset.
5. **Snapshot:** indexer computes eligible balances at a finalized block, excludes burned/zero and protocol addresses, requires eligibility attestations.
6. **Tree + manifest:** deterministic cumulative Merkle tree (domain-separated per chain/distributor/epoch) + IPFS-pinned manifest; validated against vault funding; proposed through a challenge delay, then activated.
7. **Claim:** user (or opted-in relayer, non-redirecting) proves cumulative entitlement; distributor pays `cumulative - claimed`; eligibility re-checked at claim time.

## Compliance rail

Eligibility registry sits between reward accounting and the actual transfer of Stock Tokens. Claims are only for wallets with a live signed attestation scoped to (chain, contract, wallet), expiring, non-replayable, revocable. Jurisdiction policy is a signed/versioned config, not a hardcoded list, and never a client-side-only control.

## Non-goals

- No `PENNY` basket backing / redemption / ownership semantics.
- No admin-seizable user balances; no freeze of `PENNY` transfers (pause affects reward ops only).
- No self-acting "every 15 minutes" distribution; epochs are event-driven by funded fees and safe snapshots.

## Deployment order (local/testnet; mainnet gated)

1. PennyToken → 2. Allocator + vesting + Safe allocations → 3. Timelock/Safe roles → 4. FeeCollector+OracleGuard → 5. BasketBuyer(adapters) → 6. RewardVault+Distributor+registry → 7. Hook CREATE2 mining & PoolKey bind → 8. Pool init + LP + permanent lock (irreversible, deferred) → 9. governance handover → 10. keepers/indexer wiring. Full scripted & diffed, irreversible steps require explicit typed confirmation.

See ADRs (docs/adr/) for the bounded decisions behind each component.