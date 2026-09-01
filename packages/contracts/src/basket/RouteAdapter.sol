// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ILiquidityAdapter} from "./ILiquidityAdapter.sol";

/// @title RouteAdapter — venue-agnostic execution adapter for basket purchases (D037)
/// @notice Executes keeper-staged swap routes (LiFi Diamond, Uniswap router, or any future
///         venue) under hard onchain guarantees that make a bad or malicious route physically
///         unable to steal:
///
///         1. WHITELISTED ROUTERS ONLY — routes can only call routers the owner registered
///            (timelocked Safe on mainnet). Arbitrary-call is impossible.
///         2. ORACLE-FLOOR ENFORCEMENT LIVES IN BasketBuyer — the buyer computes minTokenOut
///            from Chainlink and this adapter additionally re-checks the realized balance
///            delta against it. A route that underdelivers reverts the whole purchase.
///         3. EXACT-INPUT CUSTODY — the adapter pulls exactly `wethAmount`, grants the router
///            an exact allowance, and revokes it after. Router never gets standing approval.
///         4. BALANCE-DELTA ACCOUNTING — amountOut is measured as the recipient's real balance
///            delta, never trusted from the route's return data.
///         5. ROUTES EXPIRE — each staged route carries a deadline; stale quotes can't execute.
///
///         The keeper stages one route per (token, cycle) via `stageRoute`; `BasketBuyer`
///         consumes it during `purchaseBasket`. Staging is keeper-gated but staging a bad
///         route only causes a revert — funds never move on staging.
contract RouteAdapter is Ownable, ReentrancyGuard, ILiquidityAdapter {
    using SafeERC20 for IERC20;

    struct Route {
        address router;
        bytes callData;
        uint64 deadline;
    }

    IERC20 public immutable WETH;
    address public buyer; // set-once: the only address allowed to execute (D031)
    mapping(address => bool) public routerAllowed;
    mapping(address => bool) public keeperAllowed;
    mapping(address => Route) internal _staged; // tokenOut => staged route

    event RouterAllowed(address indexed router, bool allowed);
    event KeeperAllowed(address indexed keeper, bool allowed);
    event BuyerSet(address indexed buyer);
    event RouteStaged(address indexed tokenOut, address indexed router, uint64 deadline, bytes32 callDataHash);
    event RouteExecuted(address indexed tokenOut, address indexed router, uint256 wethIn, uint256 amountOut);

    error NotBuyer();
    error NotKeeper();
    error AlreadySet();
    error ZeroAddress();
    error RouterNotAllowed();
    error NoRoute();
    error RouteExpired();
    error RouteFailed();
    error InsufficientOut();

    constructor(address initialOwner, IERC20 weth) Ownable(initialOwner) {
        WETH = weth;
    }

    // ------------------------------------------------------------------ wiring

    function setBuyer(address buyer_) external onlyOwner {
        if (buyer_ == address(0)) revert ZeroAddress();
        if (buyer != address(0)) revert AlreadySet();
        buyer = buyer_;
        emit BuyerSet(buyer_);
    }

    function setRouterAllowed(address router, bool allowed) external onlyOwner {
        if (router == address(0)) revert ZeroAddress();
        routerAllowed[router] = allowed;
        emit RouterAllowed(router, allowed);
    }

    function setKeeperAllowed(address keeper, bool allowed) external onlyOwner {
        if (keeper == address(0)) revert ZeroAddress();
        keeperAllowed[keeper] = allowed;
        emit KeeperAllowed(keeper, allowed);
    }

    // ------------------------------------------------------------------ staging

    /// @notice Stage the route for `tokenOut` for the upcoming purchase cycle. Overwrites any
    ///         previous staging for the token. No funds move here.
    function stageRoute(address tokenOut, address router, bytes calldata callData, uint64 deadline) external {
        if (!keeperAllowed[msg.sender]) revert NotKeeper();
        if (!routerAllowed[router]) revert RouterNotAllowed();
        _staged[tokenOut] = Route(router, callData, deadline);
        emit RouteStaged(tokenOut, router, deadline, keccak256(callData));
    }

    function stagedRoute(address tokenOut) external view returns (address router, bytes32 callDataHash, uint64 deadline) {
        Route storage r = _staged[tokenOut];
        return (r.router, keccak256(r.callData), r.deadline);
    }

    // ------------------------------------------------------------------ execution

    /// @inheritdoc ILiquidityAdapter
    /// @dev Only the wired BasketBuyer may execute. The route's calldata must be built so the
    ///      router delivers `tokenOut` to `recipient` (the buyer); we verify by balance delta
    ///      and enforce the buyer's oracle-derived `minTokenOut` here as well.
    function swapExactWethForToken(IERC20 tokenOut, uint256 wethAmount, uint256 minTokenOut, address recipient)
        external
        nonReentrant
        returns (uint256 amountOut)
    {
        if (msg.sender != buyer) revert NotBuyer();
        Route memory r = _staged[address(tokenOut)];
        if (r.router == address(0)) revert NoRoute();
        if (block.timestamp > r.deadline) revert RouteExpired();
        if (!routerAllowed[r.router]) revert RouterNotAllowed();
        // one-shot: consume the staging so a route can never be replayed across cycles
        delete _staged[address(tokenOut)];

        uint256 outBefore = tokenOut.balanceOf(recipient);

        WETH.safeTransferFrom(msg.sender, address(this), wethAmount);
        WETH.forceApprove(r.router, wethAmount);
        (bool ok,) = r.router.call(r.callData);
        if (!ok) revert RouteFailed();
        WETH.forceApprove(r.router, 0);

        amountOut = tokenOut.balanceOf(recipient) - outBefore;
        if (amountOut < minTokenOut) revert InsufficientOut();

        // Any WETH the route didn't consume goes back to the buyer (it enforces zero leftover).
        uint256 dust = WETH.balanceOf(address(this));
        if (dust > 0) WETH.safeTransfer(msg.sender, dust);

        emit RouteExecuted(address(tokenOut), r.router, wethAmount, amountOut);
    }
}
