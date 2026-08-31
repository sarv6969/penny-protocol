// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {RewardVault} from "../src/rewards/RewardVault.sol";

/// @notice Phase 7 vault tests: reward-source-only PULL ingress (custody moves with the
///         record), distributor-only redemption, set-once wiring latches (D031), and the
///         D013 protected-asset recovery boundary.
contract RewardVaultTest is Test {
    MockERC20 weth;
    MockERC20 penny;
    MockERC20 rwd;
    RewardVault vault;

    address internal constant SOURCE = address(0x501);
    address internal constant DISTRIBUTOR = address(0xD157);
    address user = address(0xBEEF);
    address recipient = address(0xF00D);

    function setUp() public {
        weth = new MockERC20("Wrapped Ether", "WETH");
        penny = new MockERC20("Penny Stocks", "PENNY");
        rwd = new MockERC20("Reward One", "REW1");
        vault = new RewardVault(address(this), IERC20(address(weth)), IERC20(address(penny)));
        vault.setRewardSource(SOURCE);
        vault.setDistributor(DISTRIBUTOR);
    }

    function _fundSource(uint256 amount) internal {
        rwd.mint(SOURCE, amount);
        vm.prank(SOURCE);
        rwd.approve(address(vault), amount);
    }

    function test_IngressOnlyFromRewardSource() public {
        _fundSource(1 ether);
        vm.prank(DISTRIBUTOR);
        vm.expectRevert(RewardVault.NotRewardSource.selector);
        vault.receiveRewardAsset(IERC20(address(rwd)), 1 ether);

        vm.prank(SOURCE);
        vault.receiveRewardAsset(IERC20(address(rwd)), 1 ether);
        assertEq(vault.lifetimeDeposits(address(rwd)), 1 ether);
        assertEq(rwd.balanceOf(address(vault)), 1 ether, "custody moved with the record");
    }

    function test_IngressWithoutTokensReverts() public {
        // The record can never exceed physical custody: pulling with no balance reverts.
        vm.prank(SOURCE);
        vm.expectRevert();
        vault.receiveRewardAsset(IERC20(address(rwd)), 1 ether);
        assertEq(vault.lifetimeDeposits(address(rwd)), 0);
    }

    function test_ZeroAmountIngressReverts() public {
        vm.prank(SOURCE);
        vm.expectRevert(RewardVault.ZeroAmount.selector);
        vault.receiveRewardAsset(IERC20(address(rwd)), 0);
    }

    function test_WiringIsSetOnce() public {
        vm.expectRevert(RewardVault.AlreadySet.selector);
        vault.setRewardSource(address(0xAAAA));
        vm.expectRevert(RewardVault.AlreadySet.selector);
        vault.setDistributor(address(0xBBBB));
    }

    function test_RedeemOnlyFromDistributor() public {
        rwd.mint(address(vault), 100 ether);
        vm.prank(SOURCE);
        vm.expectRevert(RewardVault.NotDistributor.selector);
        vault.redeem(IERC20(address(rwd)), recipient, 1 ether);

        vm.prank(DISTRIBUTOR);
        vault.redeem(IERC20(address(rwd)), recipient, 100 ether);
        assertEq(rwd.balanceOf(recipient), 100 ether);
    }

    function test_ZeroAmountRedeemReverts() public {
        vm.prank(DISTRIBUTOR);
        vm.expectRevert(RewardVault.ZeroAmount.selector);
        vault.redeem(IERC20(address(rwd)), recipient, 0);
    }

    function test_WethAndPennyNeverRecoverable() public {
        weth.mint(address(vault), 1 ether);
        penny.mint(address(vault), 1 ether);

        vm.expectRevert(RewardVault.ProtectedAsset.selector);
        vault.recoverAccidental(IERC20(address(weth)), recipient, 1 ether);
        vm.expectRevert(RewardVault.ProtectedAsset.selector);
        vault.recoverAccidental(IERC20(address(penny)), recipient, 1 ether);
        assertEq(weth.balanceOf(address(vault)), 1 ether);
        assertEq(penny.balanceOf(address(vault)), 1 ether);
    }

    function test_HistoricalRewardAssetNeverRecoverable() public {
        _fundSource(1 ether);
        vm.prank(SOURCE);
        vault.receiveRewardAsset(IERC20(address(rwd)), 1 ether);
        rwd.mint(address(vault), 1 ether); // extra stray on top of the reward record

        vm.expectRevert(RewardVault.ProtectedAsset.selector);
        vault.recoverAccidental(IERC20(address(rwd)), recipient, 1 ether);
    }

    function test_UnrelatedAccidentalDepositRecoverable() public {
        MockERC20 stray = new MockERC20("Stray Coin", "STRY");
        stray.mint(address(vault), 42 ether);

        vault.recoverAccidental(IERC20(address(stray)), recipient, 42 ether);
        assertEq(stray.balanceOf(recipient), 42 ether);
    }

    function test_RecoveryOwnerOnly() public {
        MockERC20 stray = new MockERC20("Stray Coin", "STRY");
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));
        vault.recoverAccidental(IERC20(address(stray)), recipient, 1);
    }
}
