# ADR 0004 — BasketBuyer / liquidity adapter interface

- **Status:** Accepted (2026-08-30); implementation Phase 6
- **Context:** Stock Tokens have documented liquidity via 0x RFQ, 1inch Fusion, LiFi, Uniswap AMM, and Rialto propAMM. A generic "any call" execution surface from a funded contract is the #1 privilege-escalation bug class.
- **Decision:**
  - `BasketBuyer` spends WETH only toward currently active, governance-approved Stock Tokens.
  - Narrow `ILiquidityAdapter` interface. Whitelist: adapters, routers, input token, output tokens, selectors. No arbitrary calls.
  - Enforce deadline, max WETH in, min Stock Token out, balance-delta checks, oracle sanity bands, reentrancy lock, atomic rollback.
  - Launch: all five purchases succeed or the whole cycle reverts (no four-stock epoch). Expansion: deterministic batched state machine that never finalizes a partial cycle.
  - At least one verified executable adapter on a production route required per constituent before mainnet; otherwise `NO_GO_LIQUIDITY`.
- **Consequences:** Adapter review is part of every audit; new adapters require Safe + timelock. D017.