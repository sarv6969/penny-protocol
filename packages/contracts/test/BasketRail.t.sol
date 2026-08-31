// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockStockToken} from "./mocks/MockStockToken.sol";
import {MockOracle} from "./mocks/MockOracle.sol";
import {MockAdapter} from "./mocks/MockAdapter.sol";
import {MockRewardVault} from "./mocks/MockRewardVault.sol";
import {StockTokenVerifier} from "../src/governance/StockTokenVerifier.sol";
import {RebalanceController} from "../src/governance/RebalanceController.sol";
import {OracleGuard} from "../src/basket/OracleGuard.sol";
import {BasketBuyer} from "../src/basket/BasketBuyer.sol";
import {FeeCollector} from "../src/fees/FeeCollector.sol";
import {IBasketBuyer} from "../src/basket/IBasketBuyer.sol";

/// @notice Phase 6 rail tests: hook-side fee WETH -> FeeCollector -> BasketBuyer ->
///         5-way equal-notional Stock Token purchase -> RewardVault. Oracle rail is a
///         clearly-labelled mock; production feeds are a blocked launch gate.
contract BasketRailTest is Test {
    MockERC20 weth;
    MockStockToken[5] tok;
    MockOracle oracle;
    MockAdapter adapter;
    MockRewardVault vault;
    StockTokenVerifier verifier;
    RebalanceController rebalance;
    OracleGuard guard;
    BasketBuyer buyer;
    FeeCollector collector;

    uint256 constant AMOUNT = 100 ether;

    address user = address(0xBEEF);
    address owner = address(this);

    function setUp() public {
        weth = new MockERC20("Wrapped Ether", "WETH");

        string[5] memory syms = ["AAPL", "MSFT", "NVDA", "TSLA", "AMZN"];
        string[5] memory names = ["Apple", "Microsoft", "Nvidia", "Tesla", "Amazon"];
        address[] memory founding = new address[](5);
        for (uint256 i = 0; i < 5; i++) {
            tok[i] = new MockStockToken(syms[i], names[i]);
            founding[i] = address(tok[i]);
        }

        verifier = new StockTokenVerifier(address(this));
        rebalance = new RebalanceController(founding, verifier, 7 days);

        oracle = new MockOracle();
        for (uint256 i = 0; i < 5; i++) {
            oracle.register(address(tok[i]), 1e18, true);
        }
        oracle.register(address(weth), 1e18, true);

        guard = new OracleGuard(address(this), oracle, address(weth));
        guard.grantRole(guard.MARKET_APPROVER_ROLE(), address(this));
        guard.setMarketOpen(true);

        buyer = new BasketBuyer(address(this), IERC20(address(weth)), guard, rebalance);
        adapter = new MockAdapter(weth);
        vault = new MockRewardVault();
        buyer.setAdapter(adapter);
        buyer.setRewardVault(vault);

        collector = new FeeCollector(address(this), IERC20(address(weth)));
        collector.setBasketBuyer(IBasketBuyer(address(buyer)));
        collector.setMinSweepAmount(0);
    }

    // ------------------------------------------------------------------ happy path

    function test_SweepBuysEqualNotionalBasket() public {
        // Hook streams the 3% fee as WETH straight into the collector.
        weth.mint(address(collector), AMOUNT);

        uint256 share = AMOUNT / 5;
        vm.expectEmit(true, true, false, true);
        emit BasketBuyer.PurchaseExecuted(address(tok[0]), share, 1e18, share, (share * 9_900) / 10_000);

        uint256 spent = collector.sweep();

        assertEq(spent, AMOUNT, "basket spend");
        assertEq(weth.balanceOf(address(collector)), 0, "collector drained");
        assertEq(weth.balanceOf(address(buyer)), 0, "buyer drained");
        for (uint256 i = 0; i < 5; i++) {
            assertEq(vault.holdings(address(tok[i])), AMOUNT / 5, "equal share");
        }
    }

    function test_DustConvergesDeterministically() public {
        uint256 amount = 100 ether + 7;
        weth.mint(address(collector), amount);
        collector.sweep();

        // Largest-remainder tie-break (lower index wins): floor spend is 20e18+1 for every
        // token (weight 2000 floor leaves residue 4000), and the two remaining wei go to the
        // two smallest indices -> tok0/tok1 hold 20e18+2, the rest 20e18+1.
        assertEq(vault.holdings(address(tok[0])), 20 ether + 2);
        assertEq(vault.holdings(address(tok[1])), 20 ether + 2);
        for (uint256 i = 2; i < 5; i++) {
            assertEq(vault.holdings(address(tok[i])), 20 ether + 1);
        }
        assertEq(weth.balanceOf(address(buyer)), 0, "every whole wei spent");
    }

    // ------------------------------------------------------------------ fail-closed oracle rail

    function test_MarketClosedAbortsWholeSweep() public {
        guard.setMarketOpen(false);
        weth.mint(address(collector), AMOUNT);
        vm.expectRevert(OracleGuard.MarketClosed.selector);
        collector.sweep();
        assertEq(weth.balanceOf(address(collector)), AMOUNT, "atomic rollback");
    }

    function test_NonLiveFeedAbortsWholeSweep() public {
        oracle.setLive(address(tok[2]), false);
        weth.mint(address(collector), AMOUNT);
        vm.expectRevert(OracleGuard.OracleFailClosed.selector);
        collector.sweep();
        assertEq(weth.balanceOf(address(buyer)), 0, "no partial purchase");
    }

    function test_ZeroPriceFeedReverts() public {
        oracle.setPrice(address(tok[1]), 0);
        weth.mint(address(collector), AMOUNT);
        vm.expectRevert(OracleGuard.ZeroPrice.selector);
        collector.sweep();
    }

    // ------------------------------------------------------------------ venue slippage

    function test_AdversePriceMovesAbortPurchase() public {
        oracle.setPrice(address(tok[0]), 5e17); // token worth $0.50 -> need 2x spend -> over slip
        weth.mint(address(collector), AMOUNT);
        vm.expectRevert(MockAdapter.SlippageExceeded.selector);
        collector.sweep();
        assertEq(weth.balanceOf(address(collector)), AMOUNT, "atomic rollback");
    }

    function test_SlippageCapEnforced() public {
        vm.expectRevert(BasketBuyer.SlippageCapOutOfRange.selector);
        buyer.setMaxSlippageBps(6_000);
    }

    // ------------------------------------------------------------------ wiring guards

    function test_UnsetAdapterReverts() public {
        BasketBuyer b = new BasketBuyer(address(this), IERC20(address(weth)), guard, rebalance);
        b.setRewardVault(vault);
        weth.mint(address(b), AMOUNT);
        vm.expectRevert(BasketBuyer.UnsetAdapter.selector);
        b.purchaseBasket();
    }

    function test_UnsetRewardVaultReverts() public {
        BasketBuyer b = new BasketBuyer(address(this), IERC20(address(weth)), guard, rebalance);
        b.setAdapter(adapter);
        weth.mint(address(b), AMOUNT);
        vm.expectRevert(BasketBuyer.UnsetRewardVault.selector);
        b.purchaseBasket();
    }

    function test_ZeroBalanceReverts() public {
        vm.expectRevert(BasketBuyer.ZeroBalance.selector);
        buyer.purchaseBasket();
    }

    // ------------------------------------------------------------------ FeeCollector knobs

    function test_SweepBelowThresholdReverts() public {
        collector.setMinSweepAmount(50 ether);
        weth.mint(address(collector), 1 ether);
        vm.expectRevert(FeeCollector.BelowSweepThreshold.selector);
        collector.sweep();
    }

    function test_SweepsPausedReverts() public {
        collector.setSweepsPaused(true);
        weth.mint(address(collector), AMOUNT);
        vm.expectRevert(FeeCollector.SweepsPaused.selector);
        collector.sweep();
    }

    function test_FeeCollectorSettersAreOwnerOnly() public {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        collector.setBasketBuyer(IBasketBuyer(address(0xB0B)));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        collector.setMinSweepAmount(1);
        vm.stopPrank();
    }

    // ------------------------------------------------------------------ OracleGuard

    function test_OracleGuardReads() public view {
        assertEq(guard.getPriceWad(address(tok[0])), 1e18);
        assertEq(guard.getWethPriceWad(), 1e18);
    }

    function test_MarketOpenRequiresApproverRole() public {
        guard.setMarketOpen(false);
        bytes32 role = guard.MARKET_APPROVER_ROLE();
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")), user, role));
        guard.setMarketOpen(true);
        assertFalse(guard.marketOpen());
    }
}
