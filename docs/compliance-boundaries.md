# Compliance boundaries

Hard engineering requirement — not a footer. Stock Tokens are regulated, cross-border, and their delivery is restricted.

## What Robinhood states (confirmed from official docs)

- Stock Tokens are **tokenised debt securities issued by Robinhood Assets (Jersey) Limited (RHJ)** and are **not registered under U.S. securities laws**.
- They **may not be offered, sold or delivered directly or indirectly in the United States or to/for the account or benefit of U.S. persons**.
- Additional restrictions apply in at least **Canada, the United Kingdom, and Switzerland**.
- They **do not grant legal or beneficial ownership** of underlying shares — hence "Stock Token rewards providing economic exposure", never "you own five stocks".

## What the product must enforce

1. **No blind distribution.** We never sweep-fund arbitrary holder wallets with Stock Tokens. Receipt of reward assets requires a live eligibility attestation.
2. **Attestation design:** signed, scoped to (chain, contract, wallet), expiring, non-replayable across domains, revocable under counsel-approved policy; re-checked at claim time.
3. **Jurisdiction policy is configuration, not code copy.** Final list supplied by counsel, versioned and signed; loaded, not hardcoded. Frontend geolocation is supplementary, never the control.
4. **Language discipline in UI/docs:** "Stock Token rewards", "economic exposure", "separate rewards", "founding small-cap moonshot basket"; explicitly "PENNY is not redeemable for the basket and does not itself represent ownership of the Stock Tokens or underlying shares". Never "own five stocks", "shares paid every 15 minutes", "dividend", "guaranteed yield", or misleading "audited".
5. **Honest about pauses:** purchases/epochs can pause for thresholds, market closure, liquidity, oracle, corporate actions, compliance, emergencies.
6. **Own-model disclosure:** the project's own token and the 3%-fee reward model themselves require securities, promotions, tax, money-transmission, sanctions, consumer-protection, and data-privacy analysis. This is stated, not assumed.

## Hard stop

`MAINNET_LEGAL_APPROVAL=false` is the default and is checked by deployment and production services. Only a deliberate, documented, user-controlled configuration change — after counsel signoff — flips it. Nothing in this repository constitutes legal approval.

## Ownership of decisions

- The issuer/operator, eligible jurisdictions, and the restricted-person delivery mechanism are decided by counsel + humans; the codebase implements the mechanism they approve.
- Adding constituents must also pass the legal/compliance review for that issuer in addition to the tokenized/technical gate.