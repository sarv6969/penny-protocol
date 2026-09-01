// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ChainlinkOracle, IAggregatorV3} from "../src/basket/ChainlinkOracle.sol";
import {MockAggregatorV3} from "./mocks/MockAggregatorV3.sol";
import {MockStockToken} from "./mocks/MockStockToken.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/// @notice D036 production oracle tests: 8→18 decimal normalization (Robinhood feeds are
///         8-dec), fail-closed staleness/round/pause behavior, and owner gating.
contract ChainlinkOracleTest is Test {
    ChainlinkOracle oracle;
    MockAggregatorV3 stockFeed; // 8 decimals like real Robinhood equity feeds
    MockAggregatorV3 ethFeed; // 8 decimals like real ETH/USD
    MockStockToken stock;
    MockERC20 weth;

    uint48 constant STOCK_BOUND = 4 days; // spans weekends (24/5 feeds)
    uint48 constant ETH_BOUND = 1 days + 2 hours;

    function setUp() public {
        vm.warp(30 days); // realistic non-zero clock
        oracle = new ChainlinkOracle(address(this));
        stock = new MockStockToken("USAR", "USA Rare Earth");
        weth = new MockERC20("Wrapped Ether", "WETH");
        stockFeed = new MockAggregatorV3(8, 17_87500000); // $17.875, 8 decimals
        ethFeed = new MockAggregatorV3(8, 2473_43520000); // $2473.4352

        oracle.setFeed(address(stock), IAggregatorV3(address(stockFeed)), STOCK_BOUND, true);
        oracle.setFeed(address(weth), IAggregatorV3(address(ethFeed)), ETH_BOUND, false);
    }

    // ------------------------------------------------------------------ pricing

    function test_NormalizesEightDecimalsToWad() public view {
        assertEq(oracle.priceOf(address(stock)), 17.875e18, "8-dec answer scaled to wad");
        assertEq(oracle.priceOf(address(weth)), 2473.4352e18, "ETH feed scaled to wad");
    }

    function test_UnknownTokenPricesZeroAndNotLive() public {
        MockERC20 stranger = new MockERC20("X", "X");
        assertEq(oracle.priceOf(address(stranger)), 0);
        assertFalse(oracle.isLive(address(stranger)));
    }

    function test_NonPositiveAnswerNotLive() public {
        stockFeed.set(0, block.timestamp);
        assertFalse(oracle.isLive(address(stock)));
        assertEq(oracle.priceOf(address(stock)), 0);

        stockFeed.set(-1, block.timestamp);
        assertFalse(oracle.isLive(address(stock)));
    }

    // ------------------------------------------------------------------ liveness

    function test_LiveWithinBound() public view {
        assertTrue(oracle.isLive(address(stock)));
        assertTrue(oracle.isLive(address(weth)));
    }

    function test_StaleBeyondBoundNotLive() public {
        // fresh at t0; warp past the stock bound (weekend hold is fine, beyond it is not)
        vm.warp(block.timestamp + STOCK_BOUND + 1);
        assertFalse(oracle.isLive(address(stock)), "stock feed stale");
        // ETH bound is tighter — already stale too
        assertFalse(oracle.isLive(address(weth)));
    }

    function test_WeekendHoldWithinBoundStillLive() public {
        vm.warp(block.timestamp + 2 days + 12 hours); // long weekend, inside 4d bound
        assertTrue(oracle.isLive(address(stock)));
    }

    function test_UnfinishedRoundNotLive() public {
        stockFeed.setStaleRound();
        assertFalse(oracle.isLive(address(stock)));
    }

    function test_FeedRevertNotLive() public {
        stockFeed.setRevert(true);
        assertFalse(oracle.isLive(address(stock)));
    }

    function test_OraclePausedNotLive() public {
        stock.setOraclePaused(true);
        assertFalse(oracle.isLive(address(stock)), "corporate action pause must fail closed");
        stock.setOraclePaused(false);
        assertTrue(oracle.isLive(address(stock)));
    }

    function test_PauseCheckSkippedForNonStockTokens() public view {
        // WETH has no oraclePaused() — configured with checkOraclePaused=false, stays live.
        assertTrue(oracle.isLive(address(weth)));
    }

    function test_NonStockTokenWithPauseCheckFailsClosed() public {
        // If misconfigured WITH the pause check, a token lacking oraclePaused() is not live.
        oracle.setFeed(address(weth), IAggregatorV3(address(ethFeed)), ETH_BOUND, true);
        assertFalse(oracle.isLive(address(weth)));
    }

    // ------------------------------------------------------------------ admin

    function test_SetFeedOwnerOnly() public {
        vm.prank(address(0xBAD));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(0xBAD)));
        oracle.setFeed(address(stock), IAggregatorV3(address(stockFeed)), 1 days, true);
    }

    function test_SetFeedRejectsZeroes() public {
        vm.expectRevert(ChainlinkOracle.ZeroAddress.selector);
        oracle.setFeed(address(0), IAggregatorV3(address(stockFeed)), 1 days, true);
        vm.expectRevert(ChainlinkOracle.ZeroAddress.selector);
        oracle.setFeed(address(stock), IAggregatorV3(address(0)), 1 days, true);
        vm.expectRevert(ChainlinkOracle.BadBound.selector);
        oracle.setFeed(address(stock), IAggregatorV3(address(stockFeed)), 0, true);
    }
}
