// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRewardVault} from "../../src/basket/IRewardVault.sol";

/// @notice Test-only reward vault: PULLS delivered tokens exactly like the production
///         RewardVault (custody and record move in the same call).
contract MockRewardVault is IRewardVault {
    mapping(address => uint256) public holdings;

    event RewardReceived(address indexed token, uint256 amount);

    function receiveRewardAsset(IERC20 token, uint256 amount) external {
        require(token.transferFrom(msg.sender, address(this), amount), "MRV: pull failed");
        holdings[address(token)] += amount;
        emit RewardReceived(address(token), amount);
    }
}
