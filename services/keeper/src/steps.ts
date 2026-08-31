import type { EpochResult, Indexer, SnapshotResult } from "@penny/indexer";
import type { Hex } from "viem";
import type { ChainAdapter, RewardDeposit } from "./chain.js";
import type { KeeperConfig } from "./config.js";
import type { JobName } from "./jobs.js";
import {
  cursorOf,
  emptyCursor,
  ingestBatch,
  manifestValidate,
  publishIfNeeded,
  treeBuild,
  type EpochCursor,
  type IngestRun,
} from "./pipeline.js";
import { PurchaseMachine, type PurchaseOutcome } from "./purchase.js";
import { inputHash, type StepStore } from "./state.js";

/**
 * Per-cycle execution context threaded through the job graph. `cursor` is the *previous*
 * epoch until `root-activate` writes the new one; `assets` (from `tree-build`) and `funded`
 * (from `funding-reconcile`) feed the onchain publish and the crash-recovery guards.
 */
export interface CycleContext {
  cycleId: string;
  cursor: EpochCursor;
  ingest?: IngestRun;
  purchase?: PurchaseOutcome;
  deposits?: RewardDeposit[];
  /** Net per-token funding for this epoch (raw deposits minus already-consumed), wei. */
  funded?: Map<Hex, bigint>;
  /** Tip at `funding-reconcile` time — advances the `fundedUpToBlock` watermark on publish. */
  fundingTip?: number;
  assets?: Hex[];
  snapshot?: SnapshotResult;
  epoch?: EpochResult;
  /** D034 auto-delivery: armed only when the production attestation service is configured. */
  relayArmed?: boolean;
  /** Opted-in wallets' delivery entries for the activated epoch (built by the census). */
  deliveries?: DeliveryEntry[];
  /** Injected adapter call → RewardDistributor.claimForMany; returns delivered count. */
  claimForMany?: (
    epochIndex: number,
    deliveries: DeliveryEntry[],
  ) => Promise<number>;
}

export interface StepOutcome {
  status: "succeeded" | "skipped" | "failed";
  atBlock?: number;
  detail?: string;
  error?: string;
  inputHash?: string;
}

export function ok(
  hash: string,
  extra: Partial<StepOutcome> = {},
): StepOutcome {
  return { status: "succeeded", inputHash: hash, ...extra };
}

export function skip(reason: string, hash?: string): StepOutcome {
  return {
    status: "skipped",
    detail: reason,
    ...(hash !== undefined ? { inputHash: hash } : {}),
  };
}

export function fail(error: string): StepOutcome {
  return { status: "failed", error };
}

export async function readCursor(store: StepStore): Promise<EpochCursor> {
  const history = await store.history("root-activate");
  for (const record of history) {
    if (record.status === "succeeded" && record.detail) {
      try {
        return JSON.parse(record.detail) as EpochCursor;
      } catch {
        continue;
      }
    }
  }
  return emptyCursor();
}

export function writeCursor(cursor: EpochCursor): string {
  return JSON.stringify(cursor);
}

/** Write-ahead intent recorded by `root-propose` before any publish transaction (D030). */
export interface ProposeIntent {
  root: string;
  epochIndex: number;
  snapshotBlock: number;
  contentHash: string;
  /** Per-token fundedTotals this epoch intends to distribute (decimal wei strings). */
  funded: Record<string, string>;
  /**
   * The full cursor this epoch would persist upon activation (serialized). Crash recovery
   * warms the cursor up from here — the onchain root at `epochIndex` matching `root` proves
   * the activation happened, so the cumulative map, watermark and residuals are restored
   * atomically instead of being re-derived (which would drift from the published sequence).
   */
  nextCursor: string;
}

export async function latestIntent(
  store: StepStore,
): Promise<{ intent: ProposeIntent; cycleId: string } | undefined> {
  const history = await store.history("root-propose");
  for (const record of history) {
    if (record.status === "succeeded" && record.detail) {
      try {
        return {
          intent: JSON.parse(record.detail) as ProposeIntent,
          cycleId: record.cycleId,
        };
      } catch {
        continue;
      }
    }
  }
  return undefined;
}

/**
 * A prior SUCCEEDED record with the same inputHash whose forward-progress marker still holds
 * means the work is already done onchain — return the skip reason; otherwise undefined.
 */
export async function resumeReason(
  store: StepStore,
  job: JobName,
  hash: string | undefined,
  forward: () => Promise<boolean>,
): Promise<string | undefined> {
  if (!hash) return undefined;
  const history = await store.history(job);
  for (const record of history) {
    if (record.status !== "succeeded" || record.inputHash !== hash) continue;
    if (!(await forward())) return undefined;
    return `identical to cycle ${record.cycleId}`;
  }
  return undefined;
}

/** `ingest`: re-scan the rescan window through the indexer (fork rollback happens here). */
export async function runIngest(
  indexer: Indexer,
  adapter: ChainAdapter,
  config: KeeperConfig,
  store: StepStore,
  ctx: CycleContext,
): Promise<StepOutcome> {
  const run = await ingestBatch(indexer, adapter, config);
  ctx.ingest = run;
  if (run.hash === "") return skip("no blocks");
  const detail =
    run.rolledBackAtFork !== undefined
      ? `${run.pushedBlocks} blocks, ${run.pushedTransfers} transfers; fork rolled back at ${run.rolledBackAtFork}`
      : `${run.pushedBlocks} blocks, ${run.pushedTransfers} transfers`;
  const reason = await resumeReason(
    store,
    "ingest",
    run.hash,
    async () => true,
  );
  if (reason) return skip(reason, run.hash);
  return ok(run.hash, { atBlock: run.toBlock, detail, inputHash: run.hash });
}

/** `basket-purchase`: gate session + armed venue, then sweep→purchase when the tank is fed. */
export async function runBasketPurchase(
  adapter: ChainAdapter,
  config: KeeperConfig,
  store: StepStore,
  ctx: CycleContext,
): Promise<StepOutcome> {
  if (!config.venueArmed)
    return fail("NO_GO_LIQUIDITY: venue adapter unverified (mainnet gate)");
  if (!(await adapter.getMarketSessionOpen()))
    return fail("market session closed (fail-closed D009)");
  if (!(await adapter.getSweepEnabled())) return fail("sweeps paused");

  const machine = new PurchaseMachine(adapter, config);
  const purchase = await machine.purchase(ctx.cursor.fundedUpToBlock);
  ctx.purchase = purchase;

  const hash = inputHash({
    reason: purchase.reason,
    sweptWei: purchase.sweptWei.toString(),
    spentWei: purchase.spentWei.toString(),
  });
  if (purchase.reason === "below-min-sweep") {
    const reason = await resumeReason(
      store,
      "basket-purchase",
      hash,
      async () => (await adapter.getFeeCollectorWeth()) < config.minSweepWei,
    );
    return reason
      ? skip(reason, hash)
      : ok(hash, { detail: "below-min-sweep (tank drained)", inputHash: hash });
  }
  return ok(hash, {
    detail: `swept ${purchase.sweptWei} wei, spent ${purchase.spentWei} wei`,
    inputHash: hash,
  });
}

/**
 * Warm-start recovery (D030): if the recorded cursor sits behind the frontier intent and the
 * intent's epoch is already published onchain (root matches), the activation record was lost
 * to a crash — adopt the intent's `nextCursor` and synthesize the missing SUCCEEDED record so
 * the cumulative map, funding watermark and residuals continue from where the chain actually
 * is. If the intent is not yet published, we replay the cycle (pre-publish crash, safe).
 */
export async function reconcileCursor(
  adapter: ChainAdapter,
  store: StepStore,
): Promise<{ cursor: EpochCursor; recovered: boolean }> {
  const cursor = await readCursor(store);
  const last = await latestIntent(store);
  if (!last) return { cursor, recovered: false };
  const intent = last.intent;
  const next = parseIntRecordCursor(intent.nextCursor);
  if (!next || next.epochIndex <= cursor.epochIndex)
    return { cursor, recovered: false };
  const onchain = await adapter.getDistributorEpochRoot(intent.epochIndex);
  if (onchain === undefined || onchain !== intent.root)
    return { cursor, recovered: false };
  await store.put({
    cycleId: `${last.cycleId}~recovered`,
    job: "root-activate",
    status: "succeeded",
    inputHash: intent.contentHash,
    attempts: 1,
    atBlock: next.finalizedBlock,
    detail: intent.nextCursor,
    updatedAt: BigInt(Date.now()),
  });
  return { cursor: next, recovered: true };
}

function parseIntRecordCursor(
  raw: string | undefined,
): EpochCursor | undefined {
  if (!raw) return undefined;
  try {
    const parsed = JSON.parse(raw) as EpochCursor;
    return typeof parsed.epochIndex === "number" &&
      typeof parsed.fundedUpToBlock === "number"
      ? parsed
      : undefined;
  } catch {
    return undefined;
  }
}

/**
 * `funding-reconcile`: build this epoch's funding ledger from `RewardsDeposited` logs above
 * the `fundedUpToBlock` watermark — deposits at <= watermark were already lumped into a
 * published epoch and must never be lumped again. Cursor drift from a lost activation record
 * is repaired up-front by `reconcileCursor`, so the window is always anchored to the true
 * published frontier (D030 exactly-once).
 */
export async function runFunding(
  adapter: ChainAdapter,
  store: StepStore,
  ctx: CycleContext,
): Promise<StepOutcome> {
  const tip = (await adapter.getTip())?.number ?? 0;
  const raw = await adapter.getRewardsDeposited(
    ctx.cursor.fundedUpToBlock + 1,
    tip,
  );
  ctx.deposits = raw;
  ctx.fundingTip = tip;

  const perToken = new Map<Hex, bigint>();
  for (const d of raw)
    perToken.set(d.token, (perToken.get(d.token) ?? 0n) + d.amount);

  const funded = new Map<Hex, bigint>();
  for (const [token, amount] of perToken) {
    if (amount > 0n) funded.set(token, amount);
  }
  ctx.funded = funded;

  const hash = inputHash({
    window: [ctx.cursor.fundedUpToBlock + 1, tip],
    deposits: raw.map(
      (d) => `${d.blockNumber}:${d.token}:${d.amount.toString()}`,
    ),
  });
  const detail = `${funded.size} assets funded (${raw.length} deposits since ${ctx.cursor.fundedUpToBlock + 1})`;
  return ok(hash, { atBlock: tip, detail, inputHash: hash });
}

/** `snapshot-request`: confirm + derive holder balances at a finalized block. */
export async function runSnapshot(
  indexer: Indexer,
  store: StepStore,
  ctx: CycleContext,
): Promise<StepOutcome> {
  const snapshot = await indexer.snapshot();
  ctx.snapshot = snapshot;
  const hash = inputHash({
    block: snapshot.block.number,
    hash: snapshot.block.hash,
  });
  const reason = await resumeReason(
    store,
    "snapshot-request",
    hash,
    async () => true,
  );
  return reason
    ? skip(reason, hash)
    : ok(hash, {
        atBlock: snapshot.block.number,
        detail: `${snapshot.eligibility.wallets.length} eligible wallets`,
        inputHash: hash,
      });
}

/** `tree-build`: allocate, merge cumulative, build tree + manifest, hard-gated (D029). */
export async function runTreeBuild(
  indexer: Indexer,
  adapter: ChainAdapter,
  config: KeeperConfig,
  store: StepStore,
  ctx: CycleContext,
): Promise<StepOutcome> {
  const count = await adapter.getDistributorEpochCount();
  const frontier = count - 1;
  if (frontier > ctx.cursor.epochIndex) {
    const last = await latestIntent(store);
    const covered = last !== undefined && last.intent.epochIndex >= frontier;
    if (!covered) {
      return fail(
        `cursor drift: onchain frontier ${frontier} exceeds recorded ${ctx.cursor.epochIndex} with no covering intent (operator recovery required)`,
      );
    }
  }

  const funded = ctx.funded ?? new Map<Hex, bigint>();
  ctx.funded = funded;

  const candidates = new Set<Hex>([
    ...funded.keys(),
    ...(Object.keys(ctx.cursor.residual) as Hex[]),
  ]);
  const vaultBalances = new Map<Hex, bigint>();
  for (const token of candidates)
    vaultBalances.set(token, await adapter.getVaultBalance(token));

  const tree = await treeBuild(
    indexer,
    adapter,
    config,
    ctx.cursor,
    funded,
    vaultBalances,
  );
  if (tree.skipped) return skip(tree.reason ?? "skipped");
  const epoch = tree.epoch!;
  ctx.epoch = epoch;
  ctx.assets = tree.assets;
  const hash = epoch.manifest.contentHash;
  return ok(hash, {
    atBlock: epoch.snapshot.block.number,
    detail: `${epoch.wallets.length} leaves, ${tree.assets.length} assets`,
    inputHash: hash,
  });
}

/** `manifest-validate`: re-gate the root against funding, the epoch target, and the content hash. */
export async function runManifestValidate(
  adapter: ChainAdapter,
  ctx: CycleContext,
): Promise<StepOutcome> {
  const epoch = ctx.epoch;
  if (!epoch) return skip("nothing to validate");
  const expected = await adapter.getDistributorEpochCount();
  const errors = manifestValidate(epoch, expected);
  return errors.length === 0
    ? ok(epoch.manifest.contentHash, {
        detail: `root ${epoch.root.slice(0, 10)}… targets epoch ${expected}`,
      })
    : fail(errors.join("; "));
}

/** `root-propose`: write the intent (incl. nextCursor) BEFORE any publish tx (write-ahead, D030). No write onchain. */
export async function runRootPropose(
  store: StepStore,
  ctx: CycleContext,
): Promise<StepOutcome> {
  const epoch = ctx.epoch;
  const funded = ctx.funded ?? new Map<Hex, bigint>();
  if (!epoch || !ctx.snapshot) return skip("no epoch to propose");
  const hash = epoch.manifest.contentHash;
  const nextCursor = cursorOf(
    epoch,
    ctx.snapshot,
    epoch.residual,
    ctx.fundingTip ?? epoch.snapshot.block.number,
  );
  const intent: ProposeIntent = {
    root: epoch.root,
    epochIndex: epoch.epochIndex,
    snapshotBlock: epoch.snapshot.block.number,
    contentHash: hash,
    funded: Object.fromEntries([...funded].map(([k, v]) => [k, v.toString()])),
    nextCursor: writeCursor(nextCursor),
  };
  void store;
  return ok(hash, { detail: JSON.stringify(intent) });
}

/** `root-activate`: publish the root exactly once; crash-safe forward-progress guard. */
export async function runRootActivate(
  adapter: ChainAdapter,
  store: StepStore,
  ctx: CycleContext,
): Promise<StepOutcome> {
  const epoch = ctx.epoch;
  if (!epoch || !ctx.snapshot) return skip("no epoch to activate");
  const hash = epoch.manifest.contentHash;
  const expected = epoch.epochIndex;
  const assets = ctx.assets ?? [];

  const reason = await resumeReason(store, "root-activate", hash, async () => {
    const onchain = await adapter.getDistributorEpochRoot(expected);
    return onchain !== undefined && onchain === epoch.root;
  });
  if (reason) return skip(reason, hash);

  // Per-asset cumulative totals (sum of every wallet's genesis-total entitlement), the
  // onchain monotonicity/funding commitment of D032, in the same order as `assets`.
  const cumulativeTotals = assets.map((asset) => {
    const byWallet = epoch.newCumulative[asset] ?? {};
    return Object.values(byWallet).reduce((a, b) => a + b, 0n);
  });

  await publishIfNeeded(
    adapter,
    epoch.root,
    assets,
    expected,
    cumulativeTotals,
    hash as Hex,
  );
  const next = cursorOf(
    epoch,
    ctx.snapshot,
    epoch.residual,
    ctx.fundingTip ?? epoch.snapshot.block.number,
  );
  ctx.cursor = next;
  return ok(hash, {
    atBlock: ctx.snapshot.block.number,
    detail: writeCursor(next),
    inputHash: hash,
  });
}

/**
 * `claim-relay` — $INDEX-style auto-delivery (D034). For every wallet in the activated epoch
 * that has a live `autoDelivery` opt-in in the EligibilityRegistry, the keeper batches
 * `RewardDistributor.claimForMany(epochIndex, deliveries[])` so rewards simply ARRIVE in the
 * entitled wallets — holders never claim. Structural guarantees enforced onchain, not here:
 * tokens can only land in the entitled wallet (leaf-bound), delivery requires the wallet's
 * signed opt-in + a live scoped attestation, and a failing entry is skipped, never fatal.
 *
 * The batch itself is a mainnet-gated write like every other keeper tx: it stays unarmed
 * until `venueArmed` and the attestation service are configured (D009/D025).
 */
export async function runClaimRelay(ctx: CycleContext): Promise<StepOutcome> {
  const epoch = ctx.epoch;
  if (!epoch) return skip("no epoch");
  if (!ctx.relayArmed) {
    return skip(
      "claim-relay unarmed: auto-delivery batches need the production attestation service + opt-in census (D034); armed via config after launch gates",
    );
  }
  const deliveries = ctx.deliveries ?? [];
  if (deliveries.length === 0) return skip("no opted-in wallets to deliver");
  const delivered = await ctxAdapterClaimForMany(ctx, epoch.epochIndex, deliveries);
  return ok(epoch.manifest.contentHash, {
    detail: `auto-delivered ${delivered}/${deliveries.length} opted-in wallets for epoch ${epoch.epochIndex}`,
  });
}

/** Indirection so tests can inject the adapter call; production wires ChainAdapter.claimForMany. */
async function ctxAdapterClaimForMany(
  ctx: CycleContext,
  epochIndex: number,
  deliveries: DeliveryEntry[],
): Promise<number> {
  if (!ctx.claimForMany) throw new Error("claimForMany adapter not wired");
  return ctx.claimForMany(epochIndex, deliveries);
}

/** One auto-delivery batch entry mirroring RewardDistributor.Delivery. */
export interface DeliveryEntry {
  wallet: Hex;
  cumulative: bigint[];
  proof: Hex[];
  attestationExpiry: bigint;
  attestationSignature: Hex;
}
