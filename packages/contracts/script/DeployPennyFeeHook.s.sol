// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PennyFeeHook} from "../src/hooks/PennyFeeHook.sol";
import {PennyFeeHookFactory} from "../src/hooks/PennyFeeHookFactory.sol";

/// @notice Deployment script for PennyFeeHook (CREATE2-mined so the address bits encode the hooks).
/// Env: V4_POOL_MANAGER, PENNY_TOKEN, WETH_ADDRESS, POOL_FEE, POOL_TICK_SPACING,
///      PROTOCOL_OWNER (initial owner -> SET_FEE_COLLECTOR later), PRIVATE_KEY.
/// Dry-run with: forge script script/DeployPennyFeeHook.s.sol:DeployPennyFeeHookScript --rpc-url ...
contract DeployPennyFeeHookScript is Script {
    function run() external {
        IPoolManager poolManager = IPoolManager(vm.envAddress("V4_POOL_MANAGER"));
        address penny = vm.envAddress("PENNY_TOKEN");
        address weth = vm.envAddress("WETH_ADDRESS");
        uint24 fee = uint24(vm.envUint("POOL_FEE"));
        int24 tickSpacing = int24(int256(vm.envUint("POOL_TICK_SPACING")));
        address owner = vm.envAddress("PROTOCOL_OWNER");

        vm.startBroadcast();
        PennyFeeHookFactory factory = new PennyFeeHookFactory();
        (PennyFeeHook hook, bytes32 salt) = factory.deployHook(poolManager, owner, penny, weth, fee, tickSpacing);
        vm.stopBroadcast();

        console2.log("factory", address(factory));
        console2.log("hook", address(hook));
        console2.log("hook flag bits", uint256(uint160(address(hook)) & ((uint160(1) << 14) - 1)));
        console2.log("salt", vm.toString(salt));
        console2.log("feeCollector", hook.feeCollector());
    }
}
