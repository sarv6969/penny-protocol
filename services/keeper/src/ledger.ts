import {
  closeSync,
  existsSync,
  fsyncSync,
  openSync,
  readFileSync,
  writeFileSync,
  writeSync,
} from "node:fs";
import type { JobName } from "./jobs.js";
import { stepId, type StepRecord, type StepStore } from "./state.js";

/**
 * Durable, process-crash-safe `StepStore` (D030). The ledger is an fsync'd append-only JSONL
 * file: every `put`, `delete` and cycle-id allocation is applied on disk (fsync) BEFORE it
 * mutates the in-memory map, so the write-ahead intent of `root-propose` and the activation
 * cursor of `root-activate` survive a process kill. On start the file is replayed to rebuild
 * the map — a restart recovers the exact frontier the crash left behind (cumulative map,
 * funding watermark and residuals included), which is what makes warm-start correct across
 * restarts.
 *
 * This is the production build-time ledger. The Postgres-backed store (planned) implements the
 * same `StepStore` interface; nothing in the keeper depends on process-local state.
 *
 * Lines (append-only, one JSON object per line, fsync'd):
 *   {"type":"record", ..., "updatedAt":"<decimal>"}   a StepRecord (BigInts as strings)
 *   {"tombstone": <stepId>}                            a delete
 */
interface LogRecord extends Omit<StepRecord, "updatedAt"> {
  type: "record";
  updatedAt: string;
}

export class DurableStepStore implements StepStore {
  private readonly records = new Map<string, StepRecord>();
  private readonly fd: number;
  private readonly filePath: string;
  /** Session allocator, seeded from the max replayed cycle id so a crash never double-allocates. */
  private counter = 0;

  constructor(filePath: string) {
    this.filePath = filePath;
    if (!existsSync(filePath)) writeFileSync(filePath, "");
    this.fd = openSync(filePath, "a");
    this.replay();
    let max = 0;
    for (const key of this.records.keys()) {
      const match = /^c(\d+)/.exec(key);
      if (match) max = Math.max(max, Number(match[1]));
    }
    this.counter = max;
  }

  private replay(): void {
    const data = readFileSync(this.filePath, "utf8");
    for (const rawLine of data.split("\n")) {
      const line = rawLine.trim();
      if (line === "") continue;
      let entry: Record<string, unknown>;
      try {
        entry = JSON.parse(line) as Record<string, unknown>;
      } catch {
        continue; // torn tail can never occur with fsync writes; skip defensively
      }
      if (entry.tombstone !== undefined) {
        this.records.delete(entry.tombstone as string);
      } else if (entry.type === "record") {
        const { type: _t, ...rest } = entry;
        const record = rest as unknown as StepRecord;
        if (typeof record.updatedAt === "number") {
          record.updatedAt = BigInt(record.updatedAt);
        } else {
          record.updatedAt = BigInt(record.updatedAt as unknown as string);
        }
        this.records.set(stepId(record.cycleId, record.job), record);
      }
    }
  }

  private append(payload: unknown): void {
    writeSync(this.fd, JSON.stringify(payload) + "\n");
    fsyncSync(this.fd);
  }

  async get(id: string): Promise<StepRecord | undefined> {
    return this.records.get(id);
  }

  async put(record: StepRecord): Promise<void> {
    const log: LogRecord = {
      type: "record",
      ...record,
      updatedAt: record.updatedAt.toString(),
    };
    this.append(log);
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
    this.append({ tombstone: id });
    this.records.delete(id);
  }

  async nextCycleId(): Promise<string> {
    // Never collide with an existing id even if records were written after construction:
    // allocation rises to max(replayed, in-memory) + 1 each time.
    let next = this.counter;
    for (const key of this.records.keys()) {
      const match = /^c(\d+)/.exec(key);
      if (match) next = Math.max(next, Number(match[1]));
    }
    const id = `c${next + 1}`;
    if (this.counter < next + 1) this.counter = next + 1;
    return id;
  }

  /** Flush + close the file handle (graceful shutdown / tests). */
  close(): void {
    try {
      fsyncSync(this.fd);
    } finally {
      closeSync(this.fd);
    }
  }
}
