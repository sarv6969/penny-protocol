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

export const BASKET_TICKERS = ["TE", "POET", "NNE", "WYFI", "RCAT"] as const;

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