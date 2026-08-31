import type { BlockHeader } from "./events.js";

/**
 * Finality primitives for the reorg-safe ingest rail.
 *
 * Robinhood Chain is a novel L2: recent state is forkable, so nothing is treated as
 * permanent until it is `confirmationDepth` blocks deep (D025). The indexer snapshots
 * exclusively at confirmed blocks and rolls back the instant a canonical chain change
 * is observed at a height it already stored.
 */
export const DEFAULT_CONFIRMATION_DEPTH = 12;

/** Highest block number safe to snapshot: tip - depth (>= 0). Undefined before any tip. */
export function confirmedTip(tip: number | undefined, depth: number): number | undefined {
  if (tip === undefined) return undefined;
  return Math.max(0, tip - depth);
}

/** First height where an existing chain and an incoming canonical batch disagree. */
export function forkAt(existing: BlockHeader[], incoming: BlockHeader[]): number | undefined {
  const existingByNumber = new Map(existing.map((b) => [b.number, b]));
  for (const block of incoming) {
    const stored = existingByNumber.get(block.number);
    if (stored && stored.hash !== block.hash) return block.number;
  }
  return undefined;
}

/** True when every block in the batch links to its predecessor via parentHash. */
export function isContiguous(batch: BlockHeader[]): boolean {
  for (let i = 1; i < batch.length; i++) {
    const prev = batch[i - 1];
    const cur = batch[i];
    if (prev === undefined || cur === undefined) return false;
    if (prev.number + 1 !== cur.number) return false;
    if (cur.parentHash !== prev.hash) return false;
  }
  return true;
}

/** Block just below the deepest stored height, if any (for resuming a seeded `fromBlock`). */
export function lowestStored(batch: BlockHeader[]): BlockHeader | undefined {
  return batch.length === 0 ? undefined : [...batch].sort((a, b) => a.number - b.number)[0];
}