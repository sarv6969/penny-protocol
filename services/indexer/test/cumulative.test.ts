import assert from "node:assert/strict";
import { test } from "node:test";

import { applyCumulative, cumulativeTotal, isMonotone, type CumulativeByAsset } from "../src/cumulative.js";

const A = "0x" + "a".repeat(40);
const B = "0x" + "b".repeat(40);
const C = "0x" + "c".repeat(40); // drops out mid-way (lost eligibility)

function leaf(wallet: string, v: bigint): Record<string, bigint> {
  return { [wallet]: v };
}

test("applyCumulative merges deltas onto genesis-total and preserves dropped wallets", () => {
  const prior: CumulativeByAsset = {
    [A]: { ...leaf("0x1111", 100n), ...leaf("0x2222", 50n), ...leaf(C, 999n) },
  };
  const deltas: CumulativeByAsset = {
    [A]: { ...leaf("0x1111", 25n), ...leaf("0x2222", 0n) },
  };

  const next = applyCumulative(prior, [A], deltas, ["0x1111", "0x2222"]);
  assert.equal(next[A]!["0x1111"], 125n);
  assert.equal(next[A]!["0x2222"], 50n);
  // C had an entitlement and is absent from this run -> retained untouched.
  assert.equal(next[A]![C], 999n);
});

test("isMonotone catches entitlement destruction", () => {
  const prior: CumulativeByAsset = { [A]: { ...leaf("0x1111", 100n) } };
  const next: CumulativeByAsset = { [A]: { ...leaf("0x1111", 99n) } };
  assert.equal(isMonotone(prior, next, [A]), false);

  const flat: CumulativeByAsset = { [A]: { ...leaf("0x1111", 100n) } };
  assert.equal(isMonotone(prior, flat, [A]), true);
});

test("cumulativeTotal sums all wallets for an asset", () => {
  const byWallet: CumulativeByAsset = { [A]: { ...leaf("0x1111", 100n), ...leaf("0x2222", 50n) } };
  assert.equal(cumulativeTotal(byWallet, A), 150n);
  assert.equal(cumulativeTotal({}, A), 0n);
});