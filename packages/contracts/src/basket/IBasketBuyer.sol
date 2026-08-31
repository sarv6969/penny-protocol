// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

/// @notice Buyer surface used by FeeCollector.sweep().
interface IBasketBuyer {
    /// @notice Purchases the active basket with the caller-facing WETH balance held by the buyer.
    function purchaseBasket() external returns (uint256 totalSpent);
}
