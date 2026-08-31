// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {EligibilityRegistry} from "../../src/rewards/EligibilityRegistry.sol";
import {RewardVault} from "../../src/rewards/RewardVault.sol";
import {RewardDistributor} from "../../src/rewards/RewardDistributor.sol";
import {MerkleHarness} from "../utils/MerkleHarness.sol";

/// @notice Bounded random-walk keeper for the cumulative Merkle reward distributor (Phase 11).
/// @dev The walker publishes epochs over a closed set of three wallets x three reward tokens with
///      monotone cumulative leaves, then claims random (epoch, wallet) pairs with valid proofs and
///      signer attestations. The handler mirrors `distributor.claimed` so every invariant can
///      verify that a claimed epoch paid exactly the delta to the wallet's balance.
contract RewardDistributorHandler is Test {
    uint256 internal constant SIGNER_KEY = 0xA11CE;
    uint256 internal constant WALLET_COUNT = 3;
    uint256 internal constant TOKEN_COUNT = 3;
    uint256 internal constant MAX_EPOCHS = 40;

    EligibilityRegistry internal registry;
    RewardVault internal vault;
    RewardDistributor internal distributor;
    MerkleHarness internal merkle;

    address[3] internal wallets;
    address[3] internal rewardTokens;

    struct EpochRec {
        bytes32 root;
        bytes32[] leaves;
        uint256[] cum0;
        uint256[] cum1;
        uint256[] cum2;
        uint256 publishedAt;
    }
    EpochRec[] internal recs;

    uint256[3][3] internal currentCum; // [wallet][token]
    uint256[3][3] public mirrorClaimed; // [wallet][token]

    constructor(
        EligibilityRegistry registry_,
        RewardVault vault_,
        RewardDistributor distributor_,
        MerkleHarness merkle_,
        address[3] memory wallets_,
        address[3] memory rewardTokens_
    ) {
        registry = registry_;
        vault = vault_;
        distributor = distributor_;
        merkle = merkle_;
        wallets = wallets_;
        rewardTokens = rewardTokens_;
    }

    function recCount() external view returns (uint256) {
        return recs.length;
    }

    function publishedAtAt(uint256 i) external view returns (uint256) {
        return recs[i].publishedAt;
    }

    /// @dev Re-read the onchain epoch record. Solidity's public array-of-struct getter drops the
    ///      dynamic array members, leaving (root, scope, manifestHash, proposedAt, activatesAt,
    ///      cancelled).
    function onchainPublishedAt(uint256 i) external view returns (uint256) {
        (,,, uint64 proposedAt,,) = distributor.epochs(i);
        return uint256(proposedAt);
    }

    /// @notice Publishes a fresh epoch with monotone cumulative increments per wallet/token.
    function publishEpoch(uint256 seed) external {
        uint256 n = recs.length;
        if (n >= MAX_EPOCHS) return;
        seed = seed % 1e9;

        bytes32[] memory leaves = new bytes32[](WALLET_COUNT);
        uint256[] memory cum0 = new uint256[](TOKEN_COUNT);
        uint256[] memory cum1 = new uint256[](TOKEN_COUNT);
        uint256[] memory cum2 = new uint256[](TOKEN_COUNT);

        for (uint256 w = 0; w < WALLET_COUNT; w++) {
            uint256[] memory row = new uint256[](TOKEN_COUNT);
            for (uint256 t = 0; t < TOKEN_COUNT; t++) {
                uint256 r = uint256(keccak256(abi.encodePacked(seed, w, t, n)));
                uint256 inc = r % (1e20 + 1);
                currentCum[w][t] += inc;
                row[t] = currentCum[w][t];
            }
            leaves[w] = keccak256(abi.encode(wallets[w], row));
            if (w == 0) cum0 = row;
            else if (w == 1) cum1 = row;
            else cum2 = row;
        }

        bytes32 root = merkle.rootOf(leaves);
        address[] memory tokensArr = new address[](TOKEN_COUNT);
        uint256[] memory totalsArr = new uint256[](TOKEN_COUNT);
        for (uint256 t = 0; t < TOKEN_COUNT; t++) {
            tokensArr[t] = rewardTokens[t];
            for (uint256 w = 0; w < WALLET_COUNT; w++) {
                totalsArr[t] += currentCum[w][t];
            }
        }

        distributor.publishEpoch(root, tokensArr, totalsArr, keccak256(abi.encode(root, n)));
        recs.push(EpochRec({root: root, leaves: leaves, cum0: cum0, cum1: cum1, cum2: cum2, publishedAt: block.timestamp}));
    }

    /// @notice Claims a random (epoch, wallet) with the epoch's stored leaf/proof and a valid
    ///         scoped attestation; mirrors the resulting claimed cumulative on success.
    function claimEpoch(uint256 seed) external {
        uint256 n = recs.length;
        if (n == 0) return;
        uint256 e = seed % n;
        uint256 w = (seed / 17) % WALLET_COUNT;
        EpochRec storage rec = recs[e];
        uint256[] memory cum = w == 0 ? rec.cum0 : (w == 1 ? rec.cum1 : rec.cum2);
        bytes32[] memory proof = merkle.proofFor(rec.leaves, w);

        bytes32 scope = keccak256(abi.encodePacked("PENNY_REWARD_ELIGIBILITY", block.chainid, address(distributor), e, rec.root));
        uint64 expiry = uint64(block.timestamp + 30 days);
        bytes32 digest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", registry.messageHash(wallets[w], scope, expiry)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_KEY, digest);

        vm.prank(wallets[w]);
        distributor.claim(e, cum, proof, expiry, abi.encodePacked(r, s, v));

        for (uint256 t = 0; t < TOKEN_COUNT; t++) {
            mirrorClaimed[w][t] = cum[t];
        }
    }
}

/// @notice Invariant suite for RewardDistributor: epoch ledger monotonicity and exact-delta
///         payout accounting over a bounded random walk.
contract InvariantRewardDistributorTest is Test {
    address internal constant REWARD_SOURCE = address(0x501);
    uint256 internal constant INITIAL_FUNDING = 1e27;

    MockERC20 internal penny;
    MockERC20 internal weth;
    MockERC20[3] internal rwd;

    EligibilityRegistry internal registry;
    RewardVault internal vault;
    RewardDistributor internal distributor;
    MerkleHarness internal merkle = new MerkleHarness();

    address[3] internal wallets;
    address[3] internal rewardTokens;

    RewardDistributorHandler internal handler;

    function setUp() public {
        penny = new MockERC20("Penny Stocks", "PENNY");
        weth = new MockERC20("Wrapped Ether", "WETH");
        rwd[0] = new MockERC20("Reward One", "REW1");
        rwd[1] = new MockERC20("Reward Two", "REW2");
        rwd[2] = new MockERC20("Reward Three", "REW3");

        address[3] memory sorted = _sorted3(address(rwd[0]), address(rwd[1]), address(rwd[2]));
        for (uint256 i = 0; i < 3; i++) {
            rewardTokens[i] = sorted[i];
        }

        wallets[0] = vm.addr(0x7771);
        wallets[1] = vm.addr(0x7772);
        wallets[2] = vm.addr(0x7773);

        registry = new EligibilityRegistry(address(this), IERC20(address(penny)));
        registry.setAttestationSigner(vm.addr(0xA11CE));

        vault = new RewardVault(address(this), IERC20(address(weth)), IERC20(address(penny)));
        vault.setRewardSource(REWARD_SOURCE);

        // Zero challenge delay: the walk exercises claim accounting, not the activation window
        // (covered in RewardDistributor.t.sol).
        distributor = new RewardDistributor(address(this), vault, registry, 0);
        vault.setDistributor(address(distributor));

        for (uint256 t = 0; t < 3; t++) {
            MockERC20(rewardTokens[t]).mint(REWARD_SOURCE, INITIAL_FUNDING);
            vm.startPrank(REWARD_SOURCE);
            MockERC20(rewardTokens[t]).approve(address(vault), INITIAL_FUNDING);
            vault.receiveRewardAsset(IERC20(rewardTokens[t]), INITIAL_FUNDING);
            vm.stopPrank();
        }

        handler = new RewardDistributorHandler(registry, vault, distributor, merkle, wallets, rewardTokens);
        distributor.grantRole(distributor.DISTRIBUTOR_ROLE(), address(handler));
        targetContract(address(handler));
    }

    /// @dev epochCount only ever increases (handler ledger must match, i.e. no stale epochs).
    function invariant_epochCount_only_increases() external view {
        assertEq(handler.recCount(), distributor.epochCount(), "epoch count / ledger divergence");
    }

    /// @dev publishedAt across consecutive epochs is non-decreasing and matches the onchain record.
    function invariant_publishedAt_is_non_decreasing() external view {
        uint256 n = distributor.epochCount();
        for (uint256 i = 0; i < n; i++) {
            assertEq(handler.publishedAtAt(i), handler.onchainPublishedAt(i), "publishedAt diverged");
            if (i > 0) {
                assertGe(handler.publishedAtAt(i), handler.publishedAtAt(i - 1), "epoch publishedAt went backwards");
            }
        }
    }

    /// @dev Per (wallet, token): claimed ledger == onchain claimed == wallet token balance, i.e.
    ///      the monotone cumulative record is exact and every epoch paid precisely its delta.
    function invariant_claimed_pays_exact_deltas() external view {
        for (uint256 w = 0; w < 3; w++) {
            address wallet = wallets[w];
            for (uint256 t = 0; t < 3; t++) {
                uint256 onchain = distributor.claimed(wallet, rewardTokens[t]);
                uint256 mirrored = handler.mirrorClaimed(w, t);
                assertEq(onchain, mirrored, "onchain claimed diverged from handler mirror");
                assertEq(MockERC20(rewardTokens[t]).balanceOf(wallet), onchain, "wallet balance differs from cumulative claimed total");
            }
        }
    }

    /// @dev Vault drawdown across all wallets equals the cumulative totals; nothing overpaid.
    function invariant_vault_drawdown_is_bounded() external view {
        for (uint256 t = 0; t < 3; t++) {
            uint256 paid;
            for (uint256 w = 0; w < 3; w++) {
                paid += MockERC20(rewardTokens[t]).balanceOf(wallets[w]);
            }
            assertEq(
                MockERC20(rewardTokens[t]).balanceOf(address(vault)), INITIAL_FUNDING - paid, "vault not the sole agreed payer / overdraw"
            );
        }
    }

    function _sorted3(address a, address b, address c) internal pure returns (address[3] memory arr) {
        arr = [a, b, c];
        for (uint256 i = 0; i < 3; i++) {
            for (uint256 j = i + 1; j < 3; j++) {
                if (arr[j] < arr[i]) (arr[i], arr[j]) = (arr[j], arr[i]);
            }
        }
    }
}
