import assert from "node:assert";
import { test } from "node:test";

import { minimumExpectedOutput, PENNY_TOTAL_SUPPLY, PROTOCOL_FEE_BPS } from "../src/constants.js";
import { isFixedSupplyAmount, render } from "../src/index.js";

test("protocol fee is 300 bps", () => {
  assert.equal(PROTOCOL_FEE_BPS, 300);
});

test("minimumExpectedOutput applies exactly 3% protocol fee", () => {
  const input = 1000n * 10n ** 6n;
  assert.equal(minimumExpectedOutput(input), 970n * 10n ** 6n);
});

test("fixed supply is exactly 1 billion e18", () => {
  assert.equal(PENNY_TOTAL_SUPPLY, 1_000_000_000n * 10n ** 18n);
  assert.ok(isFixedSupplyAmount(PENNY_TOTAL_SUPPLY));
  assert.ok(!isFixedSupplyAmount(PENNY_TOTAL_SUPPLY - 1n));
});

test("render shortens an address", () => {
  const long = "0xb1969f6604ca1ae7a2cd3f1827876e914594ca2d";
  const short = render(long);
  assert.equal(short, "0xb196...ca2d");
});