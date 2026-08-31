// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "v4-core/test/PoolModifyLiquidityTest.sol";
import {PennyFeeHook} from "../src/hooks/PennyFeeHook.sol";
import {PennyFeeHookFactory} from "../src/hooks/PennyFeeHookFactory.sol";

contract PennyFeeHookTest is Test {
    uint160 constant SQRT_RATIO_1_1 = 79228162514264337593543950336;
    uint160 constant MIN_SQRT_LIMIT = 4295128739 + 1; // TickMath.MIN_SQRT_PRICE + 1 (out-of-bounds bound is inclusive)
    uint160 constant MAX_SQRT_LIMIT = 1461446703485210103287273052203988822378723970342 - 1; // MAX_SQRT_PRICE - 1
    uint24 constant LP_FEE = 3000;
    int24 constant TICK_SPACING = 60;
    int24 constant TICK_LOWER = -60;
    int24 constant TICK_UPPER = 60;

    PoolManager manager;
    PoolSwapTest swapRouter;
    PoolModifyLiquidityTest lpRouter;
    PennyFeeHookFactory factory;
    PennyFeeHook hook;

    MockERC20 weth;
    MockERC20 penny;
    address wethAddr;
    address pennyAddr;
    bool wethIs0;
    PoolKey key;

    address lpHolder = makeAddr("lpHolder");
    address alice = makeAddr("alice");
    address feeCollector = makeAddr("feeCollector");

    function setUp() public {
        manager = new PoolManager(address(this));
        swapRouter = new PoolSwapTest(manager);
        lpRouter = new PoolModifyLiquidityTest(manager);

        weth = new MockERC20("Wrapped Ether", "WETH");
        penny = new MockERC20("Penny", "PENNY");
        wethAddr = address(weth);
        pennyAddr = address(penny);

        factory = new PennyFeeHookFactory();
        (hook,) = factory.deployHook(manager, address(this), pennyAddr, wethAddr, LP_FEE, TICK_SPACING);
        hook.setFeeCollector(feeCollector);

        wethIs0 = wethAddr < pennyAddr;
        key = PoolKey({
            currency0: wethIs0 ? Currency.wrap(wethAddr) : Currency.wrap(pennyAddr),
            currency1: wethIs0 ? Currency.wrap(pennyAddr) : Currency.wrap(wethAddr),
            fee: LP_FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(hook))
        });

        manager.initialize(key, SQRT_RATIO_1_1);

        // Deep liquidity both sides around 1:1 so swap price impact is negligible.
        lpHolderFunds();
        vm.prank(lpHolder);
        lpRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: TICK_LOWER, tickUpper: TICK_UPPER, liquidityDelta: int128(uint128(1e32)), salt: 0
            }),
            ""
        );

        vm.prank(alice);
        weth.approve(address(swapRouter), type(uint256).max);
        vm.prank(alice);
        penny.approve(address(swapRouter), type(uint256).max);
    }

    function lpHolderFunds() internal {
        weth.mint(lpHolder, 1e40);
        penny.mint(lpHolder, 1e40);
        vm.startPrank(lpHolder);
        weth.approve(address(lpRouter), type(uint256).max);
        penny.approve(address(lpRouter), type(uint256).max);
        vm.stopPrank();
    }

    function wethInputAmount(BalanceDelta d) internal view returns (int128) {
        return wethIs0 ? d.amount0() : d.amount1();
    }

    function pennyInputAmount(BalanceDelta d) internal view returns (int128) {
        return wethIs0 ? d.amount1() : d.amount0();
    }

    function exactInSwap(bool zeroForOne, int256 amount) internal returns (BalanceDelta) {
        uint160 limit = zeroForOne ? MIN_SQRT_LIMIT : MAX_SQRT_LIMIT;
        vm.prank(alice);
        return swapRouter.swap(
            key,
            IPoolManager.SwapParams({zeroForOne: zeroForOne, amountSpecified: amount, sqrtPriceLimitX96: limit}),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );
    }

    function test_BuyExactInputChargesFullInputAndFee() public {
        uint256 input = 100_000e18;
        uint256 expectedFee = (input * 300) / 10_000; // exactly 3_000e18

        vm.prank(alice);
        weth.mint(alice, input);

        BalanceDelta delta = exactInSwap(wethIs0, -int256(input));

        // Trader settles the FULL WETH input (3% goes to the hook, 97% reaches the LP leg).
        assertEq(uint256(uint128(-wethInputAmount(delta))), input, "trader pays full WETH input");
        // PENNY output corresponds to the 97% LP leg (impact neglible, bounded ±1%).
        uint256 pennyOut = uint256(uint128(pennyInputAmount(delta)));
        assertGt(pennyOut, input * 960 / 1000, "PENNY out >= ~97% of input");
        assertLt(pennyOut, input * 990 / 1000, "PENNY out <= ~99% of input");

        // Fee is taken directly to FeeCollector, exactly 3% of the input (divisible amount).
        assertEq(weth.balanceOf(feeCollector), expectedFee, "WETH landed on feeCollector");
        assertEq(hook.totalFees(), expectedFee, "hook fee ledger matches");
    }

    function test_SellExactInputDeductsFeeFromWethOut() public {
        uint256 amountIn = 100_000e18;

        vm.prank(alice);
        penny.mint(alice, amountIn);

        BalanceDelta delta = exactInSwap(!wethIs0, -int256(amountIn));

        // Trader gives up the full PENNY input.
        assertEq(uint256(uint128(-pennyInputAmount(delta))), amountIn, "trader pays full PENNY input");

        uint256 wethOut = uint256(uint128(wethInputAmount(delta)));
        // Around 97% of the gross WETH output after the 3% hook fee (impact negligible, ±1%).
        assertGt(wethOut, amountIn * 960 / 1000, "WETH out >= ~97%");
        assertLt(wethOut, amountIn * 985 / 1000, "WETH out <= ~98.5%");

        uint256 fees = weth.balanceOf(feeCollector);
        assertGt(fees, amountIn * 29 / 1000, "sell fee >= ~2.9% of notional");
        assertLt(fees, amountIn * 31 / 1000, "sell fee <= ~3.1% of notional");
    }

    function test_ExactOutputSwapsRevert() public {
        vm.prank(alice);
        weth.mint(alice, 1e24);
        vm.expectRevert();
        exactInSwap(wethIs0, 1_000e18);
    }

    function test_TinyBuyFeeRoundsToZero() public {
        uint256 input = 33; // floor(33 * 300 / 10_000) == 0, fee < 1 wei
        vm.prank(alice);
        weth.mint(alice, input);

        BalanceDelta delta = exactInSwap(wethIs0, -int256(input));
        assertEq(uint256(uint128(-wethInputAmount(delta))), input, "trader still pays full tiny input");
        assertEq(weth.balanceOf(feeCollector), 0, "no fee below the rounding floor");
        assertEq(hook.totalFees(), 0, "bookkeeping clean");
    }

    function test_SetFeeCollectorOnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        hook.setFeeCollector(address(0xBEEF));
        assertEq(hook.feeCollector(), feeCollector, "unchanged");
    }

    function test_SetFeeCollectorIsSetOnce() public {
        // Already wired in setUp: even the owner can never redirect the fee stream (D031).
        vm.expectRevert(PennyFeeHook.AlreadySet.selector);
        hook.setFeeCollector(address(0xBEEF));
        assertEq(hook.feeCollector(), feeCollector, "unchanged");
    }

    function test_PartialFillBuyReverts() public {
        // A price-limited buy that cannot consume the full 97% LP leg must revert rather than
        // charge 3% of the specified input on a smaller fill (ADR 0003 v1 semantics).
        uint256 input = 1e30; // vastly larger than pool depth within one tick spacing
        vm.prank(alice);
        weth.mint(alice, input);

        uint160 limit = wethIs0 ? MIN_SQRT_LIMIT : MAX_SQRT_LIMIT;
        vm.prank(alice);
        vm.expectRevert(); // PartialFillUnsupported wrapped by the router/manager
        swapRouter.swap(
            key,
            IPoolManager.SwapParams({zeroForOne: wethIs0, amountSpecified: -int256(input), sqrtPriceLimitX96: limit}),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );
        assertEq(weth.balanceOf(feeCollector), 0, "no fee on a rejected partial fill");
    }

    function test_ExactInputSellCapturesFeeAndCollectorOwnedWeth() public {
        uint256 amountIn = 40_000e18;
        vm.prank(alice);
        penny.mint(alice, amountIn * 2);

        // First sale spikes the price slightly; run two so directional skew does not hide errors.
        exactInSwap(!wethIs0, -int256(amountIn));
        uint256 afterFirst = weth.balanceOf(feeCollector);
        assertGt(afterFirst, amountIn * 29 / 1000, "first sale fees ~3%");

        exactInSwap(!wethIs0, -int256(amountIn));
        uint256 afterSecond = weth.balanceOf(feeCollector);
        assertGt(afterSecond, afterFirst, "second sale adds fees");
        assertEq(hook.totalFees(), afterSecond, "ledger matches collector balance");
    }
}
