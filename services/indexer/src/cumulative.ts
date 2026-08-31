export type CumulativePerWallet = Record<string, bigint>;
export type CumulativeByAsset = Record<string /* normalized asset address */, CumulativePerWallet>;

/**
 * Merge an epoch's awarded deltas on top of the running genesis-total (i.e. cumulative)
 * entitlement. Wallets that lose eligibility keep their prior cumulative; new exposure is
 * strictly additive, so `new >= prior` for every (asset, wallet) by construction (D026).
 */
export function applyCumulative(
  prior: CumulativeByAsset,
  assets: string[],
  deltas: CumulativeByAsset,
  wallets: string[],
): CumulativeByAsset {
  if (assets.length === 0) throw new Error("applyCumulative: empty asset list");
  if (Object.keys(deltas).length !== assets.length) {
    throw new Error("applyCumulative: delta/assets length mismatch");
  }

  const next: CumulativeByAsset = {};
  for (const asset of assets) {
    const priorWallet = prior[asset] ?? {};
    const deltaWallet = deltas[asset] ?? {};
    const merged: CumulativePerWallet = {};
    for (const wallet of wallets) {
      const before = priorWallet[wallet] ?? 0n;
      const delta = deltaWallet[wallet] ?? 0n;
      merged[wallet] = before + delta;
    }
    // Preserve prior entitlements for wallets that no longer appear (e.g. lost
    // eligibility): they keep their last cumulative value even if absent from this run.
    for (const wallet of Object.keys(priorWallet)) {
      if (merged[wallet] === undefined) merged[wallet] = priorWallet[wallet]!;
    }
    next[asset] = merged;
  }
  return next;
}

/** Sum of all wallets' cumulative entitlements for an asset. */
export function cumulativeTotal(cumulative: CumulativeByAsset, asset: string): bigint {
  const byWallet = cumulative[asset] ?? {};
  let total = 0n;
  for (const v of Object.values(byWallet)) total += v;
  return total;
}

/** True when, for every asset and wallet, `next.value >= prior.value`. */
export function isMonotone(prior: CumulativeByAsset, next: CumulativeByAsset, assets: string[]): boolean {
  for (const asset of assets) {
    const priorWallet = prior[asset] ?? {};
    const nextWallet = next[asset] ?? {};
    const wallets = new Set([...Object.keys(priorWallet), ...Object.keys(nextWallet)]);
    for (const wallet of wallets) {
      if ((nextWallet[wallet] ?? 0n) < (priorWallet[wallet] ?? 0n)) return false;
    }
  }
  return true;
}