// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IOracleSource} from "./IOracleSource.sol";
import {OracleGuard} from "./OracleGuard.sol";
import {ILiquidityAdapter} from "./ILiquidityAdapter.sol";
import {IRewardVault} from "./IRewardVault.sol";
import {IBasketBuyer} from "./IBasketBuyer.sol";
import {IRebalanceWeights} from "./IRebalanceWeights.sol";

/// @notice Turns accumulated fee WETH into equal-notional shares of every active Stock Token
/// (D017). Allocation uses the RebalanceController weights with a deterministic
/// largest-remainder pass so the full principal is spent and dust converges to zero
/// (ADR 0008). The oracle rail is fail-closed: one bad price, stale feed, or closed market
/// session aborts the whole purchase. WETH is spent through a single liquidity adapter whose
/// venue must be verified before any spend path is armed (launch gate).
/// @dev minTokenOut converts WETH-in to expected token-out through BOTH oracle legs:
///      expectedToken = wethSpend × (WETH USD price) / (token USD price). Purchased tokens are
///      pulled into the RewardVault via a per-purchase exact allowance (custody and record move
///      in the same call — see RewardVault.receiveRewardAsset).
contract BasketBuyer is Ownable, ReentrancyGuard, IBasketBuyer {
    using SafeERC20 for IERC20;

    uint256 private constant TEN_THOUSAND = 10_000;

    IERC20 public immutable WETH;
    OracleGuard public immutable guard;
    IRebalanceWeights public immutable rebalance;

    ILiquidityAdapter public adapter;
    IRewardVault public rewardVault;
    uint256 public maxSlippageBps;

    error UnsetAdapter();
    error UnsetRewardVault();
    error EmptyBasket();
    error WeightMismatch();
    error ZeroBalance();
    error ZeroAddress();
    error AlreadySet();
    error SlippageCapOutOfRange();

    event AdapterSet(address indexed adapter);
    event RewardVaultSet(address indexed vault);
    event PurchaseExecuted(address indexed token, uint256 wethSpent, uint256 priceWad, uint256 amountOut, uint256 minTokenOut);

    constructor(address initialOwner, IERC20 weth, OracleGuard guard_, IRebalanceWeights rebalance_) Ownable(initialOwner) {
        WETH = weth;
        guard = guard_;
        rebalance = rebalance_;
        maxSlippageBps = 100; // 1% default
    }

    /// @dev Revokes the previous adapter's allowance before wiring the new one so a retired
    ///      venue can never spend residual WETH. Allowance to the active adapter is granted
    ///      per-purchase for the exact spend, never unlimited.
    function setAdapter(ILiquidityAdapter adapter_) external onlyOwner {
        if (address(adapter_) == address(0)) revert ZeroAddress();
        address previous = address(adapter);
        if (previous != address(0)) {
            WETH.forceApprove(previous, 0);
        }
        adapter = adapter_;
        emit AdapterSet(address(adapter_));
    }

    /// @dev Set-once latch: the custody destination cannot be redirected after wiring (D031).
    function setRewardVault(IRewardVault vault) external onlyOwner {
        if (address(vault) == address(0)) revert ZeroAddress();
        if (address(rewardVault) != address(0)) revert AlreadySet();
        rewardVault = vault;
        emit RewardVaultSet(address(vault));
    }

    function setMaxSlippageBps(uint256 bps) external onlyOwner {
        if (bps > 500) revert SlippageCapOutOfRange();
        maxSlippageBps = bps;
    }

    function purchaseBasket() external nonReentrant returns (uint256 totalSpent) {
        if (address(adapter) == address(0)) revert UnsetAdapter();
        if (address(rewardVault) == address(0)) revert UnsetRewardVault();

        uint256 amount = WETH.balanceOf(address(this));
        if (amount == 0) revert ZeroBalance();

        uint16[] memory weights = rebalance.weights();
        address[] memory tokens = rebalance.getBasket();
        uint256 n = tokens.length;
        if (n == 0) revert EmptyBasket();
        if (n != weights.length) revert WeightMismatch();

        // WETH-leg session/liveness check doubles as the fail-closed gate; its price feeds the
        // WETH->USD leg of every minTokenOut below.
        uint256 wethPrice = guard.getWethPriceWad();

        uint256[] memory spend = new uint256[](n);
        {
            // Largest-remainder allocation: floor by weight, then hand whole-WETH units to the
            // largest fractional residues, ties broken by lower index (deterministic convergence).
            uint256 distributed;
            for (uint256 i = 0; i < n; i++) {
                spend[i] = (amount * weights[i]) / TEN_THOUSAND;
                distributed += spend[i];
            }
            uint256 owed = amount - distributed;
            if (owed > 0) {
                uint256[] memory residue = new uint256[](n);
                for (uint256 i = 0; i < n; i++) {
                    residue[i] = (amount * weights[i]) % TEN_THOUSAND;
                }
                for (uint256 k = 0; k < owed; k++) {
                    uint256 best;
                    for (uint256 i = 1; i < n; i++) {
                        if (residue[i] > residue[best]) best = i;
                    }
                    spend[best]++;
                    residue[best] = 0;
                }
            }
        }

        uint256 allowedSlip = TEN_THOUSAND - maxSlippageBps;
        for (uint256 i = 0; i < n; i++) {
            uint256 price = guard.getPriceWad(tokens[i]);
            // wethSpend [wei] × wethUsd [wad] / tokenUsd [wad] => token out in token wei.
            // Multiply before dividing so the slippage floor loses no precision.
            uint256 minTokenOut = (spend[i] * wethPrice * allowedSlip) / (price * TEN_THOUSAND);

            WETH.forceApprove(address(adapter), spend[i]);
            uint256 amountOut = adapter.swapExactWethForToken(IERC20(tokens[i]), spend[i], minTokenOut, address(this));
            if (amountOut < minTokenOut) revert("BB: insufficient out");

            // Custody handoff: the vault pulls the exact purchased amount in the same call that
            // extends its lifetimeDeposits record.
            IERC20(tokens[i]).forceApprove(address(rewardVault), amountOut);
            rewardVault.receiveRewardAsset(IERC20(tokens[i]), amountOut);

            totalSpent += spend[i];
            emit PurchaseExecuted(tokens[i], spend[i], price, amountOut, minTokenOut);
        }
        // Defense-in-depth: no residual venue allowance survives the purchase.
        WETH.forceApprove(address(adapter), 0);

        require(totalSpent == amount, "BB: misallocation");
        // ADR 0008: the largest-remainder pass guarantees every whole wei above the fee is spent.
        uint256 leftover = WETH.balanceOf(address(this));
        require(leftover == 0, "BB: leftover weth");
    }
}
