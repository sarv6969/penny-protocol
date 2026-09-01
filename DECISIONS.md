# Decisions

Dated decision log. Latest first. Evidence in `docs/evidence/` and `packages/config/src/generated/`.

## 2026-08-30

- **D001 — Build network: Robinhood Chain mainnet (4663).** Confirmed against docs.robinhood.com/chain/connecting/. Not Base. Rationale: five canonical Robinhood Stock Tokens + per-asset Chainlink feeds + ETH gas + live Uniswap v4 deployment. Evidence: `docs/evidence/01-robinhood-chain-verification.md`.
- **D002 — Launch model: NOT O1 Launchpad.** O1 launch pairs one new token with one Stock Token; does not build/custody a five-stock basket. Build our own Uniswap v4 pool + hook. Rationale in D002 ADR (0001).
- **D003 — Product: INDEX-style rewards token, not redeemable vault.** `PENNY` is fixed-supply, not basket-backed, not redeemable. Stock Tokens are separate pro-rata rewards. ADR 0001.
- **D004 — Locked economics:** 1B supply / 18 decimals / no post-constructor mint / no transfer tax / no blacklist / 3% (300 bps) WETH-only protocol fee on exact-input swaps in both directions / 100% of net fees buy the five Stock Tokens / 90-5-5 launch split / 12-month team vest / 100k `PENNY` eligibility threshold.
- **D005 — Solidity 0.8.26, evm_version `cancun`.** Cancun required for v4 transient storage later; fine for Phase 4 contracts now.
- **D006 — Pinned deps:** forge-std v1.16.2 (commit `bf647bd`), OpenZeppelin v5.4.0 (commit `c64a1ed`). pnpm 11.24.0, turbo 2.10.12, TS 5.9.3.
- **D007 — Fee session type:** fees collected in WETH through the hook, not PENNY. Never market a >3% all-in trading cost as "3%".
- **D008 — Chainlink price already includes `uiMultiplier()`. Do not multiply again.** Confirmed by Robinhood docs.
- **D009 — Sequencer uptime policy:** NO official Robinhood Chain L2 sequencer feed proxy exists (blocked). OracleGuard design must incorporate a staffed market-session/oracle-liveness policy and fail closed until an approved mechanism exists. Do not ship a hardcoded Arbitrum feed address.
- **D010 — Reward delivery model:** cumulative multi-token Merkle roots + signed scoped eligibility attestation at claim time. No push-to-all-holders. Admiralty of claim = entitled wallet, never relayers.
- **D011 — Launch basket weight & governance protections:** five founding constituents, 2,000 bps each, total exactly 10,000 bps, no removals below five except documented emergencies, expansion by timelocked admission only, no basket reweighting of historical entitlements.
- **D012 — `MAX_CONSTITUENTS` and batched expansion:** set an explicit gas-tested cap in an ADR (0008); support many-to-one and multi-transaction claims if basket grows beyond atomic limits.
- **D013 — Tokens with protected status:** WETH owed to purchases, `PENNY`, and current/historical reward assets are NEVER admin-recoverable. Only unrelated accidental deposits may be timelocked-recovered.
- **D014 — Escape hatches:** pause may stop fee sweeping and root activation; it must never trap `PENNY` transfers or seize user assets.
- **D015 — Deploy register:** all addresses served from the generated verified manifest, never scattered constants (see D016).
- **D016 — Manifest source of truth:** `packages/config/src/generated/mainnet.verified.json`, generated with schema v1.0.0, source URLs, verification status. Blocked entries cannot pass the verification gate (test-enforced).
- **D017 — Fee USD notional equality:** purchases target equal USD notional via current Chainlink token prices; deterministic leftover/dust handling must converge toward equal weights. ADR 0008.
- **D020 — Uniswap v4 pinned at `v4-core` v4.0.0 (commit `e50237c`).** v4.0.0 hook invocation is decided by address bits (no `getHookPermissions` call); deltas must be squared within the lock (`NonzeroDeltaCount`/`CurrencyNotSettled` otherwise). The fee hook returns `BeforeSwapDelta` on buy (shrink LP leg by 3% of WETH input) and an `afterSwap` unspecified delta on sell (3% of WETH out), and `take`s each fee to `feeCollector` inside `afterSwap` so its delta nets zero and the trader still settles the full amount.
- **D021 — Fee runs direct to `FeeCollector`, no hook-side escrow.** Each exact-in swap pays the 3% WETH fee instantly to `feeCollector` (transaction-level atomicity); the keeper merely sweeps WETH from `FeeCollector` to `BasketBuyer` above the min-USD threshold. No hook accumulation, no permissioned drip.
- **D022 — CREATE2 hook address is canonical and must be re-derived, never reused.** `PennyFeeHookFactory` mines low 14 bits to exactly `0xC4` (bits 7/6/3/2 = beforeSwap/afterSwap/+return-delta). Any change to constructor args or code changes the address; the deploy script re-derives it on each `forge script` run.
- **D023 — Basket rail is hook-stream, collector tank, buyer, vault.** `PennyFeeHook` `take`s fee WETH directly into `FeeCollector`; only `sweep()` moves it (to `BasketBuyer`, above `minSweepAmount`, pause only halts sweeps — D014); `BasketBuyer` spends the full balance via one `ILiquidityAdapter`; the adapter delivers token to the buyer which forwards through `IRewardVault.receiveRewardAsset` (single deterministic accounting point).
- **D024 — Equal-notional purchases with deterministic largest-remainder dust convergence (ADR 0008).** Allocation = `amount × weightBps / 10_000` floored, then the residual principal is handed one wei each to the largest fractional residues (ties→lower index). Every whole wei above a fee is spent; dust converges to zero. WETH/5 is NOT used directly — weights come from `RebalanceController.weights()` so the rule survives future rebalancing.
- **D025 — Oracle rail is fail-closed and un-armed on mainnet.** Prices flow through `IOracleSource` behind `OracleGuard`: staffed market-session gate (D009, `MARKET_APPROVER_ROLE`), per-feed liveness, zero-price rejection — any failure aborts the whole purchase atomically. `ChainlinkOracle` impl + the five feed proxies remain an unresolved launch gate; tests use clearly-labelled `MockOracle`. `RebalanceController` implements `IRebalanceWeights` so the buyer binds to the governance roll.
- **D026 — Cumulative multi-asset Merkle rewards, delta-paid exactly-once.** Each epoch commits `root(keccak(abi.encode(wallet, uint256[] cumulative)))` over the epoch's reward tokens in canonical ascending order. Because leaves are genesis-total, the pay delta is `cumulative[i] - claimedAggregate[wallet][i]` (single running total, not per-epoch), so roots never expire, claims are exactly-once, and a wallet may catch up on every unclaimed epoch in one transaction (`claimAll`, D012). Admiralty is structural: the leaf binds `msg.sender`, so relayers cannot claim for others.
- **D027 — Eligibility = signed scoped attestation; scope binds signature to one epoch root.** The signing service attests ≥100k PENNY holding and signs `keccak(abi.encodePacked(wallet, scope))` where `scope = keccak("PENNY_REWARD_ELIGIBILITY", epochIndex, root)`; replay against another root is impossible. Signature verification is soft-fail (`ECDSA.tryRecover` → invalid sigs are `false`, never a revert). `requireLiveBalance` (an owner maintenance flag, default off) optionally re-checks the live 100k PENNY balance at claim time so holders who later sell are never locked out (D004/D010).
- **D028 — Reorg-safe indexer with live fork rollback, snapshots only at confirmed blocks.** Nothing above `tip - confirmationDepth` (default 12, per-chain config) is ever treated as final; the moment a stored block hash disagrees with the canonical chain, the whole subtree from that height is rolled back atomically and replayed. Balances are never read from stored state — they are always re-derived from Transfer logs up to the snapshot block, so a rollback is free to reconcile. Protocol addresses (allocator/vesting/safes) are excluded from eligibility with rationale captured in the manifest.
- **D029 — Deterministic, bit-reproducible manifest pipeline.** Eligibility, largest-remainder allocation (exact in wei; residual < #wallets is awarded as +1 wei to the largest fractional residue, ties to the lower address, so the residual is zero and recorded for transparency), cumulative merge, and Merkle build use canonical key ordering; `contentHash = keccak256(canonicalJSON(payload))` excludes transient `meta.generatedAt` so two clean builds on identical inputs are byte-identical. A committed golden manifest is re-verified onchain in Solidity tests (`ManifestCrossCheck`): the JS-recomputed root equals the Solidity `merkle.rootOf`, OpenZeppelin proofs verify, and a full claim replays the manifest deltas exactly.
- **D030 — Exactly-once epoch publish via write-ahead intent + warm-start crash recovery.** `root-propose` writes a durable `ProposeIntent` (root, epochIndex, snapshotBlock, contentHash, per-token fundedTotals, and the full `nextCursor` it WOULD persist — cumulative map, residuals, funding watermark) to the step ledger BEFORE any publish transaction. `root-activate` publishes only after the intent is durable, reads the onchain root at the target index first (already-activated root ⇒ absorb without a second tx; foreign root at a stale index ⇒ hard stop), and writes the cursor + SUCCEEDED record. Funding is windowed above a monotonic `fundedUpToBlock` watermark so a deposit lumped into a published epoch can never be lumped again. Crash semantics divide cleanly: (1) crash before publish — no intent ⇒ same inputs re-run, one identical epoch publishes; (2) crash between tx and ledger write — intent + onchain root match ⇒ keeper synthesizes the missing activation record and adopts the intent's `nextCursor` (cumulative included), so the published sequence is never re-derived and claims stay consistent; (3) epoch published with every ledger record lost — `tree-build` sees frontier > cursor with no covering intent and FAILS CLOSED (operator recovery) rather than double-fund. Monitor/reconcile jobs stay read-only; the keeper holds no signing keys. Reference ledger is `DurableStepStore` — an fsync'd append-only JSONL (tombstone deletions) replayed on start, so a process-kill leaves the intent and cursor intact and warm-start works across restarts; the planned Postgres store implements the same `StepStore` interface.

## 2026-08-31 — adversarial code review (post-Phase-12)

A full adversarial review of every production contract found and fixed the following. All 99
contract tests + all TS suites green after the fixes; slither re-run clean of new mediums.

- **R1 (HIGH, fixed) — RewardVault ingress never moved custody.** `receiveRewardAsset` only wrote
  `lifetimeDeposits`; purchased Stock Tokens sat in `BasketBuyer` where the vault could never pay
  claims from them. Fixed: the vault now PULLS custody via `safeTransferFrom` in the same call
  that extends the record (record can never exceed custody); `BasketBuyer` grants a per-purchase
  exact allowance. Mocks updated to the same semantics so tests can no longer mask the gap.
- **R2 (HIGH, fixed) — claimed ledger keyed by token INDEX, not address.** `claimed[wallet][i]`
  corrupted accounting the moment an epoch's token list changed (expansion re-indexes). Fixed:
  `claimed[wallet][tokenAddress]`.
- **R3 (HIGH, fixed) — missing challenge delay / root cancellation / funding checks.** The spec
  requires a configurable activation delay, cancellation of unactivated roots, cumulative-total
  monotonicity, and vault-funding coverage enforced onchain. Added (D032): `publishEpoch` now
  takes `cumulativeTotals` + `manifestHash`, enforces `total >= committedTotals[token]` and
  `total <= vault.lifetimeDeposits(token)`; epochs activate after `challengeDelay`;
  `ROOT_CANCEL_ROLE` can cancel only not-yet-active epochs; cancelled epochs are skipped in catch-up.
- **R4 (HIGH, fixed) — BasketBuyer minTokenOut assumed WETH = 1 USD.** `expected = spend/price`
  ignored the WETH/USD leg, so the slippage floor was ~2500x too low at real prices (venue could
  under-deliver massively within "slippage"). Fixed: `minOut = spend × wethUsd × slip / tokenUsd`.
- **R5 (MEDIUM, fixed) — attestations were not expiring, not revocable, replayable across
  chains/deployments.** `messageHash` now binds wallet, scope, expiry, `block.chainid` and the
  registry address; `revoked[wallet]` blocks future claims (never completed ones); the epoch
  scope also binds chainid + distributor. Keeper `scopeOf`/`AttestationService` updated to match.
- **R6 (MEDIUM, fixed) — owner could redirect custody flows.** `PennyFeeHook.setFeeCollector`,
  `FeeCollector.setBasketBuyer`, `RewardVault.setRewardSource/setDistributor`, and
  `BasketBuyer.setRewardVault` are now set-once latches (D031). `BasketBuyer.setAdapter` revokes
  the previous venue's allowance and grants only per-purchase exact allowances (no standing
  unlimited approval to a swappable adapter).
- **R7 (MEDIUM, fixed) — buy-path fee overcharge on partial fills.** A price-limited exact-in buy
  used to charge 3% of the SPECIFIED input even when the pool consumed less. v1 semantics now
  reject partial-fill buys (`PartialFillUnsupported`) so the effective fee can never exceed 300
  bps of executed notional (ADR 0003 note).
- **R8 (LOW, fixed) — OracleGuard session never expired.** A staffed `marketOpen=true` flag could
  hold the rail open through market closure. Sessions now auto-expire after `sessionTtl`
  (default 8h, hard cap 24h).
- **R9 (LOW, fixed) — raw `transfer` return-value checks.** FeeCollector/RewardVault/BasketBuyer
  now use SafeERC20 everywhere; `lastClaimed` in single-epoch `claim` is monotone (no rewind);
  `claimAll` guards the empty-epochs underflow; claim paths carry `nonReentrant`; state writes
  precede vault redeems (CEI).

- **D031 — Custody wiring is set-once.** Fee stream (hook→collector→buyer) and reward custody
  (buyer→vault→distributor) destinations latch on first set. Redirection after launch is
  impossible even for owners; a bad wire requires redeploying the affected module before launch.
- **D032 — Root lifecycle: propose → challenge window → active; onchain funding commitment.**
  Every root carries per-token cumulative totals checked onchain against monotonicity and vault
  `lifetimeDeposits`. Cancellation only before activation; completed claims are never clawed
  back. The keeper publishes totals derived from the manifest (`runRootActivate`).

## 2026-08-31 — product pivots (rotation + auto-delivery)

- **D033 — ROTATING basket (revises D011).** Product decision by the owner: the basket actively
  adds AND removes constituents rather than expand-only. Mechanics: `REBALANCE_ROLE` proposes
  additions and removals through the same timelock; every removal (routine or emergency)
  requires a published onchain reason (emitted in `RemovalProposed`); previously removed stocks
  may be re-admitted after passing the canonical screen again; the basket can never rotate
  below `MIN_CONSTITUENTS = 5` or above `MAX_CONSTITUENTS = 8`. Unchanged and load-bearing:
  rotation only redirects FUTURE fee purchases — historical purchases, entitlements, and claims
  are token-address-keyed (R2 fix) and are never restated; removed-token rewards remain
  claimable forever (D013). Compliance note: active rotation discretion strengthens the case
  for investment-company/adviser analysis — flagged explicitly for the counsel gate (D019).
- **D034 — $INDEX-style auto-delivery (opt-in, permissionless relay).** Holders do not claim;
  rewards ARRIVE. A wallet opts in once — `setAutoDelivery(true)` onchain, or gaslessly via
  `setAutoDeliveryBySig` (nonce-sequenced, chain+registry domain-bound, collected in the same
  session as the eligibility attestation, revocable anytime). `RewardDistributor.claimFor` /
  `claimForMany(epochIndex, Delivery[])` are PERMISSIONLESS: anyone may relay (the keeper is
  just the default operator), because safety is structural — the Merkle leaf binds the entitled
  wallet so rewards cannot be redirected, the opt-in and a live scoped attestation gate every
  delivery, and a failing batch entry is skipped (isolated via self-call), never fatal. Blind
  push to non-opted-in wallets remains impossible: the opt-in + attestation ARE the
  counsel-required eligibility mechanism, so the airdrop UX never becomes an unsolicited
  transfer of restricted Stock Tokens. Keeper `claim-relay` job is implemented and
  mainnet-gated behind `relayArmed` (same gate family as D009/D025).

## 2026-09-01 — founding basket replaced (D035)

- **D035 — Founding basket is now AUR / JOBY / SOUN / SMR / CLOV (revises the D011 launch
  list).** Owner decision pre-launch (nothing was ever deployed against the old list, so this
  is a config change, not a rotation event). New screen: low price band, real daily dollar
  volume, tight spreads, ACTIVE not halted, one-per-sector frontier diversity — autonomous
  trucking (AUR), electric air taxis (JOBY), voice AI (SOUN), small modular reactors (SMR),
  AI health insurance (CLOV). All five canonical Robinhood Stock Tokens verified onchain at
  pinned block **51123566** (bytecode 283B proxies, symbol match, 18 decimals,
  `uiMultiplier()==1e18`, `oraclePaused()==false`, name `'{Company} • Robinhood Token'`).
  Chainlink per-stock feed proxies remain BLOCKED (resolve before arming, as before). Old
  TE/POET/NNE/WYFI/RCAT entries retired from the manifest. Contracts unchanged — the basket
  list is constructor/config input, which is exactly why it lives in the manifest.

## 2026-09-01 — production oracle + venue rail (D036–D037)

- **D036 — ChainlinkOracle is live-verified.** Official Robinhood equity feed proxies resolved
  from Chainlink's reference directory and read onchain (block 51175803): IONQ/RGTI/RKLB/CLSK/
  USAR + ETH/USD, all 8-dec, 24h heartbeat, 0.5% deviation. `ChainlinkOracle` (IOracleSource)
  normalizes 8→18 dec, fails closed on staleness (4d stock bound spans weekends; 26h ETH),
  unfinished rounds, feed reverts, and ERC-8056 `oraclePaused()`. Fork test reads REAL values
  (ETH $2,473.44 / USAR $17.875) and executes the full rail. TRV pricing confirmed: feed bakes
  in uiMultiplier — never multiply twice (D008).
- **D037 — Venue rail = keeper-staged routes through whitelisted routers; trap pools measured
  and excluded.** Exhaustive v4 scan (9,407 pools / 2.4M blocks): our five tokens have ONLY
  90–99% fee trap pools + two mispriced pools (+25%/+142% vs oracle). Real Stock Token flow is
  RFQ/propAMM per Robinhood docs. LiFi Diamond (verified official, 0xB477…4Af3) routes via
  'nordstern' propAMM with executable quotes: USAR −0.23%, RKLB −8%, RGTI mispriced, IONQ/CLSK
  unrouted. `RouteAdapter`: keeper stages (router, calldata, deadline) per token per cycle —
  whitelisted routers only, one-shot routes, exact allowance granted+revoked, balance-delta
  measured output, oracle-derived minOut enforced, unconsumed WETH returned. A bad route can
  only revert, never steal. Uniswap remains a first-class route when a sane pool exists.
  CANARY: founding count parametrized (3–8, immutable at construction); $PONEY canary = 3
  routable stocks (USAR/RKLB/RGTI), production PENNY stays 5. Fork rehearsal green: 3-leg
  equal-notional purchase ($24.73/leg), atomic rollback on missing route.

## Blocker-adjacent decisions (may be revisited)

- **D018 — AI-assisted build is in progress but is NOT an audit.** Reports from tooling do not replace the external audit gate. "Audited" wording is never used in docs/UI until a named audit report is linked.
- **D019 — This project is not legal advice.** Final jurisdiction list, delivery mechanism, and the 3%-fee reward model all wait on counsel (gate 1). See `docs/compliance-boundaries.md`.