# Reward accounting

Cumulative multi-token Merkle reward system. Design summary + invariants behind Phase 7.

## Principles

- **Never enumerate holders onchain.** The indexer reconstructs `PENNY` balances from Transfer logs and snapshots at a finalized block.
- **Cumulative entitlements, not per-epoch drops.** Each leaf: `(wallet, asseti, cumulativeEntitlement, proofIndex...)`. A claim pays `cumulative - claimed`, making double-claims and cross-root decreases structurally impossible.
- **Eligibility at both snapshot and claim.** Balance threshold + exclusion list at snapshot; live scoped eligibility attestation at claim.

## Epoch pipeline

1. Funded fees → basket purchase → RewardVault deposits (per-asset totals recorded).
2. Keeper chooses safe snapshot block (finalized, not "latest").
3. Indexer computes eligible holder set + total eligible supply (exact integers; exclusions with reason/effectiveBlock/authorizer).
4. Per asset: `walletShare = (walletBalance * assetAmount) / totalEligibleSupply` with documented deterministic rounding (dust to a burn/fraction rule — must be transparent, not admin-claimed).
5. Add prior cumulative; build Merkle tree and canonical JSON manifest (inputs, exclusions, balances, totals, proofs, source hashes, software version/commit, content hash).
6. Cross-checks: manifest totals == vault funded totals; new cumulative >= prior; never exceeds vault.
7. Propose root → challenge delay → activate → optional relayer claims (opt-in, non-redirecting).

## Invariants (test-enforced)

- For all `a,i`: `cumulativeNew[a,i] >= cumulativeOld[a,i]`.
- `sum(cumulativeTotals[i]) <= vaultBalance[i]` at every activation.
- A claim can only transfer `cumulative[a,i] - claimed[a,i]`.
- Leaf digest domain-separates chain / distributor contract / epoch — non-replayable.

## Dust rule

Deterministic; expressed in the manifest; applied identically across clean runs (bit-for-bit reproducible trees). No "dust to treasury". Leftover per-asset units from division roll into the manifest's residual tally and are re-absorbed deterministically in the next cycle's funding reconciliation.

## Snapshot determinism

Same chain block + data + software version → identical tree and manifest. CI test asserts two clean builds produce identical `keccak256(manifest)`.