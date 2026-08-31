// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {PennyToken} from "../src/token/PennyToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PennyTokenTest is Test {
    PennyToken internal token;
    address internal deployer = makeAddr("deployer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 internal constant TOTAL_SUPPLY = 1_000_000_000e18;

    function setUp() public {
        vm.startPrank(deployer);
        token = new PennyToken(TOTAL_SUPPLY, deployer);
        vm.stopPrank();
    }

    function test_TotalSupplyFixed() public view {
        assertEq(token.totalSupply(), TOTAL_SUPPLY, "supply");
        assertEq(token.balanceOf(deployer), TOTAL_SUPPLY, "minted to recipient");
    }

    function test_Decimals() public view {
        assertEq(token.decimals(), 18, "decimals");
    }

    function test_NameAndSymbol() public view {
        assertEq(token.name(), "Penny Stocks", "name");
        assertEq(token.symbol(), "PENNY", "symbol");
    }

    function test_TransfersMoveBalancesNotSupply() public {
        vm.prank(deployer);
        token.transfer(alice, 100_000e18);

        assertEq(token.totalSupply(), TOTAL_SUPPLY, "supply unchanged");
        assertEq(token.balanceOf(alice), 100_000e18, "alice");
        assertEq(token.balanceOf(deployer), TOTAL_SUPPLY - 100_000e18, "deployer");
    }

    function _permitDigest(address owner, address spender, uint256 value, uint256 deadline) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner,
                spender,
                value,
                token.nonces(owner),
                deadline
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));
    }

    function test_PermitAllowsTransferFrom() public {
        uint256 privateKey = 0xA11CE;
        address owner = vm.addr(privateKey);
        uint256 deadline = block.timestamp + 1 days;

        vm.prank(deployer);
        token.transfer(owner, 1000e18);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, _permitDigest(owner, alice, 1000e18, deadline));
        vm.deal(alice, 1 ether);

        vm.prank(alice);
        token.permit(owner, alice, 1000e18, deadline, v, r, s);
        assertEq(token.allowance(owner, alice), 1000e18, "permit allowance");

        vm.prank(alice);
        token.transferFrom(owner, alice, 1000e18);

        assertEq(token.balanceOf(owner), 0, "owner balance after transferFrom");
        assertEq(token.balanceOf(alice), 1000e18, "alice balance after transferFrom");
        assertEq(token.nonces(owner), 1, "nonce bumped");
    }

    function test_PermitRejectsReplay() public {
        uint256 privateKey = 0xA11CE;
        address owner = vm.addr(privateKey);
        uint256 deadline = block.timestamp + 1 days;

        vm.prank(deployer);
        token.transfer(owner, 1000e18);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, _permitDigest(owner, alice, 1000e18, deadline));

        vm.prank(alice);
        token.permit(owner, alice, 1000e18, deadline, v, r, s);

        vm.expectRevert();
        vm.prank(alice);
        token.permit(owner, alice, 1000e18, deadline, v, r, s);
    }

    function test_ZerothRecipientReverts() public {
        vm.expectRevert("PENNY: zero recipient");
        new PennyToken(TOTAL_SUPPLY, address(0));
    }

    function testFuzz_roundTripsNeverChangeSupply(uint256 amountToAlice, uint256 amountToBob, uint256 onward) public {
        amountToAlice = bound(amountToAlice, 0, TOTAL_SUPPLY);
        amountToBob = bound(amountToBob, 0, amountToAlice);
        onward = bound(onward, 0, amountToBob);

        address aliceF = makeAddr("alice-fuzz");
        address bobF = makeAddr("bob-fuzz");
        address carolF = makeAddr("carol-fuzz");

        vm.startPrank(deployer);
        token.transfer(aliceF, amountToAlice);
        vm.stopPrank();

        vm.prank(aliceF);
        token.transfer(bobF, amountToBob);
        vm.prank(bobF);
        token.transfer(carolF, onward);

        assertEq(token.totalSupply(), TOTAL_SUPPLY, "fuzz supply invariant");
        assertEq(token.balanceOf(aliceF), amountToAlice - amountToBob, "alice");
        assertEq(token.balanceOf(bobF), amountToBob - onward, "bob");
        assertEq(token.balanceOf(carolF), onward, "carol");
    }

    function testFuzz_transferFrom_approveAndMove(uint256 allowance_, uint256 amount) public {
        allowance_ = bound(allowance_, 0, TOTAL_SUPPLY);
        amount = bound(amount, 0, allowance_);

        address owner = makeAddr("owner");
        vm.prank(deployer);
        token.transfer(owner, allowance_);

        vm.prank(owner);
        token.approve(alice, allowance_);
        vm.prank(alice);
        token.transferFrom(owner, bob, amount);

        assertEq(token.balanceOf(bob), amount, "bob");
        assertEq(token.allowance(owner, alice), allowance_ - amount, "allowance");
        assertEq(token.totalSupply(), TOTAL_SUPPLY, "supply invariant");
    }
}
