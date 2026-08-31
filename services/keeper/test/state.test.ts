import { test } from "node:test";
import assert from "node:assert/strict";
import { inputHash, MemoryStepStore, stepId } from "../src/index.js";
import { A, B, T1 } from "./harness.js";

test("inputHash is deterministic over bigints, nested objects and arrays", () => {
  const v1 = {
    asset: T1,
    threshold: 100_000n * 10n ** 18n,
    wallets: [A, B],
    shares: { [A]: 15n },
  };
  const v2 = {
    asset: T1,
    threshold: 100_000n * 10n ** 18n,
    wallets: [A, B],
    shares: { [A]: 15n },
  };
  assert.equal(inputHash(v1), inputHash(v2));

  const v3 = { ...v1, shares: { [A]: 16n } };
  assert.notEqual(inputHash(v1), inputHash(v3));

  // object key order must not matter (D029 canonical ordering)
  const v4 = {
    shares: { [A]: 15n },
    wallets: [A, B],
    threshold: 100_000n * 10n ** 18n,
    asset: T1,
  };
  assert.equal(inputHash(v1), inputHash(v4));
});

test("step store records, histories and cycle ids", async () => {
  const store = new MemoryStepStore();
  const c1 = await store.nextCycleId();
  const c2 = await store.nextCycleId();
  assert.equal(c1, "c1");
  assert.equal(c2, "c2");

  await store.put({
    cycleId: c1,
    job: "ingest",
    status: "succeeded",
    inputHash: "0xaaa",
    attempts: 1,
    updatedAt: 1n,
  });
  await store.put({
    cycleId: c2,
    job: "ingest",
    status: "succeeded",
    inputHash: "0xbbb",
    attempts: 1,
    updatedAt: 2n,
  });
  assert.equal((await store.get(stepId(c1, "ingest")))?.inputHash, "0xaaa");
  const history = await store.history("ingest");
  assert.deepEqual(
    history.map((r) => r.inputHash),
    ["0xbbb", "0xaaa"],
  );
});
