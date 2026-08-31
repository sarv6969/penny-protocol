import { test } from "node:test";
import assert from "node:assert/strict";
import type { Hex } from "viem";
import { PurchaseMachine, funding } from "../src/index.js";
import { T1, T2, harness, seedChain } from "./harness.js";

const MIN_SWEEP = 1n * 10n ** 18n;

test("basket-purchase no-ops when the collector tank is below min-sweep", async () => {
  const h = harness({ minSweepWei: MIN_SWEEP });
  seedChain(h.chain, h.config.rescanWindow, 0n);
  const machine = new PurchaseMachine(h.chain, h.config);
  const { collectorWeth, canSweep } = await machine.inspect();
  assert.equal(collectorWeth, 0n);
  assert.equal(canSweep, false);

  const out = await machine.purchase(0);
  assert.equal(out.reason, "below-min-sweep");
  assert.equal(out.sweptWei, 0n);
  assert.equal(out.deposits.length, 0);
});

test("sweep drains the collector, triggers the purchase, and the second call is a no-op", async () => {
  const h = harness({ minSweepWei: MIN_SWEEP });
  h.chain.provisionRewardToken(T1);
  h.chain.provisionRewardToken(T2);
  seedChain(h.chain, h.config.rescanWindow, 60n * 10n ** 18n);
  const machine = new PurchaseMachine(h.chain, h.config);

  const first = await machine.purchase(0);
  assert.equal(first.reason, "swept");
  assert.equal(first.sweptWei, 60n * 10n ** 18n);
  assert.equal(first.spentWei, 60n * 10n ** 18n);
  assert.equal(await h.chain.getFeeCollectorWeth(), 0n);
  // one deposit per reward token, half the spend each
  assert.equal(first.deposits.length, 2);
  assert.deepEqual(
    first.deposits.map((d) => d.token),
    [T1, T2],
  );
  assert.equal(
    first.deposits.map((d) => d.amount).every((a) => a === 30n * 10n ** 18n),
    true,
  );
  assert.equal(await h.chain.getVaultBalance(T1), 30n * 10n ** 18n);

  // tank is drained: second purchase is a no-op (idempotency across halves of a cycle)
  const second = await machine.purchase(0);
  assert.equal(second.reason, "below-min-sweep");
  assert.equal(first.deposits.length + second.deposits.length, 2);
});

test("funding folds prior residuals back in before the next distribution (D029)", () => {
  const deposits = [
    { blockNumber: 5, token: T1 as Hex, amount: 30n, purchaseIndex: 1 },
    { blockNumber: 5, token: T2 as Hex, amount: 30n, purchaseIndex: 1 },
  ];
  const residual = new Map<string, bigint>([[T1, 2n]]);
  const out = funding(deposits, residual as ReadonlyMap<Hex, bigint>);
  assert.equal(out.perAsset.get(T1), 30n);
  assert.equal(out.priorResidual.get(T1), 2n);
  assert.equal(out.fundedTotals.get(T1), 32n);
  assert.equal(out.fundedTotals.get(T2), 30n);
});
