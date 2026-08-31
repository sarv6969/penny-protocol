import { encodePacked, keccak256, toHex, type Hex } from "viem";

/**
 * Scope binding used by RewardDistributor.publishEpoch:
 * `scope = keccak256(abi.encodePacked("PENNY_REWARD_ELIGIBILITY", block.chainid, distributor,
 * epochIndex, root))`. Replicated here so the keeper's relay/notify tooling and the attestation
 * service agree with the onchain registry byte-for-byte (D027). Domain separation: the chain id
 * and distributor address make a scope non-replayable across chains and deployments.
 */
export function scopeOf(
  chainId: number,
  distributor: Hex,
  epochIndex: number,
  root: Hex,
): Hex {
  return keccak256(
    encodePacked(
      ["string", "uint256", "address", "uint256", "bytes32"],
      [
        "PENNY_REWARD_ELIGIBILITY",
        BigInt(chainId),
        distributor,
        BigInt(epochIndex),
        root,
      ],
    ),
  );
}

/**
 * Attestation service contract. `claim-relay` is opt-in: relaying a claim for a wallet
 * requires that wallet's scoped eligibility signature, which is only ever produced for the
 * wallet owner by the attestation service. The keeper stores no signing keys (D027).
 */
export interface EligibilitySigner {
  sign(wallet: Hex, scope: Hex): Promise<Hex>;
  /** Returns null when the wallet is not eligible at this instant (revoked/lost threshold). */
  attest(wallet: Hex, scope: Hex, thresholdMet: boolean): Promise<Hex | null>;
}

/** Deterministic stub for tests: proves the attestation wire is plumbed without forging keys. */
export class StubSigner implements EligibilitySigner {
  constructor(private readonly pattern: Hex = "0xdeadbeef") {}

  async sign(wallet: Hex, scope: Hex): Promise<Hex> {
    return keccak256(
      encodePacked(
        ["bytes4", "address", "bytes32"],
        [this.pattern, wallet, scope],
      ),
    );
  }

  async attest(
    wallet: Hex,
    _scope: Hex,
    thresholdMet: boolean,
  ): Promise<Hex | null> {
    return thresholdMet ? this.sign(wallet, _scope) : null;
  }
}

export function bytesToHex(bytes: Uint8Array): Hex {
  return toHex(bytes);
}
