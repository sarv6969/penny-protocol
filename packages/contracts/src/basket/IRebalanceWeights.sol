// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

/// @notice Minimal read surface of RebalanceController required by BasketBuyer.
interface IRebalanceWeights {
    function activeCount() external view returns (uint256);

    function getBasket() external view returns (address[] memory);

    function weights() external view returns (uint16[] memory);
}
