import assert from "node:assert/strict";
import test from "node:test";
import { encodeFunctionData, keccak256, toBytes, type Hex } from "viem";
import {
  BASKET_PURCHASE,
  DISTRIBUTOR_EPOCH_COUNT,
  DISTRIBUTOR_PUBLISH,
  FEE_COLLECTOR_SWEEP,
} from "../src/index.js";

const MANIFEST_HASH = ("0x" + "33".repeat(32)) as Hex;

/**
 * Selector pinning: every keeper write/read fragment must encode to the exact keccak-derived
 * 4-byte selector of its canonical Solidity signature. If a contract rename ever diverges the
 * produced call from the compiled artifact, this test fails loudly (D030).
 */
test("ABI fragments encode to their canonical function selectors", () => {
  const canonical = (signature: string): string =>
    keccak256(toBytes(signature)).slice(0, 10);

  const sweepId = encodeFunctionData({
    abi: FEE_COLLECTOR_SWEEP,
    functionName: "sweep",
  }).slice(0, 10);
  assert.equal(sweepId, canonical("sweep()"));

  const basketId = encodeFunctionData({
    abi: BASKET_PURCHASE,
    functionName: "purchaseBasket",
  }).slice(0, 10);
  assert.equal(basketId, canonical("purchaseBasket()"));

  const publishId = encodeFunctionData({
    abi: DISTRIBUTOR_PUBLISH,
    functionName: "publishEpoch",
    args: ["0x" + "11".repeat(32), [], [], MANIFEST_HASH],
  }).slice(0, 10);
  assert.equal(
    publishId,
    canonical("publishEpoch(bytes32,address[],uint256[],bytes32)"),
  );

  const countId = encodeFunctionData({
    abi: DISTRIBUTOR_EPOCH_COUNT,
    functionName: "epochCount",
  }).slice(0, 10);
  assert.equal(countId, canonical("epochCount()"));
});

test("publishEpoch encodes a non-empty, ordered asset list with matching totals (contract-enforced)", () => {
  const t1: Hex = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
  const t2: Hex = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
  const data = encodeFunctionData({
    abi: DISTRIBUTOR_PUBLISH,
    functionName: "publishEpoch",
    args: ["0x" + "22".repeat(32), [t1, t2], [100n, 200n], MANIFEST_HASH],
  });
  // bytes4 selector + padded root + two dynamic-slot offsets + manifestHash
  // + (array length + 2 addresses) + (array length + 2 totals)
  assert.equal(data.length, 10 + 64 * 4 + (64 + 64 * 2) * 2);
});

test("selectors differ across functions (no collisions among keeper surface)", () => {
  const selectors = [
    "sweep()",
    "purchaseBasket()",
    "publishEpoch(bytes32,address[],uint256[],bytes32)",
    "epochCount()",
  ].map((s) => keccak256(toBytes(s)).slice(0, 10));
  assert.equal(new Set(selectors).size, selectors.length);
});
