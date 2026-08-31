# ADR 0003 — Reward distribution: cumulative multi-token Merkle

- **Status:** Accepted (2026-08-30); implementation Phase 7
- **Context:** Push-to-all-holders is unscalable and can deliver regulated Stock Tokens to ineligible recipients. Simple per-epoch airdrops allow double/replay bugs.
- **Decision:**
  - Cumulative per-wallet, per-asset entitlements in Merkle leaves; claims pay `cumulative - claimed`.
  - Domain-separated leaves (chain / distributor / epoch) — non-replayable.
  - Roots: challenge delay, cancellable before activation, never reduce entitlements, never exceed vault funding.
  - Eligibility registry re-checked at claim time (signed, scoped, expiring, revocable).
  - Self-claim + optional non-redirecting relayer path.
  - Deterministic dust rule; no admin-redirected dust.
- **Consequences:** Indexer must be reorg-safe and snapshot at finalized blocks; manifest validation is a hard gate before root proposal. D010, D017.