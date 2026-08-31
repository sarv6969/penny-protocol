// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PennyFeeHook} from "./PennyFeeHook.sol";

/// @title PennyFeeHookFactory — CREATE2 miner for PennyFeeHook
/// @notice Deploys PennyFeeHook via CREATE2 to an address whose low 14 bits encode exactly the
/// hook's enabled flags, as required by Uniswap v4 (bit 7 beforeSwap, bit 6 afterSwap,
/// bit 3 beforeSwapReturnDelta, bit 2 afterSwapReturnDelta).
contract PennyFeeHookFactory {
    uint160 internal constant HOOK_MASK = (uint160(1) << 14) - 1;
    uint160 internal constant EXPECTED_FLAGS =
        Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG;

    error NoValidSaltFound();

    function deployHook(IPoolManager manager, address initialOwner, address penny, address weth, uint24 fee, int24 tickSpacing)
        external
        returns (PennyFeeHook hook, bytes32 salt)
    {
        bytes32 bytecodeHash = keccak256(
            abi.encodePacked(type(PennyFeeHook).creationCode, abi.encode(manager, initialOwner, penny, weth, fee, tickSpacing))
        );

        for (uint256 i = 0; i < (1 << 18); ++i) {
            salt = bytes32(i);
            address predicted = _computeCreate2Address(salt, bytecodeHash);
            if (uint160(predicted) & HOOK_MASK == EXPECTED_FLAGS) {
                hook = new PennyFeeHook{salt: salt}(manager, initialOwner, penny, weth, fee, tickSpacing);
                if (address(hook) != predicted) revert NoValidSaltFound();
                return (hook, salt);
            }
        }
        revert NoValidSaltFound();
    }

    function _computeCreate2Address(bytes32 salt, bytes32 bytecodeHash) internal view returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, bytecodeHash)))));
    }
}
