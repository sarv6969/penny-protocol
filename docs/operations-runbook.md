# Operations runbook

## Roles

- **Protocol ops pager** — keeper health, feed health, reorgs.
- **Governance signers** — Safe/timelock actions (root, rebalance, adapter, pause).
- **Compliance officer** — eligibility registry / jurisdiction policy updates.
- **Security** — incident response lead (see incident-response.md).

## Steady-state

- Keeper polls every 15 min; sweep fires only above min-USD threshold (pauses are honest: no fake 15-minute payouts).
- Metrics (Prometheus/OpenTelemetry): stale jobs, low balances, quote failures, slippage, oracle pause/staleness, sequencer outage, root mismatch, failed claims, reorgs, RPC disagreement, nonce backlog, unusual admin events.
- Daily: reconcile RewardVault funding vs cumulative liabilities; confirm roots match manifests; check indexer checkpoint drift.

## Failure playbooks (non-incident level)

| Symptom | Action |
|---|---|
| Basket purchase reverts for one constituent | Review oracle/session/quote; do NOT mark cycle complete; pending, not partial |
| Oracle stale/paused in market hours | Halt purchases; alert; wait recovery or root correction |
| RPC disagreement | Fail over provider; halt root generation; reconcile first |
| Keeper restart mid-job | Idempotent jobs + unique cycle IDs; resume, never duplicate |
| Root mismatch vs manifest/vault | Halt activation; cancel unactivated root; regenerate manifest; propose again |

## Pause/unpause reward ops

Pause stops fee-sweep and root activation only. It must never trap `PENNY` transfers or freeze claims already active for eligible wallets — policy enforced by the emergency controls in Phase 5-7 ADRs.

## Constituent addition

1. Candidate passes genuine penny-stock screen (share price <$5, mcap <$1B at the reviewed snapshot) OR documented methodology change proposed+timelocked.
2. Official Chainlink feed active + verified; executable liquidity at target size; legal/compliance clear for that issuer.
3. Public reproducible review report → Safe approval → timelock → admission. Future purchases reweight equal across all active constituents; history untouched.
4. Expansion beyond safe atomic limits → deterministic batched purchase state machine (see ADR 0008).

## Signer rotation

Multisig signer add/remove via Safe's standard flow; rotate hot keeper keys via KMS; never print/commit keys.