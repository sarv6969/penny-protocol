// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

/// @notice Price/liveness source for the basket rail.
interface IOracleSource {
    /// @notice USD price per whole token, 18 decimal fixed point (uiMultiplier already baked in, D008).
    function priceOf(address token) external view returns (uint256 priceWad);

    /// @notice Fail-closed liveness; false for unknown or stale feeds.
    function isLive(address token) external view returns (bool);
}
