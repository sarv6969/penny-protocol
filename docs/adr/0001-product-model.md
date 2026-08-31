# ADR 0001 — Product model: INDEX-style rewards token

- **Status:** Accepted (2026-08-30)
- **Context:** A redeemable basket vault for Robinhood Stock Tokens is legally explosive, operationally heavy (mint/burn with AUM accounting), and misleads on ownership semantics. A rewards-token model keeps `PENNY` a plain ERC-20.
- **Decision:** `PENNY` is a fixed-supply token trading in a dedicated PENNY/WETH v4 pool. A 3% WETH protocol fee funds purchases of the five founding Stock Tokens at equal weight. Eligible holders earn cumulative pro-rata entitlements through signed Merkle epochs. `PENNY` is not backed by, redeemable for, or ownership of the basket.
- **Consequences:** No redemption vault. Reward rail carries all product value. UI/docs language is strictly controlled ("Stock Token rewards", "economic exposure"). D001–D004, D010, D011.