import assert from "node:assert/strict";
import test from "node:test";
import type { Hex } from "viem";
import {
  emptyCursor,
  ingestBatch,
  manifestValidate,
  publishIfNeeded,
  treeBuild,
} from "../src/index.js";
import { harness, seedChain, A, B, DEPTH, T1, T2 } from "./harness.js";

const E18 = 10n ** 18n;
const ROOT_LEAF: Hex = ("0x" + "11".repeat(32)) as Hex;

test("treeBuild manifests a reconcile-clean epoch that re-computes identically", async () => {
  const h = harness();
  h.chain.provisionRewardToken(T1);
  h.chain.provisionRewardToken(T2);
  seedChain(h.chain, DEPTH, 60n * E18);
  await ingestBatch(h.indexer, h.chain, h.config);

  const funded = new Map<Hex, bigint>([
    [T1, 30n * E18],
    [T2, 30n * E18],
  ]);
  const vault = new Map<Hex, bigint>(funded);
  const run = await treeBuild(
    h.indexer,
    h.chain,
    h.config,
    emptyCursor(),
    funded,
    vault,
  );
  assert.equal(run.skipped, false);
  const epoch = run.epoch!;

  assert.equal(epoch.epochIndex, 0);
  assert.deepEqual(run.assets, [T1, T2]); // canonical ascending address order
  assert.equal(epoch.distributedTotals[T1], 30n * E18);
  assert.equal(epoch.distributedTotals[T2], 30n * E18);
  assert.equal(epoch.newCumulative[T1]![A], 15n * E18);
  assert.equal(epoch.newCumulative[T1]![B], 15n * E18);
  assert.equal(epoch.reconcile.ok, true, epoch.reconcile.errors.join(";"));
  assert.deepEqual(manifestValidate(epoch, 0), []);

  // Determinism at the keeper boundary: identical inputs across runs give the same root +
  // contentHash (generatedAt lives in `meta`, outside the canonical payload).
  const again = await treeBuild(
    h.indexer,
    h.chain,
    h.config,
    emptyCursor(),
    new Map(funded),
    new Map(vault),
  );
  assert.equal(again.epoch!.manifest.contentHash, epoch.manifest.contentHash);
  assert.equal(again.epoch!.root, epoch.root);
});

test("manifestValidate flags epoch-index skew and contentHash tampering", async () => {
  const h = harness();
  h.chain.provisionRewardToken(T1);
  seedChain(h.chain, DEPTH, 60n * E18);
  await ingestBatch(h.indexer, h.chain, h.config);
  const funded = new Map<Hex, bigint>([
    [T1, 30n * E18],
    [T2, 30n * E18],
  ]);
  const run = await treeBuild(
    h.indexer,
    h.chain,
    h.config,
    emptyCursor(),
    funded,
    new Map(funded),
  );
  const epoch = run.epoch!;

  const skew = manifestValidate(epoch, 1);
  assert.ok(skew.some((e) => e.includes("epochIndex mismatch")));

  // A tampered canonical payload must no longer hash to the published contentHash.
  const payload = structuredClone(epoch.manifest.payload) as {
    epochIndex: number;
  };
  payload.epochIndex = 999;
  const tampered = { ...epoch, manifest: { ...epoch.manifest, payload } };
  const taint = manifestValidate(tampered, 0);
  assert.ok(taint.some((e) => e.includes("contentHash does not match")));
});

test("publishIfNeeded publishes exactly once, absorbs replays, and blocks foreign roots", async () => {
  const h = harness();
  h.chain.provisionRewardToken(T1);
  h.chain.provisionRewardToken(T2);
  seedChain(h.chain, DEPTH, 60n * E18);
  await ingestBatch(h.indexer, h.chain, h.config);
  const run = await treeBuild(
    h.indexer,
    h.chain,
    h.config,
    emptyCursor(),
    new Map([[T1, 30n * E18]]),
    new Map([[T1, 30n * E18]]),
  );
  const root = run.epoch!.root;
  const assets = [T1, T2];
  assert.equal(run.epoch!.epochIndex, 0);

  assert.equal(await h.chain.getDistributorEpochCount(), 0);
  const first = await publishIfNeeded(h.chain, root, assets, 0);
  assert.equal(first.published, true);
  assert.equal(await h.chain.getDistributorEpochRoot(0), root);
  assert.equal(await h.chain.getDistributorEpochCount(), 1);

  // Replay after a crash-between-tx-and-record: page existing root, no second tx.
  const replay = await publishIfNeeded(h.chain, root, assets, 0);
  assert.equal(replay.published, false);
  assert.equal(await h.chain.getDistributorEpochCount(), 1);

  // A foreign root one slot ahead (simulated concurrent/other keeper) must refuse the stale index.
  await h.chain.publishEpoch(ROOT_LEAF, [T1]);
  assert.equal(await h.chain.getDistributorEpochCount(), 2);
  await assert.rejects(
    () => publishIfNeeded(h.chain, root, assets, 1),
    (error: unknown) => (error as Error).message.includes("foreign epoch root"),
  );
});
