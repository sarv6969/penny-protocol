// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IBasketBuyer} from "../basket/IBasketBuyer.sol";
import {IWETH9} from "../interfaces/IWETH9.sol";

/// @notice Public fee tank for the pons-launched model (D039).
///
/// The token itself is launched on pons v2, which charges the creator tax and credits it to the
/// creator's payout wallet. The operator forwards those proceeds here — this contract is the
/// published deposit address. Anyone may also donate; every deposit is a public onchain event.
///
/// TRUST BOUNDARY (be honest about it): with the pons model there is no hook physically routing
/// fees here, so "100% of fees buy stocks" is an operator commitment for the leg BEFORE the
/// deposit. Everything AFTER the deposit is trustless: funds can only ever move to the set-once
/// BasketBuyer, which can only buy governance-approved Stock Tokens at oracle-checked prices and
/// deliver them to the RewardVault. Nobody — including the owner — can withdraw from here.
///
/// `sweep` moves the entire WETH balance to the BasketBuyer above a threshold and triggers the
/// purchase. Pausing only halts sweeps (D014); it never traps user assets.
/// @dev `setBasketBuyer` is a set-once latch (D031).
contract FeeCollector is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IWETH9 public immutable WETH;
    IBasketBuyer public basketBuyer;
    uint256 public minSweepAmount;
    bool public sweepsPaused;

    /// @notice Cumulative native ETH ever wrapped by this contract (transparency counter).
    uint256 public lifetimeEthReceived;

    error SweepsPaused();
    error NoBasketBuyer();
    error BelowSweepThreshold();
    error AlreadySet();
    error ZeroAddress();
    error NothingToWrap();

    event BasketBuyerSet(address indexed buyer);
    event FeesDeposited(address indexed from, uint256 amount, bool wrapped);
    event SweptToBasket(uint256 amount, uint256 basketSpend);

    constructor(address initialOwner, IWETH9 weth) Ownable(initialOwner) {
        WETH = weth;
    }

    /// @notice Accept native ETH fee forwards and wrap immediately so the rail only ever sees
    ///         WETH. This is the address the operator sends pons creator-tax proceeds to.
    receive() external payable {
        _wrap(msg.value);
    }

    /// @notice Explicit deposit entrypoint (same as sending ETH, clearer in wallets/explorers).
    function depositFees() external payable {
        _wrap(msg.value);
    }

    /// @notice Wrap any stray native ETH that arrived via selfdestruct/coinbase (no receive hook).
    function wrapDust() external {
        uint256 bal = address(this).balance;
        if (bal == 0) revert NothingToWrap();
        _wrap(bal);
    }

    function _wrap(uint256 amount) internal {
        if (amount == 0) revert NothingToWrap();
        lifetimeEthReceived += amount;
        WETH.deposit{value: amount}();
        emit FeesDeposited(msg.sender, amount, true);
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

        uint256 balance = IERC20(address(WETH)).balanceOf(address(this));
        if (balance < minSweepAmount) revert BelowSweepThreshold();

        IERC20(address(WETH)).safeTransfer(buyer, balance);
        basketSpend = basketBuyer.purchaseBasket();
        emit SweptToBasket(balance, basketSpend);
    }
}
