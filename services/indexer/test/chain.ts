import type { BlockHeader, BlockSource, TransferLog } from "../src/index.js";

export function zeroAddress(): string {
  return "0x" + "0".repeat(40);
}

export function hashOf(n: number): string {
  return "0x" + n.toString(16).padStart(64, "0");
}

export interface ChainSpec {
  size: number;
  /** Optional override for block n's hash, used to force a fork. */
  override?: Record<number, string>;
}

/** Deterministic canonical chain: block i hashes to `hashOf(i)` and links its predecessor. */
export function buildChain(spec: ChainSpec): BlockHeader[] {
  const blocks: BlockHeader[] = [];
  const hashAt = (n: number): string => spec.override?.[n] ?? hashOf(n);
  for (let n = 0; n < spec.size; n++) {
    blocks.push({
      number: n,
      hash: hashAt(n),
      parentHash: n === 0 ? hashAt(0) : hashAt(n - 1), // children follow overridden hashes too
    });
  }
  return blocks;
}

export function transfer(blockNumber: number, txIndex: number, logIndex: number, from: string, to: string, amount: bigint): TransferLog {
  return { blockNumber, txIndex, logIndex, from, to, amount };
}

export class FakeSource implements BlockSource {
  private blocks: BlockHeader[];
  private transfers: TransferLog[];

  constructor(blocks: BlockHeader[], transfers: TransferLog[]) {
    this.blocks = blocks;
    this.transfers = transfers;
  }

  /** Swap the canonical view the indexer observes (simulates a chain reorg at the RPC). */
  replace(blocks: BlockHeader[], transfers: TransferLog[]): void {
    this.blocks = blocks;
    this.transfers = transfers;
  }

  async getTip(): Promise<BlockHeader | undefined> {
    return this.blocks[this.blocks.length - 1];
  }

  async getBlocks(fromBlock: number, toBlock: number): Promise<BlockHeader[]> {
    return this.blocks.filter((b) => b.number >= fromBlock && b.number <= toBlock);
  }

  async getTransfers(fromBlock: number, toBlock: number): Promise<TransferLog[]> {
    return this.transfers.filter((t) => t.blockNumber >= fromBlock && t.blockNumber <= toBlock);
  }
}

export const TOTAL_SUPPLY = 1_000_000_000n * 10n ** 18n;
export const THRESHOLD = 100_000n * 10n ** 18n;