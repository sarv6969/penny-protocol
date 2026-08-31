import assert from "node:assert/strict";
import test from "node:test";
import type { Hex } from "viem";
import {
  AttestationService,
  scopeOf,
  StubSigner,
  type EligibilitySigner,
} from "../src/index.js";

const E18 = 10n ** 18n;
const THRESHOLD = 100_000n * E18;
const WALLET: Hex = "0x1111111111111111111111111111111111111111";
const ROOT: Hex = ("0x" + "ab".repeat(32)) as Hex;
const EPOCH = 3;
const CHAIN_ID = 4663;
const DISTRIBUTOR: Hex = "0xdddddddddddddddddddddddddddddddddddddddd";

test("attestEligibility gates on the balance threshold (below / at / above)", async () => {
  const svc = new AttestationService(new StubSigner(), THRESHOLD, CHAIN_ID, DISTRIBUTOR);
  assert.equal(
    await svc.attestEligibility(WALLET, THRESHOLD - 1n, EPOCH, ROOT),
    null,
  );
  const at = await svc.attestEligibility(WALLET, THRESHOLD, EPOCH, ROOT);
  assert.ok(at);
  assert.equal(at.scope, scopeOf(CHAIN_ID, DISTRIBUTOR, EPOCH, ROOT));
  const above = await svc.attestEligibility(
    WALLET,
    THRESHOLD + 1n,
    EPOCH,
    ROOT,
  );
  assert.ok(above);
  assert.equal(above.scope, scopeOf(CHAIN_ID, DISTRIBUTOR, EPOCH, ROOT));
});

test("attestation scope is derived deterministically and matches the onchain scopeOf", async () => {
  const svc = new AttestationService(new StubSigner(), THRESHOLD, CHAIN_ID, DISTRIBUTOR);
  const a = await svc.attestEligibility(WALLET, THRESHOLD, EPOCH, ROOT);
  const b = await svc.attestEligibility(WALLET, THRESHOLD, EPOCH, ROOT);
  assert.ok(a && b);
  assert.equal(a.scope, b.scope);
  assert.equal(a.scope, scopeOf(CHAIN_ID, DISTRIBUTOR, EPOCH, ROOT));
  assert.notEqual(a.scope, scopeOf(CHAIN_ID, DISTRIBUTOR, EPOCH + 1, ROOT));
  const note = svc.noteClaim(EPOCH, WALLET, ROOT, a.signedAttestation);
  assert.equal(note.scope, scopeOf(CHAIN_ID, DISTRIBUTOR, EPOCH, ROOT));
});

test("full EligibilitySigner flow plumbs the attestation wire without any signing secret", async () => {
  const signer: EligibilitySigner = new StubSigner();
  const svc = new AttestationService(signer, THRESHOLD, CHAIN_ID, DISTRIBUTOR);
  const claim = await svc.attestEligibility(WALLET, THRESHOLD, EPOCH, ROOT);
  assert.ok(claim);
  const scope = scopeOf(CHAIN_ID, DISTRIBUTOR, EPOCH, ROOT);
  assert.equal(claim.wallet, WALLET);
  assert.equal(claim.epochIndex, EPOCH);
  assert.equal(claim.scope, scope);
  assert.equal(claim.signedAttestation, await signer.sign(WALLET, scope));
  assert.equal(claim.signedAttestation.length, 66);
  assert.equal(typeof claim.at, "bigint");
  // No key material rides on the claim or the service object.
  assert.deepEqual(Object.keys(claim).sort(), [
    "at",
    "epochIndex",
    "scope",
    "signedAttestation",
    "wallet",
  ]);
  assert.ok(!("key" in svc));
  assert.ok(!("secret" in svc));
});

test("noteClaim records a pre-signed attestation ready for the opt-in relay", async () => {
  const svc = new AttestationService(new StubSigner(), THRESHOLD, CHAIN_ID, DISTRIBUTOR);
  const signer = new StubSigner();
  const sig = await signer.sign(WALLET, scopeOf(CHAIN_ID, DISTRIBUTOR, EPOCH, ROOT));
  const claim = svc.noteClaim(EPOCH, WALLET, ROOT, sig);
  assert.equal(claim.signedAttestation, sig);
  assert.equal(claim.scope, scopeOf(CHAIN_ID, DISTRIBUTOR, EPOCH, ROOT));
  assert.equal(claim.wallet, WALLET);
  assert.equal(typeof claim.at, "bigint");
});
