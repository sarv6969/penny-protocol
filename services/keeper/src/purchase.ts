import type { Hex } from "viem";
import type { ChainAdapter, RewardDeposit } from "./chain.js";
import type { KeeperConfig } from "./config.js";

/**
 * Sweep → purchase → funding ledger (architecture.md step 2-4). `sweep()` replays
 * `FeeCollector.sweep()` which transfers the whole collector balance to the buyer and — in
 * the same transaction — triggers `BasketBuyer.purchaseBasket()`, emitting `SweptToBasket`
 * then one `RewardsDeposited` per bought Stock Token. The whole cycle is idempotent: a second
 * call no-ops with zero spent once the collector is drained; `purchaseBasket()` no-ops at zero
 * buyer balance.
 */
export interface PurchaseOutcome {
  reason: "below-min-sweep" | "swept";
  sweptWei: bigint;
  spentWei: bigint;
  /** RewardVault deposits observed since `windowStartBlock` (exclusive), per token. */
  deposits: RewardDeposit[];
}

export class PurchaseMachine {
  constructor(
    private readonly adapter: ChainAdapter,
    private readonly config: KeeperConfig,
  ) {}

  /** Deterministic state the keeper reports before acting: can this cycle sweep? */
  async inspect(): Promise<{ collectorWeth: bigint; canSweep: boolean }> {
    const collectorWeth = await this.adapter.getFeeCollectorWeth();
    return {
      collectorWeth,
      canSweep: collectorWeth >= this.config.minSweepWei,
    };
  }

  /**
   * Run one basket-purchase attempt: sweep when the collector tank is at/above `minSweepWei`,
   * then return the funding ledger for deposits made since `windowStartBlock` (the previous
   * epoch's finalization, D029 dust re-absorption uses `priorResidual` — see funding()).
   */
  async purchase(windowStartBlock: number): Promise<PurchaseOutcome> {
    const { canSweep } = await this.inspect();
    if (!canSweep)
      return {
        reason: "below-min-sweep",
        sweptWei: 0n,
        spentWei: 0n,
        deposits: [],
      };

    const sweptWei = await this.adapter.sweep();
    const spentWei =
      sweptWei > 0n ? sweptWei : await this.adapter.purchaseBasket();
    const tip = (await this.adapter.getTip())?.number ?? windowStartBlock;
    const deposits = await this.adapter.getRewardsDeposited(
      windowStartBlock + 1,
      tip,
    );
    deposits.sort(
      (a, b) =>
        a.blockNumber - b.blockNumber || a.purchaseIndex - b.purchaseIndex,
    );
    return { reason: "swept", sweptWei, spentWei, deposits };
  }
}

export interface FundingLedger {
  /** Deposit sums per reward token for this epoch (in wei). */
  perAsset: Map<Hex, bigint>;
  /** Prior epoch residuals re-absorbed this funding window (D029) — sum fed to the pipeline. */
  priorResidual: Map<Hex, bigint>;
  /** This epoch's total funding per token: deposits + priorResidual. */
  fundedTotals: Map<Hex, bigint>;
}

/**
 * Funding-reconcile: fold the purchase ledger into the epoch spec. The manifest's `fundedTotals`
 * must equal `deposits + priorResidual` per asset (reconcile.ts hard gate); residuals from the
 * previous epoch are deterministically re-absorbed before the next distribution.
 */
export function funding(
  deposits: RewardDeposit[],
  priorResidual: ReadonlyMap<Hex, bigint>,
): FundingLedger {
  const perAsset = new Map<Hex, bigint>();
  for (const d of deposits)
    perAsset.set(d.token, (perAsset.get(d.token) ?? 0n) + d.amount);

  const priorResidualNorm = new Map<Hex, bigint>();
  const fundedTotals = new Map<Hex, bigint>();
  const tokens = new Set<Hex>([...perAsset.keys(), ...priorResidual.keys()]);
  for (const token of tokens) {
    const depositsThis = perAsset.get(token) ?? 0n;
    const residual = priorResidual.get(token) ?? 0n;
    priorResidualNorm.set(token, residual);
    fundedTotals.set(token, depositsThis + residual);
  }

  return { perAsset, priorResidual: priorResidualNorm, fundedTotals };
}
