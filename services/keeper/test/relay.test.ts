import assert from "node:assert/strict";
import test from "node:test";
import type { Hex } from "viem";
import { runClaimRelay, type CycleContext, type DeliveryEntry } from "../src/index.js";
import type { EpochResult } from "@penny/indexer";

/**
 * D034 auto-delivery relay step. The onchain safety properties (leaf-bound wallet, opt-in
 * gate, skip-not-fatal batching) are proven in Solidity tests; these tests pin the keeper-side
 * behavior: unarmed-by-default, empty-census skip, and the armed batch path via the injected
 * adapter call.
 */

const WALLET: Hex = "0x1111111111111111111111111111111111111111";

function fakeEpoch(): EpochResult {
  return {
    epochIndex: 0,
    root: ("0x" + "ab".repeat(32)) as Hex,
    manifest: { contentHash: ("0x" + "cd".repeat(32)) as Hex },
  } as unknown as EpochResult;
}

function baseCtx(overrides: Partial<CycleContext>): CycleContext {
  return {
    cycleId: "t",
    cursor: {} as CycleContext["cursor"],
    epoch: fakeEpoch(),
    snapshot: {} as CycleContext["snapshot"],
    ...overrides,
  };
}

function entry(): DeliveryEntry {
  return {
    wallet: WALLET,
    cumulative: [100n],
    proof: [],
    attestationExpiry: 2n ** 40n,
    attestationSignature: "0xdeadbeef",
  };
}

test("claim-relay stays unarmed by default (mainnet gate)", async () => {
  const out = await runClaimRelay(baseCtx({ deliveries: [entry()] }));
  assert.equal(out.status, "skipped");
  assert.match(out.detail ?? "", /unarmed/);
});

test("armed relay with an empty census skips without calling the adapter", async () => {
  let called = 0;
  const out = await runClaimRelay(
    baseCtx({
      relayArmed: true,
      deliveries: [],
      claimForMany: async () => {
        called++;
        return 0;
      },
    }),
  );
  assert.equal(out.status, "skipped");
  assert.equal(called, 0);
});

test("armed relay batches opted-in wallets through claimForMany and reports delivered count", async () => {
  const seen: { epochIndex: number; count: number }[] = [];
  const out = await runClaimRelay(
    baseCtx({
      relayArmed: true,
      deliveries: [entry(), { ...entry(), wallet: "0x2222222222222222222222222222222222222222" }],
      claimForMany: async (epochIndex, deliveries) => {
        seen.push({ epochIndex, count: deliveries.length });
        return deliveries.length - 1; // one entry skipped onchain (not opted in)
      },
    }),
  );
  assert.equal(out.status, "succeeded");
  assert.deepEqual(seen, [{ epochIndex: 0, count: 2 }]);
  assert.match(out.detail ?? "", /auto-delivered 1\/2/);
});

test("armed relay without a wired adapter fails loudly instead of pretending", async () => {
  await assert.rejects(
    runClaimRelay(baseCtx({ relayArmed: true, deliveries: [entry()] })),
    /claimForMany adapter not wired/,
  );
});
