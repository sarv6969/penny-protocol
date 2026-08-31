import assert from "node:assert/strict";
import { test } from "node:test";

import { memoryIndexer, type EpochSpec } from "../src/indexer.js";
import { verify } from "../src/merkle.js";
import { buildChain, FakeSource, THRESHOLD, TOTAL_SUPPLY, transfer, zeroAddress, hashOf } from "./chain.js";

const Z = zeroAddress();
const S = "0x" + "0".repeat(8) + "5".repeat(32); // protocol
const A = "0x" + "a".repeat(40);
const B = "0x" + "b".repeat(40);
const C = "0x" + "c".repeat(40);
const T1 = "0x" + "a".repeat(40);
const T2 = "0x" + "b".repeat(40);

const H = (n: number) => hashOf(n);

function protocol(): ReadonlySet<string> {
  return new Set([S]);
}

function deployEvents() {
  return [
    transfer(1, 0, 0, Z, S, TOTAL_SUPPLY),
    transfer(2, 0, 0, S, A, 400_000n * 10n ** 18n),
    transfer(3, 0, 0, S, B, 250_000n * 10n ** 18n),
    transfer(4, 0, 0, S, C, 150_000n * 10n ** 18n),
    transfer(5, 0, 0, A, B, 50_000n * 10n ** 18n),
  ];
}

function epochSpec(extra: Partial<EpochSpec> = {}): EpochSpec {
  return {
    chainId: 4663,
    distributor: "0x" + "d".repeat(40),
    epochIndex: 0,
    assets: [T1, T2],
    fundedTotals: { [T1]: 1_000n * 10n ** 18n, [T2]: 500n * 10n ** 18n },
    vaultBalances: { [T1]: 1_000n * 10n ** 18n, [T2]: 500n * 10n ** 18n },
    meta: { generatedAt: "2026-08-30T00:00:00.000Z", softwareVersion: "8.0.0", commit: "0".repeat(40) },
    ...extra,
  };
}

test("ingest then snapshot at a confirmed block yields the expected eligible set", async () => {
  const source = new FakeSource(buildChain({ size: 8 }), deployEvents());
  const { indexer, store } = memoryIndexer(source, {
    confirmationDepth: 2,
    threshold: THRESHOLD,
    excluded: protocol(),
  });

  await indexer.ingestRange(0, 7);

  // depth 2 -> confirmed = tip(7) - 2 = 5; block 6 is not yet final.
  await assert.rejects(() => indexer.snapshot(6), /not yet final/);
  await assert.rejects(() => indexer.snapshot(99), /not ingested/);

  const snap = await indexer.snapshot();
  assert.equal(snap.block.number, 5);
  assert.equal(snap.block.hash, H(5));
  assert.equal(snap.balances.get(A), 350_000n * 10n ** 18n);
  assert.equal(snap.balances.get(B), 300_000n * 10n ** 18n);
  assert.deepEqual(snap.eligibility.wallets, [A, B, C]);
  assert.equal(snap.totalEligibleSupply, 800_000n * 10n ** 18n);
});

test("epoch build is deterministic: same inputs, same root and content hash", async () => {
  async function run(): Promise<{ root: string; contentHash: string; wallets: string[] }> {
    const source = new FakeSource(buildChain({ size: 8 }), deployEvents());
    const { indexer } = memoryIndexer(source, {
      confirmationDepth: 2,
      threshold: THRESHOLD,
      excluded: protocol(),
    });
    await indexer.ingestRange(0, 7);
    const epoch = await indexer.buildEpoch(epochSpec());
    assert.equal(epoch.reconcile.ok, true);
    return { root: epoch.root, contentHash: epoch.manifest.contentHash, wallets: epoch.wallets };
  }

  const first = await run();
  const second = await run();
  assert.equal(first.root, second.root);
  assert.equal(first.contentHash, second.contentHash);
  assert.deepEqual(first.wallets, second.wallets);
});

test("epoch proofs verify against the published root", async () => {
  const source = new FakeSource(buildChain({ size: 8 }), deployEvents());
  const { indexer } = memoryIndexer(source, {
    confirmationDepth: 2,
    threshold: THRESHOLD,
    excluded: protocol(),
  });
  await indexer.ingestRange(0, 7);
  const epoch = await indexer.buildEpoch(epochSpec());

  for (let i = 0; i < epoch.wallets.length; i++) {
    const leaf = epoch.leaves[i]!;
    assert.equal(verify(epoch.proofs[i]!.proof, epoch.root, leaf), true);
    // The leaf also commits the exact genesis-total cumulative.
    const wallet = epoch.proofs[i]!.wallet;
    const cumulative = epoch.proofs[i]!.cumulative;
    assert.equal(cumulative[0]! + cumulative[1]! > 0n, true);
    assert.equal(wallet, epoch.wallets[i]);
  }

  // Wallet A holds 350k of the 800k eligible supply -> 350/800 * 1000 = 437.5 tokens.
  const w1 = epoch.newCumulative[T1]![A];
  assert.equal(w1, 437_500_000_000_000_000_000n);
});

test("losing eligibility keeps prior cumulative but stops delta accrual", async () => {
  const source = new FakeSource(buildChain({ size: 8 }), deployEvents());
  const before = deployEvents();
  // Remove the 50k A -> B transfer at block 5 so A keeps its full 400k through epoch 0.
  before.splice(4, 1);

  const { indexer } = memoryIndexer(new FakeSource(buildChain({ size: 8 }), before), {
    confirmationDepth: 2,
    threshold: THRESHOLD,
    excluded: protocol(),
  });
  await indexer.ingestRange(0, 7);

  const epoch0 = await indexer.buildEpoch(epochSpec({ epochIndex: 0 }));
  const prior = epoch0.newCumulative;
  const bCumulativeBefore = prior[T1]![B];

  // Next epoch: A dumps all 400k to C and B dumps to 50k below the threshold. Only C
  // remains eligible; the losers keep their prior cumulative untouched.
  const nextEvents = [...before, transfer(6, 0, 0, A, C, 400_000n * 10n ** 18n), transfer(6, 1, 0, B, S, 200_000n * 10n ** 18n)];
  const { indexer: ix2 } = memoryIndexer(new FakeSource(buildChain({ size: 9 }), nextEvents), {
    confirmationDepth: 2,
    threshold: THRESHOLD,
    excluded: protocol(),
  });
  await ix2.ingestRange(0, 8);

  const epoch1 = await ix2.buildEpoch(epochSpec({ epochIndex: 1, priorCumulative: prior }));

  assert.deepEqual(epoch1.wallets, [C], "only C is eligible in epoch 1");
  assert.equal(epoch1.newCumulative[T1]![B], bCumulativeBefore, "B retained prior entitlement");
  assert.equal(epoch1.newCumulative[T1]![A], prior[T1]![A], "A retained prior entitlement");
  assert.ok(epoch1.newCumulative[T1]![C] > epoch0.newCumulative[T1]![C], "C accrued a fresh delta");
  assert.equal(epoch1.reconcile.ok, true);
});

test("a canonical fork is detected and rolled back before new truth is committed", async () => {
  const source = new FakeSource(buildChain({ size: 8 }), deployEvents());
  const { indexer, store } = memoryIndexer(source, {
    confirmationDepth: 2,
    threshold: THRESHOLD,
    excluded: protocol(),
  });
  await indexer.ingestRange(0, 7);
  assert.equal((await store.latestBlock())!.number, 7);

  // The RPC view changes: the chain forks at block 6 (canonical hash changes, subtree
  // grows to 10). Re-ingesting the same range through the same store must roll back.
  source.replace(buildChain({ size: 10, override: { 6: "0x" + "c".repeat(64) } }), deployEvents());
  const ingest = await indexer.ingestRange(0, 9);
  assert.equal(ingest.rolledBackAtFork, 6);

  assert.equal((await store.latestBlock())!.number, 9, "forked chain now the tip");
  assert.equal((await store.blockAt(6))!.hash, "0x" + "c".repeat(64), "replaced with canonical hash");
  assert.equal((await store.blockAt(5))!.hash, H(5), "pre-fork history untouched");
});

test("a shallow (unconfirmed) reorg does not disturb confirmed history", async () => {
  const source = new FakeSource(buildChain({ size: 8 }), deployEvents());
  const { indexer, store } = memoryIndexer(source, {
    confirmationDepth: 3,
    threshold: THRESHOLD,
    excluded: protocol(),
  });
  await indexer.ingestRange(0, 7);

  // Reorg only at the tip (7): everything from the fork height is rewound and re-pushed,
  // but the confirmed history below it is re-applied exactly as before.
  source.replace(buildChain({ size: 9, override: { 7: "0x" + "e".repeat(64) } }), deployEvents());
  const ingest = await indexer.ingestRange(0, 8);
  assert.equal(ingest.rolledBackAtFork, 7);
  assert.equal((await store.latestBlock())!.number, 8);
  for (let n = 0; n <= 6; n++) assert.equal((await store.blockAt(n))!.hash, H(n));
});

test("buildEpoch refuses to snapshot an unconfirmed or uningested block", async () => {
  const source = new FakeSource(buildChain({ size: 6 }), []);
  const { indexer } = memoryIndexer(source, { confirmationDepth: 2, threshold: THRESHOLD });
  await indexer.ingestRange(0, 5);
  await assert.rejects(() => indexer.buildEpoch(epochSpec({ atBlock: 5 })), /not yet final/);
  await assert.rejects(() => indexer.buildEpoch(epochSpec({ atBlock: 99 })), /not ingested/);
});