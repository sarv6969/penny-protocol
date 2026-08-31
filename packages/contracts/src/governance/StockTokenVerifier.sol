// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IStockTokenVerifier} from "./IStockTokenVerifier.sol";

interface IERC8056StockToken {
    function uiMultiplier() external view returns (uint256);

    function oraclePaused() external view returns (bool);
}

/// @notice Lightweight canonical Stock Token verifier used as a governance hook.
///         Confirms deployed bytecode and the ERC-8056 surface (`uiMultiplier`,
///         `oraclePaused`) plus 18 decimals. Governed by an owner role for future
///         hardening; its verdict gates admissions, never user funds.
contract StockTokenVerifier is IStockTokenVerifier {
    address public owner;

    error NotOwner();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address owner_) {
        owner = owner_;
    }

    function setOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "VERIFIER: zero owner");
        owner = newOwner;
    }

    function isVerifiedCanonicalToken(address token) public view returns (bool) {
        if (token.code.length == 0) return false;
        (bool decOk, bytes memory dec) = token.staticcall(abi.encodeCall(IERC20Metadata.decimals, ()));
        if (!decOk || dec.length != 32) return false;
        if (uint256(bytes32(dec)) != 18) return false;

        (bool uiOk,) = token.staticcall(abi.encodeCall(IERC8056StockToken.uiMultiplier, ()));
        if (!uiOk) return false;

        (bool pauseOk,) = token.staticcall(abi.encodeCall(IERC8056StockToken.oraclePaused, ()));
        return pauseOk;
    }
}
