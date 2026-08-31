// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Execution venue for a single exact-in WETH->token purchase.
/// Implementations must be verified against a live venue before use (launch gate).
interface ILiquidityAdapter {
    /// @return amountOut tokens delivered to `recipient` (>= minTokenOut or revert).
    function swapExactWethForToken(IERC20 tokenOut, uint256 wethAmount, uint256 minTokenOut, address recipient)
        external
        returns (uint256 amountOut);
}
