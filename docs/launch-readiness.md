# Launch readiness — Penny Stocks mainnet dry-run bundle

_Updated: 2026-08-31 · Bundle v1 (dry-run; nothing deployed)_

This is the honest go/no-go sheet for the phase-12 launch bundle. Every line is either
a **shipped artifact** (produced and verified on this machine) or a **holding gate**
(requires humans/infrastructure the repo cannot fabricate).

## Shipped artifacts (verified here)

| Artifact | Location | Proof |
|---|---|---|
| Contract ABIs + creation/deployed bytecode + compiler metadata | `artifacts/*.json` (11 contracts) | `scripts/export-artifacts.sh`; checksums in `artifacts/SHA256SUMS` |
| Deployment script | `packages/contracts/src/DeployPennyFeeHook.s.sol` | `forge script` target; salts CREATE2-mine the hook flags (bits 7,6,3,2) |
| Genesis values + verified Stock Token address manifest | `packages/config/src/generated/mainnet.verified.json` (pinned block 49902198) | `eth_getCode`/symbol/decimals/`uiMultiplier`/`oraclePaused` re-checked onchain |
| Golden manifest + Solidity↔JS lockstep | `packages/contracts/test/fixtures/manifest.golden.json`; `ManifestCrossCheck.t.sol` | 2/2 cross-check tests green |
| Test suite w/ invariants | `packages/contracts` — **82 tests**, incl. 4 invariant suites | `forge test`; coverage 89.87% lines in `coverage-summary.txt`; `.gas-snapshot` |
| Accelerated local soak | `scripts/soak-local.sh` | bounded 60k fuzz runs + invariant battery + 3×flake replay, all green |
| Secret + licence gates | `scripts/secret-scan.sh`; `pnpm licenses list` | Tier-1 scan PASS (no key material in committed source); dependency licences reviewed in `docs/evidence/licences.md` |
| Keeper (off-chain operator) | `@penny/keeper` — **24 tests** | write-ahead intents, warm-start crash recovery, durable JSONL ledger, fail-closed drift guard, Postgres `StepStore` impl behind the same interface |
| Indexer | `@penny/indexer` — **35 tests** | reorg-safe ingest, confirmation-depth finality, manifests |
| Web claim-status UI | `apps/web`, static export | `scripts/web-smoke.sh` green (sample manifest only) |

## Dry-run bundle contents

1. `artifacts/` + `SHA256SUMS` (immutable contract images).
2. `packages/config/src/generated/mainnet.verified.json` → genesis inputs.
3. `scripts/deploy*.sh`/`DeployPennyFeeHook.s.sol` → CREATE2 deployment sequence.
4. Genesis Epoch 0 manifest `public/manifest.sample.json` shape for the indexer/keeper/web.

## Go / No-go matrix (as of today)

| Gate | State | Who unlocks |
|---|---|---|
| `MAINNET_LEGAL_APPROVAL` | **NO-GO** (hard stop) | Legal counsel signoff (as documented in `docs/compliance.md`) |
| Independent audit + remediation | **Blocker** | Nominated auditor |
| Live executable quote/depth on all 5 Stock Tokens at target size/slippage | **Blocker** | Confirmed production route (Rialto/0x/LiFi…) on Robinhood Chain |
| Chainlink feed resolution (decimals/heartbeat/proxy) for the 5 assets + sequencer-uptime design | **Blocker** | Staffed oracle/session solution (D009; OracleGuard currently fails closed) |
| Keeper signing key via KMS/relayer (no keys in repo) | **Blocker** | Operator |
| 48h anchored testnet/fork soak | **Not run (need docker + ARCHIVE_RPC_URL)** | Infra; local accelerated battery green (`scripts/soak-local.sh`) |
| Postgres-backed indexer/keeper runtime | **Not run (need docker)** | Infra; schema shipped in `pg-store.ts`, JSONL ledger covers non-Postgres runs |
| Human inputs (deployer, Safe signers, treasury, amounts, scope, launch timestamp) | **Blocker** | Humans |

## Claims that are intentionally NOT made

- No contract has been audited by a third party.
- No liquidity, quote, or depth has been verified on a production venue.
- No real feed addresses are resolved and no keeper key exists.
- Everything above is a **dry run**; the system fails closed anywhere a gate
  (venueArmed, eligibility, session, drift guard, legal flag) is not satisfied.