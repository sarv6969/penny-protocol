// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IOracleSource} from "./IOracleSource.sol";

/// @notice Fail-closed price guard for the basket rail. Wraps an IOracleSource and adds a
/// staffed market-session gate with a bounded session lifetime.
/// @dev D009: Robinhood Chain has NO documented Chainlink L2 sequencer uptime proxy. Until an
/// approved mechanism exists (sequencer feed OR a monitored staffed policy), the rail stays
/// closed: sessions default closed, only MARKET_APPROVER_ROLE can open one, and every open
/// session EXPIRES after `sessionTtl` so a forgotten flag can never hold the rail open through
/// market closure. The sequencer feed slot is reserved and stays address(0).
contract OracleGuard is AccessControl {
    bytes32 public constant MARKET_APPROVER_ROLE = keccak256("MARKET_APPROVER_ROLE");
    uint64 public constant MAX_SESSION_TTL = 24 hours;

    IOracleSource public immutable source;
    address public immutable WETH;

    uint64 public sessionTtl;
    uint64 public sessionOpenedAt; // 0 = closed
    address public sequencerUptimeFeed; // reserved; address(0) on Robinhood Chain (D009)

    error MarketClosed();
    error OracleFailClosed();
    error ZeroPrice();
    error ZeroAddress();
    error BadTtl();

    event MarketSessionChanged(bool open, uint64 openedAt, uint64 expiresAt, address setter);
    event SessionTtlChanged(uint64 ttl);

    constructor(address admin, IOracleSource source_, address weth) {
        if (address(source_) == address(0) || weth == address(0)) revert ZeroAddress();
        source = source_;
        WETH = weth;
        sessionTtl = 8 hours;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function setSessionTtl(uint64 ttl) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (ttl == 0 || ttl > MAX_SESSION_TTL) revert BadTtl();
        sessionTtl = ttl;
        emit SessionTtlChanged(ttl);
    }

    function setMarketOpen(bool open) external onlyRole(MARKET_APPROVER_ROLE) {
        if (open) {
            sessionOpenedAt = uint64(block.timestamp);
            emit MarketSessionChanged(true, sessionOpenedAt, sessionOpenedAt + sessionTtl, msg.sender);
        } else {
            sessionOpenedAt = 0;
            emit MarketSessionChanged(false, 0, 0, msg.sender);
        }
    }

    function marketOpen() public view returns (bool) {
        uint64 openedAt = sessionOpenedAt;
        return openedAt != 0 && block.timestamp <= openedAt + sessionTtl;
    }

    /// @dev Reserved for when Robinhood Chain publishes a sequencer feed. Not used today (D009).
    function setSequencerUptimeFeed(address feed) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (feed == address(0)) revert ZeroAddress();
        sequencerUptimeFeed = feed;
    }

    function getPriceWad(address token) public view returns (uint256) {
        _requireSession();
        _requireLive(token);
        uint256 price = source.priceOf(token);
        if (price == 0) revert ZeroPrice();
        return price;
    }

    function getWethPriceWad() external view returns (uint256) {
        return getPriceWad(WETH);
    }

    function _requireSession() internal view {
        if (!marketOpen()) revert MarketClosed();
    }

    function _requireLive(address token) internal view {
        if (!source.isLive(token)) revert OracleFailClosed();
    }
}
