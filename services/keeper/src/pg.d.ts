/**
 * Minimal ambient types for the `pg` package. node-postgres ships no bundled types and
 * @types/pg is not vendored (pnpm add is out of scope for this change), so only the surface
 * `PostgresStepStore` touches is declared here. The build/typecheck stays green without any
 * dependency on the @types package.
 */
declare module "pg" {
  export interface QueryConfig {
    name?: string;
    text: string;
    values?: unknown[];
  }

  export interface QueryResult<R = Record<string, unknown>> {
    command: string;
    rowCount: number | null;
    rows: R[];
  }

  export class Client {
    constructor(config: Record<string, unknown>);
    connect(): Promise<void>;
    end(): Promise<void>;
    query<R = Record<string, unknown>>(
      config: QueryConfig,
    ): Promise<QueryResult<R>>;
  }

  export class PoolClient {
    query<R = Record<string, unknown>>(
      config: QueryConfig,
    ): Promise<QueryResult<R>>;
    release(err?: Error): void;
  }

  export class Pool {
    constructor(config?: Record<string, unknown>);
    query<R = Record<string, unknown>>(
      config: QueryConfig,
    ): Promise<QueryResult<R>>;
    connect(): Promise<PoolClient>;
    end(): Promise<void>;
  }
}
