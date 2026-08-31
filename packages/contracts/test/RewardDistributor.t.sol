// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {EligibilityRegistry} from "../src/rewards/EligibilityRegistry.sol";
import {RewardVault} from "../src/rewards/RewardVault.sol";
import {RewardDistributor} from "../src/rewards/RewardDistributor.sol";
import {MerkleHarness} from "./utils/MerkleHarness.sol";

/// @notice Phase 7 reward tests: cumulative multi-asset Merkle distribution with scoped
///         expiring eligibility attestations, admiralty-of-claim, challenge-delayed root
///         activation with cancellation, funding caps, and catch-up claims.
contract RewardDistributorTest is Test {
    MockERC20 penny;
    MockERC20 weth;
    MockERC20[3] rwd;
    address[3] ascTokens;

    EligibilityRegistry registry;
    RewardVault vault;
    RewardDistributor distributor;
    MerkleHarness merkle = new MerkleHarness();

    uint256 internal constant SIGNER_KEY = 0xA11CE;
    uint64 internal constant CHALLENGE_DELAY = 6 hours;
    address signerAddr;

    address internal REWARD_SOURCE = address(0x501);
    address internal constant WALLET0 = address(0xFEED);
    address internal constant WALLET1 = address(0xCAFE);

    function setUp() public {
        penny = new MockERC20("Penny Stocks", "PENNY");
        weth = new MockERC20("Wrapped Ether", "WETH");
        rwd[0] = new MockERC20("Reward One", "REW1");
        rwd[1] = new MockERC20("Reward Two", "REW2");
        rwd[2] = new MockERC20("Reward Three", "REW3");
        ascTokens = _sorted3(address(rwd[0]), address(rwd[1]), address(rwd[2]));

        signerAddr = vm.addr(SIGNER_KEY);
        registry = new EligibilityRegistry(address(this), IERC20(address(penny)));
        registry.setAttestationSigner(signerAddr);

        vault = new RewardVault(address(this), IERC20(address(weth)), IERC20(address(penny)));
        vault.setRewardSource(REWARD_SOURCE);
        distributor = new RewardDistributor(address(this), vault, registry, CHALLENGE_DELAY);
        vault.setDistributor(address(distributor));
        distributor.grantRole(distributor.DISTRIBUTOR_ROLE(), address(this));
        distributor.grantRole(distributor.ROOT_CANCEL_ROLE(), address(this));

        for (uint256 i = 0; i < 3; i++) {
            MockERC20(ascTokens[i]).mint(REWARD_SOURCE, 10_000 ether);
            vm.startPrank(REWARD_SOURCE);
            MockERC20(ascTokens[i]).approve(address(vault), type(uint256).max);
            vault.receiveRewardAsset(IERC20(ascTokens[i]), 10_000 ether);
            vm.stopPrank();
        }
    }

    // ------------------------------------------------------------------ helpers

    function _expiry() internal view returns (uint64) {
        return uint64(block.timestamp + 30 days);
    }

    function _leaf(address wallet, uint256 c0, uint256 c1, uint256 c2) internal pure returns (bytes32) {
        uint256[] memory c = new uint256[](3);
        c[0] = c0;
        c[1] = c1;
        c[2] = c2;
        return keccak256(abi.encode(wallet, c));
    }

    function _scope(uint256 epochIndex, bytes32 root) internal view returns (bytes32) {
        return keccak256(abi.encodePacked("PENNY_REWARD_ELIGIBILITY", block.chainid, address(distributor), epochIndex, root));
    }

    function _sig(address wallet, uint256 epochIndex, bytes32 root, uint64 expiry) internal view returns (bytes memory) {
        bytes32 digest =
            keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", registry.messageHash(wallet, _scope(epochIndex, root), expiry)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_KEY, digest);
        return abi.encodePacked(r, s, v);
    }

    /// @notice Publishes an epoch over two leaves (WALLET0, WALLET1), warps through the
    ///         challenge delay so it is active, and returns root+proof for WALLET0.
    function _publishEpoch(uint256 c0w0, uint256 c1w0, uint256 c2w0, uint256 c0w1, uint256 c1w1, uint256 c2w1)
        internal
        returns (bytes32 root, bytes32[] memory proof0)
    {
        (root, proof0) = _proposeEpoch(c0w0, c1w0, c2w0, c0w1, c1w1, c2w1);
        vm.warp(block.timestamp + CHALLENGE_DELAY);
    }

    function _proposeEpoch(uint256 c0w0, uint256 c1w0, uint256 c2w0, uint256 c0w1, uint256 c1w1, uint256 c2w1)
        internal
        returns (bytes32 root, bytes32[] memory proof0)
    {
        bytes32[] memory leaves = new bytes32[](2);
        leaves[0] = _leaf(WALLET0, c0w0, c1w0, c2w0);
        leaves[1] = _leaf(WALLET1, c0w1, c1w1, c2w1);
        root = merkle.rootOf(leaves);
        proof0 = merkle.proofFor(leaves, 0);

        address[] memory tokens = new address[](3);
        uint256[] memory totals = new uint256[](3);
        tokens[0] = ascTokens[0];
        tokens[1] = ascTokens[1];
        tokens[2] = ascTokens[2];
        totals[0] = c0w0 + c0w1;
        totals[1] = c1w0 + c1w1;
        totals[2] = c2w0 + c2w1;
        distributor.publishEpoch(root, tokens, totals, keccak256(abi.encode(root, "manifest")));
    }

    function _cumulative(uint256 c0, uint256 c1, uint256 c2) internal pure returns (uint256[] memory c) {
        c = new uint256[](3);
        c[0] = c0;
        c[1] = c1;
        c[2] = c2;
    }

    function _claimEpoch(uint256 epochIndex, uint256 c0, uint256 c1, uint256 c2, bytes32[] memory proof, bytes memory sig) internal {
        vm.prank(WALLET0);
        distributor.claim(epochIndex, _cumulative(c0, c1, c2), proof, _expiry(), sig);
    }

    // ------------------------------------------------------------------ claims

    function test_FirstClaimPaysFullCumulative() public {
        (bytes32 root0, bytes32[] memory p0) = _publishEpoch(0, 100 ether, 300 ether, 50 ether, 0, 0);

        _claimEpoch(0, 0, 100 ether, 300 ether, p0, _sig(WALLET0, 0, root0, _expiry()));

        assertEq(MockERC20(ascTokens[0]).balanceOf(WALLET0), 0);
        assertEq(MockERC20(ascTokens[1]).balanceOf(WALLET0), 100 ether);
        assertEq(MockERC20(ascTokens[2]).balanceOf(WALLET0), 300 ether);
        assertEq(distributor.claimed(WALLET0, ascTokens[1]), 100 ether);
        assertEq(distributor.claimed(WALLET0, ascTokens[2]), 300 ether);
    }

    function test_SecondEpochPaysOnlyDelta() public {
        (bytes32 root0, bytes32[] memory p0) = _publishEpoch(0, 100 ether, 300 ether, 50 ether, 0, 0);
        _claimEpoch(0, 0, 100 ether, 300 ether, p0, _sig(WALLET0, 0, root0, _expiry()));

        (bytes32 root1, bytes32[] memory p1) = _publishEpoch(0, 100 ether, 500 ether, 70 ether, 0, 0);
        _claimEpoch(1, 0, 100 ether, 500 ether, p1, _sig(WALLET0, 1, root1, _expiry()));

        assertEq(MockERC20(ascTokens[1]).balanceOf(WALLET0), 100 ether);
        assertEq(MockERC20(ascTokens[2]).balanceOf(WALLET0), 500 ether, "only +200 delta");
        assertEq(MockERC20(ascTokens[1]).balanceOf(address(vault)), 10_000 ether - 100 ether);
    }

    function test_ReclaimReturnsZeroDeltas() public {
        (bytes32 root0, bytes32[] memory p0) = _publishEpoch(0, 100 ether, 300 ether, 50 ether, 0, 0);
        bytes memory sig = _sig(WALLET0, 0, root0, _expiry());
        _claimEpoch(0, 0, 100 ether, 300 ether, p0, sig);

        vm.prank(WALLET0);
        uint256[] memory deltas = distributor.claim(0, _cumulative(0, 100 ether, 300 ether), p0, _expiry(), sig);

        for (uint256 i = 0; i < 3; i++) {
            assertEq(deltas[i], 0, "nothing re-paid");
        }
        assertEq(MockERC20(ascTokens[2]).balanceOf(WALLET0), 300 ether);
    }

    function test_BadProofReverts() public {
        (bytes32 root0,) = _publishEpoch(0, 100 ether, 300 ether, 50 ether, 0, 0);

        // WALLET1's proof cannot verify WALLET0's leaf.
        bytes32[] memory leaves = new bytes32[](2);
        leaves[0] = _leaf(WALLET0, 0, 100 ether, 300 ether);
        leaves[1] = _leaf(WALLET1, 50 ether, 0, 0);
        bytes32[] memory wrong = merkle.proofFor(leaves, 1);
        bytes memory sig = _sig(WALLET0, 0, root0, _expiry());

        vm.prank(WALLET0);
        vm.expectRevert(RewardDistributor.BadProof.selector);
        distributor.claim(0, _cumulative(0, 100 ether, 300 ether), wrong, _expiry(), sig);
    }

    function test_NotEligibleWithoutAttestation() public {
        (, bytes32[] memory p0) = _publishEpoch(0, 100 ether, 300 ether, 50 ether, 0, 0);
        vm.prank(WALLET0);
        vm.expectRevert(RewardDistributor.NotEligible.selector);
        distributor.claim(0, _cumulative(0, 100 ether, 300 ether), p0, _expiry(), hex"");
    }

    function test_ExpiredAttestationRejected() public {
        (bytes32 root0, bytes32[] memory p0) = _publishEpoch(0, 100 ether, 300 ether, 50 ether, 0, 0);
        uint64 shortExpiry = uint64(block.timestamp + 1);
        bytes memory sig = _sig(WALLET0, 0, root0, shortExpiry);
        vm.warp(block.timestamp + 2);

        vm.prank(WALLET0);
        vm.expectRevert(RewardDistributor.NotEligible.selector);
        distributor.claim(0, _cumulative(0, 100 ether, 300 ether), p0, shortExpiry, sig);
    }

    function test_AttestationScopeBindsToEpoch() public {
        (bytes32 root0,) = _publishEpoch(0, 100 ether, 300 ether, 50 ether, 0, 0);
        // Epoch 1 root; claim attempted with epoch 0's signature -> scope mismatch.
        (, bytes32[] memory p1) = _publishEpoch(0, 100 ether, 350 ether, 70 ether, 0, 0);

        bytes memory staleSig = _sig(WALLET0, 0, root0, _expiry());
        vm.prank(WALLET0);
        vm.expectRevert(RewardDistributor.NotEligible.selector);
        distributor.claim(1, _cumulative(0, 100 ether, 350 ether), p1, _expiry(), staleSig);
    }

    function test_RelayerCannotClaimForOthers() public {
        (bytes32 root0, bytes32[] memory p0) = _publishEpoch(0, 100 ether, 300 ether, 50 ether, 0, 0);
        // Relayer passes WALLET0's leaf/proof but is not the wallet -> leaf mismatch.
        bytes memory sig = _sig(WALLET0, 0, root0, _expiry());
        vm.prank(address(0xBAD));
        vm.expectRevert(RewardDistributor.BadProof.selector);
        distributor.claim(0, _cumulative(0, 100 ether, 300 ether), p0, _expiry(), sig);
    }

    function test_ClaimAllCatchesUpThenPrunes() public {
        bytes32[3] memory roots;
        bytes32[][3] memory proofs;
        for (uint256 e = 0; e < 3; e++) {
            (roots[e], proofs[e]) = _publishEpoch(0, 100 ether, 300 ether + e * 100 ether, 50 ether + e * 10 ether, 0, 0);
        }

        bytes32[][] memory proofsArr = new bytes32[][](3);
        uint256[][] memory cumulative = new uint256[][](3);
        uint64[] memory expiries = new uint64[](3);
        bytes[] memory sigs = new bytes[](3);
        for (uint256 e = 0; e < 3; e++) {
            proofsArr[e] = proofs[e];
            cumulative[e] = _cumulative(0, 100 ether, 300 ether + e * 100 ether);
            expiries[e] = _expiry();
            sigs[e] = _sig(WALLET0, e, roots[e], expiries[e]);
        }

        vm.prank(WALLET0);
        uint256 n = distributor.claimAll(proofsArr, cumulative, expiries, sigs);
        assertEq(n, 3, "three epochs in one tx");
        assertEq(MockERC20(ascTokens[1]).balanceOf(WALLET0), 100 ether);
        assertEq(MockERC20(ascTokens[2]).balanceOf(WALLET0), 500 ether);
        assertEq(distributor.lastClaimed(WALLET0), 3);

        vm.expectRevert(RewardDistributor.PrunedTooFar.selector);
        vm.prank(WALLET0);
        distributor.claimUpTo(0, proofsArr, cumulative, expiries, sigs);
    }

    function test_UnderfundedVaultAbortsEverything() public {
        (bytes32 root0, bytes32[] memory p0) = _publishEpoch(0, 100 ether, 300 ether, 50 ether, 0, 0);

        // Physically short the vault on ascTokens[2] below the leaf's 300 ether (records intact).
        deal(address(ascTokens[2]), address(vault), 300 ether - 1);
        bytes memory sig = _sig(WALLET0, 0, root0, _expiry());

        vm.prank(WALLET0);
        vm.expectRevert(); // all-or-nothing: no token leaves the vault
        distributor.claim(0, _cumulative(0, 100 ether, 300 ether), p0, _expiry(), sig);

        assertEq(MockERC20(ascTokens[1]).balanceOf(address(vault)), 10_000 ether, "untouched");
        assertEq(distributor.claimed(WALLET0, ascTokens[1]), 0, "no claimed state survives the revert");
    }

    // ------------------------------------------------------------------ auto-delivery (D034)

    function test_ClaimForDeliversToOptedInWallet() public {
        (bytes32 root0, bytes32[] memory p0) = _publishEpoch(0, 100 ether, 300 ether, 50 ether, 0, 0);
        vm.prank(WALLET0);
        registry.setAutoDelivery(true);

        // Any relayer (here the test contract) delivers; tokens land ONLY in WALLET0.
        distributor.claimFor(WALLET0, 0, _cumulative(0, 100 ether, 300 ether), p0, _expiry(), _sig(WALLET0, 0, root0, _expiry()));

        assertEq(MockERC20(ascTokens[1]).balanceOf(WALLET0), 100 ether, "delivered to entitled wallet");
        assertEq(MockERC20(ascTokens[1]).balanceOf(address(this)), 0, "relayer receives nothing");
        assertEq(distributor.lastClaimed(WALLET0), 1);
    }

    function test_ClaimForWithoutOptInReverts() public {
        (bytes32 root0, bytes32[] memory p0) = _publishEpoch(0, 100 ether, 300 ether, 50 ether, 0, 0);
        uint64 expiry = _expiry();
        bytes memory sig = _sig(WALLET0, 0, root0, expiry);
        vm.expectRevert(RewardDistributor.NotOptedIn.selector);
        distributor.claimFor(WALLET0, 0, _cumulative(0, 100 ether, 300 ether), p0, expiry, sig);
    }

    function test_ClaimForAfterOptOutReverts() public {
        (bytes32 root0, bytes32[] memory p0) = _publishEpoch(0, 100 ether, 300 ether, 50 ether, 0, 0);
        vm.prank(WALLET0);
        registry.setAutoDelivery(true);
        vm.prank(WALLET0);
        registry.setAutoDelivery(false);

        uint64 expiry = _expiry();
        bytes memory sig = _sig(WALLET0, 0, root0, expiry);
        vm.expectRevert(RewardDistributor.NotOptedIn.selector);
        distributor.claimFor(WALLET0, 0, _cumulative(0, 100 ether, 300 ether), p0, expiry, sig);
    }

    function test_ClaimForCannotRedirectOrForgeLeaf() public {
        (bytes32 root0, bytes32[] memory p0) = _publishEpoch(0, 100 ether, 300 ether, 50 ether, 0, 0);
        address attacker = address(0xBAD);
        vm.prank(attacker);
        registry.setAutoDelivery(true);

        // Attacker opted in, but tries to claim with WALLET0's leaf under their own address:
        // the leaf binds the wallet, so the proof fails.
        uint64 expiry = _expiry();
        bytes memory sig = _sig(attacker, 0, root0, expiry);
        vm.prank(attacker);
        vm.expectRevert(RewardDistributor.BadProof.selector);
        distributor.claimFor(attacker, 0, _cumulative(0, 100 ether, 300 ether), p0, expiry, sig);
    }

    function test_ClaimForManySkipsBadEntriesAndDeliversRest() public {
        // WALLET0 and WALLET1 both entitled; only WALLET0 opts in.
        (bytes32 root0,) = _publishEpoch(0, 100 ether, 300 ether, 50 ether, 10 ether, 5 ether);
        bytes32[] memory leaves = new bytes32[](2);
        leaves[0] = _leaf(WALLET0, 0, 100 ether, 300 ether);
        leaves[1] = _leaf(WALLET1, 50 ether, 10 ether, 5 ether);

        vm.prank(WALLET0);
        registry.setAutoDelivery(true);
        // WALLET1 not opted in -> skipped silently, not fatal.

        RewardDistributor.Delivery[] memory batch = new RewardDistributor.Delivery[](2);
        batch[0] = RewardDistributor.Delivery({
            wallet: WALLET0,
            cumulative: _cumulative(0, 100 ether, 300 ether),
            proof: merkle.proofFor(leaves, 0),
            attestationExpiry: _expiry(),
            attestationSignature: _sig(WALLET0, 0, root0, _expiry())
        });
        batch[1] = RewardDistributor.Delivery({
            wallet: WALLET1,
            cumulative: _cumulative(50 ether, 10 ether, 5 ether),
            proof: merkle.proofFor(leaves, 1),
            attestationExpiry: _expiry(),
            attestationSignature: _sig(WALLET1, 0, root0, _expiry())
        });

        uint256 delivered = distributor.claimForMany(0, batch);
        assertEq(delivered, 1, "only the opted-in wallet is delivered");
        assertEq(MockERC20(ascTokens[1]).balanceOf(WALLET0), 100 ether);
        assertEq(MockERC20(ascTokens[1]).balanceOf(WALLET1), 0, "no delivery without opt-in");
    }

    function test_DeliverOneIsSelfOnly() public {
        (, bytes32[] memory p0) = _publishEpoch(0, 100 ether, 300 ether, 50 ether, 0, 0);
        vm.expectRevert("DIST: self only");
        distributor.deliverOne(WALLET0, 0, _cumulative(0, 100 ether, 300 ether), p0, _expiry(), hex"");
    }

    function test_AutoDeliveryBySigOnboardsGaslessly() public {
        // Wallet with a known key signs the opt-in offchain; a relayer submits it.
        uint256 walletKey = 0x1234;
        address wallet = vm.addr(walletKey);

        bytes32 inner = keccak256(abi.encodePacked("PENNY_AUTO_DELIVERY", wallet, true, uint256(0), block.chainid, address(registry)));
        bytes32 digest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", inner));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(walletKey, digest);

        registry.setAutoDeliveryBySig(wallet, true, 0, abi.encodePacked(r, s, v));
        assertTrue(registry.autoDelivery(wallet), "opted in by signature");

        // Replay of the same signature fails (nonce advanced).
        vm.expectRevert("ELIG: bad nonce");
        registry.setAutoDeliveryBySig(wallet, true, 0, abi.encodePacked(r, s, v));
    }

    // ------------------------------------------------------------------ root lifecycle (D032)

    function test_ClaimBeforeActivationReverts() public {
        (bytes32 root0, bytes32[] memory p0) = _proposeEpoch(0, 100 ether, 300 ether, 50 ether, 0, 0);
        assertFalse(distributor.isEpochActive(0), "not active during challenge window");

        uint64 expiry = _expiry();
        bytes memory sig = _sig(WALLET0, 0, root0, expiry);
        vm.prank(WALLET0);
        vm.expectRevert(RewardDistributor.EpochNotActive.selector);
        distributor.claim(0, _cumulative(0, 100 ether, 300 ether), p0, expiry, sig);

        vm.warp(block.timestamp + CHALLENGE_DELAY);
        assertTrue(distributor.isEpochActive(0), "active after delay");
    }

    function test_CancelDuringChallengeWindowBlocksClaims() public {
        (bytes32 root0, bytes32[] memory p0) = _proposeEpoch(0, 100 ether, 300 ether, 50 ether, 0, 0);
        distributor.cancelEpoch(0);

        vm.warp(block.timestamp + CHALLENGE_DELAY + 1);
        assertFalse(distributor.isEpochActive(0), "cancelled epoch never activates");
        uint64 expiry = _expiry();
        bytes memory sig = _sig(WALLET0, 0, root0, expiry);
        vm.prank(WALLET0);
        vm.expectRevert(RewardDistributor.EpochNotActive.selector);
        distributor.claim(0, _cumulative(0, 100 ether, 300 ether), p0, expiry, sig);
    }

    function test_CancelAfterActivationReverts() public {
        _publishEpoch(0, 100 ether, 300 ether, 50 ether, 0, 0);
        vm.expectRevert(RewardDistributor.AlreadyActive.selector);
        distributor.cancelEpoch(0);
    }

    function test_CancelRequiresRole() public {
        _proposeEpoch(0, 100 ether, 300 ether, 50 ether, 0, 0);
        bytes32 role = distributor.ROOT_CANCEL_ROLE();
        vm.prank(address(0xBAD));
        vm.expectRevert(
            abi.encodeWithSelector(bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")), address(0xBAD), role)
        );
        distributor.cancelEpoch(0);
    }

    function test_CancelledEpochSkippedInCatchUp() public {
        (bytes32 root0, bytes32[] memory p0) = _proposeEpoch(0, 100 ether, 300 ether, 50 ether, 0, 0);
        distributor.cancelEpoch(0);
        vm.warp(block.timestamp + CHALLENGE_DELAY);
        (bytes32 root1, bytes32[] memory p1) = _publishEpoch(0, 120 ether, 320 ether, 60 ether, 0, 0);

        bytes32[][] memory proofsArr = new bytes32[][](2);
        uint256[][] memory cumulative = new uint256[][](2);
        uint64[] memory expiries = new uint64[](2);
        bytes[] memory sigs = new bytes[](2);
        proofsArr[0] = p0;
        proofsArr[1] = p1;
        cumulative[0] = _cumulative(0, 100 ether, 300 ether);
        cumulative[1] = _cumulative(0, 120 ether, 320 ether);
        expiries[0] = _expiry();
        expiries[1] = _expiry();
        sigs[0] = _sig(WALLET0, 0, root0, expiries[0]);
        sigs[1] = _sig(WALLET0, 1, root1, expiries[1]);

        vm.prank(WALLET0);
        distributor.claimAll(proofsArr, cumulative, expiries, sigs);
        assertEq(MockERC20(ascTokens[1]).balanceOf(WALLET0), 120 ether, "cancelled epoch skipped, live epoch paid");
        assertEq(distributor.lastClaimed(WALLET0), 2);
    }

    // ------------------------------------------------------------------ funding caps (D032)

    function test_PublishExceedingVaultFundingReverts() public {
        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = _leaf(WALLET0, 0, 10_000 ether + 1, 0);
        bytes32 root = merkle.rootOf(leaves);

        address[] memory tokens = new address[](3);
        uint256[] memory totals = new uint256[](3);
        for (uint256 i = 0; i < 3; i++) {
            tokens[i] = ascTokens[i];
        }
        totals[1] = 10_000 ether + 1; // exceeds lifetimeDeposits by 1 wei

        vm.expectRevert(RewardDistributor.ExceedsFunding.selector);
        distributor.publishEpoch(root, tokens, totals, bytes32(uint256(1)));
    }

    function test_PublishDecreasingCumulativeTotalsReverts() public {
        _publishEpoch(0, 100 ether, 300 ether, 50 ether, 0, 0);

        address[] memory tokens = new address[](3);
        uint256[] memory totals = new uint256[](3);
        for (uint256 i = 0; i < 3; i++) {
            tokens[i] = ascTokens[i];
        }
        totals[1] = 99 ether; // below committed 100 ether for ascTokens[1]
        totals[2] = 300 ether + 50 ether;

        vm.expectRevert(RewardDistributor.CumulativeOutOfOrder.selector);
        distributor.publishEpoch(keccak256("r2"), tokens, totals, bytes32(uint256(2)));
    }

    // ------------------------------------------------------------------ publish guards

    function test_PublishZeroRootReverts() public {
        address[] memory tokens = new address[](1);
        uint256[] memory totals = new uint256[](1);
        tokens[0] = ascTokens[0];
        vm.expectRevert(RewardDistributor.ZeroRoot.selector);
        distributor.publishEpoch(bytes32(0), tokens, totals, bytes32(0));
    }

    function test_PublishRejectsUnsortedTokens() public {
        address[] memory tokens = new address[](2);
        uint256[] memory totals = new uint256[](2);
        tokens[0] = ascTokens[1];
        tokens[1] = ascTokens[0];
        vm.expectRevert(RewardDistributor.TokensNotSorted.selector);
        distributor.publishEpoch(keccak256("r"), tokens, totals, bytes32(0));
    }

    function test_PublishRequiresDistributorRole() public {
        address[] memory tokens = new address[](1);
        uint256[] memory totals = new uint256[](1);
        tokens[0] = ascTokens[0];
        bytes32 role = distributor.DISTRIBUTOR_ROLE();
        vm.prank(address(0xBAD));
        vm.expectRevert(
            abi.encodeWithSelector(bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")), address(0xBAD), role)
        );
        distributor.publishEpoch(keccak256("r"), tokens, totals, bytes32(0));
    }

    // ------------------------------------------------------------------ eligibility gating

    function test_LiveBalanceGateOptional() public {
        (bytes32 root0, bytes32[] memory p0) = _publishEpoch(0, 100 ether, 300 ether, 50 ether, 0, 0);
        uint64 expiry = _expiry();
        bytes memory sig = _sig(WALLET0, 0, root0, expiry);
        registry.setRequireLiveBalance(true);

        // Below the 100k PENNY threshold -> attestation still signed, but claim is blocked.
        penny.mint(WALLET0, 99_999 ether);
        vm.prank(WALLET0);
        vm.expectRevert(RewardDistributor.NotEligible.selector);
        distributor.claim(0, _cumulative(0, 100 ether, 300 ether), p0, expiry, sig);

        // Cross the threshold -> claim succeeds.
        penny.mint(WALLET0, 1 ether);
        vm.prank(WALLET0);
        distributor.claim(0, _cumulative(0, 100 ether, 300 ether), p0, expiry, sig);
        assertEq(MockERC20(ascTokens[2]).balanceOf(WALLET0), 300 ether);
    }

    // ------------------------------------------------------------------ util

    function _sorted3(address a, address b, address c) internal pure returns (address[3] memory out) {
        address[3] memory arr = [a, b, c];
        for (uint256 i = 0; i < 3; i++) {
            for (uint256 j = i + 1; j < 3; j++) {
                if (arr[j] < arr[i]) {
                    (arr[i], arr[j]) = (arr[j], arr[i]);
                }
            }
        }
        return arr;
    }
}
