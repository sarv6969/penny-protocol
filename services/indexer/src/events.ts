export interface BlockHeader {
  number: number;
  hash: string;
  parentHash: string;
}

export interface TransferLog {
  blockNumber: number;
  txIndex: number;
  logIndex: number;
  from: string;
  to: string;
  amount: bigint;
}

/** Canonical block + event source. The source returns the best-known chain at call time. */
export interface BlockSource {
  /** Latest canonical tip (head) of the chain. */
  getTip(): Promise<BlockHeader | undefined>;
  /** Canonical block headers inclusively covering [fromBlock, toBlock], ascending. */
  getBlocks(fromBlock: number, toBlock: number): Promise<BlockHeader[]>;
  /** PENNY Transfer logs in [fromBlock, toBlock], ascending by (blockNumber, txIndex, logIndex). */
  getTransfers(fromBlock: number, toBlock: number): Promise<TransferLog[]>;
}