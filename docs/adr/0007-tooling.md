# ADR 0007 — Monorepo tooling & pinned versions

- **Status:** Accepted (2026-08-30)
- **Context:** Reproducible builds are a release gate; wandering toolchain versions break bytecode comparison.
- **Decision:**
  - pnpm 11.24.0 + Turborepo 2.10.12 + TypeScript 5.9.x + Node >=20.
  - Solidity 0.8.26, `evm_version` cancun, optimizer runs 200 (deploy profile), bytecode hash ipfs.
  - foundry-std v1.16.2 (bf647bd), OpenZeppelin contracts v5.4.0 (c64a1ed) pinned as git submodules; Uniswap v4 deps added at Phase 5, pinned to the official compatible release then audio-tested.
  - Prettier for JS/TS; `forge fmt` for Solidity; CI runs fmt/build/test + secret/licence scans.
  - Foundry binary resolved via `scripts/forge.sh` (PATH or `~/.foundry/bin`).
- **Consequences:** Lockfile + submodules are reviewed in CI; a clean-checkout install/build must be bit-identical. D005, D006.