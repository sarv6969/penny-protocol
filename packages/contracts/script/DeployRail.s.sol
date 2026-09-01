// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IWETH9} from "../src/interfaces/IWETH9.sol";
import {FeeCollector} from "../src/fees/FeeCollector.sol";
import {ChainlinkOracle, IAggregatorV3} from "../src/basket/ChainlinkOracle.sol";
import {OracleGuard} from "../src/basket/OracleGuard.sol";
import {RouteAdapter} from "../src/basket/RouteAdapter.sol";
import {BasketBuyer} from "../src/basket/BasketBuyer.sol";
import {RewardVault} from "../src/rewards/RewardVault.sol";
import {RewardDistributor} from "../src/rewards/RewardDistributor.sol";
import {EligibilityRegistry} from "../src/rewards/EligibilityRegistry.sol";
import {RebalanceController} from "../src/governance/RebalanceController.sol";
import {StockTokenVerifier} from "../src/governance/StockTokenVerifier.sol";
import {IBasketBuyer} from "../src/basket/IBasketBuyer.sol";
import {IRewardVault} from "../src/basket/IRewardVault.sol";
import {ILiquidityAdapter} from "../src/basket/ILiquidityAdapter.sol";

/// @title DeployRail — the buy-and-distribute rail for a pons-launched token (D039)
/// @notice The TOKEN is not deployed here: it is launched on pons v2, which mints the supply,
///         runs the bonding curve, charges the creator tax, and permanently locks the graduated
///         Uniswap v4 pool. This script deploys only the machinery that turns forwarded fee
///         proceeds into penny-stock rewards for holders:
///
///           operator forwards pons creator-tax ETH -> FeeCollector (public deposit address)
///             -> BasketBuyer (equal-notional, Chainlink-priced, oracle floor enforced)
///               -> RewardVault (no admin can sweep)
///                 -> RewardDistributor (pro-rata Merkle, auto-delivery to opted-in holders)
///
/// Env:
///   PRIVATE_KEY, WETH_ADDRESS, PONS_TOKEN (the launched token, for eligibility balances)
///   FEED_ETH_USD, BASKET_TOKENS (csv), BASKET_FEEDS (csv, same order)
///   LIFI_ROUTER, KEEPER_ADDRESS, ATTESTATION_SIGNER
///   MIN_SWEEP_WEI, MAX_SLIPPAGE_BPS, CHALLENGE_DELAY_SECONDS
///   STOCK_STALENESS_SECONDS, ETH_STALENESS_SECONDS, REBALANCE_TIMELOCK_SECONDS
contract DeployRailScript is Script {
    struct Cfg {
        address weth;
        address ponsToken;
        address[] tokens;
        address[] feeds;
        address keeper;
        address deployer;
    }

    struct Deployed {
        address collector;
        address oracle;
        address guard;
        address verifier;
        address rebalance;
        address adapter;
        address buyer;
        address vault;
        address registry;
        address distributor;
    }

    function _cfg() internal view returns (Cfg memory c) {
        c.weth = vm.envAddress("WETH_ADDRESS");
        c.ponsToken = vm.envAddress("PONS_TOKEN");
        c.tokens = vm.envAddress("BASKET_TOKENS", ",");
        c.feeds = vm.envAddress("BASKET_FEEDS", ",");
        c.keeper = vm.envAddress("KEEPER_ADDRESS");
        c.deployer = vm.addr(vm.envUint("PRIVATE_KEY"));
        require(c.tokens.length == c.feeds.length && c.tokens.length > 0, "RAIL: token/feed mismatch");
        require(c.ponsToken != address(0), "RAIL: pons token required");
    }

    function run() external {
        Cfg memory c = _cfg();
        Deployed memory d;

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        d = _deployBuySide(c);
        _deployRewardSide(c, d);
        vm.stopBroadcast();

        _report(c, d);
    }

    /// @dev collector -> oracle/guard -> basket policy -> adapter -> buyer
    function _deployBuySide(Cfg memory c) internal returns (Deployed memory d) {
        FeeCollector collector = new FeeCollector(c.deployer, IWETH9(c.weth));
        d.collector = address(collector);

        d.oracle = _deployOracle(c);
        OracleGuard guard = new OracleGuard(c.deployer, ChainlinkOracle(d.oracle), c.weth);
        guard.grantRole(guard.MARKET_APPROVER_ROLE(), c.deployer);
        d.guard = address(guard);

        StockTokenVerifier verifier = new StockTokenVerifier(c.deployer);
        d.verifier = address(verifier);
        d.rebalance = address(new RebalanceController(c.tokens, verifier, vm.envUint("REBALANCE_TIMELOCK_SECONDS")));

        RouteAdapter adapter = new RouteAdapter(c.deployer, IERC20(c.weth));
        adapter.setRouterAllowed(vm.envAddress("LIFI_ROUTER"), true);
        adapter.setKeeperAllowed(c.keeper, true);
        d.adapter = address(adapter);

        BasketBuyer buyer = new BasketBuyer(c.deployer, IERC20(c.weth), guard, RebalanceController(d.rebalance));
        buyer.setMaxSlippageBps(vm.envUint("MAX_SLIPPAGE_BPS"));
        buyer.setAdapter(ILiquidityAdapter(d.adapter));
        d.buyer = address(buyer);
        adapter.setBuyer(d.buyer);

        collector.setBasketBuyer(IBasketBuyer(d.buyer));
        collector.setMinSweepAmount(vm.envUint("MIN_SWEEP_WEI"));
    }

    function _deployOracle(Cfg memory c) internal returns (address) {
        ChainlinkOracle oracle = new ChainlinkOracle(c.deployer);
        oracle.setFeed(c.weth, IAggregatorV3(vm.envAddress("FEED_ETH_USD")), uint48(vm.envUint("ETH_STALENESS_SECONDS")), false);
        uint48 bound = uint48(vm.envUint("STOCK_STALENESS_SECONDS"));
        for (uint256 i = 0; i < c.tokens.length; i++) {
            oracle.setFeed(c.tokens[i], IAggregatorV3(c.feeds[i]), bound, true);
        }
        return address(oracle);
    }

    /// @dev vault -> registry (reads the PONS token for holder eligibility) -> distributor
    function _deployRewardSide(Cfg memory c, Deployed memory d) internal {
        RewardVault vault = new RewardVault(c.deployer, IERC20(c.weth), IERC20(c.ponsToken));
        vault.setRewardSource(d.buyer);
        BasketBuyer(d.buyer).setRewardVault(IRewardVault(address(vault)));
        d.vault = address(vault);

        EligibilityRegistry registry = new EligibilityRegistry(c.deployer, IERC20(c.ponsToken));
        registry.setAttestationSigner(vm.envAddress("ATTESTATION_SIGNER"));
        d.registry = address(registry);

        RewardDistributor distributor = new RewardDistributor(c.deployer, vault, registry, uint64(vm.envUint("CHALLENGE_DELAY_SECONDS")));
        vault.setDistributor(address(distributor));
        distributor.grantRole(distributor.DISTRIBUTOR_ROLE(), c.keeper);
        distributor.grantRole(distributor.ROOT_CANCEL_ROLE(), c.deployer);
        d.distributor = address(distributor);
    }

    function _report(Cfg memory c, Deployed memory d) internal pure {
        console2.log("=== PENNY STOCKS RAIL DEPLOYED (token lives on pons v2) ===");
        console2.log("pons token (eligibility) ", c.ponsToken);
        console2.log("FeeCollector <- SEND FEES", d.collector);
        console2.log("ChainlinkOracle          ", d.oracle);
        console2.log("OracleGuard              ", d.guard);
        console2.log("StockTokenVerifier       ", d.verifier);
        console2.log("RebalanceController      ", d.rebalance);
        console2.log("RouteAdapter             ", d.adapter);
        console2.log("BasketBuyer              ", d.buyer);
        console2.log("RewardVault              ", d.vault);
        console2.log("EligibilityRegistry      ", d.registry);
        console2.log("RewardDistributor        ", d.distributor);
        console2.log("basket size              ", c.tokens.length);
        console2.log("NEXT: send pons creator-tax ETH to the FeeCollector above");
        console2.log("NEXT: market session CLOSED until setMarketOpen(true) (D009)");
    }
}
