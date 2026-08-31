import type { BlockHeader, TransferLog } from "@penny/indexer";
import type { Hex } from "viem";

/**
 * Keeper onchain interface (Phase 9). The keeper drives the rail through `ChainAdapter`
 * so tests run a `FakeChain` and the production adapter stays un-armed until the mainnet
 * gates resolve (D009/D025, architecture.md "deployment order" step 10).
 *
 * Reads: the same `BlockHeader`/`TransferLog` shapes the Phase 8 indexer consumes, plus the
 * funding/epoch state the payout pipeline reconciles against. Writes: sweep, purchase and
 * publish are naturally idempotent or guarded in `pipeline.ts` — no keeper op is re-run
 * against a state it already produced (D030).
 */
export interface RewardDeposit {
  blockNumber: number;
  token: Hex;
  amount: bigint;
  /** index of the purchase cycle that paid for this deposit (i.e. txIndex of the purchase) */
  purchaseIndex: number;
}

export interface ChainAdapter {
  getTip(): Promise<BlockHeader | undefined>;
  getBlocks(fromBlock: number, toBlock: number): Promise<BlockHeader[]>;
  /** PENNY Transfer logs in [fromBlock, toBlock], ascending by (blockNumber, txIndex, logIndex). */
  getTransfers(fromBlock: number, toBlock: number): Promise<TransferLog[]>;
  /** RewardVault `RewardsDeposited` records in [fromBlock, toBlock], ascending. */
  getRewardsDeposited(
    fromBlock: number,
    toBlock: number,
  ): Promise<RewardDeposit[]>;

  getFeeCollectorWeth(): Promise<bigint>;
  getVaultBalance(token: Hex): Promise<bigint>;
  getDistributorEpochCount(): Promise<number>;
  getDistributorEpochRoot(index: number): Promise<Hex | undefined>;
  /** OracleGuard market-session gate (fail-closed D009). */
  getMarketSessionOpen(): Promise<boolean>;
  /** FeeCollector.sweepsPaused flag — pause only blocks sweeps (D014). */
  getSweepEnabled(): Promise<boolean>;

  /** FeeCollector.sweep() → basketSpend. No-op (=0) when collector balance is below threshold. */
  sweep(): Promise<bigint>;
  /** BasketBuyer.purchaseBasket() → totalSpent. No-op (=0) when there is no swept balance. */
  purchaseBasket(): Promise<bigint>;
  /**
   * RewardDistributor.publishEpoch(root, assets, cumulativeTotals, manifestHash) → the new
   * epochIndex (only when not yet published). `cumulativeTotals[i]` is the manifest's total
   * cumulative entitlement for `assets[i]`; the contract enforces monotonicity and vault
   * funding coverage onchain (D032).
   */
  publishEpoch(
    root: Hex,
    assets: Hex[],
    cumulativeTotals: bigint[],
    manifestHash: Hex,
  ): Promise<number>;
}
