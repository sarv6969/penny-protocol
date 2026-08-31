import assert from "node:assert/strict";
import test from "node:test";
import { encodePacked, keccak256, type Hex } from "viem";
import { scopeOf, StubSigner } from "../src/index.js";

const ROOT: Hex = ("0x" + "ab".repeat(32)) as Hex;
const CHAIN_ID = 4663;
const DISTRIBUTOR: Hex = "0xdddddddddddddddddddddddddddddddddddddddd";

test("scopeOf replicates the onchain PENNY_REWARD_ELIGIBILITY scope (D027)", () => {
  const expected = keccak256(
    encodePacked(
      ["string", "uint256", "address", "uint256", "bytes32"],
      ["PENNY_REWARD_ELIGIBILITY", BigInt(CHAIN_ID), DISTRIBUTOR, 0n, ROOT],
    ),
  );
  assert.equal(scopeOf(CHAIN_ID, DISTRIBUTOR, 0, ROOT), expected);
});

test("scopeOf is deterministic and distinguishes every domain component", () => {
  const base = scopeOf(CHAIN_ID, DISTRIBUTOR, 0, ROOT);
  assert.equal(base, scopeOf(CHAIN_ID, DISTRIBUTOR, 0, ROOT));
  assert.notEqual(base, scopeOf(CHAIN_ID, DISTRIBUTOR, 1, ROOT));
  assert.notEqual(
    base,
    scopeOf(CHAIN_ID, DISTRIBUTOR, 0, ("0x" + "cd".repeat(32)) as Hex),
  );
  // Cross-chain and cross-deployment scopes never collide (D027 domain separation).
  assert.notEqual(base, scopeOf(999, DISTRIBUTOR, 0, ROOT));
  assert.notEqual(
    base,
    scopeOf(CHAIN_ID, "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee", 0, ROOT),
  );
});

test("StubSigner signs deterministically and refuses below-threshold attestations", async () => {
  const signer = new StubSigner();
  const wallet: Hex = "0x1111111111111111111111111111111111111111";
  const scope = scopeOf(CHAIN_ID, DISTRIBUTOR, 0, ROOT);
  const a = await signer.sign(wallet, scope);
  const b = await signer.sign(wallet, scope);
  assert.equal(a, b);
  assert.equal(a.length, 66); // keccak output
  assert.notEqual(
    await signer.sign(wallet, scope),
    await signer.sign("0x2222222222222222222222222222222222222222", scope),
  );
  assert.notEqual(await signer.attest(wallet, scope, true), null);
  assert.equal(await signer.attest(wallet, scope, false), null);
});
