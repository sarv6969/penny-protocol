// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IRewardVault} from "../basket/IRewardVault.sol";

/// @notice Custodian of purchased reward Stock Tokens, fed by BasketBuyer, drawn down by the
/// RewardDistributor. Ingress PULLS custody: `receiveRewardAsset` transfers the tokens from the
/// reward source in the same call that extends the `lifetimeDeposits` record, so the record can
/// never exceed physical custody. Per D013, WETH (owed to purchases), PENNY, and every token ever
/// received as reward are NOT admin-recoverable; only unrelated accidental deposits may be
/// recovered by the owner (moved to a timelocked recovery on mainnet).
/// @dev `rewardSource` and `distributor` are set-once latches (D031): once wired, the owner can
/// never redirect the vault's ingress or egress to a different contract, closing the
/// admin-drain path through a swapped distributor.
contract RewardVault is Ownable, IRewardVault {
    using SafeERC20 for IERC20;

    IERC20 public immutable WETH;
    IERC20 public immutable PENNY;

    address public rewardSource;
    address public distributor;

    mapping(address => uint256) public lifetimeDeposits;

    error NotRewardSource();
    error NotDistributor();
    error ProtectedAsset();
    error AlreadySet();
    error ZeroAddress();
    error ZeroAmount();

    event RewardSourceSet(address indexed source);
    event DistributorSet(address indexed distributor);
    event RewardsDeposited(address indexed token, uint256 amount);
    event RewardsRedeemed(address indexed token, address indexed to, uint256 amount);
    event AccidentalFundsRecovered(address indexed token, address indexed to, uint256 amount);

    constructor(address initialOwner, IERC20 weth, IERC20 penny) Ownable(initialOwner) {
        WETH = weth;
        PENNY = penny;
    }

    /// @dev Set-once: the ingress contract cannot be swapped after wiring (D031).
    function setRewardSource(address source) external onlyOwner {
        if (source == address(0)) revert ZeroAddress();
        if (rewardSource != address(0)) revert AlreadySet();
        rewardSource = source;
        emit RewardSourceSet(source);
    }

    /// @dev Set-once: the egress contract cannot be swapped after wiring (D031).
    function setDistributor(address distributor_) external onlyOwner {
        if (distributor_ == address(0)) revert ZeroAddress();
        if (distributor != address(0)) revert AlreadySet();
        distributor = distributor_;
        emit DistributorSet(distributor_);
    }

    /// @dev Only the basket buyer (reward source) may feed the vault. Custody moves in the same
    ///      call as the record: tokens are pulled from the caller (requires prior approval).
    function receiveRewardAsset(IERC20 token, uint256 amount) external {
        if (msg.sender != rewardSource) revert NotRewardSource();
        if (amount == 0) revert ZeroAmount();
        uint256 balanceBefore = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = token.balanceOf(address(this)) - balanceBefore;
        // Stock Tokens are not fee-on-transfer; record only what physically arrived, fail closed
        // on any shortfall so the record can never exceed custody.
        if (received != amount) revert ZeroAmount();
        lifetimeDeposits[address(token)] += amount;
        emit RewardsDeposited(address(token), amount);
    }

    /// @dev Only the distributor draws down; tokens go straight to the claimant.
    function redeem(IERC20 token, address to, uint256 amount) external {
        if (msg.sender != distributor) revert NotDistributor();
        if (amount == 0) revert ZeroAmount();
        token.safeTransfer(to, amount);
        emit RewardsRedeemed(address(token), to, amount);
    }

    /// @dev D013: WETH, PENNY and any historical reward asset are never recoverable.
    function recoverAccidental(IERC20 token, address to, uint256 amount) external onlyOwner {
        if (token == WETH || token == PENNY) revert ProtectedAsset();
        if (lifetimeDeposits[address(token)] > 0) revert ProtectedAsset();
        token.safeTransfer(to, amount);
        emit AccidentalFundsRecovered(address(token), to, amount);
    }
}
