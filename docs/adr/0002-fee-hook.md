# ADR 0002 — PennyFeeHook design (Uniswap v4, custom accounting)

- **Status:** Accepted (2026-08-30); implementation Phase 5
- **Context:** Need exactly 300 bps of the traded side fee in WETH in both directions, collated into FeeCollector, with full router/delta correctness.
- **Decision:**
  - Attach only to the configured PENNY/WETH PoolKey; any other PoolKey reverts.
  - **Exact-input swaps only** in v1; exact-output rejected with a clear error until a separately audited semantics module exists.
  - WETH-in buy: 3% of specified WETH in diverted to FeeCollector; 97% into the swap. PENNY-in sell: 3% of actual WETH output deducted; user gets 97%.
  - Follow Uniswap official custom-accounting patterns (IDelta/`_accountDelta`), settle deltas correctly on both currency orderings; assert exact WETH balances before/after in integration tests.
  - Immutable 300 bps fee. No settable fee above 300 bps.
  - Pause may stop fee-sweep/purchases; **fail-open for swaps** (pauses never trap trading).
- **Consequences:** If the standard Universal Router cannot route this exact-input flow, build the narrowest audited-style custom router and document it. D007, D014.