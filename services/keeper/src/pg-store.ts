import type { Client, Pool, PoolClient } from "pg";
import type { JobName } from "./jobs.js";
import {
  stepId,
  type StepRecord,
  type StepStore,
  type StepStatus,
} from "./state.js";

/**
 * Postgres-backed `StepStore` (D030), matching the `StepStore` interface from state.ts. Single
 * table holding the idempotency ledger keyed by `${cycleId}:${job}` plus a single-row counter
 * table for cycle-id allocation. Operator DDL:
 *
 *   create table if not exists step_records (
 *     step_id     text primary key,
 *     cycle_id    text not null,
 *     job         text not null,
 *     status      text not null,
 *     input_hash  text,
 *     attempts    integer not null default 0,
 *     at_block    integer,
 *     detail      text,
 *     last_error  text,
 *     updated_at  numeric not null
 *   );
 *   create index if not exists step_records_job_updated
 *     on step_records (job, updated_at desc);
 *
 *   create table if not exists journals (
 *     id    integer primary key check (id = 1),
 *     cycle integer not null
 *   );
 *   insert into journals (id, cycle) values (1, 0)
 *     on conflict (id) do nothing;
 *
 * BigInt `updatedAt`/cycle ids are persisted as numeric/integer (pg has no native bigint JS
 * type); reads convert the decimal string back to a BigInt. All statements are prepared (named
 * query configs). `put` and `nextCycleId` each run inside one transaction; `nextCycleId` is a
 * locked single-row bump so concurrent keeper processes never double-allocate a cycle id.
 *
 * A `Pool` (and optionally a dedicated `Client` for transactions) is injected via the
 * constructor so tests can drive it without a live database.
 */
interface StepRow {
  step_id: string;
  cycle_id: string;
  job: string;
  status: string;
  input_hash: string | null;
  attempts: number;
  at_block: number | null;
  detail: string | null;
  last_error: string | null;
  updated_at: string;
}

const STEP_COLUMNS =
  "step_id, cycle_id, job, status, input_hash, attempts, at_block, detail, last_error, updated_at";

const STEP_GET = {
  name: "keeper_step_get",
  text: `select ${STEP_COLUMNS} from step_records where step_id = $1`,
} as const;

const STEP_PUT = {
  name: "keeper_step_put",
  text: `insert into step_records (${STEP_COLUMNS}) values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
on conflict (step_id) do update set
  cycle_id = excluded.cycle_id,
  job = excluded.job,
  status = excluded.status,
  input_hash = excluded.input_hash,
  attempts = excluded.attempts,
  at_block = excluded.at_block,
  detail = excluded.detail,
  last_error = excluded.last_error,
  updated_at = excluded.updated_at`,
} as const;

const STEP_HISTORY = {
  name: "keeper_step_history",
  text: `select ${STEP_COLUMNS} from step_records where job = $1 order by updated_at desc, cycle_id desc`,
} as const;

const STEP_DELETE = {
  name: "keeper_step_delete",
  text: "delete from step_records where step_id = $1",
} as const;

const CYCLE_NEXT = {
  name: "keeper_cycle_next",
  text: "update journals set cycle = cycle + 1 where id = 1 returning cycle",
} as const;

const BEGIN = { name: "keeper_txn_begin", text: "begin" } as const;
const COMMIT = { name: "keeper_txn_commit", text: "commit" } as const;
const ROLLBACK = { name: "keeper_txn_rollback", text: "rollback" } as const;

export class PostgresStepStore implements StepStore {
  private readonly pool: Pool;
  private readonly client: Client | undefined;

  constructor(pool: Pool, client?: Client) {
    this.pool = pool;
    this.client = client;
  }

  async get(id: string): Promise<StepRecord | undefined> {
    const { rows } = await this.pool.query<StepRow>({
      ...STEP_GET,
      values: [id],
    });
    const row = rows[0];
    if (row === undefined) return undefined;
    return this.mapRow(row);
  }

  async put(record: StepRecord): Promise<void> {
    await this.withConnection(async (conn) => {
      await conn.query(BEGIN);
      try {
        await conn.query({
          ...STEP_PUT,
          values: [
            stepId(record.cycleId, record.job),
            record.cycleId,
            record.job,
            record.status,
            record.inputHash ?? null,
            record.attempts,
            record.atBlock ?? null,
            record.detail ?? null,
            record.lastError ?? null,
            record.updatedAt.toString(),
          ],
        });
        await conn.query(COMMIT);
      } catch (error) {
        await conn.query(ROLLBACK).catch(() => undefined);
        throw error;
      }
    });
  }

  async history(job: JobName): Promise<StepRecord[]> {
    const { rows } = await this.pool.query<StepRow>({
      ...STEP_HISTORY,
      values: [job],
    });
    return rows.map((row) => this.mapRow(row));
  }

  async delete(id: string): Promise<void> {
    await this.pool.query({ ...STEP_DELETE, values: [id] });
  }

  async nextCycleId(): Promise<string> {
    let next = 0;
    await this.withConnection(async (conn) => {
      await conn.query(BEGIN);
      try {
        const { rows } = await conn.query<{ cycle: number }>(CYCLE_NEXT);
        next = rows[0]?.cycle ?? 0;
        await conn.query(COMMIT);
      } catch (error) {
        await conn.query(ROLLBACK).catch(() => undefined);
        throw error;
      }
    });
    return `c${next}`;
  }

  /**
   * Run `fn` on the injected Client when present, else on a pooled connection (checked out for
   * the transaction and released afterwards). Multi-statement work must stay on one connection.
   */
  private async withConnection<T>(
    fn: (conn: Client | PoolClient) => Promise<T>,
  ): Promise<T> {
    if (this.client !== undefined) return fn(this.client);
    const conn = await this.pool.connect();
    try {
      return await fn(conn);
    } finally {
      conn.release();
    }
  }

  private mapRow(row: StepRow): StepRecord {
    const record: StepRecord = {
      cycleId: row.cycle_id,
      job: row.job as JobName,
      status: row.status as StepStatus,
      attempts: row.attempts,
      updatedAt: BigInt(row.updated_at),
    };
    if (row.input_hash !== null) record.inputHash = row.input_hash;
    if (row.at_block !== null) record.atBlock = row.at_block;
    if (row.detail !== null) record.detail = row.detail;
    if (row.last_error !== null) record.lastError = row.last_error;
    return record;
  }
}
