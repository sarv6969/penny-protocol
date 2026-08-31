import assert from "node:assert/strict";
import { keccak256 } from "viem";
import { test } from "node:test";

import { leafFor, proofFor, rootOf, verify } from "../src/merkle.js";

const W = (n: number) => "0x" + n.toString(16).padStart(40, "0");

function abiLeaf(wallet: string, cumulative: bigint[]): `0x${string}` {
  const word = (n: string | bigint, bytes = 32) => {
    const s = typeof n === "bigint" ? n.toString(16) : n;
    return s.padStart(bytes * 2, "0");
  };
  // ABI head: address padded to 32 bytes, then the dynamic offset (0x40).
  // ABI tail: array length, then each uint256 element.
  const body =
    "0x" +
    word(wallet.slice(2)) +
    word(64n) +
    word(BigInt(cumulative.length)) +
    cumulative.map((c) => word(c)).join("");
  return keccak256(body);
}

test("leafFor matches standard abi.encode(address,uint256[])", () => {
  const wallet = W(10);
  const cumulative = [100n, 200n] as bigint[];
  assert.equal(leafFor(wallet, cumulative), abiLeaf(wallet, cumulative));
  assert.equal(leafFor(wallet, []) .length, 66, "32-byte hash");
});

test("rootOf is deterministic and empty-safe", () => {
  const leaves = [leafFor(W(1), [1n]), leafFor(W(2), [2n])];
  assert.equal(rootOf(leaves), rootOf(leaves));
  assert.equal(rootOf([]), "0x" + "0".repeat(64));
  assert.equal(rootOf([leaves[0]! ]), leaves[0], "single leaf hashes to itself");
});

test("proofFor+verify round-trips for even and odd trees", () => {
  for (const n of [2, 3, 4, 5, 6]) {
    const leaves = Array.from({ length: n }, (_, i) => leafFor(W(i + 1), [BigInt(i + 1)]));
    const root = rootOf(leaves);
    for (let i = 0; i < n; i++) {
      assert.equal(verify(proofFor(leaves, i), root, leaves[i]), true, `leaf ${i} of ${n}`);
    }
  }
});

test("verify rejects wrong proof, wrong leaf, wrong root", () => {
  const leaves = [leafFor(W(1), [10n]), leafFor(W(2), [20n]), leafFor(W(3), [30n])];
  const root = rootOf(leaves);
  assert.equal(verify(proofFor(leaves, 0), root, leaves[1]!), false, "wrong leaf");
  assert.equal(verify([], root, leafFor(W(9), [9n])), false, "empty proof");
  assert.equal(verify(proofFor(leaves, 0), rootOf([leaves[0]! , leaves[1]!]), leaves[0]! ), false, "wrong root");
});

test("leaves with duplicate values still produce valid proofs aggregate-wise", () => {
  const leaves = [leafFor(W(1), [7n]), leafFor(W(1), [7n]), leafFor(W(2), [8n])];
  const root = rootOf(leaves);
  for (let i = 0; i < leaves.length; i++) assert.equal(verify(proofFor(leaves, i), root, leaves[i]!), true);
});