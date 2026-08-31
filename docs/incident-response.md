# Incident response

Severity: **P1** = funds/user harm · **P2** = reward rail down · **P3** = degraded observability.

## Principles

- Never silently fix an exploited or anomalous path; follow the checklist.
- Every P1/P2 gets a postmortem appended to `DECISIONS.md` with evidence.

## P1 — suspected exploit (unexpected WETH/reward loss)

1. **Immediately pause reward ops** (fee-sweep + root activation). Never freeze `PENNY` transfers.
2. Identify exploit vector from onchain trace (tracer/Tenderly-equivalent on local fork); capture the tx.
3. Confirm whether reward/claim state is compromised; if a root was activated maliciously, record affected wallets — completed claims are not clawed back.
4. If vector is in hook/basket logic, take down keeper and keep swap surface honest; quantify loss; notify security.
5. Reproduce on a fork, write regression test, THEN fix; redeploy path changes only via timelock/Safe.

## P2 — reward rail down (keeper stops / oracle stuck / root mismatch)

1. Determine stage: sweep, purchase, snapshot, tree, propose, activate, claim-relay.
2. Run the relevant playbook (see operations-runbook) — idempotency means resume is safe.
3. Root mismatch: cancel unactivated root, regenerate manifest from same snapshot inputs, re-propose.
4. Oracle/session issue: purchases pause until recovery rules satisfied; do not force through.

## P3 — degraded monitoring / RPC disagreement

- Fail over RPC provider; reconcile indexer checkpoints; alert if disagreement persists.

## Contacts & comms

- P1: security lead + ops pager immediate; no public statements without counsel.
- Keep a comms log; postmortem within 48h of stabilisation.

## After-action

- Update threat model, tests, and runbooks; track fix in STATUS.md.