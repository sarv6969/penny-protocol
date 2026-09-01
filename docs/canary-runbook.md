# $PONEY Canary — Launch Runbook

**What this is:** an explicitly-labelled *test* deployment of the full Penny Stocks rail on
Robinhood Chain mainnet. Real contracts, real Chainlink feeds, real (tiny) money. It exists to
prove the machine works end-to-end: trade → 3% fee → buyback → vault → epoch → auto-delivery.

**What this is NOT:** the production $PENNY launch. Different token, canary supply, 1-stock
basket, 3-minute cadence, no marketing, no public invitation to buy.

---

## 0. Preflight (why the basket is 1 stock)

Live quote check on 2026-09-01 (WETH → stock, vs Chainlink):

| Stock | Chainlink | Executable | Deviation | Verdict |
|---|---|---|---|---|
| **USAR** | $17.88 | $17.90 | **+0.16%** | ✅ within 5% cap |
| RKLB | $64.02 | $72.04 | +12.53% | ❌ rejected |
| RGTI | $15.66 | $16.95 | +8.28% | ❌ rejected |
| CLSK | $11.62 | $12.57 | +8.09% | ❌ rejected |
| IONQ | — | no route | — | ❌ no venue |

The canary launches with **USAR only**. Constituents are added by timelocked rotation as their
executable routes come inside the cap. Re-run the check before deploying — routes move daily:

```bash
bash scripts/check-routes.sh
```

---

## 1. What you need

- **A funded deployer wallet on Robinhood Chain** — a *fresh* key used only for this canary.
  Never a production treasury key.
- **~0.05 ETH** total: ~0.018 deploy gas + pool liquidity + swap gas + keeper gas.
- Foundry installed (`foundryup`).

> I never see or handle your key. You export it locally; `forge` reads it from your shell.

---

## 2. Configure

Copy `.env.canary.example` → `.env.canary` and fill the three human values
(`PRIVATE_KEY`, `KEEPER_ADDRESS`, `ATTESTATION_SIGNER`). Everything else is pre-filled with
onchain-verified mainnet addresses.

```bash
cp .env.canary.example .env.canary
$EDITOR .env.canary        # add your keys/addresses
```

Sanity-check the config resolves to live contracts:

```bash
set -a; . ./.env.canary; set +a
cast code $WETH_ADDRESS   --rpc-url $RPC_URL | wc -c   # non-trivial
cast call $FEED_ETH_USD "latestRoundData()(uint80,int256,uint256,uint256,uint80)" --rpc-url $RPC_URL
```

---

## 3. Dry run (no broadcast — do this first, always)

```bash
cd packages/contracts
set -a; . ../../.env.canary; set +a
forge script script/DeployCanary.s.sol:DeployCanaryScript --rpc-url $RPC_URL
```

Expect: `SIMULATION COMPLETE`, ~0.0174 ETH estimated gas, and the 12-contract address report.
**If anything reverts here, stop.** Do not proceed to broadcast.

---

## 4. Deploy (broadcast — this spends real ETH)

```bash
forge script script/DeployCanary.s.sol:DeployCanaryScript \
  --rpc-url $RPC_URL --broadcast --slow
```

Save the printed addresses into `.env.canary` (`PONEY_TOKEN`, `HOOK`, `COLLECTOR`, `BUYER`,
`ADAPTER`, `VAULT`, `DISTRIBUTOR`, `ORACLE`, `GUARD`, `REBALANCE`).

State after this step: contracts live, pool initialized, **no liquidity, market session CLOSED,
no buybacks possible yet.** That is intentional.

---

## 5. Add liquidity

The pool exists but is empty. Add a small two-sided position via the v4 PositionManager
(`0x58daec3116aae6d93017baaea7749052e8a04fa7`). Suggested canary size: **0.01 ETH + the
matching PONEY at your chosen price**, full range.

> Do this yourself in a wallet/UI you trust, or ask me to prepare a `mint` script. Keep it
> small: this is a test, and canary LP is not locked.

---

## 6. Open the market session (staffed gate, D009)

Robinhood Chain publishes no sequencer-uptime feed, so purchases stay fail-closed until a human
opens a session. Sessions auto-expire (8h default), which is the point.

```bash
cast send $GUARD "setMarketOpen(bool)" true --rpc-url $RPC_URL --private-key $PRIVATE_KEY
cast call $GUARD "marketOpen()(bool)" --rpc-url $RPC_URL    # -> true
```

Only open during US equity market hours — the feeds are 24/5 and hold last price when closed.

---

## 7. Generate fee volume

Swap ETH↔PONEY a few times through a v4 router. Each swap sends 3% of the WETH leg to the
FeeCollector. Watch it accrue:

```bash
cast call $WETH_ADDRESS "balanceOf(address)(uint256)" $COLLECTOR --rpc-url $RPC_URL
```

Once the balance clears `MIN_SWEEP_WEI` (0.002 ETH default), a buyback can fire.

---

## 8. Run the keeper (3-minute cadence)

```bash
pnpm --filter @penny/keeper start
```

Each cycle the keeper: fetches a LiFi quote for USAR → checks it against Chainlink (rejects
>5% deviation) → stages the route on `RouteAdapter` → calls `sweep()` → the buyer purchases
under the onchain oracle floor → USAR lands in the RewardVault.

Verify a buyback happened:

```bash
cast call $CANARY_TOKENS "balanceOf(address)(uint256)" $VAULT --rpc-url $RPC_URL
cast call $VAULT "lifetimeDeposits(address)(uint256)" $CANARY_TOKENS --rpc-url $RPC_URL
```

Both should be equal and non-zero. **That is the moment the whole thesis is proven.**

---

## 9. Rewards (epoch → auto-delivery)

Keeper builds the snapshot, publishes a Merkle root, waits the 5-minute challenge delay, then
delivers to opted-in wallets. To receive automatically, opt in once:

```bash
cast send $REGISTRY "setAutoDelivery(bool)" true --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

Then watch USAR arrive in the holder wallet with no claim transaction.

---

## Kill switches

| Situation | Command |
|---|---|
| Stop all buybacks | `cast send $COLLECTOR "setSweepsPaused(bool)" true …` |
| Close oracle session | `cast send $GUARD "setMarketOpen(bool)" false …` |
| Kill a bad root pre-activation | `cast send $DISTRIBUTOR "cancelEpoch(uint256)" <idx> …` |
| Stop the keeper | Ctrl-C — everything is idempotent and resumes cleanly |

Note: nothing here can freeze PONEY transfers or seize user assets — by design.

---

## Known canary limitations (be honest about these)

1. **One constituent.** Not the 5-stock product; it's a rail test.
2. **LP is not locked.** Production requires the irreversible lock; the canary deliberately
   keeps liquidity recoverable.
3. **Deployer holds all roles.** Production requires Safe + timelock. Canary is single-key for
   speed — which is exactly why it must stay small and unadvertised.
4. **Venue depth is thin.** Buybacks are tiny; large orders would move price badly.
5. **Not audited at this commit.** The oracle/adapter/canary code postdates any prior review.
