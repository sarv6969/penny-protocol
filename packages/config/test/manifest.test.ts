import assert from "node:assert";
import { readFile } from "node:fs/promises";
import { test } from "node:test";

import { assertAllVerified, requireEntry, type AddressManifest } from "../src/index.js";

async function loadManifest(): Promise<AddressManifest> {
  const raw = await readFile(new URL("../src/generated/mainnet.verified.json", import.meta.url), "utf8");
  return JSON.parse(raw) as AddressManifest;
}

test("manifest contains all required launch entries", async () => {
  const manifest = await loadManifest();
  for (const key of [
    "chain.mainnet",
    "chain.testnet",
    "weth",
    "uniswap.poolManager",
    "uniswap.positionManager",
    "uniswap.positionDescriptor",
    "uniswap.quoter",
    "uniswap.universalRouter",
    "stock.TE",
    "stock.POET",
    "stock.NNE",
    "stock.WYFI",
    "stock.RCAT",
  ]) {
    requireEntry(manifest, key);
  }
});

test("blocked entries are present and do not pass verification gate", async () => {
  const manifest = await loadManifest();
  const sequencer = requireEntry(manifest, "chainlink.sequencerUptime");
  assert.equal(sequencer.verification, "blocked");
  assert.throws(() => assertAllVerified(manifest, ["chainlink.sequencerUptime"]));
  assert.throws(() => assertAllVerified(manifest, ["chainlink.stockFeed.TE"]));
});

test("founding basket has exactly five constituents, each verified onchain at pinned block", async () => {
  const manifest = await loadManifest();
  const tickers = ["TE", "POET", "NNE", "WYFI", "RCAT"];
  for (const t of tickers) {
    const e = requireEntry(manifest, `stock.${t}`);
    assert.equal(e.verification, "onchain", `${t} must be onchain-verified`);
    assert.ok(e.verifiedAtBlock, `${t} needs pinned block`);
    assert.equal(e.oraclePausedVerified, "false", `${t} oracle must be unpaused`);
    assert.equal(e.uiMultiplierVerified, "1000000000000000000", `${t} multiplier must be 1e18`);
  }
  assert.equal(tickers.length, 5);
});

test("weth and critical uniswap contracts verified", async () => {
  const manifest = await loadManifest();
  for (const key of ["weth", "uniswap.poolManager", "uniswap.positionManager", "uniswap.universalRouter"]) {
    assert.equal(requireEntry(manifest, key).verification, "onchain", key);
  }
});