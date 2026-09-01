import assert from "node:assert/strict";
import test from "node:test";
import type { Hex } from "viem";
import {
  collectQuotes,
  type LifiClient,
  type LifiQuote,
  type OracleReader,
  type QuoteRequest,
} from "../src/quotes.js";

const WETH: Hex = "0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73";
const USAR: Hex = "0xd917B029C761D264c6A312BBbcDA868658eF86a6";
const RKLB: Hex = "0x3b14C39E89D60D627b42a1A4CA45b5bb45Fc12e2";
const BUYER: Hex = "0x1111111111111111111111111111111111111111";
const ROUTER: Hex = "0xB477751B76CF82d00a686A1232f5fCD772414Af3";
const E18 = 10n ** 18n;

/** Oracle: ETH $2460, USAR $17.88, RKLB $64.02 (live values from 2026-09-01). */
const oracle: OracleReader = {
  async priceWad(token) {
    if (token === WETH) return 2460n * E18;
    if (token === USAR) return 1788n * E18 / 100n;
    if (token === RKLB) return 6402n * E18 / 100n;
    return 0n;
  },
};

/** Builds a client that returns a route delivering `tokens` out for the leg. */
function clientReturning(map: Record<string, bigint | null>): LifiClient {
  return {
    async quote(req: QuoteRequest): Promise<LifiQuote | null> {
      const out = map[req.toToken];
      if (out === null || out === undefined) return null;
      return {
        tool: "nordstern",
        toAmount: out,
        router: ROUTER,
        callData: "0xdeadbeef",
      };
    },
  };
}

const LEG = 2n * 10n ** 16n; // 0.02 WETH -> $49.20 at $2460

test("accepts a route priced at the oracle (USAR real case, +0.16%)", async () => {
  // $49.20 / $17.905 ≈ 2.7479 USAR
  const client = clientReturning({ [USAR]: 2747900000000000000n });
  const r = await collectQuotes(client, oracle, WETH, BUYER, [{ token: USAR, fromAmount: LEG }], 500);
  assert.equal(r.cycleViable, true);
  assert.equal(r.passed.length, 1);
  assert.ok(r.passed[0]!.deviationBps <= 100, `dev ${r.passed[0]!.deviationBps}bps should be tiny`);
  assert.equal(r.passed[0]!.router, ROUTER);
  assert.equal(r.passed[0]!.callData, "0xdeadbeef");
});

test("rejects a route beyond the deviation cap (RKLB real case, +12.5%)", async () => {
  // $49.20 at an effective $72.04 => 0.68296 RKLB
  const client = clientReturning({ [RKLB]: 682960000000000000n });
  const r = await collectQuotes(client, oracle, WETH, BUYER, [{ token: RKLB, fromAmount: LEG }], 500);
  assert.equal(r.cycleViable, false);
  assert.equal(r.passed.length, 0);
  assert.match(r.failed[0]!.reason, /deviation \d+bps > cap 500bps/);
});

test("a cheaper-than-oracle route still passes while inside the band", async () => {
  // 3% better than oracle: more tokens out
  const fair = (49_20n * E18) / 1788n; // ~2.7517
  const client = clientReturning({ [USAR]: (fair * 103n) / 100n });
  const r = await collectQuotes(client, oracle, WETH, BUYER, [{ token: USAR, fromAmount: LEG }], 500);
  assert.equal(r.cycleViable, true);
});

test("no-route legs fail closed and sink the cycle", async () => {
  const client = clientReturning({ [USAR]: null });
  const r = await collectQuotes(client, oracle, WETH, BUYER, [{ token: USAR, fromAmount: LEG }], 500);
  assert.equal(r.cycleViable, false);
  assert.equal(r.failed[0]!.reason, "no route");
});

test("dead token oracle fails closed without calling the venue", async () => {
  let called = 0;
  const client: LifiClient = {
    async quote() {
      called++;
      return { tool: "x", toAmount: 1n, router: ROUTER, callData: "0x" };
    },
  };
  const unknown: Hex = "0x2222222222222222222222222222222222222222";
  const r = await collectQuotes(client, oracle, WETH, BUYER, [{ token: unknown, fromAmount: LEG }], 500);
  assert.equal(r.cycleViable, false);
  assert.equal(r.failed[0]!.reason, "token oracle dead");
  assert.equal(called, 0, "must not request a quote when the oracle is dead");
});

test("dead WETH oracle sinks every leg", async () => {
  const deadEth: OracleReader = { async priceWad() { return 0n; } };
  const client = clientReturning({ [USAR]: 1n });
  const r = await collectQuotes(client, deadEth, WETH, BUYER, [{ token: USAR, fromAmount: LEG }], 500);
  assert.equal(r.cycleViable, false);
  assert.equal(r.failed[0]!.reason, "WETH oracle dead");
});

test("multi-leg cycle is all-or-nothing (mirrors the atomic onchain purchase)", async () => {
  const fairUsar = (49_20n * E18) / 1788n;
  const client = clientReturning({
    [USAR]: fairUsar, // good
    [RKLB]: 682960000000000000n, // 12.5% off
  });
  const r = await collectQuotes(
    client,
    oracle,
    WETH,
    BUYER,
    [
      { token: USAR, fromAmount: LEG },
      { token: RKLB, fromAmount: LEG },
    ],
    500,
  );
  assert.equal(r.passed.length, 1, "one leg is fine on its own");
  assert.equal(r.failed.length, 1);
  assert.equal(r.cycleViable, false, "but the cycle must not proceed");
});
