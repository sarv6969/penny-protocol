// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {SafeCast} from "v4-core/libraries/SafeCast.sol";
import {BaseHooks} from "./BaseHooks.sol";

/// @title PennyFeeHook — Uniswap v4 hook that charges the immutable 300 bps WETH protocol fee
/// @notice Fee charged in WETH on exact-input swaps only, in both trade directions:
///   Buy  (WETH in):  beforeSwap shrinks the pool's swap amount by 3% of the WETH input and the
///                     afterSwap callback takes that 3% straight to `feeCollector`.
///   Sell (WETH out): afterSwap takes 3% of the realized WETH output to `feeCollector`.
///   The trader's settlement covers the full amount; the hook nets its pool-manager delta to zero
///   on every swap, so no accumulation or collection step is needed.
contract PennyFeeHook is BaseHooks, Ownable {
    using Hooks for IHooks;
    using SafeCast for uint256;

    uint16 public constant FEE_BPS = 300; // 3.00%, immutable by construction

    address public immutable PENNY;
    address public immutable WETH;
    uint24 public immutable STATIC_FEE;
    int24 public immutable TICK_SPACING;
    IPoolManager public immutable MANAGER;

    address public feeCollector;
    uint256 public totalFees;

    error OnlyPoolManager();
    error NotWhitelistedPool();
    error ExactInputOnly();
    error InvalidCurrencies();
    error AlreadySet();
    error ZeroAddress();
    error PartialFillUnsupported();

    event FeesToCollector(address indexed feeTarget, uint256 amount);

    modifier onlyPoolManager() {
        if (msg.sender != address(MANAGER)) revert OnlyPoolManager();
        _;
    }

    constructor(IPoolManager manager, address initialOwner, address penny, address weth, uint24 fee, int24 tickSpacing)
        Ownable(initialOwner)
    {
        if (penny == address(0) || weth == address(0) || penny == weth) revert InvalidCurrencies();
        MANAGER = manager;
        PENNY = penny;
        WETH = weth;
        STATIC_FEE = fee;
        TICK_SPACING = tickSpacing;

        Hooks.Permissions memory permissions;
        permissions.beforeSwap = true;
        permissions.afterSwap = true;
        permissions.beforeSwapReturnDelta = true;
        permissions.afterSwapReturnDelta = true;
        Hooks.validateHookPermissions(IHooks(address(this)), permissions);
    }

    /// @dev Set-once latch (D031): after the collector is wired the owner can never redirect
    ///      the 3% WETH fee stream to another address.
    function setFeeCollector(address collector) external onlyOwner {
        if (collector == address(0)) revert ZeroAddress();
        if (feeCollector != address(0)) revert AlreadySet();
        feeCollector = collector;
    }

    function beforeSwap(
        address, /* sender **/
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata /* hookData **/
    )
        external
        override
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        _onlyWhitelisted(key);
        if (params.amountSpecified >= 0) revert ExactInputOnly();

        // Sell direction: the fee is 3% of the realized WETH output, sized in afterSwap.
        if (!_wethIsInput(key, params)) {
            return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }

        // Buy direction: route only 97% of the WETH input through the LP leg. The trader still
        // settles the full input; the 3% cut is taken for the collector in afterSwap.
        uint256 fee = _feeOnInput(params);
        return (IHooks.beforeSwap.selector, toBeforeSwapDelta(fee.toInt128(), 0), 0);
    }

    function afterSwap(
        address, /* sender **/
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata /* hookData **/
    )
        external
        override
        onlyPoolManager
        returns (bytes4, int128)
    {
        _onlyWhitelisted(key);

        if (_wethIsInput(key, params)) {
            uint256 buyFee = _feeOnInput(params);
            // Partial fills (price-limited swaps) would make the 3%-of-specified fee exceed
            // 300 bps of the actually-swapped notional. v1 rejects them: the LP leg must have
            // consumed exactly the 97% remainder (ADR 0003).
            uint256 lpLeg = uint256(-params.amountSpecified) - buyFee;
            int128 wethConsumed = _wethSide(key, delta);
            if (uint256(uint128(-wethConsumed)) != lpLeg) revert PartialFillUnsupported();
            // Buy: take the 3% WETH input fee for the collector; the beforeSwap delta nets this.
            _sendFee(buyFee);
            return (IHooks.afterSwap.selector, 0);
        }

        int128 wethOut = _wethSide(key, delta);
        if (wethOut <= 0) return (IHooks.afterSwap.selector, 0);

        // Sell: take 3% of the WETH output and return it as the hook's unspecified delta so the
        // pool manager nets this hook's delta and reduces the trader's take by exactly the fee.
        uint256 sellFee = (uint256(uint128(wethOut)) * FEE_BPS) / 10_000;
        _sendFee(sellFee);
        return (IHooks.afterSwap.selector, sellFee.toInt128());
    }

    function _feeOnInput(IPoolManager.SwapParams calldata params) internal pure returns (uint256) {
        uint256 input = uint256(-params.amountSpecified);
        return (input * FEE_BPS) / 10_000;
    }

    function _sendFee(uint256 fee) internal {
        if (fee == 0) return;
        MANAGER.take(Currency.wrap(WETH), feeCollector, fee);
        totalFees += fee;
        emit FeesToCollector(feeCollector, fee);
    }

    function _onlyWhitelisted(PoolKey calldata key) internal view {
        if (address(key.hooks) != address(this)) revert NotWhitelistedPool();
        if (key.fee != STATIC_FEE || key.tickSpacing != TICK_SPACING) revert NotWhitelistedPool();

        (address lo, address hi) = PENNY < WETH ? (PENNY, WETH) : (WETH, PENNY);
        if (Currency.unwrap(key.currency0) != lo || Currency.unwrap(key.currency1) != hi) {
            revert NotWhitelistedPool();
        }
    }

    function _wethIsInput(PoolKey calldata key, IPoolManager.SwapParams calldata params) internal view returns (bool) {
        bool wethIs0 = Currency.unwrap(key.currency0) == WETH;
        return wethIs0 ? params.zeroForOne : !params.zeroForOne;
    }

    function _wethSide(PoolKey calldata key, BalanceDelta delta) internal view returns (int128) {
        bool wethIs0 = Currency.unwrap(key.currency0) == WETH;
        return wethIs0 ? delta.amount0() : delta.amount1();
    }
}
