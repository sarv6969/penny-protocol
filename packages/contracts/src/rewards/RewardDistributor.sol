// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {RewardVault} from "./RewardVault.sol";
import {EligibilityRegistry} from "./EligibilityRegistry.sol";

/// @notice Cumulative multi-asset Merkle reward distributor (D010, D012, D026, D032).
/// @dev Each epoch commits a Merkle root whose leaves are
/// `keccak256(abi.encode(wallet, uint256[] cumulative))` over the epoch's reward tokens in
/// canonical (ascending) address order. Cumulative values are monotone across epochs; a claim
/// pays only the delta against what the wallet already claimed PER TOKEN ADDRESS (stable across
/// epochs whose token lists differ), so roots never expire and no push-to-holders is needed.
/// Admiralty is the wallet itself: every claim's leaf binds msg.sender, and claims are gated by
/// a signed, scoped, expiring eligibility attestation.
///
/// Root lifecycle (D032): DISTRIBUTOR_ROLE proposes a root together with the per-token cumulative
/// totals the manifest commits to; the totals are checked onchain against the vault's
/// lifetimeDeposits (funding can never be exceeded) and against the previous epoch's totals
/// (cumulative never decreases). The root activates only after `challengeDelay`; ROOT_CANCEL_ROLE
/// may cancel a NOT-yet-active root (erroneous manifest), but can never cancel an active one or
/// claw back completed claims. Claims verify against ACTIVE epochs only.
contract RewardDistributor is AccessControl, ReentrancyGuard {
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");
    bytes32 public constant ROOT_CANCEL_ROLE = keccak256("ROOT_CANCEL_ROLE");
    uint256 public constant MAX_REWARD_TOKENS = 8;

    struct Epoch {
        bytes32 root;
        address[] rewardTokens;
        uint256[] cumulativeTotals;
        bytes32 scope;
        bytes32 manifestHash;
        uint64 proposedAt;
        uint64 activatesAt;
        bool cancelled;
    }

    RewardVault public immutable vault;
    EligibilityRegistry public immutable eligibility;
    uint64 public immutable challengeDelay;

    Epoch[] public epochs;
    /// @notice Running total already paid to a wallet per reward TOKEN ADDRESS across all epochs.
    mapping(address => mapping(address => uint256)) public claimed;
    /// @notice Highest cumulative total ever committed per token (monotonicity anchor).
    mapping(address => uint256) public committedTotals;
    /// @notice Next unclaimed epoch hint for claimUpTo (monotone, never rewound).
    mapping(address => uint256) public lastClaimed;

    error ZeroRoot();
    error NotOptedIn();
    error BadTokenCount();
    error TokensNotSorted();
    error EmptyEpoch();
    error EpochNotActive();
    error EpochCancelled();
    error AlreadyActive();
    error NotEligible();
    error BadProof();
    error CumulativeOutOfOrder();
    error ExceedsFunding();
    error PrunedTooFar();

    event EpochProposed(uint256 indexed epochIndex, bytes32 indexed root, uint256 tokenCount, bytes32 manifestHash, uint64 activatesAt);
    event EpochCancelledEvent(uint256 indexed epochIndex, bytes32 indexed root, address indexed by);
    event RewardsClaimed(uint256 indexed epochIndex, address indexed wallet, address[] rewardTokens, uint256[] deltas);

    constructor(address admin, RewardVault vault_, EligibilityRegistry eligibility_, uint64 challengeDelay_) {
        vault = vault_;
        eligibility = eligibility_;
        challengeDelay = challengeDelay_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function epochCount() external view returns (uint256) {
        return epochs.length;
    }

    function epochTokens(uint256 epochIndex) external view returns (address[] memory) {
        return epochs[epochIndex].rewardTokens;
    }

    function epochScope(uint256 epochIndex) external view returns (bytes32) {
        return epochs[epochIndex].scope;
    }

    function isEpochActive(uint256 epochIndex) public view returns (bool) {
        if (epochIndex >= epochs.length) return false;
        Epoch storage ep = epochs[epochIndex];
        return !ep.cancelled && block.timestamp >= ep.activatesAt;
    }

    /// @notice Propose a new cumulative root. `cumulativeTotals[i]` is the manifest's total
    ///         cumulative entitlement for `rewardTokens[i]` across all wallets; it must not
    ///         decrease versus any prior commitment and must be covered by vault funding.
    function publishEpoch(bytes32 root, address[] calldata rewardTokens, uint256[] calldata cumulativeTotals, bytes32 manifestHash)
        external
        onlyRole(DISTRIBUTOR_ROLE)
        returns (uint256 epochIndex)
    {
        if (root == bytes32(0)) revert ZeroRoot();
        uint256 n = rewardTokens.length;
        if (n == 0 || n > MAX_REWARD_TOKENS) revert BadTokenCount();
        if (cumulativeTotals.length != n) revert BadTokenCount();
        for (uint256 i = 1; i < n; i++) {
            if (rewardTokens[i] <= rewardTokens[i - 1]) revert TokensNotSorted();
        }
        for (uint256 i = 0; i < n; i++) {
            address token = rewardTokens[i];
            // Cumulative totals never decrease across roots (D026).
            if (cumulativeTotals[i] < committedTotals[token]) revert CumulativeOutOfOrder();
            // Vault funding always covers cumulative liabilities (onchain half of D032).
            if (cumulativeTotals[i] > vault.lifetimeDeposits(token)) revert ExceedsFunding();
        }

        epochIndex = epochs.length;
        // Scope is domain-separated: chain + distributor + epoch + root (D027).
        bytes32 scope = keccak256(abi.encodePacked("PENNY_REWARD_ELIGIBILITY", block.chainid, address(this), epochIndex, root));
        uint64 activatesAt = uint64(block.timestamp) + challengeDelay;

        epochs.push(
            Epoch({
                root: root,
                rewardTokens: rewardTokens,
                cumulativeTotals: cumulativeTotals,
                scope: scope,
                manifestHash: manifestHash,
                proposedAt: uint64(block.timestamp),
                activatesAt: activatesAt,
                cancelled: false
            })
        );
        for (uint256 i = 0; i < n; i++) {
            committedTotals[rewardTokens[i]] = cumulativeTotals[i];
        }
        emit EpochProposed(epochIndex, root, n, manifestHash, activatesAt);
    }

    /// @notice Cancel a proposed-but-not-yet-active root (erroneous manifest). Active roots and
    ///         completed claims can never be cancelled or clawed back.
    function cancelEpoch(uint256 epochIndex) external onlyRole(ROOT_CANCEL_ROLE) {
        if (epochIndex >= epochs.length) revert EmptyEpoch();
        Epoch storage ep = epochs[epochIndex];
        if (ep.cancelled) revert EpochCancelled();
        if (block.timestamp >= ep.activatesAt) revert AlreadyActive();
        ep.cancelled = true;
        emit EpochCancelledEvent(epochIndex, ep.root, msg.sender);
    }

    /// @notice Claim one epoch as the entitled wallet (msg.sender).
    function claim(
        uint256 epochIndex,
        uint256[] calldata cumulative,
        bytes32[] calldata proof,
        uint64 attestationExpiry,
        bytes calldata attestationSignature
    ) external nonReentrant returns (uint256[] memory deltas) {
        deltas = _claim(msg.sender, epochIndex, cumulative, proof, attestationExpiry, attestationSignature);
        if (epochIndex + 1 > lastClaimed[msg.sender]) {
            lastClaimed[msg.sender] = epochIndex + 1;
        }
    }

    /// @notice $INDEX-style auto-delivery (D034): permissionlessly deliver an opted-in wallet's
    ///         rewards for one epoch. Anyone may call — the keeper is merely the default
    ///         operator — but tokens can ONLY land in the entitled wallet, the wallet must have
    ///         a live opt-in in the EligibilityRegistry, and the same proof/attestation gates
    ///         apply as for a self-claim. Holders who opt in never claim: Stock Tokens simply
    ///         arrive each epoch.
    function claimFor(
        address wallet,
        uint256 epochIndex,
        uint256[] calldata cumulative,
        bytes32[] calldata proof,
        uint64 attestationExpiry,
        bytes calldata attestationSignature
    ) external nonReentrant returns (uint256[] memory deltas) {
        if (!eligibility.autoDelivery(wallet)) revert NotOptedIn();
        deltas = _claim(wallet, epochIndex, cumulative, proof, attestationExpiry, attestationSignature);
        if (epochIndex + 1 > lastClaimed[wallet]) {
            lastClaimed[wallet] = epochIndex + 1;
        }
    }

    /// @notice One batch entry for claimForMany (keeps the batch path within stack limits).
    struct Delivery {
        address wallet;
        uint256[] cumulative;
        bytes32[] proof;
        uint64 attestationExpiry;
        bytes attestationSignature;
    }

    /// @notice Batched auto-delivery: one transaction delivers a whole epoch to many opted-in
    ///         wallets (keeper batch path, D034). Reverting entries are skipped, not fatal, so
    ///         one revoked/ineligible wallet can never block the rest of the batch.
    function claimForMany(uint256 epochIndex, Delivery[] calldata deliveries) external nonReentrant returns (uint256 delivered) {
        for (uint256 i = 0; i < deliveries.length; i++) {
            Delivery calldata d = deliveries[i];
            if (!eligibility.autoDelivery(d.wallet)) continue;
            try this.deliverOne(d.wallet, epochIndex, d.cumulative, d.proof, d.attestationExpiry, d.attestationSignature) {
                delivered++;
            } catch {}
        }
    }

    /// @dev Self-call target for claimForMany's isolated per-wallet delivery. Not callable
    ///      externally by anyone else.
    function deliverOne(
        address wallet,
        uint256 epochIndex,
        uint256[] calldata cumulative,
        bytes32[] calldata proof,
        uint64 attestationExpiry,
        bytes calldata attestationSignature
    ) external {
        require(msg.sender == address(this), "DIST: self only");
        _claim(wallet, epochIndex, cumulative, proof, attestationExpiry, attestationSignature);
        if (epochIndex + 1 > lastClaimed[wallet]) {
            lastClaimed[wallet] = epochIndex + 1;
        }
    }

    /// @notice Catch up on a contiguous range of unclaimed epochs in one transaction (D012).
    /// @dev `lastClaimed` stores the next unclaimed epoch index; the range must line up exactly
    ///      with the remaining epochs so a span can never be double-submitted.
    function claimUpTo(
        uint256 toEpoch,
        bytes32[][] calldata proofs,
        uint256[][] calldata cumulative,
        uint64[] calldata attestationExpiries,
        bytes[] calldata attestationSignatures
    ) public nonReentrant returns (uint256 totalEpochsClaimed) {
        if (toEpoch >= epochs.length) revert EmptyEpoch();
        uint256 from = lastClaimed[msg.sender];
        if (toEpoch < from) revert PrunedTooFar();
        uint256 span = toEpoch - from + 1;
        if (span != proofs.length) revert BadProof();
        if (cumulative.length != span || attestationSignatures.length != span || attestationExpiries.length != span) revert BadProof();

        for (uint256 i = 0; i < span; i++) {
            // Cancelled epochs are permanently inactive; skip them so they never block catch-up.
            if (epochs[from + i].cancelled) continue;
            _claim(msg.sender, from + i, cumulative[i], proofs[i], attestationExpiries[i], attestationSignatures[i]);
        }
        lastClaimed[msg.sender] = toEpoch + 1;
        totalEpochsClaimed = span;
    }

    function claimAll(
        bytes32[][] calldata proofs,
        uint256[][] calldata cumulative,
        uint64[] calldata attestationExpiries,
        bytes[] calldata attestationSignatures
    ) external returns (uint256 totalEpochsClaimed) {
        if (epochs.length == 0) revert EmptyEpoch();
        uint256 last = epochs.length - 1;
        return claimUpTo(last, proofs, cumulative, attestationExpiries, attestationSignatures);
    }

    function _claim(
        address wallet,
        uint256 epochIndex,
        uint256[] memory cumulative,
        bytes32[] memory proof,
        uint64 attestationExpiry,
        bytes memory attestationSignature
    ) internal returns (uint256[] memory deltas) {
        if (epochIndex >= epochs.length) revert EmptyEpoch();
        if (!isEpochActive(epochIndex)) revert EpochNotActive();
        Epoch storage ep = epochs[epochIndex];
        if (cumulative.length != ep.rewardTokens.length) revert BadProof();

        if (!MerkleProof.verify(proof, ep.root, keccak256(abi.encode(wallet, cumulative)))) revert BadProof();
        if (!eligibility.isEligible(wallet, ep.scope, attestationExpiry, attestationSignature)) revert NotEligible();

        deltas = _payDeltas(wallet, ep, cumulative);
        emit RewardsClaimed(epochIndex, wallet, ep.rewardTokens, deltas);
    }

    /// @dev All-or-nothing: tally every delta first, then draw down the vault. The cumulative
    ///      leaf values are genesis-total per token ADDRESS, so deltas stay exact even when the
    ///      epoch token lists change over time.
    function _payDeltas(address wallet, Epoch storage ep, uint256[] memory cumulative) private returns (uint256[] memory deltas) {
        uint256 n = ep.rewardTokens.length;
        deltas = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            uint256 before = claimed[wallet][ep.rewardTokens[i]];
            if (cumulative[i] < before) revert CumulativeOutOfOrder();
            deltas[i] = cumulative[i] - before;
        }
        for (uint256 i = 0; i < n; i++) {
            if (deltas[i] > 0) {
                address token = ep.rewardTokens[i];
                claimed[wallet][token] = cumulative[i];
                vault.redeem(IERC20(token), wallet, deltas[i]);
            }
        }
    }
}
