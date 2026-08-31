# Developer Handover — Penny Protocol

Repo: https://github.com/sarv6969/penny-protocol
Owner: sarv6969 (non-technical — explain decisions in plain language)
State: feature-complete, all local suites green, **mainnet deployment intentionally blocked**.

## What this is

$PENNY — a fixed-supply ERC-20 on **Robinhood Chain (chain ID 4663)** trading against WETH in a
dedicated Uniswap v4 pool. A custom hook takes a 3% WETH fee on exact-input swaps (both
directions). A keeper periodically spends accumulated WETH on a **rotating basket** of canonical
Robinhood Stock Tokens (launch five: AUR, JOBY, SOUN, SMR, CLOV — equal notional, D035). Purchased
Stock Tokens are distributed to eligible PENNY holders (≥100k at snapshot, jurisdiction-attested)
through cumulative multi-token Merkle epochs. Holders who opt in get **auto-delivery** — a
permissionless relayer pushes their rewards each epoch, no claiming (rewards can only land in the
entitled wallet; the Merkle leaf binds it).

PENNY is NOT redeemable for the basket and does not represent ownership of the Stock Tokens or
underlying shares. Never use ownership language in UI/marketing.

## Read these first (in order)

1. `STATUS.md` — phase-by-phase state + blockers
2. `DECISIONS.md` — dated decision log D001–D034; the contracts implement these exactly
3. `docs/launch-readiness.md` — the go/no-go sheet
4. `docs/compliance-boundaries.md` — the regulatory constraints that shaped the design
5. `docs/architecture.md`, `docs/threat-model.md`

## Layout

```
packages/contracts   Solidity 0.8.26 + Foundry. 109 tests (unit/fuzz/invariant), ~90% line cov
packages/sdk         typed ABIs/constants        packages/config  verified address manifest
services/indexer     reorg-safe balance indexer + deterministic Merkle/manifest pipeline (35 tests)
services/keeper      idempotent job runner: sweep → purchase → snapshot → root → auto-delivery (28 tests)
apps/web             Next.js static status app
scripts/             export-artifacts, secret-scan, soak, fork-test
```

Key contracts: `PennyToken` (fixed 1B), `PennyFeeHook` (v4 hook, immutable 300 bps, CREATE2-mined
address), `FeeCollector` → `BasketBuyer` → `RewardVault` (custody rail, set-once wiring),
`OracleGuard` (fail-closed, staffed session gate — see D009), `RewardDistributor` (cumulative
Merkle, challenge-delayed roots, `claimFor`/`claimForMany` auto-delivery), `EligibilityRegistry`
(expiring scoped attestations + auto-delivery opt-in), `RebalanceController` (rotation, floor 5 /
cap 8, timelocked, onchain reasons).

## Run it

```bash
make setup            # pnpm install + forge submodules
pnpm -r typecheck && pnpm -r test
cd packages/contracts && forge test    # needs Foundry (foundry.sh)
make db-up            # Postgres for indexer (Docker)
```

## Hard blockers before ANY mainnet action (do not bypass — they are code-enforced)

1. `MAINNET_LEGAL_APPROVAL=false` — needs documented counsel signoff (securities/jurisdiction
   analysis; rotation + 3%-fee reward model flagged in D033/D019).
2. **No independent audit yet.** Contracts changed 2026-08-31 (rotation, auto-delivery, security
   fixes R1–R9) — the audit must cover current HEAD.
3. **Liquidity route unverified** — no executable venue confirmed for the five Stock Tokens at
   size. `ILiquidityAdapter` is the integration point; tests use a clearly-labelled MockAdapter.
   If any token lacks a route: NO_GO.
4. **Chainlink feed proxies unresolved** — production `IOracleSource` impl must be built from the
   official Chainlink Robinhood feeds page, verified onchain, added to the manifest. Note: no L2
   sequencer uptime feed exists for Robinhood Chain (D009) — OracleGuard fails closed via a
   staffed session gate until one exists.
5. **HUMAN_INPUT_REQUIRED** values: deployer, Safe signers/threshold, vesting beneficiary,
   liquidity ETH + initial price/range, keeper caps, attestation signer, archive RPC.
6. 48-hour soak on a pinned fork (`scripts/soak-local.sh` is the accelerated battery).

## Housekeeping for the new dev

- **CI workflow**: `.github/workflows/ci.yml` exists locally but was held out of the push (owner's
  OAuth token lacked `workflow` scope). Run `gh auth refresh -s workflow` on an authorized
  machine, then `git add .github/workflows/ci.yml && git commit && git push`.
- Owner should add you as a collaborator with least privilege needed; move the repo to an org
  with branch protection on `main` before real money is involved.
- The owner's local `.env` was never committed. Never commit keys; `scripts/secret-scan.sh` runs
  Tier-1 checks.
- The keeper holds no signing keys by design — production signing must go through KMS/relayer.

## Trust model (short version)

Set-once custody wiring (D031), immutable fee bps, no mint/blacklist/pause on PENNY, timelocked
basket changes with a floor of five, challenge-delayed reward roots with pre-activation
cancellation only, admin can never touch WETH owed to purchases / PENNY / reward assets (D013).
Rotation only redirects future purchases; historical entitlements are token-address-keyed and
immutable.
