export const SCHEMA_VERSION = 1;

export interface BalanceRow {
  blockNumber: bigint;
  blockHash: string;
  address: string;
  balance: bigint;
  confirmations: number;
}

export function validateSupplySum(rows: BalanceRow[], expectedSupply: bigint): boolean {
  return rows.reduce((acc, r) => acc + r.balance, 0n) === expectedSupply;
}