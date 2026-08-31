# Threat model

Threats against the protocol, the reward rail, and the frontend. Mitigations inline; gaps tracked in STATUS.md.

## Class A — hook / pool integrity

- **Delta mishandling (int128 bounds, currency ordering, signed deltas).** Mitigation: official-pattern custom-accounting hook, exact-input only, before/after WETH balance assertions on both directions in integration tests, `getHookPermissions()` flag proof, PoolKey whitelist, reject exact-output.
- **Only the configured pool may invoke economic behavior.** Any other PoolKey reverts.
- **Malicious / malformed callback reentrancy.** NonReentrant on fee settlement paths; no external calls before state finalization; pool manager is trusted (official deployment).
- **Fee-on-transfer / refund-token assumptions.** WETH in/out asserted by balance deltas, not `amountIn/amountOut` trust.
- **Sandwich / MEV on 3% fee.** Fee not preventable by routing around the pool; documented as acceptable given fee rate + pool size; keeper uses minAmountOut + deadline + best quote.

## Class B — oracle manipulation / staleness

- Stale/bad-round/negative/zero answers, heartbeat exceeded, session (24/5) last-value semantics.
- `oraclePaused()` on Stock Token → purchases halted.
- Pending `newUIMultiplier()/effectiveAt()` corporate-action windows → fail closed.
- Sequencer outage / grace period → purchases halted as configured (see D009: no official feed proxy; staffed session/liveness policy required).
- Feed already includes `uiMultiplier()` → never multiply twice.
- Quote vs oracle divergence beyond sanity band → reject.

## Class C — route / liquidity

- Illiquid or malicious adapter/router swapping into bad prices or honeypots.
- Broad adapter surface abused. Mitigation: narrow interface, whitelisted adapters/routers/tokens/selectors, no arbitrary calls from funded contracts, deadline/min-out/oracle-band, atomic all-or-nothing basket cycle. No production route for a token → `NO_GO_LIQUIDITY`, never invent one.

## Class D — keeper / ops

- Keeper compromise: least-privilege keys, secure signer/KMS, replay/duplicate protection via cycle IDs + DB constraints + nonce management, reimbursement strictly capped by actual gas & configured limits.
- RPC disagreement / provider failover / reorgs → confirmation tracking, reconcile-and-halt on mismatch.

## Class E — governance

- Safe / timelock compromise → cannot exceed red lines (fee >3%, mint, withdraw fees/rewards, redirect rewards, non-100% weights, silent pool swap); roles split; root can be cancelled only before activation; claims never clawed back.
- Legit root replaced by malicious root → challenge delay, deterministic manifest validation vs vault funding, cumulative semantics prevent decrease.

## Class F — reward/accounting

- Double claim / replay across chain-contract-epoch → domain-separated leaves + cumulative `cumulative-claimed`.
- Insolvency: root cumulative totals exceed vault funding → onchain caps + manifest cross-check, reconcile before propose.
- Rounding/dust directional theft → documented deterministic dust rule; no admin redirecting dust.

## Class G — compliance delivery

- Stock Tokens delivered to restricted persons → eligibility attestation at claim, versioned jurisdiction policy, no push distribution. Residual risk acknowledged; counsel decides the mechanism.
- Issuer/counterparty risk (RHJ) → protocol controls nothing on issuer side; disclosed.

## Class H — infra / web

- Frontend/domain compromise → content security headers, no secrets client-side, wallet signing only what UI displays, addresses from verified manifest; geoblock is supplementary only.
- Dependency/redeployment risk → pinned versions, reproducible builds, bytecode comparison, dependency/licence/secret scans in CI.
- LP lock mistakes → irreversible step gated behind typed confirmation + dry-run simulation.

## Class I — incident recovery

Runbooks: pause/unpause reward ops; root correction before activation; constituent replacement; signer rotation; see `incident-response.md`.

## Residual risks to disclose

- Zero-knowledge of RHJ mint/burn schedule; Stock Tokens can be minted/burned by Authorized Participants (supply of reward asset out of protocol control).
- No official sequencer uptime feed exists; availability policy must be staffed/approved before spend paths arm.
- This software being ready says nothing about the product being lawful to operate; that waits on counsel.