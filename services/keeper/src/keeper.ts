import type { Indexer } from "@penny/indexer";
import type { ChainAdapter } from "./chain.js";
import type { KeeperConfig } from "./config.js";
import type { JobName } from "./jobs.js";
import type { Metrics } from "./monitor.js";
import type { StepRecord, StepStore } from "./state.js";
import {
  readCursor,
  reconcileCursor,
  runBasketPurchase,
  runClaimRelay,
  runFunding,
  runIngest,
  runManifestValidate,
  runRootActivate,
  runRootPropose,
  runSnapshot,
  runTreeBuild,
  type CycleContext,
  type StepOutcome,
} from "./steps.js";

export interface KeeperSpec {
  adapter: ChainAdapter;
  indexer: Indexer;
  store: StepStore;
  config: KeeperConfig;
  metrics?: Metrics;
}

export interface CycleReport {
  cycleId: string;
  status: "ok" | "failed";
  failingJob?: JobName;
  steps: StepRecord[];
}

const DONE: readonly JobName[] = [
  "fee-monitor",
  "quote-collect",
  "oracle-session-check",
  "basket-purchase",
  "funding-reconcile",
  "ingest",
  "snapshot-request",
  "tree-build",
  "manifest-validate",
  "root-propose",
  "root-activate",
  "claim-relay",
  "monitoring",
] as const;

/**
 * The idempotent keeper cycle (Phase 9). Each cycle runs `config.jobs` in order; every step is
 * persisted to the StepStore, deduplicated by inputHash + onchain forward-progress, and any
 * failure halts the cycle (fail-closed). Re-running a cycle after a crash is safe: publishes
 * are reconciled against the onchain epoch root before resending.
 */
export class Keeper {
  private readonly adapter: ChainAdapter;
  private readonly indexer: Indexer;
  private readonly store: StepStore;
  private readonly config: KeeperConfig;
  private readonly metrics: Metrics | undefined;

  constructor(spec: KeeperSpec) {
    this.adapter = spec.adapter;
    this.indexer = spec.indexer;
    this.store = spec.store;
    this.config = spec.config;
    this.metrics = spec.metrics;
  }

  async runCycle(): Promise<CycleReport> {
    const cycleId = await this.store.nextCycleId();
    const ctx: CycleContext = {
      cycleId,
      cursor: (await reconcileCursor(this.adapter, this.store)).cursor,
    };
    const steps: StepRecord[] = [];

    for (const job of this.config.jobs) {
      if (!(DONE as readonly string[]).includes(job)) {
        return this.report(
          cycleId,
          "failed",
          [
            ...steps,
            this.seal(
              ctx,
              job,
              { status: "failed", error: `unknown job ${job}` },
              cycleId,
            ),
          ],
          job,
          "unknown job",
        );
      }

      let outcome: StepOutcome;
      try {
        outcome = await this.run(job, ctx);
      } catch (error) {
        outcome = {
          status: "failed",
          error: error instanceof Error ? error.message : String(error),
        };
      }
      const step = this.seal(ctx, job, outcome, cycleId);
      steps.push(step);
      this.metrics?.record(step);

      if (outcome.status === "failed") {
        return this.report(cycleId, "failed", steps, job, outcome.error);
      }
    }

    const tip = await this.adapter.getTip();
    this.metrics?.heartbeat(cycleId, true, tip?.number);
    return { cycleId, status: "ok", steps };
  }

  private async run(job: JobName, ctx: CycleContext): Promise<StepOutcome> {
    switch (job) {
      case "ingest":
        return runIngest(
          this.indexer,
          this.adapter,
          this.config,
          this.store,
          ctx,
        );
      case "basket-purchase":
        return runBasketPurchase(this.adapter, this.config, this.store, ctx);
      case "funding-reconcile":
        return runFunding(this.adapter, this.store, ctx);
      case "snapshot-request":
        return runSnapshot(this.indexer, this.store, ctx);
      case "tree-build":
        return runTreeBuild(
          this.indexer,
          this.adapter,
          this.config,
          this.store,
          ctx,
        );
      case "manifest-validate":
        return runManifestValidate(this.adapter, ctx);
      case "root-propose":
        return runRootPropose(this.store, ctx);
      case "root-activate":
        return runRootActivate(this.adapter, this.store, ctx);
      case "claim-relay":
        return runClaimRelay(ctx);
      case "monitoring":
        return { status: "succeeded", detail: "metrics emitted" };
      default:
        return { status: "failed", error: `unhandled job ${job}` };
    }
  }

  private seal(
    ctx: CycleContext,
    job: JobName,
    outcome: StepOutcome,
    cycleId: string,
  ): StepRecord {
    const record: StepRecord = {
      cycleId,
      job,
      status: outcome.status,
      attempts: 1,
      updatedAt: BigInt(Date.now()),
    };
    if (outcome.inputHash !== undefined) record.inputHash = outcome.inputHash;
    if (outcome.atBlock !== undefined) record.atBlock = outcome.atBlock;
    if (outcome.detail !== undefined) record.detail = outcome.detail;
    if (outcome.error !== undefined) record.lastError = outcome.error;
    void this.store.put(record).catch(() => undefined);
    return record;
  }

  private report(
    cycleId: string,
    status: "ok" | "failed",
    steps: StepRecord[],
    failingJob?: JobName,
    error?: string,
  ): CycleReport {
    if (status === "failed") {
      this.metrics?.heartbeat(cycleId, false);
      void error;
    }
    const report: CycleReport = { cycleId, status, steps };
    if (failingJob !== undefined) report.failingJob = failingJob;
    return report;
  }
}
