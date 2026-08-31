import assert from "node:assert/strict";
import { test } from "node:test";

import { ZERO_ADDRESS, allocate, balancesAt, eligible, totalSupplyOf } from "../src/snapshot.js";
import { THRESHOLD, TOTAL_SUPPLY, transfer } from "./chain.js";

const Z = ZERO_ADDRESS;
const A = "0x" + "a".repeat(40);
const B = "0x" + "b".repeat(40);
const C = "0x" + "c".repeat(40);
const P = "0x" + "0".repeat(8) + "5".repeat(32);

function chain(size: number) {
  return Array.from({ length: size }, (_, b) => b);
}

test("balancesAt re-derives balances and always sums to total supply", () => {
  const logs = [
    transfer(1, 0, 0, Z, P, TOTAL_SUPPLY), // genesis mint to protocol
    transfer(2, 0, 0, P, A, 400_000n * 10n ** 18n),
    transfer(3, 0, 0, P, B, 250_000n * 10n ** 18n),
    transfer(4, 0, 0, P, C, 150_000n * 10n ** 18n),
    transfer(5, 0, 0, A, B, 50_000n * 10n ** 18n),
  ];

  const at4 = balancesAt(logs, 4);
  assert.equal(at4.get(A), 400_000n * 10n ** 18n);
  assert.equal(at4.get(B), 250_000n * 10n ** 18n);
  assert.equal(totalSupplyOf(at4), TOTAL_SUPPLY);

  const at5 = balancesAt(logs, 5);
  assert.equal(at5.get(A), 350_000n * 10n ** 18n);
  assert.equal(at5.get(B), 300_000n * 10n ** 18n);
  assert.equal(totalSupplyOf(at5), TOTAL_SUPPLY);
});

test("eligible filters threshold + exclusions and sorts ascending", () => {
  const balances = new Map([
    [A, 400_000n * 10n ** 18n],
    [B, 250_000n * 10n ** 18n],
    [C, 99_999n * 10n ** 18n],
    [P, THRESHOLD], // exactly at threshold -> eligible
  ]);

  const { wallets, totalEligibleSupply } = eligible(balances, THRESHOLD, new Set([P]));
  assert.deepEqual(wallets, [A, B]); // P excluded by address, C below threshold
  assert.equal(totalEligibleSupply, 650_000n * 10n ** 18n);
});

test("allocate settles exact wei-fair shares with no dust", () => {
  const balances = new Map([
    [A, 400_000n * 10n ** 18n],
    [B, 250_000n * 10n ** 18n],
    [C, 150_000n * 10n ** 18n],
  ]);
  const supply = 800_000n * 10n ** 18n;
  const total = 1_000n * 10n ** 18n;

  const shares = allocate(balances, [A, B, C], total, supply);
  // Exact wei-share = balance * total / supply: A 500, B 312.5, C 187.5 (all integer wei).
  assert.deepEqual(
    [...shares.entries()].map(([w, v]) => [w, v] as const),
    [
      [A, 500n * 10n ** 18n],
      [B, 312_500_000_000_000_000_000n],
      [C, 187_500_000_000_000_000_000n],
    ],
  );
  const sum = [...shares.values()].reduce((a, b) => a + b, 0n);
  assert.equal(sum, total, "no dust: allocation is exact");
});

test("allocate distributes residual wei to the largest fractional remainder, tie-break by lower address", () => {
  // supply 3e18 with balances 1e18 each; shares are 333333333333333333.33 wei, leaving
  // exactly 1 wei of dust -> the lowest-address wallet is awarded it.
  const balances = new Map([
    [A, 1n * 10n ** 18n],
    [B, 1n * 10n ** 18n],
    [C, 1n * 10n ** 18n],
  ]);
  const shares = allocate(balances, [A, B, C], 1n * 10n ** 18n, 3n * 10n ** 18n);
  assert.deepEqual([...shares.values()].reduce((a, b) => a + b, 0n), 1n * 10n ** 18n);
  assert.equal(shares.get(A), 333_333_333_333_333_333n + 1n, "A wins the 1-wei tie");
  assert.equal(shares.get(B), 333_333_333_333_333_333n);
  assert.equal(shares.get(C), 333_333_333_333_333_333n);
});

test("allocate is repeatable and order-independent", () => {
  const balances = new Map([
    [A, 300_000n * 10n ** 18n],
    [B, 500_000n * 10n ** 18n],
    [C, 200_000n * 10n ** 18n],
  ]);
  const supply = 1_000_000n * 10n ** 18n;
  const first = allocate(balances, [A, B, C], 777_777n * 10n ** 18n, supply);
  const second = allocate(balances, [C, B, A], 777_777n * 10n ** 18n, supply);
  assert.deepEqual(new Map([...first.entries()].sort()), new Map([...second.entries()].sort()));
});

test("allocate with zero asset total yields all-zero shares", () => {
  const balances = new Map([[A, THRESHOLD]]);
  const shares = allocate(balances, [A], 0n, THRESHOLD);
  assert.equal(shares.get(A), 0n);
});

test("chain() helper sanity", () => {
  assert.deepEqual(chain(3), [0, 1, 2]);
});