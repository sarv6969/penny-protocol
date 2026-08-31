import type { TransferLog } from "./events.js";

export const ZERO_ADDRESS = "0x" + "0".repeat(40);

function normalize(address: string): string {
  return address.toLowerCase();
}

/**
* Rebuild every PENNY balance by replaying Transfer logs up to (and including) a
 * snapshot block. The token is fixed-supply; the mint is the `from == 0x0` transfer and a
 * burn is `to == 0x0`, so the zero address is used purely as a bookkeeping sink/source and
 * never carries a holder balance. The sum of all non-zero balances at any block equals the
 * circulating supply. This is a full re-derivation — no stored balance is ever trusted,
 * which makes the reorg rollback trivially correct.
 */
export function balancesAt(transfers: TransferLog[], atBlock: number): Map<string, bigint> {
  const zero = ZERO_ADDRESS;
  const balances = new Map<string, bigint>();
  for (const t of transfers) {
    if (t.blockNumber > atBlock) continue;
    const from = normalize(t.from);
    const to = normalize(t.to);
    if (to !== zero) balances.set(to, (balances.get(to) ?? 0n) + t.amount);
    if (from !== zero) balances.set(from, (balances.get(from) ?? 0n) - t.amount);
  }
  return balances;
}

export function totalSupplyOf(balances: Map<string, bigint>): bigint {
  let total = 0n;
  for (const b of balances.values()) total += b;
  return total;
}

export interface Eligibility {
  wallets: string[];
  totalEligibleSupply: bigint;
}

/**
 * Deterministic eligibility filter: balance >= threshold, address not excluded.
 * Wallets are returned in ascending address order (canonical manifest ordering).
 */
export function eligible(balances: Map<string, bigint>, threshold: bigint, exclusions: ReadonlySet<string>): Eligibility {
  const wallets = new Set<string>();
  let totalEligibleSupply = 0n;
  for (const [addr, balance] of balances) {
    if (balance < threshold) continue;
    if (exclusions.has(addr)) continue;
    wallets.add(addr);
    totalEligibleSupply += balance;
  }
  return { wallets: [...wallets].sort(), totalEligibleSupply };
}

/**
 * Deterministic largest-remainder allocation: every eligible wallet gets
 * `floor(balance * assetTotal / totalEligibleSupply)`, then leftover units go +1 each
 * to the wallets with the largest fractional remainders, ties broken by ascending
 * address. The sum is guaranteed exactly `assetTotal`; the residual is zero and is
 * recorded in the manifest for transparency (D024-style dust rule).
 */
export function allocate(
  balances: Map<string, bigint>,
  walletsASC: string[],
  assetTotal: bigint,
  totalEligibleSupply: bigint,
): Map<string, bigint> {
  if (assetTotal === 0n) {
    return new Map(walletsASC.map((w) => [w, 0n] as const));
  }
  if (totalEligibleSupply === 0n) throw new Error("allocate: empty eligible supply with nonzero asset total");

  const rows = walletsASC.map((w, i) => {
    const balance = balances.get(w);
    if (balance === undefined) throw new Error(`allocate: no balance for ${w}`);
    return {
      w,
      order: i,
      quotient: (balance * assetTotal) / totalEligibleSupply,
      remainder: (balance * assetTotal) % totalEligibleSupply,
    };
  });

  let distributed = rows.reduce((acc, r) => acc + r.quotient, 0n);
  let leftover = assetTotal - distributed;

  rows.sort((a, b) => (a.remainder === b.remainder ? a.order - b.order : a.remainder > b.remainder ? -1 : 1));

  const shares = new Map<string, bigint>();
  const it = rows[Symbol.iterator]();
  for (let r = it.next(); leftover > 0n && !r.done; r = it.next()) {
    shares.set(r.value.w, r.value.quotient + 1n);
    leftover -= 1n;
  }
  for (const row of rows) {
    if (!shares.has(row.w)) shares.set(row.w, row.quotient);
  }
  if (leftover !== 0n) throw new Error("allocate: residual not absorbed");
  return shares;
}