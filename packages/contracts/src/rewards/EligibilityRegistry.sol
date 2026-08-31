// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Eligibility gate for reward claims (D010, D004, D027).
/// @dev Eligibility is a signed, scoped, EXPIRING attestation: the signing service confirms a
/// wallet held at least ELIGIBILITY_THRESHOLD PENNY at a pinned block and signs
/// `keccak(wallet, scope, expiry, chainid, registry)`. The scope binds the attestation to one
/// reward epoch (its root + distributor + chain), the expiry bounds its lifetime, and the
/// chainid/registry fields prevent cross-chain and cross-deployment replay. Wallets can be
/// revoked under the counsel-approved policy (revocation blocks future claims, never completed
/// ones). Optionally the chain re-checks a live PENNY balance on top of the signature; this is
/// a maintenance flag, off by default because holders who later sell must not be locked out of
/// previously accrued rewards.
/// @dev Signature verification is soft-fail (`ECDSA.tryRecover`): malformed signatures yield
/// false, never revert.
contract EligibilityRegistry is Ownable {
    uint256 public constant ELIGIBILITY_THRESHOLD = 100_000e18;

    IERC20 public immutable PENNY;
    address public attestationSigner;
    bool public requireLiveBalance;
    mapping(address => bool) public revoked;
    /// @notice $INDEX-style auto-delivery opt-in (D034): wallets that enable this receive their
    ///         Stock Token rewards automatically via permissionless `claimFor` — no claiming.
    ///         Rewards can only ever land in the entitled wallet; opt-in is revocable anytime.
    mapping(address => bool) public autoDelivery;
    mapping(address => uint256) public autoDeliveryNonce;

    event AttestationSignerSet(address indexed signer);
    event RequireLiveBalanceChanged(bool enabled);
    event WalletRevocationSet(address indexed wallet, bool revoked);
    event AutoDeliverySet(address indexed wallet, bool enabled);

    constructor(address initialOwner, IERC20 penny_) Ownable(initialOwner) {
        PENNY = penny_;
    }

    function setAttestationSigner(address signer) external onlyOwner {
        require(signer != address(0), "ELIG: zero signer");
        attestationSigner = signer;
        emit AttestationSignerSet(signer);
    }

    function setRequireLiveBalance(bool enabled) external onlyOwner {
        requireLiveBalance = enabled;
        emit RequireLiveBalanceChanged(enabled);
    }

    /// @notice Counsel-policy revocation: blocks future claims for a wallet. Cannot claw back
    ///         claims already completed.
    function setRevoked(address wallet, bool revoked_) external onlyOwner {
        revoked[wallet] = revoked_;
        emit WalletRevocationSet(wallet, revoked_);
    }

    /// @notice Enable/disable auto-delivery directly from the wallet (D034).
    function setAutoDelivery(bool enabled) external {
        autoDelivery[msg.sender] = enabled;
        emit AutoDeliverySet(msg.sender, enabled);
    }

    /// @notice Enable/disable auto-delivery by wallet signature (gasless onboarding: the same
    ///         session that grants the eligibility attestation collects this signature, so the
    ///         holder signs once and never touches the chain again). Nonce prevents replay of a
    ///         stale enable after the wallet disables (and vice versa); domain bound to this
    ///         chain and registry like the eligibility digest.
    function setAutoDeliveryBySig(address wallet, bool enabled, uint256 nonce, bytes calldata signature) external {
        require(nonce == autoDeliveryNonce[wallet], "ELIG: bad nonce");
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n32",
                keccak256(abi.encodePacked("PENNY_AUTO_DELIVERY", wallet, enabled, nonce, block.chainid, address(this)))
            )
        );
        (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(digest, signature);
        require(err == ECDSA.RecoverError.NoError && recovered == wallet, "ELIG: bad signature");
        autoDeliveryNonce[wallet] = nonce + 1;
        autoDelivery[wallet] = enabled;
        emit AutoDeliverySet(wallet, enabled);
    }

    /// @notice Message the signer service signs as the ethereum-signed-message digest. Domain
    ///         bound to this chain and this registry deployment (non-replayable, D027).
    function messageHash(address wallet, bytes32 scope, uint64 expiry) public view returns (bytes32) {
        return keccak256(abi.encodePacked(wallet, scope, expiry, block.chainid, address(this)));
    }

    function isEligible(address wallet, bytes32 scope, uint64 expiry, bytes calldata signature) external view returns (bool) {
        if (attestationSigner == address(0)) return false;
        if (revoked[wallet]) return false;
        if (block.timestamp > expiry) return false;
        bytes32 digest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash(wallet, scope, expiry)));
        (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(digest, signature);
        if (err != ECDSA.RecoverError.NoError || recovered != attestationSigner) return false;
        if (!requireLiveBalance) return true;
        return PENNY.balanceOf(wallet) >= ELIGIBILITY_THRESHOLD;
    }
}
