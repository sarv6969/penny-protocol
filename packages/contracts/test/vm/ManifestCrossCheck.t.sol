// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {EligibilityRegistry} from "../../src/rewards/EligibilityRegistry.sol";
import {RewardVault} from "../../src/rewards/RewardVault.sol";
import {RewardDistributor} from "../../src/rewards/RewardDistributor.sol";
import {MerkleHarness} from "../utils/MerkleHarness.sol";

/// @notice Phase 8 cross-language lockstep: the indexer (TypeScript) writes
///         `manifest.golden.json`; this test proves the TS Merkle tree, leaves and proofs
///         are bit-for-bit identical to the Solidity `RewardDistributor` semantics, and that
///         a real claim can be replayed onchain from the committed manifest.
contract ManifestCrossCheck is Test {
    string constant JSON_PATH = "test/fixtures/manifest.golden.json";
    uint256 internal constant SIGNER_KEY = 0xA11CE;
    address internal constant REWARD_SOURCE = address(0x501);

    MerkleHarness merkle = new MerkleHarness();

    function test_RecomputedLeavesMatchPublishedRoot() public {
        string memory json = vm.readFile(JSON_PATH);
        bytes32 publishedRoot = vm.parseJsonBytes32(json, ".root");
        uint256 n = vm.parseJsonUint(json, ".walletCount");
        assertGt(n, 0);

        bytes32[] memory leaves = new bytes32[](n);
        for (uint256 i = 0; i < n; i++) {
            string memory key = vm.toString(i);
            address wallet = vm.parseJsonAddress(json, string.concat(".walletProofs[", key, "].wallet"));
            uint256[] memory cumulative = vm.parseJsonUintArray(json, string.concat(".walletProofs[", key, "].cumulative"));
            leaves[i] = keccak256(abi.encode(wallet, cumulative));
        }

        assertEq(bytes32(merkle.rootOf(leaves)), publishedRoot, "TypeScript root must equal Solidity root recomputed from the manifest");

        for (uint256 i = 0; i < n; i++) {
            string memory key = vm.toString(i);
            bytes32[] memory proof = vm.parseJsonBytes32Array(json, string.concat(".walletProofs[", key, "].proof"));
            assertTrue(MerkleProof.verify(proof, publishedRoot, leaves[i]), "indexer proof must verify for OZ");
        }
    }

    struct Env {
        address[] tokens;
        EligibilityRegistry registry;
        RewardVault vault;
        RewardDistributor distributor;
    }

    function test_EndToEndClaimReplaysIndexerManifest() public {
        string memory json = vm.readFile(JSON_PATH);
        bytes32 root = vm.parseJsonBytes32(json, ".root");
        Env memory env = _deployEnv(json);

        env.distributor.publishEpoch(root, env.tokens, _fundedPair(json), root);

        // Claim as the first manifest wallet with its exact fixture cumulative + proof.
        address wallet = vm.parseJsonAddress(json, ".walletProofs[0].wallet");
        uint256[] memory cumulative = vm.parseJsonUintArray(json, ".walletProofs[0].cumulative");
        uint64 expiry = uint64(block.timestamp + 30 days);
        bytes memory sig = _sig(wallet, 0, env.registry, address(env.distributor), root, expiry);

        vm.prank(wallet);
        uint256[] memory deltas =
            env.distributor.claim(0, cumulative, vm.parseJsonBytes32Array(json, ".walletProofs[0].proof"), expiry, sig);

        for (uint256 i = 0; i < 2; i++) {
            assertEq(deltas[i], cumulative[i], "first claim pays the full genesis-total");
            assertEq(IERC20(env.tokens[i]).balanceOf(wallet), cumulative[i], "token landed in the wallet");
        }
        assertEq(env.distributor.lastClaimed(wallet), 1);
    }

    function _deployEnv(string memory json) internal returns (Env memory env) {
        MockERC20[2] memory rwd = [new MockERC20("Reward One", "REW1"), new MockERC20("Reward Two", "REW2")];
        env.tokens = _sortedPair(address(rwd[0]), address(rwd[1]));

        MockERC20 penny = new MockERC20("Penny Stocks", "PENNY");
        env.registry = new EligibilityRegistry(address(this), IERC20(address(penny)));
        env.registry.setAttestationSigner(vm.addr(SIGNER_KEY));

        env.vault = new RewardVault(address(this), IERC20(address(rwd[0])), IERC20(address(penny)));
        env.vault.setRewardSource(REWARD_SOURCE);
        env.distributor = new RewardDistributor(address(this), env.vault, env.registry, 0);
        env.vault.setDistributor(address(env.distributor));
        env.distributor.grantRole(env.distributor.DISTRIBUTOR_ROLE(), address(this));

        // Fund the vault to the manifest's funded totals via the reward-source PULL ingress.
        for (uint256 i = 0; i < 2; i++) {
            uint256 funded = _fundedUnit(json, i);
            MockERC20(env.tokens[i]).mint(REWARD_SOURCE, funded);
            vm.startPrank(REWARD_SOURCE);
            MockERC20(env.tokens[i]).approve(address(env.vault), funded);
            env.vault.receiveRewardAsset(IERC20(env.tokens[i]), funded);
            vm.stopPrank();
        }
    }

    function _fundedPair(string memory json) internal view returns (uint256[] memory totals) {
        totals = new uint256[](2);
        totals[0] = _fundedUnit(json, 0);
        totals[1] = _fundedUnit(json, 1);
    }

    function _fundedUnit(string memory json, uint256 i) internal view returns (uint256) {
        return vm.parseJsonUint(
            json,
            i == 0 ? ".fundedTotals.0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" : ".fundedTotals.0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        );
    }

    function _sortedPair(address a, address b) internal pure returns (address[] memory out) {
        out = new address[](2);
        (out[0], out[1]) = a < b ? (a, b) : (b, a);
    }

    function _sig(address wallet, uint256 epochIndex, EligibilityRegistry registry, address distributor, bytes32 root, uint64 expiry)
        internal
        view
        returns (bytes memory)
    {
        bytes32 scope = keccak256(abi.encodePacked("PENNY_REWARD_ELIGIBILITY", block.chainid, distributor, epochIndex, root));
        bytes32 digest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", registry.messageHash(wallet, scope, expiry)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_KEY, digest);
        return abi.encodePacked(r, s, v);
    }
}
