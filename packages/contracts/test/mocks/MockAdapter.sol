// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILiquidityAdapter} from "../../src/basket/ILiquidityAdapter.sol";
import {MockERC20} from "./MockERC20.sol";
import {MockStockToken} from "./MockStockToken.sol";

/// @notice Test-only venue: pulls `wethAmount` WETH from the caller, mints 1 whole token
///         per WETH at a 1 USD price to the recipient. Reverts if minTokenOut is not met
///         (mirrors venue slippage guarantees).
contract MockAdapter is ILiquidityAdapter {
    MockERC20 public immutable weth;

    error SlippageExceeded();

    constructor(MockERC20 weth_) {
        weth = weth_;
    }

    function swapExactWethForToken(IERC20 tokenOut, uint256 wethAmount, uint256 minTokenOut, address recipient)
        external
        returns (uint256 amountOut)
    {
        if (wethAmount < minTokenOut) revert SlippageExceeded();
        require(weth.transferFrom(msg.sender, address(this), wethAmount), "MA: pull failed");
        MockStockToken(address(tokenOut)).mint(recipient, wethAmount);
        return wethAmount;
    }
}
