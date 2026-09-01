import type { Hex } from "viem";

/**
 * LiFi quote collection + oracle sanity gate (D037, Phase: canary).
 *
 * Every purchase cycle, the keeper asks LiFi for one same-chain route per active constituent
 * (WETH -> stock token) and REJECTS any route whose effective execution price deviates from
 * the Chainlink oracle price beyond `maxDeviationBps`. Only cycles where EVERY active
 * constituent has a passing route proceed to staging — mirroring the contracts' atomic
 * all-or-nothing purchase (a single missing/failed leg reverts the sweep onchain anyway;
 * this gate just avoids wasting gas on cycles that cannot pass).
 *
 * The onchain `RouteAdapter` re-enforces everything that matters (whitelisted router, route
 * expiry, balance-delta vs oracle-derived minOut), so a wrong quote here can only cause a
 * revert, never a loss.
 */

export interface QuoteRequest {
  fromToken: Hex;
  toToken: Hex;
  /** WETH wei to spend on this leg. */
  fromAmount: bigint;
  /** Address the route must deliver to (the BasketBuyer). */
  recipient: Hex;
}

export interface CollectedRoute {
  token: Hex;
  router: Hex;
  callData: Hex;
  /** Route output estimate in token wei (informational — chain enforces minOut). */
  toAmount: bigint;
  /** LiFi tool id, e.g. "nordstern" | "fly" | a Uniswap route. */
  tool: string;
  /** Effective USD price per token implied by the route. */
  execPriceWad: bigint;
  /** Oracle USD price per token (wad). */
  oraclePriceWad: bigint;
  /** |exec - oracle| / oracle in bps. */
  deviationBps: number;
}

export interface QuoteGateResult {
  passed: CollectedRoute[];
  failed: { token: Hex; reason: string }[];
  /** True only when every requested leg passed — the cycle may proceed. */
  cycleViable: boolean;
}

export interface LifiClient {
  /** Returns the raw LiFi /v1/quote JSON for a same-chain swap, or null on no-route. */
  quote(req: QuoteRequest): Promise<LifiQuote | null>;
}

export interface LifiQuote {
  tool: string;
  toAmount: bigint;
  router: Hex;
  callData: Hex;
}

export interface OracleReader {
  /** 18-dec USD price for a token (0 = unknown/dead — leg fails). */
  priceWad(token: Hex): Promise<bigint>;
}

const WAD = 10n ** 18n;

export async function collectQuotes(
  lifi: LifiClient,
  oracle: OracleReader,
  weth: Hex,
  recipient: Hex,
  legs: { token: Hex; fromAmount: bigint }[],
  maxDeviationBps: number,
): Promise<QuoteGateResult> {
  const passed: CollectedRoute[] = [];
  const failed: { token: Hex; reason: string }[] = [];

  const wethUsd = await oracle.priceWad(weth);
  if (wethUsd === 0n) {
    return {
      passed: [],
      failed: legs.map((l) => ({ token: l.token, reason: "WETH oracle dead" })),
      cycleViable: false,
    };
  }

  for (const leg of legs) {
    const oraclePriceWad = await oracle.priceWad(leg.token);
    if (oraclePriceWad === 0n) {
      failed.push({ token: leg.token, reason: "token oracle dead" });
      continue;
    }
    const q = await lifi.quote({
      fromToken: weth,
      toToken: leg.token,
      fromAmount: leg.fromAmount,
      recipient,
    });
    if (q === null || q.toAmount === 0n) {
      failed.push({ token: leg.token, reason: "no route" });
      continue;
    }
    // exec price = usdIn / tokensOut  (all wad math)
    const usdIn = (leg.fromAmount * wethUsd) / WAD;
    const execPriceWad = (usdIn * WAD) / q.toAmount;
    const diff =
      execPriceWad > oraclePriceWad
        ? execPriceWad - oraclePriceWad
        : oraclePriceWad - execPriceWad;
    const deviationBps = Number((diff * 10_000n) / oraclePriceWad);
    if (deviationBps > maxDeviationBps) {
      failed.push({
        token: leg.token,
        reason: `deviation ${deviationBps}bps > cap ${maxDeviationBps}bps (exec vs oracle)`,
      });
      continue;
    }
    passed.push({
      token: leg.token,
      router: q.router,
      callData: q.callData,
      toAmount: q.toAmount,
      tool: q.tool,
      execPriceWad,
      oraclePriceWad,
      deviationBps,
    });
  }

  return { passed, failed, cycleViable: failed.length === 0 && passed.length === legs.length };
}

/** Production LiFi client over HTTPS. Never holds keys; returns executable calldata only. */
export class HttpLifiClient implements LifiClient {
  constructor(
    private readonly chainId: number,
    private readonly fromAddress: Hex,
    private readonly slippage = 0.03,
    private readonly fetchImpl: typeof fetch = fetch,
  ) {}

  async quote(req: QuoteRequest): Promise<LifiQuote | null> {
    const url =
      `https://li.quest/v1/quote?fromChain=${this.chainId}&toChain=${this.chainId}` +
      `&fromToken=${req.fromToken}&toToken=${req.toToken}` +
      `&fromAmount=${req.fromAmount}&fromAddress=${this.fromAddress}` +
      `&toAddress=${req.recipient}&slippage=${this.slippage}`;
    const res = await this.fetchImpl(url, {
      headers: { accept: "application/json" },
    });
    if (!res.ok) return null;
    const d = (await res.json()) as {
      message?: string;
      tool?: string;
      estimate?: { toAmount?: string };
      transactionRequest?: { to?: string; data?: string };
    };
    if (d.message || !d.transactionRequest?.to || !d.transactionRequest.data) {
      return null;
    }
    return {
      tool: d.tool ?? "unknown",
      toAmount: BigInt(d.estimate?.toAmount ?? "0"),
      router: d.transactionRequest.to as Hex,
      callData: d.transactionRequest.data as Hex,
    };
  }
}
