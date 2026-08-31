# Penny Stocks

INDEX-style Stock Token rewards product on **Robinhood Chain mainnet (chain ID 4663)**.

- Project token `PENNY` (fixed 1B supply, 18 decimals) trades against WETH in a dedicated Uniswap v4 pool.
- A 3% protocol fee in WETH is collected by a custom v4 hook on exact-input buys and sells.
- A keeper buys five Robinhood Stock Tokens at equal USD weights (20% each).
- Eligible `PENNY` holders earn pro-rata **cumulative** Stock Token entitlements via signed Merkle reward epochs; **`PENNY` is not redeemable for and does not represent ownership of the basket.**
- Launch gated hard on audit, legal approval, live liquidity, human inputs, and soak. **Mainnet is currently `MAINNET_BLOCKED`.**

> Warning: this repo is a living build, not a finished product, and contains zero financial advice.

## Repo layout

```
apps/web              Next.js app (Phase 10 — placeholder)
packages/contracts    Solidity + Foundry (token, allocation, vesting ✅)
packages/sdk          typed ABIs + quote/claim helpers (constants + fee math ✅)
packages/config       verified address manifest + schema (✅)
services/indexer      reorg-safe indexer (Phase 8 — skeleton)
services/keeper       idempotent keeper (Phase 9 — skeleton)
infra/docker          postgres for indexer
docs/                 architecture, economics, threat model, ADRs, runbooks
```

## Quickstart

```bash
make setup            # installs JS deps + forge submodules
make contracts-test   # Solidity tests (14 passing)
pnpm typecheck        # TS across workspaces
pnpm test             # every workspace's tests
```

Node >= 20, pnpm >= 11, Foundry (foundryup).

## Live deployment status

See [STATUS.md](STATUS.md). All mainnet hardware is gated behind the checklist there. Verified addresses live in `packages/config/src/generated/mainnet.verified.json`.

## Documentation

- [Architecture](docs/architecture.md)
- [Economics](docs/economics.md)
- [Compliance boundaries](docs/compliance-boundaries.md)
- [Threat model](docs/threat-model.md)
- [Reward accounting](docs/reward-accounting.md)
- [ADR index](docs/adr/)
- Runbooks: [deployment](docs/deployment-runbook.md) · [operations](docs/operations-runbook.md) · [incident response](docs/incident-response.md)
- [Decisions](DECISIONS.md) · [Status](STATUS.md)

## Safety notes

- No private keys, seeds, or API secrets are stored in this repo. Production signing must use a KMS/Secure relayer.
- Dial `ARCHIVE_RPC_URL` to an authenticated archive RPC before any fork/verification work.
- Mainnet broadcasting is disabled by design until every gate in `STATUS.md` is green.