/**
 * Keeper job taxonomy (Phase 9). Jobs run in `config.jobs` order each cycle; every job is
 * idempotent and records a `StepRecord` in the `StepStore` keyed `${cycleId}:${job}`.
 * A job is SKIPped when a prior SUCCEEDED record exists for the same inputHash and the
 * onchain forward-progress marker is already satisfied (see state.ts / pipeline.ts).
 */
export type JobName =
  | "fee-monitor"
  | "quote-collect"
  | "oracle-session-check"
  | "basket-purchase"
  | "funding-reconcile"
  | "ingest"
  | "snapshot-request"
  | "tree-build"
  | "manifest-validate"
  | "root-propose"
  | "root-activate"
  | "claim-relay"
  | "monitoring";

/** Default cycle order. `root-activate` is the epoch publish; `claim-relay` is opt-in only. */
export const JOB_NAMES: JobName[] = [
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
];

/** The minimum job graph every cycle must run, in dependency order. */
export const CORE_JOB_ORDER: readonly JobName[] = [
  "basket-purchase",
  "funding-reconcile",
  "ingest",
  "snapshot-request",
  "tree-build",
  "manifest-validate",
  "root-propose",
  "root-activate",
] as const;
