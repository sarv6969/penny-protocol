// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Phase 7 vault; BasketBuyer delivers purchased Stock Tokens here.
interface IRewardVault {
    function receiveRewardAsset(IERC20 token, uint256 amount) external;
}
