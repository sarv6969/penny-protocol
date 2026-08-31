import type { Hex } from "viem";
import { CORE_JOB_ORDER, type JobName } from "./jobs.js";

/**
 * Keeper configuration. Contract addresses are HUMAN_INPUT — they are not onchain-derived
 * and never fabricated; a config missing them is invalid. `rpcUrl` unset keeps the top of the
 * rail un-armed (D009). Tests build explicit configs against `FakeChain`.
 */
export interface AdapterAddresses {
  rewardVault: Hex;
  feeCollector: Hex;
  basketBuyer: Hex;
  distributor: Hex;
  penny: Hex;
}

export interface KeeperConfig {
  chainId: number;
  /** Sequence of jobs per cycle. Defaults to `JOB_ORDER` when omitted. */
  jobs: JobName[];
  /** How far behind the confirmed cursor the indexer re-scans each cycle so reorgs roll back. */
  rescanWindow: number;
  /**
   * The vault-balance feed used by `basket-purchase` / `funding-reconcile`. Funding this cycle
   * is `purchaseDeposits[asset] + priorResidual[asset]` — leftover dust from the previous
   * epoch is re-absorbed before the next distribution (reward-accounting.md "Dust rule").
   */
  minSweepWei: bigint;
  eligibilityThreshold: bigint;
  /**
   * Whether a verified liquidity venue adapter is configured. `false` (default) fails
   * `basket-purchase` fail-closed (NO_GO_LIQUIDITY) — the mainnet gate (architecture.md).
   */
  venueArmed: boolean;
  /** Protocol addresses excluded from eligibility (D028). Sorted for deterministic inputHash. */
  excluded: Hex[];
  addresses: AdapterAddresses;
  rpcUrl?: string;
}

/** Verified-manifest-driven defaults; caller must supply the HUMAN_INPUT deployment block. */
export const DEFAULT_JOBS: readonly JobName[] = CORE_JOB_ORDER;

export function validateConfig(config: KeeperConfig): string[] {
  const errors: string[] = [];
  if (config.chainId !== 4663 && config.chainId !== 46630) {
    errors.push(
      `unrecognized chainId ${config.chainId} (expected 4663 mainnet / 46630 testnet)`,
    );
  }
  if (config.jobs.length === 0) errors.push("jobs order is empty");
  if (config.rescanWindow < 0) errors.push("rescanWindow must be >= 0");
  if (config.minSweepWei < 0n) errors.push("minSweepWei must be >= 0");
  for (const key of Object.keys(
    config.addresses,
  ) as (keyof AdapterAddresses)[]) {
    if (!config.addresses[key]) errors.push(`missing address: ${key}`);
  }
  const seen = new Set<string>();
  for (const a of config.excluded) {
    if (seen.has(a)) errors.push(`duplicate excluded address ${a}`);
    seen.add(a);
  }
  if (config.excluded.some((a) => a !== a.toLowerCase())) {
    errors.push("excluded addresses must be lowercase");
  }
  if (!config.rpcUrl)
    errors.push("rpcUrl unset — keeper is un-armed (mainnet gate D009)");
  return errors;
}
