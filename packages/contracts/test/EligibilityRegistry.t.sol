// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {EligibilityRegistry} from "../src/rewards/EligibilityRegistry.sol";

/// @notice Phase 7 eligibility tests: scoped expiring attestation signatures, soft-fail
///         recovery, revocation, domain binding (chainid + registry address), owner-only
///         signer rotation, optional live-balance reinforcement.
contract EligibilityRegistryTest is Test {
    MockERC20 penny;
    EligibilityRegistry registry;

    uint256 internal constant SIGNER_KEY = 0xA11CE;
    address signer;
    address user = address(0xBEEF);
    bytes32 internal constant SCOPE = keccak256("SCOPE");
    uint64 internal EXPIRY;

    function setUp() public {
        penny = new MockERC20("Penny Stocks", "PENNY");
        signer = vm.addr(SIGNER_KEY);
        registry = new EligibilityRegistry(address(this), IERC20(address(penny)));
        EXPIRY = uint64(block.timestamp + 1 days);
    }

    function _sig(address wallet, bytes32 scope, uint64 expiry) internal view returns (bytes memory) {
        bytes32 digest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", registry.messageHash(wallet, scope, expiry)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_KEY, digest);
        return abi.encodePacked(r, s, v);
    }

    function test_NoSignerConfiguredFails() public view {
        assertFalse(registry.isEligible(user, SCOPE, EXPIRY, _sig(user, SCOPE, EXPIRY)));
    }

    function test_ValidAttestationPasses() public {
        registry.setAttestationSigner(signer);
        assertTrue(registry.isEligible(user, SCOPE, EXPIRY, _sig(user, SCOPE, EXPIRY)));
    }

    function test_WrongScopeFails() public {
        registry.setAttestationSigner(signer);
        assertFalse(registry.isEligible(user, keccak256("OTHER"), EXPIRY, _sig(user, SCOPE, EXPIRY)));
    }

    function test_WrongSignerFails() public {
        registry.setAttestationSigner(vm.addr(0xDEAD));
        assertFalse(registry.isEligible(user, SCOPE, EXPIRY, _sig(user, SCOPE, EXPIRY)));
    }

    function test_GarbageSignatureFailsSoft() public {
        registry.setAttestationSigner(signer);
        assertFalse(registry.isEligible(user, SCOPE, EXPIRY, hex"0001"));
        assertFalse(registry.isEligible(user, SCOPE, EXPIRY, hex""));
    }

    function test_ExpiredAttestationFails() public {
        registry.setAttestationSigner(signer);
        bytes memory sig = _sig(user, SCOPE, EXPIRY);
        assertTrue(registry.isEligible(user, SCOPE, EXPIRY, sig));
        vm.warp(uint256(EXPIRY) + 1);
        assertFalse(registry.isEligible(user, SCOPE, EXPIRY, sig), "attestation must expire");
    }

    function test_ExpiryIsSignedNotCallerSupplied() public {
        registry.setAttestationSigner(signer);
        bytes memory sig = _sig(user, SCOPE, EXPIRY);
        // A caller cannot stretch an expired attestation by claiming a longer expiry: the
        // expiry is inside the signed digest.
        assertFalse(registry.isEligible(user, SCOPE, EXPIRY + 1000, sig));
    }

    function test_RevocationBlocksFutureClaims() public {
        registry.setAttestationSigner(signer);
        bytes memory sig = _sig(user, SCOPE, EXPIRY);
        assertTrue(registry.isEligible(user, SCOPE, EXPIRY, sig));
        registry.setRevoked(user, true);
        assertFalse(registry.isEligible(user, SCOPE, EXPIRY, sig), "revoked wallet must fail");
        registry.setRevoked(user, false);
        assertTrue(registry.isEligible(user, SCOPE, EXPIRY, sig), "un-revocation restores");
    }

    function test_DomainBindingIncludesChainIdAndRegistry() public {
        registry.setAttestationSigner(signer);
        bytes memory sig = _sig(user, SCOPE, EXPIRY);

        // Same signature fails on another chain id (cross-chain replay).
        vm.chainId(999);
        assertFalse(registry.isEligible(user, SCOPE, EXPIRY, sig), "cross-chain replay must fail");
        vm.chainId(31337);
        assertTrue(registry.isEligible(user, SCOPE, EXPIRY, sig));

        // Same signature fails against a different registry deployment (cross-contract replay).
        EligibilityRegistry other = new EligibilityRegistry(address(this), IERC20(address(penny)));
        other.setAttestationSigner(signer);
        assertFalse(other.isEligible(user, SCOPE, EXPIRY, sig), "cross-registry replay must fail");
    }

    function test_LiveBalanceGate() public {
        registry.setAttestationSigner(signer);
        registry.setRequireLiveBalance(true);

        penny.mint(user, 100_000 ether - 1);
        assertFalse(registry.isEligible(user, SCOPE, EXPIRY, _sig(user, SCOPE, EXPIRY)));

        penny.mint(user, 1);
        assertTrue(registry.isEligible(user, SCOPE, EXPIRY, _sig(user, SCOPE, EXPIRY)));
    }

    function test_SettersAreOwnerOnly() public {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        registry.setAttestationSigner(signer);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        registry.setRequireLiveBalance(true);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        registry.setRevoked(user, true);
        vm.stopPrank();
    }

    function test_ZeroSignerRejected() public {
        vm.expectRevert("ELIG: zero signer");
        registry.setAttestationSigner(address(0));
    }

    function test_MessageHashIsDeterministic() public view {
        assertEq(
            registry.messageHash(user, SCOPE, EXPIRY), keccak256(abi.encodePacked(user, SCOPE, EXPIRY, block.chainid, address(registry)))
        );
        assertEq(registry.ELIGIBILITY_THRESHOLD(), 100_000 ether);
    }
}
