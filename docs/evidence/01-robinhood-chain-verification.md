# Evidence — Robinhood Chain verification (Phase 1)

Research method: official primary sources only (Robinhood Chain docs, Chainlink docs,
Uniswap developer docs, O1 docs). Retrieved 2026-08-30.
Source URLs inline. Everything unverifiable is in "BLOCKED".

## Confirmed

| Fact | Confirmation | Source |
|---|---|---|
| Mainnet chain ID 4663; testnet 46630 | YES | https://docs.robinhood.com/chain/connecting/ |
| Native gas token ETH (Arbitrum L2) | YES | https://docs.robinhood.com/chain/connecting/ |
| Mainnet RPC https://rpc.mainnet.chain.robinhood.com | YES | https://docs.robinhood.com/chain/connecting/ |
| Testnet RPC https://rpc.testnet.chain.robinhood.com | YES | https://docs.robinhood.com/chain/connecting/ |
| Explorer https://robinhoodchain.blockscout.com | YES | https://docs.robinhood.com/chain/connecting/ |
| Testnet explorer https://explorer.testnet.chain.robinhood.com | YES | https://docs.robinhood.com/chain/connecting/ |
| WETH `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73` | YES | https://docs.robinhood.com/chain/contracts/ (Token Smart Contracts) |
| USDG `0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168` | YES | https://docs.robinhood.com/chain/contracts/ (Token Smart Contracts) |
| PoolManager `0x8366a39cc670b4001a1121b8f6a443a643e40951` | YES | https://developers.uniswap.org/docs/protocols/v4/deployments (Robinhood Chain: 4663) |
| PositionManager `0x58daec3116aae6d93017baaea7749052e8a04fa7` | YES | same |
| PositionDescriptor `0x9639443158e8c5efa35bd45287bf2effd3d8dc06` | YES | same |
| Quoter `0x8dc178efb8111bb0973dd9d722ebeff267c98f94` | YES | same |
| StateView `0xf3334192d15450cdd385c8b70e03f9a6bd9e673b` | YES | same |
| ReservesLens `0x0000001b173C3bbF3984D417d8614E3eed34865B` | YES | same |
| Universal Router `0x8876789976decbfcbbbe364623c63652db8c0904` | YES | same (no Universal Router 2.1.1 row listed for Robinhood Chain) |
| Permit2 `0x000000000022D473030F116dDEE9F6B43aC78BA3` | YES | same |
| Stock Tokens = tokenised debt securities of Robinhood Assets (Jersey) Ltd; not registered under US securities laws; blocked for US persons; restrictions e.g. CA/UK/CH | YES | https://docs.robinhood.com/chain/stock-tokens/ |
| Chainlink per-token feeds on Robinhood Chain; price includes corporate-action multiplier via `uiMultiplier()` (do NOT multiply twice); `oraclePaused()` pauses updates; feeds 24/5 | YES | https://docs.robinhood.com/chain/oracles-and-price-feeds/ and https://docs.chain.link/data-feeds/tokenized-equity-feeds/robinhood |
| Liquidity venues: 0x RFQ, 1inch Fusion, LiFi, Uniswap AMM, Rialto propAMM, Lighter orderbook | YES | https://docs.robinhood.com/chain/building-with-stock-tokens/ (Trading Venues & Liquidity) |
| Uniswap v4 deployed on Robinhood Chain (4663) | YES | https://developers.uniswap.org/docs/protocols/v4/deployments |
| O1 catalog lists TE/POET/NNE/WYFI/RCAT at the five given addresses | YES | https://docs.o1.exchange/launchpad/create/stock-paired-launches |

## BLOCKED (unverifiable from official sources)

- **Chainlink L2 Sequencer Uptime Feed proxy for Robinhood Chain: none documented.** Robinhood recommends "verify the sequencer is up"; Chainlink's L2 sequencer feeds page does not list Robinhood Chain. Do NOT hardcode another L2's feed address. (D009)
- **Onchain state of all addresses above** (bytecode, code hash, symbol, decimals, activity for Stock Tokens; `uiMultiplier`, `oraclePaused`, active/status; Uniswap deployment bytecode; Chainlink feed proxies + decimals + heartbeats): NOT yet verified at a pinned block — requires an authenticated archive RPC (Phase 1a).
- **Robinhood contracts page static list:** Stock Token/ETF table is JS-rendered from an onchain registry; no static address list in fetch. Token addresses cross-checked via O1 catalog only.
- **Universal Router 2.1.1 on Robinhood Chain:** not listed; do not assume.

## Next step (Phase 1a, blocked on RPC)

With an authenticated archive-capable RPC: for each manifest address run `eth_getCode`, verify code hash, ERC-20 metadata (symbol/decimals), ERC-8056 methods, active status, feed `decimals()`/heartbeat, and record block + results in the generated manifest. Fail closed on any mismatch.