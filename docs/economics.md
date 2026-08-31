# Economics

Locked defaults. Typed deployment config must be pushed from `packages/config`; the live values are `HUMAN_INPUT_REQUIRED` before mainnet.

| Parameter | Value |
|---|---|
| `TOTAL_SUPPLY` | 1,000,000,000e18 |
| `LAUNCH_LIQUIDITY_ALLOCATION` | 90% |
| `TEAM_VESTED_ALLOCATION` | 5% (12-month linear vest) |
| `GROWTH_OPS_SAFE_ALLOCATION` | 5% |
| `PROTOCOL_FEE_BPS` | 300 (immutable, 3%) |
| `ELIGIBLE_BALANCE_THRESHOLD` | 100,000e18 (0.01% of supply) |
| `CONSTITUENT_COUNT` | 5 |
| `INITIAL_TARGET_WEIGHT_BPS_EACH` | 2,000 |
| `FUTURE_WEIGHTING` | equal across active constituents |
| `KEEPER_CHECK_INTERVAL` | 15 minutes |
| `REBALANCE_REVIEW_INTERVAL` | quarterly |

## Fee mechanics

- Exact-input swaps only in v1 (exact-output rejected). WETH-in buy: 3% of specified WETH in is diverted; 97% goes to the swap. PENNY-in sell: 3% of actual WETH out is deducted; user receives 97%.
- Fee is **WETH only**, always to `FeeCollector`, never PENNY.
- Any separate Uniswap LP / protocol fee is shown alongside. The all-in trading cost must be disclosed plainly; never market it as "3%" when higher.

## Fee disposition

100% of net WETH fees fund Stock Token purchases. Only explicit, capped, onchain-visible keeper gas reimbursement may be deducted. No team/dev/marketing/referral skim. Every accrual/sweep/reimbursement/purchase is an event.

## Launch basket (equal weight, 20% each)

AUR · JOBY · SOUN · SMR · CLOV — see verified manifest for addresses (D035, verified onchain at block 51123566). Dated snapshot values (e.g. "AUR ~$5.50") are screening notes, NOT oracles; contracts know nothing of them.

## Reward epochs

- Purchased Stock Tokens go to `RewardVault`.
- Each funded epoch: snapshot at finalized block → eligible supply → pro-rata entitlements per asset in exact integer math → deterministic rounding/dust rule → cumulative Merkle root.
- `cumulative - claimed` transfers at claim.time. Root activation behind challenge delay; unactivated erroneous root cancellable; completed claims irrevocable.
- New roots cannot exceed vault funding; onchain caps + offchain manifest validation prove it.

## Governance red lines

- Basket cannot be reduced below five founding constituents except documented availability/oracle/liquidity/legal emergency.
- No governance: sets non-100% weights, redirects rewards, withdraws user reward assets, mints PENNY, raises fee above 3%, silently replaces the pool.
- Friendly recoverable: only accidental unrelated deposits, timelocked.

## LP lock

Initial v4 LP is irreversible after an explicit launch action. Whether fee collection/range rebalancing/compounding stays possible is stated exactly; "permanently locked" must match the UI. Irreversible action never executed in this build.