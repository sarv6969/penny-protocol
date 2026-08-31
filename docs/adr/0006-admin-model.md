# ADR 0006 — Admin model: Safe + timelock + LP lock

- **Status:** Accepted (2026-08-30); governance Phase 4-7, LP lock Phase 6
- **Context:** Concentrated admin power is a top threat. Reward rail and basket are regulated-touching.
- **Decision:**
  - Safe multisig + OpenZeppelin `TimelockController` (or equivalent) for mutable governance.
  - Role split: emergency pause · root proposal · root cancel-before-activation · compliance attestation · adapter management · quarterly rebalance.
  - Red lines (immutable): no fee >3%, no mint, no admin withdrawal of WETH fees / reward reserves, no silent pool replacement, no non-100% weights, no redirect of rewards.
  - Friendly recovery ONLY for accidental, unrelated token deposits, timelocked.
  - Initial v4 LP position is **irreversibly locked** after the explicit launch action; exact semantics documented before locking; irreversible action never executed in this build.
- **Consequences:** Timelock delay must exceed keeper/swap cadence so governance can't front-run the reward rail; emergency pause role is faster and cannot seize. D011–D016.