// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IOracleSource} from "../../src/basket/IOracleSource.sol";

/// @notice Test-only price source. Prices are 18-decimal USD per whole token.
contract MockOracle is IOracleSource {
    mapping(address => uint256) public prices;
    mapping(address => bool) public live;

    function register(address token, uint256 priceWad, bool isLive_) external {
        prices[token] = priceWad;
        live[token] = isLive_;
    }

    function setPrice(address token, uint256 priceWad) external {
        prices[token] = priceWad;
    }

    function setLive(address token, bool isLive_) external {
        live[token] = isLive_;
    }

    function priceOf(address token) external view returns (uint256) {
        return prices[token];
    }

    function isLive(address token) external view returns (bool) {
        return live[token];
    }
}
