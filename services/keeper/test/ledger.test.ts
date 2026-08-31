import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { Keeper, DurableStepStore, readCursor, stepId } from "../src/index.js";
import { harness, seedChain, A, C, DEPTH, T1, T2 } from "./harness.js";

const E18 = 10n ** 18n;
const WALLET = 120_000n * E18;

function tempLedger(): { file: string; dir: string } {
  const dir = mkdtempSync(join(tmpdir(), "penny-ledger-"));
  return { file: join(dir, "ledger.jsonl"), dir };
}

test("durable store replays records, tombstones and cycle ids across a restart", async (t) => {
  const { file, dir } = tempLedger();
  t.after(() => rmSync(dir, { recursive: true, force: true }));

  const s1 = new DurableStepStore(file);
  await s1.put({
    cycleId: "c1",
    job: "root-propose",
    status: "succeeded",
    inputHash: "0x" + "ab".repeat(32),
    attempts: 1,
    updatedAt: 100n,
  });
  await s1.put({
    cycleId: "c2",
    job: "root-activate",
    status: "succeeded",
    attempts: 1,
    updatedAt: 200n,
  });
  await s1.delete(stepId("c1", "root-propose"));
  assert.equal(await s1.nextCycleId(), "c3");
  s1.close();

  // Restart: the tombstone must have removed c1's record, c2 must survive, ids continue after c2.
  const s2 = new DurableStepStore(file);
  assert.equal(
    (await s2.get(stepId("c2", "root-activate")))?.status,
    "succeeded",
  );
  assert.equal(await s2.get(stepId("c1", "root-propose")), undefined);
  assert.deepEqual(
    (await s2.history("root-activate")).map((r) => r.cycleId),
    ["c2"],
  );
  assert.equal(await s2.nextCycleId(), "c3");
  s2.close();
});

test("warm-start recovery survives a full process restart on the durable ledger", async (t) => {
  const { file, dir } = tempLedger();
  t.after(() => rmSync(dir, { recursive: true, force: true }));

  const h = harness();
  h.chain.provisionRewardToken(T1);
  h.chain.provisionRewardToken(T2);
  seedChain(h.chain, DEPTH, 60n * E18);

  // Session 1: publish epoch 0, shut down cleanly.
  const store1 = new DurableStepStore(file);
  const keeper1 = new Keeper({
    adapter: h.chain,
    indexer: h.indexer,
    store: store1,
    config: h.config,
  });
  await keeper1.runCycle();
  store1.close();
  assert.equal(await h.chain.getDistributorEpochCount(), 1);

  // Session 2: restart from the log, feed + publish epoch 1 (C becomes eligible), then a crash
  // takes the process before the activation record's fsync… simulated by deleting the record
  // after restart (the intent from root-propose is still durably on disk).
  const store2 = new DurableStepStore(file);
  const keeper2 = new Keeper({
    adapter: h.chain,
    indexer: h.indexer,
    store: store2,
    config: h.config,
  });
  h.chain.mintPENNY(C, WALLET);
  h.chain.tick();
  h.chain.tick();
  h.chain.feedFees(90n * E18);
  const r2 = await keeper2.runCycle();
  assert.equal(r2.status, "ok");
  assert.equal(await h.chain.getDistributorEpochCount(), 2);
  store2.close();

  const store3 = new DurableStepStore(file);
  await store3.delete(stepId(r2.cycleId, "root-activate"));
  const keeper3 = new Keeper({
    adapter: h.chain,
    indexer: h.indexer,
    store: store3,
    config: h.config,
  });

  // Session 3 (recovery): the durable intent is replayed, the onchain root matches it, so the
  // cursor warms up from the intent's nextCursor. No re-publish, no double-funding.
  const r3 = await keeper3.runCycle();
  assert.equal(r3.status, "ok");
  assert.ok(r3.steps.find((s) => s.job === "tree-build")?.status === "skipped");
  assert.equal(await h.chain.getDistributorEpochCount(), 2);
  store3.close();

  // Restart yet again: the synthesized recovery record and the warm-started cursor are durable.
  const store4 = new DurableStepStore(file);
  const cursor2 = await readCursor(store4);
  assert.equal(cursor2.epochIndex, 1);
  assert.equal(cursor2.fundedUpToBlock, 6);
  assert.equal(cursor2.cumulative[T1]![A], "30000000000000000000");
  assert.equal(cursor2.cumulative[T1]![C], "15000000000000000000");
  const recovered = await store4.get(
    stepId(`${r2.cycleId}~recovered`, "root-activate"),
  );
  assert.ok(recovered?.status === "succeeded");

  // Session 4: new funding builds epoch 2 on the restored cumulative map.
  const keeper4 = new Keeper({
    adapter: h.chain,
    indexer: h.indexer,
    store: store4,
    config: h.config,
  });
  h.chain.tick();
  h.chain.tick();
  h.chain.feedFees(60n * E18);
  const r4 = await keeper4.runCycle();
  assert.equal(r4.status, "ok");
  assert.equal(await h.chain.getDistributorEpochCount(), 3);
  const cursor3 = await readCursor(store4);
  assert.equal(cursor3.epochIndex, 2);
  assert.equal(cursor3.fundedUpToBlock, 8);
  assert.equal(cursor3.cumulative[T1]![A], "40000000000000000000");
  assert.equal(cursor3.cumulative[T1]![C], "25000000000000000000");
  store4.close();
});
