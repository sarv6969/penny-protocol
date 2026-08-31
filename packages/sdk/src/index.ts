import { PENNY_TOTAL_SUPPLY } from "./constants.js";

export {
  CHAIN_ID_MAINNET,
  CHAIN_ID_TESTNET,
  NATIVE_TOKEN,
  PENNY_DECIMALS,
  PENNY_TOTAL_SUPPLY,
  PROTOCOL_FEE_BPS,
  ELIGIBLE_BALANCE_THRESHOLD,
  CONSTITUENT_TARGET_WEIGHT_BPS,
  TEAM_VEST_DURATION_SECONDS,
  BASKET_TICKERS,
  BASKET_TOKENS,
  type Constituent,
  type VerifiedManifestEntry,
  targetWeightBpsFor,
  minimumExpectedOutput,
} from "./constants.js";

export const PENNY_ABI = [
  {
    inputs: [
      { internalType: "uint256", name: "totalSupply", type: "uint256" },
      { internalType: "address", name: "initialRecipient", type: "address" },
    ],
    name: "constructor",
    outputs: [],
    stateMutability: "nonpayable",
    type: "constructor",
  },
  {
    inputs: [],
    name: "totalSupply",
    outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
] as const;

export function isFixedSupplyAmount(amount: bigint): boolean {
  return amount === PENNY_TOTAL_SUPPLY;
}

export function render(address: string): string {
  return address.slice(0, 6) + "..." + address.slice(-4);
}