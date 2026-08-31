// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {PennyToken} from "../../src/token/PennyToken.sol";

/// @notice Bounded random-walk keeper for the fixed-supply PENNY token (Phase 11).
/// @dev Mutations exercised by the fuzzer: vanilla transfers and a full EIP-2612
///      permit -> transferFrom cycle against a closed set of five signer-known actors.
///      Every mutation keeps a handler-side balance ledger; the invariants re-check that the
///      real token never diverges (supply constant, zero address untouched, non-movers intact).
contract PennyTokenHandler is Test {
    uint256 internal constant N = 5;
    uint256 internal constant SUPPLY = 1_000_000_000e18;
    bytes32 internal constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    PennyToken internal token;

    /// @dev actors[0] is the deployer; every actor's address derives from a known key so it can sign permits.
    address[N] internal actors;
    uint256[N] internal keys;

    /// @dev The handler's own ledger. The token contract must match it after every mutation.
    mapping(address => uint256) public mirror;

    constructor(PennyToken token_) {
        token = token_;
        for (uint256 i = 0; i < N; i++) {
            keys[i] = 0x1001 + i;
            actors[i] = vm.addr(keys[i]);
        }

        // Seed: deployer keeps 10%, the rest spreads 30/25/20/15% across the remaining actors.
        uint256 kept = SUPPLY * 10 / 100;
        uint256[4] memory pct = [uint256(30), 25, 20, 15];
        uint256 remain = SUPPLY - kept;
        mirror[actors[0]] = kept;
        for (uint256 i = 1; i < N; i++) {
            uint256 amt = SUPPLY * pct[i - 1] / 100;
            remain -= amt;
            vm.prank(actors[0]);
            require(token.transfer(actors[i], amt), "PVT: seed transfer failed");
            mirror[actors[i]] = amt;
        }
        require(remain == 0, "PVT: seed misallocation");
    }

    /// @notice Plain transfer between two actors, sized to the sender's current ledger balance.
    function transferRandom(uint256 sel, uint256 amountDesired) external {
        uint256 fromIdx = sel % N;
        uint256 toIdx = (sel / (N + 1)) % N;
        if (toIdx == fromIdx) toIdx = (toIdx + 1) % N;
        address from = actors[fromIdx];
        uint256 bal = mirror[from];
        if (bal == 0) return;
        uint256 amount = amountDesired % (bal + 1);
        if (amount == 0) return;

        vm.prank(from);
        bool ok = token.transfer(actors[toIdx], amount);
        if (ok) {
            mirror[from] = bal - amount;
            mirror[actors[toIdx]] += amount;
        }
    }

    /// @notice EIP-2612 permit signed as the owner, then transferFrom by this handler.
    function permitAndTransfer(uint256 sel, uint256 amountDesired, uint256 deadlineSkew) external {
        uint256 fromIdx = sel % N;
        uint256 toIdx = (sel / 8) % N;
        if (toIdx == fromIdx) toIdx = (toIdx + 1) % N;
        address from = actors[fromIdx];
        uint256 bal = mirror[from];
        if (bal == 0) return;
        uint256 amount = amountDesired % (bal + 1);
        if (amount == 0) return;

        uint256 deadline = block.timestamp + (deadlineSkew % (24 hours)) + 60;
        uint256 nonce = token.nonces(from);
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, from, address(this), amount, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(keys[fromIdx], digest);
        token.permit(from, address(this), amount, deadline, v, r, s);

        bool ok = token.transferFrom(from, actors[toIdx], amount);
        if (ok) {
            mirror[from] = bal - amount;
            mirror[actors[toIdx]] += amount;
        }
    }
}

/// @notice Invariant suite for PennyToken: constitutional fixed-supply facts over a bounded walk.
contract InvariantPennyTokenTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000e18;

    PennyToken internal token;
    PennyTokenHandler internal handler;

    function setUp() public {
        token = new PennyToken(SUPPLY, vm.addr(0x1001));
        handler = new PennyTokenHandler(token);
        targetContract(address(handler));
    }

    /// @dev totalSupply must be constant across any sequence of transfers/permits/mints.
    function invariant_totalSupply_is_constant() external view {
        assertEq(token.totalSupply(), SUPPLY, "totalSupply drifted");
    }

    /// @dev The zero address can never be funded or debited to a negative balance.
    function invariant_zero_address_is_never_used() external view {
        assertEq(token.balanceOf(address(0)), 0, "zero address received PENNY");
    }

    /// @dev Balances of every tracked actor match the handler ledger (equivalently: non-movers
    ///      are untouched and the token's balances conserve to exactly totalSupply).
    function invariant_balances_match_handler_ledger() external view {
        uint256 sum;
        for (uint256 i = 0; i < 5; i++) {
            address a = vm.addr(0x1001 + i);
            uint256 bal = token.balanceOf(a);
            uint256 mir = handler.mirror(a);
            assertEq(bal, mir, "token balance diverged from handler ledger");
            sum += mir;
        }
        assertEq(sum, SUPPLY, "ledger conservation broken");
    }
}
