import type { Address, Hex } from "viem";

export const CHAIN_ID_MAINNET = 4663;
export const CHAIN_ID_TESTNET = 46630;
export const NATIVE_TOKEN = "ETH";

export const PENNY_DECIMALS = 18;
export const PENNY_TOTAL_SUPPLY = 1_000_000_000n * 10n ** 18n;

export const PROTOCOL_FEE_BPS = 300;
export const ELIGIBLE_BALANCE_THRESHOLD = 100_000n * 10n ** 18n;
export const CONSTITUENT_TARGET_WEIGHT_BPS = 2_000;
export const TEAM_VEST_DURATION_SECONDS = 365n * 24n * 3600n;

export const BASKET_TICKERS = ["AUR", "JOBY", "SOUN", "SMR", "CLOV"] as const;

/** Canonical Robinhood Stock Token addresses for the founding basket (verified onchain
 *  at block 51123566 — see packages/config generated manifest, D035). */
export const BASKET_TOKENS: Record<(typeof BASKET_TICKERS)[number], Address> = {
  AUR: "0x373C06c4f7BDe527D7Dae4BA169E42b55E393CeD",
  JOBY: "0xb334C5cE741B80B5B671F47F5C269Cb193fe8E24",
  SOUN: "0x6E3Dfd9f7e1649BaA14D25cac18C94d62dB10A54",
  SMR: "0x1Eebee7F74517e0279dFb09d25B0407bEEc3FDd6",
  CLOV: "0x62200915e7DEab1eC7f79fb246daDbB80eACdDd0",
};

export interface Constituent {
  ticker: string;
  name: string;
  token: Address;
  targetWeightBps: number;
  uiMultiplier?: bigint;
  oraclePaused?: boolean;
}

export interface VerifiedManifestEntry {
  address: Address;
  name: string;
  symbol?: string;
  decimals: number;
  sourceUrl: string;
  verifiedAtBlock?: number;
  codeHash?: Hex;
  status: "confirmed-by-docs" | "verified-onchain" | "blocked";
}

export function targetWeightBpsFor(index?: number): number {
  void index;
  return CONSTITUENT_TARGET_WEIGHT_BPS;
}

export function minimumExpectedOutput(inputNotionalUsd: bigint, protocolFeeBps = PROTOCOL_FEE_BPS): bigint {
  return (inputNotionalUsd * BigInt(10_000 - protocolFeeBps)) / 10_000n;
}