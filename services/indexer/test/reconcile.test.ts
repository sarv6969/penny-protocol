import assert from "node:assert/strict";
import { test } from "node:test";

import type { CumulativeByAsset } from "../src/cumulative.js";
import { reconcile } from "../src/reconcile.js";

const A = "0x" + "a".repeat(40);
const B = "0x" + "b".repeat(40);

function base(): Parameters<typeof reconcile>[0] {
  return {
    assets: [A, B],
    fundedTotals: { [A]: 100n, [B]: 50n },
    distributedTotals: { [A]: 100n, [B]: 50n },
    residuals: { [A]: 0n, [B]: 0n },
    vaultBalances: { [A]: 10_000n, [B]: 10_000n },
    cumulativePrior: {},
    cumulativeNew: {},
  };
}

test("reconcile passes a clean epoch", () => {
  const { ok, errors } = reconcile(base());
  assert.equal(ok, true);
  assert.deepEqual(errors, []);
});

test("reconcile fails when distributed + residual != funded", () => {
  const input = base();
  input.distributedTotals[A] = 99n;
  const { ok, errors } = reconcile(input);
  assert.equal(ok, false);
  assert.match(errors[0]!, /distributed\(99\) \+ residual\(0\) != funded\(100\)/);
});

test("reconcile fails on undeclared residual", () => {
  const input = base();
  input.residuals[A] = 1n;
  assert.equal(reconcile(input).ok, false);
});

test("reconcile fails when this epoch's payments exceed the funded vault", () => {
  const input = base();
  input.fundedTotals[A] = 200n;
  input.distributedTotals[A] = 200n;
  input.vaultBalances[A] = 150n;
  const { ok, errors } = reconcile(input);
  assert.equal(ok, false);
  assert.match(errors[0]!, /this epoch's payments\(200\) > vault\(150\)/);
});

test("reconcile fails on a cumulative decrease", () => {
  const input = base();
  const prior: CumulativeByAsset = { [B]: { "0x1111": 9n } };
  const next: CumulativeByAsset = { [B]: { "0x1111": 8n } };
  input.cumulativePrior = prior;
  input.cumulativeNew = next;
  assert.equal(reconcile(input).ok, false);
});