import { Indexer, MemoryStore } from "@penny/indexer";
import type { Hex } from "viem";
import {
  Keeper,
  MemoryStepStore,
  validateConfig,
  type KeeperConfig,
  type StepStore,
} from "../src/index.js";
import { FakeChain } from "./fake.js";

export const THRESHOLD = 100_000n * 10n ** 18n;
export const A: Hex = "0x1111111111111111111111111111111111111111";
export const B: Hex = "0x2222222222222222222222222222222222222222";
export const C: Hex = "0x3333333333333333333333333333333333333333";
export const T1: Hex = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
export const T2: Hex = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";

export const DEPTH = 2;

export interface Harness {
  chain: FakeChain;
  indexer: Indexer;
  indexerStore: MemoryStore;
  stepStore: StepStore;
  keeper: Keeper;
  config: KeeperConfig;
}

export function harness(
  overrides: {
    depth?: number;
    threshold?: bigint;
    excluded?: string[];
    minSweepWei?: bigint;
    window?: number;
  } = {},
): Harness {
  const depth = overrides.depth ?? DEPTH;
  const chain = new FakeChain(depth);
  const indexerStore = new MemoryStore();
  const indexer = new Indexer(chain, indexerStore, {
    confirmationDepth: depth,
    threshold: overrides.threshold ?? THRESHOLD,
    excluded: new Set(overrides.excluded ?? []),
  });

  const config: KeeperConfig = {
    chainId: 4663,
    jobs: [
      "basket-purchase",
      "funding-reconcile",
      "ingest",
      "snapshot-request",
      "tree-build",
      "manifest-validate",
      "root-propose",
      "root-activate",
      "monitoring",
    ],
    rescanWindow: overrides.window ?? depth + 1,
    minSweepWei: overrides.minSweepWei ?? 1n * 10n ** 18n,
    eligibilityThreshold: overrides.threshold ?? THRESHOLD,
    excluded: (overrides.excluded ?? []).map((e) => e as Hex),
    venueArmed: true,
    addresses: {
      penny: "0x00000000000000000000000000000000000000a1",
      feeCollector: "0x00000000000000000000000000000000000000a2",
      basketBuyer: "0x00000000000000000000000000000000000000a3",
      rewardVault: "0x00000000000000000000000000000000000000a4",
      distributor: "0x00000000000000000000000000000000000000a5",
    } satisfies KeeperConfig["addresses"],
    rpcUrl: "https://rpc.test.fake",
  };
  const errors = validateConfig(config);
  if (errors.length > 0)
    throw new Error(`harness: invalid config: ${errors.join("; ")}`);

  const stepStore = new MemoryStepStore();
  const keeper = new Keeper({
    adapter: chain,
    indexer,
    store: stepStore,
    config,
  });
  return { chain, indexer, indexerStore, stepStore, keeper, config };
}

/**
 * Build a canonical chain the snapshot can certify:
 *  - blocks 1..(depth): scaffolding, no transfers;
 *  - block depth: mint A; block depth: mint B (mints target the same tip block; both land ≤
 *    `confirmed = tip - depth = depth`, so they certify instantly);
 *  - blocks depth+1..depth+2: tip scaffolding.
 * Fees are fed to the collector at the tip block. `wealth` is each wallet's PENNY balance —
 * must exceed the 100k eligibility threshold. Returns the confirmed block number.
 */
export function seedChain(
  chain: FakeChain,
  depth: number,
  fees: bigint,
  wealth: bigint = 120_000n * 10n ** 18n,
): { confirmed: number; tip: number } {
  for (let i = 0; i < depth; i++) chain.tick();
  chain.mintPENNY(A, wealth);
  chain.mintPENNY(B, wealth);
  chain.tick();
  chain.tick();
  chain.feedFees(fees);
  const tip = chain.tip();
  return { confirmed: tip - depth, tip };
}
