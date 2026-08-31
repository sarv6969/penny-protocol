import { isMonotone, type CumulativeByAsset } from "./cumulative.js";

export interface ReconcileInput {
  assets: string[];
  /** Amounts actually funded into the RewardVault this epoch (from the basket-purchase record). */
  fundedTotals: Record<string, bigint>;
  /** Sum of the deltas the indexer allocated per asset. */
  distributedTotals: Record<string, bigint>;
  /** Amounts left over per asset (must be zero with largest-remainder allocation). */
  residuals: Record<string, bigint>;
  /** Current RewardVault balance per asset (as read onchain before activation). */
  vaultBalances: Record<string, bigint>;
  cumulativePrior: CumulativeByAsset;
  cumulativeNew: CumulativeByAsset;
}

export interface ReconcileResult {
  ok: boolean;
  errors: string[];
}

/**
 * Hard validation gate between tree generation and root proposal (ADR 0003):
 *  - manifest totals == vault-funded totals (deltas fully explained);
 *  - residual is zero (no undeclared dust), recorded for transparency;
 *  - new cumulative never below prior (monotone, no entitlement destruction);
 *  - this epoch's total payments per asset never exceed the funded vault balance
 *    (against the *running* vault, which shrinks as prior epochs are claimed).
 * Any failed check is a hard stop — the root must not be proposed.
 */
export function reconcile(input: ReconcileInput): ReconcileResult {
  const errors: string[] = [];
  const { assets } = input;

  for (const asset of assets) {
    const funded = input.fundedTotals[asset] ?? 0n;
    const distributed = input.distributedTotals[asset] ?? 0n;
    const residual = input.residuals[asset] ?? 0n;

    if (distributed + residual !== funded) {
      errors.push(`asset ${asset}: distributed(${distributed}) + residual(${residual}) != funded(${funded})`);
    }
    if (residual > 0n) {
      errors.push(`asset ${asset}: nonzero residual ${residual} not yet re-absorbed`);
    }
    const outstanding = input.distributedTotals[asset] ?? 0n;
    const vault = input.vaultBalances[asset] ?? 0n;
    if (outstanding > vault) {
      errors.push(`asset ${asset}: this epoch's payments(${outstanding}) > vault(${vault})`);
    }
  }

  if (!isMonotone(input.cumulativePrior, input.cumulativeNew, assets)) {
    errors.push("cumulative decreased in at least one (asset, wallet)");
  }

  return { ok: errors.length === 0, errors };
}