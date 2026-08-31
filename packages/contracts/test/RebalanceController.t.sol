// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {RebalanceController} from "../src/governance/RebalanceController.sol";
import {StockTokenVerifier} from "../src/governance/StockTokenVerifier.sol";
import {IStockTokenVerifier} from "../src/governance/IStockTokenVerifier.sol";
import {MockStockToken} from "./mocks/MockStockToken.sol";
import {MockERC20VariableDecimals} from "./mocks/MockERC20VariableDecimals.sol";

contract RebalanceControllerTest is Test {
    RebalanceController internal controller;
    StockTokenVerifier internal verifier;
    MockStockToken internal s1;
    MockStockToken internal s2;
    MockStockToken internal s3;
    MockStockToken internal s4;
    MockStockToken internal s5;
    MockStockToken internal s6;

    address internal admin = makeAddr("admin");
    address internal rebalancer = makeAddr("rebalancer");
    address internal emergency = makeAddr("emergency");
    address internal outsider = makeAddr("outsider");

    uint256 internal constant DELAY = 7 days;

    function _founding() internal view returns (address[] memory f) {
        f = new address[](5);
        f[0] = address(s1);
        f[1] = address(s2);
        f[2] = address(s3);
        f[3] = address(s4);
        f[4] = address(s5);
    }

    function setUp() public {
        s1 = new MockStockToken("TE", "T1 Energy");
        s2 = new MockStockToken("POET", "POET Technologies");
        s3 = new MockStockToken("NNE", "NANO Nuclear Energy");
        s4 = new MockStockToken("WYFI", "WhiteFiber");
        s5 = new MockStockToken("RCAT", "Red Cat");
        s6 = new MockStockToken("SIX", "Sixth Stock");

        vm.prank(admin);
        verifier = new StockTokenVerifier(admin);

        vm.startPrank(admin);
        controller = new RebalanceController(_founding(), verifier, DELAY);
        controller.grantRole(controller.REBALANCE_ROLE(), rebalancer);
        controller.grantRole(controller.EMERGENCY_ROLE(), emergency);
        vm.stopPrank();
    }

    function test_FoundingFiveAtLaunchWeights() public view {
        assertEq(controller.activeCount(), 5, "active count");
        uint16[] memory w = controller.weights();
        assertEq(w.length, 5, "weights length");
        uint256 total;
        for (uint256 i = 0; i < 5; i++) {
            assertEq(w[i], 2_000, "founding weight");
            total += w[i];
        }
        assertEq(total, 10_000, "total bps");
    }

    function test_AddRequiresRoleAndDelay() public {
        vm.prank(rebalancer);
        controller.proposeAddition(address(s6));

        (bool exists,,, address token,) = controller.pending();
        assertTrue(exists, "pending set");
        assertEq(token, address(s6), "pending token");

        vm.expectRevert("REBAL: delay not elapsed");
        controller.activateChange();

        vm.warp(block.timestamp + DELAY);
        controller.activateChange();

        assertEq(controller.activeCount(), 6, "six active");
        assertTrue(controller.isActive(address(s6)), "s6 active");
        assertEq(controller.admittedAt(address(s6)), block.timestamp, "admission ts");
    }

    function test_AddRejectedForNonRole() public {
        vm.prank(outsider);
        vm.expectRevert();
        controller.proposeAddition(address(s6));
    }

    function test_AddRejectsUnverifiedToken() public {
        MockERC20VariableDecimals fake = new MockERC20VariableDecimals("Fake", "FAKE", 18);
        vm.expectRevert("REBAL: unverified token");
        vm.prank(rebalancer);
        controller.proposeAddition(address(fake));
    }

    function test_AddAtCeilingRejected() public {
        for (uint256 i = 6; i <= 8; i++) {
            MockStockToken t = new MockStockToken(string(abi.encodePacked("T", i)), "extra");
            vm.prank(rebalancer);
            controller.proposeAddition(address(t));
            vm.warp(block.timestamp + DELAY);
            controller.activateChange();
        }
        MockStockToken ninth = new MockStockToken("T9", "extra");
        vm.prank(rebalancer);
        vm.expectRevert("REBAL: at ceiling");
        controller.proposeAddition(address(ninth));
    }

    function test_SecondProposalWhilePendingRejected() public {
        vm.prank(rebalancer);
        controller.proposeAddition(address(s6));
        MockStockToken seventh = new MockStockToken("T7", "extra");
        vm.prank(rebalancer);
        vm.expectRevert("REBAL: pending exists");
        controller.proposeAddition(address(seventh));
    }

    function test_RotationOutThenReAdmission() public {
        // Rotate in s6 (6 active), rotate it back out (5 active), then re-admit it (D033).
        vm.prank(rebalancer);
        controller.proposeAddition(address(s6));
        vm.warp(block.timestamp + DELAY);
        controller.activateChange();
        assertEq(controller.activeCount(), 6, "six active");

        vm.warp(block.timestamp + 1 seconds);
        vm.prank(rebalancer);
        controller.proposeRemoval(5, "quarterly rotation: thesis played out");

        vm.warp(block.timestamp + DELAY);
        controller.activateChange();
        assertEq(controller.activeCount(), 5, "back to five");
        assertFalse(controller.isActive(address(s6)), "s6 rotated out");

        // Re-admission is allowed: the stock passes the screen again and returns.
        vm.prank(rebalancer);
        controller.proposeAddition(address(s6));
        vm.warp(block.timestamp + DELAY);
        controller.activateChange();
        assertEq(controller.activeCount(), 6, "s6 re-admitted");
        assertTrue(controller.isActive(address(s6)), "s6 active again");
    }

    function test_DuplicateActiveAdditionRejected() public {
        vm.prank(rebalancer);
        vm.expectRevert("REBAL: already active");
        controller.proposeAddition(address(s1));
    }

    function test_RemovalBelowFloorRejected() public {
        // At exactly MIN_CONSTITUENTS (5), no removal may be proposed — rotation must add first.
        vm.prank(rebalancer);
        vm.expectRevert("REBAL: at floor");
        controller.proposeRemoval(0, "would breach the floor");

        vm.prank(emergency);
        vm.expectRevert("REBAL: at floor");
        controller.proposeRemoval(0, "even emergencies respect the floor");
    }

    function test_RoutineRemovalByRebalancerWithReason() public {
        // Grow to six so the floor allows one removal.
        vm.prank(rebalancer);
        controller.proposeAddition(address(s6));
        vm.warp(block.timestamp + DELAY);
        controller.activateChange();

        vm.prank(outsider);
        vm.expectRevert("REBAL: not authorized");
        controller.proposeRemoval(0, "outsiders cannot rotate");

        vm.prank(rebalancer);
        vm.expectRevert("REBAL: empty reason");
        controller.proposeRemoval(0, "");

        vm.prank(rebalancer);
        controller.proposeRemoval(0, "quarterly rotation");
        vm.warp(block.timestamp + DELAY);
        controller.activateChange();
        assertEq(controller.activeCount(), 5, "rotated back to floor");
    }

    function test_FutureWeightsRebalanceEqualDeterministically() public {
        vm.startPrank(rebalancer);
        controller.proposeAddition(address(s6));
        vm.stopPrank();
        vm.warp(block.timestamp + DELAY);
        controller.activateChange();

        uint16[] memory w = controller.weights();
        assertEq(w.length, 6, "six weights");
        uint256 total;
        uint256 expectedBase = 1_666;
        uint256 countBig = 4;
        for (uint256 i = 0; i < 6; i++) {
            total += w[i];
            if (i < countBig) assertEq(w[i], expectedBase + 1, "remainder-first");
            else assertEq(w[i], expectedBase, "base weight");
        }
        assertEq(total, 10_000, "six-weight total");
    }

    function _growToSix() internal {
        vm.prank(rebalancer);
        controller.proposeAddition(address(s6));
        vm.warp(block.timestamp + DELAY);
        controller.activateChange();
    }

    function test_EmergencyRemovalRequiresReasonAndDelay() public {
        _growToSix();

        vm.prank(emergency);
        vm.expectRevert("REBAL: empty reason");
        controller.proposeRemoval(0, "");

        vm.prank(emergency);
        controller.proposeRemoval(0, "availability emergency");

        vm.expectRevert("REBAL: delay not elapsed");
        controller.activateChange();

        vm.warp(block.timestamp + DELAY);
        controller.activateChange();

        assertEq(controller.activeCount(), 5, "five active after emergency");
        assertFalse(controller.isActive(address(s1)), "s1 inactive");
    }

    function test_RemovalBindsIndexAndToken() public {
        _growToSix();
        vm.prank(emergency);
        controller.proposeRemoval(4, "emergency delisting");
        vm.warp(block.timestamp + DELAY);
        controller.activateChange();
        assertFalse(controller.isActive(address(s5)), "s5 removed");
        assertEq(controller.activeCount(), 5, "five active");
    }

    function test_ConstructorGateways() public {
        vm.expectRevert("REBAL: need 5 founding");
        new RebalanceController(new address[](4), verifier, DELAY);

        address[] memory withDup = _founding();
        withDup[4] = withDup[1];
        vm.expectRevert("REBAL: duplicate founding");
        new RebalanceController(withDup, verifier, DELAY);

        vm.expectRevert("REBAL: zero delay");
        new RebalanceController(_founding(), verifier, 0);

        vm.expectRevert("REBAL: zero verifier");
        new RebalanceController(_founding(), IStockTokenVerifier(address(0)), DELAY);
    }

    function test_VerifierRejectsEOAAndBadSurfaces() public {
        assertFalse(verifier.isVerifiedCanonicalToken(makeAddr("eoa")), "EOA rejected");

        MockERC20VariableDecimals badDecimals = new MockERC20VariableDecimals("B", "B", 6);
        assertFalse(verifier.isVerifiedCanonicalToken(address(badDecimals)), "bad decimals rejected");

        MockStockToken good = new MockStockToken("G", "Good");
        assertTrue(verifier.isVerifiedCanonicalToken(address(good)), "proper surface accepted");
        assertTrue(verifier.isVerifiedCanonicalToken(address(s1)), "founding surface accepted");
    }
}
