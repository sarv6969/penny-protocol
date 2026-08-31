// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {RewardVault} from "../../src/rewards/RewardVault.sol";

/// @notice Bounded random-walk keeper for RewardVault (Phase 11).
/// @dev Walk model (verified against the production wiring): `receiveRewardAsset` PULLS custody
///      from the reward source in the same call that extends the `lifetimeDeposits` burn-record,
///      so record and custody can never diverge on ingress. Stray inflows arrive without a
///      record, and physical egress happens only via distributor redeems and owner recoveries.
///      The walker also repeatedly ATTEMPTS to recover WETH/PENNY/protected assets; those revert
///      (checked: ghosts never advance), so the failing branch is exercised every run.
///      Token order (index 0..5): WETH, PENNY, REW1, REW2, REW3, STRAY.
contract RewardVaultHandler is Test {
    uint256 internal constant N = 6;

    address internal immutable owner;
    address internal constant REWARD_SOURCE = address(0x501);
    address internal constant REWARD_DISTRIBUTOR = address(0xD157);
    address internal constant RECIPIENT = address(0xF00D);

    RewardVault internal vault;
    MockERC20[6] internal tokens;

    /// @dev ghostStray   — unrecorded physical inflow (airdrop / mis-routed funds).
    /// @dev ghostDeposited — recorded inflow (the burn-record itself).
    /// @dev ghostRedeemed  — distributor draw-downs.
    /// @dev ghostRecovered — owner recoveries.
    mapping(uint256 => uint256) public ghostStray;
    mapping(uint256 => uint256) public ghostDeposited;
    mapping(uint256 => uint256) public ghostRedeemed;
    mapping(uint256 => uint256) public ghostRecovered;

    constructor(RewardVault vault_, MockERC20[6] memory tokens_, address owner_) {
        vault = vault_;
        tokens = tokens_;
        owner = owner_;
    }

    /// @notice Unrecorded physical inflow (stray token arrives in the vault). Not recoverable once
    ///         the deposit record for this token is non-empty.
    function strayDrop(uint256 sel, uint256 amountDesired) external {
        uint256 idx = sel % N;
        uint256 amount = amountDesired % (1e24 + 1);
        if (amount == 0) return;
        tokens[idx].mint(address(vault), amount);
        ghostStray[idx] += amount;
    }

    /// @notice Authorized reward ingress: the vault PULLS custody from the source in the same
    ///         call that extends the record, exactly as the basket rail intends.
    function depositReward(uint256 sel, uint256 amountDesired) external {
        uint256 idx = sel % N;
        uint256 amount = amountDesired % (1e23 + 1) + 1;
        tokens[idx].mint(REWARD_SOURCE, amount);
        vm.prank(REWARD_SOURCE);
        tokens[idx].approve(address(vault), amount);
        vm.prank(REWARD_SOURCE);
        vault.receiveRewardAsset(IERC20(address(tokens[idx])), amount);
        ghostDeposited[idx] += amount;
    }

    /// @notice Authorized egress only: the distributor pays a claimant, physically.
    function redeemReward(uint256 sel, uint256 amountDesired) external {
        uint256 idx = sel % N;
        uint256 bal = tokens[idx].balanceOf(address(vault));
        if (bal == 0) return;
        uint256 amount = amountDesired % (bal + 1);
        if (amount == 0) return;
        vm.prank(REWARD_DISTRIBUTOR);
        vault.redeem(IERC20(address(tokens[idx])), RECIPIENT, amount);
        ghostRedeemed[idx] += amount;
    }

    /// @notice Owner recovery attempt on ANY token. Protected assets (WETH/PENNY or any token
    ///         whose burn-record is non-empty) revert here — the walk intentionally hits the
    ///         revert path; ghosts and vault state only advance on a legitimate recovery.
    function recoverAccidental(uint256 sel, uint256 amountDesired) external {
        uint256 idx = sel % N;
        uint256 bal = tokens[idx].balanceOf(address(vault));
        if (bal == 0) return;
        uint256 amount = amountDesired % (bal + 1);
        if (amount == 0) return;
        vm.prank(owner);
        vault.recoverAccidental(IERC20(address(tokens[idx])), RECIPIENT, amount);
        ghostRecovered[idx] += amount;
    }
}

/// @notice Invariant suite for RewardVault: custody bookkeeping and the D013 protected-asset
///         burn-record boundary over a bounded random walk.
contract InvariantRewardVaultTest is Test {
    uint256 internal constant COUNT = 6;

    RewardVault internal vault;
    RewardVaultHandler internal handler;
    MockERC20[6] internal tokens;

    function setUp() public {
        tokens = [
            new MockERC20("Wrapped Ether", "WETH"),
            new MockERC20("Penny Stocks", "PENNY"),
            new MockERC20("Reward One", "REW1"),
            new MockERC20("Reward Two", "REW2"),
            new MockERC20("Reward Three", "REW3"),
            new MockERC20("Stray Coin", "STRY")
        ];

        vault = new RewardVault(address(this), IERC20(address(tokens[0])), IERC20(address(tokens[1])));
        vault.setRewardSource(address(0x501));
        vault.setDistributor(address(0xD157));

        handler = new RewardVaultHandler(vault, tokens, address(this));
        targetContract(address(handler));
    }

    /// @dev Every token's physical vault balance must be fully accounted for by the four custody
    ///      flows (stray arrival, recorded deposit, redeem, recover) — no unauthorized movement.
    ///      Note `receiveRewardAsset` only writes the record; the ledger must not be confused with
    ///      custody, so physical inflow is tracked explicitly.
    function invariant_physical_balances_are_fully_accounted() external view {
        for (uint256 i = 0; i < COUNT; i++) {
            uint256 expected = handler.ghostStray(i) + handler.ghostDeposited(i) - handler.ghostRedeemed(i) - handler.ghostRecovered(i);
            assertEq(tokens[i].balanceOf(address(vault)), expected, "unaccounted vault balance movement");
        }
    }

    /// @dev The deposit record (lifetimeDeposits / the D013 burn-record) is cumulative, only
    ///      extended by authorized deposits, and never rewound by redemptions or recoveries.
    function invariant_burn_record_never_rewound() external view {
        for (uint256 i = 0; i < COUNT; i++) {
            assertEq(vault.lifetimeDeposits(address(tokens[i])), handler.ghostDeposited(i), "burn-record diverged from deposit ledger");
        }
    }

    /// @dev WETH and PENNY are immutable-protected: no recovery of either can ever be recorded.
    function invariant_weth_and_penny_never_recoverable() external view {
        assertEq(handler.ghostRecovered(0), 0, "WETH recovery recorded");
        assertEq(handler.ghostRecovered(1), 0, "PENNY recovery recorded");
    }

    /// @dev D013 "recovered dust can never be claimed": the owner can only ever recover physical
    ///      balance that has NO deposit record — cumulative recoveries can therefore never exceed
    ///      the cumulative unrecorded (stray) inflow, so dust can never bite into the protected,
    ///      claimable reservoir.
    function invariant_recovered_dust_never_touches_burn_record() external view {
        for (uint256 i = 0; i < COUNT; i++) {
            assertLe(handler.ghostRecovered(i), handler.ghostStray(i), "recoveries exceeded the unrecorded (stray) reservoir");
        }
    }
}
