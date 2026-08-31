import type {
  CumulativeByAsset,
  EpochResult,
  Indexer,
  SnapshotResult,
} from "@penny/indexer";
import type { Hex } from "viem";
import type { ChainAdapter } from "./chain.js";
import type { KeeperConfig } from "./config.js";
import { inputHash } from "./state.js";

/**
 * The keeper's epoch pipeline (reward-accounting.md): ingest the rescan window with the
 * Phase 8 indexer (which rolls back forks), snapshot at a confirmed block, allocate + merge
 * cumulative into a Merkle tree, hard-gate through `reconcile`, and publish the root
 * exactly once. Publish is crash-safe: an already-activated root at the same epoch index is
 * detected onchain and recorded SUCCEEDED without a second transaction (D030).
 */

export interface IngestRun {
  fromBlock: number;
  toBlock: number;
  pushedBlocks: number;
  pushedTransfers: number;
  rolledBackAtFork: number | undefined;
  hash: string; // inputHash over (range + fetched block hashes)
}

/** Rescan the last `rescanWindow` blocks so a reorg at the confirmed cursor rolls back here. */
export async function ingestBatch(
  indexer: Indexer,
  adapter: ChainAdapter,
  config: KeeperConfig,
): Promise<IngestRun> {
  const tip = await adapter.getTip();
  const toBlock = tip?.number ?? 0;
  const fromBlock = Math.max(0, toBlock - config.rescanWindow);
  if (tip === undefined)
    return {
      fromBlock,
      toBlock,
      pushedBlocks: 0,
      pushedTransfers: 0,
      rolledBackAtFork: undefined,
      hash: "",
    };

  const blocks = await adapter.getBlocks(fromBlock, toBlock);
  const result = await indexer.ingestRange(fromBlock, toBlock);
  return {
    fromBlock,
    toBlock,
    pushedBlocks: result.pushedBlocks,
    pushedTransfers: result.pushedTransfers,
    rolledBackAtFork: result.rolledBackAtFork,
    hash: inputHash({
      from: fromBlock,
      to: toBlock,
      hashes: blocks.map((b) => b.hash),
    }),
  };
}

/**
 * Previous epoch state the keeper persists through the `root-activate` step record
 * (`detail`): where the last epoch finalized, its root, residuals (D029 dust to re-absorb),
 * the full cumulative entitlement map (so this epoch builds on real genesis-totals) and the
 * monotonic funding watermark — deposits at blocks <= `fundedUpToBlock` were already lumped
 * into a published epoch and must never be lumped again (D030).
 */
export interface EpochCursor {
  finalizedBlock: number;
  epochIndex: number;
  root: Hex;
  residual: Record<string, string>;
  cumulative: Record<string, Record<string, string>>;
  /** Highest deposit block already attributed to a published epoch. */
  fundedUpToBlock: number;
}

export function emptyCursor(): EpochCursor {
  return {
    finalizedBlock: 0,
    epochIndex: -1,
    root: "0x0000000000000000000000000000000000000000000000000000000000000000",
    residual: {},
    cumulative: {},
    fundedUpToBlock: 0,
  };
}

export interface TreeBuild {
  skipped: boolean;
  reason?: string;
  epoch?: EpochResult;
  assets: Hex[];
  funded: Map<Hex, bigint>;
}

/**
 * Allocate + merge + tree + hard-gate for the current funding window. Returns `skipped` when
 * there is no new funding or no eligible holders (the indexer refuses an empty tree).
 * `funded` is the per-token ledger produced by `funding-reconcile` — already net of any
 * funding consumed by a published-but-unrecorded epoch (see steps.runFunding).
 */
export async function treeBuild(
  indexer: Indexer,
  adapter: ChainAdapter,
  config: KeeperConfig,
  cursor: EpochCursor,
  funded: Map<Hex, bigint>,
  vaultBalances: Map<Hex, bigint>,
): Promise<TreeBuild> {
  const priorResidual = new Map(
    Object.entries(cursor.residual).map(([k, v]) => [k as Hex, BigInt(v)]),
  );
  const fundedTotals = new Map<Hex, bigint>(funded);
  for (const [token, residual] of priorResidual) {
    if (residual === 0n) continue;
    fundedTotals.set(token, (fundedTotals.get(token) ?? 0n) + residual);
  }
  const assets = [...new Set(fundedTotals.keys())]
    .filter((a) => fundedTotals.get(a)! > 0n)
    .sort() as Hex[];
  if (assets.length === 0) {
    return {
      skipped: true,
      reason: "no new funding",
      assets: [],
      funded: fundedTotals,
    };
  }

  const epochIndex = await adapter.getDistributorEpochCount();
  const priorCumulative: CumulativeByAsset = toCumulative(cursor.cumulative);
  const epoch = await indexer.buildEpoch({
    chainId: config.chainId,
    distributor: config.addresses.distributor,
    epochIndex,
    assets,
    fundedTotals: Object.fromEntries(fundedTotals),
    vaultBalances: Object.fromEntries(vaultBalances),
    priorCumulative,
    exclusions: new Set(config.excluded),
    meta: {
      generatedAt: new Date().toISOString(),
      softwareVersion: `keeper@${"0.1.0"}`,
      commit: undefined,
    },
  });

  return { skipped: false, epoch, assets, funded: fundedTotals };
}

/** Recompute the content hash from the canonical payload and check the epoch target. */
export function manifestValidate(
  epoch: EpochResult,
  expectedEpochIndex: number,
): string[] {
  const errors: string[] = [];
  if (!epoch.reconcile.ok)
    errors.push(`reconcile: ${epoch.reconcile.errors.join("; ")}`);
  if (epoch.epochIndex !== expectedEpochIndex) {
    errors.push(
      `epochIndex mismatch: built ${epoch.epochIndex}, onchain target ${expectedEpochIndex}`,
    );
  }
  // Determinism proof at the keeper boundary: the stored canonical payload must hash to the
  // published contentHash (same canonicalizer + keccak as buildManifest, D029).
  const remanifest = inputHash(epoch.manifest.payload);
  if (remanifest !== epoch.manifest.contentHash) {
    errors.push("contentHash does not match the recomputed canonical payload");
  }
  return errors;
}

export interface PublishRun {
  published: boolean;
  epochIndex: number;
  root: Hex;
}

/**
 * Publish `root` at `epochIndex` exactly once. If the onchain epoch at that index already
 * carries the root (crash between tx and ledger write), record success without re-sending.
 * A foreign root at the target index is a hard stop.
 */
export async function publishIfNeeded(
  adapter: ChainAdapter,
  root: Hex,
  assets: Hex[],
  epochIndex: number,
  cumulativeTotals: bigint[],
  manifestHash: Hex,
): Promise<PublishRun> {
  const onchainRoot = await adapter.getDistributorEpochRoot(epochIndex);
  if (onchainRoot !== undefined && onchainRoot === root) {
    return { published: false, epochIndex, root };
  }
  const onchainCount = await adapter.getDistributorEpochCount();
  if (onchainCount > epochIndex) {
    throw new Error(
      `foreign epoch root already activated at ${epochIndex} (count ${onchainCount})`,
    );
  }
  const activated = await adapter.publishEpoch(
    root,
    assets,
    cumulativeTotals,
    manifestHash,
  );
  if (activated !== epochIndex) {
    throw new Error(
      `publishEpoch returned ${activated}, expected ${epochIndex}`,
    );
  }
  return { published: true, epochIndex, root };
}

export function toCumulative(
  cursorCumulative: Record<string, Record<string, string>>,
): CumulativeByAsset {
  const out: CumulativeByAsset = {};
  for (const [asset, byWallet] of Object.entries(cursorCumulative)) {
    out[asset] = {};
    for (const [wallet, value] of Object.entries(byWallet)) {
      out[asset]![wallet] = BigInt(value);
    }
  }
  return out;
}

export function cursorOf(
  epoch: EpochResult,
  snapshot: SnapshotResult,
  residual: Record<string, bigint>,
  fundingTip: number,
): EpochCursor {
  const cumulative: Record<string, Record<string, string>> = {};
  for (const [asset, byWallet] of Object.entries(epoch.newCumulative)) {
    cumulative[asset] = {};
    for (const [wallet, value] of Object.entries(byWallet)) {
      cumulative[asset]![wallet] = value.toString();
    }
  }
  const residualStr: Record<string, string> = {};
  for (const [asset, value] of Object.entries(residual)) {
    residualStr[asset] = value.toString();
  }
  return {
    finalizedBlock: snapshot.block.number,
    epochIndex: epoch.epochIndex,
    root: epoch.root,
    residual: residualStr,
    cumulative,
    fundedUpToBlock: fundingTip,
  };
}
