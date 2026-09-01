// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {RouteAdapter} from "../src/basket/RouteAdapter.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockStockToken} from "./mocks/MockStockToken.sol";

/// @notice Venue router stub: swaps WETH pulled from the adapter into minted stock tokens at a
///         configurable rate; can also underdeliver, steal, or consume partially.
contract MockRouter {
    MockERC20 immutable weth;

    uint256 public rateWad = 1e18; // tokens per WETH
    bool public underdeliver;
    uint256 public consumeOnly; // 0 = consume full allowance

    constructor(MockERC20 weth_) {
        weth = weth_;
    }

    function setRate(uint256 r) external {
        rateWad = r;
    }

    function setUnderdeliver(bool u) external {
        underdeliver = u;
    }

    function setConsumeOnly(uint256 amount) external {
        consumeOnly = amount;
    }

    /// @dev Signature mirrors a venue "swap(bytes)" entry: adapter calls with staged calldata.
    function swap(address tokenOut, uint256 wethAmount, address recipient) external {
        uint256 pull = consumeOnly == 0 ? wethAmount : consumeOnly;
        require(weth.transferFrom(msg.sender, address(this), pull), "router: pull");
        uint256 out = (pull * rateWad) / 1e18;
        if (underdeliver) out = out / 100; // deliver 1%
        MockStockToken(tokenOut).mint(recipient, out);
    }
}

contract RouteAdapterTest is Test {
    MockERC20 weth;
    MockStockToken stock;
    MockRouter router;
    RouteAdapter adapter;

    address keeper = makeAddr("keeper");
    address buyer = makeAddr("buyer");
    address stranger = makeAddr("stranger");

    uint256 constant AMOUNT = 1 ether;

    function setUp() public {
        vm.warp(30 days);
        weth = new MockERC20("Wrapped Ether", "WETH");
        stock = new MockStockToken("USAR", "USA Rare Earth");
        router = new MockRouter(weth);

        adapter = new RouteAdapter(address(this), IERC20(address(weth)));
        adapter.setBuyer(buyer);
        adapter.setRouterAllowed(address(router), true);
        adapter.setKeeperAllowed(keeper, true);

        weth.mint(buyer, 100 ether);
        vm.prank(buyer);
        weth.approve(address(adapter), type(uint256).max);
    }

    function _stage(uint64 ttl) internal {
        bytes memory data = abi.encodeCall(MockRouter.swap, (address(stock), AMOUNT, buyer));
        vm.prank(keeper);
        adapter.stageRoute(address(stock), address(router), data, uint64(block.timestamp) + ttl);
    }

    // ------------------------------------------------------------------ happy path

    function test_ExecutesStagedRouteAndMeasuresDelta() public {
        _stage(180);
        vm.prank(buyer);
        uint256 out = adapter.swapExactWethForToken(IERC20(address(stock)), AMOUNT, 0.99 ether, buyer);
        assertEq(out, 1 ether, "balance-delta measured output");
        assertEq(stock.balanceOf(buyer), 1 ether, "tokens landed on the buyer");
        assertEq(weth.balanceOf(address(adapter)), 0, "no custody residue");
        assertEq(weth.allowance(address(adapter), address(router)), 0, "allowance revoked");
    }

    function test_RouteIsOneShot() public {
        _stage(180);
        vm.prank(buyer);
        adapter.swapExactWethForToken(IERC20(address(stock)), AMOUNT, 0, buyer);

        vm.prank(buyer);
        vm.expectRevert(RouteAdapter.NoRoute.selector);
        adapter.swapExactWethForToken(IERC20(address(stock)), AMOUNT, 0, buyer);
    }

    function test_UnconsumedWethReturnsToBuyer() public {
        router.setConsumeOnly(0.4 ether); // route only takes 40%
        bytes memory data = abi.encodeCall(MockRouter.swap, (address(stock), AMOUNT, buyer));
        vm.prank(keeper);
        adapter.stageRoute(address(stock), address(router), data, uint64(block.timestamp) + 180);

        uint256 before = weth.balanceOf(buyer);
        vm.prank(buyer);
        adapter.swapExactWethForToken(IERC20(address(stock)), AMOUNT, 0, buyer);
        // 0.6 WETH dust returned; net spend 0.4
        assertEq(before - weth.balanceOf(buyer), 0.4 ether, "unconsumed WETH returned");
    }

    // ------------------------------------------------------------------ safety rails

    function test_UnderdeliveringRouteReverts() public {
        router.setUnderdeliver(true); // delivers 1% of quoted
        _stage(180);
        vm.prank(buyer);
        vm.expectRevert(RouteAdapter.InsufficientOut.selector);
        adapter.swapExactWethForToken(IERC20(address(stock)), AMOUNT, 0.99 ether, buyer);
    }

    function test_ExpiredRouteReverts() public {
        _stage(60);
        vm.warp(block.timestamp + 61);
        vm.prank(buyer);
        vm.expectRevert(RouteAdapter.RouteExpired.selector);
        adapter.swapExactWethForToken(IERC20(address(stock)), AMOUNT, 0, buyer);
    }

    function test_MissingRouteReverts() public {
        vm.prank(buyer);
        vm.expectRevert(RouteAdapter.NoRoute.selector);
        adapter.swapExactWethForToken(IERC20(address(stock)), AMOUNT, 0, buyer);
    }

    function test_OnlyBuyerExecutes() public {
        _stage(180);
        vm.prank(stranger);
        vm.expectRevert(RouteAdapter.NotBuyer.selector);
        adapter.swapExactWethForToken(IERC20(address(stock)), AMOUNT, 0, stranger);
    }

    function test_OnlyKeeperStages() public {
        vm.prank(stranger);
        vm.expectRevert(RouteAdapter.NotKeeper.selector);
        adapter.stageRoute(address(stock), address(router), hex"", uint64(block.timestamp) + 60);
    }

    function test_UnallowedRouterCannotBeStaged() public {
        MockRouter rogue = new MockRouter(weth);
        vm.prank(keeper);
        vm.expectRevert(RouteAdapter.RouterNotAllowed.selector);
        adapter.stageRoute(address(stock), address(rogue), hex"", uint64(block.timestamp) + 60);
    }

    function test_RouterDelistedBetweenStageAndExecuteReverts() public {
        _stage(180);
        adapter.setRouterAllowed(address(router), false);
        vm.prank(buyer);
        vm.expectRevert(RouteAdapter.RouterNotAllowed.selector);
        adapter.swapExactWethForToken(IERC20(address(stock)), AMOUNT, 0, buyer);
    }

    function test_RevertingRouteBubblesAsRouteFailed() public {
        // stage calldata for a function that doesn't exist on the router
        vm.prank(keeper);
        adapter.stageRoute(address(stock), address(router), abi.encodeWithSignature("nope()"), uint64(block.timestamp) + 60);
        vm.prank(buyer);
        vm.expectRevert(RouteAdapter.RouteFailed.selector);
        adapter.swapExactWethForToken(IERC20(address(stock)), AMOUNT, 0, buyer);
    }

    function test_BuyerIsSetOnce() public {
        vm.expectRevert(RouteAdapter.AlreadySet.selector);
        adapter.setBuyer(stranger);
    }

    function test_WiringIsOwnerOnly() public {
        vm.startPrank(stranger);
        vm.expectRevert();
        adapter.setRouterAllowed(address(router), false);
        vm.expectRevert();
        adapter.setKeeperAllowed(stranger, true);
        vm.stopPrank();
    }
}
