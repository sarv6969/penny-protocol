import { canonicalize } from "@penny/indexer";
import { keccak256, toHex } from "viem";
import type { JobName } from "./jobs.js";

/**
 * Idempotency ledger (D030). A cycle is a sequential pass over `config.jobs`; each step is
 * logged against `${cycleId}:${job}`. Two passes are deduplicated by `inputHash` — the
 * keccak of the job's canonicalized inputs (bigints as decimal strings, keys sorted, D029),
 * which is byte-identical across clean runs. Combined with an onchain forward-progress check
 * (e.g. `epochCount`/last published root for `root-propose`), a crash mid-step is recovered
 * on the next cycle without double-execution: the step either re-runs (no onchain effect yet)
 * or is recorded SUCCEEDED against the already-observed effect.
 */
export type StepStatus =
  "pending" | "running" | "succeeded" | "failed" | "skipped";

export interface StepRecord {
  cycleId: string;
  job: JobName;
  status: StepStatus;
  inputHash?: string;
  attempts: number;
  /** block number the step observed, when meaningful */
  atBlock?: number;
  lastError?: string;
  detail?: string;
  updatedAt: bigint;
}

export function stepId(cycleId: string, job: JobName): string {
  return `${cycleId}:${job}`;
}

export interface StepStore {
  get(id: string): Promise<StepRecord | undefined>;
  put(record: StepRecord): Promise<void>;
  /** Every record for a job across cycles, most recent first. */
  history(job: JobName): Promise<StepRecord[]>;
  nextCycleId(): Promise<string>;
  /** Remove a single record (ledger maintenance / crash-replay simulations). */
  delete(id: string): Promise<void>;
}

/**
 * In-memory StepStore (tests / build-time runs). The SQL-backed store (Postgres) is expected
 * to implement the same interface; nothing here depends on process-local state.
 */
export class MemoryStepStore implements StepStore {
  private records = new Map<string, StepRecord>();
  private counter = 0;

  async get(id: string): Promise<StepRecord | undefined> {
    return this.records.get(id);
  }

  async put(record: StepRecord): Promise<void> {
    this.records.set(stepId(record.cycleId, record.job), record);
  }

  async history(job: JobName): Promise<StepRecord[]> {
    const rows = [...this.records.values()].filter((r) => r.job === job);
    rows.sort((a, b) =>
      a.updatedAt === b.updatedAt
        ? a.cycleId.localeCompare(b.cycleId)
        : a.updatedAt > b.updatedAt
          ? -1
          : 1,
    );
    return rows;
  }

  async delete(id: string): Promise<void> {
    this.records.delete(id);
  }

  async nextCycleId(): Promise<string> {
    this.counter += 1;
    return `c${this.counter}`;
  }
}

/**
 * Keccak of the job's canonicalized inputs (D029). Two clean pipelines over identical data
 * MUST produce the same hash, so a SUCCEEDED record with the same hash authorizes a SKIP.
 */
export function inputHash(value: unknown): string {
  return keccak256(toHex(canonicalize(value)));
}
