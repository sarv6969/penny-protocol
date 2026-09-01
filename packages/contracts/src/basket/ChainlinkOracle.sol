// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IOracleSource} from "./IOracleSource.sol";

/// @notice Chainlink AggregatorV3 proxy surface (only what we consume).
interface IAggregatorV3 {
    function decimals() external view returns (uint8);
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

/// @notice ERC-8056 corporate-action surface (only what we consume).
interface IStockTokenPause {
    function oraclePaused() external view returns (bool);
}

/// @title ChainlinkOracle — production IOracleSource over official Robinhood equity feeds (D036)
/// @notice Prices are Chainlink Total Return Values: the feed already bakes in `uiMultiplier()`
///         (dividends/splits) so we NEVER multiply again (D008). Fail-closed liveness:
///         - unknown token → not live
///         - stale beyond the per-feed staleness bound → not live
///         - non-positive answer or unfinished round → not live
///         - Stock Token `oraclePaused()` (corporate action window) → not live
///         Robinhood feeds are 24/5 with a 24h heartbeat; equities hold the last value through
///         closed sessions, so the staleness bound must span weekends for stocks. The staffed
///         market-session gate in OracleGuard (D009) remains the first line; this bound is the
///         second.
contract ChainlinkOracle is Ownable, IOracleSource {
    struct FeedConfig {
        IAggregatorV3 feed;
        uint48 stalenessBound; // seconds; 0 = unset (not live)
        bool checkOraclePaused; // true for ERC-8056 Stock Tokens, false for WETH/ETH
    }

    mapping(address => FeedConfig) public feeds;

    event FeedSet(address indexed token, address indexed feed, uint48 stalenessBound, bool checkOraclePaused);

    error ZeroAddress();
    error BadBound();

    constructor(address initialOwner) Ownable(initialOwner) {}

    /// @notice Register/replace the feed for a token. Owner-gated; on mainnet the owner is the
    ///         timelocked governance Safe, and every feed must match the verified manifest.
    function setFeed(address token, IAggregatorV3 feed, uint48 stalenessBound, bool checkOraclePaused) external onlyOwner {
        if (token == address(0) || address(feed) == address(0)) revert ZeroAddress();
        if (stalenessBound == 0) revert BadBound();
        feeds[token] = FeedConfig(feed, stalenessBound, checkOraclePaused);
        emit FeedSet(token, address(feed), stalenessBound, checkOraclePaused);
    }

    /// @inheritdoc IOracleSource
    /// @dev Returns the price normalized to 18-decimal USD per whole token. Callers must gate on
    ///      `isLive` first (OracleGuard does); this function still never returns junk for a dead
    ///      feed — it reverts on zero-config and returns 0 for non-positive answers, which the
    ///      guard rejects as ZeroPrice.
    function priceOf(address token) external view returns (uint256 priceWad) {
        FeedConfig memory cfg = feeds[token];
        if (address(cfg.feed) == address(0)) return 0;
        (, int256 answer,,,) = cfg.feed.latestRoundData();
        if (answer <= 0) return 0;
        uint8 dec = cfg.feed.decimals();
        if (dec <= 18) {
            return uint256(answer) * 10 ** (18 - dec);
        }
        return uint256(answer) / 10 ** (dec - 18);
    }

    /// @inheritdoc IOracleSource
    function isLive(address token) external view returns (bool) {
        FeedConfig memory cfg = feeds[token];
        if (address(cfg.feed) == address(0) || cfg.stalenessBound == 0) return false;

        (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) = _tryRound(cfg.feed);
        if (answer <= 0) return false;
        if (updatedAt == 0 || block.timestamp > updatedAt + cfg.stalenessBound) return false;
        if (answeredInRound < roundId) return false;

        if (cfg.checkOraclePaused) {
            (bool ok, bytes memory ret) = token.staticcall(abi.encodeCall(IStockTokenPause.oraclePaused, ()));
            if (!ok || ret.length != 32) return false;
            if (abi.decode(ret, (bool))) return false;
        }
        return true;
    }

    function _tryRound(IAggregatorV3 feed) private view returns (uint80, int256, uint256, uint256, uint80) {
        try feed.latestRoundData() returns (uint80 rid, int256 ans, uint256 st, uint256 up, uint80 air) {
            return (rid, ans, st, up, air);
        } catch {
            return (0, 0, 0, 0, 0);
        }
    }
}
