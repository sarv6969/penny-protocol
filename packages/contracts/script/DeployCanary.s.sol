// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";

import {PennyToken} from "../src/token/PennyToken.sol";
import {PennyFeeHook} from "../src/hooks/PennyFeeHook.sol";
import {PennyFeeHookFactory} from "../src/hooks/PennyFeeHookFactory.sol";
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

/// @title DeployCanary — $PONEY canary deployment on Robinhood Chain (D038)
/// @notice CANARY: an explicitly-labelled test deployment of the full Penny Stocks rail with a
///         narrow basket (constituents limited to those with executable routes inside the
///         oracle-deviation cap). NOT the production $PENNY launch: supply, basket size, and
///         cadence are canary values, and the token is named/tickered as a test asset.
///
/// Order (each step depends on the previous):
///   1. PONEY token (fixed supply -> deployer, who seeds the pool and keeps the rest)
///   2. CREATE2-mined fee hook bound to the PONEY/WETH PoolKey
///   3. FeeCollector  <- hook streams the 3% WETH fee here
///   4. ChainlinkOracle (real feeds) -> OracleGuard (session gate, fail-closed)
///   5. StockTokenVerifier -> RebalanceController (canary basket)
///   6. RouteAdapter (whitelisted routers, keeper-staged routes)
///   7. BasketBuyer  <- collector sweeps into it; buys via adapter under oracle floor
///   8. RewardVault  <- buyer delivers custody; EligibilityRegistry + RewardDistributor
///   9. Wire set-once latches, roles, and pool initialization
///
/// Env (all required — no defaults, nothing invented):
///   RPC_URL, PRIVATE_KEY (deployer; canary only — never a production treasury key)
///   WETH_ADDRESS, V4_POOL_MANAGER, POOL_FEE, POOL_TICK_SPACING, POOL_SQRT_PRICE_X96
///   FEED_ETH_USD, CANARY_TOKENS (comma-sep), CANARY_FEEDS (comma-sep, same order)
///   LIFI_ROUTER, KEEPER_ADDRESS, ATTESTATION_SIGNER
///   PONEY_SUPPLY, MIN_SWEEP_WEI, MAX_SLIPPAGE_BPS, CHALLENGE_DELAY_SECONDS
///   STOCK_STALENESS_SECONDS, ETH_STALENESS_SECONDS, REBALANCE_TIMELOCK_SECONDS
contract DeployCanaryScript is Script {
    struct Deployed {
        address token;
        address hook;
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

    struct Cfg {
        address weth;
        IPoolManager pm;
        uint24 poolFee;
        int24 tickSpacing;
        address[] tokens;
        address[] feeds;
        address keeper;
        address deployer;
    }

    function _cfg() internal view returns (Cfg memory c) {
        c.weth = vm.envAddress("WETH_ADDRESS");
        c.pm = IPoolManager(vm.envAddress("V4_POOL_MANAGER"));
        c.poolFee = uint24(vm.envUint("POOL_FEE"));
        c.tickSpacing = int24(int256(vm.envUint("POOL_TICK_SPACING")));
        c.tokens = vm.envAddress("CANARY_TOKENS", ",");
        c.feeds = vm.envAddress("CANARY_FEEDS", ",");
        c.keeper = vm.envAddress("KEEPER_ADDRESS");
        c.deployer = vm.addr(vm.envUint("PRIVATE_KEY"));
        require(c.tokens.length == c.feeds.length && c.tokens.length > 0, "CANARY: token/feed mismatch");
    }

    function run() external {
        Cfg memory c = _cfg();
        Deployed memory d;

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        d = _deployCore(c);
        _deployRewards(c, d);
        _initPool(c, d);
        vm.stopBroadcast();

        _report(d, c.weth < d.token, c.tokens);
    }

    /// @dev token -> hook -> collector -> oracle/guard -> basket policy -> adapter -> buyer
    function _deployCore(Cfg memory c) internal returns (Deployed memory d) {
        d.token = address(new PennyToken(vm.envUint("PONEY_SUPPLY"), c.deployer));

        PennyFeeHookFactory factory = new PennyFeeHookFactory();
        (PennyFeeHook hook,) = factory.deployHook(c.pm, c.deployer, d.token, c.weth, c.poolFee, c.tickSpacing);
        d.hook = address(hook);

        FeeCollector collector = new FeeCollector(c.deployer, IERC20(c.weth));
        d.collector = address(collector);
        hook.setFeeCollector(d.collector);

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
        uint48 stockBound = uint48(vm.envUint("STOCK_STALENESS_SECONDS"));
        for (uint256 i = 0; i < c.tokens.length; i++) {
            oracle.setFeed(c.tokens[i], IAggregatorV3(c.feeds[i]), stockBound, true);
        }
        return address(oracle);
    }

    /// @dev vault -> registry -> distributor, with every set-once latch wired here.
    function _deployRewards(Cfg memory c, Deployed memory d) internal {
        RewardVault vault = new RewardVault(c.deployer, IERC20(c.weth), IERC20(d.token));
        vault.setRewardSource(d.buyer);
        BasketBuyer(d.buyer).setRewardVault(IRewardVault(address(vault)));
        d.vault = address(vault);

        EligibilityRegistry registry = new EligibilityRegistry(c.deployer, IERC20(d.token));
        registry.setAttestationSigner(vm.envAddress("ATTESTATION_SIGNER"));
        d.registry = address(registry);

        RewardDistributor distributor = new RewardDistributor(c.deployer, vault, registry, uint64(vm.envUint("CHALLENGE_DELAY_SECONDS")));
        vault.setDistributor(address(distributor));
        distributor.grantRole(distributor.DISTRIBUTOR_ROLE(), c.keeper);
        distributor.grantRole(distributor.ROOT_CANCEL_ROLE(), c.deployer);
        d.distributor = address(distributor);
    }

    function _initPool(Cfg memory c, Deployed memory d) internal {
        bool wethIs0 = c.weth < d.token;
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(wethIs0 ? c.weth : d.token),
            currency1: Currency.wrap(wethIs0 ? d.token : c.weth),
            fee: c.poolFee,
            tickSpacing: c.tickSpacing,
            hooks: IHooks(d.hook)
        });
        c.pm.initialize(key, uint160(vm.envUint("POOL_SQRT_PRICE_X96")));
    }

    function _report(Deployed memory d, bool wethIs0, address[] memory tokens) internal pure {
        console2.log("=== $PONEY CANARY DEPLOYED (test asset, not production PENNY) ===");
        console2.log("PONEY token       ", d.token);
        console2.log("PennyFeeHook      ", d.hook);
        console2.log("FeeCollector      ", d.collector);
        console2.log("ChainlinkOracle   ", d.oracle);
        console2.log("OracleGuard       ", d.guard);
        console2.log("StockTokenVerifier", d.verifier);
        console2.log("RebalanceController", d.rebalance);
        console2.log("RouteAdapter      ", d.adapter);
        console2.log("BasketBuyer       ", d.buyer);
        console2.log("RewardVault       ", d.vault);
        console2.log("EligibilityReg    ", d.registry);
        console2.log("RewardDistributor ", d.distributor);
        console2.log("WETH is currency0 ", wethIs0);
        console2.log("basket size       ", tokens.length);
        console2.log("NOTE: market session is CLOSED until setMarketOpen(true) (D009 staffed gate)");
        console2.log("NOTE: liquidity must be added via PositionManager before swaps can route");
    }
}
