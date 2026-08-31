import type { BlockHeader, TransferLog } from "@penny/indexer";
import { keccak256, toHex, type Hex } from "viem";
import type { ChainAdapter, RewardDeposit } from "../src/index.js";

/**
 * Deterministic in-memory `ChainAdapter` test double. Mirrors the real contracts' semantics:
 *  - PENNY mints are Transfer(from == 0x0) logs appended to blocks;
 *  - `sweep()` moves the whole collector WETH balance to the buyer and immediately triggers
 *    `purchaseBasket()` in the same "transaction" (FeeCollector.sweep behavior);
 *  - `purchaseBasket()` splits the buyer balance equally across `rewardTokens`, crediting the
 *    vault and emitting one `RewardsDeposited` per token at the current tip block;
 *  - `publishEpoch()` enforces the contract's strictly-ascending, non-empty token order and
 *    appends to the epoch ledger.
 */
export class FakeChain implements ChainAdapter {
  private height = 0;
  private readonly headers: BlockHeader[] = [];
  private readonly transfers: TransferLog[] = [];
  private readonly deposits: RewardDeposit[] = [];
  private purchaseCounter = 0;
  private readonly epochs: { root: Hex; assets: Hex[] }[] = [];

  collectorWeth = 0n;
  buyerWeth = 0n;
  rewardTokens: Hex[] = [];
  private readonly vault = new Map<Hex, bigint>();
  private readonly committedTotals = new Map<Hex, bigint>();
  private readonly lifetimeDeposits = new Map<Hex, bigint>();

  marketSessionOpen = true;
  sweepsEnabled = true;

  constructor(public readonly depth: number = 2) {}

  /** Current block height. */
  tip(): number {
    return this.height;
  }

  /** Append an empty block to the canonical chain (hash derived from header fields). */
  tick(): BlockHeader {
    const number = ++this.height;
    const hash = this.hash("block", number);
    const parentHash =
      this.headers[this.headers.length - 1]?.hash ?? "0x" + "0".repeat(64);
    const header = { number, hash, parentHash };
    this.headers.push(header);
    return header;
  }

  /** Mint `amount` PENNY to `wallet` at the current tip block (mint = from 0x0). */
  mintPENNY(wallet: Hex, amount: bigint): void {
    const blockNumber = this.height;
    const txIndex = this.transfers.filter(
      (t) => t.blockNumber === blockNumber,
    ).length;
    this.transfers.push({
      blockNumber,
      txIndex,
      logIndex: 0,
      from: "0x" + "0".repeat(40),
      to: wallet.toLowerCase() as Hex,
      amount,
    });
  }

  /** Add WETH into the collector tank at the current tip. */
  feedFees(weth: bigint): void {
    this.collectorWeth += weth;
  }

  /** Pre-provision Stock Token supply the vault will receive (mock of real purchased tokens). */
  provisionRewardToken(token: Hex): void {
    this.rewardTokens.push(token);
  }

  getVaultBalance(token: Hex): Promise<bigint> {
    return Promise.resolve(this.vault.get(token) ?? 0n);
  }

  getFeeCollectorWeth(): Promise<bigint> {
    return Promise.resolve(this.collectorWeth);
  }

  getMarketSessionOpen(): Promise<boolean> {
    return Promise.resolve(this.marketSessionOpen);
  }

  getSweepEnabled(): Promise<boolean> {
    return Promise.resolve(this.sweepsEnabled);
  }

  getTip(): Promise<BlockHeader | undefined> {
    return Promise.resolve(this.headers[this.headers.length - 1]);
  }

  getBlocks(fromBlock: number, toBlock: number): Promise<BlockHeader[]> {
    return Promise.resolve(
      this.headers.filter((b) => b.number >= fromBlock && b.number <= toBlock),
    );
  }

  getTransfers(fromBlock: number, toBlock: number): Promise<TransferLog[]> {
    return Promise.resolve(
      this.transfers.filter(
        (t) => t.blockNumber >= fromBlock && t.blockNumber <= toBlock,
      ),
    );
  }

  getRewardsDeposited(
    fromBlock: number,
    toBlock: number,
  ): Promise<RewardDeposit[]> {
    return Promise.resolve(
      this.deposits.filter(
        (d) => d.blockNumber >= fromBlock && d.blockNumber <= toBlock,
      ),
    );
  }

  getDistributorEpochCount(): Promise<number> {
    return Promise.resolve(this.epochs.length);
  }

  getDistributorEpochRoot(index: number): Promise<Hex | undefined> {
    return Promise.resolve(this.epochs[index]?.root);
  }

  async sweep(): Promise<bigint> {
    if (!this.sweepsEnabled) throw new Error("SweepsPaused");
    if (this.collectorWeth === 0n) return 0n;
    const amount = this.collectorWeth;
    this.collectorWeth = 0n;
    this.buyerWeth += amount;
    return this.purchaseBasket();
  }

  async purchaseBasket(): Promise<bigint> {
    if (this.buyerWeth === 0n || this.rewardTokens.length === 0) return 0n;
    const spend = this.buyerWeth;
    this.buyerWeth = 0n;
    this.purchaseCounter += 1;
    const share = spend / BigInt(this.rewardTokens.length);
    for (const token of this.rewardTokens) {
      this.vault.set(token, (this.vault.get(token) ?? 0n) + share);
      this.lifetimeDeposits.set(
        token,
        (this.lifetimeDeposits.get(token) ?? 0n) + share,
      );
      this.deposits.push({
        blockNumber: this.height,
        token,
        amount: share,
        purchaseIndex: this.purchaseCounter,
      });
    }
    return spend;
  }

  async publishEpoch(
    root: Hex,
    assets: Hex[],
    cumulativeTotals: bigint[] = [],
    _manifestHash: Hex = ("0x" + "0".repeat(64)) as Hex,
  ): Promise<number> {
    if (assets.length === 0) throw new Error("BadTokenCount");
    if (
      cumulativeTotals.length > 0 &&
      cumulativeTotals.length !== assets.length
    ) {
      throw new Error("BadTokenCount");
    }
    for (let i = 1; i < assets.length; i++) {
      // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
      if (assets[i]! <= assets[i - 1]!) throw new Error("TokensNotSorted");
    }
    if (root === "0x" + "0".repeat(64)) throw new Error("ZeroRoot");
    // Mirror the onchain D032 guards: totals are monotone and funding-covered.
    for (let i = 0; i < cumulativeTotals.length; i++) {
      // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
      const token = assets[i]!;
      // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
      const total = cumulativeTotals[i]!;
      const prior = this.committedTotals.get(token) ?? 0n;
      if (total < prior) throw new Error("CumulativeOutOfOrder");
      const funded = this.lifetimeDeposits.get(token) ?? this.vault.get(token);
      if (funded !== undefined && total > funded) {
        throw new Error("ExceedsFunding");
      }
      this.committedTotals.set(token, total);
    }
    const index = this.epochs.length;
    this.epochs.push({ root, assets });
    return index;
  }

  private hash(domain: string, value: number): string {
    return keccak256(toHex(`${domain}:${value}`));
  }
}
