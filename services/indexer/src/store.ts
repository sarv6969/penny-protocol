import type { BlockHeader, TransferLog } from "./events.js";

export interface Store {
  upsertBlock(block: BlockHeader): Promise<void>;
  blockAt(number: number): Promise<BlockHeader | undefined>;
  latestBlock(): Promise<BlockHeader | undefined>;
  upsertTransfers(logs: TransferLog[]): Promise<number>;
  transfers(): Promise<TransferLog[]>;
  /** Immutably delete every block and transfer with blockNumber >= atBlock (reorg rollback). */
  deleteFromBlock(atBlock: number): Promise<{ removedBlocks: number; removedTransfers: number }>;
}

export function transferKey(t: TransferLog): string {
  return `${t.blockNumber}:${t.txIndex}:${t.logIndex}`;
}

/**
 * In-memory store used for tests and for pure, build-time pipeline runs.
 * The SQL-backed store (Postgres) implements the same interface.
 */
export class MemoryStore implements Store {
  private blocks = new Map<number, BlockHeader>();
  private logRows = new Map<string, TransferLog>();

  async upsertBlock(block: BlockHeader): Promise<void> {
    this.blocks.set(block.number, block);
  }

  async blockAt(number: number): Promise<BlockHeader | undefined> {
    return this.blocks.get(number);
  }

  async latestBlock(): Promise<BlockHeader | undefined> {
    let latest: BlockHeader | undefined;
    for (const b of this.blocks.values()) {
      if (!latest || b.number > latest.number) latest = b;
    }
    return latest;
  }

  async upsertTransfers(logs: TransferLog[]): Promise<number> {
    let added = 0;
    for (const t of logs) {
      const key = transferKey(t);
      if (!this.logRows.has(key)) added += 1;
      this.logRows.set(key, t);
    }
    return added;
  }

  async transfers(): Promise<TransferLog[]> {
    const rows = [...this.logRows.values()];
    rows.sort((a, b) => a.blockNumber - b.blockNumber || a.txIndex - b.txIndex || a.logIndex - b.logIndex);
    return rows;
  }

  async deleteFromBlock(atBlock: number): Promise<{ removedBlocks: number; removedTransfers: number }> {
    let removedBlocks = 0;
    for (const n of [...this.blocks.keys()]) {
      if (n >= atBlock) {
        this.blocks.delete(n);
        removedBlocks += 1;
      }
    }
    let removedTransfers = 0;
    for (const [key, t] of [...this.logRows.entries()]) {
      if (t.blockNumber >= atBlock) {
        this.logRows.delete(key);
        removedTransfers += 1;
      }
    }
    return { removedBlocks, removedTransfers };
  }
}