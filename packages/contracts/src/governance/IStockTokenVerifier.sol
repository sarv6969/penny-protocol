// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IStockTokenVerifier {
    function isVerifiedCanonicalToken(address token) external view returns (bool);
}
