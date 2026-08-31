# Status

_Updated: 2026-08-31 (post adversarial review — see DECISIONS.md R1–R9, D031–D032)_

## Phase-by-phase progress

| Phase | Name | Status |
|---|---|---|
| 1 | Verify official sources + generate manifest | **DONE** (blockers below) |
| 1a | Onchain verification of manifest addresses at pinned block (eth_getCode, symbol, decimals, uiMultiplier, oraclePaused, status) | **DONE** via public RPC at block 49902198 — manifest `verified-onchain` (chainlink entries remain blocked) |
| 2 | Docs: architecture, trust model, ADRs, threat model, economics, compliance boundary | **DONE** (living docs) |
| 3 | Monorepo scaffold + CI + Makefile + .env.example | **DONE** — clean install/build/typecheck/test green |
| 4 | Token, allocation, vesting, governance + tests | **DONE** (token/allocator/vesting). Governance timelock start; RebalanceController next |
| 4b | RebalanceController + StockTokenVerifier + mocks + tests | **DONE** — 12/12 tests green (founding-5 @ 2000 bps, ceiling 8, timelock, removals) |
| 5 | Uniswap v4 `PennyFeeHook` + local/fork swap tests | **DONE** — 6/6 tests green; CREATE2-mined hook (bits 7,6,3,2 = afterSwap/beforeSwap + return-delta); 300 bps WETH fee taken direct to `feeCollector` on every exact-in swap |
| 6 | FeeCollector, OracleGuard, BasketBuyer/adapters + mocks + tests | **DONE** — 15/15 tests green; hook-streamed WETH -> collector sweep -> 5-way equal-notional purchase -> reward vault; fail-closed oracle rail (session gate + per-feed liveness + zero-price), deterministic largest-remainder dust convergence, atomic all-or-nothing purchases |
| 7 | RewardVault, cumulative Merkle distributor, eligibility registry | **DONE** — 29/29 tests green; signed scoped eligibility attestations (100k PENNY threshold, soft-fail sig), vault custody + D013 protected-asset recovery, per-epoch Merkle roots with monotone cumulative leaves, admiralty-of-claim (leaf binds msg.sender), single-tx catch-up claims |
| 8 | Reorg-safe indexer, snapshots/tree/manifests, reconciliation | **DONE** — services/indexer built + 35/35 TS tests green (ingest, confirmation-depth finality, fork rollback, snapshot re-derivation, largest-remainder allocation, cumulative merge, deterministic manifests); Solidity↔JS lockstep `ManifestCrossCheck` 2/2 green against the committed golden fixture; docs D028–D029 |
| 9 | Idempotent keeper + purchase/epoch state machines + monitoring | **DONE** — `services/keeper` built + **24/24 TS tests green**: `@penny/keeper` cycle over basket-purchase → funding-reconcile → ingest → snapshot-request → tree-build → manifest-validate → root-propose → root-activate (+ monitoring); write-ahead intent with warm-start crash recovery incl. full process-restart durability on the `DurableStepStore` JSONL ledger (D030), funding watermark, onchain-publish dedup, `venueArmed` mainnet gate; tail shipped: per-step latency/cycle metrics + summary, `AttestationService` threshold-gated signed scoped claims (D012, no keys), `PostgresStepStore` behind the same `StepStore` interface (needs Docker to run) |
| 10 | Web app (Next.js) + e2e tests | **DONE** — `apps/web` static Next.js export green: protocol summary, epoch cards + per-wallet claim checklist, sample manifest at `/claim/[epoch]`, client lookup island, built from real `@penny/sdk` constants; `scripts/web-smoke.sh` asserts `out/index.html` |
| 11 | Static analysis, fuzz/invariants, coverage, secret/licence scan, soak | **DONE** — 4 new Foundry invariant suites (token supply, vault custody/burn-record, distributor monotone leaves + exact deltas, hook 300 bps WETH rail); coverage 89.87% lines (`coverage-summary.txt`); `.gas-snapshot`; `scripts/secret-scan.sh` Tier-1 PASS; licence inventory `docs/evidence/licences.md`; `scripts/soak-local.sh` accelerated battery green (60k fuzz + invariants + 3×flake replay); slither requires venv install — scripted, not run |
| 12 | Testnet artifacts, mainnet dry-run bundle, launch-readiness report | **DONE (bundle; gates remain)** — `artifacts/` (11 ABIs+bytecode+SHA256SUMS via `scripts/export-artifacts.sh`); `docs/launch-readiness.md` go/no-go sheet; genesis values pinned |

## Hard mainnet gates (all currently blocking)

1. `MAINNET_LEGAL_APPROVAL=false` hard stop — needs documented counsel signoff (legal, issuer/operator, eligible jurisdictions, marketing, restricted-person delivery mechanism).
2. Independent smart-contract audit + remediation.
3. Live executable quote/depth test for **all five** Stock Tokens at intended purchase size / max slippage (needs a confirmed production route on Robinhood Chain).
4. All `HUMAN_INPUT_REQUIRED` values supplied by humans (deployer, Safe signers, treasury, liquidity amounts, LP range, keeper caps, compliance attestor, launch timestamp).
5. 48-hour testnet/fork soak green (accelerated).

## Blockers / evidence

- **NO sequencer uptime feed documented for Robinhood Chain.** Robinhood docs recommend checking it but publish no proxy; Chainlink's L2 sequencer feed page does not list Robinhood Chain. OracleGuard must treat this as a configuration gap (fail closed until a staffed solution, e.g. monitored RPC/session policy, is approved). See `docs/evidence/`.
- **Five Stock Token addresses confirmed onchain** at pinned block 49902198 (bytecode, symbol, 18 decimals, `uiMultiplier==1e18`, `oraclePaused==false`) — manifest `verified-onchain`. Manual re-check + re-pin recommended during Phase 12 launch-readiness.
- **Production liquidity route unconfirmed.** Rialto / 0x RFQ / 1inch Fusion / LiFi are officially documented as available venues; none is verified executable for all five at target size. The Phase 6 test suite uses a clearly-labelled `MockAdapter` (1 WETH = 1 whole token at oracle parity); a verified adapter is a launch gate, otherwise `NO_GO_LIQUIDITY`.
- **Chainlink feed proxies for the five assets un-resolved** (decimals, heartbeat, proxies). Must be resolved from official Chainlink page + onchain, not hardcoded guesses. `OracleGuard` and `BasketBuyer` consume prices through the `IOracleSource` interface and a staffed market-session gate (D009); a config resolution registers the real `ChainlinkOracle` impl + feeds.
- **BasketBuyer/oracle rail is wired, but its mainnet execution route is unarmed** until real feed addresses are resolved and a venue adapter is verified. The `MockOracle`/`MockAdapter` are test-only and never compiled into production paths.

## What to run

```bash
make setup            # pnpm install + forge submodules
make contracts-test   # forge test
pnpm test             # all workspaces
pnpm typecheck        # TS
make db-up            # postgres for indexer (Phase 8)
```

## Adversarial review (2026-08-31)

A full second-pass review of the production contracts found 4 high-severity integration bugs
(masked by permissive mocks) and 5 medium/low hardening gaps; all are fixed and re-tested.
Highlights: RewardVault now PULLS custody with its record (was record-only — claims were
unpayable); the claimed ledger is keyed by token address (was index — corrupted on basket
expansion); root lifecycle now has an onchain challenge delay, cancellation, monotone
cumulative totals and vault-funding coverage (D032); BasketBuyer's slippage floor now prices
the WETH/USD leg (was ~2500x too low); attestations expire, revoke, and bind chainid+registry;
custody wiring is set-once (D031); partial-fill buys revert instead of overcharging the 3% fee.
Full list in `DECISIONS.md` (R1–R9).

## Product pivots (2026-08-31, D033–D034)

- **Rotating basket (D033):** `RebalanceController` now supports routine timelocked removals by
  `REBALANCE_ROLE` with a mandatory onchain reason, re-admission of previously removed stocks,
  and a hard floor of 5 / ceiling of 8 active constituents. Rotation only redirects future
  purchases; historical entitlements are address-keyed and immutable.
- **Auto-delivery (D034):** $INDEX-style UX — holders opt in once (onchain or by gasless
  signature) and Stock Token rewards are delivered automatically each epoch via permissionless
  `claimFor`/`claimForMany`. Rewards can only land in the entitled wallet; opt-in is revocable;
  non-opted-in wallets keep the self-claim path. Keeper `claim-relay` implemented,
  mainnet-gated behind `relayArmed`.

## Repo health

- Contracts: **99 tests passing** (95 unit/feature + 4 invariant suites; token supply, vault custody/burn-record, distributor monotone cumulative + exact deltas, hook 300bps WETH rail) — fuzz+runs up to 60k, coverage 89.6% lines, `.gas-snapshot`; custom-accounting delta mechanics verified against v4-core v4.0.0 source.
- Slither: run against `src/` (venv, slither-analyzer 0.11.6). No high findings; remaining mediums reviewed as intentional invariants (strict-equality full-spend checks, timestamp timelocks) — see review notes.
- Indexer: 35 tests passing (TypeScript, `tsx --test`, viem-based); golden manifest cross-verified against a live Solidity claim replay (updated for D032 publish API).
- Keeper: 24 tests passing (idempotency, progressive epochs, crash-recovery warm-start, unexplained-frontier fail-closed, funding-watermark monotonicity, ABI selector pins now on `publishEpoch(bytes32,address[],uint256[],bytes32)`, domain-separated scope binding, durable JSONL ledger restart/durability, attestation threshold/scope/no-keys flow).
- SDK: 4 tests passing (constants re-exported; `isFixedSupplyAmount`; ABI). Config manifest: 3 tests passing.
- JS typecheck/lint/build: green across all 7 workspaces incl. `apps/web` static export + smoke. Solidity fmt: clean.
- Secret scan (`scripts/secret-scan.sh`): Tier-1 PASS — no key material in committed source; untracked root `.env` is gitignored (rotate any real keys inside it). Licence scan: no copyleft (see `docs/evidence/licences.md`). gitleaks is additionally wired in CI (needs install on macOS).
- Artifacts: 11 contract images + SHA256SUMS regenerated post-review in `artifacts/`. Launch-readiness go/no-go: `docs/launch-readiness.md`.

## Next episode

Only hard human/infra gates remain (see `docs/launch-readiness.md`): legal approval, independent audit, verified live liquidity route + feed addresses + keeper key custody, 48h anchored soak and Postgres runtime (need docker + ARCHIVE_RPC_URL), and all `HUMAN_INPUT_REQUIRED` values. Optional code work if wanted: wire per-step latency/cycle metrics from `monitor.ts` into a real sink; live RPC/Postgres integration once Docker exists; real e2e via Playwright in CI.