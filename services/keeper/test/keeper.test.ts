import assert from "node:assert/strict";
import test from "node:test";
import type { Hex } from "viem";
import { readCursor, stepId } from "../src/index.js";
import { harness, seedChain, A, B, C, DEPTH, T1, T2 } from "./harness.js";

const E18 = 10n ** 18n;
const WALLET = 120_000n * E18; // each holder's PENNY balance (> 100k threshold, equal weights)
const FOREIGN_ROOT: Hex = ("0x" + "ab".repeat(32)) as Hex;

test("a cycle fails closed at basket-purchase when the venue is unarmed", async () => {
  const h = harness();
  h.config.venueArmed = false;
  seedChain(h.chain, DEPTH, 60n * E18);
  const report = await h.keeper.runCycle();
  assert.equal(report.status, "failed");
  assert.equal(report.failingJob, "basket-purchase");
  assert.ok(
    report.steps.some(
      (s) => s.job === "basket-purchase" && s.status === "failed",
    ),
  );
  assert.equal(await h.chain.getDistributorEpochCount(), 0);
});

test("progressive cycles publish each funded epoch exactly once and the cursor advances monotonically", async () => {
  const h = harness();
  h.chain.provisionRewardToken(T1);
  h.chain.provisionRewardToken(T2);
  seedChain(h.chain, DEPTH, 60n * E18);

  // c1: funds the whole tank, publishes epoch 0, watermark advances to the sweep tip (4).
  const r1 = await h.keeper.runCycle();
  assert.equal(r1.status, "ok");
  assert.ok(
    r1.steps.find((s) => s.job === "root-activate")?.status === "succeeded",
  );
  assert.equal(await h.chain.getDistributorEpochCount(), 1);

  const cursor1 = await readCursor(h.stepStore);
  assert.equal(cursor1.epochIndex, 0);
  assert.equal(cursor1.finalizedBlock, 2);
  assert.equal(cursor1.fundedUpToBlock, 4);
  assert.equal(cursor1.cumulative[T1]![A], "15000000000000000000");
  assert.equal(cursor1.cumulative[T2]![B], "15000000000000000000");

  // c2: nothing changed — the whole epoch path must skip, the onchain frontier must not move.
  const r2 = await h.keeper.runCycle();
  assert.equal(r2.status, "ok");
  assert.ok(r2.steps.find((s) => s.job === "tree-build")?.status === "skipped");
  assert.equal(await h.chain.getDistributorEpochCount(), 1);
  assert.equal((await readCursor(h.stepStore)).epochIndex, 0);

  // c3: a new wallet crosses the threshold and new fees fund the next epoch.
  h.chain.mintPENNY(C, WALLET); // block 4 (<= confirmed at tip 6)
  h.chain.tick();
  h.chain.tick();
  h.chain.feedFees(90n * E18);
  const r3 = await h.keeper.runCycle();
  assert.equal(r3.status, "ok");
  assert.ok(
    r3.steps.find((s) => s.job === "root-activate")?.status === "succeeded",
  );
  assert.equal(await h.chain.getDistributorEpochCount(), 2);

  const cursor2 = await readCursor(h.stepStore);
  assert.equal(cursor2.epochIndex, 1);
  assert.equal(cursor2.finalizedBlock, 4);
  assert.equal(cursor2.fundedUpToBlock, 6);
  // 45e18 split three ways (equal 120k weights): A/B/C each +15 -> A 30, C 15.
  assert.equal(cursor2.cumulative[T1]![A], "30000000000000000000");
  assert.equal(cursor2.cumulative[T1]![C], "15000000000000000000");
  assert.ok(
    BigInt(cursor2.cumulative[T1]![A]!) > BigInt(cursor1.cumulative[T1]![A]!),
  );
  assert.notEqual(cursor2.root, cursor1.root);
});

test("crash-recovery warms the cursor from the intent and continues without double-publishing", async () => {
  const h = harness();
  h.chain.provisionRewardToken(T1);
  h.chain.provisionRewardToken(T2);
  seedChain(h.chain, DEPTH, 60n * E18);
  await h.keeper.runCycle(); // epoch 0

  // Feed a second epoch (C eligible, 90e18) and publish it — then lose the activation record.
  h.chain.mintPENNY(C, WALLET);
  h.chain.tick();
  h.chain.tick();
  h.chain.feedFees(90n * E18);
  const r2 = await h.keeper.runCycle();
  assert.equal(r2.status, "ok");
  assert.equal(await h.chain.getDistributorEpochCount(), 2);
  await h.stepStore.delete(stepId(r2.cycleId, "root-activate"));

  // c3: reconcile sees the frontier intent already published onchain, restores the cursor
  // (cumulative incl. C, watermark 6) and skips the now-empty funding window — no epoch 2.
  const r3 = await h.keeper.runCycle();
  assert.equal(r3.status, "ok");
  assert.ok(r3.steps.find((s) => s.job === "tree-build")?.status === "skipped");
  assert.equal(await h.chain.getDistributorEpochCount(), 2);
  const recoveredRecord = await h.stepStore.get(
    stepId(`${r2.cycleId}~recovered`, "root-activate"),
  );
  assert.ok(recoveredRecord?.status === "succeeded");
  const cursor2 = await readCursor(h.stepStore);
  assert.equal(cursor2.epochIndex, 1);
  assert.equal(cursor2.fundedUpToBlock, 6);
  assert.equal(cursor2.cumulative[T1]![A], "30000000000000000000");
  assert.equal(cursor2.cumulative[T1]![C], "15000000000000000000");

  // c4: new funding builds the NEXT epoch on the restored cumulative map.
  h.chain.tick();
  h.chain.tick();
  h.chain.feedFees(60n * E18);
  const r4 = await h.keeper.runCycle();
  assert.equal(r4.status, "ok");
  assert.equal(await h.chain.getDistributorEpochCount(), 3);
  const cursor3 = await readCursor(h.stepStore);
  assert.equal(cursor3.epochIndex, 2);
  assert.equal(cursor3.finalizedBlock, 6);
  assert.equal(cursor3.fundedUpToBlock, 8);
  // A had 30; + 10 = 40. C had 15; + 10 = 25.
  assert.equal(cursor3.cumulative[T1]![A], "40000000000000000000");
  assert.equal(cursor3.cumulative[T1]![C], "25000000000000000000");
  assert.ok(
    BigInt(cursor3.cumulative[T1]![A]!) > BigInt(cursor2.cumulative[T1]![A]!),
  );
});

test("an unexplained onchain frontier ahead of the cursor fails closed instead of double-funding", async () => {
  const h = harness();
  h.chain.provisionRewardToken(T1);
  h.chain.provisionRewardToken(T2);
  seedChain(h.chain, DEPTH, 60n * E18);
  await h.keeper.runCycle();
  assert.equal(await h.chain.getDistributorEpochCount(), 1);

  // An epoch is activated onchain with every ledger record lost (no intent to warm-start from).
  await h.chain.publishEpoch(FOREIGN_ROOT, [T1, T2]);
  assert.equal(await h.chain.getDistributorEpochCount(), 2);

  // Fresh funding arrives for the dangerous window: the build must refuse the gap.
  h.chain.tick();
  h.chain.tick();
  h.chain.feedFees(60n * E18);

  const r3 = await h.keeper.runCycle();
  assert.equal(r3.status, "failed");
  assert.equal(r3.failingJob, "tree-build");
  assert.ok(
    r3.steps
      .find((s) => s.job === "tree-build")
      ?.lastError?.includes("cursor drift"),
  );
  assert.equal(await h.chain.getDistributorEpochCount(), 2);
});
