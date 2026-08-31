import type { Abi } from "viem";

/**
 * Minimal ABI fragments for the keeper's write surface (Phase 9). These mirror the Solidity
 * sources exactly and are the single place the producer keeper encodes calls from; selector
 * tests (`test/abi.test.ts`) pin each fragment to its keccak-derived 4-byte id so a rename
 * in the contracts fails loudly here.
 *
 * Crossing the configured rail is a mainnet-gated action (D009): nothing in this module
 * submits transactions — it only models the calls a configured client would make.
 */
export const FEE_COLLECTOR_SWEEP: Abi = [
  {
    type: "function",
    name: "sweep",
    inputs: [],
    outputs: [{ type: "uint256", name: "basketSpend" }],
    stateMutability: "nonpayable",
  },
];

export const BASKET_PURCHASE: Abi = [
  {
    type: "function",
    name: "purchaseBasket",
    inputs: [],
    outputs: [{ type: "uint256", name: "totalSpent" }],
    stateMutability: "nonpayable",
  },
];

export const DISTRIBUTOR_PUBLISH: Abi = [
  {
    type: "function",
    name: "publishEpoch",
    inputs: [
      { type: "bytes32", name: "root" },
      { type: "address[]", name: "rewardTokens" },
      { type: "uint256[]", name: "cumulativeTotals" },
      { type: "bytes32", name: "manifestHash" },
    ],
    outputs: [{ type: "uint256", name: "epochIndex" }],
    stateMutability: "nonpayable",
  },
];

export const DISTRIBUTOR_CLAIM_FOR_MANY: Abi = [
  {
    type: "function",
    name: "claimForMany",
    inputs: [
      { type: "uint256", name: "epochIndex" },
      {
        type: "tuple[]",
        name: "deliveries",
        components: [
          { type: "address", name: "wallet" },
          { type: "uint256[]", name: "cumulative" },
          { type: "bytes32[]", name: "proof" },
          { type: "uint64", name: "attestationExpiry" },
          { type: "bytes", name: "attestationSignature" },
        ],
      },
    ],
    outputs: [{ type: "uint256", name: "delivered" }],
    stateMutability: "nonpayable",
  },
];

export const DISTRIBUTOR_EPOCH_COUNT: Abi = [
  {
    type: "function",
    name: "epochCount",
    inputs: [],
    outputs: [{ type: "uint256", name: "" }],
    stateMutability: "view",
  },
];
