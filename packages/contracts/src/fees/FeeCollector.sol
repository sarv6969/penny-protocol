// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IBasketBuyer} from "../basket/IBasketBuyer.sol";

/// @notice Custodial WETH tank with hook-only ingress. The PennyFeeHook streams the 3% fee here
/// directly (via PoolManager.take to this address). No deposit path for third parties exists.
/// `sweep` moves the entire balance to the BasketBuyer above a threshold and triggers the basket
/// purchase. Pausing only halts sweeps (D014); it never traps user assets.
/// @dev `setBasketBuyer` is a set-once latch (D031): once wired, the owner can never redirect
/// the fee stream to a different spender.
contract FeeCollector is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable WETH;
    IBasketBuyer public basketBuyer;
    uint256 public minSweepAmount;
    bool public sweepsPaused;

    error SweepsPaused();
    error NoBasketBuyer();
    error BelowSweepThreshold();
    error AlreadySet();
    error ZeroAddress();

    event BasketBuyerSet(address indexed buyer);
    event SweptToBasket(uint256 amount, uint256 basketSpend);

    constructor(address initialOwner, IERC20 weth) Ownable(initialOwner) {
        WETH = weth;
    }

    function setBasketBuyer(IBasketBuyer buyer) external onlyOwner {
        if (address(buyer) == address(0)) revert ZeroAddress();
        if (address(basketBuyer) != address(0)) revert AlreadySet();
        basketBuyer = buyer;
        emit BasketBuyerSet(address(buyer));
    }

    function setMinSweepAmount(uint256 amount) external onlyOwner {
        minSweepAmount = amount;
    }

    function setSweepsPaused(bool paused) external onlyOwner {
        sweepsPaused = paused;
    }

    function sweep() external nonReentrant returns (uint256 basketSpend) {
        if (sweepsPaused) revert SweepsPaused();
        address buyer = address(basketBuyer);
        if (buyer == address(0)) revert NoBasketBuyer();

        uint256 balance = WETH.balanceOf(address(this));
        if (balance < minSweepAmount) revert BelowSweepThreshold();

        WETH.safeTransfer(buyer, balance);
        basketSpend = basketBuyer.purchaseBasket();
        emit SweptToBasket(balance, basketSpend);
    }
}
