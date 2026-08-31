import assert from "node:assert/strict";
import { mkdir, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

import { memoryIndexer, type EpochSpec } from "../src/indexer.js";
import { verify } from "../src/merkle.js";
import { buildChain, FakeSource, THRESHOLD, TOTAL_SUPPLY, transfer, zeroAddress } from "./chain.js";

/**
 * Generates the bit-for-bit committed golden manifest that the Solidity cross-check test
 * (`packages/contracts/test/vm/ManifestCrossCheck.t.sol`) re-reads and re-verifies
 * onchain. Any change to the indexer inputs or Merkle semantics that shifts a leaf/root
 * updates this file and is caught by the Solid-side test in CI.
 *
 * Scenario: 3 eligible wallets (address 0x1111/0x2222/0x3333) splitting a 2-asset basket
 * (address 0xaa.. / 0xbb..) from an 800k PENNY eligible supply.
 */

const Z = zeroAddress();
const S = "0x" + "0".repeat(8) + "5".repeat(32);
const W1 = "0x1111111111111111111111111111111111111111";
const W2 = "0x2222222222222222222222222222222222222222";
const W3 = "0x3333333333333333333333333333333333333333";
const T1 = "0x" + "a".repeat(40);
const T2 = "0x" + "b".repeat(40);

function events() {
  return [
    transfer(1, 0, 0, Z, S, TOTAL_SUPPLY),
    transfer(2, 0, 0, S, W1, 400_000n * 10n ** 18n),
    transfer(3, 0, 0, S, W2, 250_000n * 10n ** 18n),
    transfer(4, 0, 0, S, W3, 150_000n * 10n ** 18n),
  ];
}

test("write golden manifest fixture for the Solidity cross-check", async () => {
  const { indexer } = memoryIndexer(new FakeSource(buildChain({ size: 8 }), events()), {
    confirmationDepth: 2,
    threshold: THRESHOLD,
    excluded: new Set([S]),
  });
  await indexer.ingestRange(0, 7);

  const spec: EpochSpec = {
    chainId: 4663,
    distributor: "0x" + "d".repeat(40),
    epochIndex: 0,
    assets: [T1, T2],
    fundedTotals: { [T1]: 1_000n * 10n ** 18n, [T2]: 500n * 10n ** 18n },
    vaultBalances: { [T1]: 1_000n * 10n ** 18n, [T2]: 500n * 10n ** 18n },
    meta: { generatedAt: "2026-08-30T00:00:00.000Z", softwareVersion: "8.0.0", commit: "0".repeat(40) },
  };

  const epoch = await indexer.buildEpoch(spec);
  assert.equal(epoch.reconcile.ok, true);
  for (let i = 0; i < epoch.wallets.length; i++) {
    assert.equal(verify(epoch.proofs[i]!.proof, epoch.root, epoch.leaves[i]!), true);
  }

  const walletProofs = epoch.proofs.map((p) => ({
    wallet: p.wallet,
    cumulative: p.cumulative.map((c) => c.toString()),
    proof: p.proof,
  }));
  const fixture = {
    schemaVersion: "1.0.0",
    chainId: 4663,
    epochIndex: 0,
    distributor: spec.distributor,
    root: epoch.root,
    assets: [T1, T2],
    walletCount: epoch.wallets.length,
    snapshot: {
      blockNumber: epoch.snapshot.block.number,
      blockHash: epoch.snapshot.block.hash,
    },
    totalEligibleSupply: epoch.snapshot.totalEligibleSupply.toString(),
    fundedTotals: Object.fromEntries(Object.entries(spec.fundedTotals).map(([k, v]) => [k, v.toString()])),
    residual: Object.fromEntries(Object.entries(epoch.residual).map(([k, v]) => [k, v.toString()])),
    walletProofs,
    contentHash: epoch.manifest.contentHash,
  };

  const fixtureDir = new URL("../../../packages/contracts/test/fixtures/", import.meta.url);
  const fixturePath = new URL("../../../packages/contracts/test/fixtures/manifest.golden.json", import.meta.url);
  await mkdir(fileURLToPath(fixtureDir), { recursive: true });
  await writeFile(fileURLToPath(fixturePath), JSON.stringify(fixture, null, 2) + "\n");
  assert.ok(epoch.manifest.contentHash.length === 66);
});