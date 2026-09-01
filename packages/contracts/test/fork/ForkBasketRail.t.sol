// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ChainlinkOracle, IAggregatorV3} from "../../src/basket/ChainlinkOracle.sol";
import {OracleGuard} from "../../src/basket/OracleGuard.sol";
import {RouteAdapter} from "../../src/basket/RouteAdapter.sol";
import {BasketBuyer} from "../../src/basket/BasketBuyer.sol";
import {FeeCollector} from "../../src/fees/FeeCollector.sol";
import {RewardVault} from "../../src/rewards/RewardVault.sol";
import {RebalanceController} from "../../src/governance/RebalanceController.sol";
import {StockTokenVerifier} from "../../src/governance/StockTokenVerifier.sol";
import {IBasketBuyer} from "../../src/basket/IBasketBuyer.sol";

/// @notice Robinhood Chain MAINNET FORK test (D036/D037): the production oracle reads the real
///         Chainlink proxies, the guard gates them, and the full canary rail executes a real
///         3-stock equal-notional purchase against real Stock Token contracts. The venue leg is
///         a fork-funded counterparty filling at the REAL oracle price (labelled: routes on
///         mainnet come from LiFi/Uniswap staged by the keeper — the venue's fill quality is
///         exactly what the adapter's minOut enforces).
///
///         Run: FORK=1 forge test --match-contract ForkBasketRail --fork-url $MAINNET_RPC_URL
contract ForkBasketRailTest is Test {
    // --- real mainnet addresses (verified in the manifest at pinned blocks) ---
    address constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    address constant USAR = 0xd917B029C761D264c6A312BBbcDA868658eF86a6;
    address constant RKLB = 0x3b14C39E89D60D627b42a1A4CA45b5bb45Fc12e2;
    address constant RGTI = 0x284358abc07F9359f19f4b5b4aC91901Be2597Ba;
    address constant FEED_ETH = 0x78F3556b67E17Df817D51Ef5a990cDaF09E8d3A9;
    address constant FEED_USAR = 0xA994d3684e8400A6c8078226925779FdeE682DD9;
    address constant FEED_RKLB = 0x045477BF65Aef6f4F2386ad0164579e48381CC74;
    address constant FEED_RGTI = 0x2A045cF1C49c61c166C036d2f06FA2D2d984f765;

    ChainlinkOracle oracle;
    OracleGuard guard;
    RouteAdapter adapter;
    BasketBuyer buyer;
    FeeCollector collector;
    RewardVault vault;
    RebalanceController rebalance;

    ForkFiller filler;
    address keeper = makeAddr("keeper");

    modifier onlyFork() {
        if (vm.envOr("FORK", uint256(0)) == 0) {
            emit log("skipped: set FORK=1 and --fork-url to run");
            return;
        }
        _;
    }

    function setUp() public {
        if (vm.envOr("FORK", uint256(0)) == 0) return;
        require(block.chainid == 4663, "must fork Robinhood Chain mainnet");

        // production oracle on the REAL feeds
        oracle = new ChainlinkOracle(address(this));
        oracle.setFeed(WETH, IAggregatorV3(FEED_ETH), 26 hours, false);
        oracle.setFeed(USAR, IAggregatorV3(FEED_USAR), 4 days, true);
        oracle.setFeed(RKLB, IAggregatorV3(FEED_RKLB), 4 days, true);
        oracle.setFeed(RGTI, IAggregatorV3(FEED_RGTI), 4 days, true);

        guard = new OracleGuard(address(this), oracle, WETH);
        guard.grantRole(guard.MARKET_APPROVER_ROLE(), address(this));
        guard.setMarketOpen(true);

        StockTokenVerifier verifier = new StockTokenVerifier(address(this));
        address[] memory founding = new address[](3);
        founding[0] = USAR;
        founding[1] = RKLB;
        founding[2] = RGTI;
        rebalance = new RebalanceController(founding, verifier, 7 days);

        buyer = new BasketBuyer(address(this), IERC20(WETH), guard, rebalance);
        adapter = new RouteAdapter(address(this), IERC20(WETH));
        adapter.setBuyer(address(buyer));
        adapter.setKeeperAllowed(keeper, true);
        buyer.setAdapter(adapter);

        vault = new RewardVault(
            address(this),
            IERC20(WETH),
            IERC20(WETH) /*no penny on fork*/
        );
        vault.setRewardSource(address(buyer));
        buyer.setRewardVault(vault);

        collector = new FeeCollector(address(this), IERC20(WETH));
        collector.setBasketBuyer(IBasketBuyer(address(buyer)));

        // fork-only fill counterparty holding real Stock Tokens at real oracle prices
        filler = new ForkFiller(IERC20(WETH), oracle);
        adapter.setRouterAllowed(address(filler), true);
        deal(USAR, address(filler), 1_000e18);
        deal(RKLB, address(filler), 1_000e18);
        deal(RGTI, address(filler), 1_000e18);
    }

    function test_RealFeedsAreLiveAndSane() public onlyFork {
        assertTrue(oracle.isLive(WETH), "ETH/USD live");
        assertTrue(oracle.isLive(USAR), "USAR live");
        assertTrue(oracle.isLive(RKLB), "RKLB live");
        assertTrue(oracle.isLive(RGTI), "RGTI live");

        uint256 eth = oracle.priceOf(WETH);
        uint256 usar = oracle.priceOf(USAR);
        emit log_named_decimal_uint("ETH/USD", eth, 18);
        emit log_named_decimal_uint("USAR/USD", usar, 18);
        assertGt(eth, 100e18, "ETH price sane floor");
        assertLt(eth, 100_000e18, "ETH price sane ceiling");
        assertGt(usar, 1e18, "USAR sane floor");
        assertLt(usar, 1_000e18, "USAR sane ceiling");
    }

    function test_FullRail_FeeToVault_ThreeStock_EqualNotional() public onlyFork {
        // 1. simulate hook fee accrual: 0.03 WETH lands on the collector
        deal(WETH, address(collector), 0.03e18);

        // 2. keeper stages one route per constituent (fork filler = venue at oracle price)
        address[3] memory toks = [USAR, RKLB, RGTI];
        for (uint256 i = 0; i < 3; i++) {
            bytes memory data = abi.encodeCall(ForkFiller.fill, (toks[i], address(buyer)));
            vm.prank(keeper);
            adapter.stageRoute(toks[i], address(filler), data, uint64(block.timestamp) + 180);
        }

        // 3. sweep -> equal-notional purchase -> vault custody
        uint256 spent = collector.sweep();
        assertEq(spent, 0.03e18, "full fee spent");
        assertEq(IERC20(WETH).balanceOf(address(collector)), 0, "collector drained");
        assertEq(IERC20(WETH).balanceOf(address(buyer)), 0, "buyer drained");

        uint256 wethUsd = oracle.priceOf(WETH);
        for (uint256 i = 0; i < 3; i++) {
            uint256 got = IERC20(toks[i]).balanceOf(address(vault));
            uint256 px = oracle.priceOf(toks[i]);
            uint256 usd = (got * px) / 1e18;
            emit log_named_decimal_uint(string.concat("vault USD value leg ", vm.toString(i)), usd, 18);
            // each leg ~ (0.01 WETH * ETHUSD); allow the buyer's 1% slippage cap
            uint256 target = (0.01e18 * wethUsd) / 1e18;
            assertGe(usd, (target * 9_890) / 10_000, "leg >= 98.9% of equal-notional target");
            assertLe(usd, (target * 10_010) / 10_000, "leg <= 100.1% of target");
            assertEq(vault.lifetimeDeposits(toks[i]), got, "record == custody");
        }
    }

    function test_StaleRouteBlocksPurchaseAtomically() public onlyFork {
        deal(WETH, address(collector), 0.03e18);
        // stage only two of three routes -> third leg has NoRoute -> whole sweep reverts
        bytes memory d0 = abi.encodeCall(ForkFiller.fill, (USAR, address(buyer)));
        bytes memory d1 = abi.encodeCall(ForkFiller.fill, (RKLB, address(buyer)));
        vm.startPrank(keeper);
        adapter.stageRoute(USAR, address(filler), d0, uint64(block.timestamp) + 180);
        adapter.stageRoute(RKLB, address(filler), d1, uint64(block.timestamp) + 180);
        vm.stopPrank();

        vm.expectRevert(RouteAdapter.NoRoute.selector);
        collector.sweep();
        assertEq(IERC20(WETH).balanceOf(address(collector)), 0.03e18, "atomic rollback");
        assertEq(IERC20(USAR).balanceOf(address(vault)), 0, "no partial basket");
    }
}

/// @notice Fork-only venue: fills WETH->token at the CURRENT REAL oracle price (no spread).
///         Explicitly a stand-in for the LiFi/Uniswap route calldata staged on live mainnet.
contract ForkFiller {
    IERC20 immutable weth;
    ChainlinkOracle immutable oracle;

    constructor(IERC20 weth_, ChainlinkOracle oracle_) {
        weth = weth_;
        oracle = oracle_;
    }

    function fill(address token, address recipient) external {
        uint256 wethIn = weth.allowance(msg.sender, address(this));
        require(weth.transferFrom(msg.sender, address(this), wethIn), "filler: pull");
        uint256 usd = (wethIn * oracle.priceOf(address(weth))) / 1e18;
        uint256 out = (usd * 1e18) / oracle.priceOf(token);
        require(IERC20(token).transfer(recipient, out), "filler: pay");
    }
}
