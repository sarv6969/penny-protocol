// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "v4-core/test/PoolModifyLiquidityTest.sol";
import {PennyFeeHook} from "../../src/hooks/PennyFeeHook.sol";
import {PennyFeeHookFactory} from "../../src/hooks/PennyFeeHookFactory.sol";

/// @notice Bounded random-walk keeper for PennyFeeHook (Phase 11).
/// @dev The walker alternates WETH exact-in buys and PENNY exact-in sells against the real
///      v4 PoolManager. Fee observations are taken from the feeCollector WETH balance delta of
///      each swap and mirrored into ghosts; the invariant suite compares that against the
///      hook's own ledger and the exact 300-bps formula.
contract PennyFeeHookHandler is Test {
    uint160 internal constant MIN_SQRT_LIMIT = 4295128739 + 1;
    uint160 internal constant MAX_SQRT_LIMIT = 1461446703485210103287273052203988822378723970342 - 1;
    uint256 internal constant MAX_SWAP = 1e24;

    PoolSwapTest internal swapRouter;
    PennyFeeHook internal hook;
    MockERC20 internal weth;
    MockERC20 internal penny;
    address internal feeCollector;
    address internal alice;
    bool internal wethIs0;

    PoolKey internal key;

    uint256 public ghostFees;
    uint256 public ghostBuyFees;
    uint256 public ghostBuyExpected;
    uint256 public ghostSellFees;
    uint256 public ghostSellGross;
    uint256 public ghostSellCount;

    constructor(
        PoolSwapTest swapRouter_,
        PennyFeeHook hook_,
        MockERC20 weth_,
        MockERC20 penny_,
        address feeCollector_,
        address alice_,
        PoolKey memory key_
    ) {
        swapRouter = swapRouter_;
        hook = hook_;
        weth = weth_;
        penny = penny_;
        feeCollector = feeCollector_;
        alice = alice_;
        key = key_;
        wethIs0 = Currency.unwrap(key.currency0) == address(weth_);
    }

    /// @notice WETH exact-in buy: the fee is exactly floor(input * FEE_BPS / 10000).
    function swapBuy(uint256 seed) external {
        uint256 input = (seed % (MAX_SWAP - 1e18)) + 1e18;
        weth.mint(alice, input);

        uint256 before = weth.balanceOf(feeCollector);
        vm.prank(alice);
        swapRouter.swap(
            key,
            IPoolManager.SwapParams({
                zeroForOne: wethIs0, amountSpecified: -int256(input), sqrtPriceLimitX96: wethIs0 ? MIN_SQRT_LIMIT : MAX_SQRT_LIMIT
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );
        uint256 observed = weth.balanceOf(feeCollector) - before;

        ghostFees += observed;
        ghostBuyFees += observed;
        ghostBuyExpected += (input * 300) / 10_000;
    }

    /// @notice PENNY exact-in sell: the fee is 3% of the realized WETH output, deducted from the
    ///          trader's take; the walker mirrors gross (trader net + fee) for the aggregate check.
    function swapSell(uint256 seed) external {
        uint256 amountIn = (seed % (MAX_SWAP - 1e18)) + 1e18;
        penny.mint(alice, amountIn);

        uint256 before = weth.balanceOf(feeCollector);
        vm.prank(alice);
        BalanceDelta delta = swapRouter.swap(
            key,
            IPoolManager.SwapParams({
                zeroForOne: !wethIs0, amountSpecified: -int256(amountIn), sqrtPriceLimitX96: !wethIs0 ? MIN_SQRT_LIMIT : MAX_SQRT_LIMIT
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );
        uint256 observed = weth.balanceOf(feeCollector) - before;
        uint256 netWethOut = uint256(uint128(wethIs0 ? delta.amount0() : delta.amount1()));

        ghostFees += observed;
        ghostSellFees += observed;
        ghostSellGross += netWethOut + observed;
        ghostSellCount++;
    }
}

/// @notice Invariant suite for PennyFeeHook: 300-bps WETH fee bookkeeping over a bounded walk.
contract InvariantPennyFeeHookTest is Test {
    uint160 constant SQRT_RATIO_1_1 = 79228162514264337593543950336;
    uint24 constant LP_FEE = 3000;
    int24 constant TICK_SPACING = 60;
    int24 constant TICK_LOWER = -60;
    int24 constant TICK_UPPER = 60;

    PoolManager internal manager;
    PoolSwapTest internal swapRouter;
    PoolModifyLiquidityTest internal lpRouter;
    PennyFeeHookFactory internal factory;
    PennyFeeHook internal hook;

    MockERC20 internal weth;
    MockERC20 internal penny;
    PoolKey internal key;
    bool internal wethIs0;

    address internal lpHolder = makeAddr("lpHolder");
    address internal alice = makeAddr("alice");
    address internal feeCollector = makeAddr("feeCollector");

    PennyFeeHookHandler internal handler;

    function setUp() public {
        manager = new PoolManager(address(this));
        swapRouter = new PoolSwapTest(manager);
        lpRouter = new PoolModifyLiquidityTest(manager);

        weth = new MockERC20("Wrapped Ether", "WETH");
        penny = new MockERC20("Penny", "PENNY");

        factory = new PennyFeeHookFactory();
        (hook,) = factory.deployHook(manager, address(this), address(penny), address(weth), LP_FEE, TICK_SPACING);
        hook.setFeeCollector(feeCollector);

        wethIs0 = address(weth) < address(penny);
        key = PoolKey({
            currency0: wethIs0 ? Currency.wrap(address(weth)) : Currency.wrap(address(penny)),
            currency1: wethIs0 ? Currency.wrap(address(penny)) : Currency.wrap(address(weth)),
            fee: LP_FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(hook))
        });

        manager.initialize(key, SQRT_RATIO_1_1);

        // Deep liquidity both sides around 1:1 so per-swap price impact stays negligible.
        weth.mint(lpHolder, 1e40);
        penny.mint(lpHolder, 1e40);
        vm.startPrank(lpHolder);
        weth.approve(address(lpRouter), type(uint256).max);
        penny.approve(address(lpRouter), type(uint256).max);
        lpRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: TICK_LOWER, tickUpper: TICK_UPPER, liquidityDelta: int128(uint128(1e32)), salt: 0
            }),
            ""
        );
        vm.stopPrank();

        vm.startPrank(alice);
        weth.approve(address(swapRouter), type(uint256).max);
        penny.approve(address(swapRouter), type(uint256).max);
        vm.stopPrank();

        handler = new PennyFeeHookHandler(swapRouter, hook, weth, penny, feeCollector, alice, key);
        targetContract(address(handler));
    }

    /// @dev The hook's own accounting (totalFees), the collector's WETH balance and the handler's
    ///      aggregated fee ghost must all move in lockstep.
    function invariant_hook_ledger_eq_collector_eq_ghost() external view {
        assertEq(hook.totalFees(), weth.balanceOf(feeCollector), "hook ledger vs collector balance");
        assertEq(hook.totalFees(), handler.ghostFees(), "hook ledger vs walker ghost");
    }

    /// @dev Every WETH exact-in buy pays exactly floor(input * 300 / 10000) to the collector.
    function invariant_buy_fee_is_exactly_300bps() external view {
        assertEq(handler.ghostBuyFees(), handler.ghostBuyExpected(), "buy fee deviated from 300 bps of input");
    }

    /// @dev No WETH can exit the pool without the fee: over the walk, every sell's WETH output
    ///      (trader net + collector fee) carried 300 bps to the collector, modulo the per-swap
    ///      wei rounding floor (each swap is within one basis-point-of-wei of the 300-bps mark).
    function invariant_sell_fee_covers_300bps_of_gross_exit() external view {
        uint256 fees = handler.ghostSellFees() * 10_000;
        uint256 gross = handler.ghostSellGross() * 300;
        assertLe(fees, gross, "sell fee exceeded 300 bps of gross WETH exit");
        assertGe(fees, gross - handler.ghostSellCount() * 10_000, "sell fee under 300 bps of gross WETH exit");
    }

    /// @dev The fee is WETH-only: the collector never holds the quote token.
    function invariant_fee_is_weth_only() external view {
        assertEq(penny.balanceOf(feeCollector), 0, "PENNY landed on the fee collector");
    }
}
