import assert from "node:assert/strict";
import { test } from "node:test";

import { confirmedTip, forkAt, isContiguous } from "../src/blocks.js";
import { buildChain } from "./chain.js";

test("confirmedTip subtracts depth and clamps at zero", () => {
  assert.equal(confirmedTip(undefined, 12), undefined);
  assert.equal(confirmedTip(50, 12), 38);
  assert.equal(confirmedTip(10, 12), 0);
  assert.equal(confirmedTip(0, 0), 0);
});

test("isContiguous accepts a canonical batch and rejects gaps and hash breaks", () => {
  const blocks = buildChain({ size: 5 });
  assert.equal(isContiguous(blocks), true);

  const gap = blocks.slice(0, 3).concat(blocks[4]!);
  assert.equal(isContiguous(gap), false, "missing block 3");

  const broken = blocks.map((b, i) => (i === 2 ? { ...b, parentHash: "0x" + "f".repeat(64) } : b));
  assert.equal(isContiguous(broken), false, "parent mismatch");
});

test("forkAt reports the first height where stored and canonical hashes diverge", () => {
  const stored = buildChain({ size: 5 });
  const incoming = buildChain({
    size: 7,
    override: { 4: "0x" + "c".repeat(64) },
  });
  assert.equal(forkAt(stored, incoming), 4);

  const same = buildChain({ size: 5 });
  assert.equal(forkAt(stored, same), undefined);
});