# ADR 0005 — Compliance gate and eligibility registry

- **Status:** Accepted (2026-08-30); mechanism Phase 7, policy after counsel
- **Context:** Stock Tokens may not be delivered to U.S. persons or persons in other restricted jurisdictions. Frontend geoblocking is inadequate; blind distribution is prohibited.
- **Decision:**
  - Reward claims enforce eligibility onchain via a signed attestation registry.
  - Attestations scoped to (chain, contract, wallet), expiring, domain-scoped, revocable; re-checked at claim.
  - Jurisdiction policy is a signed/versioned config, loaded not hardcoded, supplied after legal review.
  - No claims to unattested wallets; no claimless transfers; relayers never redirect.
  - `MAINNET_LEGAL_APPROVAL=false` hard stop enforced by deployment/production services.
- **Consequences:** Attestation service + registry are production-critical components; claims pause if registry degraded (fail closed for claims, never trap PENNY transfers). D009-adjacent operational policy required.