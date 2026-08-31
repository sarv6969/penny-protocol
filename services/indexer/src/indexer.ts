import { confirmedTip, isContiguous } from "./blocks.js";
import { applyCumulative, type CumulativeByAsset } from "./cumulative.js";
import type { BlockHeader, BlockSource } from "./events.js";
import { buildManifest, type ManifestBundle, type ManifestMeta } from "./manifest.js";
import { leafFor, proofFor, rootOf } from "./merkle.js";
import { reconcile, type ReconcileResult } from "./reconcile.js";
import { allocate, balancesAt, eligible, type Eligibility } from "./snapshot.js";
import { MemoryStore, type Store } from "./store.js";
import type { Hex } from "viem";

export const ELIGIBILITY_THRESHOLD = 100_000n * 10n ** 18n;

export interface IndexerOptions {
  confirmationDepth?: number;
  threshold?: bigint;
  /** Protocol addresses (allocator, vesting, safes, burn) that never count as holders. */
  excluded?: ReadonlySet<string>;
}

export interface IngestResult {
  pushedBlocks: number;
  pushedTransfers: number;
  rolledBackAtFork: number | undefined;
}

export interface SnapshotResult {
  block: BlockHeader;
  balances: Map<string, bigint>;
  eligibility: Eligibility;
  totalEligibleSupply: bigint;
  confirmedDepth: number;
}

export interface EpochSpec {
  chainId: number;
  distributor: string;
  epochIndex: number;
  assets: string[];
  fundedTotals: Record<string, bigint>;
  vaultBalances: Record<string, bigint>;
  priorCumulative?: CumulativeByAsset;
  exclusions?: ReadonlySet<string>;
  atBlock?: number;
  meta: ManifestMeta;
}

export interface EpochWalletProof {
  wallet: string;
  cumulative: bigint[];
  proof: Hex[];
}

export interface EpochResult {
  snapshot: SnapshotResult;
  /** The epoch index this tree targets (the onchain publish slot the keeper must fill). */
  epochIndex: number;
  /** Reward tokens in canonical ascending order (manifest `assets`). */
  assets: string[];
  root: Hex;
  leaves: Hex[];
  wallets: string[];
  newCumulative: CumulativeByAsset;
  proofs: EpochWalletProof[];
  distributedTotals: Record<string, bigint>;
  residual: Record<string, bigint>;
  reconcile: ReconcileResult;
  manifest: ManifestBundle;
}

/**
 * Reorg-safe indexer + snapshot/tree/manifest pipeline.
 *
 * Ingest: pull a canonical batch from the BlockSource, check it is contiguous, and
 * compare against what is already stored. The moment a stored block hash disagrees with
 * the canonical chain, the whole subtree from that height is rolled back and replayed
 * before the batch is committed — nothing above the confirmed cursor is ever trusted.
 *
 * Snapshot: balances are re-derived from Transfer logs, never read from stored state, so
 * a rollback is always reconciled for free when the re-ingested subtree converges.
 *
 * Epoch: allocate asset totals with largest-remainder rounding, merge cumulative
 * entitlements, build the OZ-compatible tree, and hard-gate the result through
 * `reconcile` before a root can be proposed (ADR 0003).
 */
export class Indexer {
  private readonly confirmationDepth: number;
  private readonly threshold: bigint;
  private readonly excluded: ReadonlySet<string>;

  constructor(
    private readonly source: BlockSource,
    private readonly store: Store,
    options: IndexerOptions = {},
  ) {
    this.confirmationDepth = options.confirmationDepth ?? 12;
    this.threshold = options.threshold ?? ELIGIBILITY_THRESHOLD;
    this.excluded = options.excluded ?? new Set<string>();
  }

  async ingestRange(fromBlock: number, toBlock: number): Promise<IngestResult> {
    if (toBlock < fromBlock) throw new Error("ingestRange: inverted range");
    const blocks = await this.source.getBlocks(fromBlock, toBlock);
    const transfers = await this.source.getTransfers(fromBlock, toBlock);
    if (!isContiguous(blocks)) throw new Error("ingestRange: source returned a non-contiguous chain");

    let rolledBackAtFork: number | undefined;
    for (const block of blocks) {
      const stored = await this.store.blockAt(block.number);
      if (stored !== undefined && stored.hash !== block.hash) {
        // Canonical chain changed at this height: roll the subtree back atomically.
        if (rolledBackAtFork === undefined) rolledBackAtFork = block.number;
        await this.store.deleteFromBlock(block.number);
      }
    }

    let pushedTransfers = 0;
    for (const block of blocks) {
      await this.store.upsertBlock(block);
      pushedTransfers += await this.store.upsertTransfers(
        transfers.filter((t) => t.blockNumber === block.number),
      );
    }
    return { pushedBlocks: blocks.length, pushedTransfers, rolledBackAtFork };
  }

  /** Highest fully-confirmed block (tip - depth). Undefined until past the first `depth` blocks. */
  async confirmedCursor(): Promise<number | undefined> {
    const tip = await this.store.latestBlock();
    return confirmedTip(tip?.number, this.confirmationDepth);
  }

  async snapshot(atBlock?: number): Promise<SnapshotResult> {
    const confirmed = await this.confirmedCursor();
    if (confirmed === undefined) throw new Error("snapshot: no confirmed blocks");
    const blockNumber = atBlock ?? confirmed;
    const block = await this.store.blockAt(blockNumber);
    if (block === undefined) throw new Error("snapshot: requested block not ingested");
    if (blockNumber > confirmed) throw new Error("snapshot: requested block is not yet final");

    const transfers = await this.store.transfers();
    const balances = balancesAt(transfers, blockNumber);
    const eligibility = eligible(balances, this.threshold, this.excluded);
    const tip = await this.store.latestBlock();
    return {
      block,
      balances,
      eligibility,
      totalEligibleSupply: eligibility.totalEligibleSupply,
      confirmedDepth: (tip?.number ?? 0) - blockNumber,
    };
  }

  async buildEpoch(spec: EpochSpec): Promise<EpochResult> {
    const snapshot = await this.snapshot(spec.atBlock);
    const prior = spec.priorCumulative ?? {};
    const exclusions = spec.exclusions ?? this.excluded;
    const eligibility = eligible(snapshot.balances, this.threshold, exclusions);
    const wallets = eligibility.wallets;

    const residual: Record<string, bigint> = {};
    const distributedTotals: Record<string, bigint> = {};
    const deltasByAsset: CumulativeByAsset = {};
    for (const asset of spec.assets) {
      const shares = allocate(snapshot.balances, wallets, spec.fundedTotals[asset] ?? 0n, eligibility.totalEligibleSupply);
      deltasByAsset[asset] = Object.fromEntries(shares);
      distributedTotals[asset] = [...shares.values()].reduce((a, b) => a + b, 0n);
      residual[asset] = (spec.fundedTotals[asset] ?? 0n) - distributedTotals[asset];
    }

    const newCumulative = applyCumulative(prior, spec.assets, deltasByAsset, wallets);

    const leaves = wallets.map((w) => leafFor(w, spec.assets.map((a) => newCumulative[a]?.[w] ?? 0n)));
    const root = rootOf(leaves);
    const proofs: EpochWalletProof[] = wallets.map((w, i) => ({
      wallet: w,
      cumulative: spec.assets.map((a) => newCumulative[a]?.[w] ?? 0n),
      proof: proofFor(leaves, i),
    }));

    const reconciled = reconcile({
      assets: spec.assets,
      fundedTotals: spec.fundedTotals,
      distributedTotals,
      residuals: residual,
      vaultBalances: spec.vaultBalances,
      cumulativePrior: prior,
      cumulativeNew: newCumulative,
    });
    if (!reconciled.ok) throw new Error(`reconcile failed: ${reconciled.errors.join("; ")}`);

    const payload = {
      schemaVersion: "1.0.0",
      chainId: spec.chainId,
      distributor: spec.distributor,
      epochIndex: spec.epochIndex,
      snapshot: {
        blockNumber: snapshot.block.number,
        blockHash: snapshot.block.hash,
        confirmedDepth: snapshot.confirmedDepth,
      },
      threshold: this.threshold.toString(),
      totalEligibleSupply: eligibility.totalEligibleSupply.toString(),
      assets: spec.assets,
      fundedTotals: stringifyRecord(spec.fundedTotals),
      residual: stringifyRecord(residual),
      walletProofs: proofs,
      root,
      softwareVersion: spec.meta.softwareVersion,
      commit: spec.meta.commit ?? null,
    };
    const manifest = buildManifest(spec.meta, payload);

    return {
      snapshot,
      epochIndex: spec.epochIndex,
      assets: spec.assets,
      root,
      leaves,
      wallets,
      newCumulative,
      proofs,
      distributedTotals,
      residual,
      reconcile: reconciled,
      manifest,
    };
  }
}

function stringifyRecord(record: Record<string, bigint>): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(record)) out[k] = v.toString();
  return out;
}

export function memoryIndexer(source: BlockSource, options: IndexerOptions = {}): {
  indexer: Indexer;
  store: Store;
} {
  const store = new MemoryStore();
  const indexer = new Indexer(source, store, options);
  return { indexer, store };
}