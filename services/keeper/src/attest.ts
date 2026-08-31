import type { Hex } from "viem";
import { scopeOf, type EligibilitySigner } from "./signer.js";

/**
 * Attestation service (Phase 9 / D027). Holds NO signing keys and NO wallet balances: the
 * signer is injected, and eligibility is a stateless threshold check against the current
 * balance read at attest time — balances are evaluated, never persisted. `claim-relay` is
 * opt-in / D012: a relayer can only forward claims that carry a wallet owner's live, scoped
 * eligibility signature. `attestEligibility` produces exactly that wallet-bound signature from
 * the injected signer; `noteClaim` records an already-signed claim for relay. Scope binding
 * comes from `scopeOf(epochIndex, root)` (see signer.ts), byte-identical to the onchain
 * `PENNY_REWARD_ELIGIBILITY` scope, so an attestation minted here verifies onchain.
 */
export interface PendingClaim {
  epochIndex: number;
  wallet: Hex;
  scope: Hex;
  signedAttestation: Hex;
  at: bigint;
}

export class AttestationService {
  private readonly signer: EligibilitySigner;
  private readonly threshold: bigint;
  private readonly chainId: number;
  private readonly distributor: Hex;
  private readonly claims: PendingClaim[] = [];

  constructor(
    signer: EligibilitySigner,
    threshold: bigint,
    chainId: number,
    distributor: Hex,
  ) {
    this.signer = signer;
    this.threshold = threshold;
    this.chainId = chainId;
    this.distributor = distributor;
  }

  /**
   * Attest a wallet's eligibility at this instant. Requires `balance >= threshold`; the scope is
   * derived deterministically from the epoch/root pair. Returns null when ineligible. The wallet's
   * balance is used transiently and never stored (fail-closed: nothing durable records a balance).
   */
  async attestEligibility(
    wallet: Hex,
    balance: bigint,
    epochIndex: number,
    root: Hex,
  ): Promise<PendingClaim | null> {
    if (balance < this.threshold) return null;
    const scope = scopeOf(this.chainId, this.distributor, epochIndex, root);
    const signedAttestation = await this.signer.attest(wallet, scope, true);
    if (signedAttestation === null) return null;
    return this.record(epochIndex, wallet, scope, signedAttestation);
  }

  /**
   * Record a claim whose attestation was already produced (e.g. surfaced by the registry or an
   * operator), keyed to this epoch/root scope, ready for the opt-in relay. No signing happens here.
   */
  noteClaim(
    epochIndex: number,
    wallet: Hex,
    root: Hex,
    signedAttestation: Hex,
  ): PendingClaim {
    return this.record(
      epochIndex,
      wallet,
      scopeOf(this.chainId, this.distributor, epochIndex, root),
      signedAttestation,
    );
  }

  private record(
    epochIndex: number,
    wallet: Hex,
    scope: Hex,
    signedAttestation: Hex,
  ): PendingClaim {
    const claim: PendingClaim = {
      epochIndex,
      wallet,
      scope,
      signedAttestation,
      at: BigInt(Date.now()),
    };
    this.claims.push(claim);
    return claim;
  }
}
