# ADR 0008 — Basket expansion: MAX_CONSTITUENTS and equal-weight economics

- **Status:** Accepted (2026-08-30); enforced in RebalanceController (Phase 4) and BasketBuyer (Phase 6)
- **Context:** The basket should grow beyond five while preserving founding stocks, equal weighting, and atomic safety. Arbitrary expansion without a cap breaks gas budgets and equal-USD math.
- **Decision:**
  - Five founding constituents at 2,000 bps each; weights must always total exactly 10,000 bps; unique, nonzero, canonical (verified) addresses.
  - Future purchases reweight **equal** across all active constituents; each addition requires the strict penny-stock screen (share price <$5, mcap <$1B at the reviewed snapshot, distinct sector), working official Chainlink feed, executable liquidity, legal clearance, public report, Safe approval, timelock.
  - Historical purchases/distributions/entitlements/claims never change.
  - No removal below five founding constituents except documented emergency (availability/oracle/liquidity/legal).
  - Explicit, gas-tested `MAX_CONSTITUENTS` (target 8 discoverably) in `packages/config`; if an expansion would exceed atomic limits, the deterministic batched purchase + multi-transaction claim design kicks in without changing pro-rata economics.
  - Equal-USD targeting uses current Chainlink token prices; deficits/dust handled deterministically so rounding converges toward equal weights (never exact-price, always tracked).
- **Consequences:** RebalanceController tests must prove: 5 unique founding addresses preserved, additions unique + verified, future weights total 10,000 bps, history untouched. D008, D011, D017.