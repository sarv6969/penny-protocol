// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PennyToken} from "../src/token/PennyToken.sol";
import {PennyAllocator} from "../src/token/PennyAllocator.sol";
import {TeamVesting} from "../src/token/TeamVesting.sol";

contract PennyAllocationTest is Test {
    uint256 internal constant TOTAL_SUPPLY = 1_000_000_000e18;
    uint256 internal constant LAUNCH_AMOUNT = TOTAL_SUPPLY * 90 / 100;
    uint256 internal constant TEAM_AMOUNT = TOTAL_SUPPLY * 5 / 100;
    uint256 internal constant GROWTH_AMOUNT = TOTAL_SUPPLY * 5 / 100;

    PennyToken internal token;
    address internal deployer = makeAddr("deployer");
    address internal liquid = makeAddr("launch-liquidity");
    address internal growthSafe = makeAddr("growth-ops-safe");

    function setUp() public {
        vm.prank(deployer);
        token = new PennyToken(TOTAL_SUPPLY, deployer);
    }

    function _teamVesting() internal returns (TeamVesting v) {
        v = new TeamVesting(makeAddr("team-b"), uint64(block.timestamp), 365 days);
    }

    function test_Exact901005Allocation() public {
        TeamVesting vesting = _teamVesting();

        vm.startPrank(deployer);
        PennyAllocator allocator =
            new PennyAllocator(address(token), liquid, address(vesting), growthSafe, LAUNCH_AMOUNT, TEAM_AMOUNT, GROWTH_AMOUNT);
        token.transfer(address(allocator), token.balanceOf(deployer));
        vm.stopPrank();

        assertEq(token.balanceOf(address(allocator)), TOTAL_SUPPLY, "allocator holds full supply pre-allocate");

        allocator.allocate();

        assertEq(token.balanceOf(liquid), LAUNCH_AMOUNT, "90% launch");
        assertEq(token.balanceOf(address(vesting)), TEAM_AMOUNT, "5% team vesting");
        assertEq(token.balanceOf(growthSafe), GROWTH_AMOUNT, "5% growth/ops safe");
        assertEq(token.balanceOf(address(allocator)), 0, "allocator drained");
        assertEq(token.totalSupply(), TOTAL_SUPPLY, "supply conserved");

        vm.expectRevert("ALLOC: already allocated");
        allocator.allocate();
    }

    function test_AllocationRevertsOnBalanceMismatch() public {
        TeamVesting vesting = _teamVesting();

        vm.startPrank(deployer);
        PennyAllocator allocator =
            new PennyAllocator(address(token), liquid, address(vesting), growthSafe, LAUNCH_AMOUNT, TEAM_AMOUNT, GROWTH_AMOUNT);
        token.transfer(address(allocator), LAUNCH_AMOUNT + TEAM_AMOUNT); // underfunded -> 90%+5% only
        vm.stopPrank();

        assertEq(token.balanceOf(address(allocator)), LAUNCH_AMOUNT + TEAM_AMOUNT, "underfunded allocator");

        vm.expectRevert("ALLOC: balance mismatch");
        allocator.allocate();
    }

    function test_ConstructorRejectsZeroTargets() public {
        TeamVesting vesting = _teamVesting();

        vm.expectRevert("ALLOC: zero safe target");
        new PennyAllocator(address(token), liquid, address(vesting), address(0), LAUNCH_AMOUNT, TEAM_AMOUNT, GROWTH_AMOUNT);

        vm.expectRevert("ALLOC: zero vesting target");
        new PennyAllocator(address(token), liquid, address(0), growthSafe, LAUNCH_AMOUNT, TEAM_AMOUNT, GROWTH_AMOUNT);

        vm.expectRevert("ALLOC: zero launch target");
        new PennyAllocator(address(token), address(0), address(vesting), growthSafe, LAUNCH_AMOUNT, TEAM_AMOUNT, GROWTH_AMOUNT);
    }

    function test_ConstructorRejectsOverflow() public {
        TeamVesting vesting = _teamVesting();

        vm.expectRevert("ALLOC: overflow");
        new PennyAllocator(address(token), liquid, address(vesting), growthSafe, type(uint256).max, type(uint256).max, type(uint256).max);
    }

    function test_TeamVestingReleasesLinearlyOverOneYear() public {
        uint64 start = uint64(block.timestamp);
        TeamVesting vesting = new TeamVesting(makeAddr("team-b"), start, 365 days);

        vm.prank(deployer);
        token.transfer(address(vesting), TEAM_AMOUNT);

        vm.warp(start + 182 days + 12 hours);
        assertApproxEqAbs(vesting.releasable(address(token)), TEAM_AMOUNT / 2, 2, "half vested at 6 months");

        vm.warp(start + 365 days);
        assertEq(vesting.releasable(address(token)), TEAM_AMOUNT, "fully vested after 1 year");

        vm.prank(makeAddr("team-b"));
        vesting.release(address(token));
        assertEq(token.balanceOf(makeAddr("team-b")), TEAM_AMOUNT, "beneficiary received all");
        assertEq(token.balanceOf(address(vesting)), 0, "vesting drained");
    }
}
