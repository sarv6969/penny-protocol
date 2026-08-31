// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @notice One-shot deterministic 90/5/5 splitter. Receives the full PENNY supply
///         at construction, then a single `allocate` call sends exact amounts to
///         the launch-liquidity path, the team vesting wallet, and the growth/ops
///         Safe. Never holds value after allocation.
contract PennyAllocator {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;
    address public immutable launchLiquidity;
    address public immutable teamVesting;
    address public immutable growthOpsSafe;

    uint256 public immutable launchLiquidityAmount;
    uint256 public immutable teamVestingAmount;
    uint256 public immutable growthOpsSafeAmount;

    uint256 public immutable totalAllocated;

    bool public allocated;

    constructor(
        address token_,
        address launchLiquidity_,
        address teamVesting_,
        address growthOpsSafe_,
        uint256 launchLiquidityAmount_,
        uint256 teamVestingAmount_,
        uint256 growthOpsSafeAmount_
    ) {
        require(token_ != address(0), "ALLOC: zero token");
        require(launchLiquidity_ != address(0), "ALLOC: zero launch target");
        require(teamVesting_ != address(0), "ALLOC: zero vesting target");
        require(growthOpsSafe_ != address(0), "ALLOC: zero safe target");
        require(launchLiquidityAmount_ != 0, "ALLOC: zero launch amount");
        require(teamVestingAmount_ != 0, "ALLOC: zero vesting amount");
        require(growthOpsSafeAmount_ != 0, "ALLOC: zero safe amount");
        (bool sumOk, uint256 partialSum) = Math.tryAdd(launchLiquidityAmount_, teamVestingAmount_);
        require(sumOk, "ALLOC: overflow");
        (bool totalOk, uint256 total_) = Math.tryAdd(partialSum, growthOpsSafeAmount_);
        require(totalOk, "ALLOC: overflow");

        token = IERC20(token_);
        launchLiquidity = launchLiquidity_;
        teamVesting = teamVesting_;
        growthOpsSafe = growthOpsSafe_;
        launchLiquidityAmount = launchLiquidityAmount_;
        teamVestingAmount = teamVestingAmount_;
        growthOpsSafeAmount = growthOpsSafeAmount_;
        totalAllocated = total_;
    }

    function allocate() external {
        require(!allocated, "ALLOC: already allocated");
        require(token.balanceOf(address(this)) == totalAllocated, "ALLOC: balance mismatch");

        allocated = true;

        token.safeTransfer(launchLiquidity, launchLiquidityAmount);
        token.safeTransfer(teamVesting, teamVestingAmount);
        token.safeTransfer(growthOpsSafe, growthOpsSafeAmount);
    }
}
