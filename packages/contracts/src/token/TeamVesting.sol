// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {VestingWallet} from "@openzeppelin/contracts/finance/VestingWallet.sol";

/// @notice Team allocation vesting contract. Linear vesting over the configured
///         duration, released via the standard releasable/release flow. No admin
///         can accelerate or redirect vested balances.
contract TeamVesting is VestingWallet {
    constructor(address beneficiary, uint64 startTimestamp, uint64 durationSeconds)
        VestingWallet(beneficiary, startTimestamp, durationSeconds)
    {}
}
