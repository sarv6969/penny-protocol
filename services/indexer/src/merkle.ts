import { concatHex, encodeAbiParameters, keccak256, type Hex } from "viem";

/**
 * Merkle tree matching `RewardDistributor` leaves and OpenZeppelin `MerkleProof`
 * semantics, exactly:
 *
 *  - leaf  = keccak256(abi.encode(wallet, uint256[] cumulative))
 *  - pairs are hashed as keccak256(abi.encodePacked(a, b)) where a <= b
 *  - odd levels duplicate the last node
 *
 * Any two clean builds of the indexer on the same inputs therefore produce the same
 * root and proof sets (D029). Leaves are always taken in canonical (ascending address,
 * then ascending cumulative array index) order for bit-for-bit reproducible manifests.
 */

export function leafFor(wallet: string, cumulative: bigint[]): Hex {
  const encoded = encodeAbiParameters(
    [{ type: "address" }, { type: "uint256[]" }],
    [wallet as `0x${string}`, cumulative],
  );
  return keccak256(encoded);
}

function hashPair(a: Hex, b: Hex): Hex {
  return a <= b ? keccak256(concatHex([a, b])) : keccak256(concatHex([b, a]));
}

/** Compute the root over leaves using sorted-pair / duplicate-odd semantics. */
export function rootOf(leaves: Hex[]): Hex {
  if (leaves.length === 0) return "0x0000000000000000000000000000000000000000000000000000000000000000";
  let level = leaves;
  while (level.length > 1) {
    const next: Hex[] = [];
    for (let i = 0; i < level.length; i += 2) {
      const a = level[i];
      if (a === undefined) throw new Error("merkle: missing leaf");
      const b = i + 1 < level.length ? level[i + 1]! : a;
      next.push(hashPair(a, b));
    }
    level = next;
  }
  const root = level[0];
  if (root === undefined) throw new Error("merkle: empty tree");
  return root;
}

/** Bottom-up proof for leaves[index], matching `MerkleProof.verify` semantics. */
export function proofFor(leaves: Hex[], index: number): Hex[] {
  if (index < 0 || index >= leaves.length) throw new Error("merkle: index out of range");
  let level = leaves;
  let pos = index;
  const proof: Hex[] = [];
  while (level.length > 1) {
    // Sibling is the paired neighbour, clamped to self at odd-length duplicates.
    const siblingPos = pos % 2 === 0 ? Math.min(pos + 1, level.length - 1) : pos - 1;
    proof.push(level[siblingPos]!);

    const next: Hex[] = [];
    for (let i = 0; i < level.length; i += 2) {
      const a = level[i];
      if (a === undefined) throw new Error("merkle: missing leaf");
      const b = i + 1 < level.length ? level[i + 1]! : a;
      next.push(hashPair(a, b));
    }
    level = next;
    pos = Math.floor(pos / 2);
  }
  return proof;
}

/** OpenZeppelin `MerkleProof.verify` (OZ v5 `hashPair` ordering). */
export function verify(proof: Hex[], root: Hex, leaf: Hex): boolean {
  let computed = leaf;
  for (const element of proof) {
    computed = hashPair(computed, element);
  }
  return computed === root;
}